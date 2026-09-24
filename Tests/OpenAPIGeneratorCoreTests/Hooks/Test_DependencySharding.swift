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

final class Test_DependencySharding: XCTestCase {

    func testPreservesOriginalModuleContractWithNamespaceSplitting() throws {
        let input = InMemoryInputFile(
            absolutePath: URL(string: "openapi.yaml")!,
            contents: Data(Self.source.utf8)
        )
        let config = Config(
            mode: .types,
            access: .public,
            namingStrategy: .defensive,
            sharding: .init(
                typeShardCounts: [2, 1],
                maxFilesPerShard: 2,
                maxFilesPerShardOps: 2,
                operationLayerShardCounts: [2, 1],
                modulePrefix: "NetworkingCodegen"
            )
        )

        let first = try runGenerator(input: input, config: config, diagnostics: AccumulatingDiagnosticCollector())
        let second = try runGenerator(input: input, config: config, diagnostics: AccumulatingDiagnosticCollector())
        let outputByName = Dictionary(
            uniqueKeysWithValues: first.map { ($0.baseName, String(decoding: $0.contents, as: UTF8.self)) }
        )

        XCTAssertEqual(first.map(\.baseName), second.map(\.baseName))
        XCTAssertEqual(first.map(\.contents), second.map(\.contents))
        XCTAssertNotNil(outputByName["Types_root.swift"])
        XCTAssertNotNil(outputByName["NetworkingCodegenComponents_openapi_components.swift"])
        XCTAssertNotNil(outputByName["NetworkingCodegenComponents_openapi_components_1_1.swift"])
        XCTAssertNotNil(outputByName["NetworkingCodegenTypes_L1_openapi_types_l1_1_2.swift"])
        XCTAssertNotNil(outputByName["networkingcodegenoperations_openapi_operations_l0_1_1.swift"])
        XCTAssertNotNil(outputByName["Types+Components+Parameters.swift"])
        XCTAssertNotNil(outputByName["Types+Components+RequestBodies.swift"])
        XCTAssertNotNil(outputByName["Types+Components+Responses.swift"])
        XCTAssertNotNil(outputByName["Types+Components+Headers.swift"])
        XCTAssertTrue(
            try XCTUnwrap(outputByName["Types_root.swift"])
                .contains("@_exported import NetworkingCodegenComponents_1")
        )
        XCTAssertTrue(
            try XCTUnwrap(outputByName["networkingcodegenoperations_openapi_operations_l1_1_1.swift"])
                .contains("\nimport NetworkingCodegenComponents_1\n")
        )
        XCTAssertFalse(
            try XCTUnwrap(outputByName["networkingcodegenoperations_openapi_operations_l1_1_1.swift"])
                .contains("public import NetworkingCodegenComponents_1")
        )
        XCTAssertFalse(
            try XCTUnwrap(outputByName["networkingcodegenoperations_openapi_operations_l1_1_1.swift"])
                .contains("NetworkingCodegenComponentsNamespaces")
        )
        XCTAssertFalse(
            try XCTUnwrap(outputByName["Types_root.swift"])
                .contains("NetworkingCodegenComponentsNamespaces")
        )
        XCTAssertNil(outputByName["Types+Components+Parameters+Layer1.swift"])
    }

    private static let source = """
        openapi: "3.1.0"
        info:
          title: DependencySharding
          version: "1.0.0"
        paths:
          /things:
            get:
              operationId: getThing
              parameters:
                - $ref: "#/components/parameters/ThingID"
              responses:
                "200":
                  $ref: "#/components/responses/ThingResponse"
        components:
          schemas:
            Base:
              type: object
              properties:
                id:
                  type: string
            Thing:
              type: object
              properties:
                base:
                  $ref: "#/components/schemas/Base"
          parameters:
            ThingID:
              name: id
              in: query
              schema:
                type: string
          responses:
            ThingResponse:
              description: A thing.
              content:
                application/json:
                  schema:
                    $ref: "#/components/schemas/Thing"
        """
}
