import XCTest
@testable import ChezmoiCore

private final class ResponseStub: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        XCTAssertEqual(request.url?.absoluteString, "https://api.openai.com/v1/responses")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer unit-test-placeholder")
        var data = request.httpBody
        if data == nil, let stream = request.httpBodyStream {
            stream.open(); defer { stream.close() }
            var accumulated = Data()
            var buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let count = stream.read(&buffer, maxLength: buffer.count)
                if count <= 0 { break }
                accumulated.append(buffer, count: count)
            }
            data = accumulated
        }
        do {
            let body = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(data)) as? [String: Any])
            XCTAssertEqual(body["store"] as? Bool, false)
            let model = body["model"] as? String
            XCTAssertTrue(["test-model", "gpt-6-luna"].contains(model ?? ""))
            if model == "gpt-6-luna" {
                XCTAssertEqual((body["reasoning"] as? [String: String])?["effort"], "low")
            } else { XCTAssertNil(body["reasoning"]) }
            let format = (body["text"] as? [String: Any])?["format"] as? [String: Any]
            XCTAssertEqual(format?["type"] as? String, "json_schema")
            XCTAssertEqual(format?["strict"] as? Bool, true)
            let messages = try XCTUnwrap(body["input"] as? [[String: String]])
            let conflict = try JSONDecoder().decode(Conflict.self, from: Data(XCTUnwrap(messages.last?["content"]).utf8))
            XCTAssertEqual(conflict.base, "base\n")
            XCTAssertEqual(conflict.local, "local\n")
            XCTAssertEqual(conflict.remote, "remote\n")
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil,
                                           headerFields: ["Content-Type": "application/json"])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data(#"{"status":"completed","output":[{"type":"message","content":[{"type":"output_text","text":"{\"resolved\":true,\"summary\":\"ok\",\"content\":\"merged\\n\"}"}]}]}"#.utf8))
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}

@MainActor
final class OpenAIRequestTests: XCTestCase {
    func testLunaUsesLowReasoningWithoutNetwork() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [ResponseStub.self]
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }
        let resolver = OpenAIResolver(key: "unit-test-placeholder", model: "gpt-6-luna", session: session)
        let resolution = try await resolver.resolve(Conflict(path: "dot_test", base: "base\n", local: "local\n", remote: "remote\n"))
        XCTAssertEqual(resolution.content, "merged\n")
    }
    func testResponsesAPIRequestAndParsingWithoutNetwork() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [ResponseStub.self]
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }
        let resolver = OpenAIResolver(key: "unit-test-placeholder", model: "test-model", session: session)
        let resolution = try await resolver.resolve(Conflict(path: "dot_test", base: "base\n", local: "local\n", remote: "remote\n"))
        XCTAssertEqual(resolution.content, "merged\n")
    }
}
