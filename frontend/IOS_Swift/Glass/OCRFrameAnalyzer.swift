import AVFoundation
import CoreImage
import Vision

struct OCRFrameAnalysis {
    let textRegion: CGRect?
    let confidence: Float
    let blurScore: Double
    let movementScore: Double
    let timestamp: Date

    var hasText: Bool {
        textRegion != nil
    }
}

final class OCRFrameAnalyzer {
    private let queue = DispatchQueue(label: "glass.ocr.frame-analyzer", qos: .userInitiated)
    private let request = VNDetectTextRectanglesRequest()
    private var previousLumaSample: [Double]?
    private var isAnalyzing = false
    private var lastAnalysisDate: Date = .distantPast
    private let minimumFrameInterval: TimeInterval = 0.16

    init() {
        request.reportCharacterBoxes = false
    }

    func analyze(sampleBuffer: CMSampleBuffer, completion: @escaping (OCRFrameAnalysis) -> Void) {
        let now = Date()
        guard now.timeIntervalSince(lastAnalysisDate) >= minimumFrameInterval else { return }
        guard !isAnalyzing else { return }
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        lastAnalysisDate = now
        isAnalyzing = true

        queue.async { [weak self] in
            guard let self else { return }

            let sample = self.lumaSample(from: pixelBuffer)
            let blurScore = self.blurScore(from: sample)
            let movementScore = self.movementScore(current: sample)
            self.previousLumaSample = sample

            let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .right, options: [:])
            try? handler.perform([self.request])

            let observations = (self.request.results ?? [])
                .filter { $0.confidence >= 0.45 }

            let region = self.mergedBoundingBox(for: observations)
            let confidence = observations.map(\.confidence).max() ?? 0
            let analysis = OCRFrameAnalysis(
                textRegion: region,
                confidence: confidence,
                blurScore: blurScore,
                movementScore: movementScore,
                timestamp: now
            )

            self.isAnalyzing = false
            completion(analysis)
        }
    }

    private func mergedBoundingBox(for observations: [VNTextObservation]) -> CGRect? {
        guard let first = observations.first else { return nil }

        return observations.dropFirst().reduce(first.boundingBox) { partial, observation in
            partial.union(observation.boundingBox)
        }
    }

    private func lumaSample(from pixelBuffer: CVPixelBuffer) -> [Double] {
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        let width: Int
        let height: Int
        let bytesPerRow: Int
        let baseAddress: UnsafeMutableRawPointer?

        if CVPixelBufferIsPlanar(pixelBuffer) {
            width = CVPixelBufferGetWidthOfPlane(pixelBuffer, 0)
            height = CVPixelBufferGetHeightOfPlane(pixelBuffer, 0)
            bytesPerRow = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 0)
            baseAddress = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 0)
        } else {
            width = CVPixelBufferGetWidth(pixelBuffer)
            height = CVPixelBufferGetHeight(pixelBuffer)
            bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
            baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer)
        }

        guard let baseAddress else { return [] }

        let buffer = baseAddress.assumingMemoryBound(to: UInt8.self)
        let columns = 24
        let rows = 32

        var sample: [Double] = []
        sample.reserveCapacity(columns * rows)

        for row in 0..<rows {
            let y = min(height - 1, max(0, row * height / rows))
            for column in 0..<columns {
                let x = min(width - 1, max(0, column * width / columns))
                sample.append(Double(buffer[y * bytesPerRow + x]))
            }
        }

        return sample
    }

    private func blurScore(from sample: [Double]) -> Double {
        guard !sample.isEmpty else { return 0 }

        let columns = 24
        var edgeEnergy = 0.0
        var comparisons = 0.0

        for index in sample.indices {
            if index % columns != columns - 1 {
                edgeEnergy += abs(sample[index] - sample[index + 1])
                comparisons += 1
            }

            let lowerIndex = index + columns
            if lowerIndex < sample.count {
                edgeEnergy += abs(sample[index] - sample[lowerIndex])
                comparisons += 1
            }
        }

        return comparisons == 0 ? 0 : edgeEnergy / comparisons
    }

    private func movementScore(current: [Double]) -> Double {
        guard let previousLumaSample, previousLumaSample.count == current.count else { return 0 }

        let totalDifference = zip(previousLumaSample, current).reduce(0.0) { partial, pair in
            partial + abs(pair.0 - pair.1)
        }

        return totalDifference / Double(current.count)
    }
}
