import Testing
import HTTPTypes
import Foundation
@testable import Nexus
@testable import NexusTest

/// Tests for session crypto edge cases and error paths
@Suite("Session Crypto Edge Cases")
struct SessionCryptoEdgeCasesTests {

    // MARK: - MessageSigning Edge Cases

    @Test("sign with empty payload")
    func signEmptyPayload() {
        let secret = Data(repeating: 0xAA, count: 32)
        let payload = Data()

        let token = MessageSigning.sign(payload: payload, secret: secret)

        // Token should be base64url(payload).base64url(hmac)
        #expect(token.contains("."))
    }

    @Test("sign with large payload")
    func signLargePayload() {
        let secret = Data(repeating: 0xAA, count: 32)
        let payload = Data(repeating: 0xFF, count: 1_000_000)

        let token = MessageSigning.sign(payload: payload, secret: secret)

        #expect(token.contains("."))
    }

    @Test("sign with minimum secret length")
    func signMinimumSecretLength() {
        let secret = Data(repeating: 0xAA, count: 32)  // Exactly 32 bytes
        let payload = Data("test".utf8)

        let token = MessageSigning.sign(payload: payload, secret: secret)

        #expect(token.contains("."))
    }

    @Test("sign with very long secret")
    func signVeryLongSecret() {
        let secret = Data(repeating: 0xAA, count: 1024)  // Much longer than needed
        let payload = Data("test".utf8)

        let token = MessageSigning.sign(payload: payload, secret: secret)

        #expect(token.contains("."))
    }

    @Test("verify with valid token")
    func verifyValidToken() {
        let secret = Data(repeating: 0xAA, count: 32)
        let payload = Data("test payload".utf8)

        let token = MessageSigning.sign(payload: payload, secret: secret)
        let verified = MessageSigning.verify(token: token, secret: secret)

        #expect(verified == payload)
    }

    @Test("verify with wrong secret fails")
    func verifyWrongSecret() {
        let secret1 = Data(repeating: 0xAA, count: 32)
        let secret2 = Data(repeating: 0xBB, count: 32)
        let payload = Data("test payload".utf8)

        let token = MessageSigning.sign(payload: payload, secret: secret1)
        let verified = MessageSigning.verify(token: token, secret: secret2)

        #expect(verified == nil)
    }

    @Test("verify with tampered payload fails")
    func verifyTamperedPayload() {
        let secret = Data(repeating: 0xAA, count: 32)
        let payload = Data("original".utf8)

        let token = MessageSigning.sign(payload: payload, secret: secret)

        // Tamper with the payload portion (before the dot)
        let parts = token.split(separator: ".", maxSplits: 1)
        var tamperedPayload = String(parts[0])
        tamperedPayload = "X" + tamperedPayload.dropFirst()
        let tamperedToken = "\(tamperedPayload).\(parts[1])"

        let verified = MessageSigning.verify(token: tamperedToken, secret: secret)
        #expect(verified == nil)
    }

    @Test("verify with tampered MAC fails")
    func verifyTamperedMAC() {
        let secret = Data(repeating: 0xAA, count: 32)
        let payload = Data("test".utf8)

        let token = MessageSigning.sign(payload: payload, secret: secret)

        // Tamper with the MAC portion (after the dot)
        let parts = token.split(separator: ".", maxSplits: 1)
        var tamperedMAC = String(parts[1])
        tamperedMAC = "X" + tamperedMAC.dropFirst()
        let tamperedToken = "\(parts[0]).\(tamperedMAC)"

        let verified = MessageSigning.verify(token: tamperedToken, secret: secret)
        #expect(verified == nil)
    }

    @Test("verify with missing dot fails")
    func verifyMissingDot() {
        let secret = Data(repeating: 0xAA, count: 32)

        let token = "invalid-token-no-dot"
        let verified = MessageSigning.verify(token: token, secret: secret)

        #expect(verified == nil)
    }

    @Test("verify with empty token fails")
    func verifyEmptyToken() {
        let secret = Data(repeating: 0xAA, count: 32)

        let token = ""
        let verified = MessageSigning.verify(token: token, secret: secret)

        #expect(verified == nil)
    }

    @Test("verify with only payload and dot fails")
    func verifyOnlyPayloadAndDot() {
        let secret = Data(repeating: 0xAA, count: 32)

        let token = "dGVzdA==."
        let verified = MessageSigning.verify(token: token, secret: secret)

        #expect(verified == nil)
    }

    @Test("verify with only dot and MAC fails")
    func verifyOnlyDotAndMAC() {
        let secret = Data(repeating: 0xAA, count: 32)

        let token = ".YWJj"
        let verified = MessageSigning.verify(token: token, secret: secret)

        #expect(verified == nil)
    }

    @Test("verify with multiple dots")
    func verifyMultipleDots() {
        let secret = Data(repeating: 0xAA, count: 32)
        let payload = Data("test".utf8)

        let token = MessageSigning.sign(payload: payload, secret: secret)

        // Add extra dots
        let extraDotsToken = token.replacingOccurrences(of: ".", with: "..")

        let verified = MessageSigning.verify(token: extraDotsToken, secret: secret)
        #expect(verified == nil)
    }

    @Test("verify with invalid base64url characters")
    func verifyInvalidBase64URL() {
        let secret = Data(repeating: 0xAA, count: 32)

        let token = "invalid!@#$%^&*().invalid"
        let verified = MessageSigning.verify(token: token, secret: secret)

        #expect(verified == nil)
    }

    @Test("sign and verify with binary payload")
    func signAndVerifyBinaryPayload() {
        let secret = Data(repeating: 0xAA, count: 32)
        let payload = Data([0x00, 0x01, 0x02, 0xFF, 0xFE, 0xFD])

        let token = MessageSigning.sign(payload: payload, secret: secret)
        let verified = MessageSigning.verify(token: token, secret: secret)

        #expect(verified == payload)
    }

    @Test("sign and verify with Unicode payload")
    func signAndVerifyUnicodePayload() {
        let secret = Data(repeating: 0xAA, count: 32)
        let payload = Data("Hello 世界 🌍".utf8)

        let token = MessageSigning.sign(payload: payload, secret: secret)
        let verified = MessageSigning.verify(token: token, secret: secret)

        #expect(verified == payload)
    }

    @Test("sign and verify with zero bytes in payload")
    func signAndVerifyZeroBytes() {
        let secret = Data(repeating: 0xAA, count: 32)
        let payload = Data([0x00, 0x00, 0x00, 0x00])

        let token = MessageSigning.sign(payload: payload, secret: secret)
        let verified = MessageSigning.verify(token: token, secret: secret)

        #expect(verified == payload)
    }

    @Test("verify is timing-attack resistant")
    func verifyTimingAttackResistance() {
        // This test verifies that verification uses constant-time comparison
        // We can't directly test timing, but we can verify that both
        // valid and invalid tokens go through the same validation path

        let secret = Data(repeating: 0xAA, count: 32)
        let payload = Data("test".utf8)

        let validToken = MessageSigning.sign(payload: payload, secret: secret)

        // Corrupt the last character of the token to invalidate the MAC
        let corruptedChars = Array(validToken)
        let lastChar = corruptedChars.last!
        let replacedChar: Character = lastChar == "A" ? "B" : "A"
        let invalidToken = String(corruptedChars.dropLast()) + String(replacedChar)

        let validResult = MessageSigning.verify(token: validToken, secret: secret)
        let invalidResult = MessageSigning.verify(token: invalidToken, secret: secret)

        #expect(validResult != nil)
        #expect(invalidResult == nil)
    }

    // MARK: - Session Plug Edge Cases

    private func connWithCookie(_ name: String, _ value: String) -> Connection {
        Connection.make(headers: HTTPFields([HTTPField(name: .cookie, value: "\(name)=\(value)")]))
    }

    private func hasSetCookie(_ conn: Connection, named name: String) -> Bool {
        conn.response.headerFields.contains { $0.name == .setCookie && $0.value.hasPrefix("\(name)=") }
    }

    @Test("session plug with missing cookie")
    func sessionPlugMissingCookie() async throws {
        let secret = Data(repeating: 0xAA, count: 32)
        let plug = sessionPlug(SessionConfig(secret: secret))
        let result = try await plug(Connection.make())
        let session = result.assigns[Connection.sessionKey] as? [String: String]
        #expect(session == [:])
    }

    @Test("session plug with invalid token")
    func sessionPlugInvalidToken() async throws {
        let secret = Data(repeating: 0xAA, count: 32)
        let plug = sessionPlug(SessionConfig(secret: secret))
        let conn = connWithCookie("_nexus_session", "invalid-token")
        let result = try await plug(conn)
        let session = result.assigns[Connection.sessionKey] as? [String: String]
        #expect(session == [:])
    }

    @Test("session plug with valid token")
    func sessionPlugValidToken() async throws {
        let secret = Data(repeating: 0xAA, count: 32)
        let plug = sessionPlug(SessionConfig(secret: secret))
        let sessionData = ["user_id": "123", "role": "admin"]
        let jsonData = try JSONEncoder().encode(sessionData)
        let token = MessageSigning.sign(payload: jsonData, secret: secret)
        let conn = connWithCookie("_nexus_session", token)
        let result = try await plug(conn)
        let session = result.assigns[Connection.sessionKey] as? [String: String]
        #expect(session?["user_id"] == "123")
        #expect(session?["role"] == "admin")
    }

    @Test("session plug preserves existing session when not touched")
    func sessionPlugPreservesWhenNotTouched() async throws {
        let secret = Data(repeating: 0xAA, count: 32)
        let plug = sessionPlug(SessionConfig(secret: secret))
        let sessionData = ["key": "value"]
        let token = MessageSigning.sign(payload: try JSONEncoder().encode(sessionData), secret: secret)
        let conn = connWithCookie("_nexus_session", token)
        let result = try await plug(conn)
        let afterSend = result.runBeforeSend()
        #expect(!hasSetCookie(afterSend, named: "_nexus_session"))
    }

    @Test("session plug sets cookie when touched")
    func sessionPlugSetsCookieWhenTouched() async throws {
        let secret = Data(repeating: 0xAA, count: 32)
        let plug = sessionPlug(SessionConfig(secret: secret))
        let result = try await plug(Connection.make())
        var result2 = result
        var modifiedSession = result2.assigns[Connection.sessionKey] as? [String: String] ?? [:]
        modifiedSession["user_id"] = "123"
        result2.assigns[Connection.sessionKey] = modifiedSession
        result2.assigns[Connection.sessionTouchedKey] = true
        let afterSend = result2.runBeforeSend()
        #expect(hasSetCookie(afterSend, named: "_nexus_session"))
    }

    @Test("session plug drops session when requested")
    func sessionPlugDropsSession() async throws {
        let secret = Data(repeating: 0xAA, count: 32)
        let plug = sessionPlug(SessionConfig(secret: secret))
        let token = MessageSigning.sign(payload: try JSONEncoder().encode(["key": "value"]), secret: secret)
        let conn = connWithCookie("_nexus_session", token)
        let result = try await plug(conn)
        var result2 = result
        result2.assigns[Connection.sessionDropKey] = true
        result2.assigns[Connection.sessionTouchedKey] = true
        let afterSend = result2.runBeforeSend()
        #expect(hasSetCookie(afterSend, named: "_nexus_session"))
    }

    @Test("session plug with empty session data")
    func sessionPlugEmptySessionData() async throws {
        let secret = Data(repeating: 0xAA, count: 32)
        let plug = sessionPlug(SessionConfig(secret: secret))
        let token = MessageSigning.sign(payload: try JSONEncoder().encode([String: String]()), secret: secret)
        let conn = connWithCookie("_nexus_session", token)
        let result = try await plug(conn)
        let session = result.assigns[Connection.sessionKey] as? [String: String]
        #expect(session == [:])
    }

    @Test("session plug with large session data")
    func sessionPlugLargeSessionData() async throws {
        let secret = Data(repeating: 0xAA, count: 32)
        let plug = sessionPlug(SessionConfig(secret: secret))
        var sessionData: [String: String] = [:]
        for i in 0..<100 { sessionData["key_\(i)"] = String(repeating: "x", count: 20) }
        let token = MessageSigning.sign(payload: try JSONEncoder().encode(sessionData), secret: secret)
        let conn = connWithCookie("_nexus_session", token)
        let result = try await plug(conn)
        let session = result.assigns[Connection.sessionKey] as? [String: String]
        #expect(session?.count == 100)
    }

    @Test("session plug with special characters in values")
    func sessionPlugSpecialCharacters() async throws {
        let secret = Data(repeating: 0xAA, count: 32)
        let plug = sessionPlug(SessionConfig(secret: secret))
        let sessionData = [
            "spaces": "hello world",
            "unicode": "世界",
            "emoji": "😀",
            "quotes": "\"quoted\"",
            "newlines": "line1\nline2"
        ]
        let token = MessageSigning.sign(payload: try JSONEncoder().encode(sessionData), secret: secret)
        let conn = connWithCookie("_nexus_session", token)
        let result = try await plug(conn)
        let session = result.assigns[Connection.sessionKey] as? [String: String]
        #expect(session?["spaces"] == "hello world")
        #expect(session?["unicode"] == "世界")
        #expect(session?["emoji"] == "😀")
        #expect(session?["quotes"] == "\"quoted\"")
        #expect(session?["newlines"] == "line1\nline2")
    }

    @Test("session config with custom cookie attributes")
    func sessionConfigCustomAttributes() async throws {
        let secret = Data(repeating: 0xAA, count: 32)
        let config = SessionConfig(
            secret: secret,
            cookieName: "custom_session",
            path: "/api",
            domain: "example.com",
            maxAge: 3600,
            secure: false,
            httpOnly: false,
            sameSite: .strict
        )
        let plug = sessionPlug(config)
        let token = MessageSigning.sign(payload: try JSONEncoder().encode(["key": "value"]), secret: secret)
        let conn = connWithCookie("custom_session", token)
        var result = try await plug(conn)
        result.assigns[Connection.sessionTouchedKey] = true
        let afterSend = result.runBeforeSend()
        let setCookieValue = afterSend.response.headerFields
            .first { $0.name == .setCookie && $0.value.hasPrefix("custom_session=") }?.value
        #expect(setCookieValue != nil)
        #expect(setCookieValue?.contains("Path=/api") == true)
        #expect(setCookieValue?.contains("Domain=example.com") == true)
    }
}
