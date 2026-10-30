import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct CreateView: View {
    @EnvironmentObject var model: StudioModel
    @State private var showScriptPicker = false
    @State private var showAudioPicker = false
    @State private var showTags = false
    @FocusState private var editorFocused: Bool

    private let voiceOptions: [SegmentOption<VoiceMode>] = [
        SegmentOption(value: .ai, title: "Natural AI", icon: "sparkles"),
        SegmentOption(value: .device, title: "iPhone", icon: "iphone"),
        SegmentOption(value: .recording, title: "My audio", icon: "mic.fill"),
    ]
    private let qualityOptions: [SegmentOption<Bool>] = [
        SegmentOption(value: false, title: "Standard 720p", icon: "bolt.fill"),
        SegmentOption(value: true, title: "Full HD 1080p", icon: "sparkle"),
    ]

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground()
                ScrollView {
                    VStack(spacing: 16) {
                        header
                        scriptCard
                        voiceCard
                        picturesCard
                        videoCard
                        Color.clear.frame(height: 24)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 6)
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .safeAreaInset(edge: .bottom) { bottomBar }
            .toolbar(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { editorFocused = false }
                }
            }
        }
        .fileImporter(isPresented: $showScriptPicker,
                      allowedContentTypes: [.plainText, .text, UTType(filenameExtension: "md") ?? .plainText],
                      allowsMultipleSelection: false) { result in
            if case .success(let urls) = result, let u = urls.first { model.loadScript(from: u) }
        }
        .fileImporter(isPresented: $showAudioPicker, allowedContentTypes: [.audio], allowsMultipleSelection: false) { result in
            if case .success(let urls) = result, let u = urls.first { model.loadRecording(from: u) }
        }
        .sheet(isPresented: $showTags) {
            TagsHelpView()
                .presentationDetents([.medium, .large])
        }
    }

    // MARK: header

    private var header: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(RadialGradient(colors: [Theme.blue.opacity(0.55), Color.clear], center: .center, startRadius: 4, endRadius: 46))
                    .frame(width: 84, height: 84)
                Image(uiImage: Mascot.avatar)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 70, height: 70)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text("Talking Studio")
                    .font(.system(size: 30, weight: .heavy, design: .rounded))
                    .foregroundStyle(Color.white)
                Text("Turn any script into a talking video")
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondary)
            }
            Spacer(minLength: 0)
            Button {
                Haptics.tap()
                model.showSettings = true
            } label: {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Color.white)
                    .frame(width: 42, height: 42)
                    .background(Circle().fill(Color.white.opacity(0.09)))
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 4)
    }

    // MARK: script

    private var scriptCard: some View {
        CardSection(icon: "text.alignleft", title: "Your script",
                    subtitle: "\(model.wordCount) words  \u{00B7}  about \(formatClock(model.estimatedSeconds)) long") {
            ZStack(alignment: .topLeading) {
                if model.script.isEmpty {
                    Text("Paste your narration here...\n\nStart a line with # for a chapter title. Put *stars* around words to highlight them.")
                        .font(.body)
                        .foregroundStyle(Theme.tertiary)
                        .padding(.top, 8)
                        .padding(.leading, 5)
                        .allowsHitTesting(false)
                }
                TextEditor(text: $model.script)
                    .scrollContentBackground(.hidden)
                    .font(.body)
                    .foregroundStyle(Color.white)
                    .frame(minHeight: 190)
                    .focused($editorFocused)
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.black.opacity(0.28)))
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ChipButton(title: "Open file", icon: "doc") { showScriptPicker = true }
                    ChipButton(title: "Paste", icon: "doc.on.clipboard") {
                        if let s = UIPasteboard.general.string { model.script = s }
                    }
                    ChipButton(title: "Example", icon: "sparkles") { model.script = sampleScript }
                    ChipButton(title: "Tags", icon: "number") { showTags = true }
                    if !model.script.isEmpty {
                        ChipButton(title: "Clear", icon: "xmark") { model.script = "" }
                    }
                }
                .padding(.vertical, 1)
            }
        }
    }

    // MARK: voice

    private var voiceSubtitle: String {
        switch model.voiceMode {
        case .ai: return AIVoices.voice(for: model.aiVoiceID).name + " \u{00B7} natural Microsoft neural voice"
        case .device: return "Built into your iPhone, works offline"
        case .recording: return model.recordingURL == nil ? "Use your own voiceover" : "Using your recording"
        }
    }

    private var voiceCard: some View {
        CardSection(icon: "waveform", title: "Voice", subtitle: voiceSubtitle) {
            SegmentedTabs(options: voiceOptions, selection: $model.voiceMode)
            switch model.voiceMode {
            case .ai:
                aiVoices
            case .device:
                deviceVoices
            case .recording:
                recording
            }
            if model.voiceMode != .recording {
                speedControl
            }
        }
    }

    @ViewBuilder private var aiVoices: some View {
        if !model.hasAzureKey {
            Callout(icon: "sparkles", title: "Unlock the natural AI voices",
                    message: "Add your free Microsoft Azure Speech key once. These are the same neural voices as the desktop studio, and the free tier covers about 500,000 characters a month.",
                    buttonTitle: "Set up voices", action: { model.showSettings = true })
        }
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(AIVoices.all) { v in
                    VoiceCard(voice: v,
                              selected: model.aiVoiceID == v.id,
                              loading: model.previewIsLoading && model.previewingID == v.id,
                              playing: !model.previewIsLoading && model.previewingID == v.id,
                              enabled: model.hasAzureKey,
                              onSelect: {
                                  Haptics.select()
                                  model.aiVoiceID = v.id
                              },
                              onPlay: { model.previewAIVoice(v) })
                }
            }
            .padding(.vertical, 2)
        }
        Text("Tap a card to choose, press play to hear it.")
            .font(.caption)
            .foregroundStyle(Theme.tertiary)
    }

    @ViewBuilder private var deviceVoices: some View {
        HStack {
            Text("Voice").foregroundStyle(Theme.secondary)
            Spacer()
            Picker("Voice", selection: $model.deviceVoiceID) {
                ForEach(model.deviceVoices, id: \.identifier) { v in
                    Text(model.deviceVoiceLabel(v)).tag(v.identifier)
                }
            }
            .pickerStyle(.menu)
            .tint(Theme.lightBlue)
        }
        Callout(icon: "arrow.down.circle", title: "Get better iPhone voices",
                message: "Settings > Accessibility > Spoken Content > Voices > English. Download an Enhanced or Premium voice, then pick it here.",
                tint: Color(red: 0.55, green: 0.45, blue: 1.0))
    }

    @ViewBuilder private var recording: some View {
        Button {
            showAudioPicker = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: model.recordingURL == nil ? "square.and.arrow.down" : "checkmark.circle.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(model.recordingURL == nil ? Theme.lightBlue : Theme.good)
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.recordingURL == nil ? "Choose an audio file" : (model.recordingURL?.lastPathComponent ?? ""))
                        .font(.system(.subheadline, design: .rounded).weight(.semibold))
                        .lineLimit(1)
                    Text("mp3, m4a or wav. The script must match what is said.")
                        .font(.caption)
                        .foregroundStyle(Theme.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(Theme.tertiary)
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.white.opacity(0.06)))
        }
        .buttonStyle(.plain)
    }

    private var speedControl: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Speaking speed").font(.subheadline).foregroundStyle(Theme.secondary)
                Spacer()
                Text(model.speed == 0 ? "Normal" : String(format: "%+d%%", Int(model.speed)))
                    .font(.system(.subheadline, design: .rounded).weight(.bold))
                    .foregroundStyle(Theme.lightBlue)
            }
            Slider(value: $model.speed, in: -30...30, step: 5)
                .tint(Theme.blue)
        }
    }

    // MARK: pictures

    private var picturesCard: some View {
        CardSection(icon: "photo.on.rectangle.angled", title: "Pictures", subtitle: "Free-to-use images behind your character") {
            Toggle(isOn: $model.pictures) {
                Text("Add background pictures").font(.subheadline.weight(.semibold))
            }
            .tint(Theme.blue)
            if model.pictures {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Darkness").font(.subheadline).foregroundStyle(Theme.secondary)
                        Spacer()
                        Text("\(Int(model.dim * 100))%").font(.system(.subheadline, design: .rounded).weight(.bold)).foregroundStyle(Theme.lightBlue)
                    }
                    Slider(value: $model.dim, in: 0.2...0.8, step: 0.05).tint(Theme.blue)
                }
                Toggle(isOn: $model.strictLicenses) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Only pictures that need no credit").font(.subheadline.weight(.semibold))
                        Text("Otherwise CC BY pictures are allowed, with a credits list.").font(.caption).foregroundStyle(Theme.secondary)
                    }
                }
                .tint(Theme.blue)
                Text("From Wikimedia Commons, NASA and the Cleveland Museum of Art. Use [image: words] in your script to choose what to search for.")
                    .font(.caption)
                    .foregroundStyle(Theme.tertiary)
            }
        }
    }

    // MARK: video

    private var videoCard: some View {
        CardSection(icon: "film", title: "Video", subtitle: model.landscape ? "Widescreen for YouTube" : "Vertical for Shorts, Reels and TikTok") {
            HStack(spacing: 12) {
                FormatTile(title: "Shorts", subtitle: "9:16 vertical", aspect: 9.0 / 16.0, selected: !model.landscape) {
                    withAnimation(.easeInOut(duration: 0.2)) { model.landscape = false }
                }
                FormatTile(title: "YouTube", subtitle: "16:9 widescreen", aspect: 16.0 / 9.0, selected: model.landscape) {
                    withAnimation(.easeInOut(duration: 0.2)) { model.landscape = true }
                }
            }
            SegmentedTabs(options: qualityOptions, selection: $model.highQuality)
            Toggle(isOn: $model.captions) {
                Text("Captions").font(.subheadline.weight(.semibold))
            }
            .tint(Theme.blue)
        }
    }

    // MARK: bottom bar

    private var bottomBar: some View {
        VStack(spacing: 10) {
            if let e = model.errorText {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Theme.danger)
                    Text(e).font(.footnote).foregroundStyle(Color.white).fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    Button {
                        withAnimation { model.errorText = nil }
                    } label: {
                        Image(systemName: "xmark").font(.footnote.weight(.bold)).foregroundStyle(Theme.secondary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.danger.opacity(0.16)))
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            HStack(spacing: 12) {
                Button {
                    editorFocused = false
                    model.makeVideo(preview: true)
                } label: {
                    Label("Preview", systemImage: "play.circle")
                }
                .buttonStyle(SecondaryButtonStyle())
                .frame(maxWidth: 140)

                Button {
                    editorFocused = false
                    model.makeVideo(preview: false)
                } label: {
                    Label("Make video", systemImage: "wand.and.stars")
                }
                .buttonStyle(PrimaryButtonStyle(enabled: model.canMake))
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .background(
            Rectangle()
                .fill(.ultraThinMaterial)
                .overlay(Rectangle().fill(Theme.navy.opacity(0.55)))
                .overlay(alignment: .top) { Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1) }
                .ignoresSafeArea()
        )
        .animation(.easeInOut(duration: 0.2), value: model.errorText)
    }
}

// MARK: - Tag help

struct TagsHelpView: View {
    private let rows: [(String, String)] = [
        ("# Chapter title", "Shows a title banner"),
        ("*word*", "Highlights a word in the captions"),
        ("[point] [explain] [open]", "Arm gestures"),
        ("[think] [wave] [thumbs]", "More gestures"),
        ("[celebrate] [present] [rest]", "Even more gestures"),
        ("[happy] [excited] [surprised]", "Eye expressions"),
        ("[angry] [tired] [sad] [wink]", "More expressions"),
        ("[idea]", "Pops up a lightbulb"),
        ("[image: roman forum]", "Picks the background picture"),
        ("[noimage]", "Keeps the studio background"),
    ]

    var body: some View {
        ZStack {
            AppBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Script tags")
                        .font(.system(size: 26, weight: .heavy, design: .rounded))
                    Text("Type these anywhere in a sentence. Without tags the character picks gestures by itself: questions make it think, exclamations make it excited.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.secondary)
                    ForEach(rows.indices, id: \.self) { i in
                        let row = rows[i]
                        HStack(alignment: .top) {
                            Text(row.0)
                                .font(.system(.subheadline, design: .monospaced).weight(.semibold))
                                .foregroundStyle(Theme.lightBlue)
                            Spacer()
                            Text(row.1)
                                .font(.subheadline)
                                .foregroundStyle(Theme.secondary)
                                .multilineTextAlignment(.trailing)
                        }
                        .padding(12)
                        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.06)))
                    }
                }
                .padding(20)
            }
        }
    }
}
