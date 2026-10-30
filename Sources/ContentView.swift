import AVFoundation
import AVKit
import Photos
import SwiftUI
import UniformTypeIdentifiers

let sampleScript = """
# Is the tree pagan?
Everyone says the Christmas tree is *pagan*. Historians say that's mostly wrong.
Yes, the ancient Romans decorated with greenery in winter. But there's no clear record linking that to the Christmas tree.
The real clue is a medieval play. On December twenty-fourth, towns staged the story of Adam and Eve, and they needed a tree for the Garden of Eden.
In winter, only evergreens stayed green, so they hung apples on one. [idea] People loved it, and took the idea home.
So the Christmas tree isn't an ancient cult. It's a medieval stage prop. Follow for the full story.
"""

@MainActor
final class StudioModel: ObservableObject {
    @Published var script = ""
    @Published var voices: [AVSpeechSynthesisVoice] = []
    @Published var voiceID = ""
    @Published var speed: Double = 0
    @Published var ownAudioURL: URL? = nil
    @Published var useOwnAudio = false
    @Published var landscape = false
    @Published var highQuality = false
    @Published var captions = true
    @Published var pictures = true
    @Published var strictLicenses = false
    @Published var dim: Double = 0.55
    @Published var busy = false
    @Published var progress: Double = 0
    @Published var message = ""
    @Published var errorText: String? = nil
    @Published var result: StudioResult? = nil
    @Published var player: AVPlayer? = nil

    init() {
        voices = SpeechSynth.englishVoices()
        voiceID = voices.first?.identifier ?? ""
    }

    func make(preview: Bool) {
        if busy { return }
        errorText = nil
        result = nil
        player = nil
        if script.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errorText = "Paste or load a script first."
            return
        }
        if useOwnAudio && ownAudioURL == nil {
            errorText = "Choose an audio file first, or turn off 'Use my own recording'."
            return
        }
        busy = true
        progress = 0
        message = "Starting"
        let options = StudioOptions(script: script, voiceID: voiceID.isEmpty ? nil : voiceID, speed: speed,
                                    ownAudio: useOwnAudio ? ownAudioURL : nil, landscape: landscape, highQuality: highQuality,
                                    captions: captions, pictures: pictures, strictLicenses: strictLicenses, dim: dim,
                                    previewSeconds: preview ? 12 : nil)
        UIApplication.shared.isIdleTimerDisabled = true
        Task.detached(priority: .userInitiated) { [weak self] in
            do {
                let res = try await Pipeline.run(options) { msg, frac in
                    Task { @MainActor in
                        self?.message = msg
                        self?.progress = frac
                    }
                }
                await MainActor.run {
                    self?.result = res
                    self?.player = AVPlayer(url: res.videoURL)
                    self?.busy = false
                    UIApplication.shared.isIdleTimerDisabled = false
                }
            } catch {
                await MainActor.run {
                    self?.errorText = error.localizedDescription
                    self?.busy = false
                    UIApplication.shared.isIdleTimerDisabled = false
                }
            }
        }
    }

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

    func loadAudio(from url: URL) {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        do {
            let dest = FileManager.default.temporaryDirectory.appendingPathComponent("own-" + UUID().uuidString + "." + (url.pathExtension.isEmpty ? "m4a" : url.pathExtension))
            try? FileManager.default.removeItem(at: dest)
            try FileManager.default.copyItem(at: url, to: dest)
            ownAudioURL = dest
            useOwnAudio = true
        } catch {
            errorText = "Could not read that audio file: " + error.localizedDescription
        }
    }
}

struct ContentView: View {
    @StateObject private var model = StudioModel()
    @State private var showScriptPicker = false
    @State private var showAudioPicker = false

    var body: some View {
        NavigationStack {
            Form {
                Section("1. Your script") {
                    TextEditor(text: $model.script)
                        .frame(minHeight: 200)
                        .font(.system(.body, design: .monospaced))
                    HStack {
                        Button("Load .txt / .md") { showScriptPicker = true }
                        Spacer()
                        Button("Paste") {
                            if let s = UIPasteboard.general.string { model.script = s }
                        }
                        Spacer()
                        Button("Example") { model.script = sampleScript }
                    }
                    .buttonStyle(.bordered)
                    Text("Tips: # Title for a chapter banner, *word* to highlight, [point] [think] [happy] for gestures, [image: roman forum] to choose a picture, [noimage] for none.")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }

                Section("2. Voice") {
                    Toggle("Use my own recording", isOn: $model.useOwnAudio)
                    if model.useOwnAudio {
                        Button(model.ownAudioURL == nil ? "Choose an audio file" : "Change audio file") { showAudioPicker = true }
                        if let u = model.ownAudioURL {
                            Text(u.lastPathComponent).font(.footnote).foregroundColor(.secondary)
                        }
                    } else {
                        Picker("Voice", selection: $model.voiceID) {
                            ForEach(model.voices, id: \.identifier) { v in
                                Text(v.name + " (" + v.language + ")").tag(v.identifier)
                            }
                        }
                        VStack(alignment: .leading) {
                            Text("Speed: \(Int(model.speed))%")
                            Slider(value: $model.speed, in: -30...30, step: 5)
                        }
                        Text("For nicer voices: Settings > Accessibility > Spoken Content > Voices, then download an Enhanced or Premium voice.")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    }
                }

                Section("3. Pictures") {
                    Toggle("Free pictures behind the character", isOn: $model.pictures)
                    if model.pictures {
                        Toggle("Only pictures that need no credit", isOn: $model.strictLicenses)
                        VStack(alignment: .leading) {
                            Text("Picture darkness: \(Int(model.dim * 100))%")
                            Slider(value: $model.dim, in: 0.2...0.8, step: 0.05)
                        }
                        Text("Searches Wikimedia Commons, NASA and the Cleveland Museum of Art. Only licences that allow commercial use and edits are used; a credits file is saved with each video.")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    }
                }

                Section("4. Video") {
                    Picker("Format", selection: $model.landscape) {
                        Text("Shorts / Reels (9:16)").tag(false)
                        Text("YouTube widescreen (16:9)").tag(true)
                    }
                    Toggle("Full HD (slower, bigger)", isOn: $model.highQuality)
                    Toggle("Captions", isOn: $model.captions)
                }

                Section {
                    HStack {
                        Button("Preview 12 s") { model.make(preview: true) }
                            .buttonStyle(.bordered)
                        Spacer()
                        Button("Make the video") { model.make(preview: false) }
                            .buttonStyle(.borderedProminent)
                    }
                    .disabled(model.busy)
                    if model.busy {
                        ProgressView(value: model.progress)
                        Text(model.message).font(.footnote).foregroundColor(.secondary)
                        Text("Keep the app open and the screen on while it works.").font(.footnote).foregroundColor(.secondary)
                    } else if !model.message.isEmpty && model.result != nil {
                        Text(model.message).font(.footnote).foregroundColor(.secondary)
                    }
                    if let e = model.errorText {
                        Text(e).foregroundColor(.red)
                    }
                }

                if let res = model.result {
                    Section("Your video (\(Int(res.seconds)) s)") {
                        if let p = model.player {
                            VideoPlayer(player: p).frame(height: 420)
                        }
                        HStack {
                            ShareLink(item: res.videoURL) { Label("Share", systemImage: "square.and.arrow.up") }
                            Spacer()
                            Button { model.saveToPhotos(res.videoURL) } label: { Label("Save to Photos", systemImage: "photo") }
                        }
                        .buttonStyle(.bordered)
                        Text("Also saved in the Files app under Talking Studio.").font(.footnote).foregroundColor(.secondary)
                        if !res.credits.isEmpty {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Image credits (paste into your video description)").font(.footnote).bold()
                                Text(res.credits.joined(separator: "\n")).font(.caption2).textSelection(.enabled)
                                Button("Copy credits") { UIPasteboard.general.string = res.credits.joined(separator: "\n") }
                                    .buttonStyle(.bordered)
                            }
                        }
                        ForEach(res.warnings, id: \.self) { w in
                            Text(w).font(.footnote).foregroundColor(.orange)
                        }
                    }
                }
            }
            .navigationTitle("Talking Studio")
        }
        .fileImporter(isPresented: $showScriptPicker, allowedContentTypes: [.plainText, .text, UTType(filenameExtension: "md") ?? .plainText],
                      allowsMultipleSelection: false) { result in
            if case .success(let urls) = result, let u = urls.first { model.loadScript(from: u) }
        }
        .fileImporter(isPresented: $showAudioPicker, allowedContentTypes: [.audio], allowsMultipleSelection: false) { result in
            if case .success(let urls) = result, let u = urls.first { model.loadAudio(from: u) }
        }
    }
}
