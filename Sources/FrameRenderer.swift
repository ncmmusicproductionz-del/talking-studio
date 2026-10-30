import UIKit

struct SentenceTiming {
    var start: Double
    var end: Double
    var pose: String
    var emotion: String
    var idea: Bool
    var chapter: String?
}

struct CaptionChunk {
    var start: Double
    var end: Double
    var tokens: [Token]
}

struct Backdrop {
    var start: Double
    var end: Double
    var image: UIImage
}

struct LCG {
    var state: UInt64
    init(seed: UInt64) {
        state = seed &* 6364136223846793005 &+ 1442695040888963407
    }
    mutating func next() -> Double {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return Double((state >> 11) & 0x1FFFFFFFFFFFFF) / Double(0x20000000000000)
    }
    mutating func range(_ a: Double, _ b: Double) -> Double {
        return a + (b - a) * next()
    }
}

private func bisectRight(_ a: [Double], _ x: Double) -> Int {
    var lo = 0
    var hi = a.count
    while lo < hi {
        let mid = (lo + hi) / 2
        if x < a[mid] { hi = mid } else { lo = mid + 1 }
    }
    return lo
}

private struct Word {
    let text: String
    let hl: Bool
    let w: CGFloat
}

private struct CardLayout {
    var lines: [[Word]]
    var widths: [CGFloat]
    var width: CGFloat
    var height: CGFloat
    var lineHeight: CGFloat
    var pad: CGFloat
}

/// Draws one video frame: background picture, character, props, chapter banner and captions.
final class FrameRenderer {
    let W: Int
    let H: Int
    let fps: Int
    let wf: CGFloat
    let hf: CGFloat
    let portrait: Bool
    let k: CGFloat
    let cx: CGFloat
    let cy: CGFloat
    let deskY: CGFloat
    let fsz: CGFloat
    let cardW: CGFloat

    let sent: [SentenceTiming]
    let starts: [Double]
    let chunks: [CaptionChunk]
    let cstarts: [Double]
    let env: [Double]
    let blinks: [Double]
    let backdrops: [Backdrop]
    let bstarts: [Double]
    let dim: CGFloat
    let captionsOn: Bool

    private var cardCache: [Int: CardLayout] = [:]
    private lazy var bg: UIImage = buildBackground()

    init(width: Int, height: Int, fps: Int, sentences: [SentenceTiming], chunks: [CaptionChunk], env: [Double],
         blinks: [Double], backdrops: [Backdrop], dim: Double, captions: Bool) {
        self.W = width
        self.H = height
        self.fps = fps
        self.wf = CGFloat(width)
        self.hf = CGFloat(height)
        let isPortrait = height > width
        let kLocal: CGFloat
        let cxLocal: CGFloat
        let cyLocal: CGFloat
        if isPortrait {
            kLocal = CGFloat(width) / CharacterArt.cw
            cxLocal = 0
            cyLocal = CGFloat(height) - CharacterArt.ch * kLocal
        } else {
            kLocal = CGFloat(height) / CharacterArt.ch * 0.93
            cxLocal = CGFloat(width) * 0.70 - CharacterArt.cw * kLocal / 2
            cyLocal = CGFloat(height) - CharacterArt.ch * kLocal
        }
        self.portrait = isPortrait
        self.k = kLocal
        self.cx = cxLocal
        self.cy = cyLocal
        self.deskY = cyLocal + 905 * kLocal
        self.fsz = isPortrait ? CGFloat(width) * 0.072 : CGFloat(height) * 0.068
        self.cardW = isPortrait ? CGFloat(width) * 0.90 : CGFloat(width) * 0.42
        self.sent = sentences
        self.starts = sentences.map { $0.start }
        self.chunks = chunks
        self.cstarts = chunks.map { $0.start }
        self.env = env
        self.blinks = blinks
        self.backdrops = backdrops
        self.bstarts = backdrops.map { $0.start }
        self.dim = CGFloat(dim)
        self.captionsOn = captions
    }

    // MARK: static background

    private func buildBackground() -> UIImage {
        let fmt = UIGraphicsImageRendererFormat()
        fmt.scale = 1
        fmt.opaque = true
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: wf, height: hf), format: fmt)
        return renderer.image { rc in
            let c = rc.cgContext
            let cs = CGColorSpaceCreateDeviceRGB()
            let top = Pal.c(7, 11, 26).cgColor
            let bottom = Pal.c(13, 26, 60).cgColor
            if let grad = CGGradient(colorsSpace: cs, colors: [top, bottom] as CFArray, locations: [0, 1]) {
                c.drawLinearGradient(grad, start: CGPoint(x: 0, y: 0), end: CGPoint(x: 0, y: hf), options: [])
            }
            var rnd = LCG(seed: 3)
            let pen = Pen(c: c)
            if !portrait {
                let x0 = wf * 0.45
                let y0 = hf * 0.09
                let x1 = wf * 0.96
                let y1 = hf * 0.34
                let half = (y1 - y0) / 2
                let shelfColors = [Pal.c(18, 34, 74), Pal.c(22, 40, 88), Pal.c(16, 28, 60), Pal.c(30, 50, 100), Pal.c(20, 30, 52)]
                for row in 0..<2 {
                    let sy = y0 + (y1 - y0) * CGFloat(row + 1) / 2 - 10
                    var x = x0
                    while x < x1 - 40 {
                        let bw = CGFloat(rnd.range(Double(hf) * 0.017, Double(hf) * 0.037))
                        let bh = CGFloat(rnd.range(Double(half) * 0.45, Double(half) - 24))
                        let col = shelfColors[Int(rnd.range(0, Double(shelfColors.count))) % shelfColors.count]
                        pen.rect(CGRect(x: x, y: sy - bh, width: bw, height: bh), fill: col)
                        x += bw + CGFloat(rnd.range(2, 8))
                    }
                    pen.rect(CGRect(x: x0 - 10, y: sy, width: x1 - x0 + 10, height: 10), fill: Pal.c(24, 40, 82))
                }
            }
            let center = CGPoint(x: cx + CharacterArt.cw * k / 2, y: cy + 480 * k)
            let glowCols = [Pal.c(20, 90, 220, 0.34).cgColor, Pal.c(20, 90, 220, 0).cgColor]
            if let glow = CGGradient(colorsSpace: cs, colors: glowCols as CFArray, locations: [0, 1]) {
                c.drawRadialGradient(glow, startCenter: center, startRadius: 0, endCenter: center, endRadius: max(wf, hf) * 0.45, options: [])
            }
            for _ in 0..<14 {
                let r = CGFloat(rnd.range(Double(hf) * 0.012, Double(hf) * 0.04))
                let x = CGFloat(rnd.range(0, Double(wf)))
                let y = CGFloat(rnd.range(0, Double(hf) * 0.6))
                pen.ellipse(CGRect(x: x - r, y: y - r, width: 2 * r, height: 2 * r), fill: Pal.c(24, 70, 160, 0.13))
            }
            let vc = [Pal.c(0, 0, 4, 0).cgColor, Pal.c(0, 0, 4, 0.72).cgColor]
            if let vig = CGGradient(colorsSpace: cs, colors: vc as CFArray, locations: [0.55, 1]) {
                let mid = CGPoint(x: wf / 2, y: hf / 2)
                c.drawRadialGradient(vig, startCenter: mid, startRadius: 0, endCenter: mid, endRadius: hypot(wf, hf) / 2, options: .drawsAfterEndLocation)
            }
        }
    }

    // MARK: picture backdrops

    private func drawBackdropImage(_ bi: Int, _ t: Double, alpha: CGFloat) {
        let b = backdrops[bi]
        let span = max(b.end - b.start, 1.0)
        let prog = CGFloat(min(max((t - b.start) / span, 0), 1))
        let iw = b.image.size.width
        let ih = b.image.size.height
        if iw <= 0 || ih <= 0 { return }
        let s0 = max(wf / iw, hf / ih)
        let z = 1.0 + 0.14 * prog
        let dw = iw * s0 * z
        let dh = ih * s0 * z
        let dir: CGFloat = (bi % 2 == 0) ? 1 : -1
        let maxShift = max(0, dw - wf) / 2
        let ox = (wf - dw) / 2 + dir * maxShift * 0.8 * (2 * prog - 1)
        let oy = (hf - dh) / 2
        b.image.draw(in: CGRect(x: ox, y: oy, width: dw, height: dh), blendMode: .normal, alpha: alpha)
    }

    private func drawBackdrop(_ t: Double, _ ctx: CGContext) {
        if backdrops.isEmpty { return }
        let bi = bisectRight(bstarts, t) - 1
        if bi < 0 { return }
        let b = backdrops[bi]
        if t > b.end + 0.3 { return }
        let local = t - b.start
        var fade: CGFloat = 1
        ctx.saveGState()
        ctx.clip(to: CGRect(x: 0, y: 0, width: wf, height: hf))
        if local < 0.6 {
            let a = ease(CGFloat(local / 0.6))
            if bi > 0 && backdrops[bi - 1].end >= b.start - 0.2 {
                drawBackdropImage(bi - 1, min(t, backdrops[bi - 1].end), alpha: 1)
                drawBackdropImage(bi, t, alpha: a)
            } else {
                fade = a
                drawBackdropImage(bi, t, alpha: a)
            }
        } else {
            drawBackdropImage(bi, t, alpha: 1)
        }
        ctx.setFillColor(Pal.c(6, 12, 34, dim * fade).cgColor)
        ctx.fill(CGRect(x: 0, y: 0, width: wf, height: hf))
        ctx.restoreGState()
    }

    // MARK: animation state

    private func blinkAmount(_ t: Double) -> CGFloat {
        let j = bisectRight(blinks, t) - 1
        if j < 0 { return 0 }
        let d = t - blinks[j]
        if d >= 0 && d < 0.2 { return CGFloat(1 - abs(d - 0.1) / 0.1) }
        return 0
    }

    private func armsAt(_ t: Double, _ si: Int, _ amp: CGFloat) -> (ArmAngles, ArmAngles, Bool) {
        let rest = Poses.rest
        var prev = rest
        if si > 0 { prev = Poses.table[sent[si - 1].pose] ?? rest }
        var cur = rest
        var w: CGFloat = 1
        var name = "rest"
        if si >= 0 {
            name = sent[si].pose
            cur = Poses.table[name] ?? rest
            w = ease(CGFloat((t - sent[si].start) / 0.45))
        }
        var l = ArmAngles(a1: lerpF(prev.l.a1, cur.l.a1, w), a2: lerpF(prev.l.a2, cur.l.a2, w))
        var r = ArmAngles(a1: lerpF(prev.r.a1, cur.r.a1, w), a2: lerpF(prev.r.a2, cur.r.a2, w))
        if name != "rest" && name != "think" {
            let tt = CGFloat(t)
            if ["explain", "open", "celebrate", "present"].contains(name) {
                l.a2 += amp * 12 * sin(tt * 6.3)
                l.a1 += amp * 5 * sin(tt * 4.1)
            }
            r.a2 += amp * 12 * sin(tt * 6.3 + 1.9)
            r.a1 += amp * 5 * sin(tt * 4.1 + 0.8)
        }
        return (l, r, name == "thumbs" && w > 0.5)
    }

    // MARK: text

    private func drawString(_ s: String, x: CGFloat, midY: CGFloat, font: UIFont, color: UIColor) {
        let h = font.lineHeight
        (s as NSString).draw(at: CGPoint(x: x, y: midY - h / 2), withAttributes: [.font: font, .foregroundColor: color])
    }

    private func cardLayout(_ index: Int, _ toks: [Token]) -> CardLayout {
        if let c = cardCache[index] { return c }
        let font = UIFont.systemFont(ofSize: fsz, weight: .heavy)
        let space = (" " as NSString).size(withAttributes: [.font: font]).width
        let pad = fsz * 0.5
        let maxw = cardW - 2 * pad
        var lines: [[Word]] = []
        var widths: [CGFloat] = []
        var cur: [Word] = []
        var curW: CGFloat = 0
        for t in toks {
            let ww = (t.word as NSString).size(withAttributes: [.font: font]).width
            if !cur.isEmpty && curW + space + ww > maxw {
                lines.append(cur)
                widths.append(curW)
                cur = []
                curW = 0
            }
            curW += (cur.isEmpty ? 0 : space) + ww
            cur.append(Word(text: t.word, hl: t.highlight, w: ww))
        }
        lines.append(cur)
        widths.append(curW)
        let lh = fsz * 1.22
        let width = (widths.max() ?? 0) + 2 * pad
        let height = lh * CGFloat(lines.count) + 2 * pad - fsz * 0.1
        let layout = CardLayout(lines: lines, widths: widths, width: width, height: height, lineHeight: lh, pad: pad)
        cardCache[index] = layout
        return layout
    }

    private func drawCard(_ layout: CardLayout, at origin: CGPoint, _ pen: Pen) {
        let font = UIFont.systemFont(ofSize: fsz, weight: .heavy)
        let rect = CGRect(x: origin.x, y: origin.y, width: layout.width, height: layout.height)
        pen.rrect(rect, radius: fsz * 0.42, fill: Pal.c(7, 13, 34, 0.91), stroke: Pal.blue, width: 3)
        let space = (" " as NSString).size(withAttributes: [.font: font]).width
        for (n, line) in layout.lines.enumerated() {
            var x = origin.x + layout.pad
            if portrait { x = origin.x + (layout.width - layout.widths[n]) / 2 }
            let midY = origin.y + layout.pad + layout.lineHeight * CGFloat(n) + layout.lineHeight / 2 - fsz * 0.04
            for w in line {
                drawString(w.text, x: x, midY: midY, font: font, color: w.hl ? Pal.c(80, 175, 255) : UIColor.white)
                x += w.w + space
            }
        }
    }

    private func drawBanner(_ text: String, alpha: CGFloat, _ pen: Pen) {
        let font = UIFont.systemFont(ofSize: fsz * 0.62, weight: .heavy)
        let tw = (text as NSString).size(withAttributes: [.font: font]).width
        let pad = fsz * 0.4
        let bw = tw + pad * 2.4
        let bh = fsz * 0.62 + pad * 1.3
        let x = portrait ? (wf - bw) / 2 : wf * 0.04
        let y = portrait ? hf * 0.045 : hf * 0.06
        let color = Pal.c(10, 140, 255, alpha)
        pen.rrect(CGRect(x: x, y: y, width: bw, height: bh), radius: bh / 2, fill: color)
        drawString(text, x: x + (bw - tw) / 2, midY: y + bh / 2, font: font, color: UIColor.white.withAlphaComponent(alpha))
    }

    private func drawBulb(center: CGPoint, size: CGFloat, _ pen: Pen) {
        let s = size
        for a in stride(from: 0, to: 360, by: 40) {
            let rad = CGFloat(a) * CGFloat.pi / 180
            let p0 = CGPoint(x: center.x + cos(rad) * s * 0.62, y: center.y + sin(rad) * s * 0.59)
            let p1 = CGPoint(x: center.x + cos(rad) * s * 0.84, y: center.y + sin(rad) * s * 0.80)
            pen.line(p0, p1, width: max(3, s * 0.06), color: Pal.c(255, 220, 90))
        }
        pen.ellipse(CGRect(x: center.x - s * 0.42, y: center.y - s * 0.5, width: s * 0.84, height: s * 0.84), fill: Pal.c(255, 214, 72))
        pen.ellipse(CGRect(x: center.x - s * 0.24, y: center.y - s * 0.34, width: s * 0.18, height: s * 0.22), fill: Pal.c(255, 245, 200))
        pen.rrect(CGRect(x: center.x - s * 0.2, y: center.y + s * 0.28, width: s * 0.4, height: s * 0.22), radius: s * 0.06, fill: Pal.c(150, 156, 170))
    }

    // MARK: frame

    func render(frame i: Int, into ctx: CGContext) {
        let t = Double(i) / Double(fps)
        let amp = CGFloat(i < env.count ? env[i] : 0)
        let si = bisectRight(starts, t) - 1

        ctx.saveGState()
        ctx.translateBy(x: 0, y: hf)
        ctx.scaleBy(x: 1, y: -1)
        UIGraphicsPushContext(ctx)
        defer {
            UIGraphicsPopContext()
            ctx.restoreGState()
        }
        let pen = Pen(c: ctx)

        bg.draw(in: CGRect(x: 0, y: 0, width: wf, height: hf))
        drawBackdrop(t, ctx)

        // character state
        let arms = armsAt(t, si, amp)
        var state = CharState()
        state.armL = arms.0
        state.armR = arms.1
        state.thumb = arms.2
        let idle = CGFloat(sin(t * 1.9))
        state.bodyDY = idle * 3 + amp * 5
        let emotionName = si >= 0 ? sent[si].emotion : "normal"
        state.eye = Emotions.table[emotionName] ?? Emotions.normal
        state.openMul = (0.92 + 0.30 * amp) * (1 - 0.92 * blinkAmount(t))
        state.headDY = -amp * 13 + idle * 4 + (amp > 0.5 ? amp * 6 : 0)
        let tt = CGFloat(t)
        state.tilt = 2.4 * sin(tt * 1.1) + amp * 3.2 * sin(tt * 5.3)
        state.glow = 0.25 + 0.75 * amp
        state.look = 2.5 * sin(tt * 0.7)

        ctx.saveGState()
        ctx.translateBy(x: cx, y: cy)
        ctx.scaleBy(x: k, y: k)
        CharacterArt.drawBody(pen, state)
        ctx.restoreGState()

        pen.rect(CGRect(x: 0, y: deskY, width: wf, height: hf - deskY), fill: Pal.desk)
        pen.rect(CGRect(x: 0, y: deskY, width: wf, height: max(3, 5 * k)), fill: Pal.blueD)

        ctx.saveGState()
        ctx.translateBy(x: cx, y: cy)
        ctx.scaleBy(x: k, y: k)
        CharacterArt.drawLaptop(pen)
        CharacterArt.drawHead(pen, state)
        ctx.restoreGState()

        // props and chapter banner
        if si >= 0 {
            let s = sent[si]
            let local = t - s.start
            if s.idea && local >= 0 && local < 1.9 {
                var sc = popCurve(CGFloat(local / 0.35))
                if local >= 1.6 { sc *= CGFloat((1.9 - local) / 0.3) }
                let size = 150 * k * max(sc, 0.05)
                let c = CGPoint(x: cx + 800 * k, y: cy + 140 * k + 6 * sin(tt * 5))
                drawBulb(center: c, size: size, pen)
            }
            if s.emotion == "think" && local >= 0 {
                let alpha = ease(CGFloat(local / 0.3))
                let font = UIFont.systemFont(ofSize: 150 * k, weight: .heavy)
                let color = Pal.c(70, 170, 255, alpha)
                let mark = "?" as NSString
                let sz = mark.size(withAttributes: [.font: font])
                mark.draw(at: CGPoint(x: cx + 805 * k - sz.width / 2, y: cy + 210 * k + 8 * sin(tt * 3) - sz.height / 2),
                          withAttributes: [.font: font, .foregroundColor: color])
            }
            if let chapter = s.chapter, !chapter.isEmpty, local >= 0 && local < 3.4 {
                let f = min(ease(CGFloat(local / 0.35)), ease(CGFloat((3.4 - local) / 0.35)))
                drawBanner(chapter, alpha: f, pen)
            }
        }

        // captions
        if captionsOn && !chunks.isEmpty {
            let ci = bisectRight(cstarts, t) - 1
            if ci >= 0 {
                let ch = chunks[ci]
                if t < ch.end + 0.25 {
                    let layout = cardLayout(ci, ch.tokens)
                    let slide = (1 - ease(CGFloat((t - ch.start) / 0.14))) * 18
                    var origin: CGPoint
                    if portrait {
                        origin = CGPoint(x: (wf - layout.width) / 2, y: cy * 0.60 - layout.height / 2 + slide)
                    } else {
                        origin = CGPoint(x: wf * 0.04, y: hf * 0.52 - layout.height / 2 + slide)
                    }
                    drawCard(layout, at: origin, pen)
                }
            }
        }
    }
}
