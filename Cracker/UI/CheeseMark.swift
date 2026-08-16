import SwiftUI

struct CheeseMark: View {
    var size: CGFloat = 28

    var body: some View {
        Canvas { context, canvasSize in
            let w = min(canvasSize.width, canvasSize.height)
            var wedge = Path()
            wedge.move(to: CGPoint(x: w * 0.12, y: w * 0.82))
            wedge.addQuadCurve(to: CGPoint(x: w * 0.48, y: w * 0.1), control: CGPoint(x: w * 0.08, y: w * 0.68))
            wedge.addQuadCurve(to: CGPoint(x: w * 0.9, y: w * 0.82), control: CGPoint(x: w * 0.58, y: w * 0.22))
            wedge.addQuadCurve(to: CGPoint(x: w * 0.12, y: w * 0.82), control: CGPoint(x: w * 0.5, y: w * 0.92))
            wedge.closeSubpath()
            context.fill(wedge, with: .color(.cheddar))
            context.fill(Path(ellipseIn: CGRect(x: w * 0.35, y: w * 0.41, width: w * 0.14, height: w * 0.14)), with: .color(.cheddarSoft))
            context.fill(Path(ellipseIn: CGRect(x: w * 0.575, y: w * 0.575, width: w * 0.09, height: w * 0.09)), with: .color(Color.ink.opacity(0.18)))
            context.fill(Path(ellipseIn: CGRect(x: w * 0.325, y: w * 0.625, width: w * 0.11, height: w * 0.11)), with: .color(.cheddarSoft))
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

struct Wordmark: View {
    var body: some View {
        HStack(spacing: 10) {
            CheeseMark()
            HStack(spacing: 0) {
                Text("crack")
                    .foregroundStyle(Color.primary)
                Text("er")
                    .foregroundStyle(Color.cheddar)
            }
            .font(.system(size: 22, weight: .black))
            .tracking(-0.8)
        }
    }
}
