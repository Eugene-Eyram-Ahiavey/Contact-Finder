import 'package:url_launcher/url_launcher.dart';

/// PhoneDialerService
///
/// Handles initiating native cellular phone calls from the app.
/// Analogous to `window.location.href = 'tel:...'` in web JavaScript.
class PhoneDialerService {
  /// Launches the system phone dialer with the given phone number pre-filled or dialing.
  /// Returns `true` if launched successfully, `false` otherwise.
  static Future<bool> dial(String phoneNumber) async {
    final cleanNumber = phoneNumber.trim().replaceAll(RegExp(r'[^\d+]'), '');
    if (cleanNumber.isEmpty) return false;

    final uri = Uri(scheme: 'tel', path: cleanNumber);
    try {
      if (await canLaunchUrl(uri)) {
        return await launchUrl(uri);
      } else {
        // Fallback attempt
        return await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    } catch (_) {
      return false;
    }
  }
}
