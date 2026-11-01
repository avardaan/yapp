import SwiftUI

struct PacmanMark: Shape {
    var opening: Double = 28
    var animatableData: Double {
        get { opening }
        set { opening = newValue }
    }
    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2
        var path = Path()
        path.move(to: center)
        path.addArc(center: center, radius: radius, startAngle: .degrees(opening), endAngle: .degrees(360 - opening), clockwise: false)
        path.closeSubpath()
        return path
    }
}

struct ActivityIndicatorView: View {
    @ObservedObject var session: DictationSession
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let gold = Color(red: 0.88, green: 0.76, blue: 0.38)

    var body: some View {
        TimelineView(.animation(minimumInterval: reduceMotion ? 1 : 0.12)) { timeline in
            let tick = timeline.date.timeIntervalSinceReferenceDate
            let processing = session.phase == .transcribing
            let opening = reduceMotion ? 25 : 12 + (sin(tick * (processing ? 7 : 4)) + 1) * 12
            HStack(spacing: 9) {
                PacmanMark(opening: opening)
                    .fill(gold).frame(width: 12, height: 12)
                HStack(spacing: 3) {
                    ForEach(0..<7, id: \.self) { index in
                        if processing {
                            Circle().fill(gold.opacity(reduceMotion || Int(tick * 7) % 7 == index ? 0.8 : 0.22))
                                .frame(width: 3, height: 3)
                                .frame(width: 3, height: 14)
                        } else {
                            let weight = 1 - abs(Double(index - 3)) / 5
                            Capsule().fill(.primary.opacity(0.55))
                                .frame(width: 3, height: 3 + CGFloat(session.inputLevel * weight) * 12)
                                .frame(height: 15)
                        }
                    }
                }
            }
            .frame(width: 96, height: 30)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(Capsule().strokeBorder(.primary.opacity(0.08), lineWidth: 0.5))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(processing ? "Yapp transcribing" : "Yapp recording")
        }
    }
}
