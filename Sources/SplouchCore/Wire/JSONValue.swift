import Foundation

/// A JSON value as it arrives on the wire.
///
/// `update_scoreboard` is a flat dictionary of mixed types and every message may
/// carry an object, a bare string, or nothing (api.md §1), so frames are decoded
/// into this before any typed reading. Unknown keys and events are kept, not
/// rejected — C-07 says they are ignored, never treated as errors.
public enum JSONValue: Sendable, Equatable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])
}

extension JSONValue: Codable {
    public init(from decoder: any Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() {
            self = .null
        } else if let b = try? c.decode(Bool.self) {
            self = .bool(b)
        } else if let n = try? c.decode(Double.self) {
            self = .number(n)
        } else if let s = try? c.decode(String.self) {
            self = .string(s)
        } else if let a = try? c.decode([JSONValue].self) {
            self = .array(a)
        } else if let o = try? c.decode([String: JSONValue].self) {
            self = .object(o)
        } else {
            throw DecodingError.dataCorruptedError(in: c, debugDescription: "not a JSON value")
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .null: try c.encodeNil()
        case .bool(let b): try c.encode(b)
        case .number(let n):
            if n == n.rounded(), abs(n) < 1e15 { try c.encode(Int64(n)) } else { try c.encode(n) }
        case .string(let s): try c.encode(s)
        case .array(let a): try c.encode(a)
        case .object(let o): try c.encode(o)
        }
    }
}

public extension JSONValue {
    var isNull: Bool { if case .null = self { return true } else { return false } }
    var bool: Bool? { if case .bool(let b) = self { return b } else { return nil } }
    var double: Double? { if case .number(let n) = self { return n } else { return nil } }
    var int: Int? {
        guard case .number(let n) = self, n == n.rounded(), abs(n) < Double(Int.max) else { return nil }
        return Int(n)
    }
    var string: String? { if case .string(let s) = self { return s } else { return nil } }
    var array: [JSONValue]? { if case .array(let a) = self { return a } else { return nil } }
    var object: [String: JSONValue]? { if case .object(let o) = self { return o } else { return nil } }

    subscript(key: String) -> JSONValue? { object?[key] }

    /// The value read as display text. Event and heat numbers are strings in
    /// `update_scoreboard` and `results_snapshot` but integers in `next_heats` and
    /// the schedule, and S-05 compares them, so both spellings land on one form.
    var text: String? {
        switch self {
        case .string(let s): return s
        case .number(let n): return n == n.rounded() && abs(n) < 1e15 ? String(Int64(n)) : String(n)
        case .bool(let b): return b ? "true" : "false"
        case .null, .array, .object: return nil
        }
    }
}
