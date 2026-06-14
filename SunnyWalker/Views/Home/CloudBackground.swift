import SwiftUI

/// One centralized animated background pass: clouds, shared wind, stars, dust/fireflies, and flora.
struct CloudBackground: View {
    var scene: DaytimeScene = DaytimeScene.current(
        hour: Calendar.current.component(.hour, from: Date())
    )
    var isActive = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !isActive || reduceMotion)) { timeline in
            Canvas { context, size in
                let t = reduceMotion ? 0 : timeline.date.timeIntervalSinceReferenceDate
                drawMountains(context: &context, size: size)
                drawStars(context: &context, size: size, time: t)
                drawRays(context: &context, size: size, time: t)
                drawClouds(context: &context, size: size, time: t)
                drawParticles(context: &context, size: size, time: t)
                drawFlora(context: &context, size: size, time: t)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .ignoresSafeArea()
    }

    private func drawMountains(context: inout GraphicsContext, size: CGSize) {
        var distant = Path()
        distant.move(to: CGPoint(x: 0, y: size.height * 0.70))
        distant.addCurve(
            to: CGPoint(x: size.width, y: size.height * 0.72),
            control1: CGPoint(x: size.width * 0.26, y: size.height * 0.52),
            control2: CGPoint(x: size.width * 0.68, y: size.height * 0.58)
        )
        distant.addLine(to: CGPoint(x: size.width, y: size.height))
        distant.addLine(to: CGPoint(x: 0, y: size.height))
        distant.closeSubpath()
        context.fill(distant, with: .color(scene.silhouetteColor.opacity(0.24)))
    }

    private func drawClouds(context: inout GraphicsContext, size: CGSize, time: TimeInterval) {
        let specs: [(CGFloat, CGFloat, CGFloat, Double, Double)] = [
            (0.20, 0.14, 0.72, 0.9, 0.0), (0.72, 0.22, 0.58, 0.7, 1.8),
            (0.48, 0.34, 0.92, 1.0, 3.4), (0.10, 0.46, 1.12, 1.15, 5.0),
            (0.82, 0.55, 0.82, 0.85, 6.2), (0.34, 0.64, 0.55, 0.65, 2.7)
        ]
        let nightAlpha: Double = scene == .night ? 0.34 : 1
        let wind = sin(time * 0.5) + 0.4 * sin(time * 1.3)

        for (index, spec) in specs.enumerated() {
            let drift = CGFloat(sin(time * 0.055 * spec.3 + spec.4) * 34 + wind * 4)
            let breath = CGFloat(1 + sin(time * 0.55 + spec.4) * 0.015)
            let center = CGPoint(x: size.width * spec.0 + drift, y: size.height * spec.1)
            let scale = spec.2 * breath
            let shadowPath = cloudPath(center: CGPoint(x: center.x, y: center.y + 5 * scale), scale: scale)
            let bodyPath = cloudPath(center: center, scale: scale)
            let highlightPath = cloudPath(center: CGPoint(x: center.x - 2, y: center.y - 3), scale: scale * 0.96)
            let depth = index < 2 ? 0.42 : 0.66

            context.fill(shadowPath, with: .color(SunnyColors.cloudShadow.opacity(depth * nightAlpha)))
            context.fill(bodyPath, with: .color(SunnyColors.cloudWhite.opacity(depth * nightAlpha)))
            context.fill(highlightPath, with: .color(Color.white.opacity(0.18 * nightAlpha)))
        }
    }

    private func cloudPath(center: CGPoint, scale: CGFloat) -> Path {
        let lumps: [(CGFloat, CGFloat, CGFloat, CGFloat)] = [
            (0, 0, 48, 25), (30, 4, 38, 22), (-30, 5, 36, 21),
            (14, -13, 34, 28), (-13, -11, 32, 27), (50, 8, 25, 18)
        ]
        var path = Path()
        for lump in lumps {
            path.addEllipse(in: CGRect(
                x: center.x + (lump.0 - lump.2 / 2) * scale,
                y: center.y + (lump.1 - lump.3 / 2) * scale,
                width: lump.2 * scale,
                height: lump.3 * scale
            ))
        }
        return path
    }

    private func drawParticles(context: inout GraphicsContext, size: CGSize, time: TimeInterval) {
        var rng = SunnyLCG(seed: 0x51A7)
        let count = scene == .night ? 14 : 26
        for index in 0..<count {
            let baseX = rng.unit * size.width
            let baseY = rng.unit * size.height
            let radius = 0.7 + rng.unit * 1.5
            let phase = Double(rng.unit) * .pi * 2
            let speed = 0.22 + Double(rng.unit) * 0.42
            let x: CGFloat
            let y: CGFloat
            let color: Color
            let alpha: Double

            if scene == .night {
                x = baseX + CGFloat(sin(time * speed + phase)) * (20 + rng.unit * 42)
                y = baseY + CGFloat(sin(time * speed * 0.72 + phase * 1.7)) * (14 + rng.unit * 30)
                alpha = 0.28 + abs(sin(time * 1.15 + phase)) * 0.68
                color = SunnyColors.starGold
                context.fill(
                    Path(ellipseIn: CGRect(x: x - 6, y: y - 6, width: 12, height: 12)),
                    with: .radialGradient(
                        Gradient(colors: [color.opacity(alpha * 0.34), color.opacity(0)]),
                        center: CGPoint(x: x, y: y),
                        startRadius: 0,
                        endRadius: 6
                    )
                )
            } else {
                let rise = CGFloat(time * (4 + Double(rng.unit) * 4)).truncatingRemainder(dividingBy: size.height + 20)
                x = baseX + CGFloat(sin(time * speed + phase)) * (8 + rng.unit * 8)
                y = (baseY - rise + size.height).truncatingRemainder(dividingBy: size.height)
                alpha = 0.16 + abs(sin(time * 0.72 + phase)) * 0.32
                color = scene == .dusk ? SunnyColors.wheatGold : Color.white
            }
            context.fill(
                Path(ellipseIn: CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2)),
                with: .color(color.opacity(alpha))
            )
            _ = index
        }
    }

    private func drawStars(context: inout GraphicsContext, size: CGSize, time: TimeInterval) {
        guard scene == .night else { return }
        var rng = SunnyLCG(seed: 0x57A2)
        for _ in 0..<26 {
            let x = rng.unit * size.width
            let y = rng.unit * size.height * 0.68
            let r = 0.6 + rng.unit * 1.2
            let phase = Double(rng.unit) * .pi * 2
            let alpha = 0.28 + abs(sin(time * 1.4 + phase)) * 0.54
            context.fill(
                Path(ellipseIn: CGRect(x: x, y: y, width: r * 2, height: r * 2)),
                with: .color(SunnyColors.starGold.opacity(alpha))
            )
        }
    }

    private func drawRays(context: inout GraphicsContext, size: CGSize, time: TimeInterval) {
        guard scene == .dawn || scene == .morning || scene == .dusk else { return }
        context.blendMode = .softLight
        for index in 0..<3 {
            let x = size.width * (0.05 + CGFloat(index) * 0.24)
            var ray = Path()
            ray.move(to: CGPoint(x: x, y: 0))
            ray.addLine(to: CGPoint(x: x + size.width * 0.17, y: 0))
            ray.addLine(to: CGPoint(x: x + size.width * 0.62, y: size.height))
            ray.addLine(to: CGPoint(x: x + size.width * 0.40, y: size.height))
            ray.closeSubpath()
            let pulse = 0.5 + 0.5 * sin(time * 0.6 + Double(index))
            context.fill(ray, with: .color(Color.white.opacity(0.025 + pulse * 0.025)))
        }
    }

    private func drawFlora(context: inout GraphicsContext, size: CGSize, time: TimeInterval) {
        let wind = CGFloat(sin(time * 0.5) + 0.4 * sin(time * 1.3))
        var rng = SunnyLCG(seed: 0xF10A)
        for _ in 0..<42 {
            let x = rng.unit * size.width
            let height = 12 + rng.unit * 30
            let bend = wind * (1.5 + rng.unit * 3)
            var stem = Path()
            stem.move(to: CGPoint(x: x, y: size.height + 2))
            stem.addCurve(
                to: CGPoint(x: x + bend, y: size.height - height),
                control1: CGPoint(x: x, y: size.height - height * 0.35),
                control2: CGPoint(x: x + bend * 0.3, y: size.height - height * 0.72)
            )
            context.stroke(
                stem,
                with: .color(scene.silhouetteColor.opacity(0.62)),
                lineWidth: 1.1 + rng.unit * 1.2
            )
            let leaf = Path(ellipseIn: CGRect(x: x + bend - 2.5, y: size.height - height - 2, width: 5.5, height: 3))
            context.fill(leaf, with: .color(scene.silhouetteColor.opacity(0.56)))
        }
    }
}

#Preview {
    ZStack {
        LinearGradient(colors: DaytimeScene.morning.gradientColors, startPoint: .top, endPoint: .bottom)
        CloudBackground(scene: .morning)
    }
}
