import Foundation

/// A unified network client that provides async HTTP operations.
///
/// This provides a platform-agnostic interface for network operations using
/// Swift 6 structured concurrency.
public actor NetworkClient {
    /// Shared instance of the network client
    public static let shared = NetworkClient()
    
    private let session: URLSession
    
    private init() {
        let configuration = URLSessionConfiguration.default
        self.session = URLSession(configuration: configuration)
    }
    
    /// Performs an HTTP GET request.
    ///
    /// - Parameter url: The URL to request.
    /// - Returns: The HTTP response and data.
    /// - Throws: An error if the request fails.
    public func get(_ url: URL) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(from: url)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NetworkError.invalidResponse
        }
        return (data, httpResponse)
    }
    
    /// Performs an HTTP POST request.
    ///
    /// - Parameters:
    ///   - url: The URL to request.
    ///   - body: The request body data.
    /// - Returns: The HTTP response and data.
    /// - Throws: An error if the request fails.
    public func post(_ url: URL, body: Data) async throws -> (Data, HTTPURLResponse) {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NetworkError.invalidResponse
        }
        return (data, httpResponse)
    }
    
    /// Downloads data from a URL with progress tracking.
    ///
    /// - Parameter url: The URL to download from.
    /// - Returns: An async stream of download progress and data.
    public func download(_ url: URL) -> AsyncThrowingStream<DownloadProgress, Error> {
        AsyncThrowingStream { continuation in
            let task = session.downloadTask(with: url) { localURL, response, error in
                if let error = error {
                    continuation.finish(throwing: error)
                    return
                }
                
                guard let localURL = localURL,
                      let httpResponse = response as? HTTPURLResponse else {
                    continuation.finish(throwing: NetworkError.invalidResponse)
                    return
                }
                
                do {
                    let data = try Data(contentsOf: localURL)
                    continuation.yield(DownloadProgress(
                        bytesReceived: Int64(data.count),
                        totalBytes: httpResponse.expectedContentLength,
                        data: data,
                        completed: true
                    ))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            
            task.resume()
            
            continuation.onTermination = { @Sendable _ in
                task.cancel()
            }
        }
    }
}

/// Download progress information
public struct DownloadProgress: Sendable {
    public let bytesReceived: Int64
    public let totalBytes: Int64
    public let data: Data?
    public let completed: Bool
    
    public var progress: Double {
        guard totalBytes > 0 else { return 0 }
        return Double(bytesReceived) / Double(totalBytes)
    }
}

/// Network operation errors
public enum NetworkError: Error, Sendable {
    case invalidURL
    case invalidResponse
    case httpError(statusCode: Int)
    case requestFailed(Error)
    case noData
}