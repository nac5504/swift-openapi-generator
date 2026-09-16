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

        let maxDeclarationsPerFile = config.maxDeclarationsPerFile
        if let maxDeclarationsPerFile, maxDeclarationsPerFile <= 0 {
            throw GenericError(message: "Expected output.maxDeclarationsPerFile to be greater than zero.")
        }
        let dependencyLayerCount = config.dependencyLayerCount
        if let dependencyLayerCount, dependencyLayerCount <= 0 {
            throw GenericError(message: "Expected output.dependencyLayerCount to be greater than zero.")
        }
        if let sharding = config.sharding {
            try sharding.validate()
            if let dependencyLayerCount, dependencyLayerCount != sharding.layerCount {
                throw GenericError(
                    message: "Expected dependencyLayerCount to equal sharding.typeShardCounts.count when both are set."
                )
            }
        }

        let topComment = self.topComment

        let imports = importDescriptions(adding: Constants.File.imports)

        let apiProtocol = try translateAPIProtocol(doc.paths)

        let apiProtocolExtension = try translateAPIProtocolExtension(doc.paths)

        let serversDecl = translateServers(doc.servers)

        let multipartSchemaNames = try parseSchemaNamesUsedInMultipart(paths: doc.paths, components: doc.components)
        let operationDescriptions = try OperationDescription.all(from: doc.paths, in: doc.components, context: context)
        if let requestedLayerCount = config.sharding?.layerCount ?? dependencyLayerCount {
            return try translateDependencyLayeredFile(
                doc: doc,
                topComment: topComment,
                imports: imports,
                apiProtocol: apiProtocol,
                apiProtocolExtension: apiProtocolExtension,
                serversDecl: serversDecl,
                multipartSchemaNames: multipartSchemaNames,
                operationDescriptions: operationDescriptions,
                requestedLayerCount: requestedLayerCount,
                shardingConfig: config.sharding
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
        if maxDeclarationsPerFile == nil {
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

        typealias Namespace = (path: [String], baseFileName: String, comment: Comment?, declarations: [Declaration])
        let namespaces: [Namespace] =
            [
                (
                    path: [Constants.Operations.namespace], baseFileName: OutputFileName.typesOperations.rawValue,
                    comment: operations.comment, declarations: operations.namespaceDeclarations
                )
            ]
            + componentNamespaces.map { namespace in
                let contents = namespace.declaration.namespaceContents
                return (
                    path: [Constants.Components.namespace, contents.name], baseFileName: namespace.outputFile.rawValue,
                    comment: contents.comment, declarations: contents.declarations
                )
            }

        func namespaceRoot(for namespace: Namespace) -> Declaration {
            (.commentable(
                namespace.comment,
                .enum(.init(accessModifier: config.access, name: namespace.path.last!, members: []))
            ))
        }

        let typesRoot: [CodeBlock] =
            [.declaration(apiProtocol), .declaration(apiProtocolExtension), .declaration(serversDecl), componentsRoot]
            + namespaces.filter { $0.path.count == 1 }.map { .declaration(namespaceRoot(for: $0)) }
        let componentNamespacesRoot = CodeBlock.declaration(
            .extension(
                accessModifier: nil,
                onType: Constants.Components.namespace,
                declarations: namespaces.filter { $0.path.dropLast() == [Constants.Components.namespace] }
                    .map(namespaceRoot)
            )
        )
        let namespaceFiles = namespaces.flatMap { namespace in
            makeSplitFiles(
                for: namespace.declarations.map { [$0] },
                extending: namespace.path.joined(separator: "."),
                baseFileName: namespace.baseFileName,
                role: namespace.path.joined(separator: "."),
                dependencyLayer: nil,
                preserveEmptyFile: true,
                topComment: topComment,
                imports: imports,
                maxDeclarationsPerFile: maxDeclarationsPerFile
            )
        }

        return StructuredSwiftRepresentation(
            files: [
                .init(
                    name: OutputFileName.types.rawValue,
                    contents: .init(topComment: topComment, imports: imports, codeBlocks: typesRoot)
                ),
                .init(
                    name: OutputFileName.typesComponents.rawValue,
                    contents: .init(topComment: topComment, imports: imports, codeBlocks: [componentNamespacesRoot])
                ),
            ] + namespaceFiles
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
        shardingConfig: ShardingConfig?
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

        let resolvedParameters = try doc.components.parameters.mapValues { try doc.components.assumeLookupOnce($0) }
        let resolvedRequestBodies = try doc.components.requestBodies.mapValues {
            try doc.components.assumeLookupOnce($0)
        }
        let resolvedResponses = try doc.components.responses.mapValues { try doc.components.assumeLookupOnce($0) }
        let resolvedHeaders = try doc.components.headers.mapValues {
            (header: Either<OpenAPI.Reference<OpenAPI.Header>, OpenAPI.Header>) in
            try doc.components.assumeLookupOnce(header)
        }

        func highestLayer(for references: Set<String>) -> Int { references.compactMap { layerBySchema[$0] }.max() ?? 0 }

        func groupsByLayer<Component>(
            _ groups: [OwnedDeclarations],
            components: OpenAPI.ComponentDictionary<Component>,
            references: (Component) -> Set<String>
        ) -> [Int: [[Declaration]]] {
            var result: [Int: [[Declaration]]] = [:]
            for group in groups {
                guard let key = OpenAPI.ComponentKey(rawValue: group.owner), let component = components[key] else {
                    continue
                }
                result[highestLayer(for: references(component)), default: []].append(group.declarations)
            }
            return result
        }

        let parameterGroups = try translateComponentParameterDeclarationGroups(resolvedParameters)
        let requestBodyGroups = try translateComponentRequestBodyDeclarationGroups(resolvedRequestBodies)
        let responseGroups = try translateComponentResponseDeclarationGroups(resolvedResponses)
        let headerGroups = try translateComponentHeaderDeclarationGroups(resolvedHeaders)

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
        let namespaces: [(name: String, comment: Comment?)] = [
            (Constants.Components.Schemas.namespace, JSONSchema.sectionComment()),
            (Constants.Components.Parameters.namespace, OpenAPI.Parameter.sectionComment()),
            (Constants.Components.RequestBodies.namespace, OpenAPI.Request.sectionComment()),
            (Constants.Components.Responses.namespace, OpenAPI.Response.sectionComment()),
            (Constants.Components.Headers.namespace, OpenAPI.Header.sectionComment()),
        ]
        let componentNamespacesRoot = CodeBlock.declaration(
            .extension(
                accessModifier: nil,
                onType: Constants.Components.namespace,
                declarations: namespaces.map { namespace in
                    .commentable(
                        namespace.comment,
                        .enum(.init(accessModifier: config.access, name: namespace.name, members: []))
                    )
                }
            )
        )
        let operationsRoot = CodeBlock.declaration(
            .commentable(
                .operationsNamespace(),
                .enum(.init(accessModifier: config.access, name: Constants.Operations.namespace, members: []))
            )
        )

        var files: [NamedFileDescription] = [
            .init(
                name: OutputFileName.types.rawValue,
                contents: .init(
                    topComment: topComment,
                    imports: imports,
                    codeBlocks: [
                        .declaration(apiProtocol), .declaration(apiProtocolExtension), .declaration(serversDecl),
                        componentsRoot, operationsRoot,
                    ]
                ),
                metadata: .init(role: "typesRoot", dependencyLayer: nil, declarationChunk: nil)
            ),
            .init(
                name: OutputFileName.typesComponents.rawValue,
                contents: .init(topComment: topComment, imports: imports, codeBlocks: [componentNamespacesRoot]),
                metadata: .init(role: "componentsRoot", dependencyLayer: nil, declarationChunk: nil)
            ),
        ]

        func appendLayerFiles(
            groupsByLayer: [Int: [[Declaration]]],
            namespace: String,
            baseFileName: String,
            role: String,
            shardCounts: [Int]? = nil,
            maximumFilesPerShard: Int? = nil,
            fixedLayerCount: Int? = nil
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
                    if shardCounts != nil {
                        shardBaseFileName = shardBaseFileName.appendingFileNameSuffix("Shard\(shard)")
                    }
                    files += makeSplitFiles(
                        for: groups,
                        extending: namespace,
                        baseFileName: shardBaseFileName,
                        role: role,
                        dependencyLayer: layer,
                        preserveEmptyFile: fixedLayerCount != nil,
                        topComment: topComment,
                        imports: imports,
                        maxDeclarationsPerFile: config.maxDeclarationsPerFile,
                        maximumFileCount: maximumFilesPerShard
                    )
                }
            }
        }

        appendLayerFiles(
            groupsByLayer: schemaLayerGroups,
            namespace: "Components.Schemas",
            baseFileName: OutputFileName.typesComponentsSchemas.rawValue,
            role: "components.schemas",
            shardCounts: shardingConfig?.typeShardCounts,
            maximumFilesPerShard: shardingConfig?.maxFilesPerShard,
            fixedLayerCount: shardingConfig?.layerCount
        )
        appendLayerFiles(
            groupsByLayer: groupsByLayer(parameterGroups, components: resolvedParameters) {
                SchemaDependencyGraph.schemaReferences(in: $0, components: doc.components)
            },
            namespace: "Components.Parameters",
            baseFileName: OutputFileName.typesComponentsParameters.rawValue,
            role: "components.parameters",
            fixedLayerCount: shardingConfig?.layerCount
        )
        appendLayerFiles(
            groupsByLayer: groupsByLayer(requestBodyGroups, components: resolvedRequestBodies) {
                SchemaDependencyGraph.schemaReferences(in: $0, components: doc.components)
            },
            namespace: "Components.RequestBodies",
            baseFileName: OutputFileName.typesComponentsRequestBodies.rawValue,
            role: "components.requestBodies",
            fixedLayerCount: shardingConfig?.layerCount
        )
        appendLayerFiles(
            groupsByLayer: groupsByLayer(responseGroups, components: resolvedResponses) {
                SchemaDependencyGraph.schemaReferences(in: $0, components: doc.components)
            },
            namespace: "Components.Responses",
            baseFileName: OutputFileName.typesComponentsResponses.rawValue,
            role: "components.responses",
            fixedLayerCount: shardingConfig?.layerCount
        )
        appendLayerFiles(
            groupsByLayer: groupsByLayer(headerGroups, components: resolvedHeaders) {
                SchemaDependencyGraph.schemaReferences(in: $0, components: doc.components)
            },
            namespace: "Components.Headers",
            baseFileName: OutputFileName.typesComponentsHeaders.rawValue,
            role: "components.headers",
            fixedLayerCount: shardingConfig?.layerCount
        )
        appendLayerFiles(
            groupsByLayer: operationGroupsByLayer,
            namespace: Constants.Operations.namespace,
            baseFileName: OutputFileName.typesOperations.rawValue,
            role: "operations",
            shardCounts: shardingConfig?.operationLayerShardCounts,
            maximumFilesPerShard: shardingConfig?.maxFilesPerShardOps,
            fixedLayerCount: shardingConfig?.layerCount
        )
        return .init(files: files)
    }

    private func makeSplitFiles(
        for declarationGroups: [[Declaration]],
        extending namespace: String,
        baseFileName: String,
        role: String,
        dependencyLayer: Int?,
        preserveEmptyFile: Bool,
        topComment: Comment,
        imports: [ImportDescription],
        maxDeclarationsPerFile: Int?,
        maximumFileCount: Int? = nil
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
        } else if let maxDeclarationsPerFile {
            var chunks: [[Declaration]] = []
            for group in declarationGroups {
                if let last = chunks.indices.last, !chunks[last].isEmpty,
                    chunks[last].count + group.count <= maxDeclarationsPerFile
                {
                    chunks[last].append(contentsOf: group)
                } else {
                    chunks.append(group)
                }
            }
            declarationChunks = chunks
        } else {
            declarationChunks = declarationGroups.isEmpty ? [] : [declarationGroups.flatMap { $0 }]
        }
        let chunks = declarationChunks.isEmpty && preserveEmptyFile ? [[]] : declarationChunks
        return chunks.enumerated()
            .map { splitIndex, declarations in
                NamedFileDescription(
                    name: splitIndex == 0 ? baseFileName : baseFileName.appendingFileNameSuffix(String(splitIndex)),
                    contents: .init(
                        topComment: topComment,
                        imports: imports,
                        codeBlocks: [
                            .declaration(.extension(accessModifier: nil, onType: namespace, declarations: declarations))
                        ]
                    ),
                    metadata: .init(role: role, dependencyLayer: dependencyLayer, declarationChunk: splitIndex)
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
