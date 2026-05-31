// SunnyWalker — CloudBackground.swift  |  Day 1  |  three drifting cloud ovals

import SwiftUI

struct CloudBackground: View {
    // Each cloud has its own phase offset so they move independently
    @State private var offsets: [CGFloat] = [0, 0, 0]

    private struct CloudSpec {
        let width: CGFloat
        let height: CGFloat
        let yFraction: CGFloat   // 0 = top, 1 = bottom of the safe area
        let speed: Double        // animation duration (seconds)
        let xStart: CGFloat      // starting x offset relative to screen center
    }

    private let specs: [CloudSpec] = [
        CloudSpec(width: 140, height: 60,  yFraction: 0.12, speed: 14, xStart: -120),
        CloudSpec(width: 100, height: 45,  yFraction: 0.22, speed: 18, xStart:   50),
        CloudSpec(width: 120, height: 50,  yFraction: 0.32, speed: 11, xStart:  -60),
    ]

    var body: some View {
        GeometryReader { geo in
            ForEach(specs.indices, id: \.self) { i in
                let spec = specs[i]
                Ellipse()
                    .fill(GhibliColors.cloudWhite.opacity(0.55))
                    .frame(width: spec.width, height: spec.height)
                    .offset(
                        x: spec.xStart + offsets[i],
                        y: geo.size.height * spec.yFraction
                    )
                    .onAppear {
                        withAnimation(
                            .easeInOut(duration: spec.speed)
                            .repeatForever(autoreverses: true)
                        ) {
                            offsets[i] = 40
                        }
                    }
            }
        }
        .allowsHitTesting(false)
        .ignoresSafeArea()
    }
}

#Preview {
    ZStack {
        LinearGradient(
            colors: [GhibliColors.skyBlue, GhibliColors.cloudWhite],
            startPoint: .top, endPoint: .bottom
        )
        .ignoresSafeArea()
        CloudBackground()
    }
}
