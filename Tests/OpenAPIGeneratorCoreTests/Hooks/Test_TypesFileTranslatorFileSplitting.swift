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
import Foundation
import XCTest
@testable import _OpenAPIGeneratorCore

final class Test_TypesFileTranslatorFileSplitting: Test_Core {

    func testNamespaceSplittingProducesRootComponentsAndOperationsFiles() throws {
        let input = InMemoryInputFile(
            absolutePath: URL(string: "openapi.yaml")!,
            contents: Data(Self.source.utf8)
        )
        let diagnostics = AccumulatingDiagnosticCollector()
        let outputs = try runGenerator(
            input: input,
            config: Self.splitConfig(strategy: .namespace, namespace: .init(depth: .one)),
            diagnostics: diagnostics
        )

        XCTAssertEqual(diagnostics.diagnostics.count, 0)
        XCTAssertEqual(outputs.map(\.baseName), ["Types.swift", "Types+Components.swift", "Types+Operations.swift"])

        let outputByName = Self.outputByName(outputs)
        let rootSource = try XCTUnwrap(outputByName["Types.swift"])
        let componentsSource = try XCTUnwrap(outputByName["Types+Components.swift"])
        let operationsSource = try XCTUnwrap(outputByName["Types+Operations.swift"])

        XCTAssertTrue(rootSource.contains("protocol APIProtocol"))
        XCTAssertFalse(rootSource.contains("enum Components"))
        XCTAssertFalse(rootSource.contains("enum Operations"))

        XCTAssertTrue(componentsSource.contains("enum Components"))
        XCTAssertTrue(componentsSource.contains("enum Schemas"))
        XCTAssertTrue(componentsSource.contains("enum Parameters"))
        XCTAssertTrue(componentsSource.contains("enum RequestBodies"))
        XCTAssertTrue(componentsSource.contains("enum Responses"))
        XCTAssertTrue(componentsSource.contains("enum Headers"))
        XCTAssertTrue(componentsSource.contains("struct User"))
        XCTAssertFalse(componentsSource.contains("protocol APIProtocol"))
        XCTAssertFalse(componentsSource.contains("enum Operations"))

        XCTAssertTrue(operationsSource.contains("enum Operations"))
        XCTAssertFalse(operationsSource.contains("enum Components"))
        XCTAssertFalse(operationsSource.contains("protocol APIProtocol"))
    }

    func testNamespaceDepth2SplittingProducesComponentNamespaceFiles() throws {
        let input = InMemoryInputFile(
            absolutePath: URL(string: "openapi.yaml")!,
            contents: Data(Self.source.utf8)
        )
        let diagnostics = AccumulatingDiagnosticCollector()
        let outputs = try runGenerator(
            input: input,
            config: Self.splitConfig(strategy: .namespace, namespace: .init(depth: .two)),
            diagnostics: diagnostics
        )

        XCTAssertEqual(diagnostics.diagnostics.count, 0)
        XCTAssertEqual(
            outputs.map(\.baseName),
            [
                "Types.swift",
                "Types+Components.swift",
                "Types+Operations.swift",
                "Types+Components+Schemas.swift",
                "Types+Components+Parameters.swift",
                "Types+Components+RequestBodies.swift",
                "Types+Components+Responses.swift",
                "Types+Components+Headers.swift",
            ]
        )

        let outputByName = Self.outputByName(outputs)
        let rootSource = try XCTUnwrap(outputByName["Types.swift"])
        let componentsSource = try XCTUnwrap(outputByName["Types+Components.swift"])
        let componentSchemasSource = try XCTUnwrap(outputByName["Types+Components+Schemas.swift"])
        let componentParametersSource = try XCTUnwrap(outputByName["Types+Components+Parameters.swift"])
        let componentRequestBodiesSource = try XCTUnwrap(outputByName["Types+Components+RequestBodies.swift"])
        let componentResponsesSource = try XCTUnwrap(outputByName["Types+Components+Responses.swift"])
        let componentHeadersSource = try XCTUnwrap(outputByName["Types+Components+Headers.swift"])
        let operationsSource = try XCTUnwrap(outputByName["Types+Operations.swift"])

        XCTAssertTrue(rootSource.contains("import OpenAPIRuntime"))
        XCTAssertTrue(componentsSource.contains("import OpenAPIRuntime"))
        XCTAssertTrue(componentSchemasSource.contains("import OpenAPIRuntime"))
        XCTAssertTrue(componentParametersSource.contains("import OpenAPIRuntime"))
        XCTAssertTrue(componentRequestBodiesSource.contains("import OpenAPIRuntime"))
        XCTAssertTrue(componentResponsesSource.contains("import OpenAPIRuntime"))
        XCTAssertTrue(componentHeadersSource.contains("import OpenAPIRuntime"))
        XCTAssertTrue(operationsSource.contains("import OpenAPIRuntime"))
        XCTAssertTrue(componentSchemasSource.contains("import struct Foundation.Date"))
        XCTAssertTrue(operationsSource.contains("import struct Foundation.Date"))

        XCTAssertTrue(rootSource.contains("protocol APIProtocol"))
        XCTAssertFalse(rootSource.contains("enum Components"))
        XCTAssertFalse(rootSource.contains("enum Operations"))

        XCTAssertTrue(componentsSource.contains("enum Components"))
        XCTAssertFalse(componentsSource.contains("enum Schemas"))
        XCTAssertFalse(componentsSource.contains("enum Parameters"))
        XCTAssertFalse(componentsSource.contains("enum RequestBodies"))
        XCTAssertFalse(componentsSource.contains("enum Responses"))
        XCTAssertFalse(componentsSource.contains("enum Headers"))
        XCTAssertFalse(componentsSource.contains("struct User"))
        XCTAssertFalse(componentsSource.contains("protocol APIProtocol"))
        XCTAssertFalse(componentsSource.contains("enum Operations"))

        XCTAssertTrue(componentSchemasSource.contains("extension Components"))
        XCTAssertTrue(componentSchemasSource.contains("enum Schemas"))
        XCTAssertTrue(componentSchemasSource.contains("struct User"))
        XCTAssertFalse(componentSchemasSource.contains("protocol APIProtocol"))
        XCTAssertFalse(componentSchemasSource.contains("enum Operations"))

        Self.assertComponentNamespaceFile(
            componentParametersSource,
            containsNamespace: "Parameters",
            excludesNamespaces: ["Schemas", "RequestBodies", "Responses", "Headers"]
        )
        Self.assertComponentNamespaceFile(
            componentRequestBodiesSource,
            containsNamespace: "RequestBodies",
            excludesNamespaces: ["Schemas", "Parameters", "Responses", "Headers"]
        )
        Self.assertComponentNamespaceFile(
            componentResponsesSource,
            containsNamespace: "Responses",
            excludesNamespaces: ["Schemas", "Parameters", "RequestBodies", "Headers"]
        )
        Self.assertComponentNamespaceFile(
            componentHeadersSource,
            containsNamespace: "Headers",
            excludesNamespaces: ["Schemas", "Parameters", "RequestBodies", "Responses"]
        )

        XCTAssertTrue(operationsSource.contains("enum Operations"))
        XCTAssertFalse(operationsSource.contains("enum Components"))
        XCTAssertFalse(operationsSource.contains("protocol APIProtocol"))
    }

    func testNamespaceSplittingIsDisabledByDefault() throws {
        let input = InMemoryInputFile(
            absolutePath: URL(string: "openapi.yaml")!,
            contents: Data(Self.source.utf8)
        )
        let diagnostics = AccumulatingDiagnosticCollector()
        let outputs = try runGenerator(
            input: input,
            config: Config(mode: .types, access: .public, namingStrategy: .defensive),
            diagnostics: diagnostics
        )

        XCTAssertEqual(diagnostics.diagnostics.count, 0)
        XCTAssertEqual(outputs.map(\.baseName), ["Types.swift"])
    }

    func testSlicesSplittingProducesRequestedNumberOfFiles() throws {
        let input = InMemoryInputFile(
            absolutePath: URL(string: "openapi.yaml")!,
            contents: Data(Self.source.utf8)
        )
        let diagnostics = AccumulatingDiagnosticCollector()
        let outputs = try runGenerator(
            input: input,
            config: Self.splitConfig(strategy: .slices, slices: .init(count: 2)),
            diagnostics: diagnostics
        )

        XCTAssertEqual(diagnostics.diagnostics.count, 0)
        XCTAssertEqual(outputs.map(\.baseName), ["Types+Slice1.swift", "Types+Slice2.swift"])

        let outputByName = Self.outputByName(outputs)
        let slice1Source = try XCTUnwrap(outputByName["Types+Slice1.swift"])
        let slice2Source = try XCTUnwrap(outputByName["Types+Slice2.swift"])

        XCTAssertTrue(slice1Source.contains("import OpenAPIRuntime"))
        XCTAssertTrue(slice2Source.contains("import OpenAPIRuntime"))

        XCTAssertTrue(slice1Source.contains("protocol APIProtocol"))
        XCTAssertFalse(slice1Source.contains("enum Components"))
        XCTAssertFalse(slice1Source.contains("enum Operations"))
        XCTAssertFalse(slice1Source.contains("struct User"))

        XCTAssertTrue(slice2Source.contains("enum Components"))
        XCTAssertTrue(slice2Source.contains("struct User"))
        XCTAssertTrue(slice2Source.contains("enum Operations"))
        XCTAssertFalse(slice2Source.contains("protocol APIProtocol"))

        let joinedSources = [slice1Source, slice2Source].joined(separator: "\n")
        XCTAssertTrue(joinedSources.contains("protocol APIProtocol"))
        XCTAssertTrue(joinedSources.contains("enum Components"))
        XCTAssertTrue(joinedSources.contains("struct User"))
        XCTAssertTrue(joinedSources.contains("enum Operations"))
    }

    func testSlicesSplittingRequiresValidCount() throws {
        let input = InMemoryInputFile(
            absolutePath: URL(string: "openapi.yaml")!,
            contents: Data(Self.source.utf8)
        )

        XCTAssertThrowsError(
            try runGenerator(
                input: input,
                config: Self.splitConfig(strategy: .slices, slices: .init(count: 0)),
                diagnostics: AccumulatingDiagnosticCollector()
            )
        ) { error in
            XCTAssertTrue(String(describing: error).contains("greater than zero"))
        }
    }

    private static func splitConfig(strategy: TypesFileSplittingStrategy) -> Config {
        splitConfig(strategy: strategy, namespace: nil, slices: nil)
    }

    private static func outputByName(_ outputs: [InMemoryOutputFile]) -> [String: String] {
        Dictionary(uniqueKeysWithValues: outputs.map { output in
            (output.baseName, String(decoding: output.contents, as: UTF8.self))
        })
    }

    private static func assertComponentNamespaceFile(
        _ source: String,
        containsNamespace namespace: String,
        excludesNamespaces excludedNamespaces: [String],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertTrue(source.contains("extension Components"), file: file, line: line)
        XCTAssertTrue(source.contains("enum \(namespace)"), file: file, line: line)
        XCTAssertFalse(source.contains("protocol APIProtocol"), file: file, line: line)
        XCTAssertFalse(source.contains("enum Operations"), file: file, line: line)
        for excludedNamespace in excludedNamespaces {
            XCTAssertFalse(source.contains("enum \(excludedNamespace)"), file: file, line: line)
        }
    }

    private static func splitConfig(
        strategy: TypesFileSplittingStrategy,
        namespace: NamespaceTypesFileSplittingOptions? = nil,
        slices: SlicesTypesFileSplittingOptions? = nil
    ) -> Config {
        .init(
            mode: .types,
            access: .public,
            namingStrategy: .defensive,
            output: .init(
                types: .init(
                    fileSplitting: .init(
                        strategy: strategy,
                        namespace: namespace,
                        slices: slices
                    )
                )
            )
        )
    }

    private static let source = """
        openapi: "3.1.0"
        info:
          title: GreetingService
          version: "1.0.0"
        paths:
          /users/{id}:
            get:
              operationId: getUser
              parameters:
                - name: id
                  in: path
                  required: true
                  schema:
                    type: string
              responses:
                "200":
                  description: A user.
                  headers:
                    X-Expires-After:
                      schema:
                        type: string
                        format: date-time
                  content:
                    application/json:
                      schema:
                        $ref: "#/components/schemas/User"
        components:
          schemas:
            User:
              type: object
              properties:
                id:
                  type: string
                createdAt:
                  type: string
                  format: date-time
              required:
                - id
        """
}
