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

/// A strategy for turning OpenAPI identifiers into Swift identifiers.
public enum NamingStrategy: String, Sendable, Codable, Equatable, CaseIterable {

    /// A defensive strategy that can handle any OpenAPI identifier and produce a non-conflicting Swift identifier.
    ///
    /// Introduced in [SOAR-0001](https://swiftpackageindex.com/apple/swift-openapi-generator/documentation/swift-openapi-generator/soar-0001).
    case defensive

    /// An idiomatic strategy that produces Swift identifiers that more likely conform to Swift conventions.
    ///
    /// Introduced in [SOAR-0013](https://swiftpackageindex.com/apple/swift-openapi-generator/documentation/swift-openapi-generator/soar-0013).
    case idiomatic
}

/// Configuration for balancing dependency-layered output into build modules.
public struct ShardingConfig: Sendable, Codable, Equatable {
    /// The number of independently compiled schema shards in each dependency layer.
    public var typeShardCounts: [Int]

    /// The maximum number of generated Swift files emitted for one schema shard.
    public var maxFilesPerShard: Int

    /// The maximum number of generated Swift files emitted for one operation shard.
    public var maxFilesPerShardOps: Int

    /// The number of independently compiled operation shards in each dependency layer.
    public var operationLayerShardCounts: [Int]

    /// An optional consumer module prefix retained for compatibility with the original sharding configuration.
    public var modulePrefix: String?

    /// The number of dependency layers represented by this configuration.
    public var layerCount: Int { typeShardCounts.count }

    /// Creates a dependency-layered sharding configuration.
    /// - Parameters:
    ///   - typeShardCounts: The number of independently compiled schema shards in each dependency layer.
    ///   - maxFilesPerShard: The maximum number of generated Swift files emitted for one schema shard.
    ///   - maxFilesPerShardOps: The maximum number of generated Swift files emitted for one operation shard.
    ///   - operationLayerShardCounts: The number of independently compiled operation shards in each dependency layer.
    ///   - modulePrefix: An optional consumer module prefix retained for compatibility with the original sharding configuration.
    public init(
        typeShardCounts: [Int],
        maxFilesPerShard: Int = 25,
        maxFilesPerShardOps: Int = 16,
        operationLayerShardCounts: [Int],
        modulePrefix: String? = nil
    ) {
        self.typeShardCounts = typeShardCounts
        self.maxFilesPerShard = maxFilesPerShard
        self.maxFilesPerShardOps = maxFilesPerShardOps
        self.operationLayerShardCounts = operationLayerShardCounts
        self.modulePrefix = modulePrefix
    }

    /// An error describing an invalid dependency-layered sharding configuration.
    public enum ValidationError: Error, CustomStringConvertible {
        /// A sharding configuration field contains a nonpositive value.
        case nonPositiveValue(field: String, value: Int)

        /// The operation and schema layer configurations contain different numbers of layers.
        case shardCountMismatch(expected: Int, actual: Int)

        /// A human-readable description of the invalid configuration.
        public var description: String {
            switch self {
            case .nonPositiveValue(let field, let value): return "\(field) must be greater than zero, got \(value)."
            case .shardCountMismatch(let expected, let actual):
                return "operationLayerShardCounts must contain \(expected) entries, got \(actual)."
            }
        }
    }

    /// Validates that every shard count and file limit is positive and both layer configurations have equal lengths.
    public func validate() throws {
        for (index, count) in typeShardCounts.enumerated() where count <= 0 {
            throw ValidationError.nonPositiveValue(field: "typeShardCounts[\(index)]", value: count)
        }
        guard !typeShardCounts.isEmpty else {
            throw ValidationError.nonPositiveValue(field: "typeShardCounts.count", value: 0)
        }
        guard maxFilesPerShard > 0 else {
            throw ValidationError.nonPositiveValue(field: "maxFilesPerShard", value: maxFilesPerShard)
        }
        guard maxFilesPerShardOps > 0 else {
            throw ValidationError.nonPositiveValue(field: "maxFilesPerShardOps", value: maxFilesPerShardOps)
        }
        for (index, count) in operationLayerShardCounts.enumerated() where count <= 0 {
            throw ValidationError.nonPositiveValue(field: "operationLayerShardCounts[\(index)]", value: count)
        }
        guard operationLayerShardCounts.count == typeShardCounts.count else {
            throw ValidationError.shardCountMismatch(
                expected: typeShardCounts.count,
                actual: operationLayerShardCounts.count
            )
        }
    }
}

/// A structure that contains configuration options for a single execution
/// of the generator pipeline run.
///
/// A single generator pipeline run produces the files associated with one
/// generator mode.
public struct Config: Sendable {

    /// The generator mode to use.
    public var mode: GeneratorMode

    /// The access modifier to use for generated declarations.
    public var access: AccessModifier

    /// The default access modifier.
    public static let defaultAccessModifier: AccessModifier = .internal

    /// Additional imports to add to each generated file.
    public var additionalImports: [String]

    /// Additional comments to add to the top of each generated file.
    public var additionalFileComments: [String]

    /// Filter to apply to the OpenAPI document before generation.
    public var filter: DocumentFilter?

    /// The naming strategy to use for deriving Swift identifiers from OpenAPI identifiers.
    ///
    /// Defaults to `defensive`.
    public var namingStrategy: NamingStrategy

    /// The default naming strategy.
    public static let defaultNamingStrategy: NamingStrategy = .defensive

    /// A map of OpenAPI identifiers to desired Swift identifiers, used instead of the naming strategy.
    public var nameOverrides: [String: String]
    /// A map of OpenAPI schema names to desired custom type names.
    public var typeOverrides: TypeOverrides

    /// Additional pre-release features to enable.
    public var featureFlags: FeatureFlags

    /// Optional build-oriented balancing for dependency-layered types output.
    public var sharding: ShardingConfig?

    /// Creates a configuration with the specified generator mode and imports.
    /// - Parameters:
    ///   - mode: The mode to use for generation.
    ///   - access: The access modifier to use for generated declarations.
    ///   - additionalImports: Additional imports to add to each generated file.
    ///   - additionalFileComments: Additional comments to add to the top of each generated file.
    ///   - filter: Filter to apply to the OpenAPI document before generation.
    ///   - namingStrategy: The naming strategy to use for deriving Swift identifiers from OpenAPI identifiers.
    ///     Defaults to `defensive`.
    ///   - nameOverrides: A map of OpenAPI identifiers to desired Swift identifiers, used instead
    ///     of the naming strategy.
    ///   - typeOverrides: A map of OpenAPI schema names to desired custom type names.
    ///   - featureFlags: Additional pre-release features to enable.
    ///   - sharding: Optional build-oriented balancing for dependency-layered types output.
    public init(
        mode: GeneratorMode,
        access: AccessModifier,
        additionalImports: [String] = [],
        additionalFileComments: [String] = [],
        filter: DocumentFilter? = nil,
        namingStrategy: NamingStrategy,
        nameOverrides: [String: String] = [:],
        typeOverrides: TypeOverrides = .init(),
        featureFlags: FeatureFlags = [],
        sharding: ShardingConfig? = nil
    ) {
        self.mode = mode
        self.access = access
        self.additionalImports = additionalImports
        self.additionalFileComments = additionalFileComments
        self.filter = filter
        self.namingStrategy = namingStrategy
        self.nameOverrides = nameOverrides
        self.typeOverrides = typeOverrides
        self.featureFlags = featureFlags
        self.sharding = sharding
    }
}
