import AppIntents
import Flutter
import UIKit
import ActivityKit
import AuthenticationServices
import CryptoKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate, ASWebAuthenticationPresentationContextProviding {
  private var liveTimerObserver: NSObjectProtocol?
  private var pickerSession: ASWebAuthenticationSession?
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    if #available(iOS 16.0, *) { LittleLogShortcuts.updateAppShortcutParameters() }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    guard let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "LittleLogLiveActivity") else { return }
    let siri = FlutterMethodChannel(name: "app.littlelog/siri", binaryMessenger: registrar.messenger())
    Task { @MainActor in SiriRequestBridge.shared.channel = siri }
    siri.setMethodCallHandler { call, result in
      Task { @MainActor in
        switch call.method {
        case "listen": result(SiriRequestBridge.shared.startListening())
        case "complete":
          guard let args = call.arguments as? [String: Any], let id = args["id"] as? String else {
            result(FlutterError(code: "siri_request", message: "Invalid Siri response.", details: nil)); return
          }
          result(SiriRequestBridge.shared.complete(id: id, message: args["message"] as? String, error: args["error"] as? String))
        default: result(FlutterMethodNotImplemented)
        }
      }
    }
    let quickActions = FlutterMethodChannel(name: "app.littlelog/quick_actions", binaryMessenger: registrar.messenger())
    HomeQuickActionBridge.shared.channel = quickActions
    quickActions.setMethodCallHandler { call, result in
      if call.method == "listen" {
        result(HomeQuickActionBridge.shared.startListening())
      } else {
        result(FlutterMethodNotImplemented)
      }
    }
    let picker = FlutterMethodChannel(name: "app.littlelog/picker", binaryMessenger: registrar.messenger())
    picker.setMethodCallHandler { [weak self] call, result in
      guard call.method == "pickFamily" else { result(FlutterMethodNotImplemented); return }
      guard let args = call.arguments as? [String: String],
            let clientID = args["clientId"], let email = args["email"], !email.isEmpty else {
        result(FlutterError(code: "account", message: "Sign in first.", details: nil)); return
      }
      self?.openDrivePicker(clientID: clientID, email: email, requestedFileID: args["fileId"], result: result)
    }
    let invitations = FlutterMethodChannel(name: "app.littlelog/invitation", binaryMessenger: registrar.messenger())
    InvitationLinkBridge.shared.channel = invitations
    invitations.setMethodCallHandler { call, result in
      switch call.method {
      case "listen":
        result(InvitationLinkBridge.shared.startListening())
      case "share":
        guard let args = call.arguments as? [String: String],
              let message = args["message"], !message.isEmpty else {
          result(FlutterError(code: "share_empty", message: "There is no invitation to share.", details: nil)); return
        }
        guard let presenter = UIApplication.shared.connectedScenes
          .compactMap({ $0 as? UIWindowScene })
          .flatMap({ $0.windows }).first(where: { $0.isKeyWindow })?.rootViewController else {
          result(FlutterError(code: "share_unavailable", message: "The share sheet could not open.", details: nil)); return
        }
        let sheet = UIActivityViewController(activityItems: [message], applicationActivities: nil)
        sheet.popoverPresentationController?.sourceView = presenter.view
        presenter.present(sheet, animated: true)
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    let channel = FlutterMethodChannel(name: "little_log/live_activity", binaryMessenger: registrar.messenger())
    liveTimerObserver = NotificationCenter.default.addObserver(forName: LiveTimerStopStore.changed, object: nil, queue: .main) { _ in
      channel.invokeMethod("stopped", arguments: nil)
    }
    channel.setMethodCallHandler { call, result in
      do {
        if call.method == "pendingStops" {
          result(try LiveTimerStopStore.shared.pending().map { $0.payload }); return
        }
        if call.method == "acknowledgeStop", let id = call.arguments as? String {
          try LiveTimerStopStore.shared.acknowledge(id); result(nil); return
        }
      } catch {
        result(FlutterError(code: "live_timer_storage", message: "Could not read or save the stopped timer. Reopen Little Log.", details: nil)); return
      }
      guard call.method == "update" else { result(FlutterMethodNotImplemented); return }
      guard #available(iOS 16.2, *) else { result(nil); return }
      let requestedSessions = call.arguments as? [[String: Any]] ?? []
      let sessions = requestedSessions
      Task { @MainActor in
        let ids = Set(sessions.compactMap { $0["id"] as? String })
        for activity in Activity<TimerAttributes>.activities where !ids.contains(activity.attributes.sessionID) {
          await activity.end(nil, dismissalPolicy: .immediate)
        }
        do {
          for session in sessions {
            guard let id = session["id"] as? String,
                  let title = session["title"] as? String,
                  let timestamp = session["startedAt"] as? Double,
                  let detail = session["detail"] as? String else { continue }
            var state = TimerAttributes.ContentState(method: session["method"] as? String, title: title,
                startedAt: Date(timeIntervalSince1970: timestamp), detail: detail,
                phase: session["phase"] as? String, elapsedSeconds: session["elapsedSeconds"] as? Double,
                revision: session["revision"] as? Int)
            state = try LiveTimerStopStore.shared.resolvedState(id, observed: state)
            if state.currentPhase == "finished" {
              if let existing = Activity<TimerAttributes>.activities.first(where: { $0.attributes.sessionID == id }) {
                await existing.end(nil, dismissalPolicy: .immediate)
              }
              continue
            }
            let content = ActivityContent(state: state, staleDate: nil)
            let existing = Activity<TimerAttributes>.activities.first(where: { $0.attributes.sessionID == id })
            if let activity = existing, activity.attributes.familyID == session["familyId"] as? String {
              await activity.update(content)
            } else if ActivityAuthorizationInfo().areActivitiesEnabled {
              if let activity = existing { await activity.end(nil, dismissalPolicy: .immediate) }
              _ = try Activity.request(attributes: TimerAttributes(familyID: session["familyId"] as? String, sessionID: id), content: content, pushType: nil)
            }
          }
          result(nil)
        } catch { result(FlutterError(code: "live_activity", message: error.localizedDescription, details: nil)) }
      }
    }
  }
  func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
    return UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
      .flatMap { $0.windows }.first { $0.isKeyWindow } ?? ASPresentationAnchor()
  }

  private func openDrivePicker(clientID: String, email: String, requestedFileID: String?, result: @escaping FlutterResult) {
    guard pickerSession == nil else {
      result(FlutterError(code: "busy", message: "Google Drive is already open.", details: nil)); return
    }
    let verifier = UUID().uuidString + UUID().uuidString
    let state = UUID().uuidString
    let challenge = Data(SHA256.hash(data: Data(verifier.utf8))).base64EncodedString()
      .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
      .replacingOccurrences(of: "=", with: "")
    let scheme = clientID.components(separatedBy: ".").reversed().joined(separator: ".")
    let redirect = "\(scheme):/oauthredirect"
    var url = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
    var queryItems = [
      "client_id": clientID, "redirect_uri": redirect, "response_type": "code",
      "scope": "https://www.googleapis.com/auth/drive.file", "prompt": "consent",
      "trigger_onepick": "true", "allow_multiple": "false", "login_hint": email,
      "mimetypes": "text/csv,application/csv", "state": state,
      "code_challenge": challenge, "code_challenge_method": "S256"
    ].map { URLQueryItem(name: $0.key, value: $0.value) }
    if let fileID = requestedFileID, !fileID.isEmpty {
      queryItems.append(URLQueryItem(name: "file_ids", value: fileID))
    }
    url.queryItems = queryItems
    pickerSession = ASWebAuthenticationSession(url: url.url!, callbackURLScheme: scheme) { [weak self] callback, error in
      DispatchQueue.main.async {
        self?.pickerSession = nil
        if let authError = error as? ASWebAuthenticationSessionError, authError.code == .canceledLogin {
          result(nil); return
        }
        guard error == nil, let callback = callback,
              let items = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems else {
          result(FlutterError(code: "picker_failed", message: "Google Drive could not be opened. Please try again.", details: nil)); return
        }
        func item(_ key: String) -> String? { items.first { $0.name == key }?.value }
        guard item("state") == state else {
          result(FlutterError(code: "picker_state", message: "Google authorization could not be verified. Please try again.", details: nil)); return
        }
        if item("error") == "access_denied" { result(nil); return }
        guard let code = item("code"),
              let fileID = item("picked_file_ids")?.components(separatedBy: ",").first, !fileID.isEmpty else {
          result(FlutterError(code: "picker_empty", message: "No log was selected. Choose the shared Little Log file in Google Drive.", details: nil)); return
        }
        if let requestedID = requestedFileID, fileID != requestedID {
          result(FlutterError(code: "picker_wrong_file", message: "That is a different Drive file. Open the invitation link from the sender and try again.", details: nil)); return
        }
        var request = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var form = URLComponents()
        form.queryItems = ["client_id": clientID, "code": code, "code_verifier": verifier,
                           "redirect_uri": redirect, "grant_type": "authorization_code"]
          .map { URLQueryItem(name: $0.key, value: $0.value) }
        request.httpBody = form.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B").data(using: .utf8)
        URLSession.shared.dataTask(with: request) { data, response, error in
          let json = data.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
          DispatchQueue.main.async {
            guard error == nil, (response as? HTTPURLResponse)?.statusCode == 200,
                  let token = json?["access_token"] as? String else {
              result(FlutterError(code: "picker_token", message: "Google could not finish granting access. Please try again.", details: nil)); return
            }
            result(["fileId": fileID, "accessToken": token])
          }
        }.resume()
      }
    }
    pickerSession?.presentationContextProvider = self
    if pickerSession?.start() != true {
      pickerSession = nil
      result(FlutterError(code: "picker_start", message: "Google Drive could not be opened. Please try again.", details: nil))
    }
  }

}
