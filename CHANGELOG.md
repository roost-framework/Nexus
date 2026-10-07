# Changelog

All notable changes to Nexus are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [2.1.0] - 2026-10-07

### Changed

- `NexusVapor` and its Vapor dependency now sit behind the `Vapor` package trait, enabled by default. Packages that only
  use the Hummingbird adapter can depend on Nexus with `traits: []`, and SwiftPM then skips fetching Vapor and its
  dependencies (about 75 MB of sources).
- Nexus now requires Swift 6.1 (swift-tools-version 6.1), the first version with package traits. Swift 6.0 projects
  keep resolving Nexus 2.0.x.

## [2.0.0] - 2026-10-04

### Added

- `NexusVapor`, a Vapor 4 adapter for Nexus middleware, with HTTP request/response conversion and WebSocket integration.
- SwiftCheck property generators and expanded `NexusTest` request builders.
- Lazy `ResponseBody.producer` and `ResponseBodyWriter`, with transport backpressure and automatic
  completion in both adapters. Real TCP tests cover slow readers, disconnects, file and SSE delivery,
  producer errors, and suppression for HEAD/bodyless responses.
- Connection metadata (`port`, `requestURL`, `requestPath`, `queryString`, `pathInfo`), multi-value header access,
  header merge/prepend/update helpers, `mergeAssigns`, and separate `privateData` storage for framework metadata.
- Session renewal, session getter overloads, persistence options, and `clearSession(drop: false)`.
- Regression tests for compression wire formats, HTTP negotiation, session persistence, and actual Hummingbird
  and Vapor request/response conversion.

### Changed

- **Breaking:** `sendChunked` and `Connection.sseEvent` now use a scoped async writer. Add `try await`
  to writes, replace SSE continuation `yield` with `write`, remove `finish()` and nested producer tasks,
  and throw to abort. Both helpers halt the pipeline. `ResponseBody` switches must handle `.producer`.
  Caller-supplied `.stream(AsyncThrowingStream)` remains supported with caller-owned lifecycle/buffering.
- `sendFile` opens lazily, reads only after the previous write completes, and closes on stream exit.
  Invalid chunk sizes are rejected. Opening/reading failures after preparation abort the stream.
- Query and form parameters now use the last duplicate value; query `+` characters decode to spaces, matching
  Plug. Callers needing all query values can use `queryParameters`. Combined parameters prioritize path, body,
  then query values. These are observable changes from previous Nexus behavior.
- Compression uses system zlib on Apple platforms and Linux. Debian/Ubuntu builds require `zlib1g-dev`.

### Fixed

- Valid gzip and zlib-wrapped deflate output, quality-aware content negotiation, cache variation headers,
  existing content encodings, and `no-transform` handling.
- Repeated session plugs no longer overwrite changes or emit duplicate session cookies.
- Favicon HEAD and conditional requests, deterministic ETags, configurable caching, and method filtering.
- Timeout handling for zero, negative, non-finite, and extreme durations without trapping.
- Vapor request query strings, IPv6 authority, repeated headers and cookies, precollected body size limits,
  and propagation of streaming response failures.
- Both adapters preserve HEAD and 304 representation lengths and suppress bodies for HEAD and bodyless statuses.
- Linux-compatible test byte-buffer conversions and Swift Testing 6.0 assertions.
- Linux CI installs zlib headers and propagates build/test process failures instead of masking exit codes.
- Coverage reporting combines all test executables and profiles, uses matching LLVM tools on macOS and Linux,
  and enforces the 85% threshold on unique executable source lines from LCOV.
- Property tests now report SwiftCheck failures and exhausted generators through Swift Testing; corrected
  expectations for empty HTTP field values and assigns whose generated keys coincide.

### Migration and validation

- Update the package requirement to `from: "2.0.0"` and apply the streaming changes above.
- Review duplicate query/form keys and plus decoding; use `queryParameters` when every value is needed.
- Install zlib development headers on Linux. The manifest uses Swift tools 6.0.
- All 967 tests passed on macOS with Swift 6.4 and Linux arm64 with Swift 6.0.3, including
  live HTTP/1 TCP streaming checks on both adapters. Two intentional known-issue probes verify the
  property-test assertion bridge.
- Idle SSE producers should send heartbeat comments: disconnects are observed through failed writes,
  and immediate cancellation while waiting on unrelated work is not guaranteed.
- HTTP/2, TLS/proxy streaming, WebSocket behavioral parity, and load performance were not validated
  by the streaming pilot.

## [1.3.0] - 2026-04-02

### Added

- **NamedPipeline** (Spec 29) -- reusable, named middleware pipeline that can be declared once and
  applied to multiple routes or scopes. Conforms to `Sendable` and `ModulePlug`, works with
  `@PlugPipeline` result builder, and integrates via new `scope(_:through:)` overload accepting
  `NamedPipeline`. Supports conditionals, loops, halt propagation, and nested scope composition.

## [1.2.0] - 2026-03-29

Plug feature parity release. Adds 10 new source files, 9 test suites (98 tests), and closes the
critical gaps between Nexus and Elixir's Plug framework.

### Added

- **ModulePlug protocol** (Spec 17) -- lightweight alternative to `ConfigurablePlug` for plugs
  that carry configuration as plain init parameters. Includes `asPlug()` conversion to the
  universal `Plug` function type.
- **Header helpers** (Spec 18) -- convenience methods on `Connection`: `putRespHeader`,
  `deleteRespHeader`, `getRespHeader`, `putReqHeader`, `deleteReqHeader`, `getReqHeader`,
  and `putRespContentType`.
- **Nested assigns** (Spec 19) -- dot-path and array-path notation for hierarchical data storage
  in `Connection` assigns: `assign(dotPath:value:)`, `value(forDotPath:)`.
- **onError plug** (Spec 20) -- centralized error handling via `onError(_:handler:)` that catches
  errors from downstream plugs and lets the handler produce a recovery response.
- **Fetch session helpers** (Spec 24) -- `fetchSession`, `fetchSessionIfMissing`,
  `isSessionFetched`, and `clearSession` for explicit session loading control.
- **Route parameters access** (Spec 25) -- `pathParameters`, `queryParameters`, `parameters`
  (combined), `getParameter(_:)`, `getParameters(_:)`, and typed `getParameter(_:as:)` for
  convenient parameter extraction.
- **ContentNegotiation plug** (Spec 27) -- validates `Accept` headers against supported media
  types with quality-value support; returns 406 on mismatch.
- **Timeout plug** (Spec 27) -- wraps plug execution with a configurable duration; returns
  503 Service Unavailable on timeout.
- **Favicon plug** (Spec 27) -- serves a static icon for `/favicon.ico` requests.
- **PlugBuilder result builder** (Spec 26) -- declarative plug composition with Swift's
  `@resultBuilder`, supporting `if`/`else` conditional plugs and automatic `ModulePlug`/
  `ConfigurablePlug` conversion.
- **HTTPServerAdapter protocol** (Spec 22) -- abstraction layer for HTTP server backends.
- **NexusTest helpers** (Spec 23) -- `Connection.make(method:path:headers:body:)`,
  `Connection.makeJSON`, and `Connection.makeForm` factory methods for tests.
- **Specs 17--28** -- full specification documents for the Plug parity effort.

### Fixed

- **Linux CI build** -- `NSData.compressed(using:)` is Apple-only. Compression now gracefully
  returns `nil` on Linux via `#if canImport(Compression)`. Compression tests are skipped on
  platforms without the `Compression` framework.
- **sendFile race condition** -- fixed data race in `Connection+SendFile.swift`.

### Removed

- Stale specification files (specs 08--16) that shipped in 1.0.0.

## [1.1.0] - 2026-03-29

### Added

- Assign Plug Factory for dynamic plug creation from assigns.
- Typed Assigns with `AssignKey` protocol for type-safe connection data access.
- WebSocket support via Hummingbird WebSocket integration.
- Service injection pattern for dependency management.

## [1.0.0] - 2026-03-28

Initial stable release with 22+ built-in plugs, immutable `Connection` value type,
pipeline composition (`pipe`, `pipeline`), `ConfigurablePlug` protocol, full session/cookie
support, CSRF protection, CORS, BasicAuth, StaticFiles, BodyParser, and more.

[Unreleased]: https://github.com/roost-framework/Nexus/compare/2.1.0...HEAD
[2.1.0]: https://github.com/roost-framework/Nexus/compare/2.0.0...2.1.0
[2.0.0]: https://github.com/roost-framework/Nexus/compare/1.3.0...2.0.0
[1.3.0]: https://github.com/roost-framework/Nexus/compare/1.2.0...1.3.0
[1.2.0]: https://github.com/roost-framework/Nexus/compare/1.1.1...1.2.0
[1.1.0]: https://github.com/roost-framework/Nexus/compare/1.0.0...1.1.0
[1.0.0]: https://github.com/roost-framework/Nexus/releases/tag/1.0.0
