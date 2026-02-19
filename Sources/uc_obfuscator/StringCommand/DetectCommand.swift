import Foundation
import ArgumentParser
import SwiftSyntax
import SwiftParser

struct DetectCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "string-detect",
        abstract: "Detect string literals and add //:obfuscate comments before them."
    )
    
    @Argument(help: "Directory path to scan for .swift files.")
    var focusDirectory: String
    
    @Flag(name: .shortAndLong, help: "Perform a dry run without modifying files.")
    var dryRun: Bool = false
    
    mutating func run() throws {
        let sourcePath = URL(fileURLWithPath: focusDirectory)
        
        let fileManager = FileManager.default
        var isDirectory: ObjCBool = false
        
        guard fileManager.fileExists(
            atPath: sourcePath.path,
            isDirectory: &isDirectory
        ) else {
            print("❌ Error: Directory '\(focusDirectory)' does not exist")
            throw ExitCode.failure
        }
        
        guard isDirectory.boolValue else {
            print("❌ Error: '\(focusDirectory)' is not a directory")
            throw ExitCode.failure
        }
        
        try processDirectory(sourceDir: sourcePath)
    }
    
    private func processDirectory(sourceDir: URL) throws {
        print("🔍 Scanning for .swift files in: \(sourceDir.path)")
        if dryRun {
            print("🔎 DRY RUN MODE - No files will be modified")
        } else {
            print("⚠️  Files will be modified IN PLACE (adding //:obfuscate comments)")
        }
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        
        let swiftFiles = findSwiftFiles(in: sourceDir)
        
        guard !swiftFiles.isEmpty else {
            print("⚠️  No .swift files found in directory")
            return
        }
        
        print("📊 Found \(swiftFiles.count) .swift file(s)")
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n")
        
        var modifiedCount = 0
        var skippedCount = 0
        var failCount = 0
        var totalLinesAdded = 0
        
        for (index, sourceFile) in swiftFiles.enumerated() {
            let relativePath = sourceFile.path.replacingOccurrences(
                of: sourceDir.path + "/",
                with: ""
            )
            
            do {
                let result = try processFile(at: sourceFile, dryRun: dryRun)
                
                if result.modified {
                    print("[\(index + 1)/\(swiftFiles.count)] Processing: \(relativePath)")
                    if dryRun {
                        print("   🔎 Would add \(result.linesAdded) //:obfuscate comment(s)")
                    } else {
                        print("   ✅ Added \(result.linesAdded) //:obfuscate comment(s)")
                    }
                    modifiedCount += 1
                    totalLinesAdded += result.linesAdded
                } else {
                    skippedCount += 1
                }
            } catch {
                print("   ❌ Failed: \(error.localizedDescription)")
                failCount += 1
            }
        }
        
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        print("📊 Summary:")
        print("   Total files: \(swiftFiles.count)")
        if dryRun {
            print("   🔎 Would modify: \(modifiedCount)")
        } else {
            print("   ✅ Modified: \(modifiedCount)")
        }
        print("   ⏭️  Skipped: \(skippedCount)")
        if failCount > 0 {
            print("   ❌ Failed: \(failCount)")
        }
        print("   📝 Total //:obfuscate comments added: \(totalLinesAdded)")
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
    }
    
    private func findSwiftFiles(in directory: URL) -> [URL] {
        let fileManager = FileManager.default
        var swiftFiles: [URL] = []
        
        
        
        guard let enumerator = fileManager.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }
        
        for case let fileURL as URL in enumerator {
            let relativePath = fileURL.path.replacingOccurrences(
                of: directory.path + "/",
                with: ""
            )
            
            let pathComponents = fileURL.pathComponents
            var hasExcludedFolder = false
            
            hasExcludedFolder = pathComponents.contains { component in
                if IgnoreFormat.excludedFolders.contains(component) {
                    return true
                }
                if IgnoreFormat.excludedFolderSuffixes.contains(where: { component.hasSuffix($0) }) {
                    return true
                }
                return false
            }
            
            if !hasExcludedFolder {
                hasExcludedFolder = IgnoreFormat.excludedFolders.contains { excludedPath in
                    excludedPath.contains("/") && relativePath.hasPrefix(excludedPath)
                }
            }
            
            if hasExcludedFolder {
                if let resourceValues = try? fileURL.resourceValues(forKeys: [.isDirectoryKey]),
                   resourceValues.isDirectory == true {
                    enumerator.skipDescendants()
                }
                continue
            }
            
            guard fileURL.pathExtension == "swift" else {
                continue
            }
            
            let fileName = fileURL.lastPathComponent
            
            if IgnoreFormat.excludedFiles.contains(fileName) {
                continue
            }
            
            if IgnoreFormat.excludedSuffixes.contains(where: { fileName.hasSuffix($0) }) {
                continue
            }
            
            if let resourceValues = try? fileURL.resourceValues(forKeys: [.isRegularFileKey]),
               resourceValues.isRegularFile == true {
                swiftFiles.append(fileURL)
            }
        }
        
        
        return swiftFiles.sorted { $0.path < $1.path }
    }
    
    private func processFile(at fileURL: URL, dryRun: Bool) throws -> (modified: Bool, linesAdded: Int) {
        let content = try String(contentsOf: fileURL, encoding: .utf8)
        let sourceFile = Parser.parse(source: content)
        
        let detector = StringLiteralDetector(sourceLocationConverter: SourceLocationConverter(file: fileURL.path, tree: sourceFile))
        detector.walk(sourceFile)
        detector.finalizeLinesToObfuscate()
        
        let linesToAddObfuscate = detector.linesToObfuscate
        
        guard !linesToAddObfuscate.isEmpty else {
            return (modified: false, linesAdded: 0)
        }
        
        let lines = content.components(separatedBy: .newlines)
        var modifiedLines: [String] = []
        var linesAdded = 0
        
        for (index, line) in lines.enumerated() {
            let lineNumber = index + 1
            
            // ตรวจสอบบรรทัดก่อนหน้า (จาก original lines)
            let previousLine = index > 0 ? lines[index - 1].trimmingCharacters(in: .whitespaces) : ""
            let previousLineHasIgnore = previousLine == "//:ignoreobfuscate"
            let previousLineHasObfuscate = previousLine == "//:obfuscate"
            
            let shouldExclude = IgnoreFormat.excludePatterns.contains { pattern in
                line.contains(pattern)
            }
            
            // ถ้ามี //:ignoreobfuscate ให้ข้าม
            if previousLineHasIgnore || shouldExclude {
                modifiedLines.append(line)
                continue
            }
            
            // ตรวจสอบว่าบรรทัดนี้ต้องการ obfuscate หรือไม่
            if linesToAddObfuscate.contains(lineNumber) {
                // เพิ่ม //:obfuscate เพียง 1 บรรทัด (ไม่ว่าจะมีกี่ string)
                // ถ้ายังไม่มี comment อยู่แล้ว
                if !previousLineHasObfuscate {
                    modifiedLines.append("//:obfuscate")
                    linesAdded += 1
                }
            }
            
            modifiedLines.append(line)
        }
        
        let modified = linesAdded > 0
        
        if modified && !dryRun {
            let newContent = modifiedLines.joined(separator: "\n")
            try newContent.write(to: fileURL, atomically: true, encoding: .utf8)
        }
        
        return (modified: modified, linesAdded: linesAdded)
    }
}

// MARK: - SwiftSyntax Visitor

class StringLiteralDetector: SyntaxVisitor {
    var linesToObfuscate: Set<Int> = []
    private let converter: SourceLocationConverter
    private var linesWithInterpolation: Set<Int> = []
    private var enumCaseLines: Set<Int> = []
    private var stringCountPerLine: [Int: Int] = [:]
    private var debugInfo: [(line: Int, string: String, reason: String)] = []
    
    init(sourceLocationConverter: SourceLocationConverter) {
        self.converter = sourceLocationConverter
        super.init(viewMode: .sourceAccurate)
    }
    
    override func visit(_ node: EnumCaseDeclSyntax) -> SyntaxVisitorContinueKind {
        let location = converter.location(for: node.positionAfterSkippingLeadingTrivia)
        if let lineNumber = location.line {
            enumCaseLines.insert(lineNumber)
        }
        return .visitChildren
    }
    
    override func visit(_ node: SubscriptExprSyntax) -> SyntaxVisitorContinueKind {
        let location = converter.location(for: node.positionAfterSkippingLeadingTrivia)
        if let lineNumber = location.line {
            debugInfo.append((line: lineNumber, string: "SUBSCRIPT: \(node)", reason: "subscript expression detected"))
        }
        return .visitChildren
    }
    
    override func visit(_ node: DictionaryElementSyntax) -> SyntaxVisitorContinueKind {
        let location = converter.location(for: node.positionAfterSkippingLeadingTrivia)
        if let lineNumber = location.line {
            debugInfo.append((line: lineNumber, string: "DICT ELEMENT: \(node)", reason: "dictionary element detected"))
        }
        return .visitChildren
    }
    
    override func visit(_ node: StringLiteralExprSyntax) -> SyntaxVisitorContinueKind {
        let location = converter.location(for: node.positionAfterSkippingLeadingTrivia)
        guard let lineNumber = location.line else {
            debugInfo.append((line: 0, string: "\(node.segments)", reason: "❌ NO LINE NUMBER"))
            return .visitChildren
        }
        
        stringCountPerLine[lineNumber, default: 0] += 1
        
        let hasInterpolation = node.segments.contains { segment in
            segment.is(ExpressionSegmentSyntax.self)
        }
        
        let isEmpty = node.segments.isEmpty ||
                      (node.segments.count == 1 &&
                       node.segments.first?.as(StringSegmentSyntax.self)?.content.text.isEmpty == true)
        
        let stringValue = "\(node.segments)"
        
        if hasInterpolation {
            linesWithInterpolation.insert(lineNumber)
            debugInfo.append((line: lineNumber, string: stringValue, reason: "has interpolation"))
        } else if isEmpty {
            debugInfo.append((line: lineNumber, string: stringValue, reason: "is empty"))
        } else {
            let isInEnumCase = enumCaseLines.contains(lineNumber)
            
            if isInEnumCase {
                debugInfo.append((line: lineNumber, string: stringValue, reason: "in enum case"))
            } else {
                linesToObfuscate.insert(lineNumber)
                debugInfo.append((line: lineNumber, string: stringValue, reason: "✅ WILL OBFUSCATE"))
            }
        }
        
        return .visitChildren
    }
    
    func finalizeLinesToObfuscate() {
        linesToObfuscate.subtract(linesWithInterpolation)
    }
    
    func getStringCount(for line: Int) -> Int {
        return stringCountPerLine[line] ?? 0
    }
    
    func printDebugInfo(fileName: String) {
        guard !debugInfo.isEmpty else { return }
        
        print("\n📄 File: \(fileName)")
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        for info in debugInfo.sorted(by: { $0.line < $1.line }) {
            print("Line \(info.line): \(info.reason)")
            if !info.string.contains("SUBSCRIPT") && !info.string.contains("DICT") {
                print("         → \"\(info.string)\"")
            }
        }
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n")
    }
}

struct IgnoreFormat {
    static let excludedFiles = [
        "Package.swift",
        "IconName.swift",
        "ImageNames.swift",
        "AppIcon.swift",
        "DataCategory+SeasonalAppIcon.swift",
        "UCLanguageType.swift",
        "AppConstant.swift",
        "Constants.swift",
        "JailbreakChecker.swift"
    ]
    
    static let excludedSuffixes = [
        "Tests.swift",
        "Test.swift"
    ]
    
    static let excludedFolders = [
        "script",
        ".build",
        "DerivedData",
        "UChooseTests",
        "AYCAnalyticSdk",
        "UCSpy",
        "UCFactory",
        "UCFoundationInterface",
        "UCEntity",
        "UCCoreInterface/DeepLink"
    ]
    
    static let excludedFolderSuffixes = [
        "Tests",
        "Sample"
    ]
    
    static let excludePatterns = [
        ".replacingOccurrences(of:",
        ".contains(",
        ".hasPrefix(",
        ".hasSuffix(",
        ".components(separatedBy:",
        ".split(separator:",
        ".firstIndex(of:"
    ]
}
