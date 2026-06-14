import SwiftUI

/// A deterministic, static paper grain. The fixed seed keeps Canvas output stable between redraws.
struct PaperTextureOverlay: View {
    var tint: Color = SunnyColors.wheatGold
    var density: Int = 1500

    var body: some View {
        Canvas { context, size in
            guard size.width > 0, size.height > 0 else { return }
            var rng = SunnyLCG(seed: UInt64(size.width.rounded()) &* 31 + UInt64(size.height.rounded()))

            context.blendMode = .overlay
            for _ in 0..<density {
                let x = rng.unit * size.width
                let y = rng.unit * size.height
                let diameter = 0.45 + rng.unit * 1.15
                let bright = rng.unit > 0.48
                let color = bright ? Color.white.opacity(0.42) : Color.black.opacity(0.28)
                context.fill(
                    Path(ellipseIn: CGRect(x: x, y: y, width: diameter, height: diameter)),
                    with: .color(color)
                )
            }

            context.blendMode = .softLight
            let washes: [(CGPoint, CGFloat, Double)] = [
                (CGPoint(x: size.width * 0.12, y: size.height * 0.18), size.width * 0.58, 0.15),
                (CGPoint(x: size.width * 0.82, y: size.height * 0.42), size.width * 0.46, 0.11),
                (CGPoint(x: size.width * 0.35, y: size.height * 0.88), size.width * 0.64, 0.10)
            ]
            for wash in washes {
                context.fill(
                    Path(ellipseIn: CGRect(
                        x: wash.0.x - wash.1, y: wash.0.y - wash.1,
                        width: wash.1 * 2, height: wash.1 * 2
                    )),
                    with: .radialGradient(
                        Gradient(colors: [tint.opacity(wash.2), tint.opacity(0)]),
                        center: wash.0,
                        startRadius: 0,
                        endRadius: wash.1
                    )
                )
            }
        }
        .opacity(0.10)
        .drawingGroup()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

struct SunnyLCG {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed == 0 ? 0x9E3779B97F4A7C15 : seed
    }

    var unit: CGFloat {
        mutating get {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return CGFloat(Double(state >> 11) / Double(1 << 53))
        }
    }
}
