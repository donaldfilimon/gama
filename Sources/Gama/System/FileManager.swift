import Foundation

/// A unified file manager that provides async file I/O operations.
///
/// This provides a platform-agnostic interface for file operations using
/// Swift 6 structured concurrency.
///
/// Swift 6.2: Enhanced with region-based isolation and typed throws
public actor FileManager: @unchecked Sendable {
    /// Shared instance of the file manager
    public static let shared = FileManager()
    
    private init() {}
    
    /// Reads the contents of a file asynchronously.
    ///
    /// - Parameter path: The path to the file to read.
    /// - Returns: The contents of the file as Data.
    /// - Throws: An error if the file cannot be read.
    public func readFile(at path: String) async throws -> Data {
        let url = URL(fileURLWithPath: path)
        return try Data(contentsOf: url)
    }
    
    /// Writes data to a file asynchronously.
    ///
    /// - Parameters:
    ///   - data: The data to write.
    ///   - path: The path where to write the file.
    /// - Throws: An error if the file cannot be written.
    public func writeFile(_ data: Data, to path: String) async throws {
        let url = URL(fileURLWithPath: path)
        try data.write(to: url)
    }
    
    /// Reads the contents of a file as a string asynchronously.
    ///
    /// - Parameters:
    ///   - path: The path to the file to read.
    ///   - encoding: The string encoding to use. Defaults to UTF-8.
    /// - Returns: The contents of the file as a String.
    /// - Throws: An error if the file cannot be read or decoded.
    public func readString(at path: String, encoding: String.Encoding = .utf8) async throws -> String {
        let data = try await readFile(at: path)
        guard let string = String(data: data, encoding: encoding) else {
            throw FileError.encodingFailed
        }
        return string
    }
    
    /// Writes a string to a file asynchronously.
    ///
    /// - Parameters:
    ///   - string: The string to write.
    ///   - path: The path where to write the file.
    ///   - encoding: The string encoding to use. Defaults to UTF-8.
    /// - Throws: An error if the string cannot be encoded or written.
    public func writeString(_ string: String, to path: String, encoding: String.Encoding = .utf8) async throws {
        guard let data = string.data(using: encoding) else {
            throw FileError.encodingFailed
        }
        try await writeFile(data, to: path)
    }
    
    /// Checks if a file or directory exists at the given path.
    ///
    /// - Parameter path: The path to check.
    /// - Returns: `true` if the path exists; otherwise, `false`.
    public func fileExists(at path: String) -> Bool {
        let url = URL(fileURLWithPath: path)
        return Foundation.FileManager.default.fileExists(atPath: url.path)
    }
    
    /// Creates a directory at the specified path.
    ///
    /// - Parameters:
    ///   - path: The path where to create the directory.
    ///   - createIntermediates: If `true`, creates intermediate directories as needed.
    /// - Throws: An error if the directory cannot be created.
    public func createDirectory(at path: String, createIntermediates: Bool = true) async throws {
        let url = URL(fileURLWithPath: path)
        try Foundation.FileManager.default.createDirectory(
            at: url,
            withIntermediateDirectories: createIntermediates,
            attributes: nil
        )
    }
    
    /// Removes a file or directory at the specified path.
    ///
    /// - Parameter path: The path to remove.
    /// - Throws: An error if the path cannot be removed.
    public func removeItem(at path: String) async throws {
        let url = URL(fileURLWithPath: path)
        try Foundation.FileManager.default.removeItem(at: url)
    }
    
    /// Lists the contents of a directory.
    ///
    /// - Parameter path: The path of the directory to list.
    /// - Returns: An array of filenames in the directory.
    /// - Throws: An error if the directory cannot be read.
    public func contentsOfDirectory(at path: String) async throws -> [String] {
        let url = URL(fileURLWithPath: path)
        let contents = try Foundation.FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: nil,
            options: []
        )
        return contents.map { $0.lastPathComponent }
    }
}

/// File operation errors
/// Swift 6.2: Enhanced with typed throws support
public enum FileError: Error, @retroactive Sendable {
    case fileNotFound
    case encodingFailed
    case permissionDenied
    case invalidPath
    case unknown(any Error)
    
    // Swift 6.2: Typed error information
    public var underlyingError: (any Error)? {
        if case .unknown(let error) = self {
            return error
        }
        return nil
    }
}