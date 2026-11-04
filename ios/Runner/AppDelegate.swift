import Flutter
import UIKit
import CallKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

    if !engineBridge.pluginRegistry.hasPlugin("QaraCallerIdPlugin"),
       let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "QaraCallerIdPlugin") {
      QaraCallerIdPlugin.register(with: registrar)
    }
  }
}

class QaraCallerIdPlugin: NSObject, FlutterPlugin {
  private static let channelName = "com.mode.qara/caller_id"
  private static let extensionIdentifier = "com.kobe.qara.CallDirectoryExtension"
  private static let appGroupId = "group.com.mode.qara"
  private static let directoryFileName = "contacts_directory.json"

  private static var isRegistered = false

  static func register(with registrar: FlutterPluginRegistrar) {
    guard !isRegistered else { return }
    isRegistered = true

    let channel = FlutterMethodChannel(name: channelName, binaryMessenger: registrar.messenger())
    let instance = QaraCallerIdPlugin()
    registrar.addMethodCallDelegate(instance, channel: channel)
    NSLog("[Qara] QaraCallerIdPlugin registered successfully on channel: %@", channelName)
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "isCallScreeningRoleHeld":
      CXCallDirectoryManager.sharedInstance.getEnabledStatusForExtension(
        withIdentifier: Self.extensionIdentifier
      ) { (status, error) in
        DispatchQueue.main.async {
          if let _ = error {
            result(false)
          } else {
            result(status == .enabled)
          }
        }
      }

    case "requestCallScreeningRole", "openAppSettings":
      // Open iOS Settings so user can navigate to Phone -> Call Blocking & Identification
      if let settingsURL = URL(string: UIApplication.openSettingsURLString),
         UIApplication.shared.canOpenURL(settingsURL) {
        UIApplication.shared.open(settingsURL, options: [:]) { _ in
          result(true)
        }
      } else {
        result(false)
      }

    case "isOverlayPermissionGranted":
      // Android-specific floating overlay permission; iOS uses system CallKit instead
      result(true)

    case "requestOverlayPermission":
      result(true)

    case "syncContactsToCallDirectory":
      guard let contacts = call.arguments as? [[String: Any]] else {
        result(false)
        return
      }
      syncContacts(contacts: contacts, result: result)

    case "shareText":
      guard let text = call.arguments as? String else {
        result(false)
        return
      }
      DispatchQueue.main.async {
        guard let topController = self.getTopViewController() else {
          NSLog("[Qara] ERROR: Could not find active UIViewController for share sheet")
          result(false)
          return
        }

        let activityVC = UIActivityViewController(activityItems: [text], applicationActivities: nil)
        if let popover = activityVC.popoverPresentationController {
          popover.sourceView = topController.view
          popover.sourceRect = CGRect(
            x: topController.view.bounds.midX,
            y: topController.view.bounds.midY,
            width: 0,
            height: 0
          )
          popover.permittedArrowDirections = []
        }
        topController.present(activityVC, animated: true, completion: nil)
        result(true)
      }

    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func getTopViewController() -> UIViewController? {
    let scenes = UIApplication.shared.connectedScenes
      .compactMap { $0 as? UIWindowScene }
    for scene in scenes {
      if let window = scene.windows.first(where: { $0.isKeyWindow }) ?? scene.windows.first {
        var top = window.rootViewController
        while let presented = top?.presentedViewController {
          top = presented
        }
        return top
      }
    }
    return nil
  }

  private func syncContacts(contacts: [[String: Any]], result: @escaping FlutterResult) {
    guard let containerURL = FileManager.default.containerURL(
      forSecurityApplicationGroupIdentifier: Self.appGroupId
    ) else {
      NSLog("[Qara] App Group containerURL is nil for %@", Self.appGroupId)
      result(false)
      return
    }

    var entries: [QaraDirectoryEntry] = []

    for contact in contacts {
      let rawNormalized = (contact["normalizedPhone"] as? String) ?? ""
      let rawPhone = (contact["phone"] as? String) ?? ""

      // Clean all non-digit characters
      var digits = rawNormalized.filter { $0.isNumber }
      if digits.isEmpty {
        digits = rawPhone.filter { $0.isNumber }
      }

      // Convert 10-digit Ghanaian local number (024... or 055...) to international 233...
      if digits.hasPrefix("0") && digits.count == 10 {
        digits = "233" + String(digits.dropFirst())
      } else if digits.hasPrefix("00233") {
        digits = String(digits.dropFirst(2))
      } else if digits.hasPrefix("233") && digits.count == 12 {
        // Standard full international format without plus
      } else if digits.count == 9 && !digits.hasPrefix("0") {
        // Missing leading zero, e.g. 531216007 -> 233531216007
        digits = "233" + digits
      }

      guard let phoneInt = Int64(digits), phoneInt > 0 else {
        continue
      }

      let name = (contact["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
      let location = (contact["location"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
      let callStatus = (contact["callStatus"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
      let center = (contact["callCenterName"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

      var label = name.isEmpty ? "Outreach Contact" : name
      if !callStatus.isEmpty {
        label += " • \(callStatus)"
      }
      if !location.isEmpty {
        label += " • \(location)"
      }
      if !center.isEmpty {
        label += " (\(center))"
      }

      // 1. Primary entry: Full International E.164 number (e.g. 233595158131)
      // Matches outgoing calls dialed with +233 and incoming calls delivered with +233
      entries.append(QaraDirectoryEntry(phoneNumber: phoneInt, label: label))

      // 2. Secondary entry: Core 9-digit local subscriber number (e.g. 595158131)
      // Resilient workaround: If iOS does not recognize newer telecom prefixes (e.g. 053/059)
      // or if the carrier delivers local incoming calls without +233, iOS queries CallKit
      // using the local digits. Registering both guarantees a 100% match in all scenarios!
      if digits.hasPrefix("233") && digits.count == 12 {
        let localCore = String(digits.dropFirst(3))
        if let localPhoneInt = Int64(localCore), localPhoneInt > 0 {
          entries.append(QaraDirectoryEntry(phoneNumber: localPhoneInt, label: label))
        }
      }
    }

    // CallKit strictly requires ascending numerical sort order
    entries.sort { $0.phoneNumber < $1.phoneNumber }

    // Deduplicate
    var uniqueEntries: [QaraDirectoryEntry] = []
    var seen = Set<Int64>()
    for entry in entries {
      if !seen.contains(entry.phoneNumber) {
        seen.insert(entry.phoneNumber)
        uniqueEntries.append(entry)
      }
    }

    let fileURL = containerURL.appendingPathComponent(Self.directoryFileName)
    do {
      let data = try JSONEncoder().encode(uniqueEntries)
      try data.write(to: fileURL, options: .atomic)
      NSLog("[Qara] Saved %ld entries to App Group container", uniqueEntries.count)
      for entry in uniqueEntries {
        NSLog("[Qara] Directory entry: %lld -> %@", entry.phoneNumber, entry.label)
      }

      // Reload extension with CallKit
      CXCallDirectoryManager.sharedInstance.reloadExtension(
        withIdentifier: Self.extensionIdentifier
      ) { error in
        DispatchQueue.main.async {
          if let error = error {
            NSLog("[Qara] CXCallDirectoryManager.reloadExtension error: %@", error.localizedDescription)
            result(false)
          } else {
            NSLog("[Qara] CXCallDirectoryManager.reloadExtension succeeded for identifier: %@", Self.extensionIdentifier)
            result(true)
          }
        }
      }
    } catch {
      NSLog("[Qara] Failed to write directory file: %@", error.localizedDescription)
      result(false)
    }
  }
}

private struct QaraDirectoryEntry: Codable {
  let phoneNumber: Int64
  let label: String
}
