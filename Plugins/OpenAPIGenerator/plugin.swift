//===----------------------------------------------------------------------===//
//
// This source file is part of the SwiftOpenAPIGenerator open source project
//
// Copyright (c) 2023 Apple Inc. and the SwiftOpenAPIGenerator project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of SwiftOpenAPIGenerator project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//
import PackagePlugin
import Foundation

@main struct SwiftOpenAPIGeneratorPlugin {
    func createBuildCommands(
        pluginWorkDirectory: URL,
        tool: (String) throws -> PluginContext.Tool,
        sourceFiles: FileList,
        targetName: String
    ) throws -> [Command] {
        let inputs = try PluginUtils.validateInputs(
            workingDirectory: pluginWorkDirectory,
            tool: tool,
            sourceFiles: sourceFiles,
            targetName: targetName,
            pluginSource: .build
        )

        let outputFiles = outputFiles(config: inputs.config, genSourcesDir: inputs.genSourcesDir)
        return [
            .buildCommand(
                displayName: "Running swift-openapi-generator",
                executable: inputs.tool.url,
                arguments: inputs.arguments,
                environment: [:],
                inputFiles: [inputs.config, inputs.doc],
                outputFiles: outputFiles
            )
        ]
    }

    /// Returns the generated files that SwiftPM should compile for this plugin invocation.
    private func outputFiles(config: URL, genSourcesDir: URL) -> [URL] {
        var fileNames = GeneratorMode.allOutputFileNames
        if typesFileSplittingStrategy(config: config) == "namespace" {
            fileNames.append(
                contentsOf: [
                    GeneratorMode.outputFileName(GeneratorMode.types.outputFileName, "Components"),
                    GeneratorMode.outputFileName(GeneratorMode.types.outputFileName, "Operations"),
                ]
            )
        }
        return fileNames.map { genSourcesDir.appending(component: $0) }
    }

    /// Returns the configured types file splitting strategy, if present.
    private func typesFileSplittingStrategy(config: URL) -> String? {
        value(inConfig: config, atPath: ["output", "types", "fileSplitting", "strategy"])
    }

    /// Returns a string value at the specified YAML key path, if present.
    private func value(inConfig config: URL, atPath path: [String]) -> String? {
        guard let source = try? String(contentsOf: config, encoding: .utf8) else { return nil }
        var keyPath: [(indentation: Int, key: String)] = []
        for line in source.split(whereSeparator: \.isNewline) {
            let indentation = line.prefix(while: { $0 == " " }).count
            let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedLine.isEmpty, !trimmedLine.hasPrefix("#") else { continue }
            let parts = trimmedLine.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
            guard let key = parts.first else { continue }
            keyPath.removeAll { $0.indentation >= indentation }
            keyPath.append((indentation, String(key)))
            guard keyPath.map(\.key) == path else { continue }
            return parts.dropFirst().first?.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return nil
    }
}

extension SwiftOpenAPIGeneratorPlugin: BuildToolPlugin {
    func createBuildCommands(context: PluginContext, target: Target) async throws -> [Command] {
        guard let swiftTarget = target as? SwiftSourceModuleTarget else {
            throw PluginError.incompatibleTarget(name: target.name)
        }
        return try createBuildCommands(
            pluginWorkDirectory: context.pluginWorkDirectoryURL,
            tool: context.tool,
            sourceFiles: swiftTarget.sourceFiles,
            targetName: target.name
        )
    }
}

#if canImport(XcodeProjectPlugin)
import XcodeProjectPlugin

extension SwiftOpenAPIGeneratorPlugin: XcodeBuildToolPlugin {
    func createBuildCommands(context: XcodePluginContext, target: XcodeTarget) throws -> [Command] {
        try createBuildCommands(
            pluginWorkDirectory: context.pluginWorkDirectoryURL,
            tool: context.tool,
            sourceFiles: target.inputFiles,
            targetName: target.displayName
        )
    }
}
#endif
