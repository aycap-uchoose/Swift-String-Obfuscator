//
//  CommentSampleAppCommand.swift
//  SwiftStringObfuscator
//
//  Created by Podsirin Vanichvarodom on 19/2/2569 BE.
//
import ArgumentParser
import Foundation

struct DeleteSampleAppCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "delete-sample-app",
        abstract: "Delete function bodies and lazy vars in SampleAppCoordinator.swift files, keeping override func intact."
    )

    @Argument(help: "Root directory to search for SampleAppCoordinator.swift (default: current directory)")
    var searchDir: String = "."

    @Flag(name: .long, help: "Preview changes without modifying any files.")
    var dryRun: Bool = false

    mutating func run() throws {
        let files = FileFinder(root: searchDir, filename: "SampleAppCoordinator.swift").find()

        guard !files.isEmpty else {
            print("❌  ไม่พบไฟล์ SampleAppCoordinator.swift ใน: \(searchDir)")
            throw ExitCode.failure
        }

        print("🔍  พบไฟล์ทั้งหมด \(files.count) ไฟล์:")
        files.forEach { print("    • \($0)") }
        print("")

        var success = 0
        var failed = 0

        for path in files {
            print("⚙️   กำลังประมวลผล: \(path)")
            do {
                let original = try String(contentsOfFile: path, encoding: .utf8)
                let result = CoordinatorDeleter(source: original).process()

                if dryRun {
                    print(String(repeating: "─", count: 50))
                    print(result)
                    print(String(repeating: "─", count: 50) + "\n")
                } else {
                    try original.write(toFile: path + ".bak", atomically: true, encoding: .utf8)
                    try result.write(toFile: path, atomically: true, encoding: .utf8)
                    print("    ✅  แก้ไขแล้ว  |  backup → \(path).bak")
                    success += 1
                }
            } catch {
                print("    ❌  เกิดข้อผิดพลาด: \(error.localizedDescription)")
                failed += 1
            }
        }

        print("")
        if dryRun {
            print("📋  Dry-run เสร็จสิ้น (ไม่มีไฟล์ถูกแก้ไข)")
        } else {
            let failMsg = failed > 0 ? " | ผิดพลาด \(failed) ไฟล์" : ""
            print("🎉  เสร็จสิ้น! แก้ไขแล้ว \(success) ไฟล์\(failMsg)")
        }
    }
}

// MARK: - File Finder

private struct FileFinder {
    let root: String
    let filename: String

    func find() -> [String] {
        guard let enumerator = FileManager.default.enumerator(
            at: URL(fileURLWithPath: root),
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        return (enumerator.compactMap { $0 as? URL })
            .filter { $0.lastPathComponent == filename }
            .map { $0.path }
            .sorted()
    }
}

// MARK: - Deleter Logic

struct CoordinatorDeleter {
    let source: String

    func process() -> String {
        let lines = source.components(separatedBy: "\n")
        var result: [String] = []
        var braceDepth = 0

        var funcBodyStack: [Int] = []

        var inLazyClosureDelete = false
        var lazyClosureBraceDepth = 0

        var inLazyParenDelete = false
        var lazyParenDepth = 0

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let (opens, closes) = countBraces(in: line)

            if inLazyClosureDelete {
                lazyClosureBraceDepth += opens - closes
                if lazyClosureBraceDepth <= 0 { inLazyClosureDelete = false }
                continue
            }

            if inLazyParenDelete {
                lazyParenDepth += line.filter { $0 == "(" }.count
                lazyParenDepth -= line.filter { $0 == ")" }.count
                if lazyParenDepth <= 0 { inLazyParenDelete = false }
                continue
            }

            if !funcBodyStack.isEmpty && braceDepth > funcBodyStack.last! {
                let newDepth = braceDepth + opens - closes
                let willClose = newDepth <= funcBodyStack.last!
                if willClose { funcBodyStack.removeLast() }

                braceDepth = newDepth

                if willClose && trimmed == "}" {
                    result.append(line)
                }
                continue
            }

            if isLazyVar(trimmed) {
                if isLazyClosureStyle(trimmed) {
                    let netBraces = opens - closes
                    if netBraces > 0 {
                        inLazyClosureDelete = true
                        lazyClosureBraceDepth = netBraces
                    }
                } else {
                    let paren = line.filter { $0 == "(" }.count - line.filter { $0 == ")" }.count
                    if paren > 0 { inLazyParenDelete = true; lazyParenDepth = paren }
                }
                continue
            }

            let depthBefore = braceDepth
            result.append(line)
            braceDepth += opens - closes

            if isFuncDecl(trimmed) && !isOverride(trimmed) && opens > 0 && funcBodyStack.isEmpty {
                funcBodyStack.append(depthBefore + opens - 1)
            }
        }

        return result.joined(separator: "\n")
    }

    // MARK: - Helpers

    private func countBraces(in line: String) -> (Int, Int) {
        var opens = 0, closes = 0
        var inString = false
        var index = line.startIndex

        while index < line.endIndex {
            let c = line[index]
            let next = line.index(after: index)

            if inString {
                if c == "\\" && next < line.endIndex { index = line.index(after: next); continue }
                if c == "\"" { inString = false }
            } else {
                if c == "\"" { inString = true }
                else if c == "/" && next < line.endIndex && line[next] == "/" { break }
                else if c == "{" { opens += 1 }
                else if c == "}" { closes += 1 }
            }
            index = next
        }
        return (opens, closes)
    }

    private func isLazyVar(_ s: String) -> Bool {
        s.range(of: #"^(private\s+|internal\s+|public\s+|fileprivate\s+)?lazy\s+var\s+"#,
                options: .regularExpression) != nil
    }

    private func isLazyClosureStyle(_ s: String) -> Bool {
        s.range(of: #"=\s*\{"#, options: .regularExpression) != nil
    }

    private func isFuncDecl(_ s: String) -> Bool {
        s.range(of: #"\b(func|init|deinit)\b"#, options: .regularExpression) != nil
    }

    private func isOverride(_ s: String) -> Bool {
        s.range(of: #"\boverride\b"#, options: .regularExpression) != nil
    }
}
