import SwiftUI

struct ContentView: View {
    @StateObject private var provider = CameraFrameProvider()
    @StateObject private var pipeline = DepthPolypPipeline()

    private let columns = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10)
    ]

    var body: some View {
        VStack(spacing: 10) {
            header

            LazyVGrid(columns: columns, spacing: 10) {
                TileView(title: "Original", image: pipeline.outputs.original)
                TileView(title: "Overlay", image: pipeline.outputs.overlay)
                TileView(title: "Segmentation Mask", image: pipeline.outputs.mask)
                TileView(title: "Depth Estimation", image: pipeline.outputs.depth)
            }
            .padding(.horizontal, 12)

            PerformancePanel(samples: pipeline.performanceHistory)
                .frame(height: 132)
                .padding(.horizontal, 12)
                .padding(.bottom, 10)
        }
        .background(Color(red: 0.055, green: 0.06, blue: 0.065))
        .task {
            await provider.requestAccessAndStart()
        }
        .onReceive(provider.$latestFrame.compactMap { $0 }) { frame in
            pipeline.enqueue(frame)
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("DepthPolyp Live")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.white)
                Text(pipeline.statusText)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.64))
                    .lineLimit(1)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(String(format: "%.1f model FPS", pipeline.currentFPS))
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(Color(red: 0.34, green: 0.95, blue: 0.65))
                Text(String(format: "model %.1f ms / pipeline %.1f ms", pipeline.currentLatencyMS, pipeline.currentPipelineMS))
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.72))
            }
            .monospacedDigit()
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
    }
}
