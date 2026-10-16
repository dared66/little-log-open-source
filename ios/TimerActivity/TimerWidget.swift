import ActivityKit
import SwiftUI
import WidgetKit

@main
struct TimerWidgets: WidgetBundle {
    var body: some Widget { CareTimerWidget() }
}

// These 24-point paths match the app's CareGlyph outline icons.
struct CareActivityShape: Shape {
    var method: String
    func path(in rect: CGRect) -> Path {
        var p = Path()
        if method == "nursing" {
            p.addEllipse(in: CGRect(x: 5.5, y: 1.5, width: 5, height: 5))
            p.addEllipse(in: CGRect(x: 13.5, y: 8.5, width: 5, height: 5))
            p.move(to: CGPoint(x: 5, y: 9)); p.addQuadCurve(to: CGPoint(x: 5, y: 21), control: CGPoint(x: 2, y: 15))
            p.addLine(to: CGPoint(x: 18, y: 21))
            p.move(to: CGPoint(x: 8, y: 9)); p.addLine(to: CGPoint(x: 10, y: 14)); p.addLine(to: CGPoint(x: 17, y: 17))
            p.addQuadCurve(to: CGPoint(x: 7, y: 16), control: CGPoint(x: 12, y: 21))
            p.move(to: CGPoint(x: 10, y: 14)); p.addLine(to: CGPoint(x: 13, y: 12))
        } else if method == "pumping" {
            p.addRoundedRect(in: CGRect(x: 6, y: 8, width: 12, height: 14), cornerSize: CGSize(width: 3, height: 3))
            p.move(to: CGPoint(x: 6, y: 8)); p.addLine(to: CGPoint(x: 18, y: 8))
            p.move(to: CGPoint(x: 8, y: 8)); p.addLine(to: CGPoint(x: 8, y: 5)); p.addLine(to: CGPoint(x: 10, y: 5)); p.addLine(to: CGPoint(x: 10, y: 3))
            p.addQuadCurve(to: CGPoint(x: 14, y: 3), control: CGPoint(x: 12, y: 0)); p.addLine(to: CGPoint(x: 14, y: 5)); p.addLine(to: CGPoint(x: 16, y: 5)); p.addLine(to: CGPoint(x: 16, y: 8))
            for y in [12.0, 16.0, 19.0] { p.move(to: CGPoint(x: 7, y: y)); p.addLine(to: CGPoint(x: 10, y: y)) }
            p.move(to: CGPoint(x: 16, y: 4)); p.addLine(to: CGPoint(x: 21, y: 4)); p.addLine(to: CGPoint(x: 21, y: 11))
        } else {
            p.move(to: CGPoint(x: 20, y: 15))
            p.addCurve(to: CGPoint(x: 9, y: 3), control1: CGPoint(x: 12, y: 18), control2: CGPoint(x: 5, y: 10))
            p.addCurve(to: CGPoint(x: 20, y: 15), control1: CGPoint(x: -2, y: 6), control2: CGPoint(x: 6, y: 28))
            p.closeSubpath()
        }
        return p.applying(CGAffineTransform(scaleX: rect.width / 24, y: rect.height / 24))
    }
}

struct CareTimerWidget: Widget {
    private let lockScreenInk = Color(red: 0.12, green: 0.20, blue: 0.18)

    private func method(_ state: TimerAttributes.ContentState) -> String {
        state.method ?? (state.title.contains("Nursing") ? "nursing" : state.title.contains("Pumping") ? "pumping" : "sleep")
    }
    private func icon(_ state: TimerAttributes.ContentState, size: CGFloat = 24) -> some View {
        CareActivityShape(method: method(state))
            .stroke(style: StrokeStyle(lineWidth: size * 1.7 / 24, lineCap: .round, lineJoin: .round))
            .frame(width: size, height: size)
            .accessibilityLabel(method(state).capitalized)
    }
    @ViewBuilder private func timer(_ state: TimerAttributes.ContentState) -> some View {
        if state.currentPhase == "running" {
            Text(state.startedAt, style: .timer).monospacedDigit().multilineTextAlignment(.trailing)
        } else {
            let seconds = Int(state.elapsedSeconds ?? 0)
            Text(seconds >= 3600 ? String(format: "%d:%02d:%02d", seconds / 3600, seconds / 60 % 60, seconds % 60)
                 : String(format: "%d:%02d", seconds / 60, seconds % 60)).monospacedDigit()
        }
    }
    @ViewBuilder private func finish(_ context: ActivityViewContext<TimerAttributes>) -> some View {
        if #available(iOS 17.0, *), context.attributes.familyID != nil {
            let id = context.attributes.sessionID
            let revision = context.state.revision ?? 0
            HStack(spacing: 8) {
                if context.state.currentPhase == "running" && method(context.state) != "sleep" {
                    Button(intent: PauseLiveTimerIntent(sessionID: id, revision: revision)) { Label("Pause", systemImage: "pause.fill") }
                        .accessibilityLabel("Pause " + method(context.state))
                } else {
                    if context.state.currentPhase == "paused" {
                        Button(intent: ResumeLiveTimerIntent(sessionID: id, revision: revision)) { Label("Resume", systemImage: "play.fill") }
                            .accessibilityLabel("Resume " + method(context.state))
                    }
                    if method(context.state) == "pumping" {
                        Button(intent: FinishLivePumpingIntent(sessionID: id, revision: revision,
                            action: context.state.currentPhase == "review" ? "review" : "finish")) {
                            Text(context.state.currentPhase == "review" ? "Add amount" : "Finish")
                        }.accessibilityLabel("Finish pumping and enter amount")
                    } else {
                        Button(intent: FinishLiveTimerIntent(sessionID: id, revision: revision)) { Text("Finish") }
                            .accessibilityLabel("Finish " + method(context.state))
                    }
                }
            }
        }
    }
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: TimerAttributes.self) { context in
            VStack(alignment: .leading, spacing: 10) {
              HStack(spacing: 12) {
                icon(context.state, size: 30)
                VStack(alignment: .leading, spacing: 4) {
                    Text(context.state.title).font(.headline)
                    Text(context.state.detail).font(.caption)
                }
                Spacer(minLength: 8)
                timer(context.state).font(.title2).frame(width: 100)
              }
              HStack { Spacer(); finish(context).buttonStyle(.bordered).tint(lockScreenInk) }
            }
            .padding()
            .foregroundStyle(lockScreenInk)
            .activityBackgroundTint(Color(red: 0.89, green: 0.94, blue: 0.91))
            .activitySystemActionForegroundColor(lockScreenInk)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) { icon(context.state) }
                DynamicIslandExpandedRegion(.trailing) { timer(context.state).font(.title2).frame(width: 100) }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack {
                        VStack(alignment: .leading) { Text(context.state.title).font(.headline); Text(context.state.detail).font(.caption) }
                        Spacer()
                        finish(context).buttonStyle(.bordered).tint(.white)
                    }
                }
            } compactLeading: { icon(context.state, size: 20) }
              compactTrailing: { timer(context.state).font(.system(size: 14, weight: .medium)).frame(width: 64) }
              minimal: {
                  VStack(spacing: 1) {
                      icon(context.state, size: 13)
                      timer(context.state).font(.system(size: 8, weight: .medium)).frame(width: 34)
                  }
              }
        }
    }
}
