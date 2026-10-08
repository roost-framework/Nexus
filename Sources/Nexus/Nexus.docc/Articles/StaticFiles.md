# Static Files

Serve an entire directory of static assets from a URL prefix.

## Overview

The ``staticFiles(_:)`` plug maps a URL prefix to a filesystem directory and
serves matching files. This is the Nexus equivalent of Elixir's `Plug.Static`.

Unlike ``Connection/sendFile(path:contentType:chunkSize:)`` which serves
individual files, `staticFiles` handles an entire directory tree with
automatic MIME type detection, path traversal protection, and extension
filtering.

## Basic Usage

```swift
let app = pipeline([
    staticFiles(StaticFilesConfig(at: "/static", from: "./priv/static")),
    router.callAsFunction,
])
```

With this configuration:
- `GET /static/css/app.css` serves `./priv/static/css/app.css`
- `GET /static/js/main.js` serves `./priv/static/js/main.js`
- `GET /static/images/logo.png` serves `./priv/static/images/logo.png`
- `GET /api/users` passes through to the router

## Configuration

```swift
let config = StaticFilesConfig(
    at: "/assets",              // URL prefix to match
    from: "./public",           // Filesystem root (resolved to absolute at init)
    only: ["css", "js", "png"], // Optional: only serve these extensions
    except: ["exe", "sh"],      // Optional: never serve these extensions
    chunkSize: 65_536           // Bytes per stream chunk (default)
)
```

### Extension Filtering

Use `only` to restrict which file types are served:

```swift
// Only serve web assets
let assets = staticFiles(StaticFilesConfig(
    at: "/static",
    from: "./public",
    only: ["css", "js", "png", "jpg", "svg", "woff2"]
))
```

Use `except` to block specific types:

```swift
// Serve everything except executables
let files = staticFiles(StaticFilesConfig(
    at: "/files",
    from: "./uploads",
    except: ["exe", "sh", "bat"]
))
```

## Behavior

### Methods

Only **GET** and **HEAD** requests are handled. All other methods (POST, PUT,
DELETE, etc.) pass through to downstream plugs unchanged.

HEAD requests return the same headers as GET but with an empty body.

### File Not Found

When a requested file does not exist, the plug sets the status to **404 but
does not halt**. This matches Elixir's `Plug.Static` behavior and allows
downstream plugs (like a router) to handle the path.

```swift
// Static files first, router as fallback
let app = pipeline([
    staticFiles(StaticFilesConfig(at: "/", from: "./public")),
    router.callAsFunction,  // handles paths not found as static files
])
```

### Security

The plug includes multiple layers of path traversal protection:

1. **Segment check** — rejects paths containing `..` segments with 403 Forbidden
2. **Null byte check** — rejects paths containing null bytes
3. **Resolved path validation** — after resolving symlinks, verifies the final
   path is still under the configured root directory

### MIME Types

Content types are inferred automatically from file extensions using the same
internal MIME type table used by
``Connection/sendFile(path:contentType:chunkSize:)``.

## Topics

### API
- ``StaticFilesConfig``
- ``staticFiles(_:)``
