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

/// Configuration for generated output files.
public struct OutputOptions: Sendable, Codable, Equatable {

    /// Options that only affect `Types.swift` generation.
    public var types: TypesOutputOptions?

    /// Creates output options.
    /// - Parameter types: Options that only affect `Types.swift` generation.
    public init(types: TypesOutputOptions? = nil) { self.types = types }
}

/// Configuration for generated types output files.
public struct TypesOutputOptions: Sendable, Codable, Equatable {

    /// Optional configuration for splitting generated types across files.
    public var fileSplitting: TypesFileSplittingConfig?

    /// Creates types output options.
    /// - Parameter fileSplitting: Optional configuration for splitting generated types across files.
    public init(fileSplitting: TypesFileSplittingConfig? = nil) { self.fileSplitting = fileSplitting }
}

/// Configuration for splitting generated types across files.
public struct TypesFileSplittingConfig: Sendable, Codable, Equatable {

    /// The strategy to use when splitting generated types across files.
    public var strategy: TypesFileSplittingStrategy

    /// Options for the namespace file splitting strategy.
    public var namespace: NamespaceTypesFileSplittingOptions?

    /// Options for the slices file splitting strategy.
    public var slices: SlicesTypesFileSplittingOptions?

    /// Creates a file splitting configuration.
    /// - Parameters:
    ///   - strategy: The strategy to use when splitting generated types across files.
    ///   - namespace: Options for the namespace file splitting strategy.
    ///   - slices: Options for the slices file splitting strategy.
    public init(
        strategy: TypesFileSplittingStrategy,
        namespace: NamespaceTypesFileSplittingOptions? = nil,
        slices: SlicesTypesFileSplittingOptions? = nil
    ) {
        self.strategy = strategy
        self.namespace = namespace
        self.slices = slices
    }
}

/// Options for the namespace file splitting strategy.
public struct NamespaceTypesFileSplittingOptions: Sendable, Codable, Equatable {

    /// The namespace depth to split.
    public var depth: NamespaceTypesFileSplittingDepth

    /// Creates namespace file splitting options.
    /// - Parameter depth: The namespace depth to split.
    public init(depth: NamespaceTypesFileSplittingDepth = .one) { self.depth = depth }
}

/// The namespace depth to split.
public enum NamespaceTypesFileSplittingDepth: Int, Sendable, Codable, Equatable {

    /// Split first-level namespaces into separate files.
    case one = 1

    /// Split first-level namespaces and supported second-level namespaces into separate files.
    case two = 2

    /// Creates a namespace file splitting depth by decoding an integer raw value.
    /// Unsupported values default to the first supported depth.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(Int.self)
        self = Self(rawValue: rawValue) ?? .one
    }

    /// Encodes the namespace file splitting depth as its integer raw value.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

/// Options for the slices file splitting strategy.
public struct SlicesTypesFileSplittingOptions: Sendable, Codable, Equatable {

    /// The requested number of similarly sized files.
    public var count: Int

    /// Creates slices file splitting options.
    /// - Parameter count: The requested number of similarly sized files.
    public init(count: Int) { self.count = count }
}

/// A strategy for splitting generated types across files.
public enum TypesFileSplittingStrategy: String, Sendable, Codable, Equatable, CaseIterable {

    /// Splits generated types into files by namespace.
    case namespace

    /// Splits generated types into a requested number of similarly sized files.
    case slices
}

extension TypesFileSplittingConfig {

    /// Returns the Swift output file names emitted by the configuration.
    /// - Parameter primaryTypesFileName: The file name for the primary generated types file.
    /// - Returns: The emitted Swift output file names.
    public func outputFileNames(primaryTypesFileName: String) -> [String] {
        switch strategy {
        case .namespace:
            let depth1Files = [
                primaryTypesFileName,
                GeneratorMode.outputFileName(primaryTypesFileName, "Components"),
                GeneratorMode.outputFileName(primaryTypesFileName, "Operations"),
            ]
            let depth2Files = [
                GeneratorMode.outputFileName(primaryTypesFileName, "Components", "Schemas"),
                GeneratorMode.outputFileName(primaryTypesFileName, "Components", "Parameters"),
                GeneratorMode.outputFileName(primaryTypesFileName, "Components", "RequestBodies"),
                GeneratorMode.outputFileName(primaryTypesFileName, "Components", "Responses"),
                GeneratorMode.outputFileName(primaryTypesFileName, "Components", "Headers"),
            ]
            return depth1Files + (namespace?.depth == .two ? depth2Files : [])
        case .slices:
            guard let count = slices?.count, count > 0 else { return [] }
            return (1...count).map { index in
                GeneratorMode.outputFileName(primaryTypesFileName, "Slice\(index)")
            }
        }
    }
}
