import Foundation
import Network
import XCTest
@testable import Carina

/// Real loopback HTTP fixture: no external destination or real user content.
private final class RedirectFixture {
    let process = Process()
    let input = Pipe()
    let output = Pipe()
    let origin: URL
    let receiver: URL

    init(status: Int) throws {
        process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        process.arguments = ["-u", "-c", #"""
import json, sys, threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
seen = []
class Receiver(BaseHTTPRequestHandler):
    def do_GET(self): self.receive()
    def do_POST(self): self.receive()
    def receive(self):
        body = self.rfile.read(int(self.headers.get('Content-Length', '0')))
        seen.append({'body_received': bool(body)})
        self.send_response(200); self.send_header('Content-Length', '3'); self.end_headers(); self.wfile.write(b'ok\n')
    def log_message(self, *args): pass
sink = ThreadingHTTPServer(('127.0.0.1', 0), Receiver)
class Origin(BaseHTTPRequestHandler):
    def do_GET(self): self.redirect()
    def do_POST(self): self.redirect()
    def redirect(self):
        self.rfile.read(int(self.headers.get('Content-Length', '0')))
        self.send_response(int(sys.argv[1]))
        self.send_header('Location', 'http://127.0.0.1:%d/sink' % sink.server_port)
        self.send_header('Content-Length', '0'); self.end_headers()
    def log_message(self, *args): pass
source = ThreadingHTTPServer(('127.0.0.1', 0), Origin)
for server in (source, sink):
    threading.Thread(target=server.serve_forever, daemon=True).start()
print(json.dumps({'origin': source.server_port, 'receiver': sink.server_port}), flush=True)
for line in sys.stdin:
    print(json.dumps({'requests': len(seen), 'bodies': sum(x['body_received'] for x in seen)}), flush=True)
"""#, String(status)]
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        try process.run()
        let ports = try Self.readLine(output.fileHandleForReading)
        origin = URL(string: "http://127.0.0.1:\(ports["origin"]!)/api/generate")!
        receiver = URL(string: "http://127.0.0.1:\(ports["receiver"]!)/sink")!
    }

    private static func readLine(_ handle: FileHandle) throws -> [String: Int] {
        var bytes = Data()
        while true {
            let byte = handle.readData(ofLength: 1)
            guard !byte.isEmpty else { throw URLError(.cannotConnectToHost) }
            if byte == Data([10]) { break }
            bytes.append(byte)
        }
        return try JSONDecoder().decode([String: Int].self, from: bytes)
    }

    func counts() throws -> [String: Int] {
        input.fileHandleForWriting.write(Data("counts\n".utf8))
        return try Self.readLine(output.fileHandleForReading)
    }

    deinit {
        try? input.fileHandleForWriting.close()
        if process.isRunning { process.terminate() }
        process.waitUntilExit()
    }
}

final class OllamaNetworkTests: XCTestCase {
    func testProductionSessionClearsExplicitProxyConfiguration() {
        let config = URLSessionConfiguration.ephemeral
        config.connectionProxyDictionary = ["HTTPEnable": 1, "HTTPProxy": "example.invalid", "HTTPPort": 8080]
        if #available(macOS 14.0, *) {
            config.proxyConfigurations = [ProxyConfiguration(httpCONNECTProxy:
                .hostPort(host: "127.0.0.1", port: 9999))]
        }
        let original = URLSession(configuration: config)
        defer { original.invalidateAndCancel() }
        let guarded = OllamaTransport.makeSession(copying: original)
        defer { guarded.invalidateAndCancel() }
        XCTAssertTrue(guarded.configuration.connectionProxyDictionary?.isEmpty == true)
        if #available(macOS 14.0, *) {
            XCTAssertTrue(guarded.configuration.proxyConfigurations.isEmpty)
        }
        XCTAssertTrue(guarded.delegate is OllamaRedirectGuard)
    }

    func testReceiverDetectsSyntheticBodyWithoutRedirect() async throws {
        let fixture = try RedirectFixture(status: 307)
        let session = OllamaTransport.makeSession()
        defer { session.invalidateAndCancel() }
        var request = URLRequest(url: fixture.receiver, timeoutInterval: 5)
        request.httpMethod = "POST"
        request.httpBody = Data("synthetic-review-canary".utf8)
        _ = try await session.data(for: request)
        XCTAssertEqual(try fixture.counts(), ["requests": 1, "bodies": 1])
    }

    func test307And308NeverDeliverRequestOrBodyToSecondOrigin() async throws {
        for code in [307, 308] {
            let fixture = try RedirectFixture(status: code)
            let session = OllamaTransport.makeSession()
            defer { session.invalidateAndCancel() }
            let healthRequest = URLRequest(url: fixture.origin, timeoutInterval: 5)
            let (_, healthResponse) = try await session.data(for: healthRequest)
            XCTAssertEqual((healthResponse as? HTTPURLResponse)?.statusCode, code)
            var request = URLRequest(url: fixture.origin, timeoutInterval: 5)
            request.httpMethod = "POST"
            request.httpBody = Data("synthetic-review-canary".utf8)
            let (bytes, response) = try await session.bytes(for: request)
            for try await _ in bytes { }
            XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, code)
            XCTAssertEqual(try fixture.counts(), ["requests": 0, "bodies": 0])
        }
    }
}
