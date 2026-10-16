import ActivityKit
import Foundation
import AppIntents

@available(iOS 16.2, *)
struct TimerAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var method: String?
        var title: String
        var startedAt: Date
        var detail: String
        var phase: String? = nil
        var elapsedSeconds: Double? = nil
        var revision: Int? = nil
        var currentPhase: String { phase ?? "running" }
        func elapsed(at: Date) -> Double {
            currentPhase == "running" ? max(0, at.timeIntervalSince(startedAt)) : (elapsedSeconds ?? 0)
        }
        func applying(action: String, at: Date, expectedRevision: Int?) -> Self? {
            if let expectedRevision, expectedRevision != (revision ?? 0) { return nil }
            var next = self
            switch action {
            case "pause":
                guard method != "sleep", currentPhase == "running" else { return nil }
                next.elapsedSeconds = elapsed(at: at); next.phase = "paused"; next.detail = "Paused"
            case "resume":
                guard currentPhase == "paused" else { return nil }
                next.startedAt = at.addingTimeInterval(-(elapsedSeconds ?? 0))
                next.phase = "running"; next.detail = "Timer running"
            case "finish":
                guard method == "sleep" || currentPhase == "paused" else { return nil }
                next.elapsedSeconds = elapsed(at: at)
                next.phase = method == "pumping" ? "review" : "finished"
                next.detail = method == "pumping" ? "Add pumped amount" : "Finished"
            case "review":
                return currentPhase == "review" ? self : nil
            default: return nil
            }
            next.revision = (revision ?? 0) + 1
            return next
        }
    }
    var familyID: String?
    var sessionID: String
}

struct LiveTimerStop: Codable, Equatable {
    let id: String
    let familyId: String
    let method: String
    let stoppedAt: Int64
    let sessionId: String?
    let action: String?
    let revision: Int?
    var resolvedSessionID: String { sessionId ?? id }
    init(id: String, familyId: String, method: String, stoppedAt: Int64,
         sessionId: String? = nil, action: String? = nil, revision: Int? = nil) {
        self.id = id; self.familyId = familyId; self.method = method; self.stoppedAt = stoppedAt
        self.sessionId = sessionId; self.action = action; self.revision = revision
    }
    var payload: [String: Any] {
        var fields: [String: Any] = ["id": id, "familyId": familyId, "method": method, "stoppedAt": stoppedAt]
        if let sessionId { fields["sessionId"] = sessionId }
        if let action { fields["action"] = action }
        if let revision { fields["revision"] = revision }
        return fields
    }
}

// Actions stay durable until Dart acknowledges their local database transition.
final class LiveTimerStopStore: @unchecked Sendable {
    static let shared = LiveTimerStopStore()
    static let changed = Notification.Name("LittleLogLiveTimerStopped")
    private let lock = NSLock()
    private let file: URL
    @MainActor private var observedStates: [String: Data] = [:]
    init(file: URL? = nil) {
        self.file = file ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("live-timer-stops.json")
    }
    private func read() throws -> [LiveTimerStop] {
        guard FileManager.default.fileExists(atPath: file.path) else { return [] }
        return try JSONDecoder().decode([LiveTimerStop].self, from: Data(contentsOf: file))
    }
    private func write(_ requests: [LiveTimerStop]) throws {
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(requests).write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
    func pending() throws -> [LiveTimerStop] { lock.lock(); defer { lock.unlock() }; return try read() }
    @discardableResult func append(_ request: LiveTimerStop) throws -> LiveTimerStop {
        lock.lock(); defer { lock.unlock() }
        var requests = try read()
        if let previous = requests.first(where: { $0.id == request.id }) { return previous }
        requests.append(request); try write(requests); return request
    }
    // ActivityKit publishes content asynchronously. Use accepted actions while
    // that publication catches up, including immediately after Dart acknowledges.
    @available(iOS 16.2, *) @MainActor
    func resolvedState(_ id: String, observed: TimerAttributes.ContentState) throws -> TimerAttributes.ContentState {
        var state = observed
        if let data = observedStates[id],
           let cached = try? JSONDecoder().decode(TimerAttributes.ContentState.self, from: data),
           (cached.revision ?? 0) > (state.revision ?? 0) { state = cached }
        for request in try pending() where request.resolvedSessionID == id {
            if let next = state.applying(action: request.action ?? "finish",
                at: Date(timeIntervalSince1970: Double(request.stoppedAt) / 1000),
                expectedRevision: request.revision) { state = next }
        }
        observedStates[id] = try JSONEncoder().encode(state)
        return state
    }
    @available(iOS 16.2, *) @MainActor
    func remember(_ id: String, state: TimerAttributes.ContentState) throws {
        observedStates[id] = try JSONEncoder().encode(state)
    }
    func acknowledge(_ id: String) throws {
        lock.lock(); defer { lock.unlock() }; try write(read().filter { $0.id != id })
    }
}

@available(iOS 17.0, *) @MainActor
func changeLiveTimer(_ sessionID: String, action: String, revision: Int?, store: LiveTimerStopStore = .shared) async throws {
    guard let activity = Activity<TimerAttributes>.activities.first(where: { $0.attributes.sessionID == sessionID }),
          let family = activity.attributes.familyID, let method = activity.content.state.method else { return }
    let now = Date()
    let current = try store.resolvedState(sessionID, observed: activity.content.state)
    guard let state = current.applying(action: action, at: now, expectedRevision: revision) else { return }
    try store.append(LiveTimerStop(id: UUID().uuidString, familyId: family, method: method,
        stoppedAt: Int64(now.timeIntervalSince1970 * 1000), sessionId: sessionID, action: action, revision: revision))
    try store.remember(sessionID, state: state)
    let content = ActivityContent(state: state, staleDate: nil)
    if state.currentPhase == "finished" { await activity.end(content, dismissalPolicy: .immediate) }
    else { await activity.update(content) }
    NotificationCenter.default.post(name: LiveTimerStopStore.changed, object: nil)
}

@available(iOS 17.0, *) @MainActor
func stopLiveTimer(_ sessionID: String, store: LiveTimerStopStore = .shared) async throws {
    try await changeLiveTimer(sessionID, action: "finish", revision: nil, store: store)
}

@available(iOS 17.0, *)
struct PauseLiveTimerIntent: LiveActivityIntent {
    static var title: LocalizedStringResource { "Pause timer" }
    static var isDiscoverable: Bool { false }
    @Parameter(title: "Session") var sessionID: String
    @Parameter(title: "Revision") var revision: Int
    init() {}
    init(sessionID: String, revision: Int) { self.sessionID = sessionID; self.revision = revision }
    func perform() async throws -> some IntentResult {
        try await changeLiveTimer(sessionID, action: "pause", revision: revision); return .result()
    }
}
@available(iOS 17.0, *)
struct ResumeLiveTimerIntent: LiveActivityIntent {
    static var title: LocalizedStringResource { "Resume timer" }
    static var isDiscoverable: Bool { false }
    @Parameter(title: "Session") var sessionID: String
    @Parameter(title: "Revision") var revision: Int
    init() {}
    init(sessionID: String, revision: Int) { self.sessionID = sessionID; self.revision = revision }
    func perform() async throws -> some IntentResult {
        try await changeLiveTimer(sessionID, action: "resume", revision: revision); return .result()
    }
}
@available(iOS 17.0, *)
struct FinishLiveTimerIntent: LiveActivityIntent {
    static var title: LocalizedStringResource { "Finish timer" }
    static var isDiscoverable: Bool { false }
    @Parameter(title: "Session") var sessionID: String
    @Parameter(title: "Revision") var revision: Int
    init() {}
    init(sessionID: String, revision: Int = 0) { self.sessionID = sessionID; self.revision = revision }
    func perform() async throws -> some IntentResult {
        try await changeLiveTimer(sessionID, action: "finish", revision: revision); return .result()
    }
}
@available(iOS 17.0, *)
struct FinishLivePumpingIntent: LiveActivityIntent {
    static var title: LocalizedStringResource { "Finish pumping" }
    static var isDiscoverable: Bool { false }
    @available(iOS, deprecated: 26.0) static var openAppWhenRun: Bool { true }
    @available(iOS 26.0, *) static var supportedModes: IntentModes { .foreground }
    @Parameter(title: "Session") var sessionID: String
    @Parameter(title: "Revision") var revision: Int
    @Parameter(title: "Action") var action: String
    init() {}
    init(sessionID: String, revision: Int = 0, action: String = "finish") {
        self.sessionID = sessionID; self.revision = revision; self.action = action
    }
    func perform() async throws -> some IntentResult {
        try await changeLiveTimer(sessionID, action: action, revision: revision); return .result()
    }
}
