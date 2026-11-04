import Foundation

/// Case-insensitive substring search. ASCII queries (the usual case) go to `strcasestr`,
/// many times faster than lowercasing every note or asking Foundation; non-ASCII bytes
/// in the text are compared as is, which is right for an ASCII query.
public struct TextMatcher: Sendable {
    private let query: String
    private let ascii: Bool

    public init(_ query: String) {
        ascii = query.utf8.allSatisfy { $0 < 128 }
        self.query = ascii ? query : query.lowercased()
    }

    public func matches(_ text: String) -> Bool {
        guard !query.isEmpty else { return true }
        guard ascii else { return text.lowercased().contains(query) }
        return text.withCString { hay in query.withCString { strcasestr(hay, $0) != nil } }
    }
}
