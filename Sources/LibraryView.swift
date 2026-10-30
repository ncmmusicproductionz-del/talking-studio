import AVFoundation
import AVKit
import SwiftUI
import UIKit

struct LibraryItem: Identifiable {
    let id: URL
    let title: String
    let date: Date
    let seconds: Double
    let voice: String
    let preview: Bool
    let creditsURL: URL?
    var url: URL { id }
}

enum Library {
    static func load() -> [LibraryItem] {
        guard let folder = try? Pipeline.outputFolder() else { return [] }
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.creationDateKey],
                                                                   options: [.skipsHiddenFiles])) ?? []
        var items: [LibraryItem] = []
        for f in files where f.pathExtension.lowercased() == "mp4" {
            let base = f.deletingPathExtension()
            let name = base.lastPathComponent
            var meta: VideoMeta? = nil
            if let d = try? Data(contentsOf: folder.appendingPathComponent(name + ".json")) {
                meta = try? JSONDecoder().decode(VideoMeta.self, from: d)
            }
            let creditsFile = folder.appendingPathComponent(name + "-image-credits.txt")
            let credits: URL? = FileManager.default.fileExists(atPath: creditsFile.path) ? creditsFile : nil
            let fileDate = (try? f.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? Date()
            items.append(LibraryItem(id: f,
                                     title: meta?.title ?? name,
                                     date: meta?.created ?? fileDate,
                                     seconds: meta?.seconds ?? 0,
                                     voice: meta?.voice ?? "",
                                     preview: meta?.preview ?? name.hasPrefix("Preview-"),
                                     creditsURL: credits))
        }
        return items.sorted { $0.date > $1.date }
    }

    static func delete(_ item: LibraryItem) {
        let folder = item.url.deletingLastPathComponent()
        let name = item.url.deletingPathExtension().lastPathComponent
        try? FileManager.default.removeItem(at: item.url)
        try? FileManager.default.removeItem(at: folder.appendingPathComponent(name + ".json"))
        if let c = item.creditsURL { try? FileManager.default.removeItem(at: c) }
    }

    static func thumbnail(_ url: URL) async -> UIImage? {
        let asset = AVURLAsset(url: url)
        let gen = AVAssetImageGenerator(asset: asset)
        gen.appliesPreferredTrackTransform = true
        gen.maximumSize = CGSize(width: 480, height: 480)
        do {
            let result = try await gen.image(at: CMTime(seconds: 1.0, preferredTimescale: 600))
            return UIImage(cgImage: result.image)
        } catch {
            return nil
        }
    }
}

struct ThumbnailView: View {
    let url: URL
    @State private var image: UIImage? = nil

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.white.opacity(0.06))
            if let img = image {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: "film").foregroundStyle(Theme.tertiary)
            }
            Image(systemName: "play.circle.fill")
                .font(.system(size: 26))
                .foregroundStyle(Color.white.opacity(0.92))
                .shadow(radius: 6)
        }
        .frame(width: 92, height: 120)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .task {
            if image == nil { image = await Library.thumbnail(url) }
        }
    }
}

struct PlayerSheet: View {
    let item: LibraryItem
    @EnvironmentObject var model: StudioModel
    @Environment(\.dismiss) private var dismiss
    @State private var player: AVPlayer? = nil

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 16) {
                HStack {
                    Text(item.title).font(.system(.headline, design: .rounded)).lineLimit(1)
                    Spacer()
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark").font(.system(size: 15, weight: .bold)).foregroundStyle(Color.white)
                            .frame(width: 34, height: 34).background(Circle().fill(Color.white.opacity(0.12)))
                    }
                    .buttonStyle(.plain)
                }
                if let p = player {
                    VideoPlayer(player: p)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                HStack(spacing: 12) {
                    ShareLink(item: item.url) { Label("Share", systemImage: "square.and.arrow.up") }
                        .buttonStyle(SecondaryButtonStyle())
                    Button {
                        model.saveToPhotos(item.url)
                    } label: {
                        Label("Save to Photos", systemImage: "photo.badge.plus")
                    }
                    .buttonStyle(PrimaryButtonStyle())
                }
            }
            .padding(18)
        }
        .onAppear {
            let p = AVPlayer(url: item.url)
            player = p
            p.play()
        }
        .onDisappear { player?.pause() }
    }
}

struct LibraryView: View {
    @EnvironmentObject var model: StudioModel
    var onCreate: () -> Void = {}
    @State private var items: [LibraryItem] = []
    @State private var playing: LibraryItem? = nil
    @State private var toDelete: LibraryItem? = nil

    private let dateFormat: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground()
                if items.isEmpty {
                    emptyState
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("My Videos")
                                .font(.system(size: 30, weight: .heavy, design: .rounded))
                                .padding(.bottom, 4)
                            ForEach(items) { item in
                                row(item)
                            }
                        }
                        .padding(16)
                    }
                }
            }
            .toolbar(.hidden, for: .navigationBar)
        }
        .onAppear { items = Library.load() }
        .onChange(of: model.libraryVersion) { _ in items = Library.load() }
        .sheet(item: $playing) { item in
            PlayerSheet(item: item).environmentObject(model)
        }
        .confirmationDialog("Delete this video?", isPresented: Binding(get: { toDelete != nil }, set: { if !$0 { toDelete = nil } }),
                            titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                if let d = toDelete {
                    Library.delete(d)
                    items = Library.load()
                    Haptics.tap()
                }
                toDelete = nil
            }
            Button("Cancel", role: .cancel) { toDelete = nil }
        } message: {
            Text("It will be removed from this app. Copies you saved to Photos stay.")
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(uiImage: Mascot.emptyState)
                .resizable()
                .scaledToFit()
                .frame(width: 170, height: 170)
            Text("No videos yet")
                .font(.system(size: 24, weight: .heavy, design: .rounded))
            Text("Videos you make appear here, ready to watch, share or save.")
                .font(.subheadline)
                .foregroundStyle(Theme.secondary)
                .multilineTextAlignment(.center)
            Button {
                onCreate()
            } label: {
                Label("Make your first video", systemImage: "wand.and.stars")
            }
            .buttonStyle(PrimaryButtonStyle())
            .frame(maxWidth: 280)
        }
        .padding(30)
    }

    private func row(_ item: LibraryItem) -> some View {
        HStack(spacing: 14) {
            ThumbnailView(url: item.url)
                .onTapGesture { playing = item }
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    if item.preview {
                        Text("PREVIEW")
                            .font(.system(size: 9, weight: .heavy, design: .rounded))
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Capsule().fill(Theme.blue.opacity(0.3)))
                    }
                    Text(item.title).font(.system(.subheadline, design: .rounded).weight(.bold)).lineLimit(2)
                }
                Text(dateFormat.string(from: item.date)).font(.caption).foregroundStyle(Theme.secondary)
                HStack(spacing: 10) {
                    if item.seconds > 0 {
                        Label(formatClock(item.seconds), systemImage: "clock").font(.caption2).foregroundStyle(Theme.tertiary)
                    }
                    if !item.voice.isEmpty {
                        Label(item.voice, systemImage: "waveform").font(.caption2).foregroundStyle(Theme.tertiary).lineLimit(1)
                    }
                }
                HStack(spacing: 8) {
                    ShareLink(item: item.url) {
                        Image(systemName: "square.and.arrow.up").font(.system(size: 13, weight: .semibold))
                            .frame(width: 34, height: 30).background(Capsule().fill(Color.white.opacity(0.08)))
                    }
                    Button {
                        model.saveToPhotos(item.url)
                    } label: {
                        Image(systemName: "photo.badge.plus").font(.system(size: 13, weight: .semibold))
                            .frame(width: 34, height: 30).background(Capsule().fill(Color.white.opacity(0.08)))
                    }
                    .buttonStyle(.plain)
                    Button {
                        toDelete = item
                    } label: {
                        Image(systemName: "trash").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.danger)
                            .frame(width: 34, height: 30).background(Capsule().fill(Color.white.opacity(0.08)))
                    }
                    .buttonStyle(.plain)
                }
                .foregroundStyle(Theme.lightBlue)
                .padding(.top, 2)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Theme.cardFill))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
    }
}
