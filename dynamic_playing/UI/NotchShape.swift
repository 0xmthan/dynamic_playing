import SwiftUI

struct NotchShape: Shape {
    var shoulder: CGFloat
    var bottomRadius: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(shoulder, bottomRadius) }
        set {
            shoulder = newValue.first
            bottomRadius = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        let width = rect.width
        let height = rect.height
        let sh = max(0, min(shoulder, width / 4))
        let br = max(0, min(bottomRadius, min(height, (width - 2 * sh) / 2)))

        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addQuadCurve(to: CGPoint(x: rect.minX + sh, y: rect.minY + sh),
                          control: CGPoint(x: rect.minX + sh, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX + sh, y: rect.maxY - br))
        path.addQuadCurve(to: CGPoint(x: rect.minX + sh + br, y: rect.maxY),
                          control: CGPoint(x: rect.minX + sh, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX - sh - br, y: rect.maxY))
        path.addQuadCurve(to: CGPoint(x: rect.maxX - sh, y: rect.maxY - br),
                          control: CGPoint(x: rect.maxX - sh, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX - sh, y: rect.minY + sh))
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY),
                          control: CGPoint(x: rect.maxX - sh, y: rect.minY))
        path.closeSubpath()
        return path
    }
}
