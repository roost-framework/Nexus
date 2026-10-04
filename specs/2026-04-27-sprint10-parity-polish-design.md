# Sprint 10: Parity Polish Design

**Date:** 2026-04-27\
**Status:** Approved\
**Scope:** Connection API gap fills + test coverage for untested plugs + integration tests

---

## Context

Sprints 0–9 brought Nexus to ~95% Elixir Plug feature parity. A survey found:

- Four plugs (Compression, ContentNegotiation, Timeout, Favicon) implemented but **not tested**
- Six Connection API functions/properties present in Plug.Conn but **missing from Nexus**

This sprint closes both gaps. All changes are additive — no existing public API changes.

Current baseline: **829 tests, 83 suites, all passing.**

---

## Part 1 — Connection API Additions

### 1.1 Multi-value header access

**Files:** `Sources/Nexus/Connection+Convenience.swift`

Existing `getReqHeader`/`getRespHeader` return `String?` (first value only). Plug's `get_req_header/2` returns all values for a header name. Add:

```swift
public func getReqHeaders(_ name: HTTPField.Name) -> [String]
public func getReqHeaders(_ name: String) -> [String]
public func getRespHeaders(_ name: HTTPField.Name) -> [String]
public func getRespHeaders(_ name: String) -> [String]
```

Implementation: filter `request.headerFields` / `response.headerFields` by name, map to `value`. Returns empty array when no values match (never nil). Follows the existing `HTTPField.Name` + `String` overload pattern in the file.

### 1.2 `port` computed property

**File:** `Sources/Nexus/Connection+Convenience.swift`

```swift
public var port: Int? { get }
```

Parse order:
1. Extract from `request.authority` after the last `:` — e.g. `"example.com:8080"` → `8080`
2. If no explicit port: return `443` when `scheme == "https"`, `80` when `scheme == "http"`, `nil` otherwise

No mutation — this is read-only like `host` and `scheme`.

### 1.3 `requestURL` computed property

**File:** `Sources/Nexus/Connection+Convenience.swift`

```swift
public var requestURL: String { get }
```

Builds `scheme://host[:port]/path[?query]`. Port is omitted when it is the default for the scheme (80 for http, 443 for https). Uses `request.path` which includes query string per HTTPTypes convention. Falls back to `"http"` / `"localhost"` / `"/"` for nil components.

### 1.4 `mergeAssigns`

**File:** `Sources/Nexus/Connection+Convenience.swift`

```swift
public func mergeAssigns(_ other: [String: any Sendable]) -> Connection
```

Returns a copy with `other` merged into `assigns`. Existing keys in `assigns` are overwritten by keys in `other` (same semantics as Swift's `Dictionary.merge(_:uniquingKeysWith:)` with the new value winning).

### 1.5 `renewSession`

**File:** `Sources/Nexus/Connection+Session.swift`

```swift
public func renewSession() -> Connection
```

Marks the session as touched so `sessionPlug`'s `beforeSend` callback re-issues the cookie with a fresh expiry. Equivalent to Plug's `configure_session(conn, renew: true)`. Implementation: `assign(key: Connection.sessionTouchedKey, value: true)`.

---

## Part 2 — Test Suites for Untested Plugs

All files use `import Testing`, `@testable import Nexus`, `Connection.make()`. Pattern matches existing test suite.

### 2.1 `Tests/NexusTests/CompressionTests.swift` (~30 tests)

**Suite: "Compression Plug"**

Coverage:
- Gzip encoding when client sends `Accept-Encoding: gzip`
- Deflate encoding when client sends `Accept-Encoding: deflate`
- Algorithm priority — `gzip` preferred over `deflate` when both accepted
- Bodies below `minimumLength` threshold pass through uncompressed
- Streaming (`ResponseBody.stream`) passes through unchanged
- Empty body passes through unchanged
- No `Accept-Encoding` header → no compression
- `identity` encoding accepted → no compression
- `*;q=0` (reject all) → no compression
- `Content-Encoding` response header set on compressed responses
- `Content-Length` absent or updated after compression
- Compression registered via `beforeSend` — runs after downstream plugs

### 2.2 `Tests/NexusTests/ContentNegotiationTests.swift` (~25 tests)

**Suite: "ContentNegotiation Plug"**

Coverage:
- Exact MIME type match → negotiated type stored under `NegotiatedTypeKey`
- Quality value ordering (`application/json;q=0.9, text/html;q=1.0` → html wins)
- Wildcard `*/*` matches first supported type
- Missing `Accept` header → first supported type wins
- No overlap → 406 Not Acceptable, connection halted
- Case-insensitive type matching
- `NegotiatedTypeKey` accessible downstream in same pipeline
- Multiple supported types, client accepts only last one

### 2.3 `Tests/NexusTests/TimeoutTests.swift` (~15 tests)

**Suite: "Timeout Plug"**

Coverage:
- Fast plug completes without triggering timeout
- Plug that exceeds timeout duration → expected timeout response (status + body from config)
- Timeout response halts the connection
- Timeout value from `TimeoutConfig` is respected
- Plug already halted before timeout check — halted result returned as-is
- Zero/negative timeout values handled gracefully

### 2.4 `Tests/NexusTests/FaviconTests.swift` (~20 tests)

**Suite: "Favicon Plug"**

Coverage:
- `GET /favicon.ico` → 200 with `Content-Type: image/x-icon`
- Response body is the configured favicon bytes
- Default favicon data served when no custom data configured
- Non-favicon paths → plug passes through unchanged
- `HEAD /favicon.ico` → 200 with headers, empty body
- Cache headers present: `Cache-Control`, `ETag`
- ETag is stable across calls for the same favicon data
- `If-None-Match` matching → 304 Not Modified
- Plug ignores POST/PUT/DELETE to `/favicon.ico` (pass through)

---

## Part 3 — Integration Tests

### 3.1 `Tests/NexusHummingbirdTests/PlugIntegrationTests.swift` (~40 tests)

Uses the `runHummingbirdPlug()` harness from `AdapterPropertyTests.swift` — calls plug, executes `runBeforeSend()`, returns serialized `AdapterTestResult`. No live server required.

**Suite: "Plug Integration Tests"**

**Compression (10 tests)**
- Compressed response has correct `Content-Encoding` header through adapter
- Streaming body survives adapter path without compression
- `beforeSend` compression runs after router response is built
- Multiple requests through same plug instance produce correct results

**ContentNegotiation (10 tests)**
- 406 response exits pipeline and is returned by adapter unchanged
- Negotiated type is readable by downstream plug in the same pipeline
- Pipeline with both ContentNegotiation and Router — router sees negotiated type

**Timeout (10 tests)**
- Timeout fires under adapter's async execution path
- Timeout response body is preserved through adapter serialization
- Non-timing-out plug returns normally through adapter

**Favicon (10 tests)**
- `/favicon.ico` body bytes match configured data after adapter round-trip
- `ETag` header survives adapter serialization
- 304 response returns no body through adapter

### 3.2 `Tests/NexusTests/ConnectionAPITests.swift` (~25 tests)

**Suite: "Connection API Parity"**

Unit tests for all six new additions:
- `getReqHeaders` returns all values for multi-value headers
- `getReqHeaders` returns empty array for absent header
- `getRespHeaders` symmetry with `getReqHeaders`
- `port` parsed from `host:port` authority
- `port` defaults to 443 for https, 80 for http
- `port` returns nil for unknown scheme with no explicit port
- `requestURL` includes scheme, host, path
- `requestURL` omits default port (80/443)
- `requestURL` includes explicit non-default port
- `requestURL` includes query string from path
- `mergeAssigns` merges new keys
- `mergeAssigns` new values overwrite existing keys
- `mergeAssigns` empty dict returns identical assigns
- `renewSession` sets touched flag
- `renewSession` does not clear existing session data

---

## Deliverables

| Artifact | Location |
|---|---|
| Multi-value header API | `Sources/Nexus/Connection+Convenience.swift` |
| `port`, `requestURL`, `mergeAssigns` | `Sources/Nexus/Connection+Convenience.swift` |
| `renewSession` | `Sources/Nexus/Connection+Session.swift` |
| CompressionTests | `Tests/NexusTests/CompressionTests.swift` |
| ContentNegotiationTests | `Tests/NexusTests/ContentNegotiationTests.swift` |
| TimeoutTests | `Tests/NexusTests/TimeoutTests.swift` |
| FaviconTests | `Tests/NexusTests/FaviconTests.swift` |
| ConnectionAPITests | `Tests/NexusTests/ConnectionAPITests.swift` |
| PlugIntegrationTests | `Tests/NexusHummingbirdTests/PlugIntegrationTests.swift` |

**Expected test count after Sprint 10:** ~984 tests (829 existing + ~155 new)

---

## Non-Goals

- No breaking changes to existing public API
- No new plugs — only testing and API gaps for existing code
- No `Plug.Conn.private` namespace — single `assigns` dict is intentional design
- No `read_body` streaming API — body collection in adapter layer is intentional
- No new server adapters
