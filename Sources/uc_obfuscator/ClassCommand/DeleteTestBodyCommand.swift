//
//  DeleteTestBodyCommand.swift
//  SwiftStringObfuscator
//
//  Created by Podsirin Vanichvarodom on 19/2/2569 BE.
//

import ArgumentParser
import Foundation

struct DeleteTestsBodyCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "delete-tests-body",
        abstract: "Delete the body of struct XXXTests { } in XXXTests.swift files, leaving an empty struct."
    )

    @Argument(help: "Root directory to search for *Tests.swift files.")
    var searchDir: String = "."

    @Flag(name: .long, help: "Preview changes without modifying any files.")
    var dryRun: Bool = false

    mutating func run() throws {
        let files = FileFinder(root: searchDir).find()

        guard !files.isEmpty else {
            print("❌  ไม่พบไฟล์ *Tests.swift ใน: \(searchDir)")
            throw ExitCode.failure
        }

        print("🔍  พบไฟล์ทั้งหมด \(files.count) ไฟล์:")
        files.forEach { print("    • \($0)") }
        print("")

        var success = 0, skipped = 0, failed = 0

        for path in files {
            print("⚙️   กำลังประมวลผล: \(path)")
            do {
                let original = try String(contentsOfFile: path, encoding: .utf8)
                let processor = TestsBodyDeleter(source: original)
                let found = processor.foundStructNames()

                guard !found.isEmpty else {
                    print("    ⏭️   ไม่พบ struct/class ที่ลงท้ายด้วย Tests — ข้ามไฟล์นี้")
                    skipped += 1
                    continue
                }

                print("    🧪  พบ: \(found.joined(separator: ", "))")
                let result = processor.process()

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
            var summary = "🎉  เสร็จสิ้น! แก้ไขแล้ว \(success) ไฟล์"
            if skipped > 0 { summary += " | ข้าม \(skipped) ไฟล์" }
            if failed  > 0 { summary += " | ผิดพลาด \(failed) ไฟล์" }
            print(summary)
        }
    }
}

// MARK: - File Finder (ค้นหา *Tests.swift)

private struct FileFinder {
    let root: String

    func find() -> [String] {
        guard let enumerator = FileManager.default.enumerator(
            at: URL(fileURLWithPath: root),
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        return (enumerator.compactMap { $0 as? URL })
            .filter { $0.lastPathComponent.hasSuffix("Tests.swift") }
            .map { $0.path }
            .sorted()
    }
}

// MARK: - Tests Body Deleter

struct TestsBodyDeleter {
    let source: String

    /// คืนชื่อ struct/class ที่ลงท้ายด้วย Tests ทั้งหมดในไฟล์
    func foundStructNames() -> [String] {
        let pattern = #"\b(?:struct|class)\s+(\w+Tests)\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let ns = source as NSString
        return regex.matches(in: source, range: NSRange(source.startIndex..., in: source))
            .compactMap { match -> String? in
                guard match.numberOfRanges > 1 else { return nil }
                let range = match.range(at: 1)
                guard range.location != NSNotFound else { return nil }
                return ns.substring(with: range)
            }
    }

    /// ลบ body ของทุก struct/class ที่ลงท้ายด้วย Tests — คง declaration ไว้เป็น `XxxTests { }`
    func process() -> String {
        let lines = source.components(separatedBy: "\n")
        var result: [String] = []
        var braceDepth = 0

        // stack: (structStartDepth, isInsideTests)
        // ใช้ stack เพราะอาจมี nested type ข้างใน
        struct ScopeEntry { let startDepth: Int; let isTests: Bool }
        var scopeStack: [ScopeEntry] = []

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let (opens, closes) = countBraces(in: line)

            // ── ตรวจว่าเราอยู่ใน Tests scope ที่ต้องลบ body ──────────────
            let insideTests = scopeStack.last?.isTests == true
                           && braceDepth > scopeStack.last!.startDepth

            if insideTests {
                let newDepth = braceDepth + opens - closes
                let willClose = newDepth <= scopeStack.last!.startDepth

                if willClose {
                    scopeStack.removeLast()
                    braceDepth = newDepth
                    // closing `}` ของ Tests struct — ไม่ต้องใส่ เพราะใส่ `{}` ไปแล้วใน decl
                    continue
                }

                // ลบทุกบรรทัดข้างใน (รวม nested struct/class ที่ไม่ใช่ Tests)
                braceDepth = newDepth

                // ถ้ามี nested scope ต้อง push/pop ด้วยเพื่อให้ depth ถูกต้อง
                if opens > 0 { scopeStack.append(ScopeEntry(startDepth: braceDepth - closes + opens - 1, isTests: false)) }
                if !scopeStack.isEmpty && scopeStack.last!.isTests == false && newDepth <= scopeStack.last!.startDepth {
                    scopeStack.removeLast()
                }
                continue
            }

            // ── ตรวจว่าบรรทัดนี้เป็น struct/class XXXTests ──────────────
            if let name = testsTypeName(in: trimmed), opens > 0 {
                let declOnly = extractDeclaration(from: line)
                result.append(declOnly + " {}")
                let startDepth = braceDepth + opens - 1
                braceDepth += opens - closes
                scopeStack.append(ScopeEntry(startDepth: startDepth, isTests: true))
                continue
            }

            // ── บรรทัดปกติ ────────────────────────────────────────────────
            // track non-Tests scope เพื่อให้ depth ถูก
            if opens > 0 {
                scopeStack.append(ScopeEntry(startDepth: braceDepth + opens - 1, isTests: false))
            }
            result.append(line)
            braceDepth += opens - closes

            // pop non-Tests scope ที่ปิดแล้ว
            while let last = scopeStack.last, !last.isTests, braceDepth <= last.startDepth {
                scopeStack.removeLast()
            }
        }

        return result.joined(separator: "\n")
    }

    // MARK: Helpers

    /// คืนชื่อ type ถ้าบรรทัดนี้เป็น struct/class ที่ลงท้ายด้วย Tests
    private func testsTypeName(in line: String) -> String? {
        let pattern = #"\b(?:struct|class)\s+(\w+Tests)\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
              match.numberOfRanges > 1 else { return nil }
        let range = match.range(at: 1)
        guard range.location != NSNotFound,
              let swiftRange = Range(range, in: line) else { return nil }
        return String(line[swiftRange])
    }

    /// ดึงเฉพาะส่วน declaration ก่อน `{`  เช่น "    final class FooTests: XCTestCase"
    private func extractDeclaration(from line: String) -> String {
        guard let braceIdx = line.firstIndex(of: "{") else { return line }
        return String(line[line.startIndex..<braceIdx])
            .replacingOccurrences(of: #"\s+$"#, with: "", options: .regularExpression)
    }

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
}
