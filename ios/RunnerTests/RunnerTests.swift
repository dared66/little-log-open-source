import XCTest
import ActivityKit
@testable import Runner

@MainActor
class RunnerTests: XCTestCase {
  func testNursingSwitchKeepsClockAndSideAcrossPauseResumeAndQueuedRetries() throws {
    guard #available(iOS 17.0, *) else { throw XCTSkip("Requires iOS 17") }
    let start = Date().addingTimeInterval(-600)
    let initial = TimerAttributes.ContentState(method: "nursing", title: "Synthetic QA · Nursing",
      startedAt: start, detail: "Left side running", phase: "running", elapsedSeconds: 0, revision: 0)
    let switched = try XCTUnwrap(initial.applying(action: "switch", at: start.addingTimeInterval(60), expectedRevision: 0))
    XCTAssertEqual(switched.side, "right")
    XCTAssertEqual(switched.detail, "Right side running")
    XCTAssertEqual(switched.startedAt, start)
    XCTAssertEqual(switched.elapsed(at: start.addingTimeInterval(90)), 90)
    XCTAssertNil(switched.applying(action: "switch", at: start.addingTimeInterval(90), expectedRevision: 0))
    let paused = try XCTUnwrap(switched.applying(action: "pause", at: start.addingTimeInterval(120), expectedRevision: 1))
    XCTAssertNil(paused.applying(action: "switch", at: start.addingTimeInterval(150), expectedRevision: 2))
    let restored = try JSONDecoder().decode(TimerAttributes.ContentState.self, from: JSONEncoder().encode(paused))
    let resumed = try XCTUnwrap(restored.applying(action: "resume", at: start.addingTimeInterval(180), expectedRevision: 2))
    XCTAssertEqual(resumed.detail, "Right side running")
    let back = try XCTUnwrap(resumed.applying(action: "switch", at: start.addingTimeInterval(240), expectedRevision: 3))
    XCTAssertEqual(back.side, "left")
    XCTAssertEqual(back.elapsed(at: start.addingTimeInterval(240)), 180)
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let file = directory.appendingPathComponent("switch.json")
    let store = LiveTimerStopStore(file: file)
    try store.append(LiveTimerStop(id: "request", familyId: "synthetic", method: "nursing",
      stoppedAt: Int64(start.addingTimeInterval(60).timeIntervalSince1970 * 1000), sessionId: "session", action: "switch", revision: 0))
    let queued = try LiveTimerStopStore(file: file).resolvedState("session", observed: initial)
    XCTAssertEqual(queued.side, "right")
    XCTAssertEqual(try store.resolvedState("session", observed: queued).revision, 1)
    let sleep = TimerAttributes.ContentState(method: "sleep", title: "Sleep", startedAt: start, detail: "Sleeping")
    XCTAssertNil(sleep.applying(action: "switch", at: Date(), expectedRevision: 0))
  }

  func testPausedStateStaysLiveAndTransitionsRejectStaleFinish() throws {
    guard #available(iOS 17.0, *) else { throw XCTSkip("Requires iOS 17") }
    let start = Date().addingTimeInterval(-600)
    let initial = TimerAttributes.ContentState(method: "pumping", title: "Synthetic QA · Pumping", startedAt: start, detail: "Timer running", phase: "running", elapsedSeconds: 0, revision: 0)
    XCTAssertNil(initial.applying(action: "finish", at: Date(), expectedRevision: 0))
    let paused = try XCTUnwrap(initial.applying(action: "pause", at: start.addingTimeInterval(120), expectedRevision: 0))
    XCTAssertEqual(paused.currentPhase, "paused")
    XCTAssertEqual(paused.elapsed(at: start.addingTimeInterval(300)), 120)
    let resumed = try XCTUnwrap(paused.applying(action: "resume", at: start.addingTimeInterval(300), expectedRevision: 1))
    XCTAssertNil(resumed.applying(action: "finish", at: start.addingTimeInterval(310), expectedRevision: 1))
    let pausedAgain = try XCTUnwrap(resumed.applying(action: "pause", at: start.addingTimeInterval(360), expectedRevision: 2))
    XCTAssertEqual(pausedAgain.elapsedSeconds, 180)
    let review = try XCTUnwrap(pausedAgain.applying(action: "finish", at: start.addingTimeInterval(500), expectedRevision: 3))
    XCTAssertEqual(review.currentPhase, "review")
    XCTAssertEqual(review.elapsedSeconds, 180)
    XCTAssertNil(review.applying(action: "resume", at: Date(), expectedRevision: 4))
  }

  @available(iOS 17.0, *)
  private func waitForPhase(_ activity: Activity<TimerAttributes>, _ phase: String) async throws {
    for _ in 0..<100 {
      if activity.content.state.currentPhase == phase { return }
      try await Task.sleep(nanoseconds: 20_000_000)
    }
    XCTFail("Live Activity did not publish \(phase)")
  }

  @available(iOS 17.0, *)
  private func waitForEnd(_ activity: Activity<TimerAttributes>) async throws {
    for _ in 0..<100 {
      if activity.activityState == .ended || activity.activityState == .dismissed { return }
      try await Task.sleep(nanoseconds: 20_000_000)
    }
    XCTFail("Live Activity did not end")
  }

  func testNativePauseKeepsTheLiveActivityAndResumeContinuesIt() async throws {
    guard #available(iOS 17.0, *), ActivityAuthorizationInfo().areActivitiesEnabled else { throw XCTSkip("Requires interactive Live Activities") }
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = LiveTimerStopStore(file: directory.appendingPathComponent("actions.json"))
    let id = UUID().uuidString
    let initial = TimerAttributes.ContentState(method: "nursing", title: "Synthetic QA · Nursing", startedAt: Date().addingTimeInterval(-60), detail: "Left side running", phase: "running", elapsedSeconds: 60, revision: 0)
    let activity = try Activity.request(attributes: TimerAttributes(familyID: "synthetic-qa", sessionID: id), content: ActivityContent(state: initial, staleDate: nil), pushType: nil)
    do {
      try await changeLiveTimer(id, action: "finish", revision: 0, store: store)
      XCTAssertTrue(try store.pending().isEmpty)
      try await changeLiveTimer(id, action: "pause", revision: 0, store: store)
      XCTAssertEqual(activity.activityState, .active)
      try await waitForPhase(activity, "paused")
      XCTAssertEqual(activity.content.state.currentPhase, "paused")
      let frozen = activity.content.state.elapsedSeconds
      try await changeLiveTimer(id, action: "resume", revision: 1, store: store)
      XCTAssertEqual(activity.activityState, .active)
      try await waitForPhase(activity, "running")
      XCTAssertEqual(activity.content.state.currentPhase, "running")
      try await changeLiveTimer(id, action: "finish", revision: 1, store: store)
      XCTAssertEqual(activity.content.state.currentPhase, "running")
      try await changeLiveTimer(id, action: "pause", revision: 2, store: store)
      try await waitForPhase(activity, "paused")
      XCTAssertGreaterThanOrEqual(activity.content.state.elapsedSeconds ?? 0, frozen ?? 0)
      try await changeLiveTimer(id, action: "finish", revision: 3, store: store)
      try await waitForEnd(activity)
      XCTAssertTrue(activity.activityState == .ended || activity.activityState == .dismissed)
      XCTAssertEqual(try store.pending().compactMap { $0.action }, ["pause", "resume", "pause", "finish"])
    } catch {
      await activity.end(nil, dismissalPolicy: .immediate); throw error
    }
  }

  func testLiveActivityFinishStopsTheShownSessionAndIgnoresStaleActions() async throws {
    guard #available(iOS 17.0, *) else { throw XCTSkip("Interactive Live Activities require iOS 17.") }
    guard ActivityAuthorizationInfo().areActivitiesEnabled else { throw XCTSkip("Live Activities are disabled on this QA device.") }
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = LiveTimerStopStore(file: directory.appendingPathComponent("stop.json"))
    let id = UUID().uuidString
    let start = Date().addingTimeInterval(-600)
    let state = TimerAttributes.ContentState(method: "sleep", title: "Synthetic QA · Sleep", startedAt: start, detail: "Sleeping")
    let activity = try Activity.request(attributes: TimerAttributes(familyID: "synthetic-qa", sessionID: id), content: ActivityContent(state: state, staleDate: nil), pushType: nil)
    do {
      let before = Int64(Date().timeIntervalSince1970 * 1000)
      try await stopLiveTimer(id, store: store)
      let request = try XCTUnwrap(store.pending().first)
      XCTAssertEqual(request.familyId, "synthetic-qa")
      XCTAssertEqual(request.method, "sleep")
      XCTAssertEqual(request.resolvedSessionID, id)
      XCTAssertGreaterThanOrEqual(request.stoppedAt, before)
      XCTAssertLessThanOrEqual(request.stoppedAt, Int64(Date().timeIntervalSince1970 * 1000))
      try await waitForEnd(activity)
      XCTAssertTrue(activity.activityState == .ended || activity.activityState == .dismissed)
      try await stopLiveTimer("stale-session", store: store)
      XCTAssertEqual(try store.pending(), [request])
    } catch {
      await activity.end(nil, dismissalPolicy: .immediate)
      throw error
    }
  }

  func testLiveTimerStopSurvivesRestartAndKeepsFirstTapTime() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let file = directory.appendingPathComponent("stops.json")
    let request = LiveTimerStop(id: "sleep-1", familyId: "baby-1", method: "sleep", stoppedAt: 123456)
    try LiveTimerStopStore(file: file).append(request)
    let reopened = LiveTimerStopStore(file: file)
    try reopened.append(LiveTimerStop(id: request.id, familyId: request.familyId, method: request.method, stoppedAt: 999999))
    XCTAssertEqual(try reopened.pending(), [request])
    try reopened.append(LiveTimerStop(id: "pump-2", familyId: "baby-2", method: "pumping", stoppedAt: 234567))
    try reopened.acknowledge(request.id)
    XCTAssertEqual(try LiveTimerStopStore(file: file).pending().map { $0.id }, ["pump-2"])
  }

  func testCorruptStopJournalIsNotSilentlyReplaced() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let file = directory.appendingPathComponent("stops.json")
    let damaged = Data("incomplete".utf8)
    try damaged.write(to: file)
    let store = LiveTimerStopStore(file: file)
    XCTAssertThrowsError(try store.append(LiveTimerStop(id: "id", familyId: "baby", method: "sleep", stoppedAt: 1)))
    XCTAssertEqual(try Data(contentsOf: file), damaged)
  }

  func testHistoryShortcutCatalogPreservesDefaultFeedAndAllQuestionKinds() throws {
    if #available(iOS 16.0, *) {
      XCTAssertEqual(LastActivityIntent().activity, .feed)
      XCTAssertEqual(Set(SiriHistoryActivity.allCases.map(\.rawValue)), Set([
        "last_diaper", "last_wet_diaper", "last_dirty_diaper", "last_feed", "last_bottle",
        "last_nursing", "last_solids", "last_sleep", "last_wake", "last_pumping"
      ]))
      XCTAssertEqual(LittleLogShortcuts.appShortcuts.count, 10)
    }
  }

  func testColdHistoryQuestionReturnsTheAnswerWithoutWriteParameters() async throws {
    let bridge = SiriRequestBridge()
    let task = Task { try await bridge.request(action: "last_diaper") }
    var payload: [String: Any]?
    for _ in 0..<20 {
      payload = bridge.startListening().first
      if payload != nil { break }
      await Task.yield()
    }
    let request = try XCTUnwrap(payload)
    XCTAssertEqual(request["action"] as? String, "last_diaper")
    XCTAssertNil(request["kind"])
    XCTAssertNil(request["amount"])
    let id = try XCTUnwrap(request["id"] as? String)
    XCTAssertTrue(bridge.complete(id: id, message: "No diaper changes are logged for Robin.", error: nil))
    let answer = try await task.value
    XCTAssertEqual(answer, "No diaper changes are logged for Robin.")
    XCTAssertTrue(bridge.startListening().isEmpty)
  }

  func testLauncherCatalogAndColdBridgeContainTheFourRequestedActions() throws {
    let shortcuts = try XCTUnwrap(Bundle.main.object(forInfoDictionaryKey: "UIApplicationShortcutItems") as? [[String: Any]])
    XCTAssertEqual(Set(shortcuts.compactMap { $0["UIApplicationShortcutItemType"] as? String }),
                   Set(["diaper", "nursing_left", "nursing_right", "sleep"]))
    for action in ["diaper", "nursing_left", "nursing_right", "sleep"] {
      let bridge = HomeQuickActionBridge()
      XCTAssertFalse(bridge.receive("pumping"))
      XCTAssertTrue(bridge.receive(action))
      XCTAssertEqual(bridge.startListening(), action)
      XCTAssertNil(bridge.startListening())
    }
  }

  func testPumpingParametersAndMissingConfirmationAreHandledHonestly() async throws {
    let bridge = SiriRequestBridge()
    let task = Task { try await bridge.request(action: "finish_pumping", amount: 2.5, unit: "oz") }
    var payload: [String: Any]?
    for _ in 0..<20 {
      payload = bridge.startListening().first
      if payload != nil { break }
      await Task.yield()
    }
    let request = try XCTUnwrap(payload)
    XCTAssertEqual(request["amount"] as? Double, 2.5)
    XCTAssertEqual(request["unit"] as? String, "oz")
    let at = try XCTUnwrap(request["at"] as? Int64)
    let deadline = try XCTUnwrap(request["deadline"] as? Int64)
    XCTAssertEqual(deadline - at, 15_000)
    let id = try XCTUnwrap(request["id"] as? String)
    XCTAssertTrue(bridge.complete(id: id, message: "", error: nil))
    do {
      _ = try await task.value
      XCTFail("An empty confirmation must not report success")
    } catch {
      XCTAssertTrue(error.localizedDescription.contains("could not confirm"))
    }
  }

  func testColdSiriRequestWaitsForDurableCompletionAndCompletesOnce() async throws {
    let bridge = SiriRequestBridge()
    let task = Task { try await bridge.request(action: "add_diaper", kind: "wet") }
    var payload: [String: Any]?
    for _ in 0..<20 {
      payload = bridge.startListening().first
      if payload != nil { break }
      await Task.yield()
    }
    let request = try XCTUnwrap(payload)
    let id = try XCTUnwrap(request["id"] as? String)
    XCTAssertEqual(request["action"] as? String, "add_diaper")
    XCTAssertEqual(request["kind"] as? String, "wet")
    XCTAssertTrue(bridge.complete(id: id, message: "Added a wet diaper for Robin.", error: nil))
    let message = try await task.value
    XCTAssertEqual(message, "Added a wet diaper for Robin.")
    XCTAssertFalse(bridge.complete(id: id, message: "duplicate", error: nil))
    XCTAssertTrue(bridge.startListening().isEmpty)
  }

  func testSiriFailureDoesNotBecomeSuccess() async throws {
    let bridge = SiriRequestBridge()
    let task = Task { try await bridge.request(action: "sleep") }
    var payload: [String: Any]?
    for _ in 0..<20 {
      payload = bridge.startListening().first
      if payload != nil { break }
      await Task.yield()
    }
    let id = try XCTUnwrap(payload?["id"] as? String)
    XCTAssertTrue(bridge.complete(id: id, message: nil, error: "Add a baby first."))
    do {
      _ = try await task.value
      XCTFail("A failed save must not report success")
    } catch {
      XCTAssertEqual(error.localizedDescription, "Add a baby first.")
    }
  }

  func testCancelledRequestIsRemoved() async throws {
    let bridge = SiriRequestBridge()
    let task = Task { try await bridge.request(action: "sleep") }
    for _ in 0..<20 {
      if !bridge.startListening().isEmpty { break }
      await Task.yield()
    }
    task.cancel()
    do {
      _ = try await task.value
      XCTFail("A cancelled request must not report success")
    } catch {
      XCTAssertTrue(bridge.startListening().isEmpty)
    }
  }

  func testTimedOutRequestIsRemoved() async throws {
    let bridge = SiriRequestBridge(timeoutNanoseconds: 1_000_000)
    do {
      _ = try await bridge.request(action: "sleep")
      XCTFail("A timed-out request must not report success")
    } catch {
      XCTAssertTrue(bridge.startListening().isEmpty)
      XCTAssertTrue(error.localizedDescription.contains("did not finish"))
    }
  }
}
