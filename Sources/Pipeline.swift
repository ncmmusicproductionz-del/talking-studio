import AVFoundation
import UIKit

struct StudioOptions {
    var script: String
    var voiceID: String?
    var speed: Double
    var ownAudio: URL?
    var landscape: Bool
    var highQuality: Bool
    var captions: Bool
    var pictures: Bool
    var strictLicenses: Bool
    var dim: Double
    var previewSeconds: Double?
}

struct StudioResult {
    var videoURL: URL
    var creditsURL: URL?
    var credits: [String]
    var warnings: [String]
    var seconds: Double
}

enum Pipeline {
    static let fps = 24

    static func outputFolder() throws -> URL {
        let docs = try FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let dir = docs.appendingPathComponent("TalkingStudio", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func chunks(for sentences: [Sentence], portrait: Bool) -> [CaptionChunk] {
        let maxWords = portrait ? 6 : 9
        var out: [CaptionChunk] = []
        for s in sentences {
            let parts = ScriptParser.splitCaptionChunks(s.tokens, maxWords: maxWords)
            var lens: [Double] = []
            for p in parts {
                var n = 0
                for t in p { n += t.word.count + 1 }
                lens.append(Double(max(n, 1)))
            }
            let total = lens.reduce(0, +)
            let span = max(s.end - s.start, 0.3)
            var acc = 0.0
            for (p, ln) in zip(parts, lens) {
                let a = s.start + span * acc / total
                acc += ln
                let b = s.start + span * acc / total
                out.append(CaptionChunk(start: a, end: b, tokens: p))
            }
        }
        return out
    }

    /// Picks and downloads one picture per scene. Returns backdrops, credit lines and warnings.
    static func pickBackdrops(_ sentences: [Sentence], strict: Bool) async -> ([Backdrop], [String], [String]) {
        let scenes = ImageSearch.groupScenes(sentences)
        var warnings: [String] = []

        let picks: [Candidate?] = await withTaskGroup(of: (Int, Candidate?).self, returning: [Candidate?].self) { group in
            for (i, sc) in scenes.enumerated() {
                if sc.skip || sc.query.isEmpty { continue }
                group.addTask {
                    let res = await ImageSearch.search(query: sc.query, strict: strict, limit: 4)
                    return (i, res.first)
                }
            }
            var arr = [Candidate?](repeating: nil, count: scenes.count)
            for await (i, c) in group { arr[i] = c }
            return arr
        }

        var unique: [String: Candidate] = [:]
        for c in picks {
            if let c = c { unique[c.id] = c }
        }
        let downloaded: [String: UIImage] = await withTaskGroup(of: (String, UIImage?, String?).self, returning: [String: UIImage].self) { group in
            for (_, c) in unique {
                group.addTask {
                    do {
                        let img = try await ImageSearch.fetchImage(c)
                        return (c.id, img, nil)
                    } catch {
                        return (c.id, nil, "Could not download \"\(c.title)\": \(error.localizedDescription)")
                    }
                }
            }
            var dict: [String: UIImage] = [:]
            var errs: [String] = []
            for await (id, img, err) in group {
                if let img = img { dict[id] = img }
                if let err = err { errs.append(err) }
            }
            warnings.append(contentsOf: errs)
            return dict
        }

        var backdrops: [Backdrop] = []
        var used: [String: Candidate] = [:]
        var usedOrder: [String] = []
        var prev: Candidate? = nil
        for (sc, pick) in zip(scenes, picks) {
            var chosen: Candidate? = nil
            if let p = pick, downloaded[p.id] != nil {
                chosen = p
                prev = p
            } else if !sc.skip {
                chosen = prev
            }
            if let c = chosen, let img = downloaded[c.id] {
                if used[c.id] == nil {
                    used[c.id] = c
                    usedOrder.append(c.id)
                }
                backdrops.append(Backdrop(start: sentences[sc.idx[0]].start, end: sentences[sc.idx[sc.idx.count - 1]].end, image: img))
            }
        }
        let credits = usedOrder.compactMap { used[$0] }.map { ImageSearch.creditLine($0) }
        if backdrops.isEmpty && !scenes.isEmpty {
            warnings.append("No pictures were found, so the studio background was used.")
        }
        return (backdrops, credits, warnings)
    }

    static func run(_ o: StudioOptions, progress: @escaping (String, Double) -> Void) async throws -> StudioResult {
        progress("Reading the script", 0.0)
        var sentences = ScriptParser.parse(o.script)
        if sentences.isEmpty { throw StudioError.message("The script is empty. Paste some narration first.") }

        let work = FileManager.default.temporaryDirectory.appendingPathComponent("ts-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: work) }

        // voice
        let voiceM4A = work.appendingPathComponent("voice.m4a")
        if let own = o.ownAudio {
            progress("Preparing your recording", 0.03)
            try await AudioTools.toM4A(own, voiceM4A)
        } else {
            progress("Making the voiceover", 0.03)
            let caf = work.appendingPathComponent("voice.caf")
            try await SpeechSynth().synthesize(text: ScriptParser.spokenText(sentences), voiceID: o.voiceID, speedPercent: o.speed, to: caf)
            progress("Preparing the audio", 0.08)
            try await AudioTools.toM4A(caf, voiceM4A)
        }

        progress("Listening to the audio", 0.1)
        let analysis = try AudioAnalyzer.analyze(url: voiceM4A, fps: fps)
        Aligner.align(&sentences, norm: analysis.norm, hop: analysis.hop, duration: analysis.duration)

        // pictures
        var backdrops: [Backdrop] = []
        var credits: [String] = []
        var warnings: [String] = []
        if o.pictures {
            progress("Finding free pictures", 0.14)
            let r = await pickBackdrops(sentences, strict: o.strictLicenses)
            backdrops = r.0
            credits = r.1
            warnings = r.2
        }

        // frames
        let width: Int
        let height: Int
        if o.landscape {
            width = o.highQuality ? 1920 : 1280
            height = o.highQuality ? 1080 : 720
        } else {
            width = o.highQuality ? 1080 : 720
            height = o.highQuality ? 1920 : 1280
        }
        var total = analysis.duration + 0.5
        if let p = o.previewSeconds { total = min(total, p) }
        let frames = max(1, Int(total * Double(fps)))

        var timings: [SentenceTiming] = []
        for s in sentences {
            timings.append(SentenceTiming(start: s.start, end: s.end, pose: s.pose ?? "rest", emotion: s.emotion ?? "normal",
                                          idea: s.idea, chapter: s.chapter))
        }
        var rnd = LCG(seed: 7)
        var blinks: [Double] = []
        var bt = 1.2
        while bt < total + 1 {
            blinks.append(bt)
            bt += rnd.range(2.2, 4.8)
        }
        let renderer = FrameRenderer(width: width, height: height, fps: fps, sentences: timings,
                                     chunks: chunks(for: sentences, portrait: height > width), env: analysis.env, blinks: blinks,
                                     backdrops: backdrops, dim: o.dim, captions: o.captions)

        let silent = work.appendingPathComponent("silent.mp4")
        try VideoExport.writeFrames(renderer: renderer, frames: frames, fps: fps, width: width, height: height, to: silent) { f in
            progress("Animating the character", 0.18 + 0.72 * f)
        }

        progress("Adding the voice", 0.93)
        let stamp = DateFormatter()
        stamp.dateFormat = "yyyyMMdd-HHmmss"
        let name = (o.previewSeconds != nil ? "Preview-" : "Talking-") + stamp.string(from: Date())
        let folder = try outputFolder()
        let finalURL = folder.appendingPathComponent(name + ".mp4")
        try await VideoExport.merge(video: silent, audio: voiceM4A, to: finalURL)

        var creditsURL: URL? = nil
        if !credits.isEmpty {
            let cu = folder.appendingPathComponent(name + "-image-credits.txt")
            let text = "Images used in this video (paste into your video description):\n\n" + credits.joined(separator: "\n") + "\n"
            try? text.write(to: cu, atomically: true, encoding: .utf8)
            creditsURL = cu
        }
        progress("Done", 1.0)
        return StudioResult(videoURL: finalURL, creditsURL: creditsURL, credits: credits, warnings: warnings, seconds: total)
    }
}
