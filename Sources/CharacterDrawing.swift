import UIKit

// MARK: - helpers

func P(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
    return CGPoint(x: x, y: y)
}

func ease(_ x: CGFloat) -> CGFloat {
    let v = min(max(x, 0), 1)
    return v * v * (3 - 2 * v)
}

func popCurve(_ x: CGFloat) -> CGFloat {
    let v = min(max(x, 0), 1)
    let a = v - 1
    return 1 + 2.70158 * a * a * a + 1.70158 * a * a
}

func lerpF(_ a: CGFloat, _ b: CGFloat, _ w: CGFloat) -> CGFloat {
    return a + (b - a) * w
}

enum Pal {
    static func c(_ r: Int, _ g: Int, _ b: Int, _ a: CGFloat = 1) -> UIColor {
        return UIColor(red: CGFloat(r) / 255, green: CGFloat(g) / 255, blue: CGFloat(b) / 255, alpha: a)
    }
    static let blue = Pal.c(10, 140, 255)
    static let blueD = Pal.c(8, 70, 150)
    static let black = Pal.c(8, 9, 14)
    static let cap = Pal.c(22, 24, 33)
    static let capL = Pal.c(36, 39, 53)
    static let hoodie = Pal.c(50, 52, 66)
    static let hoodieD = Pal.c(33, 35, 47)
    static let band = Pal.c(26, 28, 38)
    static let white = Pal.c(250, 252, 255)
    static let glow1 = Pal.c(34, 56, 104)
    static let glow2 = Pal.c(96, 132, 196)
    static let desk = Pal.c(26, 21, 31)
    static let cup = Pal.c(24, 26, 36)
    static let string = Pal.c(205, 210, 222)
    static let lid = Pal.c(36, 38, 52)
    static let slab = Pal.c(26, 28, 38)
}

// MARK: - drawing pen

struct Pen {
    let c: CGContext

    func poly(_ pts: [CGPoint], fill: UIColor) {
        guard let f = pts.first else { return }
        c.setFillColor(fill.cgColor)
        c.beginPath()
        c.move(to: f)
        for p in pts.dropFirst() { c.addLine(to: p) }
        c.closePath()
        c.fillPath()
    }

    func ellipse(_ r: CGRect, fill: UIColor?, stroke: UIColor? = nil, width: CGFloat = 0) {
        if let f = fill {
            c.setFillColor(f.cgColor)
            c.fillEllipse(in: r)
        }
        if let s = stroke, width > 0 {
            c.setStrokeColor(s.cgColor)
            c.setLineWidth(width)
            c.strokeEllipse(in: r)
        }
    }

    func rrect(_ r: CGRect, radius: CGFloat, fill: UIColor?, stroke: UIColor? = nil, width: CGFloat = 0) {
        let path = UIBezierPath(roundedRect: r, cornerRadius: radius)
        if let f = fill {
            c.setFillColor(f.cgColor)
            c.addPath(path.cgPath)
            c.fillPath()
        }
        if let s = stroke, width > 0 {
            c.setStrokeColor(s.cgColor)
            c.setLineWidth(width)
            c.addPath(path.cgPath)
            c.strokePath()
        }
    }

    func rect(_ r: CGRect, fill: UIColor) {
        c.setFillColor(fill.cgColor)
        c.fill(r)
    }

    func line(_ a: CGPoint, _ b: CGPoint, width: CGFloat, color: UIColor) {
        c.setStrokeColor(color.cgColor)
        c.setLineWidth(width)
        c.setLineCap(.round)
        c.beginPath()
        c.move(to: a)
        c.addLine(to: b)
        c.strokePath()
    }

    /// Points along an elliptical arc. Angles are in degrees, clockwise from 3 o'clock (y axis points down).
    static func arcPoints(_ box: CGRect, _ a0: CGFloat, _ a1: CGFloat) -> [CGPoint] {
        var end = a1
        if end < a0 { end += 360 }
        let cx = box.midX
        let cy = box.midY
        let rx = box.width / 2
        let ry = box.height / 2
        let steps = max(8, Int((end - a0) / 6))
        var pts: [CGPoint] = []
        for i in 0...steps {
            let deg = a0 + (end - a0) * CGFloat(i) / CGFloat(steps)
            let t = deg * CGFloat.pi / 180
            pts.append(CGPoint(x: cx + rx * cos(t), y: cy + ry * sin(t)))
        }
        return pts
    }

    func arc(_ box: CGRect, _ a0: CGFloat, _ a1: CGFloat, width: CGFloat, color: UIColor) {
        let pts = Pen.arcPoints(box, a0, a1)
        c.setStrokeColor(color.cgColor)
        c.setLineWidth(width)
        c.setLineCap(.round)
        c.setLineJoin(.round)
        c.beginPath()
        c.move(to: pts[0])
        for p in pts.dropFirst() { c.addLine(to: p) }
        c.strokePath()
    }

    func chord(_ box: CGRect, _ a0: CGFloat, _ a1: CGFloat, fill: UIColor) {
        poly(Pen.arcPoints(box, a0, a1), fill: fill)
    }
}

// MARK: - poses and eyes

struct ArmAngles {
    var a1: CGFloat
    var a2: CGFloat
}

struct PoseDef {
    var l: ArmAngles
    var r: ArmAngles
}

enum Poses {
    static let table: [String: PoseDef] = [
        "rest": PoseDef(l: ArmAngles(a1: 10, a2: 6), r: ArmAngles(a1: 10, a2: 6)),
        "explain": PoseDef(l: ArmAngles(a1: 28, a2: 105), r: ArmAngles(a1: 28, a2: 105)),
        "open": PoseDef(l: ArmAngles(a1: 40, a2: 85), r: ArmAngles(a1: 40, a2: 85)),
        "point": PoseDef(l: ArmAngles(a1: 14, a2: 8), r: ArmAngles(a1: 46, a2: 125)),
        "think": PoseDef(l: ArmAngles(a1: 14, a2: 8), r: ArmAngles(a1: -22, a2: -140)),
        "celebrate": PoseDef(l: ArmAngles(a1: 52, a2: 160), r: ArmAngles(a1: 52, a2: 160)),
        "thumbs": PoseDef(l: ArmAngles(a1: 14, a2: 8), r: ArmAngles(a1: 30, a2: 150)),
        "wave": PoseDef(l: ArmAngles(a1: 14, a2: 8), r: ArmAngles(a1: 36, a2: 160)),
        "present": PoseDef(l: ArmAngles(a1: 38, a2: 90), r: ArmAngles(a1: 20, a2: 8)),
    ]
    static let rest = PoseDef(l: ArmAngles(a1: 10, a2: 6), r: ArmAngles(a1: 10, a2: 6))
}

struct EyeLook {
    var kind: String
    var open: CGFloat
    var tilt: CGFloat
    var look: CGFloat
    var rightOpen: CGFloat? = nil
}

enum Emotions {
    static let table: [String: EyeLook] = [
        "normal": EyeLook(kind: "angular", open: 1.0, tilt: 0, look: 0),
        "happy": EyeLook(kind: "happy", open: 1.0, tilt: 0, look: 0),
        "excited": EyeLook(kind: "wide", open: 1.0, tilt: 0, look: 0),
        "surprised": EyeLook(kind: "wide", open: 1.15, tilt: 0, look: 0),
        "angry": EyeLook(kind: "angular", open: 0.9, tilt: 16, look: 0),
        "think": EyeLook(kind: "angular", open: 1.0, tilt: -8, look: -6, rightOpen: 0.62),
        "tired": EyeLook(kind: "angular", open: 0.5, tilt: -6, look: 0),
        "focused": EyeLook(kind: "angular", open: 0.72, tilt: 6, look: 0),
        "sad": EyeLook(kind: "angular", open: 0.85, tilt: -18, look: 0),
        "wink": EyeLook(kind: "wink", open: 1.0, tilt: 0, look: 0),
    ]
    static let normal = EyeLook(kind: "angular", open: 1.0, tilt: 0, look: 0)
}

struct CharState {
    var armL = ArmAngles(a1: 10, a2: 6)
    var armR = ArmAngles(a1: 10, a2: 6)
    var thumb = false
    var bodyDY: CGFloat = 0
    var headDY: CGFloat = 0
    var tilt: CGFloat = 0
    var glow: CGFloat = 0.3
    var eye = Emotions.normal
    var openMul: CGFloat = 1
    var look: CGFloat = 0
}

// MARK: - the character

enum CharacterArt {
    static let cw: CGFloat = 1000
    static let ch: CGFloat = 1100
    static let pivot = CGPoint(x: 500, y: 540)
    static let upper: CGFloat = 170
    static let fore: CGFloat = 150

    static func armPoints(left: Bool, _ a: ArmAngles) -> (CGPoint, CGPoint, CGPoint) {
        let sx: CGFloat = left ? 305 : 695
        let dr: CGFloat = left ? -1 : 1
        let sy: CGFloat = 600
        let r1 = a.a1 * CGFloat.pi / 180
        let r2 = a.a2 * CGFloat.pi / 180
        let ex = sx + dr * sin(r1) * upper
        let ey = sy + cos(r1) * upper
        let hx = ex + dr * sin(r2) * fore
        let hy = ey + cos(r2) * fore
        return (P(sx, sy), P(ex, ey), P(hx, hy))
    }

    /// Hood, torso and arms. Drawn in character units (1000 x 1100).
    static func drawBody(_ pen: Pen, _ s: CharState) {
        let c = pen.c
        c.saveGState()
        c.translateBy(x: 0, y: s.bodyDY)
        pen.ellipse(CGRect(x: 250, y: 280, width: 500, height: 380), fill: Pal.hoodieD)
        pen.poly([P(262, 575), P(738, 575), P(812, 1100), P(188, 1100)], fill: Pal.hoodie)
        pen.ellipse(CGRect(x: 218, y: 526, width: 148, height: 148), fill: Pal.hoodie)
        pen.ellipse(CGRect(x: 634, y: 526, width: 148, height: 148), fill: Pal.hoodie)
        pen.line(P(226, 600), P(188, 1100), width: 6, color: Pal.blueD)
        pen.line(P(774, 600), P(812, 1100), width: 6, color: Pal.blue)
        pen.arc(CGRect(x: 218, y: 526, width: 148, height: 148), 180, 270, width: 6, color: Pal.blueD)
        pen.arc(CGRect(x: 634, y: 526, width: 148, height: 148), 270, 360, width: 6, color: Pal.blue)
        pen.line(P(470, 575), P(462, 700), width: 6, color: Pal.string)
        pen.line(P(530, 575), P(538, 700), width: 6, color: Pal.string)
        pen.ellipse(CGRect(x: 454, y: 692, width: 16, height: 24), fill: Pal.string)
        pen.ellipse(CGRect(x: 530, y: 692, width: 16, height: 24), fill: Pal.string)

        let left = armPoints(left: true, s.armL)
        let right = armPoints(left: false, s.armR)
        let arms = [left, right]
        let passes: [(CGFloat, UIColor)] = [(84, Pal.hoodieD), (72, Pal.hoodie)]
        for (width, col) in passes {
            for a in arms {
                pen.line(a.0, a.1, width: width, color: col)
                pen.line(a.1, a.2, width: width, color: col)
            }
        }
        for (idx, a) in arms.enumerated() {
            let h = a.2
            pen.ellipse(CGRect(x: h.x - 44, y: h.y - 44, width: 88, height: 88), fill: Pal.black, stroke: Pal.blueD, width: 4)
            if s.thumb && idx == 1 {
                pen.rrect(CGRect(x: h.x - 15, y: h.y - 84, width: 30, height: 58), radius: 15, fill: Pal.black, stroke: Pal.blueD, width: 4)
            }
        }
        c.restoreGState()
    }

    static func drawLaptop(_ pen: Pen) {
        pen.rrect(CGRect(x: 285, y: 670, width: 430, height: 260), radius: 26, fill: Pal.lid, stroke: Pal.blueD, width: 6)
        pen.rect(CGRect(x: 295, y: 926, width: 410, height: 24), fill: Pal.slab)
        pen.rrect(CGRect(x: 438, y: 755, width: 124, height: 90), radius: 22, fill: Pal.blue)
        pen.poly([P(486, 779), P(486, 821), P(523, 800)], fill: UIColor.white)
    }

    static func eyePoly(cx: CGFloat, cy: CGFloat, side: CGFloat, open: CGFloat, tilt: CGFloat, scale: CGFloat) -> [CGPoint] {
        let base: [(CGFloat, CGFloat)] = [(-46, -30), (38, -6), (30, 30), (-36, 22)]
        let tiltDeg: CGFloat = side < 0 ? tilt : -tilt
        let ang = tiltDeg * CGFloat.pi / 180
        let ca = cos(ang)
        let sa = sin(ang)
        var out: [CGPoint] = []
        for b in base {
            var x = b.0
            var y = b.1 * max(open, 0.07)
            if side > 0 { x = -x }
            x *= scale
            y *= scale
            out.append(P(cx + x * ca - y * sa, cy + x * sa + y * ca))
        }
        return out
    }

    /// Head, cap, headphones and eyes. Tilts and nods around the neck.
    static func drawHead(_ pen: Pen, _ s: CharState) {
        let c = pen.c
        let dy = s.headDY
        func box(_ x0: CGFloat, _ y0: CGFloat, _ x1: CGFloat, _ y1: CGFloat) -> CGRect {
            return CGRect(x: x0, y: y0 + dy, width: x1 - x0, height: y1 - y0)
        }
        c.saveGState()
        c.translateBy(x: 0, y: s.bodyDY)
        c.translateBy(x: pivot.x, y: pivot.y)
        c.scaleBy(x: 1.12, y: 1.12)
        c.rotate(by: -(s.tilt * CGFloat.pi / 180))
        c.translateBy(x: -pivot.x, y: -pivot.y)

        pen.ellipse(box(268, 190, 732, 590), fill: Pal.hoodie)
        pen.ellipse(box(322, 225, 678, 545), fill: Pal.black)
        pen.arc(box(322, 225, 678, 545), 300, 60, width: 7, color: Pal.blue)

        pen.chord(box(310, 120, 690, 440), 180, 360, fill: Pal.cap)
        pen.ellipse(box(488, 112, 512, 132), fill: Pal.capL)
        pen.ellipse(box(288, 262, 712, 338), fill: Pal.capL)
        pen.arc(box(288, 262, 712, 338), 10, 170, width: 5, color: Pal.blueD)

        pen.arc(box(272, 52, 728, 480), 180, 360, width: 32, color: Pal.band)
        pen.arc(box(284, 64, 716, 468), 195, 345, width: 5, color: Pal.blue)
        let glow = min(max(s.glow, 0), 1)
        let ring = UIColor(red: (10 + 60 * glow) / 255, green: (120 + 80 * glow) / 255, blue: 1, alpha: 1)
        for cxCup in [CGFloat(290), CGFloat(710)] {
            pen.ellipse(box(cxCup - 50, 322, cxCup + 50, 472), fill: Pal.cup, stroke: Pal.blue, width: 9)
            let r = 24 + 6 * glow
            pen.ellipse(box(cxCup - r, 397 - r, cxCup + r, 397 + r), fill: ring)
        }

        let e = s.eye
        let lookX = e.look + s.look
        for side in [CGFloat(-1), CGFloat(1)] {
            let ex: CGFloat = (side < 0 ? 430 : 570) + lookX
            let ey: CGFloat = 388 + dy
            var o = max(0.05, e.open * s.openMul)
            if side > 0, let ro = e.rightOpen {
                o = max(0.05, ro * s.openMul)
            }
            if e.kind == "happy" || (e.kind == "wink" && side > 0) {
                pen.arc(CGRect(x: ex - 44, y: ey - 36, width: 88, height: 72), 200, 340, width: 15, color: Pal.white)
                continue
            }
            if e.kind == "wide" {
                let rx: CGFloat = 40
                let ry: CGFloat = 50 * o
                let rings: [(CGFloat, UIColor)] = [(1.38, Pal.glow1), (1.18, Pal.glow2), (1.0, Pal.white)]
                for (kk, col) in rings {
                    pen.ellipse(CGRect(x: ex - rx * kk, y: ey - ry * kk, width: 2 * rx * kk, height: 2 * ry * kk), fill: col)
                }
                continue
            }
            let rings: [(CGFloat, UIColor)] = [(1.36, Pal.glow1), (1.17, Pal.glow2), (1.0, Pal.white)]
            for (kk, col) in rings {
                pen.poly(eyePoly(cx: ex, cy: ey, side: side, open: o, tilt: e.tilt, scale: kk), fill: col)
            }
        }
        c.restoreGState()
    }
}
