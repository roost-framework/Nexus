# ``Nexus``

A composable HTTP middleware pipeline library for Swift, inspired by Elixir's Plug.

## Overview

Nexus lets you build HTTP applications by composing middleware ("plugs") as plain functions
that transform a ``Connection`` value flowing through a pipeline. Everything is a function,
everything is a value type, and everything is `Sendable`.

```swift
let app = pipeline([
    requestId(),
    requestLogger(),
    sessionPlug(SessionConfig(secret: mySecret)),
    csrfProtection(),
    staticFiles(StaticFilesConfig(at: "/static", from: "./priv/static")),
    router.callAsFunction,
])
```

### Core Design

- **``Plug`` is a function typealias** — `@Sendable (Connection) async throws -> Connection`.
  No protocols, no registration. Write a closure, get middleware.
- **``Connection`` is a value type** — every plug returns a new copy. Thread-safe by construction.
- **Halt, don't throw** — HTTP errors (4xx/5xx) set status and halt. Infrastructure failures throw.
- **Composition over configuration** — `pipe(_:_:)` and `pipeline(_:)` compose any two plugs.

## Topics

### Essentials

- ``Connection``
- ``Plug``
- ``RequestBody``
- ``ResponseBody``
- ``pipe(_:_:)``
- ``pipeline(_:)``

### Sessions and Security

- <doc:Sessions>
- <doc:CSRFProtection>
- ``MessageSigning``
- ``SessionConfig``
- ``CSRFConfig``
- ``sessionPlug(_:)``
- ``csrfProtection(_:)``
- ``csrfToken(conn:config:)``

### Static File Serving

- <doc:StaticFiles>
- ``StaticFilesConfig``
- ``staticFiles(_:)``

### Built-in Plugs

- ``requestLogger(_:)``
- ``requestId(generator:headerName:)``
- ``corsPlug(_:)``
- ``basicAuth(realm:validate:)``
- ``sslRedirect(host:)``
- ``rescueErrors(_:)``

### Request Parsing

- ``Cookie``
- ``JSONValue``

### Streaming

- ``ResponseBodyWriter``
- ``Connection/sendChunked(status:handler:)``
- ``Connection/sseEvent(contentType:body:)``
- ``SSEEvent``
- ``sseEvent(data:event:id:retry:)``
