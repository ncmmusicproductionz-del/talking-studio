import SwiftUI

// MARK: - Cards

struct CardSection<Content: View>: View {
    let icon: String
    let title: String
    var subtitle: String? = nil
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.blue.opacity(0.20))
                    Image(systemName: icon)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.lightBlue)
                }
                .frame(width: 34, height: 34)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.system(.headline, design: .rounded))
                    if let s = subtitle {
                        Text(s).font(.caption).foregroundStyle(Theme.secondary)
                    }
                }
                Spacer(minLength: 0)
            }
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Theme.cardFill)
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .strokeBorder(LinearGradient(colors: [Color.white.opacity(0.16), Color.white.opacity(0.03)],
                                                     startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1)
                )
        )
    }
}

// MARK: - Buttons

struct PrimaryButtonStyle: ButtonStyle {
    var enabled: Bool = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(.headline, design: .rounded))
            .foregroundStyle(Color.white.opacity(enabled ? 1 : 0.5))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(enabled ? AnyShapeStyle(Theme.accentGradient) : AnyShapeStyle(Color.white.opacity(0.10)))
            )
            .shadow(color: enabled ? Theme.blue.opacity(0.40) : Color.clear, radius: 14, x: 0, y: 6)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(.headline, design: .rounded))
            .foregroundStyle(Color.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.white.opacity(0.09))
                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.white.opacity(0.16), lineWidth: 1))
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct ChipButton: View {
    let title: String
    let icon: String
    let action: () -> Void

    var body: some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: icon).font(.system(size: 12, weight: .semibold))
                Text(title).font(.system(size: 13, weight: .semibold, design: .rounded))
            }
            .foregroundStyle(Theme.lightBlue)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Capsule().fill(Theme.blue.opacity(0.16)))
            .overlay(Capsule().strokeBorder(Theme.blue.opacity(0.28), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Segmented control

struct SegmentOption<Value: Hashable>: Identifiable {
    let value: Value
    let title: String
    let icon: String
    var id: String { title }
}

struct SegmentedTabs<Value: Hashable>: View {
    let options: [SegmentOption<Value>]
    @Binding var selection: Value
    @Namespace private var ns

    var body: some View {
        HStack(spacing: 4) {
            ForEach(options) { opt in
                Button {
                    Haptics.select()
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { selection = opt.value }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: opt.icon).font(.system(size: 12, weight: .semibold))
                        Text(opt.title).font(.system(size: 13, weight: .semibold, design: .rounded)).lineLimit(1).minimumScaleFactor(0.75)
                    }
                    .foregroundStyle(selection == opt.value ? Color.white : Theme.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background {
                        if selection == opt.value {
                            Capsule().fill(Theme.accentGradient).matchedGeometryEffect(id: "pill", in: ns)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(Capsule().fill(Color.white.opacity(0.07)))
    }
}

// MARK: - Callouts

struct Callout: View {
    let icon: String
    let title: String
    let message: String
    var tint: Color = Theme.blue
    var buttonTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.system(.subheadline, design: .rounded).weight(.bold))
                Text(message).font(.footnote).foregroundStyle(Theme.secondary).fixedSize(horizontal: false, vertical: true)
                if let b = buttonTitle, let a = action {
                    Button(action: a) {
                        Text(b).font(.system(size: 13, weight: .bold, design: .rounded))
                            .padding(.horizontal, 14).padding(.vertical, 7)
                            .background(Capsule().fill(tint))
                            .foregroundStyle(Color.white)
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 2)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(tint.opacity(0.12)))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(tint.opacity(0.28), lineWidth: 1))
    }
}

// MARK: - Voice and format tiles

struct VoiceCard: View {
    let voice: AIVoice
    let selected: Bool
    let loading: Bool
    let playing: Bool
    let enabled: Bool
    let onSelect: () -> Void
    let onPlay: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(voice.flag).font(.title3)
                Spacer()
                Button(action: onPlay) {
                    ZStack {
                        Circle().fill(selected ? Color.white.opacity(0.24) : Theme.blue.opacity(0.24))
                        if loading {
                            ProgressView().scaleEffect(0.6).tint(Color.white)
                        } else {
                            Image(systemName: playing ? "stop.fill" : "play.fill")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(Color.white)
                        }
                    }
                    .frame(width: 30, height: 30)
                }
                .buttonStyle(.plain)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(voice.name).font(.system(.headline, design: .rounded))
                Text(voice.blurb)
                    .font(.caption2)
                    .foregroundStyle(selected ? Color.white.opacity(0.9) : Theme.secondary)
                    .lineLimit(1)
            }
            Text(voice.accent + (voice.female ? "  Female" : "  Male"))
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(selected ? Color.white.opacity(0.85) : Theme.tertiary)
        }
        .padding(12)
        .frame(width: 148, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(selected ? AnyShapeStyle(Theme.accentGradient) : AnyShapeStyle(Color.white.opacity(0.07)))
        )
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Color.white.opacity(selected ? 0.35 : 0.10), lineWidth: 1))
        .opacity(enabled ? 1 : 0.55)
        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .onTapGesture(perform: onSelect)
    }
}

struct FormatTile: View {
    let title: String
    let subtitle: String
    let aspect: CGFloat
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button {
            Haptics.select()
            action()
        } label: {
            VStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(selected ? Color.white : Theme.secondary, lineWidth: 2)
                        .frame(width: aspect >= 1 ? 54 : 54 * aspect, height: aspect >= 1 ? 54 / aspect : 54)
                    Image(systemName: "play.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(selected ? Color.white : Theme.secondary)
                }
                .frame(height: 60)
                VStack(spacing: 2) {
                    Text(title).font(.system(.subheadline, design: .rounded).weight(.bold))
                    Text(subtitle).font(.caption2).foregroundStyle(selected ? Color.white.opacity(0.85) : Theme.tertiary)
                }
            }
            .foregroundStyle(Color.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(selected ? AnyShapeStyle(Theme.accentGradient) : AnyShapeStyle(Color.white.opacity(0.07)))
            )
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Color.white.opacity(selected ? 0.35 : 0.10), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}
