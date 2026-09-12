import AppKit
import CoreGraphics

nonisolated struct RGB: Equatable, Sendable {
    var red: Double
    var green: Double
    var blue: Double

    static let neutral = RGB(red: 0.85, green: 0.85, blue: 0.88)
}

nonisolated enum Artwork {
    static func load(source: MediaSource, track: Track) async -> Data? {
        switch source {
        case .spotify:
            guard let url = track.artworkURL else { return nil }
            var request = URLRequest(url: url)
            request.timeoutInterval = 8
            guard let (data, response) = try? await URLSession.shared.data(for: request),
                  (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
            return data
        case .music:
            return await AppleScriptBridge.imageData(PlayerScripts.musicArtwork)
        }
    }

    static func accent(from data: Data) -> RGB {
        guard let pixels = downsample(data, side: 20) else { return .neutral }

        let binCount = 18
        var weights = [Double](repeating: 0, count: binCount)
        var sums = [RGB](repeating: RGB(red: 0, green: 0, blue: 0), count: binCount)
        var fallback = RGB(red: 0, green: 0, blue: 0)

        for pixel in pixels {
            fallback.red += pixel.red
            fallback.green += pixel.green
            fallback.blue += pixel.blue

            let hsb = toHSB(pixel)
            guard hsb.brightness > 0.15, hsb.saturation > 0.12 else { continue }
            let bin = min(binCount - 1, Int(hsb.hue * Double(binCount)))
            let weight = hsb.saturation * hsb.brightness
            weights[bin] += weight
            sums[bin].red += pixel.red * weight
            sums[bin].green += pixel.green * weight
            sums[bin].blue += pixel.blue * weight
        }

        let count = Double(pixels.count)
        var chosen = RGB(red: fallback.red / count, green: fallback.green / count, blue: fallback.blue / count)

        if let best = weights.indices.max(by: { weights[$0] < weights[$1] }), weights[best] > 0 {
            let weight = weights[best]
            chosen = RGB(red: sums[best].red / weight,
                         green: sums[best].green / weight,
                         blue: sums[best].blue / weight)
        }

        return lift(chosen)
    }

    private static func lift(_ rgb: RGB) -> RGB {
        var hsb = toHSB(rgb)
        hsb.saturation = min(1, max(0.42, hsb.saturation * 1.3))
        hsb.brightness = min(1, max(0.78, hsb.brightness * 1.15))
        return fromHSB(hsb)
    }

    private static func downsample(_ data: Data, side: Int) -> [RGB]? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }

        var buffer = [UInt8](repeating: 0, count: side * side * 4)
        let space = CGColorSpaceCreateDeviceRGB()
        let info = CGImageAlphaInfo.premultipliedLast.rawValue

        let drawn: Bool = buffer.withUnsafeMutableBytes { raw -> Bool in
            guard let context = CGContext(data: raw.baseAddress,
                                          width: side, height: side,
                                          bitsPerComponent: 8, bytesPerRow: side * 4,
                                          space: space, bitmapInfo: info) else { return false }
            context.interpolationQuality = .medium
            context.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
            return true
        }
        guard drawn else { return nil }

        var pixels: [RGB] = []
        pixels.reserveCapacity(side * side)
        for index in stride(from: 0, to: buffer.count, by: 4) {
            let alpha = Double(buffer[index + 3]) / 255
            guard alpha > 0.35 else { continue }
            pixels.append(RGB(red: Double(buffer[index]) / 255,
                              green: Double(buffer[index + 1]) / 255,
                              blue: Double(buffer[index + 2]) / 255))
        }
        return pixels.isEmpty ? nil : pixels
    }

    private struct HSB {
        var hue: Double
        var saturation: Double
        var brightness: Double
    }

    private static func toHSB(_ rgb: RGB) -> HSB {
        let maxValue = max(rgb.red, rgb.green, rgb.blue)
        let minValue = min(rgb.red, rgb.green, rgb.blue)
        let delta = maxValue - minValue
        var hue = 0.0
        if delta > 0.0001 {
            if maxValue == rgb.red {
                hue = (rgb.green - rgb.blue) / delta
            } else if maxValue == rgb.green {
                hue = 2 + (rgb.blue - rgb.red) / delta
            } else {
                hue = 4 + (rgb.red - rgb.green) / delta
            }
            hue /= 6
            if hue < 0 { hue += 1 }
        }
        return HSB(hue: hue,
                   saturation: maxValue <= 0 ? 0 : delta / maxValue,
                   brightness: maxValue)
    }

    private static func fromHSB(_ hsb: HSB) -> RGB {
        let sector = hsb.hue * 6
        let index = Int(sector) % 6
        let fraction = sector - Double(Int(sector))
        let p = hsb.brightness * (1 - hsb.saturation)
        let q = hsb.brightness * (1 - hsb.saturation * fraction)
        let t = hsb.brightness * (1 - hsb.saturation * (1 - fraction))
        let v = hsb.brightness

        switch index {
        case 0: return RGB(red: v, green: t, blue: p)
        case 1: return RGB(red: q, green: v, blue: p)
        case 2: return RGB(red: p, green: v, blue: t)
        case 3: return RGB(red: p, green: q, blue: v)
        case 4: return RGB(red: t, green: p, blue: v)
        default: return RGB(red: v, green: p, blue: q)
        }
    }
}
