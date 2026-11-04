import Foundation
import Yams

/// Splits and joins `---` YAML frontmatter and edits it at the node level, so keys
/// this app doesn't know about (added by a user or an agent) survive every write.
public enum Frontmatter {
    /// A note's text. A file that isn't valid UTF-8 (saved as Latin-1 by some editor)
    /// still loads, with the bad bytes replaced, instead of vanishing from every list.
    public static func read(_ url: URL) throws -> String {
        let data = try Data(contentsOf: url)
        return String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self)
    }

    public static func split(_ text: String) -> (yaml: String?, body: String) {
        let normalized = text.utf8.contains(13) ? text.replacingOccurrences(of: "\r\n", with: "\n") : text
        // Scans bytes up to the closing fence only: Character-level string walking is slow
        // and the body can be long.
        let bytes = normalized.utf8
        guard bytes.starts(with: "---\n".utf8) else { return (nil, normalized) }
        let start = bytes.index(bytes.startIndex, offsetBy: 4)
        var lineStart = start
        while lineStart < bytes.endIndex {
            let lineEnd = bytes[lineStart...].firstIndex(of: UInt8(ascii: "\n")) ?? bytes.endIndex
            let line = bytes[lineStart..<lineEnd]
            if line.elementsEqual("---".utf8) || line.elementsEqual("...".utf8) {
                let yaml = lineStart > start ? String(normalized[start..<bytes.index(before: lineStart)]) : ""
                var body = lineEnd < bytes.endIndex ? String(normalized[bytes.index(after: lineEnd)...]) : ""
                if body.hasPrefix("\n") { body.removeFirst() }
                return (yaml, body)
            }
            guard lineEnd < bytes.endIndex else { break }
            lineStart = bytes.index(after: lineEnd)
        }
        return (nil, normalized)
    }

    public static func join(node: Node, body: String) throws -> String {
        let yaml = try serialize(node: normalizeStyles(canonicalOrder(node)), width: -1, allowUnicode: true)
        let trimmedBody = body.hasSuffix("\n") ? body : body + "\n"
        return "---\n\(yaml)---\n\n\(trimmedBody)"
    }

    public static func parse(_ yaml: String?) throws -> Node {
        guard let yaml, !yaml.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return emptyMapping }
        guard let node = try compose(yaml: yaml), node.mapping != nil else {
            throw CotsError.invalidFrontmatter("el frontmatter debe ser un mapa YAML")
        }
        // Aliases let a few lines expand into millions of nodes on every write ("billion
        // laughs"). Parsing shares them, so counting with a cap stays cheap.
        var budget = maxNodes
        guard fits(node, budget: &budget) else {
            throw CotsError.invalidFrontmatter("el frontmatter es demasiado grande (¿alias YAML anidados?)")
        }
        return node
    }

    static let maxNodes = 20_000

    private static func fits(_ node: Node, budget: inout Int) -> Bool {
        budget -= 1
        guard budget >= 0 else { return false }
        switch node {
        case .scalar, .alias: return true
        case .sequence(let seq): return seq.allSatisfy { fits($0, budget: &budget) }
        case .mapping(let map): return map.allSatisfy { fits($0.key, budget: &budget) && fits($0.value, budget: &budget) }
        }
    }

    public static func decodeMeta(_ node: Node) throws -> NoteMeta {
        try YAMLDecoder().decode(NoteMeta.self, from: node)
    }

    public static var emptyMapping: Node { .mapping(Node.Mapping([])) }

    /// Readable block YAML for any Encodable value (unicode unescaped).
    public static func yaml<T: Encodable>(_ value: T) throws -> String {
        try serialize(node: normalizeStyles(node(from: value)), width: -1, allowUnicode: true)
    }

    /// Converts any Encodable value into a YAML node.
    public static func node<T: Encodable>(from value: T) throws -> Node {
        let yaml = try YAMLEncoder().encode(value)
        return try compose(yaml: yaml) ?? emptyMapping
    }

    /// Sets `value` at a dotted key path (`display.pinned`), creating intermediate
    /// mappings as needed. A nil value removes the key.
    public static func set(_ value: Node?, at path: [String], in node: inout Node) {
        guard let key = path.first, var mapping = node.mapping else { return }
        if path.count == 1 {
            mapping[key] = value
        } else {
            var child = mapping[key] ?? emptyMapping
            if child.mapping == nil { child = emptyMapping }
            set(value, at: Array(path.dropFirst()), in: &child)
            mapping[key] = child
        }
        node = .mapping(mapping)
    }

    /// Fills keys that are missing in `node` from `defaults`, recursing into mappings.
    public static func merge(defaults: Node, into node: inout Node) {
        guard let defaultsMapping = defaults.mapping, var mapping = node.mapping else { return }
        for (key, value) in defaultsMapping {
            if let existing = mapping[key] {
                if existing.mapping != nil, value.mapping != nil {
                    var merged = existing
                    merge(defaults: value, into: &merged)
                    mapping[key] = merged
                }
            } else {
                mapping[key] = value
            }
        }
        node = .mapping(mapping)
    }

    /// Input often arrives as JSON (flow style, quoted). Write it back as readable
    /// block YAML, with multi-line strings as `|` literals.
    static func normalizeStyles(_ node: Node) -> Node {
        switch node {
        case .scalar(var scalar):
            scalar.style = scalar.string.contains("\n") ? .literal : .any
            return .scalar(scalar)
        case .sequence(let sequence):
            return .sequence(Node.Sequence(sequence.map(normalizeStyles), sequence.tag, .block))
        case .mapping(let mapping):
            return .mapping(Node.Mapping(mapping.map { (normalizeStyles($0.key), normalizeStyles($0.value)) }, mapping.tag, .block))
        case .alias:
            return node
        }
    }

    static func canonicalOrder(_ node: Node) -> Node {
        guard let mapping = node.mapping else { return node }
        let pairs = Array(mapping)
        func rank(_ key: Node) -> Int { NoteMeta.keyOrder.firstIndex(of: key.string ?? "") ?? Int.max }
        let sorted = pairs.enumerated().sorted { a, b in
            let ra = rank(a.element.key), rb = rank(b.element.key)
            return ra != rb ? ra < rb : a.offset < b.offset
        }.map { ($0.element.key, $0.element.value) }
        return .mapping(Node.Mapping(sorted, mapping.tag, mapping.style))
    }
}
