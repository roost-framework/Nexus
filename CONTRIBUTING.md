# Contributing to Nexus

Thank you for your interest in contributing. This document describes the coding
conventions and review expectations for this project.

---

## Development Setup

```bash
git clone https://github.com/Spectro-ORM/Nexus.git
cd Nexus
swift build
swift test
```

Requires Swift 6.0.3 or later.

---

## Coding Conventions

### No Force Unwraps

Force unwraps (`!`) are **not permitted** anywhere in the codebase. Use `guard let`,
`if let`, `?? default`, or restructure the call site to eliminate the optional.

If you believe a force unwrap is truly warranted, open a discussion issue before
submitting a PR — there is almost always a safer alternative.

### No `@unchecked Sendable` in the `Nexus` Target

The `Nexus` core target must achieve `Sendable` correctness through genuine type-system
guarantees — not suppression. `@unchecked Sendable` is **not permitted** in
`Sources/Nexus/`.

It may be used sparingly in adapter or test targets when wrapping third-party types that
are documented as thread-safe but have not yet been annotated, provided a comment
explains why it is safe.

### All Public Symbols Require Doc Comments

Every `public` or `open` declaration must have a documentation comment using Swift's
`///` syntax. At minimum, the comment must describe:

- What the type/function/property represents or does.
- Any preconditions or invariants a caller must respect.
- Throws/errors, if applicable.

Use `- Parameter:`, `- Returns:`, and `- Throws:` doc tags for functions with non-obvious
signatures.

```swift
// Bad
public func pipe(_ first: Plug, _ second: Plug) -> Plug { … }

// Good
/// Returns a plug that runs `first` followed by `second`, short-circuiting
/// if `first` halts the connection.
///
/// - Parameters:
///   - first: The upstream plug.
///   - second: The downstream plug, skipped when the connection is halted.
/// - Returns: A composed plug.
public func pipe(_ first: Plug, _ second: Plug) -> Plug { … }
```

### Test Naming Convention

Tests follow `test_<subject>_<scenario>_<expectation>`:

```swift
// Subject:     connection
// Scenario:    halted() is called
// Expectation: isHalted becomes true
@Test("test_connection_halted_returnsHaltedCopy")
func test_connection_halted_returnsHaltedCopy() { … }
```

Use `@Suite("TypeName")` to group tests by the type under test.

---

## Error Signalling Contract

Follow ADR-004 strictly:

- **HTTP-level errors** (401, 403, 404, 422, …) → build the response, return
  `connection.halted()`. **Do not throw.**
- **Infrastructure failures** (I/O, database, unexpected state) → `throw` an `Error`.

Throwing an `HTTPError` (or equivalent) to signal a 404 is a bug, not a feature.
See `Docs/ADR/ADR-004.md` for full rationale.

---

## Pull Request Checklist

- [ ] `swift build` passes with zero warnings.
- [ ] `swift test` passes.
- [ ] New public symbols have doc comments.
- [ ] No force unwraps introduced.
- [ ] No `@unchecked Sendable` added to the `Nexus` target.
- [ ] Tests follow the `test_<subject>_<scenario>_<expectation>` naming convention.
- [ ] If the change affects architecture or API shape, a new or updated ADR is included.

---

## Commit Style

Use conventional commit prefixes:

| Prefix | When to use |
|---|---|
| `feat:` | New public API or behaviour |
| `fix:` | Bug fix |
| `refactor:` | Internal restructuring, no behaviour change |
| `test:` | Adding or fixing tests |
| `docs:` | Documentation changes only |
| `ci:` | CI / workflow changes |
| `chore:` | Dependency updates, tooling |

---

## License

By contributing, you agree that your contributions will be licensed under the same
license as this project.
