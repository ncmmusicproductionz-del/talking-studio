import Foundation
import Security

// MARK: - Voice catalog

struct AIVoice: Identifiable, Hashable {
    let id: String
    let name: String
    let accent: String
    let flag: String
    let female: Bool
    let blurb: String
}

/// The same Microsoft neural voices used by the desktop studio, played through Microsoft's official Azure Speech service.
enum AIVoices {
    static let all: [AIVoice] = [
        AIVoice(id: "en-US-AndrewNeural", name: "Andrew", accent: "US", flag: "\u{1F1FA}\u{1F1F8}", female: false, blurb: "Warm and confident"),
        AIVoice(id: "en-US-BrianNeural", name: "Brian", accent: "US", flag: "\u{1F1FA}\u{1F1F8}", female: false, blurb: "Clear storyteller"),
        AIVoice(id: "en-US-ChristopherNeural", name: "Christopher", accent: "US", flag: "\u{1F1FA}\u{1F1F8}", female: false, blurb: "Calm and steady"),
        AIVoice(id: "en-US-GuyNeural", name: "Guy", accent: "US", flag: "\u{1F1FA}\u{1F1F8}", female: false, blurb: "Deep and rich"),
        AIVoice(id: "en-US-EricNeural", name: "Eric", accent: "US", flag: "\u{1F1FA}\u{1F1F8}", female: false, blurb: "Smooth"),
        AIVoice(id: "en-US-AvaNeural", name: "Ava", accent: "US", flag: "\u{1F1FA}\u{1F1F8}", female: true, blurb: "Bright and friendly"),
        AIVoice(id: "en-US-EmmaNeural", name: "Emma", accent: "US", flag: "\u{1F1FA}\u{1F1F8}", female: true, blurb: "Natural and warm"),
        AIVoice(id: "en-US-AriaNeural", name: "Aria", accent: "US", flag: "\u{1F1FA}\u{1F1F8}", female: true, blurb: "Confident"),
        AIVoice(id: "en-US-JennyNeural", name: "Jenny", accent: "US", flag: "\u{1F1FA}\u{1F1F8}", female: true, blurb: "Friendly"),
        AIVoice(id: "en-US-MichelleNeural", name: "Michelle", accent: "US", flag: "\u{1F1FA}\u{1F1F8}", female: true, blurb: "Pleasant"),
        AIVoice(id: "en-GB-RyanNeural", name: "Ryan", accent: "UK", flag: "\u{1F1EC}\u{1F1E7}", female: false, blurb: "British narrator"),
        AIVoice(id: "en-GB-ThomasNeural", name: "Thomas", accent: "UK", flag: "\u{1F1EC}\u{1F1E7}", female: false, blurb: "British, measured"),
        AIVoice(id: "en-GB-SoniaNeural", name: "Sonia", accent: "UK", flag: "\u{1F1EC}\u{1F1E7}", female: true, blurb: "British, polished"),
        AIVoice(id: "en-GB-LibbyNeural", name: "Libby", accent: "UK", flag: "\u{1F1EC}\u{1F1E7}", female: true, blurb: "British, lively"),
        AIVoice(id: "en-IE-ConnorNeural", name: "Connor", accent: "Irish", flag: "\u{1F1EE}\u{1F1EA}", female: false, blurb: "Irish storyteller"),
        AIVoice(id: "en-IE-EmilyNeural", name: "Emily", accent: "Irish", flag: "\u{1F1EE}\u{1F1EA}", female: true, blurb: "Irish, gentle"),
        AIVoice(id: "en-AU-WilliamNeural", name: "William", accent: "Australian", flag: "\u{1F1E6}\u{1F1FA}", female: false, blurb: "Australian"),
        AIVoice(id: "en-AU-NatashaNeural", name: "Natasha", accent: "Australian", flag: "\u{1F1E6}\u{1F1FA}", female: true, blurb: "Australian"),
    ]

    static func voice(for id: String) -> AIVoice {
        return all.first(where: { $0.id == id }) ?? all[0]
    }
}

// MARK: - Azure Speech client

enum AzureSpeech {
    static let regions: [String] = [
        "eastus", "eastus2", "westus", "westus2", "westus3", "centralus", "southcentralus", "canadacentral",
        "northeurope", "westeurope", "uksouth", "francecentral", "germanywestcentral", "swedencentral",
        "australiaeast", "southeastasia", "japaneast", "koreacentral", "centralindia", "brazilsouth",
        "southafricanorth", "uaenorth",
    ]

    static func escapeXML(_ s: String) -> String {
        var out = s.replacingOccurrences(of: "&", with: "&amp;")
        out = out.replacingOccurrences(of: "<", with: "&lt;")
        out = out.replacingOccurrences(of: ">", with: "&gt;")
        out = out.replacingOccurrences(of: "\"", with: "&quot;")
        out = out.replacingOccurrences(of: "'", with: "&apos;")
        return out
    }

    /// Splits long scripts into pieces of about 2,800 characters at sentence boundaries.
    static func chunk(_ text: String, limit: Int = 2800) -> [String] {
        var out: [String] = []
        var cur = ""
        for sentence in ScriptParser.splitSentences(text) {
            if !cur.isEmpty && cur.count + sentence.count + 1 > limit {
                out.append(cur)
                cur = ""
            }
            cur += (cur.isEmpty ? "" : " ") + sentence
        }
        if !cur.isEmpty { out.append(cur) }
        return out
    }

    private static func send(_ req: URLRequest) async throws -> (Data, HTTPURLResponse) {
        do {
            let (d, r) = try await URLSession.shared.data(for: req)
            guard let h = r as? HTTPURLResponse else {
                throw StudioError.message("Azure Speech sent an unexpected reply.")
            }
            return (d, h)
        } catch let e as StudioError {
            throw e
        } catch {
            throw StudioError.message("Couldn't reach Azure Speech. Check your internet connection and the region in Settings.")
        }
    }

    /// Makes an .mp3 voiceover with the chosen voice. `speedPercent` is -30...+30.
    static func synthesize(text: String, voice: String, speedPercent: Double, key: String, region: String, to url: URL,
                           shouldCancel: @escaping () -> Bool = { false }) async throws {
        let cleanRegion = region.trimmingCharacters(in: .whitespaces).lowercased()
        let cleanKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleanKey.isEmpty { throw StudioError.message("Add your Azure Speech key in Settings to use the natural AI voices.") }
        guard let endpoint = URL(string: "https://\(cleanRegion).tts.speech.microsoft.com/cognitiveservices/v1") else {
            throw StudioError.message("The Azure region looks wrong. Check it in Settings.")
        }
        try? FileManager.default.removeItem(at: url)
        FileManager.default.createFile(atPath: url.path, contents: nil)
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }

        let rate = String(format: "%+d%%", Int(speedPercent.rounded()))
        let pieces = chunk(text)
        if pieces.isEmpty { throw StudioError.message("There is no text to read.") }
        for part in pieces {
            if shouldCancel() { throw StudioError.cancelled }
            let ssml = "<speak version='1.0' xml:lang='en-US'><voice name='\(voice)'><prosody rate='\(rate)'>"
                + escapeXML(part) + "</prosody></voice></speak>"
            var req = URLRequest(url: endpoint, timeoutInterval: 90)
            req.httpMethod = "POST"
            req.setValue(cleanKey, forHTTPHeaderField: "Ocp-Apim-Subscription-Key")
            req.setValue("application/ssml+xml", forHTTPHeaderField: "Content-Type")
            req.setValue("audio-24khz-48kbitrate-mono-mp3", forHTTPHeaderField: "X-Microsoft-OutputFormat")
            req.setValue("TalkingStudio", forHTTPHeaderField: "User-Agent")
            req.httpBody = ssml.data(using: .utf8)

            let (data, http) = try await send(req)
            switch http.statusCode {
            case 200:
                handle.write(data)
            case 401:
                throw StudioError.message("Azure didn't accept your key. Check the key and the region in Settings.")
            case 403:
                throw StudioError.message("Azure refused the request. Your free allowance may be used up, or the key is for a different region.")
            case 429:
                throw StudioError.message("Azure says too many requests. Wait a minute and try again.")
            case 400:
                throw StudioError.message("Azure couldn't read that voice or text. Try a different voice.")
            default:
                throw StudioError.message("Azure Speech returned error \(http.statusCode).")
            }
        }
        let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
        if size == 0 { throw StudioError.message("Azure returned no audio.") }
    }
}

// MARK: - Secret storage (Keychain)

enum SecretStore {
    private static let service = "com.talkingstudio.app.secrets"

    static func set(_ value: String, account: String) {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(base as CFDictionary)
        var add = base
        add[kSecValueData as String] = Data(value.utf8)
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        let status = SecItemAdd(add as CFDictionary, nil)
        if status != errSecSuccess {
            UserDefaults.standard.set(value, forKey: "fallback." + account)
        } else {
            UserDefaults.standard.removeObject(forKey: "fallback." + account)
        }
    }

    static func get(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecSuccess, let data = result as? Data, let s = String(data: data, encoding: .utf8), !s.isEmpty {
            return s
        }
        return UserDefaults.standard.string(forKey: "fallback." + account)
    }

    static func remove(account: String) {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(base as CFDictionary)
        UserDefaults.standard.removeObject(forKey: "fallback." + account)
    }
}
