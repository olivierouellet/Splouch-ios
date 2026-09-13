import Foundation

/// One WebSocket message, both directions: `{ "event": <name>, "data": <any> }`
/// (api.md §1). `data` is absent or null on events such as `ping`, `pong` and
/// `schedule_update`.
public struct Frame: Sendable, Equatable {
    public var event: String
    public var data: JSONValue

    public init(event: String, data: JSONValue = .null) {
        self.event = event
        self.data = data
    }

    /// The heartbeat probe, exactly as the reference client sends it.
    public static let ping = Frame(event: "ping")

    /// The cloud join handshake (api.md §3). `vid` is optional on the wire: omit it
    /// when the store has none rather than sending an empty string.
    public static func joinMeet(meetID: String, vid: String?) -> Frame {
        var data: [String: JSONValue] = ["meet_id": .string(meetID)]
        if let vid { data["vid"] = .string(vid) }
        return Frame(event: "join_meet", data: .object(data))
    }

    public static func decode(_ text: String) throws -> Frame {
        try JSONDecoder().decode(Frame.self, from: Data(text.utf8))
    }

    public func encoded() throws -> String {
        let data = try JSONEncoder().encode(self)
        return String(decoding: data, as: UTF8.self)
    }
}

extension Frame: Codable {
    private enum CodingKeys: String, CodingKey { case event, data }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        event = try c.decode(String.self, forKey: .event)
        data = try c.decodeIfPresent(JSONValue.self, forKey: .data) ?? .null
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(event, forKey: .event)
        if !data.isNull { try c.encode(data, forKey: .data) }
    }
}
