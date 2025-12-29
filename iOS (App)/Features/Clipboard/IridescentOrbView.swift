import SwiftUI

struct IridescentOrbView: View {
    private let rotationPeriod: TimeInterval = 5
    private let swirlStrength: Float = 0.34
    private let orbitStrength: Float = 0.24
    private let hueShiftDegrees: Double = 86
    private let hueShiftSpeed: Double = 0.4
    private let sparkles: [Sparkle] = IridescentOrbView.makeSparkles(count: 32, variation: 16)

    private struct RGBColor {
        let r: Double
        let g: Double
        let b: Double
    }

    private let meshRGBColors: [RGBColor] = [
        RGBColor(r: 1.00, g: 0.52, b: 0.06),
        RGBColor(r: 0.98, g: 0.32, b: 0.05),
        RGBColor(r: 0.92, g: 0.18, b: 0.14),
        RGBColor(r: 0.98, g: 0.22, b: 0.78),
        RGBColor(r: 1.00, g: 0.94, b: 1.00),
        RGBColor(r: 0.62, g: 0.18, b: 0.90),
        RGBColor(r: 0.04, g: 0.62, b: 0.98),
        RGBColor(r: 0.00, g: 0.18, b: 0.88),
        RGBColor(r: 0.02, g: 0.08, b: 0.80),
    ]

    private func meshBezierPoints(phase: Float) -> [MeshGradient.BezierPoint] {
        [
            meshPoint(0.0, -0.08, phase: phase),
            meshPoint(0.5, -0.12, phase: phase),
            meshPoint(1.0, -0.05, phase: phase),
            meshPoint(0.0, 0.45, phase: phase),
            meshPoint(0.5, 0.52, phase: phase),
            meshPoint(1.0, 0.45, phase: phase),
            meshPoint(0.0, 1.08, phase: phase),
            meshPoint(0.5, 1.08, phase: phase),
            meshPoint(1.0, 1.08, phase: phase),
        ]
    }

    private func meshPoint(_ x: Float, _ y: Float, phase: Float) -> MeshGradient.BezierPoint {
        let basePosition = SIMD2<Float>(x, y)
        let center = SIMD2<Float>(0.5, 0.5)
        let inset = min(min(x, 1 - x), min(y, 1 - y))
        let edgeFalloff = max(0, min(1, inset * 2))
        let baseToCenter = basePosition - center
        let orbitAngle = atan2(baseToCenter.y, baseToCenter.x) + phase
        let orbitVector = SIMD2<Float>(
            Float(cos(Double(orbitAngle))),
            Float(sin(Double(orbitAngle)))
        )
        let orbit = orbitVector * (orbitStrength * edgeFalloff)
        let position = basePosition + orbit
        let toCenter = position - center
        let tangent = normalized(SIMD2<Float>(toCenter.y, -toCenter.x))
        let offset = tangent * (swirlStrength * edgeFalloff)

        return MeshGradient.BezierPoint(
            position: position,
            leadingControlPoint: position - offset,
            topControlPoint: position - offset,
            trailingControlPoint: position + offset,
            bottomControlPoint: position + offset
        )
    }

    private func normalized(_ vector: SIMD2<Float>) -> SIMD2<Float> {
        let length = max(0.0001, sqrt(vector.x * vector.x + vector.y * vector.y))
        return vector / length
    }

    private func rgbToHSB(_ color: RGBColor) -> (h: Double, s: Double, b: Double) {
        let maxValue = max(color.r, color.g, color.b)
        let minValue = min(color.r, color.g, color.b)
        let delta = maxValue - minValue

        var hue: Double = 0
        if delta > 0 {
            if maxValue == color.r {
                hue = ((color.g - color.b) / delta).truncatingRemainder(dividingBy: 6)
            } else if maxValue == color.g {
                hue = ((color.b - color.r) / delta) + 2
            } else {
                hue = ((color.r - color.g) / delta) + 4
            }
            hue /= 6
            if hue < 0 { hue += 1 }
        }

        let saturation = maxValue == 0 ? 0 : delta / maxValue
        return (hue, saturation, maxValue)
    }

    private func animatedMeshColors(time: TimeInterval) -> [Color] {
        let hueShift = sin(time * hueShiftSpeed) * (hueShiftDegrees / 360)
        let brightnessShift = 0.7 + 0.3 * sin(time * (hueShiftSpeed * 0.75) + 1.4)
        return meshRGBColors.map { rgb in
            let hsb = rgbToHSB(rgb)
            var hue = hsb.h + hueShift
            hue.formTruncatingRemainder(dividingBy: 1)
            if hue < 0 { hue += 1 }
            let brightness = max(0.9, min(1.0, hsb.b * brightnessShift))
            return Color(hue: hue, saturation: hsb.s, brightness: brightness)
        }
    }

    private struct Sparkle {
        let position: SIMD2<Float>
        let radius: CGFloat
        let baseOpacity: Double
        let driftAmplitude: SIMD2<Float>
        let driftSpeedX: Double
        let driftSpeedY: Double
        let driftPhaseX: Double
        let driftPhaseY: Double
        let twinkleSpeed: Double
        let twinklePhase: Double
    }

    private struct SeededGenerator: RandomNumberGenerator {
        private var state: UInt64

        init(seed: UInt64) {
            state = seed
        }

        mutating func next() -> UInt64 {
            state &+= 0x9E3779B97F4A7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
            z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
            return z ^ (z >> 31)
        }
    }

    private static func makeSparkles(count: Int, variation: Int) -> [Sparkle] {
        var rng = SeededGenerator(seed: 0x51F00D12)
        var sparkles: [Sparkle] = []
        let clampedVariation = max(0, min(variation, count))
        let targetCount = count + Int.random(in: -clampedVariation ... clampedVariation, using: &rng)
        sparkles.reserveCapacity(targetCount)

        while sparkles.count < targetCount {
            let x = Double.random(in: -1 ... 1, using: &rng)
            let y = Double.random(in: -1 ... 1, using: &rng)
            guard x * x + y * y <= 1 else { continue }

            let radius = CGFloat(Double.random(in: 0.008 ... 0.05, using: &rng))
            let baseOpacity = Double.random(in: 0.05 ... 0.9, using: &rng)
            let driftAmplitude = SIMD2<Float>(
                Float(Double.random(in: 0.06 ... 0.16, using: &rng)),
                Float(Double.random(in: 0.06 ... 0.16, using: &rng))
            )
            let driftSpeedX = Double.random(in: 1.2 ... 3.2, using: &rng)
            let driftSpeedY = Double.random(in: 1.0 ... 2.6, using: &rng)
            let driftPhaseX = Double.random(in: 0 ... (Double.pi * 2), using: &rng)
            let driftPhaseY = Double.random(in: 0 ... (Double.pi * 2), using: &rng)
            let twinkleSpeed = Double.random(in: 0.4 ... 1.8, using: &rng)
            let twinklePhase = Double.random(in: 0 ... (Double.pi * 2), using: &rng)

            sparkles.append(
                Sparkle(
                    position: SIMD2<Float>(Float(x), Float(y)),
                    radius: radius,
                    baseOpacity: baseOpacity,
                    driftAmplitude: driftAmplitude,
                    driftSpeedX: driftSpeedX,
                    driftSpeedY: driftSpeedY,
                    driftPhaseX: driftPhaseX,
                    driftPhaseY: driftPhaseY,
                    twinkleSpeed: twinkleSpeed,
                    twinklePhase: twinklePhase
                )
            )
        }

        return sparkles
    }

    var size: CGFloat = 36
    var sizeforCircle: CGFloat {
        return size
    }

    var sizeforShadow: CGFloat {
        return size
    }

    var body: some View {
        TimelineView(.animation) { context in
            let seconds = context.date.timeIntervalSinceReferenceDate
            let progress = (seconds.truncatingRemainder(dividingBy: rotationPeriod)) / rotationPeriod
            let phase = Float(progress * .pi * 2)
            let time = seconds
            let meshColors = animatedMeshColors(time: time)
            let shadowColor = meshColors[7].opacity(0.85)

            ZStack {
                Ellipse()
                    .fill(shadowColor)
                    .frame(
                        width: sizeforShadow - 6,
                        height: sizeforShadow - 28
                    )
                    .blur(radius: 4)
                    .offset(y: sizeforShadow * 0.65)

                ZStack {
                    MeshGradient(
                        width: 3,
                        height: 3,
                        bezierPoints: meshBezierPoints(phase: phase),
                        colors: meshColors,
                        smoothsColors: true,
                        colorSpace: .perceptual
                    )

                    Canvas { context, canvasSize in
                        let minDim = min(canvasSize.width, canvasSize.height)

                        func drawSparkles(time: TimeInterval, opacityScale: Double) {
                            for sparkle in sparkles {
                                let driftX = sin(time * sparkle.driftSpeedX + sparkle.driftPhaseX) * Double(sparkle.driftAmplitude.x)
                                let driftY = cos(time * sparkle.driftSpeedY + sparkle.driftPhaseY) * Double(sparkle.driftAmplitude.y)
                                var position = SIMD2<Double>(
                                    Double(sparkle.position.x) + driftX,
                                    Double(sparkle.position.y) + driftY
                                )
                                let distance = sqrt(position.x * position.x + position.y * position.y)
                                if distance > 1 {
                                    position /= distance
                                }

                                let twinkle = 0.5 + 0.5 * sin(time * sparkle.twinkleSpeed + sparkle.twinklePhase)
                                let visibility = max(0, (twinkle - 0.1) / 0.9)
                                let edgeFade = max(0, min(1, (1 - distance) * 1.4))
                                let opacity = sparkle.baseOpacity * pow(visibility, 1.2) * Double(edgeFade) * opacityScale
                                if opacity < 0.02 { continue }

                                let radius = sparkle.radius * minDim
                                let point = CGPoint(
                                    x: (position.x + 1) * 0.5 * canvasSize.width,
                                    y: (position.y + 1) * 0.5 * canvasSize.height
                                )
                                let rect = CGRect(
                                    x: point.x - radius,
                                    y: point.y - radius,
                                    width: radius * 2,
                                    height: radius * 2
                                )
                                let path = Path(ellipseIn: rect)

                                context.drawLayer { layer in
                                    layer.addFilter(.blur(radius: radius * 1.6))
                                    layer.fill(path, with: .color(Color.white.opacity(opacity * 0.45)))
                                }
                                context.fill(path, with: .color(Color.white.opacity(opacity)))
                            }
                        }

                        drawSparkles(time: time, opacityScale: 1.0)
                        drawSparkles(time: time - 1.2, opacityScale: 0.85)
                    }
                    .allowsHitTesting(false)
                }
                .frame(width: size, height: size)
                .clipShape(Circle())

                Circle()
                    .stroke(Color.white, lineWidth: 1)
                    .frame(width: sizeforCircle, height: sizeforCircle)

                Circle()
                    .stroke(Color.white, lineWidth: 1)
                    .frame(width: sizeforCircle, height: sizeforCircle)
                    .blur(radius: 3)

                Circle()
                    .stroke(Color.white, lineWidth: 3)
                    .frame(width: sizeforCircle, height: sizeforCircle)
                    .blur(radius: 8)
                    .opacity(0.8)

                Circle()
                    .stroke(Color.white, lineWidth: 6)
                    .frame(width: sizeforCircle, height: sizeforCircle)
                    .blur(radius: 12)
                    .opacity(0.3)
            }
        }
    }
}

#Preview {
    IridescentOrbView()
}
