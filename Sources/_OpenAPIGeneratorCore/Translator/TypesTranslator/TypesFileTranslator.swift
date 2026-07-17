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
        let componentNamespaces = try translateComponentNamespaces(
            doc.components,
            multipartSchemaNames: multipartSchemaNames
        )
        let components = try translateComponents(doc.components, multipartSchemaNames: multipartSchemaNames)

        let operationDescriptions = try OperationDescription.all(from: doc.paths, in: doc.components, context: context)
        let operations = try translateOperations(operationDescriptions)

        let rootCodeBlocks: [CodeBlock] = [
            .declaration(apiProtocol), .declaration(apiProtocolExtension), .declaration(serversDecl),
        ]
        let codeBlocks = rootCodeBlocks + [components, operations]
        let typesFile = FileDescription(
            topComment: topComment,
            imports: imports,
            codeBlocks: codeBlocks
        )

        guard let fileSplitting = config.output.types?.fileSplitting else {
            return StructuredSwiftRepresentation(
                files: [.init(name: GeneratorMode.types.outputFileName, contents: typesFile)]
            )
        }

        switch fileSplitting.strategy {
        case .namespace:
            let fileNames = fileSplitting.outputFileNames(primaryTypesFileName: GeneratorMode.types.outputFileName)
            let isDepth2 = fileSplitting.namespace?.depth == .two
            let componentsRoot = CodeBlock.declaration(
                .commentable(
                    .doc(
                        """
                        Types generated from the components section of the OpenAPI document.
                        """
                    ),
                    .enum(
                        .init(
                            accessModifier: config.access,
                            name: Constants.Components.namespace,
                            members: []
                        )
                    )
                )
            )
            let componentNamespaceFiles: [NamedFileDescription] = isDepth2
                ? zip(
                    fileNames.dropFirst(3),
                    componentNamespaces
                ).map { fileName, namespace in
                    .init(
                        name: fileName,
                        contents: .init(
                            topComment: topComment,
                            imports: imports,
                            codeBlocks: [
                                .declaration(
                                    .extension(
                                        accessModifier: config.access,
                                        onType: Constants.Components.namespace,
                                        declarations: [namespace]
                                    )
                                )
                            ]
                        )
                    )
                }
                : []
            return StructuredSwiftRepresentation(
                files: [
                    .init(
                        name: fileNames[0],
                        contents: .init(
                            topComment: topComment,
                            imports: imports,
                            codeBlocks: rootCodeBlocks
                        )
                    ),
                    .init(
                        name: fileNames[1],
                        contents: .init(
                            topComment: topComment,
                            imports: imports,
                            codeBlocks: [isDepth2 ? componentsRoot : components]
                        )
                    ),
                    .init(
                        name: fileNames[2],
                        contents: .init(topComment: topComment, imports: imports, codeBlocks: [operations])
                    ),
                ] + componentNamespaceFiles
            )
        case .slices:
            guard let options = fileSplitting.slices else {
                throw GenericError(message: "Missing options for the slices types file splitting strategy.")
            }
            guard options.count > 0 else {
                throw GenericError(message: "Expected slices file splitting count to be greater than zero.")
            }
            guard options.count <= codeBlocks.count else {
                throw GenericError(
                    message:
                        "Expected slices file splitting count to be no greater than the number of top-level declarations in Types.swift."
                )
            }
            let slices = codeBlocks.slices(count: options.count)
            let fileNames = fileSplitting.outputFileNames(primaryTypesFileName: GeneratorMode.types.outputFileName)
            return StructuredSwiftRepresentation(
                files: slices.enumerated().map { index, codeBlocks in
                    .init(
                        name: fileNames[index],
                        contents: .init(topComment: topComment, imports: imports, codeBlocks: codeBlocks)
                    )
                }
            )
        }
    }
}

extension Array {
    /// Splits the array into a requested number of similarly sized slices.
    fileprivate func slices(count: Int) -> [[Element]] {
        let baseCount = self.count / count
        let extraCount = self.count % count
        var startIndex = 0
        return (0..<count).map { sliceIndex in
            let sliceCount = baseCount + (sliceIndex < extraCount ? 1 : 0)
            let endIndex = startIndex + sliceCount
            defer { startIndex = endIndex }
            return Array(self[startIndex..<endIndex])
        }
    }
}
