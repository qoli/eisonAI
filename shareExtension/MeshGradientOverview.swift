//  MeshGradientOverview.swift
//  SwiftUIPreview
//
//  Created by 黃佁媛 on 12/28/25.

import SwiftUI

struct MeshGradientOverview: View {
    @State private var phase: CGFloat = 0.0

    private var meshPoints: [SIMD2<Float>] {
        [
            // top row – absorbing light
            SIMD2<Float>(0.0, -0.2 + Float(phase)), SIMD2<Float>(0.5, -0.2 + Float(phase)), SIMD2<Float>(1.0, -0.2 + Float(phase)),

            // middle row – drifting cloud body
            SIMD2<Float>(0.0, 0.4 + Float(phase)),
            SIMD2<Float>(0.5, 0.55 + Float(phase)),
            SIMD2<Float>(1.0, 0.4 + Float(phase)),

            // bottom row – trailing glow
            SIMD2<Float>(0.0, 1.1 + Float(phase)), SIMD2<Float>(0.5, 1.1 + Float(phase)), SIMD2<Float>(1.0, 1.1 + Float(phase)),
        ]
    }

    private var meshColors: [Color] {
        let brightness = min(max(-phase, 0), 1) // brighten as the mesh moves upward
        func brighten(_ color: (r: Double, g: Double, b: Double)) -> Color {
            // Shift toward pure white in RGB space for a whiter look.
            let amount = 0.75 * Double(brightness)
            return Color(
                red: min(1, color.r + (1 - color.r) * amount),
                green: min(1, color.g + (1 - color.g) * amount),
                blue: min(1, color.b + (1 - color.b) * amount)
            )
        }
        return [
            // top – near black
            brighten((0, 0, 0)), brighten((0, 0, 0)), brighten((0, 0, 0)),

            // middle – dim transition
            brighten((0, 0, 0)),
            brighten((0.15, 0.15, 0.2)),
            brighten((0, 0, 0)),

            // bottom – primary light field
            brighten((0.35, 0.25, 0.6)), // purple-blue
            brighten((0.95, 0.8, 0.9)), // soft pink-white
            brighten((0.95, 0.85, 0.75)), // warm beige
        ]
    }

    private func startAnimation() {
        withAnimation(.easeInOut(duration: 1)) {
            phase = -1.0
        }
    }

    var body: some View {
        ZStack {
            MeshGradient(
                width: 3,
                height: 3,
                points: meshPoints,
                colors: meshColors,
                smoothsColors: true,
                colorSpace: .perceptual
            )
            .blur(radius: 80)
            .onAppear(perform: startAnimation)
        }
        .ignoresSafeArea(.all)
    }
}

#Preview {
    MeshGradientOverview()
}
