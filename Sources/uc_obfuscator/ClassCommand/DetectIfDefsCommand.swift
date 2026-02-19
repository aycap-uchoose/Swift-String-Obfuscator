//
//  DetectTagIfCommand.swift
//  SwiftStringObfuscator
//
//  Created by Podsirin Vanichvarodom on 19/2/2569 BE.
//

import ArgumentParser
import Foundation

struct DetectIfDefsCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "class-detect-ifdefs",
        abstract: "Scan Swift files for functions and variables used inside #if/#endif blocks"
    )
    
    @Argument(
        help: "Directory to search for Swift files",
        completion: .directory
    )
    var directory: String = "."
    
    @Option(
        name: [.short, .long],
        help: "Output file path"
    )
    var output: String = "swift_conditionals_report.txt"
    
    func run() throws {
        let (functions, variables) = processSwiftFiles(in: directory)
        
        // Write results
        var output = ""
        
        for funcName in functions.sorted() {
            output += "Function call : \(funcName)\n"
        }
        
        for varName in variables.sorted() {
            output += "Variable used : \(varName)\n"
        }
        
        try output.write(toFile: self.output, atomically: true, encoding: .utf8)
        print("Done! Results saved to: \(self.output)")
    }
    
    // MARK: - Helper Functions
    
    private let swiftKeywords = Set([
        "if", "for", "while", "guard", "switch", "catch", "return", "throw",
        "init", "super", "self", "defer", "print", "fatalError", "assert",
        "precondition", "type", "where"
    ])
    
    private func extractIdentifiers(from blockText: String) -> (functions: [String], variables: [String]) {
        var functions: [String] = []
        var variables: [String] = []
        
        let lines = blockText.components(separatedBy: .newlines)
        
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            
            // Skip compiler directives
            if trimmed.hasPrefix("#if") || trimmed.hasPrefix("#elseif") ||
               trimmed.hasPrefix("#else") || trimmed.hasPrefix("#endif") {
                continue
            }
            
            // Skip comment lines
            if trimmed.hasPrefix("//") {
                continue
            }
            
            // Extract function calls (identifier followed by optional '?' and '(')
            let pattern = #"[a-zA-Z_][a-zA-Z0-9_]*\s*\?*\s*\("#
            if let regex = try? NSRegularExpression(pattern: pattern) {
                let range = NSRange(line.startIndex..., in: line)
                let matches = regex.matches(in: line, range: range)
                
                for match in matches {
                    if let range = Range(match.range, in: line) {
                        let matchText = String(line[range])
                        let funcName = matchText.replacingOccurrences(of: #"\s*\?*\s*\("#, with: "", options: .regularExpression)
                        if !swiftKeywords.contains(funcName) {
                            functions.append(funcName)
                        }
                    }
                }
            }
            
            // Extract variables (left side of assignment, not declarations)
            if !trimmed.hasPrefix("var ") && !trimmed.hasPrefix("let ") &&
               !trimmed.hasPrefix("func ") && !trimmed.hasPrefix("class ") &&
               !trimmed.hasPrefix("struct ") && !trimmed.hasPrefix("enum ") &&
               !trimmed.hasPrefix("typealias ") && !trimmed.hasPrefix("import ") &&
               !trimmed.hasPrefix("@") {
                
                // Match: identifier = (not ==)
                let assignPattern = #"^\s*([a-zA-Z_][a-zA-Z0-9_.]*)\s*=[^=]"#
                if let regex = try? NSRegularExpression(pattern: assignPattern) {
                    let range = NSRange(line.startIndex..., in: line)
                    if let match = regex.firstMatch(in: line, range: range),
                       let matchRange = Range(match.range(at: 1), in: line) {
                        let lhs = String(line[matchRange])
                        let root = lhs.components(separatedBy: ".").first ?? ""
                        if !root.isEmpty && !swiftKeywords.contains(root) {
                            variables.append(root)
                        }
                    }
                }
            }
            
            // Extract property access: something.propertyName
            let propPattern = #"[a-zA-Z_][a-zA-Z0-9_]*\.[a-zA-Z_][a-zA-Z0-9_]+"#
            if let regex = try? NSRegularExpression(pattern: propPattern) {
                let range = NSRange(line.startIndex..., in: line)
                let matches = regex.matches(in: line, range: range)
                
                for match in matches {
                    if let range = Range(match.range, in: line) {
                        let propAccess = String(line[range])
                        // Extract property name (after the last dot)
                        let parts = propAccess.components(separatedBy: ".")
                        if let propName = parts.last,
                           !swiftKeywords.contains(propName),
                           !["shared", "main", "self", "Type"].contains(propName) {
                            variables.append(propName)
                        }
                    }
                }
            }
        }
        
        return (functions, variables)
    }
    
    private func processSwiftFiles(in directory: String) -> (functions: Set<String>, variables: Set<String>) {
        var allFunctions = Set<String>()
        var allVariables = Set<String>()
        
        let fileManager = FileManager.default
        
        guard let enumerator = fileManager.enumerator(atPath: directory) else {
            Self.stderr("Error: Cannot access directory \(directory)")
            return (allFunctions, allVariables)
        }
        
        let swiftFiles = enumerator.compactMap { item -> String? in
            guard let path = item as? String, path.hasSuffix(".swift") else { return nil }
            return (directory as NSString).appendingPathComponent(path)
        }.sorted()
        
        for filePath in swiftFiles {
            guard let content = try? String(contentsOfFile: filePath, encoding: .utf8) else {
                continue
            }
            
            let lines = content.components(separatedBy: .newlines)
            
            // Quick check for #if
            guard lines.contains(where: { $0.trimmingCharacters(in: .whitespaces).hasPrefix("#if") }) else {
                continue
            }
            
            Self.stderr("Scanning: \(filePath)")
            
            var depth = 0
            var blockLines = ""
            
            for line in lines {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                
                if trimmed.hasPrefix("#if") {
                    if depth == 0 {
                        blockLines = line
                    } else {
                        blockLines += "\n" + line
                    }
                    depth += 1
                } else if trimmed.hasPrefix("#endif") {
                    depth -= 1
                    if depth == 0 {
                        blockLines += "\n" + line
                        
                        // Process the block
                        let (functions, variables) = extractIdentifiers(from: blockLines)
                        allFunctions.formUnion(functions)
                        allVariables.formUnion(variables)
                        
                        blockLines = ""
                    } else {
                        blockLines += "\n" + line
                    }
                } else if depth > 0 {
                    blockLines += "\n" + line
                }
            }
        }
        
        return (allFunctions, allVariables)
    }
    
    private static func stderr(_ message: String) {
        fputs("\(message)\n", Darwin.stderr)
    }
}
