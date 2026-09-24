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
import OpenAPIKit

/// A translator for the generated common types.
///
/// Types.swift is the Swift file containing all the reusable types from
/// the "Components" section in the OpenAPI document, as well as all of the
/// namespaces for each OpenAPI operation, including their Input and Output
/// types.
///
/// Types generated in this file are depended on by both Client.swift and
/// Server.swift.
struct TypesFileTranslator: FileTranslator {

    var config: Config
    var diagnostics: any DiagnosticCollector
    var components: OpenAPI.Components

    func translateFile(parsedOpenAPI: ParsedOpenAPIRepresentation) throws -> StructuredSwiftRepresentation {

        let doc = parsedOpenAPI

        let topComment = self.topComment

        let imports = importDescriptions(adding: Constants.File.imports)

        let apiProtocol = try translateAPIProtocol(doc.paths)

        let apiProtocolExtension = try translateAPIProtocolExtension(doc.paths)

        let serversDecl = translateServers(doc.servers)

        let multipartSchemaNames = try parseSchemaNamesUsedInMultipart(paths: doc.paths, components: doc.components)
        let operationDescriptions = try OperationDescription.all(from: doc.paths, in: doc.components, context: context)
        if let sharding = config.sharding {
            try sharding.validate()
            return try translateDependencyLayeredFile(
                doc: doc,
                topComment: topComment,
                imports: imports,
                apiProtocol: apiProtocol,
                apiProtocolExtension: apiProtocolExtension,
                serversDecl: serversDecl,
                multipartSchemaNames: multipartSchemaNames,
                operationDescriptions: operationDescriptions,
                requestedLayerCount: sharding.layerCount,
                shardingConfig: sharding
            )
        }

        let componentNamespaces = try translateComponentNamespaceDescriptions(
            doc.components,
            multipartSchemaNames: multipartSchemaNames
        )
        let operations = try translateOperations(operationDescriptions)

        let componentsRoot = CodeBlock.declaration(
            .commentable(
                .doc(
                    """
                    Types generated from the components section of the OpenAPI document.
                    """
                ),
                .enum(.init(accessModifier: config.access, name: Constants.Components.namespace, members: []))
            )
        )
        let rootCodeBlocks: [CodeBlock] = [
            .declaration(apiProtocol), .declaration(apiProtocolExtension), .declaration(serversDecl),
        ]
        let componentNamespaceFiles: [NamedFileDescription] = componentNamespaces.map { namespace in
            .init(
                name: namespace.outputFile.rawValue,
                contents: .init(
                    topComment: topComment,
                    imports: imports,
                    codeBlocks: [
                        .declaration(
                            .extension(
                                accessModifier: nil,
                                onType: Constants.Components.namespace,
                                declarations: [namespace.declaration]
                            )
                        )
                    ]
                )
            )
        }
        return StructuredSwiftRepresentation(
            files: [
                .init(
                    name: OutputFileName.types.rawValue,
                    contents: .init(topComment: topComment, imports: imports, codeBlocks: rootCodeBlocks)
                ),
                .init(
                    name: OutputFileName.typesComponents.rawValue,
                    contents: .init(topComment: topComment, imports: imports, codeBlocks: [componentsRoot])
                ),
                .init(
                    name: OutputFileName.typesOperations.rawValue,
                    contents: .init(topComment: topComment, imports: imports, codeBlocks: [operations])
                ),
            ] + componentNamespaceFiles
        )
    }

    private func translateDependencyLayeredFile(
        doc: ParsedOpenAPIRepresentation,
        topComment: Comment,
        imports: [ImportDescription],
        apiProtocol: Declaration,
        apiProtocolExtension: Declaration,
        serversDecl: Declaration,
        multipartSchemaNames: Set<OpenAPI.ComponentKey>,
        operationDescriptions: [OperationDescription],
        requestedLayerCount: Int,
        shardingConfig: ShardingConfig
    ) throws -> StructuredSwiftRepresentation {
        let graph = SchemaDependencyGraph.build(from: doc.components.schemas)
        let layerBySchema = graph.mappedLayers(requestedLayerCount: requestedLayerCount)

        let schemaGroups = try translateSchemaDeclarationGroups(
            doc.components.schemas,
            multipartSchemaNames: multipartSchemaNames
        )
        let schemaGroupsByOwner = Dictionary(uniqueKeysWithValues: schemaGroups.map { ($0.owner, $0.declarations) })
        let schemaLayerGroups: [Int: [[Declaration]]] = Dictionary(grouping: graph.stronglyConnectedComponents) {
            component in component.compactMap { layerBySchema[$0] }.max() ?? 0
        }
        .mapValues { components in
            components.sorted { ($0.min() ?? "") < ($1.min() ?? "") }
                .map { component in component.sorted().flatMap { schemaGroupsByOwner[$0] ?? [] } }
        }

        func highestLayer(for references: Set<String>) -> Int { references.compactMap { layerBySchema[$0] }.max() ?? 0 }

        let reusableComponentNamespaces = try translateComponentNamespaceDescriptions(
            doc.components,
            multipartSchemaNames: multipartSchemaNames
        ).filter { $0.outputFile != .typesComponentsSchemas }

        var operationGroupsByLayer: [Int: [[Declaration]]] = [:]
        for description in operationDescriptions.sorted(by: { $0.operationID < $1.operationID }) {
            let layer = highestLayer(for: SchemaDependencyGraph.schemaReferences(in: description))
            operationGroupsByLayer[layer, default: []].append([try translateOperation(description)])
        }

        let componentsRoot = CodeBlock.declaration(
            .commentable(
                .doc("Types generated from the components section of the OpenAPI document."),
                .enum(.init(accessModifier: config.access, name: Constants.Components.namespace, members: []))
            )
        )
        let componentNamespacesRoot = CodeBlock.declaration(
            .extension(
                accessModifier: nil,
                onType: Constants.Components.namespace,
                declarations: [
                    .commentable(
                        JSONSchema.sectionComment(),
                        .enum(
                            .init(
                                accessModifier: config.access,
                                name: Constants.Components.Schemas.namespace,
                                members: []
                            )
                        )
                    )
                ]
            )
        )
        let operationsRoot = CodeBlock.declaration(
            .commentable(
                .operationsNamespace(),
                .enum(.init(accessModifier: config.access, name: Constants.Operations.namespace, members: []))
            )
        )

        func moduleImport(_ name: String, exported: Bool = false) -> ImportDescription {
            .init(moduleName: name, exported: exported, setsAccessModifier: false)
        }

        func schemaModuleNames(through layer: Int? = nil) -> [String] {
            guard let prefix = shardingConfig.modulePrefix else { return [] }
            var names = [prefix + "Components"]
            let lastLayer = min(layer ?? (shardingConfig.layerCount - 1), shardingConfig.layerCount - 1)
            if lastLayer >= 0 {
                for schemaLayer in 0...lastLayer {
                    let base = schemaLayer == 0 ? prefix + "Components" : prefix + "Types_L\(schemaLayer)"
                    for shard in 1...shardingConfig.typeShardCounts[schemaLayer] {
                        names.append("\(base)_\(shard)")
                    }
                }
            }
            return names
        }

        func operationModuleNames() -> [String] {
            guard let prefix = shardingConfig.modulePrefix else { return [] }
            let base = prefix + "Operations"
            var names = [base]
            for layer in 0..<shardingConfig.layerCount {
                let shardCount = shardingConfig.operationLayerShardCounts[layer]
                if shardCount == 1 {
                    names.append("\(base)_L\(layer)")
                } else {
                    names += (1...shardCount).map { "\(base)_L\(layer)_\($0)" }
                }
            }
            return names
        }

        let usesModuleContract = shardingConfig.modulePrefix != nil
        let rootImports = imports
            + (schemaModuleNames() + operationModuleNames())
                .map { moduleImport($0, exported: true) }
        let componentBaseName = shardingConfig.modulePrefix.map { "\($0)Components_openapi_components.swift" }
            ?? OutputFileName.typesComponents.rawValue
        let operationsBaseName = shardingConfig.modulePrefix.map { "\($0)Operations_openapi_operations.swift" }
            ?? OutputFileName.typesOperations.rawValue

        let rootCodeBlocks: [CodeBlock] = usesModuleContract
            ? [.declaration(apiProtocol), .declaration(apiProtocolExtension)]
            : [
                .declaration(apiProtocol), .declaration(apiProtocolExtension), .declaration(serversDecl), componentsRoot,
                operationsRoot,
            ]
        let componentCodeBlocks = usesModuleContract ? [componentsRoot, componentNamespacesRoot] : [componentNamespacesRoot]
        var files: [NamedFileDescription] = [
            .init(
                name: usesModuleContract ? "Types_root.swift" : OutputFileName.types.rawValue,
                contents: .init(
                    topComment: topComment,
                    imports: rootImports,
                    codeBlocks: rootCodeBlocks
                )
            ),
            .init(
                name: componentBaseName,
                contents: .init(
                    topComment: topComment,
                    imports: imports,
                    codeBlocks: componentCodeBlocks
                )
            ),
        ] + reusableComponentNamespaces.map { namespace in
            .init(
                name: namespace.outputFile.rawValue,
                contents: .init(
                    topComment: topComment,
                    imports: imports,
                    codeBlocks: [
                        .declaration(
                            .extension(
                                accessModifier: nil,
                                onType: Constants.Components.namespace,
                                declarations: [namespace.declaration]
                            )
                        )
                    ]
                )
            )
        }
        if usesModuleContract {
            files.append(.init(
                name: operationsBaseName,
                contents: .init(
                    topComment: topComment,
                    imports: imports,
                    codeBlocks: [.declaration(serversDecl), operationsRoot]
                )
            ))
        }

        func appendLayerFiles(
            groupsByLayer: [Int: [[Declaration]]],
            namespace: String,
            baseFileName: String,
            shardCounts: [Int]? = nil,
            maximumFilesPerShard: Int? = nil,
            fixedLayerCount: Int? = nil,
            importsForLayer: ((Int) -> [ImportDescription])? = nil,
            fileName: ((Int, Int, Int) -> String)? = nil
        ) {
            let layers = fixedLayerCount.map { Array(0..<$0) } ?? groupsByLayer.keys.sorted()
            for layer in layers {
                let layerGroups = groupsByLayer[layer] ?? []
                let shardGroups: [[[Declaration]]]
                if let shardCounts {
                    shardGroups = Self.balanceDeclarationGroups(layerGroups, shardCount: shardCounts[layer])
                } else {
                    shardGroups = [layerGroups]
                }
                for (shard, groups) in shardGroups.enumerated() {
                    var shardBaseFileName = baseFileName.appendingFileNameSuffix("Layer\(layer)")
                    if shardCounts != nil { shardBaseFileName = shardBaseFileName.appendingFileNameSuffix("Shard\(shard)") }
                    files += makeSplitFiles(
                        for: groups,
                        extending: namespace,
                        baseFileName: shardBaseFileName,
                        preserveEmptyFile: fixedLayerCount != nil,
                        topComment: topComment,
                        imports: imports + (importsForLayer?(layer) ?? []),
                        maximumFileCount: maximumFilesPerShard,
                        fileName: fileName.map { naming in { naming(layer, shard, $0) } }
                    )
                }
            }
        }

        appendLayerFiles(
            groupsByLayer: schemaLayerGroups,
            namespace: "Components.Schemas",
            baseFileName: OutputFileName.typesComponentsSchemas.rawValue,
            shardCounts: shardingConfig.typeShardCounts,
            maximumFilesPerShard: shardingConfig.maxFilesPerShard,
            fixedLayerCount: shardingConfig.layerCount,
            importsForLayer: { layer in
                guard usesModuleContract else { return [] }
                if layer == 0 {
                    return shardingConfig.modulePrefix.map { [moduleImport($0 + "Components")] } ?? []
                }
                return schemaModuleNames(through: layer - 1).map { moduleImport($0) }
            },
            fileName: shardingConfig.modulePrefix.map { prefix in
                { layer, shard, file in
                    if layer == 0 {
                        return "\(prefix)Components_openapi_components_\(shard + 1)_\(file + 1).swift"
                    }
                    return "\(prefix)Types_L\(layer)_openapi_types_l\(layer)_\(shard + 1)_\(file + 1).swift"
                }
            }
        )
        appendLayerFiles(
            groupsByLayer: operationGroupsByLayer,
            namespace: Constants.Operations.namespace,
            baseFileName: OutputFileName.typesOperations.rawValue,
            shardCounts: shardingConfig.operationLayerShardCounts,
            maximumFilesPerShard: shardingConfig.maxFilesPerShardOps,
            fixedLayerCount: shardingConfig.layerCount,
            importsForLayer: { layer in
                guard usesModuleContract else { return [] }
                let operations = shardingConfig.modulePrefix.map { [moduleImport($0 + "Operations")] } ?? []
                return operations + schemaModuleNames(through: layer).map { moduleImport($0) }
            },
            fileName: shardingConfig.modulePrefix.map { prefix in
                { layer, shard, file in
                    "\(prefix.lowercased())operations_openapi_operations_l\(layer)_\(shard + 1)_\(file + 1).swift"
                }
            }
        )
        return .init(files: files)
    }

    private func makeSplitFiles(
        for declarationGroups: [[Declaration]],
        extending namespace: String,
        baseFileName: String,
        preserveEmptyFile: Bool,
        topComment: Comment,
        imports: [ImportDescription],
        maximumFileCount: Int? = nil,
        fileName: ((Int) -> String)? = nil
    ) -> [NamedFileDescription] {
        let declarationChunks: [[Declaration]]
        if let maximumFileCount {
            let declarations = declarationGroups.flatMap { $0 }
            let populatedChunks: [[Declaration]]
            if declarations.isEmpty {
                populatedChunks = []
            } else {
                let minimumDeclarationsPerFile = 12
                let evenlyDistributedCount = (declarations.count + maximumFileCount - 1) / maximumFileCount
                let declarationsPerFile = max(minimumDeclarationsPerFile, evenlyDistributedCount)
                populatedChunks = stride(from: 0, to: declarations.count, by: declarationsPerFile)
                    .map { start in Array(declarations[start..<min(start + declarationsPerFile, declarations.count)]) }
            }
            declarationChunks = populatedChunks + Array(repeating: [], count: maximumFileCount - populatedChunks.count)
        } else {
            declarationChunks = declarationGroups.isEmpty ? [] : [declarationGroups.flatMap { $0 }]
        }
        let chunks = declarationChunks.isEmpty && preserveEmptyFile ? [[]] : declarationChunks
        return chunks.enumerated()
            .map { splitIndex, declarations in
                NamedFileDescription(
                    name: fileName?(splitIndex)
                        ?? (splitIndex == 0 ? baseFileName : baseFileName.appendingFileNameSuffix(String(splitIndex))),
                    contents: .init(
                        topComment: topComment,
                        imports: imports,
                        codeBlocks: [
                            .declaration(.extension(accessModifier: nil, onType: namespace, declarations: declarations))
                        ]
                    )
                )
            }
    }

    /// Longest-processing-time packing from the original dependency sharding implementation.
    private static func balanceDeclarationGroups(_ groups: [[Declaration]], shardCount: Int) -> [[[Declaration]]] {
        var shards = Array(repeating: (weight: 0, groups: [(index: Int, group: [Declaration])]()), count: shardCount)
        var weighted: [(index: Int, group: [Declaration], weight: Int)] = []
        for (index, group) in groups.enumerated() {
            var weight = 0
            for declaration in group { weight += declarationNodeCount(declaration) }
            weighted.append((index: index, group: group, weight: max(1, weight)))
        }
        weighted.sort { lhs, rhs in lhs.weight == rhs.weight ? lhs.index < rhs.index : lhs.weight > rhs.weight }
        for item in weighted {
            let shard = shards.indices.min { lhs, rhs in
                shards[lhs].weight == shards[rhs].weight ? lhs < rhs : shards[lhs].weight < shards[rhs].weight
            }!
            shards[shard].weight += item.weight
            shards[shard].groups.append((index: item.index, group: item.group))
        }
        return shards.map { shard in shard.groups.sorted { $0.index < $1.index }.map(\.group) }
    }

    private static func declarationNodeCount(_ declaration: Declaration) -> Int {
        switch declaration {
        case .commentable(_, let inner), .deprecated(_, let inner): return 1 + declarationNodeCount(inner)
        case .extension(let description):
            return 1 + description.declarations.reduce(0) { $0 + declarationNodeCount($1) }
        case .struct(let description): return 1 + description.members.reduce(0) { $0 + declarationNodeCount($1) }
        case .enum(let description): return 1 + description.members.reduce(0) { $0 + declarationNodeCount($1) }
        case .protocol(let description): return 1 + description.members.reduce(0) { $0 + declarationNodeCount($1) }
        case .variable, .typealias, .function, .enumCase: return 1
        }
    }
}

extension String {
    /// Returns a Swift file name with the provided suffix appended before the extension.
    func appendingFileNameSuffix(_ suffix: String) -> String {
        hasSuffix(".swift") ? "\(dropLast(".swift".count))+\(suffix).swift" : "\(self)+\(suffix).swift"
    }
}

extension Declaration {
    /// Returns a component namespace's comment and the declarations to emit in extension files.
    fileprivate var namespaceContents: (name: String, comment: Comment?, declarations: [Declaration]) {
        guard case .commentable(let comment, .enum(let description)) = self else {
            preconditionFailure("Expected a commented enum namespace declaration.")
        }
        return (description.name, comment, description.members)
    }
}

extension CodeBlock {
    /// Returns the operation declarations to emit in extension files.
    fileprivate var namespaceDeclarations: [Declaration] {
        guard case .declaration(.enum(let description)) = item else {
            preconditionFailure("Expected an enum namespace declaration code block.")
        }
        return description.members
    }
}
