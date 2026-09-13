import SwiftUI

struct ProgressRing<Content: View>: View {
    var progress: Double
    var accent: Color
    var diameter: CGFloat
    var lineWidth: CGFloat
    @ViewBuilder var content: Content

    var body: some View {
        ZStack {
            Circle()
                .inset(by: lineWidth / 2)
                .stroke(.white.opacity(0.15), lineWidth: lineWidth)
            Circle()
                .inset(by: lineWidth / 2)
                .trim(from: 0, to: max(0.004, min(1, progress)))
                .stroke(accent, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
            content
        }
        .frame(width: diameter, height: diameter)
    }
}
