import 'package:flutter/services.dart';
import 'package:qara/models/contact.dart';

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
      MethodChannel('com.mode.qara/caller_id');

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

  /// Checks whether the app has permission to draw floating overlays ("Display over other apps").
  static Future<bool> isOverlayPermissionGranted() async {
    try {
      final bool? isGranted =
          await _channel.invokeMethod<bool>('isOverlayPermissionGranted');
      return isGranted ?? false;
    } on PlatformException {
      return false;
    }
  }

  /// Opens the system settings screen for the user to grant "Display over other apps".
  static Future<bool> requestOverlayPermission() async {
    try {
      final bool? success =
          await _channel.invokeMethod<bool>('requestOverlayPermission');
      return success ?? false;
    } on PlatformException {
      return false;
    }
  }

  /// Syncs contacts to the OS-level caller directory:
  /// - On iOS: Formats sorted E.164 Int64 numbers, saves to App Group container,
  ///   and triggers CXCallDirectoryManager to reload the extension.
  /// - On Android: No-op (Android CallScreeningService reads from local SQLite in real-time).
  static Future<bool> syncContactsToCallDirectory(List<Contact> contacts) async {
    try {
      final payload = contacts
          .map((c) => {
                'id': c.id,
                'name': c.name,
                'phone': c.phoneNumber,
                'normalizedPhone': c.normalizedPhoneNumber,
                'location': c.location,
                'notes': c.notes,
                'callCenterName': c.callCenterName,
              })
          .toList();
      final bool? success = await _channel.invokeMethod<bool>(
        'syncContactsToCallDirectory',
        payload,
      );
      return success ?? false;
    } on PlatformException {
      return false;
    }
  }

  /// Opens the system application settings screen.
  static Future<bool> openAppSettings() async {
    try {
      final bool? success =
          await _channel.invokeMethod<bool>('openAppSettings');
      return success ?? false;
    } on PlatformException {
      return false;
    }
  }
}
