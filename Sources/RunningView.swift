import SwiftUI

/// Full-screen progress while a video is being made.
struct RunningView: View {
    @EnvironmentObject var model: StudioModel
    private let openImage = Mascot.bust(size: CGSize(width: 200, height: 200), glow: 0.8)
    private let blinkImage = Mascot.bust(size: CGSize(width: 200, height: 200), blink: true, glow: 0.8)

    private let stages: [(String, String, Double, Double)] = [
        ("Voiceover", "waveform", 0.0, 0.10),
        ("Timing", "metronome", 0.10, 0.14),
        ("Pictures", "photo", 0.14, 0.18),
        ("Animating", "figure.wave", 0.18, 0.93),
        ("Finishing", "film", 0.93, 1.01),
    ]

    var body: some View {
        ZStack {
            AppBackground()
            VStack(spacing: 26) {
                Spacer(minLength: 10)
                ZStack {
                    Circle()
                        .stroke(Color.white.opacity(0.08), lineWidth: 10)
                    Circle()
                        .trim(from: 0, to: CGFloat(max(0.02, model.progress)))
                        .stroke(Theme.accentGradient, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .animation(.easeOut(duration: 0.4), value: model.progress)
                    Circle()
                        .fill(RadialGradient(colors: [Theme.blue.opacity(0.35), Color.clear], center: .center, startRadius: 10, endRadius: 120))
                        .padding(14)
                    TimelineView(.animation) { ctx in
                        let t = ctx.date.timeIntervalSinceReferenceDate
                        let blinking = Int(t * 10) % 37 == 0
                        Image(uiImage: blinking ? blinkImage : openImage)
                            .resizable()
                            .scaledToFit()
                            .padding(34)
                            .offset(y: CGFloat(sin(t * 2.2)) * 4)
                    }
                }
                .frame(width: 270, height: 270)

                VStack(spacing: 6) {
                    Text("\(Int(model.progress * 100))%")
                        .font(.system(size: 46, weight: .heavy, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(Color.white)
                    Text(model.message)
                        .font(.headline)
                        .foregroundStyle(Theme.secondary)
                        .multilineTextAlignment(.center)
                }

                VStack(spacing: 10) {
                    ForEach(stages.indices, id: \.self) { i in
                        stageRow(stages[i])
                    }
                }
                .padding(16)
                .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Theme.cardFill))

                Spacer(minLength: 10)

                Button {
                    Haptics.tap()
                    model.cancel()
                } label: {
                    Text("Cancel")
                }
                .buttonStyle(SecondaryButtonStyle())
                Text("Keep Talking Studio open and the screen on while it works.")
                    .font(.footnote)
                    .foregroundStyle(Theme.tertiary)
                    .multilineTextAlignment(.center)
            }
            .padding(24)
        }
        .interactiveDismissDisabled(true)
    }

    private func stageRow(_ s: (String, String, Double, Double)) -> some View {
        let done = model.progress >= s.3
        let active = model.progress >= s.2 && model.progress < s.3
        return HStack(spacing: 12) {
            ZStack {
                Circle().fill(done ? Theme.good.opacity(0.22) : (active ? Theme.blue.opacity(0.25) : Color.white.opacity(0.06)))
                if done {
                    Image(systemName: "checkmark").font(.system(size: 12, weight: .bold)).foregroundStyle(Theme.good)
                } else if active {
                    ProgressView().scaleEffect(0.6).tint(Theme.lightBlue)
                } else {
                    Image(systemName: s.1).font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.tertiary)
                }
            }
            .frame(width: 28, height: 28)
            Text(s.0)
                .font(.system(.subheadline, design: .rounded).weight(active ? .bold : .medium))
                .foregroundStyle(done || active ? Color.white : Theme.tertiary)
            Spacer()
        }
    }
}
