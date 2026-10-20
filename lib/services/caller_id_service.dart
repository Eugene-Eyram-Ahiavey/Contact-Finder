import 'package:flutter/services.dart';

/// CallerIdService
///
/// Bridges the Flutter UI layer with native platform code (Kotlin on Android, Swift on iOS)
/// using Flutter's [MethodChannel].
///
/// Think of MethodChannel like an Inter-Process Communication (IPC) bridge in Electron
/// or `window.postMessage` in web development:
/// - Dart invokes a named method with optional arguments.
/// - The native platform (Android/iOS) receives the call, executes OS-specific APIs,
///   and returns the result back to Dart asynchronously as a `Future` (the Dart equivalent of a JS `Promise`).
class CallerIdService {
  // Unique channel identifier shared between Dart, Android (MainActivity.kt), and iOS (AppDelegate.swift)
  static const MethodChannel _channel =
      MethodChannel('com.mode.evangelism_caller_id/caller_id');

  /// Checks whether the app currently holds the OS-level caller identification permission/role:
  /// - On Android: Checks `RoleManager.isRoleHeld(RoleManager.ROLE_CALL_SCREENING)`.
  /// - On iOS: Checks `CXCallDirectoryManager.getEnabledStatusForExtension(...)`.
  static Future<bool> isCallerIdEnabled() async {
    try {
      final bool? isEnabled =
          await _channel.invokeMethod<bool>('isCallScreeningRoleHeld');
      return isEnabled ?? false;
    } on PlatformException {
      // PlatformException is thrown when native code returns an error.
      // Similar to a rejected Promise in JavaScript or an Error thrown across IPC.
      return false;
    }
  }

  /// Prompts the user to grant the required caller ID permission:
  /// - On Android: Opens the system RoleManager dialog asking the user to set
  ///   this app as the Call Screening app.
  /// - On iOS: Guides the user (system restrictions prevent automated prompts;
  ///   user must toggle in iOS Settings -> Phone -> Call Blocking & Identification).
  static Future<bool> requestCallerIdRole() async {
    try {
      final bool? granted =
          await _channel.invokeMethod<bool>('requestCallScreeningRole');
      return granted ?? false;
    } on PlatformException {
      return false;
    }
  }
}
