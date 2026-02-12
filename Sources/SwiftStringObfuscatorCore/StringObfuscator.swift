//
//  StringObfuscator.swift
//
//
//  Created by Lukas Gergel on 02.01.2021.
//

import Foundation
import SwiftSyntax
import SwiftSyntaxParser

public class StringObfuscator {
    public static func obfuscateContent(sourceFile: URL, targetFile: URL) throws {
        let fileContent = try String(contentsOf: sourceFile, encoding: .utf8)
        let sourceFileSyntax = try SyntaxParser.parse(sourceFile)
        let converter = SourceLocationConverter(file: sourceFile.path, tree: sourceFileSyntax)
        let rewriter = ObfuscateStringsRewritter(sourceLocationConverter: converter, fileContent: fileContent)
        
        var output = ""
        let obfuscated = rewriter.visit(sourceFileSyntax)
        obfuscated.write(to: &output)
        
        try output.write(to: targetFile, atomically: true, encoding: .utf8)
    }
}
