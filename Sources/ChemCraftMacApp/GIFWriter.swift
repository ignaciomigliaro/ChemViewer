import Foundation
import ImageIO
import UniformTypeIdentifiers

/// ImageIO quantizes each full frame; independent local palettes and disposal-to-background
/// prevent stale atoms from accumulating when transparent frames are played.
actor GIFWriter {
    private let stream: FileHandle
    private let expectedCount: Int
    private var count = 0
    private var dimensions: (Int, Int)?
    private var closed = false
    init(url: URL, count: Int) throws {
        guard FileManager.default.createFile(atPath: url.path, contents: nil) else { throw AnimationExportError.message("Cannot create GIF file.") }
        stream = try FileHandle(forWritingTo: url); expectedCount = count
    }
    deinit { try? stream.close() }
    private func word(_ n: Int) -> [UInt8] { [UInt8(n & 255), UInt8((n >> 8) & 255)] }

    /// GIF uses binary alpha. Retain white atoms; threshold coverage rather than color-keying white.
    private func binaryAlpha(_ image: CGImage) throws -> CGImage {
        let w = image.width, h = image.height
        var pixels = [UInt8](repeating: 0, count: w * h * 4)
        let drawn = pixels.withUnsafeMutableBytes { raw -> Bool in
            guard let context = CGContext(data: raw.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        guard drawn else { throw AnimationExportError.message("Cannot prepare GIF transparency.") }
        for i in stride(from: 0, to: pixels.count, by: 4) {
            let alpha = Int(pixels[i + 3])
            if alpha < 128 { pixels[i] = 0; pixels[i + 1] = 0; pixels[i + 2] = 0; pixels[i + 3] = 0 }
            else {
                if alpha < 255 { for c in 0..<3 { pixels[i + c] = UInt8(clamping: (Int(pixels[i + c]) * 255 + alpha / 2) / alpha) } }
                pixels[i + 3] = 255
            }
        }
        let data = Data(pixels)
        guard let provider = CGDataProvider(data: data as CFData), let result = CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: w * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue), provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent) else { throw AnimationExportError.message("Cannot prepare GIF pixels.") }
        return result
    }
    func append(_ source: CGImage, delay: Double) throws {
        guard !closed, count < expectedCount, delay.isFinite && delay > 0 else { throw AnimationExportError.message("Invalid GIF frame or closed encoder.") }
        let image = try binaryAlpha(source)
        if let dimensions, dimensions != (image.width, image.height) { throw AnimationExportError.message("GIF frame dimensions changed.") }
        dimensions = (image.width, image.height)
        let buffer = NSMutableData()
        guard let encoder = CGImageDestinationCreateWithData(buffer, UTType.gif.identifier as CFString, 1, nil) else { throw AnimationExportError.message("Cannot encode GIF frame.") }
        CGImageDestinationAddImage(encoder, image, nil)
        guard CGImageDestinationFinalize(encoder) else { throw AnimationExportError.message("GIF palette conversion failed.") }
        let bytes = [UInt8](buffer as Data)
        guard bytes.count >= 13 else { throw AnimationExportError.message("Invalid encoded GIF frame.") }
        var cursor = 13
        var palette: [UInt8] = [], paletteBits = Int(bytes[10] & 7)
        if bytes[10] & 0x80 != 0 {
            let size = 3 * (1 << (paletteBits + 1))
            guard cursor + size <= bytes.count else { throw AnimationExportError.message("Invalid GIF palette.") }
            palette = Array(bytes[cursor..<cursor + size]); cursor += size
        }
        var transparent: UInt8?
        func skipBlocks() throws {
            while cursor < bytes.count {
                let size = Int(bytes[cursor]); cursor += 1
                if size == 0 { return }
                guard cursor + size <= bytes.count else { throw AnimationExportError.message("Truncated GIF data.") }
                cursor += size
            }
            throw AnimationExportError.message("Unterminated GIF data.")
        }
        while cursor < bytes.count, bytes[cursor] == 0x21 {
            guard cursor + 2 < bytes.count else { throw AnimationExportError.message("Truncated GIF extension.") }
            if bytes[cursor + 1] == 0xF9, cursor + 7 < bytes.count, bytes[cursor + 2] == 4, bytes[cursor + 3] & 1 != 0 { transparent = bytes[cursor + 6] }
            cursor += 2; try skipBlocks()
        }
        guard cursor + 10 < bytes.count, bytes[cursor] == 0x2C else { throw AnimationExportError.message("GIF frame image is missing.") }
        var descriptor = Array(bytes[cursor..<cursor + 10]); cursor += 10
        if descriptor[9] & 0x80 != 0 {
            paletteBits = Int(descriptor[9] & 7)
            let size = 3 * (1 << (paletteBits + 1))
            guard cursor + size <= bytes.count else { throw AnimationExportError.message("Invalid local GIF palette.") }
            palette = Array(bytes[cursor..<cursor + size]); cursor += size
        }
        guard !palette.isEmpty else { throw AnimationExportError.message("GIF frame has no palette.") }
        let imageDataStart = cursor
        cursor += 1 // LZW minimum code size, followed by subblocks.
        try skipBlocks()
        if count == 0 {
            var header = Array("GIF89a".utf8) + word(image.width) + word(image.height)
            header += [UInt8(0xF0 | paletteBits), transparent ?? 0, 0]
            try stream.write(contentsOf: Data(header + palette))
            try stream.write(contentsOf: Data([0x21, 0xFF, 11] + Array("NETSCAPE2.0".utf8) + [3, 1, 0, 0, 0]))
        }
        let ticks = min(65535, max(1, Int((delay * 100).rounded())))
        // Disposal 2 clears each independently encoded image before the next one.
        var control: [UInt8] = [0x21, 0xF9, 4, transparent == nil ? 8 : 9]
        control += word(ticks); control += [transparent ?? 0, 0]
        descriptor[9] = (descriptor[9] & 0x78) | 0x80 | UInt8(paletteBits)
        try stream.write(contentsOf: Data(control + descriptor + palette + Array(bytes[imageDataStart..<cursor])))
        count += 1
    }
    func finish() throws {
        guard !closed, count == expectedCount else { throw AnimationExportError.message("GIF export has missing frames.") }
        try stream.write(contentsOf: Data([0x3B])); try stream.close(); closed = true
    }
}
