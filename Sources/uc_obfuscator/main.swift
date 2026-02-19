//
//  main.swift
//  string_obfuscator
//
//  Created by Lukas Gergel on 27.12.2020.
//

import ArgumentParser

struct UCStringObfuscatorCLI: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "uc-obfuscator",
        abstract: "A Swift command-line tool to convert string api-keys to byte arrays.",
        subcommands: [
            ObfuscateCommand.self,
            DetectCommand.self,
            DetectIfDefsCommand.self
        ],
        defaultSubcommand: ObfuscateCommand.self // (optional)
    )
}

UCStringObfuscatorCLI.main()
