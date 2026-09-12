import SwiftUI

struct Visualizer: View {
    var isPlaying: Bool
    var color: Color
    var height: CGFloat = 15
    var barWidth: CGFloat = 2.5

    private let speeds: [Double] = [3.4, 4.6, 2.7, 5.3]
    private let phases: [Double] = [0.0, 1.1, 2.4, 0.6]

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 24.0, paused: !isPlaying)) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            HStack(alignment: .center, spacing: barWidth) {
                ForEach(0..<4, id: \.self) { index in
                    Capsule(style: .continuous)
                        .fill(color)
                        .frame(width: barWidth, height: barHeight(at: index, time: time))
                }
            }
            .frame(height: height)
        }
        .frame(width: barWidth * 7, height: height)
    }

    private func barHeight(at index: Int, time: Double) -> CGFloat {
        guard isPlaying else { return barWidth }
        let wave = 0.5 + 0.5 * sin(time * speeds[index] + phases[index])
        return max(barWidth, height * (0.34 + 0.66 * wave))
    }
}
