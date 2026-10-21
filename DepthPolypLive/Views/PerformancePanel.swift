import SwiftUI

struct PerformancePanel: View {
    let samples: [PerformanceSample]

    private var latest: PerformanceSample? {
        samples.last
    }

    private var averageFPS: Double {
        guard !samples.isEmpty else { return 0 }
        return averageModelMS > 0 ? 1000 / averageModelMS : 0
    }

    private var averageModelMS: Double {
        guard !samples.isEmpty else { return 0 }
        return samples.map(\.modelMS).reduce(0, +) / Double(samples.count)
    }

    private var averagePipelineMS: Double {
        guard !samples.isEmpty else { return 0 }
        return samples.map(\.pipelineMS).reduce(0, +) / Double(samples.count)
    }

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                MetricCell(label: "Model", value: String(format: "%.1f FPS", latest?.modelFPS ?? 0))
                MetricCell(label: "Mean", value: String(format: "%.1f FPS", averageFPS))
                MetricCell(label: "Model", value: String(format: "%.1f ms", averageModelMS))
                MetricCell(label: "Pipeline", value: String(format: "%.1f ms", averagePipelineMS))
            }

            GeometryReader { proxy in
                HStack(alignment: .bottom, spacing: 3) {
                    ForEach(samples) { sample in
                        Capsule()
                            .fill(barColor(for: sample.modelFPS))
                            .frame(
                                width: max(4, (proxy.size.width - 105) / CGFloat(max(samples.count, 1))),
                                height: max(8, min(proxy.size.height, CGFloat(sample.modelFPS / 120.0) * proxy.size.height))
                            )
                    }
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                .overlay(alignment: .topLeading) {
                    Text("Model FPS history")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.58))
                }
            }
        }
        .padding(10)
        .background(Color(red: 0.085, green: 0.095, blue: 0.105))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(.white.opacity(0.10), lineWidth: 1)
        )
    }

    private func barColor(for fps: Double) -> Color {
        if fps >= 30 { return Color(red: 0.27, green: 0.93, blue: 0.58) }
        if fps >= 18 { return Color(red: 1.00, green: 0.74, blue: 0.28) }
        return Color(red: 1.00, green: 0.36, blue: 0.34)
    }
}

private struct MetricCell: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.54))
            Text(value)
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .monospacedDigit()
                .minimumScaleFactor(0.75)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
