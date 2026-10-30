import AVFoundation
import Photos
import SwiftUI
import UIKit

enum VoiceMode: String {
    case ai, device, recording
}

let sampleScript = """
# Is the tree pagan?
Everyone says the Christmas tree is *pagan*. Historians say that's mostly wrong.
Yes, the ancient Romans decorated with greenery in winter. But there's no clear record linking that to the Christmas tree.
The real clue is a medieval play. On December twenty-fourth, towns staged the story of Adam and Eve, and they needed a tree for the Garden of Eden.
In winter, only evergreens stayed green, so they hung apples on one. [idea] People loved it, and took the idea home.
So the Christmas tree isn't an ancient cult. It's a medieval stage prop. Follow for the full story.
"""

final class PreviewPlayerDelegate: NSObject, AVAudioPlayerDelegate {
    var onFinish: () -> Void = {}
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        onFinish()
    }
}

@MainActor
final class StudioModel: ObservableObject {
    private static let ud = UserDefaults.standard

    // saved settings
    @Published var script: String { didSet { Self.ud.set(script, forKey: "script") } }
    @Published var voiceMode: VoiceMode { didSet { Self.ud.set(voiceMode.rawValue, forKey: "voiceMode") } }
    @Published var aiVoiceID: String { didSet { Self.ud.set(aiVoiceID, forKey: "aiVoiceID") } }
    @Published var deviceVoiceID: String { didSet { Self.ud.set(deviceVoiceID, forKey: "deviceVoiceID") } }
    @Published var speed: Double { didSet { Self.ud.set(speed, forKey: "speed") } }
    @Published var landscape: Bool { didSet { Self.ud.set(landscape, forKey: "landscape") } }
    @Published var highQuality: Bool { didSet { Self.ud.set(highQuality, forKey: "highQuality") } }
    @Published var captions: Bool { didSet { Self.ud.set(captions, forKey: "captions") } }
    @Published var pictures: Bool { didSet { Self.ud.set(pictures, forKey: "pictures") } }
    @Published var strictLicenses: Bool { didSet { Self.ud.set(strictLicenses, forKey: "strict") } }
    @Published var dim: Double { didSet { Self.ud.set(dim, forKey: "dim") } }
    @Published var azureRegion: String { didSet { Self.ud.set(azureRegion, forKey: "azureRegion") } }
    @Published var hasAzureKey: Bool

    // state
    @Published var deviceVoices: [AVSpeechSynthesisVoice]
    @Published var recordingURL: URL? = nil
    @Published var busy = false
    @Published var progress: Double = 0
    @Published var message = ""
    @Published var errorText: String? = nil
    @Published var result: StudioResult? = nil
    @Published var showResult = false
    @Published var showSettings = false
    @Published var libraryVersion = 0
    @Published var previewingID: String? = nil
    @Published var previewIsLoading = false

    private var cancelToken: CancelToken? = nil
    private var previewPlayer: AVAudioPlayer? = nil
    private let previewDelegate = PreviewPlayerDelegate()

    init() {
        let d = UserDefaults.standard
        script = d.string(forKey: "script") ?? ""
        voiceMode = VoiceMode(rawValue: d.string(forKey: "voiceMode") ?? "") ?? .ai
        aiVoiceID = d.string(forKey: "aiVoiceID") ?? AIVoices.all[0].id
        let voices = SpeechSynth.englishVoices()
        deviceVoices = voices
        deviceVoiceID = d.string(forKey: "deviceVoiceID") ?? (voices.first?.identifier ?? "")
        speed = (d.object(forKey: "speed") as? Double) ?? 0
        landscape = d.bool(forKey: "landscape")
        highQuality = d.bool(forKey: "highQuality")
        captions = (d.object(forKey: "captions") as? Bool) ?? true
        pictures = (d.object(forKey: "pictures") as? Bool) ?? true
        strictLicenses = d.bool(forKey: "strict")
        dim = (d.object(forKey: "dim") as? Double) ?? 0.55
        azureRegion = d.string(forKey: "azureRegion") ?? "eastus"
        hasAzureKey = SecretStore.get(account: "azureKey") != nil
        previewDelegate.onFinish = { [weak self] in
            Task { @MainActor in
                self?.previewingID = nil
            }
        }
    }

    // MARK: script helpers

    var wordCount: Int {
        return script.split(whereSeparator: { $0.isWhitespace }).filter { !$0.hasPrefix("[") && !$0.hasPrefix("#") }.count
    }

    var estimatedSeconds: Double {
        return Double(wordCount) / 2.6
    }

    var azureKey: String {
        return SecretStore.get(account: "azureKey") ?? ""
    }

    var canMake: Bool {
        if script.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return false }
        switch voiceMode {
        case .ai: return hasAzureKey
        case .device: return true
        case .recording: return recordingURL != nil
        }
    }

    func deviceVoiceLabel(_ v: AVSpeechSynthesisVoice) -> String {
        var quality = "Standard"
        if v.quality == .premium { quality = "Premium" } else if v.quality == .enhanced { quality = "Enhanced" }
        return v.name + "  (" + v.language + ", " + quality + ")"
    }

    // MARK: Azure key

    func saveAzure(key: String, region: String) {
        let k = key.trimmingCharacters(in: .whitespacesAndNewlines)
        if !k.isEmpty { SecretStore.set(k, account: "azureKey") }
        azureRegion = region
        hasAzureKey = SecretStore.get(account: "azureKey") != nil
    }

    func clearAzureKey() {
        SecretStore.remove(account: "azureKey")
        hasAzureKey = false
    }

    /// Makes a tiny test clip with the given key; returns nil on success or an error message.
    func testAzure(key: String, region: String) async -> String? {
        let k = key.isEmpty ? azureKey : key
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("azure-test.mp3")
        do {
            try await AzureSpeech.synthesize(text: "Connection works.", voice: aiVoiceID, speedPercent: 0, key: k, region: region, to: url)
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    // MARK: voice previews

    func previewAIVoice(_ v: AIVoice) {
        if previewingID == v.id {
            stopPreview()
            return
        }
        guard hasAzureKey else {
            showSettings = true
            return
        }
        stopPreview()
        previewingID = v.id
        previewIsLoading = true
        let key = azureKey
        let region = azureRegion
        let spd = speed
        Task {
            do {
                let url = FileManager.default.temporaryDirectory.appendingPathComponent("preview-\(v.id)-\(Int(spd)).mp3")
                if !FileManager.default.fileExists(atPath: url.path) {
                    let text = "Hi, I'm \(v.name). This is how I'll sound reading your script."
                    try await AzureSpeech.synthesize(text: text, voice: v.id, speedPercent: spd, key: key, region: region, to: url)
                }
                if previewingID != v.id { return }
                try AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
                try AVAudioSession.sharedInstance().setActive(true)
                let p = try AVAudioPlayer(contentsOf: url)
                p.delegate = previewDelegate
                previewPlayer = p
                previewIsLoading = false
                p.play()
            } catch {
                previewIsLoading = false
                previewingID = nil
                errorText = error.localizedDescription
                Haptics.error()
            }
        }
    }

    func stopPreview() {
        previewPlayer?.stop()
        previewPlayer = nil
        previewingID = nil
        previewIsLoading = false
    }

    // MARK: making videos

    func makeVideo(preview: Bool) {
        if busy { return }
        errorText = nil
        stopPreview()
        if script.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errorText = "Write or paste a script first."
            Haptics.error()
            return
        }
        let voice: VoiceChoice
        switch voiceMode {
        case .ai:
            if !hasAzureKey {
                errorText = "Add your Azure Speech key to use the natural AI voices, or pick iPhone voices."
                showSettings = true
                return
            }
            voice = .azure(voice: aiVoiceID, key: azureKey, region: azureRegion)
        case .device:
            voice = .device(id: deviceVoiceID.isEmpty ? nil : deviceVoiceID)
        case .recording:
            guard let u = recordingURL else {
                errorText = "Choose your audio file first."
                Haptics.error()
                return
            }
            voice = .recording(u)
        }
        let options = StudioOptions(script: script, voice: voice, speed: speed, landscape: landscape, highQuality: highQuality,
                                    captions: captions, pictures: pictures, strictLicenses: strictLicenses, dim: dim,
                                    previewSeconds: preview ? 12 : nil)
        let token = CancelToken()
        cancelToken = token
        result = nil
        progress = 0
        message = "Getting ready"
        busy = true
        Haptics.tap()
        UIApplication.shared.isIdleTimerDisabled = true
        Task.detached(priority: .userInitiated) { [weak self] in
            do {
                let res = try await Pipeline.run(options, cancel: token) { msg, frac in
                    Task { @MainActor in
                        self?.message = msg
                        self?.progress = frac
                    }
                }
                await MainActor.run { self?.finish(res) }
            } catch StudioError.cancelled {
                await MainActor.run { self?.finishCancelled() }
            } catch {
                let text = error.localizedDescription
                await MainActor.run { self?.fail(text) }
            }
        }
    }

    func cancel() {
        cancelToken?.cancel()
        message = "Stopping..."
    }

    private func finish(_ res: StudioResult) {
        UIApplication.shared.isIdleTimerDisabled = false
        result = res
        busy = false
        libraryVersion += 1
        Haptics.success()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.showResult = true
        }
    }

    private func finishCancelled() {
        UIApplication.shared.isIdleTimerDisabled = false
        busy = false
    }

    private func fail(_ text: String) {
        UIApplication.shared.isIdleTimerDisabled = false
        busy = false
        errorText = text
        Haptics.error()
    }

    // MARK: files and photos

    func saveToPhotos(_ url: URL) {
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            if status != .authorized && status != .limited {
                Task { @MainActor in
                    self.errorText = "Allow Photos access in Settings to save videos."
                }
                return
            }
            PHPhotoLibrary.shared().performChanges({
                PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
            }, completionHandler: { ok, err in
                Task { @MainActor in
                    if ok {
                        self.message = "Saved to Photos"
                        Haptics.success()
                    } else {
                        self.errorText = err?.localizedDescription ?? "Could not save to Photos."
                    }
                }
            })
        }
    }

    func loadScript(from url: URL) {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        do {
            let data = try Data(contentsOf: url)
            script = String(decoding: data, as: UTF8.self)
        } catch {
            errorText = "Could not read that file: " + error.localizedDescription
        }
    }

    func loadRecording(from url: URL) {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        do {
            let ext = url.pathExtension.isEmpty ? "m4a" : url.pathExtension
            let dest = FileManager.default.temporaryDirectory.appendingPathComponent("own-" + UUID().uuidString + "." + ext)
            try FileManager.default.copyItem(at: url, to: dest)
            recordingURL = dest
            voiceMode = .recording
        } catch {
            errorText = "Could not read that audio file: " + error.localizedDescription
        }
    }
}
