import AppIntents
import Flutter
import Foundation

struct SiriActionFailure: LocalizedError {
  let message: String
  var errorDescription: String? { message }
}

/// Keeps cold-launch requests until Dart is ready and awaits the answer or durable write.
@MainActor
final class SiriRequestBridge {
  static let shared = SiriRequestBridge()
  var channel: FlutterMethodChannel?
  private var listening = false
  private let timeoutNanoseconds: UInt64
  init(timeoutNanoseconds: UInt64 = 20_000_000_000) { self.timeoutNanoseconds = timeoutNanoseconds }
  private struct Pending {
    let payload: [String: Any]
    let continuation: CheckedContinuation<String, Error>
    let timeout: Task<Void, Never>
  }
  private var pending: [String: Pending] = [:]

  func request(action: String, kind: String? = nil, amount: Double? = nil, unit: String? = nil) async throws -> String {
    let id = UUID().uuidString
    return try await withTaskCancellationHandler {
      try Task.checkCancellation()
      return try await withCheckedThrowingContinuation { continuation in
        let now = Date()
        var payload: [String: Any] = [
          "id": id, "action": action,
          "at": Int64(now.timeIntervalSince1970 * 1000),
          "deadline": Int64(now.addingTimeInterval(15).timeIntervalSince1970 * 1000)
        ]
        if let kind { payload["kind"] = kind }
        if let amount { payload["amount"] = amount }
        if let unit { payload["unit"] = unit }
        let timeout = Task { @MainActor [weak self] in
          do { try await Task.sleep(nanoseconds: self?.timeoutNanoseconds ?? 20_000_000_000) }
          catch { return }
          self?.fail(id: id, message: "Little Log did not finish the request. Open the app and try again.")
        }
        pending[id] = Pending(payload: payload, continuation: continuation, timeout: timeout)
        if listening, let channel { channel.invokeMethod("received", arguments: payload) }
      }
    } onCancel: {
      Task { @MainActor [weak self] in
        self?.fail(id: id, message: "The Siri request was cancelled.")
      }
    }
  }

  func startListening() -> [[String: Any]] {
    listening = true
    return pending.values.map(\.payload).sorted {
      ($0["at"] as? Int64 ?? 0) < ($1["at"] as? Int64 ?? 0)
    }
  }

  @discardableResult
  func complete(id: String, message: String?, error: String?) -> Bool {
    guard let request = pending.removeValue(forKey: id) else { return false }
    request.timeout.cancel()
    if let error {
      request.continuation.resume(throwing: SiriActionFailure(message: error))
    } else if let message, !message.isEmpty {
      request.continuation.resume(returning: message)
    } else {
      request.continuation.resume(throwing: SiriActionFailure(message: "Little Log could not confirm the action."))
    }
    return true
  }

  private func fail(id: String, message: String) {
    if complete(id: id, message: nil, error: message) {
      channel?.invokeMethod("cancelled", arguments: id)
    }
  }
}

@available(iOS 16.0, *)
enum SiriDiaperKind: String, AppEnum {
  case wet, dirty, both, dry
  static var typeDisplayRepresentation: TypeDisplayRepresentation { "Diaper type" }
  static var caseDisplayRepresentations: [SiriDiaperKind: DisplayRepresentation] {
    [.wet: "wet", .dirty: "dirty", .both: "wet and dirty", .dry: "dry"]
  }
}

@available(iOS 16.0, *)
enum SiriNursingSide: String, AppEnum {
  case left, right
  static var typeDisplayRepresentation: TypeDisplayRepresentation { "Nursing side" }
  static var caseDisplayRepresentations: [SiriNursingSide: DisplayRepresentation] {
    [.left: "left", .right: "right"]
  }
}

@available(iOS 16.0, *)
struct AddDiaperIntent: AppIntent {
  static var title: LocalizedStringResource { "Add a diaper" }
  static var description: IntentDescription {
    "Record a diaper now for the baby currently selected in Little Log."
  }
  @available(iOS, deprecated: 26.0)
  static var openAppWhenRun: Bool { true }
  @available(iOS 26.0, *)
  static var supportedModes: IntentModes { .foreground }
  static var authenticationPolicy: IntentAuthenticationPolicy { .requiresAuthentication }
  @Parameter(title: "Diaper type") var kind: SiriDiaperKind
  static var parameterSummary: some ParameterSummary { Summary("Add a \(\.$kind) diaper") }

  @MainActor
  func perform() async throws -> some IntentResult & ProvidesDialog {
    let message = try await SiriRequestBridge.shared.request(action: "add_diaper", kind: kind.rawValue)
    return .result(dialog: IntentDialog(stringLiteral: message))
  }
}

@available(iOS 16.0, *)
struct StartNursingIntent: AppIntent {
  static var title: LocalizedStringResource { "Start nursing" }
  static var description: IntentDescription {
    "Start nursing on the left or right side for the selected baby. An active timer continues unchanged."
  }
  @available(iOS, deprecated: 26.0)
  static var openAppWhenRun: Bool { true }
  @available(iOS 26.0, *)
  static var supportedModes: IntentModes { .foreground }
  static var authenticationPolicy: IntentAuthenticationPolicy { .requiresAuthentication }
  @Parameter(title: "Side") var side: SiriNursingSide
  static var parameterSummary: some ParameterSummary { Summary("Start nursing on the \(\.$side) side") }

  @MainActor
  func perform() async throws -> some IntentResult & ProvidesDialog {
    let message = try await SiriRequestBridge.shared.request(action: "nursing_\(side.rawValue)")
    return .result(dialog: IntentDialog(stringLiteral: message))
  }
}

@available(iOS 16.0, *)
struct StartSleepIntent: AppIntent {
  static var title: LocalizedStringResource { "Start sleep" }
  static var description: IntentDescription { "Start sleep for the baby currently selected in Little Log." }
  @available(iOS, deprecated: 26.0)
  static var openAppWhenRun: Bool { true }
  @available(iOS 26.0, *)
  static var supportedModes: IntentModes { .foreground }
  static var authenticationPolicy: IntentAuthenticationPolicy { .requiresAuthentication }

  @MainActor
  func perform() async throws -> some IntentResult & ProvidesDialog {
    let message = try await SiriRequestBridge.shared.request(action: "sleep")
    return .result(dialog: IntentDialog(stringLiteral: message))
  }
}

@available(iOS 16.0, *)
enum SiriVolumeUnit: String, AppEnum {
  case ml, oz
  static var typeDisplayRepresentation: TypeDisplayRepresentation { "Volume unit" }
  static var caseDisplayRepresentations: [SiriVolumeUnit: DisplayRepresentation] {
    [.ml: "milliliters", .oz: "US fluid ounces"]
  }
}

@available(iOS 16.0, *)
struct StartPumpingIntent: AppIntent {
  static var title: LocalizedStringResource { "Start pumping" }
  static var description: IntentDescription { "Start pumping for the selected baby. An active timer continues unchanged." }
  @available(iOS, deprecated: 26.0)
  static var openAppWhenRun: Bool { true }
  @available(iOS 26.0, *)
  static var supportedModes: IntentModes { .foreground }
  static var authenticationPolicy: IntentAuthenticationPolicy { .requiresAuthentication }

  @MainActor
  func perform() async throws -> some IntentResult & ProvidesDialog {
    let message = try await SiriRequestBridge.shared.request(action: "pumping")
    return .result(dialog: IntentDialog(stringLiteral: message))
  }
}

@available(iOS 16.0, *)
struct FinishSleepIntent: AppIntent {
  static var title: LocalizedStringResource { "Finish sleep" }
  static var description: IntentDescription { "Stop and save the selected baby's active sleep timer." }
  @available(iOS, deprecated: 26.0)
  static var openAppWhenRun: Bool { true }
  @available(iOS 26.0, *)
  static var supportedModes: IntentModes { .foreground }
  static var authenticationPolicy: IntentAuthenticationPolicy { .requiresAuthentication }

  @MainActor
  func perform() async throws -> some IntentResult & ProvidesDialog {
    let message = try await SiriRequestBridge.shared.request(action: "finish_sleep")
    return .result(dialog: IntentDialog(stringLiteral: message))
  }
}

@available(iOS 16.0, *)
struct FinishNursingIntent: AppIntent {
  static var title: LocalizedStringResource { "Finish nursing" }
  static var description: IntentDescription { "Stop and save the selected baby's nursing session, keeping time on both sides." }
  @available(iOS, deprecated: 26.0)
  static var openAppWhenRun: Bool { true }
  @available(iOS 26.0, *)
  static var supportedModes: IntentModes { .foreground }
  static var authenticationPolicy: IntentAuthenticationPolicy { .requiresAuthentication }

  @MainActor
  func perform() async throws -> some IntentResult & ProvidesDialog {
    let message = try await SiriRequestBridge.shared.request(action: "finish_nursing")
    return .result(dialog: IntentDialog(stringLiteral: message))
  }
}

@available(iOS 16.0, *)
struct FinishPumpingIntent: AppIntent {
  static var title: LocalizedStringResource { "Finish pumping" }
  static var description: IntentDescription { "Stop and save the selected baby's pumping timer with the pumped amount." }
  @available(iOS, deprecated: 26.0)
  static var openAppWhenRun: Bool { true }
  @available(iOS 26.0, *)
  static var supportedModes: IntentModes { .foreground }
  static var authenticationPolicy: IntentAuthenticationPolicy { .requiresAuthentication }
  @Parameter(title: "Pumped amount") var amount: Double
  @Parameter(title: "Unit") var unit: SiriVolumeUnit
  static var parameterSummary: some ParameterSummary {
    Summary("Finish pumping with \(\.$amount) \(\.$unit)")
  }

  @MainActor
  func perform() async throws -> some IntentResult & ProvidesDialog {
    let message = try await SiriRequestBridge.shared.request(action: "finish_pumping", amount: amount, unit: unit.rawValue)
    return .result(dialog: IntentDialog(stringLiteral: message))
  }
}

@available(iOS 16.0, *)
enum SiriHistoryActivity: String, AppEnum {
  case diaper = "last_diaper", wetDiaper = "last_wet_diaper", dirtyDiaper = "last_dirty_diaper"
  case feed = "last_feed", bottle = "last_bottle", nursing = "last_nursing"
  case solids = "last_solids", sleep = "last_sleep", wake = "last_wake", pumping = "last_pumping"
  static var typeDisplayRepresentation: TypeDisplayRepresentation { "Activity" }
  static let caseDisplayRepresentations: [SiriHistoryActivity: DisplayRepresentation] = [
    .diaper: "diaper", .wetDiaper: "wet diaper", .dirtyDiaper: "dirty diaper",
    .feed: "feed", .bottle: "bottle", .nursing: "nursing session", .solids: "solids meal",
    .sleep: "sleep", .wake: "wake up", .pumping: "pumping session"
  ]
}

@available(iOS 16.0, *)
struct LastActivityIntent: AppIntent {
  static var title: LocalizedStringResource { "Last activity" }
  static var description: IntentDescription { "Find the selected baby's last activity without changing any logs." }
  @available(iOS, deprecated: 26.0)
  static var openAppWhenRun: Bool { true }
  @available(iOS 26.0, *)
  static var supportedModes: IntentModes { .foreground }
  static var authenticationPolicy: IntentAuthenticationPolicy { .requiresAuthentication }
  @Parameter(title: "Activity", default: .feed) var activity: SiriHistoryActivity
  static var parameterSummary: some ParameterSummary { Summary("When was the last \(\.$activity)?") }

  @MainActor
  func perform() async throws -> some IntentResult & ProvidesDialog {
    let message = try await SiriRequestBridge.shared.request(action: activity.rawValue)
    return .result(dialog: IntentDialog(stringLiteral: message))
  }
}

@available(iOS 16.0, *)
struct LastWakeIntent: AppIntent {
  static var title: LocalizedStringResource { "Last wake-up" }
  static var description: IntentDescription { "Find the selected baby's last recorded sleep end time." }
  @available(iOS, deprecated: 26.0)
  static var openAppWhenRun: Bool { true }
  @available(iOS 26.0, *)
  static var supportedModes: IntentModes { .foreground }
  static var authenticationPolicy: IntentAuthenticationPolicy { .requiresAuthentication }

  @MainActor
  func perform() async throws -> some IntentResult & ProvidesDialog {
    let message = try await SiriRequestBridge.shared.request(action: "last_wake")
    return .result(dialog: IntentDialog(stringLiteral: message))
  }
}

@available(iOS 16.0, *)
struct SleepStatusIntent: AppIntent {
  static var title: LocalizedStringResource { "Sleep status" }
  static var description: IntentDescription { "Check the selected baby's active sleep timer." }
  @available(iOS, deprecated: 26.0)
  static var openAppWhenRun: Bool { true }
  @available(iOS 26.0, *)
  static var supportedModes: IntentModes { .foreground }
  static var authenticationPolicy: IntentAuthenticationPolicy { .requiresAuthentication }

  @MainActor
  func perform() async throws -> some IntentResult & ProvidesDialog {
    let message = try await SiriRequestBridge.shared.request(action: "sleep_status")
    return .result(dialog: IntentDialog(stringLiteral: message))
  }
}

@available(iOS 16.0, *)
struct LittleLogShortcuts: AppShortcutsProvider {
  static var appShortcuts: [AppShortcut] {
    AppShortcut(
      intent: AddDiaperIntent(),
      phrases: [
        "Add a \(\.$kind) diaper in \(.applicationName)",
        "Log a \(\.$kind) diaper in \(.applicationName)",
        "Record a \(\.$kind) diaper in \(.applicationName)",
        "Add a diaper in \(.applicationName)"
      ],
      shortTitle: "Add diaper", systemImageName: "plus.circle"
    )
    AppShortcut(
      intent: StartNursingIntent(),
      phrases: [
        "Start nursing on the \(\.$side) side in \(.applicationName)",
        "Start \(\.$side) nursing in \(.applicationName)",
        "Start nursing in \(.applicationName)"
      ],
      shortTitle: "Start nursing", systemImageName: "heart"
    )
    AppShortcut(
      intent: StartSleepIntent(),
      phrases: ["Start sleep in \(.applicationName)", "Start a nap in \(.applicationName)"],
      shortTitle: "Start sleep", systemImageName: "moon"
    )
    AppShortcut(
      intent: StartPumpingIntent(),
      phrases: ["Start pumping in \(.applicationName)"],
      shortTitle: "Start pumping", systemImageName: "drop"
    )
    AppShortcut(
      intent: FinishSleepIntent(),
      phrases: ["Finish sleep in \(.applicationName)", "Stop sleep in \(.applicationName)", "End sleep in \(.applicationName)"],
      shortTitle: "Finish sleep", systemImageName: "moon"
    )
    AppShortcut(
      intent: FinishNursingIntent(),
      phrases: ["Finish nursing in \(.applicationName)", "Stop nursing in \(.applicationName)", "End nursing in \(.applicationName)"],
      shortTitle: "Finish nursing", systemImageName: "heart"
    )
    AppShortcut(
      intent: FinishPumpingIntent(),
      phrases: ["Finish pumping in \(.applicationName)", "Stop pumping in \(.applicationName)", "End pumping in \(.applicationName)"],
      shortTitle: "Finish pumping", systemImageName: "drop"
    )
    AppShortcut(
      intent: LastActivityIntent(),
      phrases: [
        "When was the last \(\.$activity) in \(.applicationName)",
        "How long since the last \(\.$activity) in \(.applicationName)",
        "Show the last \(\.$activity) in \(.applicationName)",
        "When did my baby last eat in \(.applicationName)",
        "When was my baby last fed in \(.applicationName)"
      ],
      shortTitle: "Last activity", systemImageName: "clock"
    )
    AppShortcut(
      intent: LastWakeIntent(),
      phrases: [
        "When did my baby last wake up in \(.applicationName)",
        "When did the baby wake up in \(.applicationName)",
        "How long has my baby been awake in \(.applicationName)"
      ],
      shortTitle: "Last wake-up", systemImageName: "sun.max"
    )
    AppShortcut(
      intent: SleepStatusIntent(),
      phrases: [
        "Is my baby asleep in \(.applicationName)",
        "Is the baby sleeping in \(.applicationName)",
        "How long has my baby been asleep in \(.applicationName)"
      ],
      shortTitle: "Sleep status", systemImageName: "moon.zzz"
    )
  }
}
