# Nexus

A composable HTTP middleware pipeline library for Swift, inspired by [Elixir's Plug](https://hexdocs.pm/plug/readme.html). Nexus gives you a functional, value-type-based approach to building HTTP applications where middleware ("plugs") are plain functions that transform a `Connection` value flowing through a pipeline.

## Table of Contents

- [Key Features](#key-features)
- [Tech Stack](#tech-stack)
- [Prerequisites](#prerequisites)
- [Getting Started](#getting-started)
- [Architecture](#architecture)
  - [Design Philosophy](#design-philosophy)
  - [Package Targets](#package-targets)
  - [Directory Structure](#directory-structure)
  - [Core Concepts](#core-concepts)
  - [Request Lifecycle](#request-lifecycle)
  - [Error Signalling Contract](#error-signalling-contract)
- [Usage Guide](#usage-guide)
  - [Defining Plugs](#defining-plugs)
  - [Composing Pipelines](#composing-pipelines)
  - [Routing](#routing)
  - [JSON Handling](#json-handling)
  - [Query and Form Parameters](#query-and-form-parameters)
  - [Cookies](#cookies)
  - [Response Headers](#response-headers)
  - [Streaming Responses and SSE](#streaming-responses-and-sse)
  - [File Serving](#file-serving)
  - [Static File Serving](#static-file-serving)
  - [Sessions](#sessions)
  - [CSRF Protection](#csrf-protection)
  - [Error Rescue](#error-rescue)
  - [Lifecycle Hooks](#lifecycle-hooks)
  - [Service Injection](#service-injection)
  - [Typed Assigns](#typed-assigns)
  - [WebSocket](#websocket)
  - [Configurable Plugs](#configurable-plugs)
  - [Running with Hummingbird](#running-with-hummingbird)
- [Built-in Plugs](#built-in-plugs)
- [Testing](#testing)
- [Available Commands](#available-commands)
- [CI](#ci)
- [Architecture Decision Records](#architecture-decision-records)
- [Contributing](#contributing)
- [License](#license)

## Key Features

- **Functional middleware** -- plugs are plain `@Sendable` closures, not protocol conformances
- **Value-type pipeline** -- `Connection` is a struct; every plug returns a new copy, never mutates in place
- **Layered targets** -- import only what you need: core pipeline, router DSL, or Hummingbird adapter
- **Swift 6 strict concurrency** -- `Sendable` throughout, no `@unchecked Sendable` in core
- **Halt-not-throw contract** -- HTTP errors (4xx/5xx) halt the pipeline; only infrastructure failures throw
- **Result-builder router** -- declarative route definitions with scoped middleware, path parameters, wildcards, and sub-router forwarding
- **Built-in middleware** -- request logging, request IDs, CORS, Basic auth, SSL redirect, sessions, CSRF protection, static file serving
- **JSON, form, and query param** parsing out of the box
- **Cookies** -- read request cookies and set response cookies with full RFC 6265 attribute support
- **Sessions** -- signed cookie-based sessions with HMAC-SHA256 (CryptoKit), session helpers on Connection
- **CSRF protection** -- token-based cross-site request forgery prevention with form param and header validation
- **Static file serving** -- directory-based file serving with path traversal protection and extension filtering
- **Service injection** -- `assign(_:value:)` plug factory for injecting database repos, API clients, or any shared service into the pipeline
- **Typed assigns** -- compile-time-safe `conn[KeyType.self]` access replacing stringly-typed casts, with built-in keys for request ID, session, and remote IP
- **WebSocket** -- real-time bidirectional communication with functional handlers, Hummingbird adapter integration, and HTTP pipeline assign propagation
- **Streaming** -- chunked response bodies, Server-Sent Events helper, and file serving
- **Test helpers** -- `NexusTest` target with `TestConnection` builders for writing tests without boilerplate

## Tech Stack

| Component | Technology |
|-----------|------------|
| **Language** | Swift 6.0.3+ |
| **Swift Tools Version** | 6.0 |
| **Platforms** | macOS 14+, iOS 17+, Linux |
| **HTTP Primitives** | [swift-http-types](https://github.com/apple/swift-http-types) (Apple) |
| **Server Adapter** | [Hummingbird 2](https://github.com/hummingbird-project/hummingbird) (optional) |
| **Testing** | Swift Testing (`import Testing`) |
| **Formatting** | swift-format (120-char lines, 4-space indent) |
| **CI** | GitHub Actions (macOS + Linux) |

## Prerequisites

- **Swift 6.0.3** or later. Install via [Xcode](https://developer.apple.com/xcode/), [swiftly](https://github.com/swiftlang/swiftly), or the [official Docker image](https://hub.docker.com/_/swift) (`swift:6.0`).
- **macOS 14+** (Sonoma) or **Linux** (Ubuntu 22.04+ recommended).
- Compression uses system zlib. Apple SDKs include it; on Debian/Ubuntu install `zlib1g-dev` before building
  (`apt-get install zlib1g-dev`). Swift Package Manager resolves the Swift dependencies.

## Getting Started

### 1. Add the Dependency

Add Nexus to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/Spectro-ORM/Nexus.git", from: "2.0.0"),
]
```

Then add the targets you need:

```swift
.target(
    name: "MyApp",
    dependencies: [
        .product(name: "Nexus", package: "swift-nexus"),           // Core pipeline
        .product(name: "NexusRouter", package: "swift-nexus"),     // Router DSL
        .product(name: "NexusHummingbird", package: "swift-nexus"), // Hummingbird adapter
    ]
)
```

You can import each target independently. If you only need the pipeline and do not use Hummingbird, omit `NexusHummingbird` and Hummingbird will never be fetched.

### 2. Clone for Development

```bash
git clone https://github.com/Spectro-ORM/Nexus.git
cd Nexus
swift build
swift test
```

### 3. A Minimal Application

```swift
import Nexus
import NexusRouter
import NexusHummingbird
import Hummingbird

let router = Router {
    GET("/health") { conn in
        conn.respond(status: .ok, body: .string("OK"))
    }

    GET("/hello/:name") { conn in
        let name = conn.params["name"] ?? "world"
        return try conn.json(value: ["message": "Hello, \(name)!"])
    }
}

let app = pipeline([
    requestLogger(),
    requestId(),
    router.callAsFunction,
])

let adapter = NexusHummingbirdAdapter(plug: rescueErrors(app))
let server = Application(responder: adapter)
try await server.runService()
```

## Architecture

### Design Philosophy

Nexus draws directly from Elixir's Plug library. The core ideas are:

1. **A plug is a function.** Any `@Sendable (Connection) async throws -> Connection` closure qualifies. No protocol conformance, no registration, no ceremony.

2. **Connection is data, not a reference.** `Connection` is a value type (struct). Plugs receive a copy, transform it, and return a new copy. This eliminates shared-mutable-state bugs and plays naturally with Swift's concurrency model.

3. **Halt, don't throw, for HTTP responses.** A 401 Unauthorized is not an "error" in the infrastructure sense -- it is a valid HTTP response. Plugs that want to respond early set the status, body, and call `connection.halted()`. Throwing is reserved for genuinely unexpected failures (database down, file I/O error, etc.).

4. **Composition over configuration.** Pipelines are built by composing functions with `pipe(_:_:)` and `pipeline(_:)`. The router is a plug. Middleware is a plug. Your application is a plug.

### Package Targets

Nexus ships as a single Swift package with five library targets. Import only what you need:

```
                  ┌──────────────────────┐
                  │   NexusHummingbird    │
                  │  (Hummingbird 2 adapter)  │
                  └──────────┬───────────┘
                             │
              ┌──────────────┤
              │              │
   ┌──────────┴──────────┐   │
   │     NexusRouter     │   │
   │  (Result-builder DSL)│   │
   └──────────┬──────────┘   │
              │              │
              └──────┬───────┘
                     │
          ┌──────────┴──────────┐       ┌──────────────────┐
          │       Nexus         │       │    NexusTest      │
          │  (Core: Connection, │◄──────│  (TestConnection  │
          │   Plug, Body, Plugs)│       │   builders)       │
          └──────────┬──────────┘       └──────────────────┘
                     │
          ┌──────────┴──────────┐
          │  swift-http-types   │
          │  (Apple, HTTP only) │
          └─────────────────────┘
```

| Target | Description | External Dependencies |
|--------|-------------|----------------------|
| **Nexus** | Core. `Connection`, `Plug` typealias, `RequestBody`/`ResponseBody`, built-in plugs, JSON/form/query/cookie helpers. | `swift-http-types`, `swift-metrics`, system zlib, `swift-crypto` on Linux |
| **NexusRouter** | Result-builder HTTP router with path parameters, wildcards, scoped middleware, sub-router forwarding, and WebSocket route builder. | `Nexus` |
| **NexusHummingbird** | Bridges Nexus pipelines to Hummingbird 2's `HTTPResponder` protocol. Includes WebSocket upgrade adapter. | `Nexus` + `NexusRouter` + `Hummingbird` + `HummingbirdWebSocket` |
| **NexusVapor** | Bridges Nexus pipelines to Vapor 4's `AsyncMiddleware` protocol. Includes WebSocket route registration. | `Nexus` + `NexusRouter` + `Vapor` |
| **NexusTest** | `TestConnection` builders and HTTP property generators for tests. | `Nexus` + `swift-http-types` + `SwiftCheck` |

### Directory Structure

```
swift-nexus/
├── Sources/
│   ├── Nexus/                          # Core target
│   │   ├── Connection.swift            # The Connection value type
│   │   ├── Plug.swift                  # Plug typealias + pipe/pipeline composition
│   │   ├── Body.swift                  # RequestBody / ResponseBody enums
│   │   ├── ResponseBodyWriter.swift    # Awaited transport writes for response producers
│   │   ├── ConfigurablePlug.swift      # Two-phase plug protocol
│   │   ├── NexusHTTPError.swift        # NexusHTTPError + rescueErrors wrapper
│   │   ├── JSONValue.swift             # Dynamic JSON access wrapper
│   │   ├── Cookie.swift                # Cookie value type (RFC 6265)
│   │   ├── SSEEvent.swift              # Server-Sent Events formatter
│   │   ├── MIMEType.swift              # File extension -> MIME type mapping
│   │   ├── URLEncodedParser.swift      # Shared URL-encoded string parser
│   │   ├── Connection+Respond.swift    # respond(status:body:) convenience
│   │   ├── Connection+JSON.swift       # decode(as:) and json(value:) helpers
│   │   ├── Connection+Params.swift     # Path parameter accessors
│   │   ├── Connection+QueryParams.swift # Query string parsing
│   │   ├── Connection+FormParams.swift # Form body parsing
│   │   ├── Connection+Cookies.swift    # Cookie read/write helpers
│   │   ├── Connection+Convenience.swift # Header helpers, status, host, scheme
│   │   ├── Connection+BeforeSend.swift # Lifecycle hook registration
│   │   ├── Connection+Chunked.swift    # Streaming response + ChunkWriter
│   │   ├── Connection+SendFile.swift   # File serving with chunked streaming
│   │   ├── Connection+RemoteIP.swift   # Remote IP accessor
│   │   ├── Connection+Session.swift   # Session helpers (get/put/delete/clear)
│   │   ├── AssignKey.swift             # AssignKey protocol for typed assigns
│   │   ├── AssignKeys.swift            # Built-in keys (RequestId, Session, RemoteIP)
│   │   ├── Connection+TypedAssigns.swift # Typed subscript + convenience accessors
│   │   ├── Base64URL.swift            # Base64url encoding utility
│   │   ├── MessageSigning.swift       # HMAC-SHA256 sign/verify (CryptoKit)
│   │   ├── WebSocket/                  # WebSocket core types
│   │   │   ├── WSMessage.swift         # Message enum (text, binary, ping, pong, close)
│   │   │   ├── WSConnection.swift      # WebSocket connection with assigns + send
│   │   │   └── WSHandler.swift         # WSHandler / WSConnectHandler typealiases
│   │   └── Plugs/                      # Built-in middleware
│   │       ├── Assign.swift            # Service injection plug factory
│   │       ├── RequestLogger.swift     # Request/response logging with timing
│   │       ├── RequestId.swift         # UUID-based X-Request-Id header
│   │       ├── CORS.swift              # CORS headers + OPTIONS preflight
│   │       ├── BasicAuth.swift         # HTTP Basic authentication
│   │       ├── SSLRedirect.swift       # HTTP -> HTTPS redirect
│   │       ├── Session.swift           # Signed cookie-based sessions
│   │       ├── CSRFProtection.swift    # Cross-site request forgery prevention
│   │       └── StaticFiles.swift       # Directory-based static file serving
│   ├── NexusRouter/                    # Router DSL target
│   │   ├── Router.swift                # Router struct with callAsFunction
│   │   ├── Route.swift                 # Route struct + PathPattern matching
│   │   ├── RouteBuilder.swift          # @resultBuilder for route DSL
│   │   ├── MethodHelpers.swift         # GET/POST/PUT/DELETE/PATCH/HEAD/OPTIONS/ANY
│   │   ├── Scope.swift                 # Scoped routes with prefix + middleware
│   │   ├── Forward.swift               # Sub-router delegation
│   │   └── WebSocketRoute.swift        # WSRoute + WS() builder function
│   ├── NexusHummingbird/               # Hummingbird adapter target
│   │   ├── HummingbirdAdapter.swift    # HTTPResponder implementation
│   │   ├── NexusRequestContext.swift   # Request context with remote IP
│   │   └── WebSocketAdapter.swift      # WebSocket upgrade bridge
│   ├── NexusVapor/                     # Vapor adapter target
│   │   ├── VaporAdapter.swift          # AsyncMiddleware implementation
│   │   └── WebSocketAdapter.swift      # WebSocket route registration
│   └── NexusTest/                      # Test helper target
│       └── TestConnection.swift        # Connection builders for tests
├── Tests/
│   ├── NexusTests/                     # Core and property tests
│   ├── NexusRouterTests/               # Router tests
│   ├── NexusHummingbirdTests/          # Hummingbird integration tests
│   ├── NexusVaporTests/                # Vapor integration tests
│   └── NexusStreamingTests/            # Live TCP tests for both adapters
├── Docs/
│   ├── ADR/                            # Architecture Decision Records
│   │   ├── ADR-001.md                  # swift-http-types over custom primitives
│   │   ├── ADR-002.md                  # Body as enum, not concrete type
│   │   ├── ADR-003.md                  # Plug as typealias, not protocol
│   │   ├── ADR-004.md                  # Throws vs halting error contract
│   │   ├── ADR-005.md                  # Three-target package layout
│   │   ├── ADR-006.md                  # Lifecycle hooks + ConfigurablePlug
│   │   ├── ADR-007.md                  # Connection parity and HTTP semantics
│   │   └── ADR-008.md                  # Demand-driven response producers
│   └── migration-journal.md            # Hummingbird-to-Nexus porting notes
├── .github/workflows/ci.yml           # GitHub Actions CI
├── Package.swift                       # Swift package manifest
├── CONTRIBUTING.md                     # Contribution guidelines
├── .swift-format                       # swift-format configuration
└── .swift-version                      # 6.0.3
```

### Core Concepts

#### Connection

The `Connection` is the single value that flows through every plug in a pipeline. It carries:

| Field | Type | Description |
|-------|------|-------------|
| `request` | `HTTPRequest` | The incoming HTTP request (method, path, headers, scheme, authority). |
| `requestBody` | `RequestBody` | The request body: `.empty`, `.buffered(Data)`, or `.stream(AsyncThrowingStream)`. |
| `response` | `HTTPResponse` | The response being assembled. Defaults to `200 OK`. |
| `responseBody` | `ResponseBody` | The response body: `.empty`, `.buffered(Data)`, `.stream(AsyncThrowingStream)`, or `.producer` with awaited writes. |
| `isHalted` | `Bool` | When `true`, downstream plugs in the pipeline are skipped. |
| `assigns` | `[String: any Sendable]` | Arbitrary key-value store for passing data between plugs. |
| `beforeSend` | `[@Sendable (Connection) -> Connection]` | Lifecycle callbacks invoked (LIFO) before the response is sent. |

#### Plug

A `Plug` is a function typealias:

```swift
public typealias Plug = @Sendable (Connection) async throws -> Connection
```

Any closure, function, or method with this signature is a plug. No protocol conformance needed:

```swift
let logger: Plug = { conn in
    print("\(conn.request.method) \(conn.request.path ?? "/")")
    return conn
}
```

#### RequestBody / ResponseBody

Both enums distinguish absent, buffered, and streaming bodies. Responses also support lazy producers
that write directly to the transport:

```swift
public enum RequestBody: Sendable {
    case empty
    case buffered(Data)
    case stream(AsyncThrowingStream<Data, any Error>)
}

public enum ResponseBody: Sendable {
    case empty
    case buffered(Data)
    case stream(AsyncThrowingStream<Data, any Error>)
    case producer(@Sendable (inout any ResponseBodyWriter) async throws -> Void)
}
```

### Request Lifecycle

```
Incoming HTTP Request
        │
        ▼
┌─────────────────┐
│  Server Adapter  │  NexusHummingbirdAdapter converts Hummingbird Request -> Connection
│  (Hummingbird)   │  Populates remote IP from NIO channel
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│    Pipeline      │  pipeline([plug1, plug2, ..., router])
│                  │  Each plug transforms Connection, stops if halted
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│     Router       │  Matches method + path, extracts params, calls handler
│                  │  Returns 404/405 if no match
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│  runBeforeSend() │  LIFO lifecycle callbacks modify final response
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│  Server Adapter  │  Converts Connection back to Hummingbird Response
│  (Hummingbird)   │  Sends to client
└─────────────────┘
```

### Error Signalling Contract

This is a core design decision (see [ADR-004](Docs/ADR/ADR-004.md)):

| Scenario | Mechanism | Example |
|----------|-----------|---------|
| HTTP rejection (4xx, intentional 5xx) | Set status + body, return `connection.halted()` | 401 Unauthorized, 404 Not Found |
| Infrastructure failure | `throw` an `Error` | Database unreachable, file I/O timeout |

```swift
// Correct: halt for HTTP errors
let authPlug: Plug = { conn in
    guard isAuthenticated(conn) else {
        return conn.respond(status: .unauthorized, body: .string("Unauthorized"))
    }
    return conn
}

// Correct: throw for infrastructure errors
let dbPlug: Plug = { conn in
    let user = try await database.findUser(id: 42) // throws on DB failure
    return conn.assign(key: "user", value: user)
}
```

The `rescueErrors(_:)` wrapper is available for cases where throwing `NexusHTTPError` is more ergonomic -- it catches those errors and converts them to halted responses.

## Usage Guide

### Defining Plugs

A plug is any function matching `@Sendable (Connection) async throws -> Connection`:

```swift
import Nexus

// Inline closure
let addHeader: Plug = { conn in
    conn.putRespHeader(.init("X-Powered-By")!, "Nexus")
}

// Free function
func authenticate(_ conn: Connection) async throws -> Connection {
    guard let token = conn.getReqHeader(.authorization) else {
        return conn.respond(status: .unauthorized, body: .string("Missing token"))
    }
    let user = try await validateToken(token)
    return conn.assign(key: "current_user", value: user)
}
```

### Composing Pipelines

Use `pipe(_:_:)` for two plugs, or `pipeline(_:)` for a list. Both short-circuit when a plug halts the connection:

```swift
// Two plugs
let combined = pipe(requestLogger(), authenticate)

// Multiple plugs
let app = pipeline([
    requestId(),
    requestLogger(),
    corsPlug(),
    authenticate,
    router.callAsFunction,
])
```

### Routing

The `Router` uses a result-builder DSL with `GET`, `POST`, `PUT`, `DELETE`, `PATCH`, `HEAD`, `OPTIONS`, and `ANY` helpers:

```swift
import NexusRouter

let router = Router {
    GET("/health") { conn in
        conn.respond(status: .ok, body: .string("OK"))
    }

    // Path parameters
    GET("/users/:id") { conn in
        let id = conn.params["id"]!  // extracted from the URL
        return try conn.json(value: ["id": id])
    }

    // Wildcard catch-all
    GET("/files/*path") { conn in
        let filePath = conn.params["path"] ?? ""
        return conn.respond(status: .ok, body: .string("File: \(filePath)"))
    }
}
```

#### Scoped Routes

Group routes under a shared prefix with optional middleware:

```swift
let router = Router {
    GET("/health") { conn in conn.respond(status: .ok) }

    scope("/api") {
        GET("/status") { conn in conn.respond(status: .ok) }

        // Nested scope with middleware
        scope("/admin", through: [basicAuth { u, p in u == "admin" && p == "secret" }]) {
            GET("/dashboard") { conn in
                try conn.json(value: ["admin": true])
            }
        }
    }
}
// Matches: /health, /api/status, /api/admin/dashboard (with auth)
```

#### Sub-Router Forwarding

Delegate a path prefix to another router:

```swift
let apiRouter = Router {
    GET("/users") { conn in try conn.json(value: ["users": []]) }
    GET("/users/:id") { conn in try conn.json(value: ["id": conn.params["id"]]) }
}

let app = Router {
    GET("/health") { conn in conn.respond(status: .ok) }
    forward("/api", to: apiRouter)
}
// GET /api/users -> dispatches to apiRouter's GET /users
```

### JSON Handling

#### Decoding Request Bodies

For typed decoding with `Codable`:

```swift
struct CreateUser: Codable, Sendable {
    let name: String
    let email: String
}

POST("/users") { conn in
    let user = try conn.decode(as: CreateUser.self)
    // user.name, user.email are typed
    return try conn.json(status: .created, value: user)
}
```

For dynamic JSON access without a struct:

```swift
POST("/webhook") { conn in
    let json = try conn.jsonBody()
    let event = try json.string("event")     // throws if missing/wrong type
    let count = try json.int("count")
    let nested = try json.object("data")
    let items = try json.array("tags")
    return try conn.json(value: ["received": event])
}
```

#### Encoding Response Bodies

`conn.json(value:)` encodes any `Encodable` value, sets `Content-Type: application/json`, and halts:

```swift
GET("/users") { conn in
    let users = try await fetchUsers()
    return try conn.json(value: users)                    // 200 OK
}

POST("/users") { conn in
    let user = try await createUser(conn)
    return try conn.json(status: .created, value: user)   // 201 Created
}
```

### Query and Form Parameters

#### Query Parameters

Parsed from the URL on each access using form encoding: `+` becomes a space and the last value wins for duplicate
keys, matching Plug. Use `queryParameters` to preserve every value. `parameters` combines query, parsed body,
and path parameters, with path values taking precedence over body values, then query values.

```swift
// GET /search?q=swift&page=2
GET("/search") { conn in
    let query = conn.queryParams["q"] ?? ""     // "swift"
    let page = conn.queryParams["page"] ?? "1"  // "2"
    return try conn.json(value: ["query": query, "page": page])
}
```

#### Form Parameters

Parsed from `application/x-www-form-urlencoded` request bodies. `+` is decoded as space:

```swift
POST("/login") { conn in
    let username = conn.formParams["username"] ?? ""
    let password = conn.formParams["password"] ?? ""
    // authenticate...
    return conn.respond(status: .ok)
}
```

### Cookies

#### Reading Request Cookies

```swift
GET("/dashboard") { conn in
    let sessionId = conn.reqCookies["session_id"]
    // ...
}
```

#### Setting Response Cookies

```swift
POST("/login") { conn in
    let cookie = Cookie(
        name: "session",
        value: "abc123",
        path: "/",
        maxAge: 86400,
        secure: true,
        httpOnly: true,
        sameSite: .lax
    )
    return conn
        .putRespCookie(cookie)
        .respond(status: .ok, body: .string("Logged in"))
}
```

#### Deleting Cookies

```swift
POST("/logout") { conn in
    return conn
        .deleteRespCookie("session")
        .respond(status: .ok, body: .string("Logged out"))
}
```

### Response Headers

```swift
let conn = conn
    .putRespHeader(.init("X-Custom")!, "value")   // Set a header
    .putRespContentType("text/html")               // Set Content-Type
    .deleteRespHeader(.init("X-Old")!)             // Remove a header
    .putStatus(.created)                           // Set status without halting
```

Read request headers:

```swift
let auth = conn.getReqHeader(.authorization)  // String?
let host = conn.host                           // String? from authority
let scheme = conn.scheme                       // String? ("https", "http")
```

### Streaming Responses and SSE

#### Chunked Streaming

```swift
GET("/stream") { conn in
    conn.sendChunked { writer in
        for i in 1...5 {
            try await writer.write("chunk \(i)\n")
            try await Task.sleep(for: .seconds(1))
        }
    }
}
```

#### Server-Sent Events

Use `Connection.sseEvent` to configure the response and write typed events:

```swift
GET("/events") { conn in
    conn.sseEvent { writer in
        for i in 1...10 {
            try await writer.write(SSEEvent(data: "tick \(i)", event: "heartbeat", id: "\(i)"))
            try await Task.sleep(for: .seconds(1))
        }
    }
}
```

Both helpers return a halted connection with a lazy `ResponseBody.producer`. The adapter runs the
producer only while delivering a body; HEAD and bodyless statuses never start it. Await each write
before producing another chunk. Nexus adds no queue or background producer task. Returning completes
the response automatically; throwing aborts it. Keep resource cleanup in `defer`.

Transport writes and task cancellation can stop a producer. Immediate disconnect notification while
the producer is idle is not guaranteed: send periodic SSE heartbeat comments with
`try await writer.write(": heartbeat\n\n")`, and let write failures propagate. The transport and OS
retain their own bounded buffers; awaiting a write does not mean the client has processed the bytes.

**Migration:** chunked writes now require `try await`. Remove `writer.finish()` and replace
`finish(throwing:)` with `throw`. SSE closures now receive a writer: replace continuation `yield(event)`
with `try await writer.write(event)` and remove surrounding `Task` creation. Exhaustive `ResponseBody`
switches must handle `.producer`. Existing `.stream(AsyncThrowingStream)` remains supported, with its
buffering and producer lifecycle still managed by the caller.

### File Serving

`sendFile` streams file contents in 64 KB chunks, automatically detecting the MIME type from the file extension:

```swift
GET("/download/:filename") { conn in
    let filename = conn.params["filename"] ?? ""
    return try conn.sendFile(path: "/var/www/files/\(filename)")
}
```

Files open when body delivery starts. Each read follows the previous awaited write, and the file closes
on completion or failure. A file that disappears or becomes unreadable after response preparation causes
a stream failure. `chunkSize` must be positive.

> **Warning:** `sendFile` does not validate against directory traversal attacks. Always sanitize user-provided paths before passing them to this method. For serving an entire directory safely, use `staticFiles` instead.

### Static File Serving

The `staticFiles` plug maps a URL prefix to a filesystem directory, with path traversal protection, MIME type inference, and extension filtering. This is the Nexus equivalent of Elixir's `Plug.Static`:

```swift
let app = pipeline([
    staticFiles(StaticFilesConfig(at: "/static", from: "./priv/static")),
    router.callAsFunction,
])
// GET /static/css/app.css  -> serves ./priv/static/css/app.css
// GET /static/js/main.js   -> serves ./priv/static/js/main.js
// GET /api/users            -> passes through to router
```

Only GET and HEAD requests are handled. When a file is not found, the plug sets 404 **without halting** -- downstream plugs can still handle the path.

Extension filtering with `only` and `except`:

```swift
let assets = staticFiles(StaticFilesConfig(
    at: "/assets",
    from: "./public",
    only: ["css", "js", "png", "jpg", "svg", "woff2"]
))
```

### Sessions

Nexus provides signed, cookie-based sessions using HMAC-SHA256 via Apple's CryptoKit. Session data is stored in the cookie itself -- signed but not encrypted.

#### Setup

```swift
let secret = Data("my-32-byte-minimum-secret-key!!!".utf8)

let app = pipeline([
    sessionPlug(SessionConfig(secret: secret)),
    router.callAsFunction,
])
```

`SessionConfig` supports all standard cookie attributes (`path`, `domain`, `maxAge`, `secure`, `httpOnly`, `sameSite`).

#### Reading and Writing

```swift
POST("/login") { conn in
    let user = try authenticate(conn)
    return conn
        .putSession(key: "user_id", value: user.id)
        .respond(status: .ok)
}

GET("/profile") { conn in
    guard let userId = conn.getSession("user_id") else {
        return conn.respond(status: .unauthorized)
    }
    let user = try await fetchUser(userId)
    return try conn.json(value: user)
}

POST("/logout") { conn in
    conn.clearSession()
        .respond(status: .ok)
}
```

| Method | Description |
|--------|-------------|
| `getSession(_:)` | Read a value. Returns `nil` if not present. |
| `getSession()` / `getSession(_:default:)` | Read all values or supply a fallback for a missing key. |
| `putSession(key:value:)` | Write a key-value pair. Returns a new connection. |
| `deleteSession(_:)` | Remove a single key. Returns a new connection. |
| `clearSession()` | Remove all data and mark the cookie for deletion. |
| `clearSession(drop: false)` | Remove all data while retaining an empty session cookie. |
| `renewSession()` | Reissue the cookie with the current data. |
| `configureSession(renew:drop:ignore:)` | Control persistence; when combined, renew takes precedence over drop, then ignore. |

Repeated session fetches and repeated use of the same session plug preserve in-request changes and register
one persistence hook. Cookie renewal reissues signed data; it does not invalidate previously issued cookies.

#### MessageSigning

The `MessageSigning` enum provides low-level HMAC-SHA256 sign/verify that can be used independently:

```swift
let token = MessageSigning.sign(payload: Data("user_id=42".utf8), secret: secret)
if let payload = MessageSigning.verify(token: token, secret: secret) {
    // payload is the original Data
}
```

### CSRF Protection

Token-based cross-site request forgery prevention. Requires sessions.

```swift
let app = pipeline([
    sessionPlug(SessionConfig(secret: secret)),
    csrfProtection(),       // must come after sessionPlug
    router.callAsFunction,
])
```

- **GET, HEAD, OPTIONS** -- skip validation, ensure token exists in session
- **POST, PUT, PATCH, DELETE** -- validate token from `_csrf_token` form parameter or `x-csrf-token` header. Returns 403 on mismatch.

Embed the token in forms or JSON responses:

```swift
GET("/form") { conn in
    let (token, conn) = csrfToken(conn: conn)
    let html = """
    <form method="post">
        <input type="hidden" name="_csrf_token" value="\(token)">
        <button>Submit</button>
    </form>
    """
    return conn.respond(status: .ok, body: .string(html))
}
```

### Error Rescue

`NexusHTTPError` can be thrown for convenience when the halt pattern is too verbose. Wrap your pipeline with `rescueErrors(_:)` to catch them:

```swift
GET("/users/:id") { conn in
    guard let user = try await findUser(conn.params["id"]) else {
        throw NexusHTTPError(.notFound, message: "User not found")
    }
    return try conn.json(value: user)
}

// Wrap the pipeline
let app = rescueErrors(pipeline([logger, router.callAsFunction]))
```

`rescueErrors` catches `NexusHTTPError` and converts it to a halted response. Non-`NexusHTTPError` errors propagate to the server adapter's generic 500 handler.

### Lifecycle Hooks

Register callbacks that run just before the response is sent. Callbacks execute in LIFO order:

```swift
let addTimingHeader: Plug = { conn in
    let start = ContinuousClock.now
    return conn.registerBeforeSend { c in
        let elapsed = ContinuousClock.now - start
        return c.putRespHeader(.init("X-Response-Time")!, "\(elapsed)")
    }
}
```

The server adapter calls `connection.runBeforeSend()` before serializing the response.

### Service Injection

The `assign(_:value:)` plug factory injects any `Sendable` value into `conn.assigns`, making shared services (database repos, API clients, config) available throughout the pipeline without closure capture:

```swift
let spectro = try SpectroClient(...)
let app = pipeline([
    requestId(),
    assign("spectro", value: spectro),
    router.callAsFunction,
])
```

Route handlers read the injected value from assigns:

```swift
GET("/donuts") { conn in
    let spectro = conn.assigns["spectro"] as! SpectroClient
    let donuts = try await spectro.repository().all(Donut.self)
    return try conn.json(value: donuts)
}
```

A closure-based variant evaluates lazily per request:

```swift
assign("trace_id") { UUID().uuidString }
```

Combine with typed assigns (below) for compile-time-safe access.

### Typed Assigns

The `AssignKey` protocol provides type-safe access to connection assigns, replacing stringly-typed casts with compile-time-checked subscripts:

```swift
// Define a key
enum SpectroKey: AssignKey {
    typealias Value = SpectroClient
}

// Write -- typed
conn = conn.assign(SpectroKey.self, value: spectro)

// Read -- typed, no cast needed
let spectro = conn[SpectroKey.self]  // SpectroClient?
```

#### Built-in Keys

Nexus provides typed keys for values set by built-in plugs:

| Key | Value Type | Set by |
|-----|-----------|--------|
| `RequestIdKey` | `String` | `requestId()` plug |
| `SessionKey` | `[String: String]` | Session plug |
| `RemoteIPKey` | `String` | Server adapter |

Convenience accessors on `Connection`:

```swift
conn.requestId  // String? -- shorthand for conn[RequestIdKey.self]
conn.session    // [String: String]?
conn.remoteIP   // String?
```

#### Backward Compatibility

Typed and string-based APIs share the same underlying `assigns` dictionary. Both read and write patterns coexist -- consumers migrate at their own pace:

```swift
// Typed write, string read
conn = conn.assign(RequestIdKey.self, value: "abc")
conn.assigns["RequestIdKey"] as? String  // "abc"

// String write, typed read
conn = conn.assign(key: "RequestIdKey", value: "xyz")
conn[RequestIdKey.self]  // "xyz"
```

### WebSocket

Nexus provides WebSocket support with functional handlers, consistent with the Plug philosophy. WebSocket types live in Nexus core; the upgrade mechanism lives in NexusHummingbird.

#### Core Types

| Type | Description |
|------|-------------|
| `WSMessage` | Enum: `.text(String)`, `.binary(Data)`, `.ping`, `.pong`, `.close(code:reason:)` |
| `WSConnection` | Carries `assigns` from the HTTP upgrade and a `send` function |
| `WSHandler` | `@Sendable (WSConnection, WSMessage) async throws -> Void` |
| `WSConnectHandler` | `@Sendable (Connection) async throws -> WSConnection` |

#### Defining WebSocket Routes

Use the `WS()` builder to create WebSocket routes. The `onUpgrade` closure inspects the HTTP `Connection` (with all assigns from upstream plugs) and returns a `WSConnection`. Throw to reject the upgrade.

```swift
import NexusRouter

let echo = WS("/ws/echo", onUpgrade: { conn in
    // Authenticate, extract params, propagate assigns
    WSConnection(assigns: conn.assigns, send: { _ in })
}, onMessage: { ws, message in
    switch message {
    case .text(let text):
        try await ws.send(.text("Echo: \(text)"))
    case .binary(let data):
        try await ws.send(.binary(data))
    default:
        break
    }
})
```

#### Running with Hummingbird

Register WebSocket routes via `.nexusWebSocket()` server builder. Non-WebSocket requests fall through to the normal HTTP responder:

```swift
import NexusHummingbird
import Hummingbird

let wsRoutes = [echo]
let adapter = NexusHummingbirdAdapter(plug: myPipeline)

let app = Application(
    responder: adapter,
    server: .nexusWebSocket(routes: wsRoutes, plug: myPipeline)
)
try await server.runService()
```

The optional `plug:` parameter runs the HTTP pipeline on upgrade requests, so authentication, session, and request-ID plugs populate `Connection.assigns` before the `WSConnectHandler` runs.

### Configurable Plugs

For plugs that need a one-time configuration phase (option validation, expensive setup), implement `ConfigurablePlug`:

```swift
struct SecurityHeaders: ConfigurablePlug {
    let includeHSTS: Bool

    init(options: Bool) {
        self.includeHSTS = options
    }

    func call(_ connection: Connection) async throws -> Connection {
        var conn = connection
        conn.response.headerFields[.xContentTypeOptions] = "nosniff"
        if includeHSTS {
            conn.response.headerFields[.strictTransportSecurity] = "max-age=31536000"
        }
        return conn
    }
}

// Bridge to Plug with asPlug()
let securityPlug = try SecurityHeaders(options: true).asPlug()
let app = pipeline([securityPlug, router.callAsFunction])
```

### Running with Hummingbird

`NexusHummingbirdAdapter` implements Hummingbird's `HTTPResponder` protocol:

```swift
import Hummingbird
import Nexus
import NexusRouter
import NexusHummingbird

let router = Router {
    GET("/") { conn in
        conn.respond(status: .ok, body: .string("Hello from Nexus!"))
    }
}

let app = rescueErrors(pipeline([
    requestId(),
    requestLogger(),
    corsPlug(CORSConfig(allowedOrigin: "https://example.com")),
    router.callAsFunction,
]))

let adapter = NexusHummingbirdAdapter(
    plug: app,
    maxRequestBodySize: 4_194_304  // 4 MB (default)
)

let server = Application(responder: adapter)
try await server.runService()
```

The adapter:

1. Converts a Hummingbird `Request` into a Nexus `Connection` (buffering the body up to `maxRequestBodySize`)
2. Populates `connection.remoteIP` from the NIO channel
3. Runs the plug pipeline
4. Calls `runBeforeSend()` for lifecycle hooks
5. Converts the resulting `Connection` back to a Hummingbird `Response`
6. Catches thrown errors and returns a generic 500

## Built-in Plugs

| Plug | Description | Usage |
|------|-------------|-------|
| `assign()` | Injects a `Sendable` value into assigns. Static and closure-based overloads. | `assign("db", value: repo)` or `assign("id") { UUID().uuidString }` |
| `requestLogger()` | Logs `METHOD /path -> STATUS (Xms)` via a configurable logger closure. Uses `beforeSend` to capture the final status. | `requestLogger()` or `requestLogger { msg in myLogger.info(msg) }` |
| `requestId()` | Generates a UUID, sets `X-Request-Id` response header, stores in `assigns["request_id"]` and `RequestIdKey`. | `requestId()` or `requestId(generator: { customId() })` |
| `corsPlug()` | Adds `Access-Control-*` headers. Handles OPTIONS preflight with 204 No Content. | `corsPlug()` or `corsPlug(CORSConfig(allowedOrigin: "https://example.com"))` |
| `basicAuth()` | Parses `Authorization: Basic` header. Validates with a closure. Returns 401 with `WWW-Authenticate` on failure. Stores username in `assigns["basic_auth_username"]`. | `basicAuth { user, pass in user == "admin" && pass == "secret" }` |
| `sslRedirect()` | Redirects non-HTTPS requests with 301 Moved Permanently. | `sslRedirect()` or `sslRedirect(host: "example.com")` |
| `sessionPlug()` | Signed cookie-based sessions with HMAC-SHA256 (CryptoKit). Reads/writes session data via `beforeSend`. | `sessionPlug(SessionConfig(secret: mySecret))` |
| `csrfProtection()` | Token-based CSRF prevention. Validates on POST/PUT/PATCH/DELETE. Requires `sessionPlug`. | `csrfProtection()` or `csrfProtection(CSRFConfig(formParam: "authenticity_token"))` |
| `staticFiles()` | Serves a directory of static files from a URL prefix. Path traversal protection, extension filtering. | `staticFiles(StaticFilesConfig(at: "/static", from: "./public"))` |
| `rescueErrors()` | Catches `NexusHTTPError` and converts to halted responses. Non-Nexus errors propagate. | `rescueErrors(pipeline([...]))` |

## Testing

Nexus uses [Swift Testing](https://developer.apple.com/documentation/testing/) (`import Testing`), not XCTest.

### Running Tests

```bash
# Run all tests
swift test

# Run only core tests
swift test --filter NexusTests

# Run only router tests
swift test --filter NexusRouterTests

# Run Hummingbird adapter tests
swift test --filter NexusHummingbirdTests
```

### Using TestConnection

The `NexusTest` target provides `TestConnection` builders that eliminate `HTTPRequest` boilerplate:

```swift
import Testing
import Nexus
import NexusTest

@Suite("MyMiddleware")
struct MyMiddlewareTests {

    @Test("test_myPlug_validRequest_returns200")
    func test_myPlug_validRequest_returns200() async throws {
        let conn = TestConnection.build(method: .get, path: "/health")
        let result = try await myPlug(conn)
        #expect(result.response.status == .ok)
    }

    @Test("test_myPlug_withJsonBody_decodesCorrectly")
    func test_myPlug_withJsonBody_decodesCorrectly() async throws {
        let conn = TestConnection.buildJSON(
            method: .post,
            path: "/users",
            json: #"{"name":"Alice","email":"alice@example.com"}"#
        )
        let result = try await myPlug(conn)
        #expect(result.response.status == .created)
    }

    @Test("test_myPlug_withFormBody_parsesParams")
    func test_myPlug_withFormBody_parsesParams() async throws {
        let conn = TestConnection.buildForm(
            method: .post,
            path: "/login",
            form: "username=admin&password=secret"
        )
        #expect(conn.formParams["username"] == "admin")
    }
}
```

### Test Naming Convention

Tests follow the pattern `test_<subject>_<scenario>_<expectation>` and are grouped with `@Suite("TypeName")`.

### Testing Patterns for Sendable

When testing plugs that capture state in `@Sendable` closures, use actors instead of mutable variables to satisfy strict concurrency:

```swift
actor LogCapture {
    var lines: [String] = []
    func append(_ line: String) { lines.append(line) }
}

@Test("test_requestLogger_logsRequestDetails")
func test_requestLogger_logsRequestDetails() async throws {
    let capture = LogCapture()
    let logger = requestLogger { line in
        Task { await capture.append(line) }
    }
    // ...
}
```

## Available Commands

| Command | Description |
|---------|-------------|
| `swift build` | Build all library targets |
| `swift test` | Run all test suites |
| `swift test --filter NexusTests` | Run core tests only |
| `swift test --filter NexusRouterTests` | Run router tests only |
| `swift test --filter NexusHummingbirdTests` | Run adapter tests only |
| `swift package resolve` | Fetch/update dependencies |
| `swift package clean` | Remove build artifacts |

## CI

GitHub Actions runs on every push and pull request to `main`:

| Job | Platform | What it does |
|-----|----------|-------------|
| **Build (macOS)** | macOS 15 | `swift build` + `swift build --build-tests` |
| **Build (Linux)** | Ubuntu (swift:6.1) | `swift build` |
| **Test** | Ubuntu (swift:6.1) | `swift test` with NIO teardown crash resilience |

Configuration: [`.github/workflows/ci.yml`](.github/workflows/ci.yml)

## Architecture Decision Records

The `Docs/ADR/` directory contains Architecture Decision Records documenting key design choices:

| ADR | Title | Summary |
|-----|-------|---------|
| [ADR-001](Docs/ADR/ADR-001.md) | Use swift-http-types | Adopt Apple's HTTP primitives instead of rolling custom types. Zero-dep interop with Hummingbird and Swift OpenAPI. |
| [ADR-002](Docs/ADR/ADR-002.md) | Body is an enum | `RequestBody`/`ResponseBody` as enums with `.empty`, `.buffered`, `.stream` cases. Exhaustive switch prevents ignoring streaming. |
| [ADR-003](Docs/ADR/ADR-003.md) | Plug is a function typealias | `Plug` is `@Sendable (Connection) async throws -> Connection`, not a protocol. Zero boilerplate, trivially composable. |
| [ADR-004](Docs/ADR/ADR-004.md) | Throws vs halting | HTTP errors halt; infrastructure failures throw. Clear separation of intentional responses from unexpected failures. |
| [ADR-005](Docs/ADR/ADR-005.md) | Three-target layout | One repo, three library targets. Consumers only pull dependencies they use. |
| [ADR-006](Docs/ADR/ADR-006.md) | Lifecycle hooks + ConfigurablePlug | `beforeSend` callbacks for final-response modification. `ConfigurablePlug` protocol for two-phase init/call. |
| [ADR-007](Docs/ADR/ADR-007.md) | Connection parity and HTTP semantics | Parameter precedence, session persistence, zlib compression, and adapter behavior. |
| [ADR-008](Docs/ADR/ADR-008.md) | Response producers follow transport demand | Lazy producers, awaited writes, automatic completion, and explicit disconnect limits. |

Consult these before changing API shape or introducing new architectural patterns.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for the full guide. Key points:

- No force unwraps (`!`) anywhere in the codebase
- No `@unchecked Sendable` in the `Nexus` core target
- All public symbols require `///` doc comments
- Tests follow `test_<subject>_<scenario>_<expectation>` naming
- Conventional commits: `feat:`, `fix:`, `refactor:`, `test:`, `docs:`, `ci:`, `chore:`
- 120-character line limit, 4-space indentation, trailing commas

### Pull Request Checklist

- [ ] `swift build` passes with zero warnings
- [ ] `swift test` passes
- [ ] New public symbols have doc comments
- [ ] No force unwraps introduced
- [ ] No `@unchecked Sendable` added to the `Nexus` target
- [ ] Tests follow the naming convention
- [ ] ADR included if the change affects architecture or API shape

## License

See the project repository for license details.
