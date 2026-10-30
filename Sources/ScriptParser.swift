import Foundation

struct Token {
    let word: String
    let highlight: Bool
}

struct Sentence {
    var spoken: String
    var tokens: [Token]
    var pose: String?
    var emotion: String?
    var idea: Bool
    var imageQuery: String?
    var noImage: Bool
    var chapter: String?
    var start: Double = 0
    var end: Double = 0
}

/// Turns a pasted script into sentences. Supports:
///  - "# Title" lines (chapter banners), "**VO:** text" lines, *word* highlights
///  - [explain] [open] [point] [think] [celebrate] [thumbs] [wave] [present] [rest]
///  - [happy] [excited] [surprised] [angry] [tired] [focused] [sad] [wink] [normal]
///  - [idea], [image: search words], [noimage]
enum ScriptParser {
    static let poseTags: Set<String> = ["rest", "explain", "open", "point", "think", "celebrate", "thumbs", "wave", "present"]
    static let emotionTags: Set<String> = ["normal", "happy", "excited", "surprised", "angry", "tired", "focused", "sad", "wink"]
    static let ideaWords = ["idea", "discover", "clue", "realize", "realise", "secret", "twist"]
    static let autoPoses = ["explain", "open", "point", "explain", "rest", "open", "present", "explain"]
    static let skipPrefixes = ["**visual", "**note", "**editor", "**scene", "visual:", "note for", "editor note", "---", "___", "***"]
    static let weakEnd: Set<String> = ["a", "an", "the", "of", "to", "in", "on", "at", "for", "with", "and", "or", "but", "that", "is",
                                       "was", "so", "it", "its", "by", "from", "as", "than", "into", "their", "your", "our", "his",
                                       "her", "my", "this", "they"]

    private static let tagRE = try! NSRegularExpression(pattern: "\\[([A-Za-z ]{2,14})\\]")
    private static let imageRE = try! NSRegularExpression(pattern: "\\[image:\\s*([^\\]]{2,80})\\]", options: [.caseInsensitive])
    private static let voRE = try! NSRegularExpression(pattern: "^\\**\\s*(vo|narrator|voice[- ]?over|voiceover)\\s*:\\**\\s*(.*)$", options: [.caseInsensitive])

    private static func matches(_ re: NSRegularExpression, _ s: String) -> [NSTextCheckingResult] {
        return re.matches(in: s, range: NSRange(location: 0, length: (s as NSString).length))
    }

    private static func group(_ m: NSTextCheckingResult, _ i: Int, in s: String) -> String {
        let r = m.range(at: i)
        if r.location == NSNotFound { return "" }
        return (s as NSString).substring(with: r)
    }

    private static func removing(_ re: NSRegularExpression, from s: String) -> String {
        return re.stringByReplacingMatches(in: s, range: NSRange(location: 0, length: (s as NSString).length), withTemplate: "")
    }

    static func splitSentences(_ line: String) -> [String] {
        let chars = Array(line)
        var out: [String] = []
        var cur = ""
        var i = 0
        let enders: Set<Character> = [".", "!", "?", "\u{2026}"]
        let closers: Set<Character> = ["\"", "'", ")", "]"]
        while i < chars.count {
            cur.append(chars[i])
            if enders.contains(chars[i]) {
                var j = i + 1
                while j < chars.count && closers.contains(chars[j]) {
                    cur.append(chars[j])
                    j += 1
                }
                if j >= chars.count || chars[j].isWhitespace {
                    let t = cur.trimmingCharacters(in: .whitespaces)
                    if !t.isEmpty { out.append(t) }
                    cur = ""
                    while j < chars.count && chars[j].isWhitespace { j += 1 }
                }
                i = j
                continue
            }
            i += 1
        }
        let t = cur.trimmingCharacters(in: .whitespaces)
        if !t.isEmpty { out.append(t) }
        return out
    }

    static func tokens(from text: String) -> [Token] {
        var out: [Token] = []
        var hl = false
        for piece in text.split(whereSeparator: { $0.isWhitespace }) {
            let raw = String(piece)
            if raw.hasPrefix("*") { hl = true }
            let end = raw.dropFirst().contains("*")
            let tok = raw.replacingOccurrences(of: "*", with: "")
            if !tok.isEmpty {
                let bare = tok.filter { $0.isLetter || $0.isNumber }
                let hasDigit = bare.contains(where: { $0.isNumber })
                let allCaps = bare.count >= 3 && bare == bare.uppercased() && bare.contains(where: { $0.isLetter })
                out.append(Token(word: tok, highlight: hl || hasDigit || allCaps))
            }
            if end { hl = false }
        }
        return out
    }

    static func parse(_ text: String) -> [Sentence] {
        var lines: [(String, String?)] = []
        var chapter: String? = nil
        let normalized = text.replacingOccurrences(of: "\r", with: "")
        for raw in normalized.components(separatedBy: "\n") {
            var line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }
            let low = line.lowercased()
            if line.hasPrefix("#") {
                var t = String(line.drop(while: { $0 == "#" })).trimmingCharacters(in: .whitespaces)
                t = t.replacingOccurrences(of: "\\(.*?\\)", with: "", options: .regularExpression)
                t = t.trimmingCharacters(in: CharacterSet(charactersIn: " -:"))
                chapter = t
                continue
            }
            if skipPrefixes.contains(where: { low.hasPrefix($0) }) { continue }
            if let m = matches(voRE, line).first { line = group(m, 2, in: line) }
            line = line.replacingOccurrences(of: "**", with: "")
            line = line.replacingOccurrences(of: "^\\s*[-+>]\\s+", with: "", options: .regularExpression)
            line = line.trimmingCharacters(in: CharacterSet(charactersIn: " \"\u{201C}\u{201D}"))
            if !line.isEmpty {
                lines.append((line, chapter))
                chapter = nil
            }
        }

        var sentences: [Sentence] = []
        for (line, chap) in lines {
            let parts = splitSentences(line)
            for (n, p) in parts.enumerated() {
                var part = p
                var imageQuery: String? = nil
                if let m = matches(imageRE, part).first {
                    imageQuery = group(m, 1, in: part).trimmingCharacters(in: .whitespaces)
                }
                part = removing(imageRE, from: part)
                let found = matches(tagRE, part)
                var tags: [String] = []
                for m in found {
                    tags.append(group(m, 1, in: part).lowercased().trimmingCharacters(in: .whitespaces))
                }
                part = removing(tagRE, from: part).trimmingCharacters(in: .whitespaces)
                let pose = tags.first(where: { poseTags.contains($0) })
                let emotion = tags.first(where: { emotionTags.contains($0) })
                let noImg = tags.contains("noimage") || tags.contains("no image")
                let hasLetters = part.rangeOfCharacter(from: .alphanumerics) != nil
                if !hasLetters {
                    // tags standing alone after a full stop belong to the sentence before them
                    if var last = sentences.popLast() {
                        if last.imageQuery == nil { last.imageQuery = imageQuery }
                        if noImg { last.noImage = true }
                        if last.pose == nil { last.pose = pose }
                        if last.emotion == nil { last.emotion = emotion }
                        if tags.contains("idea") { last.idea = true }
                        sentences.append(last)
                    }
                    continue
                }
                let spoken = part.replacingOccurrences(of: "*", with: "")
                let lower = spoken.lowercased()
                var idea = tags.contains("idea")
                if !idea {
                    for w in ideaWords where lower.contains(w) { idea = true }
                }
                sentences.append(Sentence(spoken: spoken, tokens: tokens(from: part), pose: pose, emotion: emotion, idea: idea,
                                          imageQuery: imageQuery, noImage: noImg, chapter: n == 0 ? chap : nil))
            }
        }

        let count = sentences.count
        for i in 0..<count {
            let trimmed = sentences[i].spoken.trimmingCharacters(in: CharacterSet(charactersIn: "\"') "))
            let isQuestion = trimmed.hasSuffix("?")
            let isExclaim = trimmed.hasSuffix("!")
            if sentences[i].pose == nil {
                if isQuestion {
                    sentences[i].pose = "think"
                } else if i == 0 {
                    sentences[i].pose = "point"
                } else if i == count - 1 && count > 2 {
                    sentences[i].pose = "thumbs"
                } else if isExclaim {
                    sentences[i].pose = "celebrate"
                } else {
                    sentences[i].pose = autoPoses[i % autoPoses.count]
                }
            }
            if sentences[i].emotion == nil {
                if sentences[i].pose == "think" || isQuestion {
                    sentences[i].emotion = "think"
                } else if isExclaim {
                    sentences[i].emotion = "excited"
                } else if (i == count - 1 && count > 2) || sentences[i].pose == "thumbs" {
                    sentences[i].emotion = "happy"
                } else {
                    sentences[i].emotion = "normal"
                }
            }
        }
        return sentences
    }

    static func spokenText(_ sentences: [Sentence]) -> String {
        return sentences.map { $0.spoken }.joined(separator: " ")
    }

    /// Splits a sentence's words into caption-sized chunks, preferring commas and never ending on a weak word.
    static func splitCaptionChunks(_ tokens: [Token], maxWords: Int) -> [[Token]] {
        if tokens.count <= maxWords { return [tokens] }
        var chunks: [[Token]] = []
        var cur: [Token] = []
        for tok in tokens {
            cur.append(tok)
            let last = tok.word.last
            let endsClause = last == "," || last == ";" || last == ":"
            if cur.count >= maxWords || (cur.count >= 3 && endsClause) {
                var carry: [Token] = []
                while cur.count > 2 {
                    let w = cur[cur.count - 1].word
                    let bare = w.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ",;:"))
                    let hasPunct = w.last == "," || w.last == ";" || w.last == ":"
                    if weakEnd.contains(bare) && !hasPunct {
                        carry.insert(cur.removeLast(), at: 0)
                    } else {
                        break
                    }
                }
                chunks.append(cur)
                cur = carry
            }
        }
        if !cur.isEmpty {
            if cur.count <= 2 && !chunks.isEmpty {
                chunks[chunks.count - 1].append(contentsOf: cur)
            } else {
                chunks.append(cur)
            }
        }
        return chunks
    }
}
