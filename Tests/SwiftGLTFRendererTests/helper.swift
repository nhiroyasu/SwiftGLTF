import Foundation
import MetalKit
import UniformTypeIdentifiers
import Testing

func isCI() -> Bool {
    return ProcessInfo.processInfo.environment["CI"] == "true"
}

// Convert MTLTexture to CGImage
func cgImage(from texture: MTLTexture) -> CGImage? {
    let width = texture.width
    let height = texture.height
    let bytesPerPixel = 4
    let bytesPerRow = bytesPerPixel * width
    let count = bytesPerRow * height
    var raw = [UInt8](repeating: 0, count: count)
    let region = MTLRegionMake2D(0, 0, width, height)
    texture.getBytes(&raw, bytesPerRow: bytesPerRow, from: region, mipmapLevel: 0)
    let cfdata = CFDataCreate(nil, raw, count)!
    let provider = CGDataProvider(data: cfdata)!
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
    return CGImage(
        width: width,
        height: height,
        bitsPerComponent: 8,
        bitsPerPixel: 32,
        bytesPerRow: bytesPerRow,
        space: colorSpace,
        bitmapInfo: bitmapInfo,
        provider: provider,
        decode: nil,
        shouldInterpolate: false,
        intent: .defaultIntent
    )
}

func loadCGImage(from url: URL) -> CGImage? {
    guard let data = try? Data(contentsOf: url),
          let source = CGImageSourceCreateWithData(data as CFData, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
        return nil
    }
    return image
}

// Export texture as PNG to given URL
func export(texture: MTLTexture, name: String) throws {
    guard let image = cgImage(from: texture) else {
        throw NSError(domain: "RenderTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to convert texture to CGImage"])
    }
    let url = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!.appendingPathComponent(name)
    let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, image, nil)
    if !CGImageDestinationFinalize(dest) {
        throw NSError(domain: "RenderTests", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to finalize image destination"])
    }
    print("Exported texture to \(url.path)") // <- Copy this file to Resources/expected_{name}.png
}

func assertEqual(output: MTLTexture, goldenName: String) {
    let tolerance: UInt8 = 3

    var outputBytes = [UInt8](repeating: 0, count: output.width * output.height * 4)
    output.getBytes(&outputBytes, bytesPerRow: output.width * 4, from: MTLRegionMake2D(0, 0, output.width, output.height), mipmapLevel: 0)

    let goldenURL = Bundle.module.url(forResource: goldenName, withExtension: "png")!
    let data = try! Data(contentsOf: goldenURL)
    let source = CGImageSourceCreateWithData(data as CFData, nil)!
    let image = CGImageSourceCreateImageAtIndex(source, 0, nil)!

    let goldenWidth = image.width
    let goldenHeight = image.height
    let goldenContext = CGContext(
        data: nil,
        width: goldenWidth,
        height: goldenHeight,
        bitsPerComponent: 8,
        bytesPerRow: goldenWidth * 4,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    goldenContext.draw(image, in: CGRect(x: 0, y: 0, width: goldenWidth, height: goldenHeight))
    let goldenRaw = goldenContext.data!.assumingMemoryBound(to: UInt8.self)

    let byteCount = goldenWidth * goldenHeight * 4

    #expect(output.width == goldenWidth)
    #expect(output.height == goldenHeight)

    var mismatchCount = 0
    for i in 0..<byteCount {
        let diff = abs(Int(outputBytes[i]) - Int(goldenRaw[i]))
        if diff > tolerance {
            mismatchCount += 1
        }
    }
    let maxAllowedMismatchedPixels = Int(Double(byteCount) * 0.01) // 1% tolerance

    #expect(
        mismatchCount <= maxAllowedMismatchedPixels,
        "Output differs from golden image \(goldenName).png with \(mismatchCount) mismatched bytes (tolerance=\(tolerance))"
    )
}
