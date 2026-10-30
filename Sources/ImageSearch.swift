import UIKit

/// Royalty-free picture search. Only licences that allow commercial use and edits are accepted:
/// CC0 / public domain (no credit needed) and CC BY (credit required). Never CC BY-SA, NC or ND.
struct Candidate {
    let id: String
    let provider: String
    let title: String
    let creator: String
    let license: String
    let attribution: Bool
    let sourceURL: String
    let url: String
}

struct PictureScene {
    var idx: [Int]
    var text: String
    var query: String
    var skip: Bool
}

enum Net {
    static func request(_ s: String) throws -> URLRequest {
        guard let u = URL(string: s), u.scheme == "https" else {
            throw StudioError.message("Only https links are allowed.")
        }
        var r = URLRequest(url: u, timeoutInterval: 25)
        r.setValue("TalkingStudio/1.0 (iOS video tool for creators)", forHTTPHeaderField: "User-Agent")
        return r
    }

    static func json(_ s: String) async throws -> [String: Any] {
        let (data, resp) = try await URLSession.shared.data(for: try request(s))
        guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else {
            throw StudioError.message("The picture service did not answer.")
        }
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw StudioError.message("Unexpected answer from the picture service.")
        }
        return obj
    }

    static func url(_ base: String, _ items: [(String, String)]) -> String {
        guard var comps = URLComponents(string: base) else { return base }
        comps.queryItems = items.map { URLQueryItem(name: $0.0, value: $0.1) }
        return comps.url?.absoluteString ?? base
    }

    static func strip(_ s: String) -> String {
        var out = s.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        out = out.replacingOccurrences(of: "&amp;", with: "&").replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'").replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
        out = out.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        return out.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum ImageSearch {
    // MARK: sources

    static func wikimedia(_ q: String, n: Int, strict: Bool) async throws -> [Candidate] {
        let u = Net.url("https://commons.wikimedia.org/w/api.php", [
            ("action", "query"), ("generator", "search"), ("gsrsearch", q + " filetype:bitmap"), ("gsrnamespace", "6"),
            ("gsrlimit", String(min(n * 3, 30))), ("prop", "imageinfo"), ("iiprop", "url|extmetadata|size|mime"),
            ("iiurlwidth", "1600"), ("iiextmetadatafilter", "LicenseShortName|Artist|Restrictions|LicenseUrl"), ("format", "json"),
        ])
        let obj = try await Net.json(u)
        guard let query = obj["query"] as? [String: Any], let pages = query["pages"] as? [String: Any] else { return [] }
        var list: [[String: Any]] = []
        for (_, v) in pages {
            if let d = v as? [String: Any] { list.append(d) }
        }
        list.sort { (($0["index"] as? Int) ?? 0) < (($1["index"] as? Int) ?? 0) }
        var out: [Candidate] = []
        for p in list {
            guard let infos = p["imageinfo"] as? [[String: Any]], let ii = infos.first else { continue }
            let mime = (ii["mime"] as? String) ?? ""
            if !["image/jpeg", "image/png", "image/webp"].contains(mime) { continue }
            let em = (ii["extmetadata"] as? [String: Any]) ?? [:]
            func val(_ key: String) -> String {
                if let d = em[key] as? [String: Any], let v = d["value"] as? String { return Net.strip(v) }
                return ""
            }
            if !val("Restrictions").isEmpty { continue }
            let lic = val("LicenseShortName")
            var attribution = false
            if lic.range(of: "^(CC0|Public domain|PD[- ])", options: [.regularExpression, .caseInsensitive]) != nil {
                attribution = false
            } else if lic.range(of: "^CC BY \\d", options: .regularExpression) != nil {
                attribution = true
            } else {
                continue
            }
            if strict && attribution { continue }
            let width = (ii["width"] as? Int) ?? 0
            if width < 900 { continue }
            let thumb = (ii["thumburl"] as? String) ?? (ii["url"] as? String) ?? ""
            if thumb.isEmpty { continue }
            let pageID = String(describing: p["pageid"] ?? "")
            var title = (p["title"] as? String) ?? "Untitled"
            title = title.replacingOccurrences(of: "File:", with: "")
            if let dot = title.lastIndex(of: ".") { title = String(title[title.startIndex..<dot]) }
            out.append(Candidate(id: "wikimedia:" + pageID, provider: "Wikimedia Commons", title: title, creator: val("Artist"),
                                 license: lic, attribution: attribution, sourceURL: (ii["descriptionurl"] as? String) ?? "", url: thumb))
        }
        return out
    }

    static func nasa(_ q: String, n: Int) async throws -> [Candidate] {
        let u = Net.url("https://images-api.nasa.gov/search", [("q", q), ("media_type", "image"), ("page_size", String(min(max(n * 2, 6), 20)))])
        let obj = try await Net.json(u)
        guard let coll = obj["collection"] as? [String: Any], let items = coll["items"] as? [[String: Any]] else { return [] }
        var out: [Candidate] = []
        for it in items {
            guard let data = (it["data"] as? [[String: Any]])?.first, let nid = data["nasa_id"] as? String else { continue }
            let title = (data["title"] as? String) ?? "NASA image"
            let creator = (data["photographer"] as? String) ?? (data["center"] as? String) ?? "NASA"
            out.append(Candidate(id: "nasa:" + nid, provider: "NASA", title: title, creator: creator, license: "NASA (public domain)",
                                 attribution: false, sourceURL: "https://images.nasa.gov/details/" + nid, url: "nasa-asset:" + nid))
        }
        return out
    }

    static func cleveland(_ q: String, n: Int) async throws -> [Candidate] {
        let u = Net.url("https://openaccess-api.clevelandart.org/api/artworks/", [
            ("q", q), ("has_image", "1"), ("cc0", "1"), ("limit", String(min(max(n * 2, 6), 20))),
            ("fields", "id,title,creators,images,url,share_license_status"),
        ])
        let obj = try await Net.json(u)
        guard let data = obj["data"] as? [[String: Any]] else { return [] }
        var out: [Candidate] = []
        for a in data {
            guard let images = a["images"] as? [String: Any], let web = images["web"] as? [String: Any],
                  let link = web["url"] as? String, (a["share_license_status"] as? String) == "CC0" else { continue }
            let id = String(describing: a["id"] ?? "")
            let creators = a["creators"] as? [[String: Any]]
            let desc = (creators?.first?["description"] as? String) ?? "Cleveland Museum of Art"
            let creator = (desc.components(separatedBy: "(").first ?? desc).trimmingCharacters(in: .whitespaces)
            out.append(Candidate(id: "cleveland:" + id, provider: "Cleveland Museum of Art", title: (a["title"] as? String) ?? "Artwork",
                                 creator: creator, license: "CC0 (Cleveland Museum of Art)", attribution: false,
                                 sourceURL: (a["url"] as? String) ?? "", url: link))
        }
        return out
    }

    // MARK: search

    static func once(query: String, strict: Bool, limit: Int) async -> [Candidate] {
        let results: [[Candidate]] = await withTaskGroup(of: (Int, [Candidate]).self, returning: [[Candidate]].self) { group in
            group.addTask { (0, (try? await ImageSearch.wikimedia(query, n: 3, strict: strict)) ?? []) }
            group.addTask { (1, (try? await ImageSearch.nasa(query, n: 3)) ?? []) }
            group.addTask { (2, (try? await ImageSearch.cleveland(query, n: 3)) ?? []) }
            var arr: [[Candidate]] = [[], [], []]
            for await (i, list) in group { arr[i] = list }
            return arr
        }
        var merged: [Candidate] = []
        var idx = 0
        while merged.count < limit && results.contains(where: { idx < $0.count }) {
            for r in results where idx < r.count && merged.count < limit {
                merged.append(r[idx])
            }
            idx += 1
        }
        return merged
    }

    /// Searches all sources; if too few pictures turn up it retries with shorter word combinations.
    static func search(query: String, strict: Bool, limit: Int = 6) async -> [Candidate] {
        var merged = await once(query: query, strict: strict, limit: limit)
        let words = query.split(separator: " ").map { String($0) }
        if merged.count < 4 && words.count >= 2 {
            var tries: [String] = [words.prefix(2).joined(separator: " "), words.suffix(2).joined(separator: " ")]
            tries += Array(Set(words)).sorted { $0.count > $1.count }
            var tried: Set<String> = [query.lowercased()]
            var seen = Set(merged.map { $0.id })
            for t in tries {
                if merged.count >= limit { break }
                if tried.contains(t.lowercased()) { continue }
                tried.insert(t.lowercased())
                let more = await once(query: t, strict: strict, limit: limit)
                for c in more where !seen.contains(c.id) && merged.count < limit {
                    seen.insert(c.id)
                    merged.append(c)
                }
                if merged.count >= 4 { break }
            }
        }
        return merged
    }

    // MARK: download

    static func fetchImage(_ c: Candidate) async throws -> UIImage {
        var link = c.url
        if link.hasPrefix("nasa-asset:") {
            let nid = String(link.dropFirst("nasa-asset:".count))
            let encoded = nid.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? nid
            let obj = try await Net.json("https://images-api.nasa.gov/asset/" + encoded)
            let items = ((obj["collection"] as? [String: Any])?["items"] as? [[String: Any]]) ?? []
            let hrefs = items.compactMap { $0["href"] as? String }
            var chosen: String? = nil
            for tag in ["~large.jpg", "~medium.jpg", "~orig.jpg", "~small.jpg"] where chosen == nil {
                chosen = hrefs.first(where: { $0.hasSuffix(tag) })
            }
            guard let h = chosen else { throw StudioError.message("No usable NASA image size.") }
            link = h.replacingOccurrences(of: "http://", with: "https://")
        }
        let (data, resp) = try await URLSession.shared.data(for: try Net.request(link))
        guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else {
            throw StudioError.message("The picture could not be downloaded.")
        }
        let mime = http.mimeType ?? ""
        if !mime.hasPrefix("image/") || mime.contains("svg") { throw StudioError.message("The link is not a normal picture.") }
        if data.count > 25_000_000 { throw StudioError.message("The picture is too large.") }
        guard let img = UIImage(data: data), img.size.width >= 640 else {
            throw StudioError.message("The picture is too small.")
        }
        return downscale(img, maxSide: 1800)
    }

    static func downscale(_ img: UIImage, maxSide: CGFloat) -> UIImage {
        let longest = max(img.size.width, img.size.height)
        if longest <= maxSide { return img }
        let scale = maxSide / longest
        let size = CGSize(width: img.size.width * scale, height: img.size.height * scale)
        let fmt = UIGraphicsImageRendererFormat()
        fmt.scale = 1
        return UIGraphicsImageRenderer(size: size, format: fmt).image { _ in
            img.draw(in: CGRect(origin: .zero, size: size))
        }
    }

    static func creditLine(_ c: Candidate) -> String {
        var s = "\"" + c.title + "\""
        if !c.creator.isEmpty { s += " by " + c.creator }
        s += ", " + c.license + " via " + c.provider
        if !c.sourceURL.isEmpty { s += " - " + c.sourceURL }
        if c.attribution { s += " [credit required]" }
        return s
    }

    // MARK: query words from the script

    static let stopText = """
    about above after again against all also always among and another any are around because been before being below between both
    but can come could did does doing down during each even every everyone everything few for from further get gets getting going had has
    have having here how into its just keep know like made make many mostly much must need never next not now off once only other our out
    over own people really said same says see she should since some something still such take than that the their them then there these
    they thing things this those through today too took under until upon very want was way well were what when where which while who why
    will with within without would yes yet you your first real january february march april june july august september october november
    december monday tuesday wednesday thursday friday saturday sunday one two three four five six seven eight nine ten twenty thirty forty
    fifty hundred thousand fourth fifth sixth seventh eighth ninth tenth day days year years time times staged stayed needed loved
    """

    static let stop: Set<String> = Set(stopText.split(whereSeparator: { $0 == " " || $0 == "\n" }).map { String($0) })

    static func keywords(_ text: String, n: Int = 3) -> String {
        var words: [String] = []
        var cur = ""
        for ch in text {
            if ch.isLetter || ch == "'" || ch == "-" {
                cur.append(ch)
            } else {
                if !cur.isEmpty { words.append(cur); cur = "" }
            }
        }
        if !cur.isEmpty { words.append(cur) }
        var scored: [(Int, Int, String)] = []
        for (i, w) in words.enumerated() {
            let lw = w.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "'-"))
            if lw.count < 4 || stop.contains(lw) { continue }
            if lw.split(separator: "-").contains(where: { stop.contains(String($0)) }) { continue }
            let capital = (w.first?.isUppercase ?? false) && i > 0
            scored.append((lw.count + (capital ? 3 : 0), i, lw))
        }
        let top = scored.sorted { a, b in
            if a.0 != b.0 { return a.0 > b.0 }
            return a.1 < b.1
        }.prefix(n)
        var seen = Set<String>()
        var out: [String] = []
        for t in top.sorted(by: { $0.1 < $1.1 }) where !seen.contains(t.2) {
            seen.insert(t.2)
            out.append(t.2)
        }
        return out.joined(separator: " ")
    }

    /// Groups sentences into scenes that share one picture (about every 70 characters of narration).
    static func groupScenes(_ sentences: [Sentence], minChars: Int = 70) -> [PictureScene] {
        var groups: [[Int]] = []
        var cur: [Int] = []
        var size = 0
        for (i, s) in sentences.enumerated() {
            var startsNew = false
            if let last = cur.last {
                startsNew = s.chapter != nil || s.imageQuery != nil || size >= minChars || s.noImage != sentences[last].noImage
            }
            if startsNew {
                groups.append(cur)
                cur = []
                size = 0
            }
            cur.append(i)
            size += s.spoken.count
        }
        if !cur.isEmpty { groups.append(cur) }
        var out: [PictureScene] = []
        for idx in groups {
            let text = idx.map { sentences[$0].spoken }.joined(separator: " ")
            let explicit = idx.compactMap { sentences[$0].imageQuery }.first
            let skip = idx.allSatisfy { sentences[$0].noImage }
            out.append(PictureScene(idx: idx, text: text, query: explicit ?? keywords(text), skip: skip))
        }
        return out
    }
}
