import UIKit

/// Renders the character as a picture for the app's header, empty screens and progress screen.
enum Mascot {
    static func bust(size: CGSize, emotion: String = "normal", blink: Bool = false, glow: CGFloat = 0.55) -> UIImage {
        let fmt = UIGraphicsImageRendererFormat()
        fmt.scale = 3
        fmt.opaque = false
        return UIGraphicsImageRenderer(size: size, format: fmt).image { r in
            let c = r.cgContext
            let region = CGRect(x: 175, y: 45, width: 650, height: 700)
            let s = min(size.width / region.width, size.height / region.height)
            c.translateBy(x: (size.width - region.width * s) / 2 - region.minX * s,
                          y: (size.height - region.height * s) / 2 - region.minY * s)
            c.scaleBy(x: s, y: s)
            c.clip(to: region)
            var st = CharState()
            st.eye = Emotions.table[emotion] ?? Emotions.normal
            st.openMul = blink ? 0.08 : 1
            st.glow = glow
            let pen = Pen(c: c)
            CharacterArt.drawBody(pen, st)
            CharacterArt.drawHead(pen, st)
        }
    }

    static let avatar: UIImage = Mascot.bust(size: CGSize(width: 84, height: 84))
    static let emptyState: UIImage = Mascot.bust(size: CGSize(width: 200, height: 200), emotion: "happy")
}
