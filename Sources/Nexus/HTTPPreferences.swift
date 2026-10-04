import Foundation

/// Shared parsing for Accept and Accept-Encoding. Quoted delimiters are not separators.
struct HTTPPreference {
    let value: String
    let parameters: [String: String]
    let quality: Double
    let position: Int

    static func parse(_ header: String) -> [HTTPPreference] {
        split(header, on: ",").enumerated().compactMap { position, item in
            let parts = split(item, on: ";")
            guard let first = parts.first, !first.isEmpty else { return nil }
            var parameters: [String: String] = [:]
            var quality = 1.0
            var foundQuality = false
            for part in parts.dropFirst() {
                let pair = part.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
                let name = pair[0].trimmingCharacters(in: .whitespaces).lowercased()
                let value = pair.count == 2 ? pair[1].trimmingCharacters(in: .whitespaces) : ""
                if name == "q" {
                    if foundQuality {
                        quality = 0
                        continue
                    }
                    foundQuality = true
                    let number = Double(value) ?? -1
                    quality = number.isFinite && (0...1).contains(number) ? number : 0
                } else if !foundQuality, pair.count == 2 {
                    let unquoted =
                        value.hasPrefix("\"") && value.hasSuffix("\"")
                        ? String(value.dropFirst().dropLast()) : value
                    parameters[name] = name == "charset" ? unquoted.lowercased() : unquoted
                }
            }
            return HTTPPreference(
                value: first.lowercased(), parameters: parameters, quality: quality, position: position)
        }
    }

    static func split(_ value: String, on separator: Character) -> [String] {
        var result: [String] = []
        var current = ""
        var quoted = false
        var escaped = false
        for character in value {
            if escaped {
                escaped = false
            } else if quoted && character == "\\" {
                escaped = true
            } else if character == "\"" {
                quoted.toggle()
            } else if character == separator && !quoted {
                result.append(current.trimmingCharacters(in: .whitespaces))
                current = ""
                continue
            }
            current.append(character)
        }
        result.append(current.trimmingCharacters(in: .whitespaces))
        return result
    }
}

/// Chooses a representation by its most specific matching media range before comparing quality.
struct MediaPreferences {
    let ranges: [HTTPPreference]

    init(_ header: String) { ranges = HTTPPreference.parse(header) }

    func preference(for type: String) -> (quality: Double, specificity: Int, parameters: Int, position: Int)? {
        guard let candidate = HTTPPreference.parse(type).first else { return nil }
        let parts = candidate.value.split(separator: "/")
        guard parts.count == 2 else { return nil }
        var best: (quality: Double, specificity: Int, parameters: Int, position: Int)?
        for range in ranges {
            let specificity: Int
            if range.value == candidate.value {
                specificity = 2
            } else if range.value == "\(parts[0])/*" {
                specificity = 1
            } else if range.value == "*/*" {
                specificity = 0
            } else {
                continue
            }
            guard range.parameters.allSatisfy({ candidate.parameters[$0.key] == $0.value }) else { continue }
            if let current = best,
                current.specificity > specificity
                    || (current.specificity == specificity && current.parameters >= range.parameters.count)
            {
                continue
            }
            best = (range.quality, specificity, range.parameters.count, range.position)
        }
        return best
    }

    func bestMatch(in supported: [String]) -> String? {
        var chosen: String?
        var rank: (Double, Int, Int, Int)?
        for type in supported {
            guard let match = preference(for: type), match.quality > 0 else { continue }
            let candidateRank = (match.quality, match.specificity, match.parameters, -match.position)
            if let rank, candidateRank <= rank { continue }
            chosen = type
            rank = candidateRank
        }
        return chosen
    }
}
