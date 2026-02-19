//
//  ObfuscateCommand.swift
//  SwiftStringObfuscator
//
//  Created by Podsirin Vanichvarodom on 11/2/2569 BE.
//

import ArgumentParser
import Foundation
import SwiftStringObfuscatorCore

struct ObfuscateCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "string-obfuscate",
        abstract: "Scan a directory and obfuscate all .swift files in place."
    )

    @Argument(help: "Directory path to scan and obfuscate .swift files.")
    var focusDirectory: String

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
        print("⚠️  Files will be obfuscated IN PLACE (overwritten)")
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")

        let swiftFiles = findSwiftFiles(in: sourceDir)

        guard !swiftFiles.isEmpty else {
            print("⚠️  No .swift files found in directory")
            return
        }

        print("📊 Found \(swiftFiles.count) .swift file(s)")
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n")

        var successCount = 0
        var failCount = 0

        for (index, sourceFile) in swiftFiles.enumerated() {
            let relativePath = sourceFile.path.replacingOccurrences(
                of: sourceDir.path + "/",
                with: ""
            )

            print("[\(index + 1)/\(swiftFiles.count)] Processing: \(relativePath)")

            do {
                try StringObfuscator.obfuscateContent(
                    sourceFile: sourceFile,
                    targetFile: sourceFile
                )
                successCount += 1
            } catch {
                print("   ❌ Failed: \(error.localizedDescription)")
                failCount += 1
            }
        }

        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        print("📊 Summary:")
        print("   Total files: \(swiftFiles.count)")
        print("   ✅ Successful: \(successCount)")
        if failCount > 0 {
            print("   ❌ Failed: \(failCount)")
        }
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
    }

    private func findSwiftFiles(in directory: URL) -> [URL] {
        let fileManager = FileManager.default
        var swiftFiles: [URL] = []

        guard let enumerator = fileManager.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        for case let fileURL as URL in enumerator {
            guard fileURL.pathExtension == "swift" else { continue }

            if let resourceValues = try? fileURL.resourceValues(forKeys: [.isRegularFileKey]),
               resourceValues.isRegularFile == true {
                swiftFiles.append(fileURL)
            }
        }

        return swiftFiles.sorted { $0.path < $1.path }
    }
}
