import Foundation
@testable import SplouchCore

/// A scripted HTTP server behind `URLProtocol`, for the REST client and the
/// models above it. Routes are matched on path; the query is available to the
/// handler.
final class StubServer: @unchecked Sendable {
    struct Response {
        var status: Int = 200
        var body: Data = Data()
        var headers: [String: String] = [:]

        static func json(_ text: String, status: Int = 200, headers: [String: String] = [:]) -> Response {
            Response(status: status, body: Data(text.utf8), headers: ["Content-Type": "application/json"].merging(headers) { $1 })
        }
    }

    typealias Handler = @Sendable (URLRequest) -> Response

    private let lock = NSLock()
    private var routes: [String: Handler] = [:]
    private var log: [URLRequest] = []

    let session: URLSession
    /// Unique per instance: suites run in parallel and each stub owns its routes.
    let host: String
    let address: ServerAddress

    init() {
        host = "stub-\(UUID().uuidString.lowercased().prefix(8)).test"
        address = ServerAddress(typed: "https://\(host)")!
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubProtocol.self]
        session = URLSession(configuration: config)
        StubProtocol.register(self, host: host)
    }

    deinit { StubProtocol.unregister(host: host) }

    func route(_ path: String, _ handler: @escaping Handler) {
        lock.withLock { routes[path] = handler }
    }

    func route(_ path: String, json: String, status: Int = 200, headers: [String: String] = [:]) {
        route(path) { _ in .json(json, status: status, headers: headers) }
    }

    var requests: [URLRequest] { lock.withLock { log } }
    func requestCount(_ path: String) -> Int { requests.filter { $0.url?.path == path }.count }

    fileprivate func respond(_ request: URLRequest) -> Response {
        lock.withLock {
            log.append(request)
            guard let path = request.url?.path, let h = routes[path] else { return Response(status: 404) }
            return h(request)
        }
    }
}

final class StubProtocol: URLProtocol {
    nonisolated(unsafe) private static var servers: [String: StubServer] = [:]
    private static let lock = NSLock()

    static func register(_ server: StubServer, host: String) { lock.withLock { servers[host] = server } }
    static func unregister(host: String) { lock.withLock { servers[host] = nil } }

    override class func canInit(with request: URLRequest) -> Bool {
        guard let host = request.url?.host else { return false }
        return lock.withLock { servers[host] != nil }
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let host = request.url?.host, let server = Self.lock.withLock({ Self.servers[host] }) else {
            client?.urlProtocol(self, didFailWithError: URLError(.cannotFindHost))
            return
        }
        let r = server.respond(request)
        let http = HTTPURLResponse(url: request.url!, statusCode: r.status, httpVersion: "HTTP/1.1", headerFields: r.headers)!
        client?.urlProtocol(self, didReceive: http, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: r.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
