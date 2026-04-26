import Testing
import HTTPTypes
@testable import Nexus
@testable import NexusRouter

/// Tests for PathPattern matching edge cases
@Suite("PathPattern Edge Cases")
struct PathPatternEdgeCasesTests {

    // MARK: - Pattern Parsing Edge Cases

    @Test("PathPattern with empty path")
    func pathPatternEmpty() {
        // Note: Empty path splits to empty array
        // Let's test with root path
        let pattern = PathPattern("/")

        #expect(pattern.segments.isEmpty)
    }

    @Test("PathPattern with single literal segment")
    func pathPatternSingleLiteral() {
        let pattern = PathPattern("/users")

        #expect(pattern.segments.count == 1)
        if case .literal(let value) = pattern.segments[0] {
            #expect(value == "users")
        }
    }

    @Test("PathPattern with multiple literal segments")
    func pathPatternMultipleLiterals() {
        let pattern = PathPattern("/api/v1/users")

        #expect(pattern.segments.count == 3)
        if case .literal(let v1) = pattern.segments[0],
           case .literal(let v2) = pattern.segments[1],
           case .literal(let v3) = pattern.segments[2] {
            #expect(v1 == "api")
            #expect(v2 == "v1")
            #expect(v3 == "users")
        }
    }

    @Test("PathPattern with parameter segment")
    func pathPatternParameter() {
        let pattern = PathPattern("/users/:id")

        #expect(pattern.segments.count == 2)
        if case .literal(let v1) = pattern.segments[0],
           case .parameter(let v2) = pattern.segments[1] {
            #expect(v1 == "users")
            #expect(v2 == "id")
        }
    }

    @Test("PathPattern with multiple parameters")
    func pathPatternMultipleParameters() {
        let pattern = PathPattern("/users/:userId/posts/:postId")

        #expect(pattern.segments.count == 4)
        if case .literal(let v1) = pattern.segments[0],
           case .parameter(let v2) = pattern.segments[1],
           case .literal(let v3) = pattern.segments[2],
           case .parameter(let v4) = pattern.segments[3] {
            #expect(v1 == "users")
            #expect(v2 == "userId")
            #expect(v3 == "posts")
            #expect(v4 == "postId")
        }
    }

    @Test("PathPattern with unnamed wildcard")
    func pathPatternUnnamedWildcard() {
        let pattern = PathPattern("/files/*")

        #expect(pattern.segments.count == 2)
        if case .literal(let v1) = pattern.segments[0],
           case .wildcard(let v2) = pattern.segments[1] {
            #expect(v1 == "files")
            #expect(v2 == nil)
        }
    }

    @Test("PathPattern with named wildcard")
    func pathPatternNamedWildcard() {
        let pattern = PathPattern("/files/*path")

        #expect(pattern.segments.count == 2)
        if case .literal(let v1) = pattern.segments[0],
           case .wildcard(let v2) = pattern.segments[1] {
            #expect(v1 == "files")
            #expect(v2 == "path")
        }
    }

    @Test("PathPattern with mixed segments")
    func pathPatternMixed() {
        let pattern = PathPattern("/api/:version/files/*path")

        #expect(pattern.segments.count == 4)
        if case .literal = pattern.segments[0],  // api
           case .parameter = pattern.segments[1],  // version
           case .literal = pattern.segments[2],  // files
           case .wildcard = pattern.segments[3] {  // path
            // All segments match expected types
        }
    }

    @Test("PathPattern with trailing slash")
    func pathPatternTrailingSlash() {
        let pattern = PathPattern("/users/")

        // Trailing slash is stripped by split
        #expect(pattern.segments.count == 1)
        if case .literal(let value) = pattern.segments[0] {
            #expect(value == "users")
        }
    }

    @Test("PathPattern with double slashes")
    func pathPatternDoubleSlashes() {
        let pattern = PathPattern("/api//users")

        // Empty segments are omitted
        #expect(pattern.segments.count == 2)
        if case .literal(let v1) = pattern.segments[0],
           case .literal(let v2) = pattern.segments[1] {
            #expect(v1 == "api")
            #expect(v2 == "users")
        }
    }

    // MARK: - Matching Edge Cases

    @Test("match with exact path")
    func matchExactPath() {
        let pattern = PathPattern("/users")
        let result = pattern.match("/users")

        #expect(result != nil)
        #expect(result?.isEmpty ?? false)  // No params
    }

    @Test("match with different path fails")
    func matchDifferentPathFails() {
        let pattern = PathPattern("/users")
        let result = pattern.match("/posts")

        #expect(result == nil)
    }

    @Test("match with parameter extracts value")
    func matchParameterExtraction() {
        let pattern = PathPattern("/users/:id")
        let result = pattern.match("/users/123")

        #expect(result != nil)
        #expect(result?["id"] == "123")
    }

    @Test("match with multiple parameters")
    func matchMultipleParameters() {
        let pattern = PathPattern("/users/:userId/posts/:postId")
        let result = pattern.match("/users/42/posts/99")

        #expect(result != nil)
        #expect(result?["userId"] == "42")
        #expect(result?["postId"] == "99")
    }

    @Test("match with unnamed wildcard")
    func matchUnnamedWildcard() {
        let pattern = PathPattern("/files/*")
        let result = pattern.match("/files/path/to/file.txt")

        #expect(result != nil)
        #expect(result?.isEmpty ?? false)  // Unnamed wildcard doesn't capture
    }

    @Test("match with named wildcard")
    func matchNamedWildcard() {
        let pattern = PathPattern("/files/*path")
        let result = pattern.match("/files/path/to/file.txt")

        #expect(result != nil)
        #expect(result?["path"] == "path/to/file.txt")
    }

    @Test("match wildcard captures zero segments")
    func matchWildcardZeroSegments() {
        let pattern = PathPattern("/files/*")
        let result = pattern.match("/files")

        #expect(result != nil)
    }

    @Test("match wildcard captures many segments")
    func matchWildcardManySegments() {
        let pattern = PathPattern("/files/*path")
        let result = pattern.match("/files/a/b/c/d/e/f")

        #expect(result != nil)
        #expect(result?["path"] == "a/b/c/d/e/f")
    }

    @Test("match with query string strips query")
    func matchStripsQueryString() {
        let pattern = PathPattern("/users")
        let result = pattern.match("/users?foo=bar&baz=qux")

        #expect(result != nil)
    }

    @Test("match parameter with query string")
    func matchParameterWithQuery() {
        let pattern = PathPattern("/users/:id")
        let result = pattern.match("/users/123?active=true")

        #expect(result != nil)
        #expect(result?["id"] == "123")
    }

    @Test("match with empty segment in request path")
    func matchEmptySegmentInRequest() {
        let pattern = PathPattern("/users")
        let result = pattern.match("/users//")

        // Empty segments are omitted, so this should match
        #expect(result != nil)
    }

    @Test("match parameter with percent encoding")
    func matchPercentEncoding() {
        let pattern = PathPattern("/users/:name")
        let result = pattern.match("/users/John%20Doe")

        #expect(result != nil)
        #expect(result?["name"] == "John Doe")  // Decoded
    }

    @Test("match parameter with special characters")
    func matchSpecialCharacters() {
        let pattern = PathPattern("/files/:name")
        let result = pattern.match("/files/file%20with%20spaces%2Fslashes.txt")

        #expect(result != nil)
        #expect(result?["name"] == "file with spaces/slashes.txt")
    }

    @Test("match fails when segment counts differ")
    func matchSegmentCountMismatch() {
        let pattern = PathPattern("/users/:id")
        let result = pattern.match("/users/123/extra")

        #expect(result == nil)
    }

    @Test("match fails when parameter segment is empty")
    func matchEmptyParameterSegment() {
        let pattern = PathPattern("/users/:id")
        let result = pattern.match("/users/")

        // Empty parameter doesn't match
        #expect(result == nil)
    }

    @Test("match literal case sensitivity")
    func matchLiteralCaseSensitive() {
        let pattern = PathPattern("/Users")
        let result = pattern.match("/users")

        #expect(result == nil)  // Case sensitive
    }

    @Test("match with empty string parameter")
    func matchEmptyStringParameter() {
        let pattern = PathPattern("/users/:id")
        // URL with double slash creates empty segment
        let result = pattern.match("/users//")

        #expect(result == nil)
    }

    @Test("match wildcard after parameters")
    func matchWildcardAfterParameters() {
        let pattern = PathPattern("/api/:version/*path")
        let result = pattern.match("/api/v2/some/long/path")

        #expect(result != nil)
        #expect(result?["version"] == "v2")
        #expect(result?["path"] == "some/long/path")
    }

    @Test("match parameters before wildcard")
    func matchParametersBeforeWildcard() {
        let pattern = PathPattern("/users/:userId/files/*")
        let result = pattern.match("/users/42/files/a/b/c.txt")

        #expect(result != nil)
        #expect(result?["userId"] == "42")
    }

    // MARK: - Edge Cases and Error Conditions

    @Test("match with only slashes")
    func matchOnlySlashes() {
        let pattern = PathPattern("///")
        let result = pattern.match("///")

        // All slashes are empty segments, which are omitted
        #expect(result != nil)
    }

    @Test("match root path with root pattern")
    func matchRootPathWithRootPattern() {
        let pattern = PathPattern("/")
        let result = pattern.match("/")

        #expect(result != nil)
    }

    @Test("match root path with non-root pattern fails")
    func matchRootPathWithNonRootPattern() {
        let pattern = PathPattern("/users")
        let result = pattern.match("/")

        #expect(result == nil)
    }

    @Test("match non-root path with root pattern fails")
    func matchNonRootPathWithRootPattern() {
        let pattern = PathPattern("/")
        let result = pattern.match("/users")

        #expect(result == nil)
    }

    @Test("match with hash in path")
    func matchWithHashInPath() {
        let pattern = PathPattern("/files/:name")
        let result = pattern.match("/files/file#123")

        #expect(result != nil)
        #expect(result?["name"] == "file#123")
    }

    @Test("match with plus sign in parameter")
    func matchWithPlusSign() {
        let pattern = PathPattern("/search/:query")
        let result = pattern.match("/search/swift+testing")

        #expect(result != nil)
        #expect(result?["query"] == "swift+testing")
    }

    @Test("match with equals sign in parameter")
    func matchWithEqualsSign() {
        let pattern = PathPattern("/params/:key")
        let result = pattern.match("/params/name=value")

        #expect(result != nil)
        #expect(result?["key"] == "name=value")
    }

    @Test("match with query string stripped from parameter")
    func matchWithQueryStringStripped() {
        // Query strings are stripped before matching; :url captures only the path segment
        let pattern = PathPattern("/redirect/:slug")
        let result = pattern.match("/redirect/my-page?from=home")

        #expect(result != nil)
        #expect(result?["slug"] == "my-page")
    }

    @Test("path with :// splits into multiple segments")
    func pathWithDoubleSlashSplits() {
        // "http://example.com" splits into ["http:", "", "example.com"] segments;
        // pattern /link/:url has only 2 segments so cannot match
        let pattern = PathPattern("/link/:url")
        let result = pattern.match("/link/http://example.com?a=1&b=2")
        #expect(result == nil)
    }

    @Test("match Unicode path segments")
    func matchUnicodeSegments() {
        let pattern = PathPattern("/users/:name")
        let result = pattern.match("/users/日本語")

        #expect(result != nil)
        #expect(result?["name"] == "日本語")
    }

    @Test("match emoji in parameters")
    func matchEmojiParameters() {
        let pattern = PathPattern("/users/:name")
        let result = pattern.match("/users/😀")

        #expect(result != nil)
        #expect(result?["name"] == "😀")
    }

    @Test("match with multiple query params")
    func matchMultipleQueryParams() {
        let pattern = PathPattern("/users/:id")
        let result = pattern.match("/users/123?foo=bar&baz=qux&test=1")

        #expect(result != nil)
        #expect(result?["id"] == "123")
    }

    @Test("match with empty query string")
    func matchEmptyQueryString() {
        let pattern = PathPattern("/users")
        let result = pattern.match("/users?")

        #expect(result != nil)
    }

    @Test("match parameter with dots")
    func matchParameterWithDots() {
        let pattern = PathPattern("/files/:name")
        let result = pattern.match("/files/file.txt")

        #expect(result != nil)
        #expect(result?["name"] == "file.txt")
    }

    @Test("match parameter with hyphens")
    func matchParameterWithHyphens() {
        let pattern = PathPattern("/users/:slug")
        let result = pattern.match("/users/john-doe")

        #expect(result != nil)
        #expect(result?["slug"] == "john-doe")
    }

    @Test("match parameter with underscores")
    func matchParameterWithUnderscores() {
        let pattern = PathPattern("/users/:slug")
        let result = pattern.match("/users/john_doe")

        #expect(result != nil)
        #expect(result?["slug"] == "john_doe")
    }

    // MARK: - Complex Pattern Combinations

    @Test("match deeply nested wildcard")
    func matchDeeplyNestedWildcard() {
        let pattern = PathPattern("/a/b/c/d/*")
        let result = pattern.match("/a/b/c/d/1/2/3/4/5")

        #expect(result != nil)
    }

    @Test("match pattern with only wildcard")
    func matchOnlyWildcard() {
        let pattern = PathPattern("*")
        let result = pattern.match("/anything/here/works")

        #expect(result != nil)
    }

    @Test("wildcard consumes all remaining segments")
    func wildcardConsumesAll() {
        // Wildcard at position 0 returns immediately — any literal after it is not enforced
        let pattern = PathPattern("*/files")
        let result = pattern.match("/path/to/files")

        // Wildcard matches everything, returns empty params dict (not nil)
        #expect(result == [:])
    }
}
