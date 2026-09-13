import Foundation

/// Event names in the reader's language (app.md T-11).
///
/// The server decomposes the name into keys and ships them as
/// `event_name_parts`; the client joins them against the `event_name` section
/// of `GET /i18n/{lang}`. It never parses the name itself. Mirrors
/// `composeEventName` in the reference `ws.js` exactly.
public enum EventName {
    /// `dist + unit`, stroke, relay — then `separator`, then gender and age.
    /// Empty when there are no parts or no vocabulary; the raw name when the
    /// parts compose to nothing.
    public static func compose(_ parts: EventNameParts?, vocab: [String: String]?) -> String {
        guard let parts, let vocab else { return "" }
        func word(_ k: String) -> String { k.isEmpty ? "" : (vocab[k] ?? k) }
        var left: [String] = []
        if !parts.dist.isEmpty { left.append(parts.dist + " " + (vocab["unit"] ?? "m")) }
        if !parts.stroke.isEmpty { left.append(word(parts.stroke)) }
        if parts.relay, let relay = vocab["relay"], !relay.isEmpty { left.append(relay) }
        let age = parts.age.isEmpty ? word(parts.ageKey) : parts.age
        let right = [word(parts.gender), age].filter { !$0.isEmpty }.joined(separator: " ")
        let l = left.joined(separator: " ")
        if !l.isEmpty, !right.isEmpty { return l + (vocab["separator"] ?? "  \u{2014}  ") + right }
        if !l.isEmpty { return l }
        if !right.isEmpty { return right }
        return parts.raw
    }

    /// The name to show: composed when the parts and vocabulary allow it,
    /// otherwise `eventName` as the server sent it, already right for anyone
    /// who has not chosen a language.
    public static func resolve(eventName: String, parts: EventNameParts?, vocab: [String: String]?) -> String {
        let composed = compose(parts, vocab: vocab)
        return composed.isEmpty ? eventName : composed
    }
}
