import Flutter
import UIKit
import CallKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private let channelName = "com.mode.qara/caller_id"

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    let controller = window?.rootViewController as? FlutterViewController
    if let controller = controller {
      let channel = FlutterMethodChannel(name: channelName, binaryMessenger: controller.binaryMessenger)
      channel.setMethodCallHandler { (call, result) in
        switch call.method {
        case "isCallScreeningRoleHeld":
          // In Milestone 1 skeleton, check iOS Call Directory Extension enabled status
          CXCallDirectoryManager.sharedInstance.getEnabledStatusForExtension(
            withIdentifier: "com.mode.qara.CallDirectoryExtension"
          ) { (status, error) in
            DispatchQueue.main.async {
              if let _ = error {
                result(false)
              } else {
                result(status == .enabled)
              }
            }
          }
        case "requestCallScreeningRole":
          // iOS does not permit in-app prompt dialogs for Call Directory;
          // the user must manually enable it in iOS Settings -> Phone -> Call Blocking & Identification.
          result(false)
        default:
          result(FlutterMethodNotImplemented)
        }
      }
    }

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }
}
