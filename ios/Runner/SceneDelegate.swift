import Flutter
import UIKit

final class InvitationLinkBridge {
  static let shared = InvitationLinkBridge()
  var channel: FlutterMethodChannel?
  private var pendingLink: String?
  private var listening = false

  func receive(_ url: URL) {
    guard url.scheme == "littlelog", url.host == "join" else { return }
    if listening, let channel {
      channel.invokeMethod("received", arguments: url.absoluteString)
    } else {
      pendingLink = url.absoluteString
    }
  }

  func startListening() -> String? {
    listening = true
    let link = pendingLink
    pendingLink = nil
    return link
  }
}

final class HomeQuickActionBridge {
  static let shared = HomeQuickActionBridge()
  private let actions: Set<String> = ["diaper", "nursing_left", "nursing_right", "sleep"]
  var channel: FlutterMethodChannel?
  private var pendingAction: String?
  private var listening = false

  @discardableResult
  func receive(_ action: String) -> Bool {
    guard actions.contains(action) else { return false }
    if listening, let channel {
      channel.invokeMethod("received", arguments: action)
    } else {
      pendingAction = action
    }
    return true
  }

  func startListening() -> String? {
    listening = true
    let action = pendingAction
    pendingAction = nil
    return action
  }
}

class SceneDelegate: FlutterSceneDelegate {
  override func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
    if let shortcut = connectionOptions.shortcutItem {
      HomeQuickActionBridge.shared.receive(shortcut.type)
    }
    for context in connectionOptions.urlContexts {
      InvitationLinkBridge.shared.receive(context.url)
    }
    super.scene(scene, willConnectTo: session, options: connectionOptions)
  }

  override func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
    for context in URLContexts {
      InvitationLinkBridge.shared.receive(context.url)
    }
    super.scene(scene, openURLContexts: URLContexts)
  }
  override func windowScene(_ windowScene: UIWindowScene,
                            performActionFor shortcutItem: UIApplicationShortcutItem,
                            completionHandler: @escaping (Bool) -> Void) {
    completionHandler(HomeQuickActionBridge.shared.receive(shortcutItem.type))
  }

}
