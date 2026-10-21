import CoreImage
import CoreML
import CoreVideo
import SwiftUI

final class ImageRenderers {
    private let context = CIContext(options: [.cacheIntermediates: false])

    func image(from pixelBuffer: CVPixelBuffer) -> UIImage? {
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else { return nil }
        return UIImage(cgImage: cgImage, scale: UIScreen.main.scale, orientation: .up)
    }

    func multiArray(
        from pixelBuffer: CVPixelBuffer,
        width: Int,
        height: Int,
        dataType: MLMultiArrayDataType
    ) -> MLMultiArray? {
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
            .transformed(by: scaleTransform(for: pixelBuffer, targetWidth: width, targetHeight: height))
            .cropped(to: CGRect(x: 0, y: 0, width: width, height: height))

        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else { return nil }
        guard let array = try? MLMultiArray(shape: [1, 3, NSNumber(value: height), NSNumber(value: width)], dataType: dataType) else {
            return nil
        }

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        guard let bitmap = CGContext(
            data: &bytes,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }

        bitmap.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        let channelStride = width * height
        if dataType == .float16 {
            let pointer = array.dataPointer.bindMemory(to: UInt16.self, capacity: channelStride * 3)
            for y in 0..<height {
                for x in 0..<width {
                    let source = (y * width + x) * 4
                    let target = y * width + x
                    pointer[target] = Float16(Float(bytes[source]) / 255.0).bitPattern
                    pointer[channelStride + target] = Float16(Float(bytes[source + 1]) / 255.0).bitPattern
                    pointer[channelStride * 2 + target] = Float16(Float(bytes[source + 2]) / 255.0).bitPattern
                }
            }
        } else {
            let pointer = array.dataPointer.bindMemory(to: Float.self, capacity: channelStride * 3)
            for y in 0..<height {
                for x in 0..<width {
                    let source = (y * width + x) * 4
                    let target = y * width + x
                    pointer[target] = Float(bytes[source]) / 255.0
                    pointer[channelStride + target] = Float(bytes[source + 1]) / 255.0
                    pointer[channelStride * 2 + target] = Float(bytes[source + 2]) / 255.0
                }
            }
        }
        return array
    }

    func overlay(original: UIImage?, mask: MLMultiArray, threshold: Float) -> UIImage? {
        guard let base = original, let maskImage = overlayMaskImage(from: mask, threshold: threshold)?.cgImage else {
            return original
        }

        let size = base.size
        UIGraphicsBeginImageContextWithOptions(size, true, base.scale)
        base.draw(in: CGRect(origin: .zero, size: size))
        UIImage(cgImage: maskImage).draw(in: modelCropRect(for: size), blendMode: .normal, alpha: 1.0)
        let image = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        return image
    }

    func maskImage(from array: MLMultiArray, threshold: Float) -> UIImage? {
        normalizedImage(from: array, normalize: false) { value in
            value >= threshold
                ? (red: UInt8(16), green: UInt8(236), blue: UInt8(151))
                : (red: UInt8(10), green: UInt8(13), blue: UInt8(16))
        }
    }

    func depthImage(from array: MLMultiArray) -> UIImage? {
        normalizedImage(from: array) { value in
            plasmaColor(value)
        }
    }

    private func normalizedImage(
        from array: MLMultiArray,
        normalize: Bool = true,
        color: (Float) -> (red: UInt8, green: UInt8, blue: UInt8)
    ) -> UIImage? {
        let values = flattenedFloats(from: array)
        guard !values.isEmpty else { return nil }
        let side = Int(Double(values.count).squareRoot())
        let width = side > 0 ? side : 224
        let height = max(1, values.count / width)

        let minValue = values.min() ?? 0
        let maxValue = values.max() ?? 1
        let scale = max(maxValue - minValue, 1e-6)
        var pixels = [UInt8](repeating: 255, count: width * height * 4)

        for i in 0..<(width * height) {
            let value = values[min(i, values.count - 1)]
            let normalized = normalize ? (value - minValue) / scale : value
            let c = color(normalized)
            pixels[i * 4] = c.red
            pixels[i * 4 + 1] = c.green
            pixels[i * 4 + 2] = c.blue
            pixels[i * 4 + 3] = 255
        }

        guard let provider = CGDataProvider(data: Data(pixels) as CFData) else { return nil }
        guard let cgImage = CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        ) else {
            return nil
        }
        return UIImage(cgImage: cgImage)
    }

    private func overlayMaskImage(from array: MLMultiArray, threshold: Float) -> UIImage? {
        let values = flattenedFloats(from: array)
        guard !values.isEmpty else { return nil }
        let side = Int(Double(values.count).squareRoot())
        let width = side > 0 ? side : 224
        let height = max(1, values.count / width)

        var pixels = [UInt8](repeating: 0, count: width * height * 4)

        for i in 0..<(width * height) {
            if values[min(i, values.count - 1)] >= threshold {
                pixels[i * 4] = 10
                pixels[i * 4 + 1] = 135
                pixels[i * 4 + 2] = 88
                pixels[i * 4 + 3] = 145
            }
        }

        guard let provider = CGDataProvider(data: Data(pixels) as CFData) else { return nil }
        guard let cgImage = CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        ) else {
            return nil
        }
        return UIImage(cgImage: cgImage)
    }

    private func modelCropRect(for imageSize: CGSize) -> CGRect {
        let side = min(imageSize.width, imageSize.height)
        return CGRect(
            x: (imageSize.width - side) / 2,
            y: (imageSize.height - side) / 2,
            width: side,
            height: side
        )
    }

    private func plasmaColor(_ value: Float) -> (red: UInt8, green: UInt8, blue: UInt8) {
        let stops: [(Float, Float, Float, Float)] = [
            (0.00, 13, 8, 135),
            (0.16, 75, 3, 161),
            (0.32, 125, 3, 168),
            (0.48, 168, 34, 150),
            (0.64, 203, 70, 121),
            (0.80, 229, 107, 93),
            (1.00, 240, 249, 33)
        ]
        let v = max(0, min(1, value))
        for index in 0..<(stops.count - 1) {
            let a = stops[index]
            let b = stops[index + 1]
            if v <= b.0 {
                let t = (v - a.0) / max(b.0 - a.0, 1e-6)
                return (
                    red: UInt8(a.1 + (b.1 - a.1) * t),
                    green: UInt8(a.2 + (b.2 - a.2) * t),
                    blue: UInt8(a.3 + (b.3 - a.3) * t)
                )
            }
        }
        return (red: 240, green: 249, blue: 33)
    }

    private func flattenedFloats(from array: MLMultiArray) -> [Float] {
        let count = array.count
        var values = [Float](repeating: 0, count: count)
        switch array.dataType {
        case .float16:
            let pointer = array.dataPointer.bindMemory(to: UInt16.self, capacity: count)
            for index in 0..<count {
                values[index] = Float(Float16(bitPattern: pointer[index]))
            }
        case .float32:
            let pointer = array.dataPointer.bindMemory(to: Float.self, capacity: count)
            for index in 0..<count {
                values[index] = pointer[index]
            }
        case .double:
            let pointer = array.dataPointer.bindMemory(to: Double.self, capacity: count)
            for index in 0..<count {
                values[index] = Float(pointer[index])
            }
        default:
            for index in 0..<count {
                values[index] = array[index].floatValue
            }
        }
        return values
    }

    private func scaleTransform(for pixelBuffer: CVPixelBuffer, targetWidth: Int, targetHeight: Int) -> CGAffineTransform {
        let sourceWidth = CGFloat(CVPixelBufferGetWidth(pixelBuffer))
        let sourceHeight = CGFloat(CVPixelBufferGetHeight(pixelBuffer))
        let scale = max(CGFloat(targetWidth) / sourceWidth, CGFloat(targetHeight) / sourceHeight)
        let scaledWidth = sourceWidth * scale
        let scaledHeight = sourceHeight * scale
        return CGAffineTransform(translationX: (CGFloat(targetWidth) - scaledWidth) / 2, y: (CGFloat(targetHeight) - scaledHeight) / 2)
            .scaledBy(x: scale, y: scale)
    }
}
