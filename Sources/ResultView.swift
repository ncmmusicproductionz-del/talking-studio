import AVKit
import SwiftUI
import UIKit

/// Shown when a video is finished.
struct ResultView: View {
    @EnvironmentObject var model: StudioModel
    @Environment(\.dismiss) private var dismiss
    @State private var player: AVPlayer? = nil
    @State private var copied = false

    var body: some View {
        ZStack {
            AppBackground()
            if let res = model.result {
                ScrollView {
                    VStack(spacing: 18) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Your video is ready")
                                    .font(.system(size: 26, weight: .heavy, design: .rounded))
                                Text("\(formatClock(res.seconds)) long \u{00B7} saved in My Videos")
                                    .font(.subheadline)
                                    .foregroundStyle(Theme.secondary)
                            }
                            Spacer()
                            Button {
                                dismiss()
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 15, weight: .bold))
                                    .foregroundStyle(Color.white)
                                    .frame(width: 36, height: 36)
                                    .background(Circle().fill(Color.white.opacity(0.1)))
                            }
                            .buttonStyle(.plain)
                        }

                        if let p = player {
                            VideoPlayer(player: p)
                                .aspectRatio(model.landscape ? 16.0 / 9.0 : 9.0 / 16.0, contentMode: .fit)
                                .frame(maxHeight: 460)
                                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                                .shadow(color: Theme.blue.opacity(0.35), radius: 18, x: 0, y: 8)
                        }

                        HStack(spacing: 12) {
                            ShareLink(item: res.videoURL) {
                                Label("Share", systemImage: "square.and.arrow.up")
                            }
                            .buttonStyle(SecondaryButtonStyle())
                            Button {
                                model.saveToPhotos(res.videoURL)
                            } label: {
                                Label("Save to Photos", systemImage: "photo.badge.plus")
                            }
                            .buttonStyle(PrimaryButtonStyle())
                        }

                        if !res.credits.isEmpty {
                            CardSection(icon: "quote.bubble", title: "Picture credits", subtitle: "Paste these into your video description") {
                                Text(res.credits.joined(separator: "\n"))
                                    .font(.caption)
                                    .foregroundStyle(Theme.secondary)
                                    .textSelection(.enabled)
                                Button {
                                    UIPasteboard.general.string = res.credits.joined(separator: "\n")
                                    copied = true
                                    Haptics.success()
                                } label: {
                                    Label(copied ? "Copied" : "Copy credits", systemImage: copied ? "checkmark" : "doc.on.doc")
                                }
                                .buttonStyle(SecondaryButtonStyle())
                            }
                        }

                        if !res.warnings.isEmpty {
                            CardSection(icon: "exclamationmark.triangle", title: "Notes") {
                                ForEach(res.warnings, id: \.self) { w in
                                    Text(w).font(.caption).foregroundStyle(Color.orange)
                                }
                            }
                        }
                    }
                    .padding(20)
                }
            }
        }
        .onAppear {
            if let r = model.result {
                let p = AVPlayer(url: r.videoURL)
                player = p
                p.play()
            }
        }
        .onDisappear { player?.pause() }
    }
}
