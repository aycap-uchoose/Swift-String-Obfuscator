//
//  ObfuscateStringsRewritter.swift
//  string_obfuscator
//
//  Created by Lukas Gergel on 01.01.2021.
//

import Foundation
import SwiftSyntax

enum State {
    case reading
    case command
}

class ObfuscateStringsRewritter: SyntaxRewriter {
    private var linesToObfuscate: Set<Int> = []
    private let sourceLocationConverter: SourceLocationConverter
    
    init(sourceLocationConverter: SourceLocationConverter, fileContent: String) {
        self.sourceLocationConverter = sourceLocationConverter
        super.init()
        
        let lines = fileContent.components(separatedBy: .newlines)
        for (index, line) in lines.enumerated() {
            if line.trimmingCharacters(in: .whitespaces) == "//:obfuscate" {
                let targetLine = index + 2  // +2 เพราะ index เริ่มที่ 0
                linesToObfuscate.insert(targetLine)
            }
        }
    }
    
    func integerLiteralElement(_ int: Int, addComma: Bool = true) -> ArrayElementSyntax {
        let literal = SyntaxFactory.makeIntegerLiteral("\(int)")
        return SyntaxFactory.makeArrayElement(
            expression: ExprSyntax(SyntaxFactory.makeIntegerLiteralExpr(digits: literal)),
            trailingComma: addComma ? SyntaxFactory.makeCommaToken() : nil)
    }
    
    private func isInReplacingOccurrences(_ node: StringLiteralExprSyntax) -> Bool {
        var current: Syntax? = Syntax(node)
        
        while let parent = current?.parent {
            if let functionCall = parent.as(FunctionCallExprSyntax.self) {
                let functionName = "\(functionCall.calledExpression)"
                if functionName.contains("replacingOccurrences") {
                    return true
                }
            }
            current = parent
        }
        
        return false
    }
    
    override open func visit(_ node: StringLiteralExprSyntax) -> ExprSyntax {
        // ⭐ หา line number ของ string นี้
        let location = sourceLocationConverter.location(for: node.positionAfterSkippingLeadingTrivia)
        guard let lineNumber = location.line else {
            return super.visit(node)
        }
        
        // ⭐ เช็คว่าบรรทัดนี้ต้อง obfuscate หรือไม่
        let shouldObfuscate = linesToObfuscate.contains(lineNumber)
        
        let hasInterpolation = node.segments.contains { segment in
            segment.is(ExpressionSegmentSyntax.self)
        }
        
        let isEmpty = node.segments.isEmpty ||
                      (node.segments.count == 1 &&
                       node.segments.first?.as(StringSegmentSyntax.self)?.content.text.isEmpty == true)
        
        let inReplacingOccurrences = isInReplacingOccurrences(node)
        
        let origValue = "\(node.segments)"
        
        guard shouldObfuscate && !hasInterpolation && !isEmpty && !inReplacingOccurrences else {
            return super.visit(node)
        }
        
        print("🔄 Obfuscating: \"\(origValue)\" on line \(lineNumber)")
        
        let bytes = origValue.bytes.enumerated().map { (i, element) -> ArrayElementSyntax in
            integerLiteralElement(Int(element), addComma: i < origValue.bytes.count - 1)
        }
        let arrayElementList = SyntaxFactory.makeArrayElementList(bytes)
        
        let bytesArg = SyntaxFactory.makeTupleExprElement(
            label: SyntaxFactory.makeIdentifier("bytes"),
            colon: SyntaxFactory.makeColonToken(leadingTrivia: .zero, trailingTrivia: .spaces(1)),
            expression: ExprSyntax(SyntaxFactory.makeArrayExpr(
                leftSquare: SyntaxFactory.makeLeftSquareBracketToken(),
                elements: arrayElementList,
                rightSquare: SyntaxFactory.makeRightSquareBracketToken())),
            trailingComma: SyntaxFactory.makeCommaToken()
        )
        
        let encodingArg = SyntaxFactory.makeTupleExprElement(
            label: SyntaxFactory.makeIdentifier("encoding"),
            colon: SyntaxFactory.makeColonToken(leadingTrivia: .zero, trailingTrivia: .spaces(1)),
            expression: ExprSyntax(SyntaxFactory.makeIdentifierExpr(
                identifier: SyntaxFactory.makeIdentifier(".utf8"),
                declNameArguments: nil)),
            trailingComma: nil
        ).withLeadingTrivia(.spaces(1))
        
        let stringCall = SyntaxFactory.makeFunctionCallExpr(
            calledExpression: ExprSyntax(
                SyntaxFactory.makeIdentifierExpr(
                    identifier: SyntaxFactory.makeIdentifier("String"),
                    declNameArguments: nil
                )
            ),
            leftParen: SyntaxFactory.makeLeftParenToken(),
            argumentList: SyntaxFactory.makeTupleExprElementList([bytesArg, encodingArg]),
            rightParen: SyntaxFactory.makeRightParenToken(),
            trailingClosure: nil,
            additionalTrailingClosures: nil
        )
        
        let nilCoalescing = SyntaxFactory.makeSequenceExpr(
            elements: SyntaxFactory.makeExprList([
                ExprSyntax(stringCall),
                ExprSyntax(SyntaxFactory.makeBinaryOperatorExpr(operatorToken: SyntaxFactory.makeIdentifier(" ?? "))),
                ExprSyntax(SyntaxFactory.makeStringLiteralExpr(""))
            ])
        )
        
        let groupedExpr = SyntaxFactory.makeTupleExpr(
            leftParen: SyntaxFactory.makeLeftParenToken(),
            elementList: SyntaxFactory.makeTupleExprElementList([
                SyntaxFactory.makeTupleExprElement(label: nil, colon: nil, expression: ExprSyntax(nilCoalescing), trailingComma: nil)
            ]),
            rightParen: SyntaxFactory.makeRightParenToken()
        )
        
        let result = groupedExpr
            .withLeadingTrivia(node.leadingTrivia ?? .zero)
            .withTrailingTrivia(node.trailingTrivia ?? .zero)
        
        return ExprSyntax(result)
    }
}
