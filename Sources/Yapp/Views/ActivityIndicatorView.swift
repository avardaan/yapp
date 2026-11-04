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
    private let gold = Color(red: 244 / 255, green: 178 / 255, blue: 65 / 255)

    var body: some View {
        TimelineView(.animation(minimumInterval: reduceMotion ? 1 : 1.0 / 60.0)) { timeline in
            let tick = timeline.date.timeIntervalSinceReferenceDate
            let processing = session.phase == .transcribing
            let preparing = session.waitingForModel && session.phase != .recording && !processing
            let opening = reduceMotion || preparing ? 25 : 12 + (sin(tick * 9) + 1) * 12
            HStack(spacing: 10) {
                PacmanMark(opening: opening)
                    .fill(gold).frame(width: 15, height: 15)
                HStack(spacing: 3) {
                    ForEach(0..<7, id: \.self) { index in
                        if processing {
                            Circle().fill(gold.opacity(reduceMotion || Int(tick * 7) % 7 == index ? 0.8 : 0.22))
                                .frame(width: 3, height: 3)
                                .frame(width: 3, height: 14)
                        } else {
                            let weight = 1 - abs(Double(index - 3)) / 5
                            let preparationLevel = reduceMotion ? 0.35 : (sin(tick * 5 - Double(index) * 0.7) + 1) * 0.3
                            Capsule().fill(gold.opacity(preparing ? 0.55 : 0.78))
                                .frame(width: 3, height: 3 + CGFloat((preparing ? preparationLevel : session.inputLevel) * weight) * 12)
                                .frame(height: 15)
                        }
                    }
                }
            }
            .frame(width: 96, height: 32)
            .background(Color(red: 28 / 255, green: 28 / 255, blue: 30 / 255).opacity(0.99), in: Capsule())
            .overlay(Capsule().strokeBorder(.white.opacity(0.03), lineWidth: 0.5))
            .accessibilityElement(children: .ignore)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.22), value: preparing)
            .accessibilityLabel(preparing ? "Yapp preparing dictation" : processing ? "Yapp transcribing" : "Yapp recording")
        }
    }
}
