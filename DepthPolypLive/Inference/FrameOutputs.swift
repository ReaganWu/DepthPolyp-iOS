import SwiftUI

struct FrameOutputs {
    var original: UIImage?
    var overlay: UIImage?
    var mask: UIImage?
    var depth: UIImage?

    static let empty = FrameOutputs()
}

struct PerformanceSample: Identifiable {
    let id = UUID()
    let modelMS: Double
    let pipelineMS: Double
    let modelFPS: Double
    let timestamp: Date
}
