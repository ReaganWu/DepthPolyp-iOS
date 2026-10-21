import CoreImage
import CoreML
import CoreVideo
import SwiftUI

final class DepthPolypPipeline: ObservableObject {
    @Published private(set) var outputs = FrameOutputs.empty
    @Published private(set) var performanceHistory: [PerformanceSample] = []
    @Published private(set) var statusText = "Loading Core ML model"
    @Published private(set) var currentFPS: Double = 0
    @Published private(set) var currentLatencyMS: Double = 0
    @Published private(set) var currentPipelineMS: Double = 0

    private let queue = DispatchQueue(label: "depthpolyp.coreml.pipeline", qos: .userInitiated)
    private let renderer = ImageRenderers()
    private var model: MLModel?
    private var inputDataType: MLMultiArrayDataType = .float32
    private let processingLock = NSLock()
    private var isProcessing = false
    private let inputSize = 224
    private let threshold: Float = 0.30

    init() {
        queue.async { [weak self] in
            self?.loadModel()
        }
    }

    func enqueue(_ pixelBuffer: CVPixelBuffer) {
        processingLock.lock()
        guard !isProcessing else {
            processingLock.unlock()
            return
        }
        isProcessing = true
        processingLock.unlock()

        queue.async { [weak self] in
            guard let self else { return }
            let started = CACurrentMediaTime()
            let result = self.process(pixelBuffer)
            let pipelineMS = (CACurrentMediaTime() - started) * 1000
            let modelMS = result.modelMS
            let fps = modelMS > 0 ? 1000 / modelMS : 0

            Task { @MainActor in
                self.outputs = result.outputs
                self.currentLatencyMS = modelMS
                self.currentPipelineMS = pipelineMS
                self.currentFPS = fps
                if result.status != "Model unavailable" {
                    self.statusText = result.status
                }
                if modelMS > 0 {
                    self.performanceHistory.append(
                        PerformanceSample(modelMS: modelMS, pipelineMS: pipelineMS, modelFPS: fps, timestamp: Date())
                    )
                }
                if self.performanceHistory.count > 36 {
                    self.performanceHistory.removeFirst(self.performanceHistory.count - 36)
                }
                self.finishProcessing()
            }
        }
    }

    private func finishProcessing() {
        processingLock.lock()
        isProcessing = false
        processingLock.unlock()
    }

    private func loadModel() {
        do {
            let config = MLModelConfiguration()
            config.computeUnits = .cpuAndNeuralEngine

            guard let url = Bundle.main.url(
                forResource: "DepthPolyp_Kvasir_coreml_fp16",
                withExtension: "mlmodelc"
            ) else {
                Task { @MainActor in
                    self.statusText = "Model missing from app bundle"
                }
                return
            }

            model = try MLModel(contentsOf: url, configuration: config)
            inputDataType = model?.modelDescription.inputDescriptionsByName["image"]?
                .multiArrayConstraint?.dataType ?? .float32
            Task { @MainActor in
                self.statusText = "Dense FP16 Core ML on CPU+ANE"
            }
        } catch {
            Task { @MainActor in
                self.statusText = "Model load failed: \(error.localizedDescription)"
            }
        }
    }

    private func process(_ pixelBuffer: CVPixelBuffer) -> (outputs: FrameOutputs, status: String, modelMS: Double) {
        let original = renderer.image(from: pixelBuffer)
        guard let input = renderer.multiArray(
            from: pixelBuffer,
            width: inputSize,
            height: inputSize,
            dataType: inputDataType
        ) else {
            return (FrameOutputs(original: original, overlay: original, mask: nil, depth: nil), "Frame conversion failed", 0)
        }

        guard let model else {
            return (FrameOutputs(original: original), "Model unavailable", 0)
        }

        do {
            let provider = try MLDictionaryFeatureProvider(dictionary: ["image": MLFeatureValue(multiArray: input)])
            let modelStarted = CACurrentMediaTime()
            let prediction = try model.prediction(from: provider)
            let modelMS = (CACurrentMediaTime() - modelStarted) * 1000
            guard
                let segmentation = prediction.featureValue(for: "segmentation")?.multiArrayValue,
                let depth = prediction.featureValue(for: "depth")?.multiArrayValue
            else {
                return (FrameOutputs(original: original), "Missing model outputs", 0)
            }

            return (
                FrameOutputs(
                    original: original,
                    overlay: renderer.overlay(original: original, mask: segmentation, threshold: threshold),
                    mask: renderer.maskImage(from: segmentation, threshold: threshold),
                    depth: renderer.depthImage(from: depth)
                ),
                "Dense FP16 Core ML on CPU+ANE",
                modelMS
            )
        } catch {
            return (FrameOutputs(original: original), "Inference failed: \(error.localizedDescription)", 0)
        }
    }
}
