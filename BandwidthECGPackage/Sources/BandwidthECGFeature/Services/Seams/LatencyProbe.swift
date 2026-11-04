import Foundation

/// Measures one round trip to the internet and returns its duration in seconds.
/// Throws when the request fails or times out.
public protocol LatencyProbe: Sendable {
    func measureSeconds() async throws -> TimeInterval
}

/// Sends an HTTP HEAD request to https://www.apple.com (10 second timeout) and times it.
public struct HTTPHeadProbe: LatencyProbe {
    public init() {}

    public func measureSeconds() async throws -> TimeInterval {
        guard let url = URL(string: "https://www.apple.com") else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        request.timeoutInterval = 10

        let start = ContinuousClock.now
        _ = try await URLSession.shared.data(for: request)
        let elapsed = ContinuousClock.now - start
        return Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
    }
}
