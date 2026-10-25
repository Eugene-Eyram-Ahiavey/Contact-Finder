import Flutter
import UIKit
import CallKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private let channelName = "com.mode.qara/caller_id"
  private let extensionIdentifier = "com.mode.qara.CallDirectoryExtension"
  private let appGroupId = "group.com.mode.qara"
  private let directoryFileName = "contacts_directory.json"

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    let controller = window?.rootViewController as? FlutterViewController
    if let controller = controller {
      let channel = FlutterMethodChannel(name: channelName, binaryMessenger: controller.binaryMessenger)
      channel.setMethodCallHandler { [weak self] (call, result) in
        guard let self = self else { return }
        switch call.method {
        case "isCallScreeningRoleHeld":
          CXCallDirectoryManager.sharedInstance.getEnabledStatusForExtension(
            withIdentifier: self.extensionIdentifier
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

        case "syncContactsToCallDirectory":
          guard let contacts = call.arguments as? [[String: Any]] else {
            result(false)
            return
          }
          self.syncContacts(contacts: contacts, result: result)

        default:
          result(FlutterMethodNotImplemented)
        }
      }
    }

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  private func syncContacts(contacts: [[String: Any]], result: @escaping FlutterResult) {
    guard let containerURL = FileManager.default.containerURL(
      forSecurityApplicationGroupIdentifier: appGroupId
    ) else {
      NSLog("[Qara] App Group containerURL is nil for %@", appGroupId)
      result(false)
      return
    }

    var entries: [QaraDirectoryEntry] = []

    for contact in contacts {
      let rawPhone = (contact["normalizedPhone"] as? String)
        ?? (contact["phone"] as? String)
        ?? ""
      let digits = rawPhone.filter { $0.isNumber }
      guard let phoneInt = Int64(digits), phoneInt > 0 else {
        continue
      }

      let name = (contact["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
      let location = (contact["location"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

      var label = name.isEmpty ? "Outreach Contact" : name
      if !location.isEmpty {
        label += " • \(location)"
      }

      entries.append(QaraDirectoryEntry(phoneNumber: phoneInt, label: label))
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

    let fileURL = containerURL.appendingPathComponent(directoryFileName)
    do {
      let data = try JSONEncoder().encode(uniqueEntries)
      try data.write(to: fileURL, options: .atomic)
      NSLog("[Qara] Saved %ld entries to App Group container", uniqueEntries.count)

      // Reload extension with CallKit
      CXCallDirectoryManager.sharedInstance.reloadExtension(
        withIdentifier: extensionIdentifier
      ) { error in
        DispatchQueue.main.async {
          if let error = error {
            NSLog("[Qara] CXCallDirectoryManager.reloadExtension error: %@", error.localizedDescription)
            // Even if extension reload returns error (e.g. extension not yet enabled in Settings),
            // the data file was successfully written.
            result(true)
          } else {
            NSLog("[Qara] CXCallDirectoryManager.reloadExtension succeeded")
            result(true)
          }
        }
      }
    } catch {
      NSLog("[Qara] Failed to write directory file: %@", error.localizedDescription)
      result(false)
    }
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }
}

private struct QaraDirectoryEntry: Codable {
  let phoneNumber: Int64
  let label: String
}
