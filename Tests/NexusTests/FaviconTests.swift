import Foundation
import HTTPTypes
import Testing

@testable import Nexus
@testable import NexusTest

@Suite("Favicon Plug")
struct FaviconParityTests {

    private let iconBytes = Data([0x00, 0x00, 0x01, 0x00])  // minimal ICO header
    private let pngBytes = Data([0x89, 0x50, 0x4E, 0x47])  // PNG magic bytes

    // MARK: - Basic Serving

    @Test("GET /favicon.ico returns 200")
    func servesWithStatus200() async throws {
        let plug = Favicon(iconData: iconBytes)
        let conn = Connection.make(path: "/favicon.ico")
        let result = try await plug.call(conn)
        #expect(result.response.status == .ok)
        #expect(result.isHalted)
    }

    @Test("GET /favicon.ico returns correct Content-Type")
    func servesWithCorrectContentType() async throws {
        let plug = Favicon(iconData: iconBytes)
        let conn = Connection.make(path: "/favicon.ico")
        let result = try await plug.call(conn)
        #expect(result.response.headerFields[.contentType] == "image/x-icon")
    }

    @Test("GET /favicon.ico body matches configured icon data")
    func servesCorrectBody() async throws {
        let plug = Favicon(iconData: iconBytes)
        let conn = Connection.make(path: "/favicon.ico")
        let result = try await plug.call(conn)
        guard case .buffered(let data) = result.responseBody else {
            Issue.record("Expected .buffered body")
            return
        }
        #expect(data == iconBytes)
    }

    // MARK: - Content-Type by Extension

    @Test("PNG path returns image/png content type")
    func pngContentType() async throws {
        let plug = Favicon(iconData: pngBytes, iconPath: "/favicon.png")
        let conn = Connection.make(path: "/favicon.png")
        let result = try await plug.call(conn)
        #expect(result.response.headerFields[.contentType] == "image/png")
    }

    @Test("SVG path returns image/svg+xml content type")
    func svgContentType() async throws {
        let svgData = Data("<svg/>".utf8)
        let plug = Favicon(iconData: svgData, iconPath: "/favicon.svg")
        let conn = Connection.make(path: "/favicon.svg")
        let result = try await plug.call(conn)
        #expect(result.response.headerFields[.contentType] == "image/svg+xml")
    }

    // MARK: - Pass Through

    @Test("non-favicon path passes through unchanged")
    func nonFaviconPathPassesThrough() async throws {
        let plug = Favicon(iconData: iconBytes)
        let conn = Connection.make(path: "/api/users")
        let result = try await plug.call(conn)
        #expect(!result.isHalted)
        #expect(result.response.status == .ok)  // default, not set by favicon
        if case .empty = result.responseBody {
        } else {
            Issue.record("Expected .empty passthrough body")
        }
    }

    @Test("root path passes through")
    func rootPathPassesThrough() async throws {
        let plug = Favicon(iconData: iconBytes)
        let conn = Connection.make(path: "/")
        let result = try await plug.call(conn)
        #expect(!result.isHalted)
    }

    @Test("similar path does not match favicon")
    func similarPathNoMatch() async throws {
        let plug = Favicon(iconData: iconBytes)
        let conn = Connection.make(path: "/assets/favicon.ico")
        let result = try await plug.call(conn)
        #expect(!result.isHalted)
    }

    // MARK: - Custom Icon Path

    @Test("custom iconPath is respected")
    func customIconPath() async throws {
        let plug = Favicon(iconData: iconBytes, iconPath: "/static/icon.ico")
        let conn = Connection.make(path: "/static/icon.ico")
        let result = try await plug.call(conn)
        #expect(result.response.status == .ok)
        #expect(result.isHalted)
    }

    @Test("default path not served when custom path configured")
    func defaultPathNotServedWithCustom() async throws {
        let plug = Favicon(iconData: iconBytes, iconPath: "/custom-icon.ico")
        let conn = Connection.make(path: "/favicon.ico")
        let result = try await plug.call(conn)
        #expect(!result.isHalted)
    }

    // MARK: - Query String

    @Test("path with query string still matches favicon")
    func queryStringIgnored() async throws {
        let plug = Favicon(iconData: iconBytes)
        let conn = Connection.make(path: "/favicon.ico?v=2")
        let result = try await plug.call(conn)
        #expect(result.response.status == .ok)
        #expect(result.isHalted)
    }

    // MARK: - Methods

    @Test("POST to favicon path passes through")
    func postPassesThrough() async throws {
        let plug = Favicon(iconData: iconBytes)
        let conn = Connection.make(method: .post, path: "/favicon.ico")
        let result = try await plug.call(conn)
        #expect(!result.isHalted)
    }

    // MARK: - Empty Icon Data

    @Test("empty icon data is served without error")
    func emptyIconData() async throws {
        let plug = Favicon(iconData: Data())
        let conn = Connection.make(path: "/favicon.ico")
        let result = try await plug.call(conn)
        #expect(result.response.status == .ok)
        guard case .buffered(let data) = result.responseBody else {
            Issue.record("Expected .buffered body")
            return
        }
        #expect(data.isEmpty)
    }
}
