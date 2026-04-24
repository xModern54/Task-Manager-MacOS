import SwiftUI

struct PerformanceGraphView: View {
    let samples: [Double]
    let color: Color
    var fill: Bool = false

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                GraphGrid()

                if fill {
                    GraphFill(samples: samples)
                        .fill(color.opacity(0.65))
                }

                GraphLine(samples: samples)
                    .stroke(color, style: StrokeStyle(lineWidth: 1.4, lineJoin: .round))
            }
            .background(WindowsTaskManagerTheme.table)
            .overlay {
                Rectangle()
                    .stroke(color.opacity(0.45), lineWidth: 0.8)
            }
            .drawingGroup()
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
    }
}

private struct GraphGrid: View {
    var body: some View {
        GeometryReader { proxy in
            Path { path in
                let verticalCount = 6
                let horizontalCount = 6

                for index in 1..<verticalCount {
                    let x = proxy.size.width * CGFloat(index) / CGFloat(verticalCount)
                    path.move(to: CGPoint(x: x, y: 0))
                    path.addLine(to: CGPoint(x: x, y: proxy.size.height))
                }

                for index in 1..<horizontalCount {
                    let y = proxy.size.height * CGFloat(index) / CGFloat(horizontalCount)
                    path.move(to: CGPoint(x: 0, y: y))
                    path.addLine(to: CGPoint(x: proxy.size.width, y: y))
                }
            }
            .stroke(WindowsTaskManagerTheme.separator.opacity(0.9), lineWidth: 0.7)
        }
    }
}

private struct GraphLine: Shape {
    let samples: [Double]

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard samples.count > 1 else { return path }

        let points = graphPoints(in: rect, samples: samples)
        path.move(to: points[0])
        points.dropFirst().forEach { path.addLine(to: $0) }
        return path
    }
}

private struct GraphFill: Shape {
    let samples: [Double]

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard samples.count > 1 else { return path }

        let points = graphPoints(in: rect, samples: samples)
        path.move(to: CGPoint(x: points[0].x, y: rect.maxY))
        points.forEach { path.addLine(to: $0) }
        path.addLine(to: CGPoint(x: points.last?.x ?? rect.maxX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

private func graphPoints(in rect: CGRect, samples: [Double]) -> [CGPoint] {
    samples.enumerated().map { index, sample in
        let normalized = min(max(sample, 0), 100) / 100
        let x = rect.minX + rect.width * CGFloat(index) / CGFloat(samples.count - 1)
        let y = rect.maxY - rect.height * CGFloat(normalized)
        return CGPoint(x: x, y: y)
    }
}
