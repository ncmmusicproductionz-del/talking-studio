import AVFoundation
import Foundation

enum StudioError: LocalizedError {
    case message(String)
    case cancelled
    var errorDescription: String? {
        switch self {
        case .message(let m): return m
        case .cancelled: return "Cancelled"
        }
    }
}

/// Makes the voiceover with the voices built into iOS and writes it to an audio file.
final class SpeechSynth {
    private let synth = AVSpeechSynthesizer()

    static func englishVoices() -> [AVSpeechSynthesisVoice] {
        let all = AVSpeechSynthesisVoice.speechVoices().filter { $0.language.hasPrefix("en") }
        return all.sorted { a, b in
            if a.quality.rawValue != b.quality.rawValue { return a.quality.rawValue > b.quality.rawValue }
            return a.name < b.name
        }
    }

    func synthesize(text: String, voiceID: String?, speedPercent: Double, to url: URL) async throws {
        try? FileManager.default.removeItem(at: url)
        let utt = AVSpeechUtterance(string: text)
        if let id = voiceID, let v = AVSpeechSynthesisVoice(identifier: id) {
            utt.voice = v
        } else {
            utt.voice = AVSpeechSynthesisVoice(language: "en-US")
        }
        let base = Double(AVSpeechUtteranceDefaultSpeechRate)
        var rate = Float(base * (1.0 + speedPercent / 100.0))
        rate = min(max(rate, AVSpeechUtteranceMinimumSpeechRate), AVSpeechUtteranceMaximumSpeechRate)
        utt.rate = rate

        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            var file: AVAudioFile? = nil
            var finished = false
            self.synth.write(utt) { buffer in
                guard let pcm = buffer as? AVAudioPCMBuffer else { return }
                if pcm.frameLength == 0 {
                    if !finished {
                        finished = true
                        file = nil
                        cont.resume()
                    }
                    return
                }
                do {
                    if file == nil {
                        file = try AVAudioFile(forWriting: url, settings: pcm.format.settings)
                    }
                    try file?.write(from: pcm)
                } catch {
                    if !finished {
                        finished = true
                        file = nil
                        cont.resume(throwing: error)
                    }
                }
            }
        }
    }
}

enum AudioTools {
    /// Converts any audio file to AAC (.m4a), which the video export needs.
    static func toM4A(_ src: URL, _ dst: URL) async throws {
        try? FileManager.default.removeItem(at: dst)
        let asset = AVURLAsset(url: src)
        guard let ex = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else {
            throw StudioError.message("This audio file can't be converted.")
        }
        ex.outputURL = dst
        ex.outputFileType = .m4a
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            ex.exportAsynchronously { c.resume() }
        }
        if ex.status != .completed {
            throw StudioError.message("Audio conversion failed: " + (ex.error?.localizedDescription ?? "unknown error"))
        }
    }
}

struct AudioAnalysis {
    var duration: Double
    var env: [Double]
    var norm: [Double]
    var hop: Double
}

enum AudioAnalyzer {
    static func analyze(url: URL, fps: Int) throws -> AudioAnalysis {
        let file = try AVAudioFile(forReading: url)
        let format = file.processingFormat
        let frames = AVAudioFrameCount(file.length)
        guard frames > 0, let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames) else {
            throw StudioError.message("The audio is empty.")
        }
        try file.read(into: buf)
        guard let channels = buf.floatChannelData else {
            throw StudioError.message("Unsupported audio format.")
        }
        let data = channels[0]
        let n = Int(buf.frameLength)
        let sr = format.sampleRate
        let duration = Double(n) / sr
        let hopN = max(1, Int(sr * 0.02))
        let hop = Double(hopN) / sr

        var rms: [Double] = []
        var i = 0
        while i + hopN <= n {
            var sum: Float = 0
            var j = i
            let stop = i + hopN
            while j < stop {
                let v = data[j]
                sum += v * v
                j += 1
            }
            rms.append(Double((sum / Float(hopN)).squareRoot()))
            i += hopN
        }
        if rms.isEmpty { throw StudioError.message("The audio is too short.") }

        let sorted = rms.sorted()
        let ref = max(sorted[min(sorted.count - 1, Int(Double(sorted.count) * 0.95))], 0.0001)
        let norm = rms.map { min(1.0, $0 / ref) }

        let nframes = Int(duration * Double(fps)) + 1
        var env: [Double] = []
        var s = 0.0
        for f in 0..<nframes {
            let a = Int(Double(f) / Double(fps) / hop)
            let b = max(a + 1, Int(Double(f + 1) / Double(fps) / hop))
            var raw = 0.0
            var k = a
            while k < b && k < norm.count {
                raw = max(raw, norm[k])
                k += 1
            }
            if raw <= 0.06 { raw = 0 }
            s = s + (raw - s) * (raw > s ? 0.65 : 0.25)
            env.append(s)
        }
        return AudioAnalysis(duration: duration, env: env, norm: norm, hop: hop)
    }
}

enum Aligner {
    static func silences(_ norm: [Double], hop: Double, thresh: Double = 0.04, minLen: Double = 0.16) -> [(Double, Double)] {
        var out: [(Double, Double)] = []
        var start: Int? = nil
        for (i, v) in norm.enumerated() {
            if v < thresh {
                if start == nil { start = i }
            } else {
                if let s = start, Double(i - s) * hop >= minLen {
                    out.append((Double(s) * hop, Double(i) * hop))
                }
                start = nil
            }
        }
        if let s = start, Double(norm.count - s) * hop >= minLen {
            out.append((Double(s) * hop, Double(norm.count) * hop))
        }
        return out
    }

    /// Gives every sentence a start and end time by splitting the speech in proportion to text length,
    /// then snapping each boundary to the nearest pause in the audio.
    static func align(_ sentences: inout [Sentence], norm: [Double], hop: Double, duration: Double) {
        let n = sentences.count
        if n == 0 { return }
        let sil = silences(norm, hop: hop)
        var first = 0.0
        var last = duration
        if let f = sil.first, f.0 < 0.05 { first = f.1 }
        if let l = sil.last, l.1 > duration - 0.05 { last = l.0 }
        if last <= first { first = 0; last = duration }
        let inner = sil.filter { $0.0 > first + 0.2 && $0.1 < last - 0.2 }

        var weights: [Double] = []
        for s in sentences { weights.append(Double(max(s.spoken.count, 4))) }
        let total = weights.reduce(0, +)
        var bounds: [Double] = []
        var cum = 0.0
        for w in weights.dropLast() {
            cum += w
            bounds.append(first + (last - first) * cum / total)
        }

        var used = Set<Int>()
        var snapped: [Double] = []
        var prev = first
        for b in bounds {
            var best: Int? = nil
            var bestScore = 0.0
            for (idx, s) in inner.enumerated() {
                if used.contains(idx) { continue }
                let c = (s.0 + s.1) / 2
                let dist = abs(c - b)
                if dist > 1.6 || c <= prev + 0.3 { continue }
                let score = dist - min(s.1 - s.0, 1.0) * 0.6
                if best == nil || score < bestScore {
                    best = idx
                    bestScore = score
                }
            }
            if let bi = best {
                used.insert(bi)
                let c = (inner[bi].0 + inner[bi].1) / 2
                snapped.append(c)
                prev = c
            } else {
                let v = max(b, prev + 0.3)
                snapped.append(v)
                prev = v
            }
        }
        let edges = [first] + snapped + [last]
        for i in 0..<n {
            sentences[i].start = edges[i]
            sentences[i].end = edges[i + 1]
        }
    }
}
