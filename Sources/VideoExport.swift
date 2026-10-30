import AVFoundation
import UIKit

enum VideoExport {
    /// Draws every frame and writes a silent H.264 .mp4.
    static func writeFrames(renderer: FrameRenderer, frames: Int, fps: Int, width: Int, height: Int, to url: URL,
                            progress: @escaping (Double) -> Void) throws {
        try? FileManager.default.removeItem(at: url)
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let compression: [String: Any] = [
            AVVideoAverageBitRateKey: width * height * 4,
            AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
        ]
        let settings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: compression,
        ]
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        input.expectsMediaDataInRealTime = false
        let attrs: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA),
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height,
        ]
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: attrs)
        guard writer.canAdd(input) else { throw StudioError.message("Could not set up the video writer.") }
        writer.add(input)
        guard writer.startWriting() else {
            throw StudioError.message("Could not start writing video: " + (writer.error?.localizedDescription ?? "unknown error"))
        }
        writer.startSession(atSourceTime: .zero)

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue

        for i in 0..<frames {
            try autoreleasepool {
                while !input.isReadyForMoreMediaData {
                    if writer.status == .failed { break }
                    Thread.sleep(forTimeInterval: 0.002)
                }
                if writer.status == .failed {
                    throw StudioError.message("Video writing failed: " + (writer.error?.localizedDescription ?? "unknown error"))
                }
                guard let pool = adaptor.pixelBufferPool else { throw StudioError.message("No pixel buffer pool.") }
                var out: CVPixelBuffer?
                CVPixelBufferPoolCreatePixelBuffer(nil, pool, &out)
                guard let pb = out else { throw StudioError.message("Could not allocate a video frame.") }
                CVPixelBufferLockBaseAddress(pb, [])
                guard let ctx = CGContext(data: CVPixelBufferGetBaseAddress(pb), width: width, height: height, bitsPerComponent: 8,
                                          bytesPerRow: CVPixelBufferGetBytesPerRow(pb), space: colorSpace, bitmapInfo: bitmapInfo) else {
                    CVPixelBufferUnlockBaseAddress(pb, [])
                    throw StudioError.message("Could not create a drawing surface.")
                }
                renderer.render(frame: i, into: ctx)
                CVPixelBufferUnlockBaseAddress(pb, [])
                adaptor.append(pb, withPresentationTime: CMTime(value: CMTimeValue(i), timescale: CMTimeScale(fps)))
            }
            if i % 8 == 0 { progress(Double(i) / Double(max(frames, 1))) }
        }
        input.markAsFinished()
        let sem = DispatchSemaphore(value: 0)
        writer.finishWriting { sem.signal() }
        sem.wait()
        if writer.status != .completed {
            throw StudioError.message("Video export failed: " + (writer.error?.localizedDescription ?? "unknown error"))
        }
    }

    /// Joins the silent video and the voiceover (.m4a) into the final .mp4.
    static func merge(video: URL, audio: URL, to out: URL) async throws {
        try? FileManager.default.removeItem(at: out)
        let vAsset = AVURLAsset(url: video)
        let aAsset = AVURLAsset(url: audio)
        let vDur = try await vAsset.load(.duration)
        let aDur = try await aAsset.load(.duration)
        let vTracks = try await vAsset.loadTracks(withMediaType: .video)
        let aTracks = try await aAsset.loadTracks(withMediaType: .audio)
        guard let vSrc = vTracks.first, let aSrc = aTracks.first else {
            throw StudioError.message("Could not read the video or audio track.")
        }
        let comp = AVMutableComposition()
        guard let vDst = comp.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid),
              let aDst = comp.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            throw StudioError.message("Could not build the video.")
        }
        try vDst.insertTimeRange(CMTimeRange(start: .zero, duration: vDur), of: vSrc, at: .zero)
        let aLen = CMTimeMinimum(aDur, vDur)
        try aDst.insertTimeRange(CMTimeRange(start: .zero, duration: aLen), of: aSrc, at: .zero)

        guard let ex = AVAssetExportSession(asset: comp, presetName: AVAssetExportPresetPassthrough) else {
            throw StudioError.message("Could not create the video exporter.")
        }
        ex.outputURL = out
        ex.outputFileType = .mp4
        ex.shouldOptimizeForNetworkUse = true
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            ex.exportAsynchronously { c.resume() }
        }
        if ex.status != .completed {
            throw StudioError.message("Could not finish the video: " + (ex.error?.localizedDescription ?? "unknown error"))
        }
    }
}
