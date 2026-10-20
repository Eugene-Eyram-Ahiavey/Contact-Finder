/// PhoneNumberNormalizer
///
/// Handles phone number normalization, validation, and matching for evangelism contacts,
/// with specialized support for Ghanaian telephone numbering plans (country code +233)
/// as well as standard international E.164 numbers.
///
/// Why Normalization Matters:
/// Outreach contacts are entered in various formats by team members:
/// - "024 412 3456" (local with spaces)
/// - "024-412-3456" (local with hyphens)
/// - "0244123456" (local 10 digits with leading zero)
/// - "+233244123456" (international format)
/// - "233244123456" (international without leading plus)
///
/// When an incoming call arrives, the telecom network can report either the local
/// or international format. Normalizing all numbers to standard E.164 (`+233244123456`)
/// ensures 100% deterministic, instant database matching.
class PhoneNumberNormalizer {
  /// Default country code for outreach contacts (Ghana: 233).
  static const String defaultCountryCode = '233';

  /// Normalizes a raw phone number into standard international E.164 format (e.g. `+233244123456`).
  ///
  /// Returns `null` if the input is too short, malformed, or cannot be safely normalized.
  static String? normalize(String? raw, {String defaultCountry = defaultCountryCode}) {
    if (raw == null || raw.trim().isEmpty) return null;

    // 1. Remove all whitespace, hyphens, brackets, dots, and non-digit/non-plus characters
    String cleaned = raw.replaceAll(RegExp(r'[\s\-\(\)\.]'), '').trim();

    // 2. Handle international double-zero prefix: "00233..." -> "+233..."
    if (cleaned.startsWith('00')) {
      cleaned = '+${cleaned.substring(2)}';
    }

    // 3. Handle standard Ghanaian 10-digit local format: "0244123456" -> "+233244123456"
    // In Ghana, standard local numbers start with '0' followed by a 9-digit subscriber number (10 digits total)
    if (RegExp(r'^0\d{9}$').hasMatch(cleaned)) {
      return '+$defaultCountry${cleaned.substring(1)}';
    }

    // 4. Handle number entered without plus but with country code: "233244123456" (12 digits)
    if (RegExp(r'^233\d{9}$').hasMatch(cleaned)) {
      return '+$cleaned';
    }

    // 5. If it already starts with '+', verify length conforms to E.164 standard (7 to 15 digits)
    if (cleaned.startsWith('+')) {
      final digitsOnly = cleaned.substring(1).replaceAll(RegExp(r'\D'), '');
      if (digitsOnly.length >= 7 && digitsOnly.length <= 15) {
        return '+$digitsOnly';
      }
      return null;
    }

    // 6. Fallback for other standard local numbers: if digits only between 7 and 15 digits
    final digitsOnly = cleaned.replaceAll(RegExp(r'\D'), '');
    if (digitsOnly.length >= 7 && digitsOnly.length <= 15) {
      if (digitsOnly.startsWith(defaultCountry)) {
        return '+$digitsOnly';
      }
      return '+$defaultCountry$digitsOnly';
    }

    return null;
  }

  /// Validates whether a phone number string can be parsed into a usable contact number.
  static bool isValid(String? raw, {String defaultCountry = defaultCountryCode}) {
    return normalize(raw, defaultCountry: defaultCountry) != null;
  }

  /// Converts a normalized E.164 number (`+233244123456`) into an `int` for Apple CallKit.
  /// (Apple's CXCallDirectoryExtension requires `Int64` numbers with no plus sign: `233244123456`).
  static int? toCallKitInt64(String? normalized) {
    if (normalized == null) return null;
    final digits = normalized.replaceAll(RegExp(r'\D'), '');
    return int.tryParse(digits);
  }

  /// Formats a phone number for clean human presentation on mobile cards.
  /// E.g. "+233244123456" or "0244123456" -> "024 412 3456"
  static String formatForDisplay(String phone) {
    final cleaned = phone.replaceAll(RegExp(r'\s'), '');

    // Ghanaian 10-digit local format: "0244123456" -> "024 412 3456"
    if (cleaned.length == 10 && cleaned.startsWith('0')) {
      return '${cleaned.substring(0, 3)} ${cleaned.substring(3, 6)} ${cleaned.substring(6)}';
    }

    // Ghanaian international format: "+233244123456" -> "+233 24 412 3456"
    if (cleaned.startsWith('+233') && cleaned.length == 13) {
      return '+233 ${cleaned.substring(4, 6)} ${cleaned.substring(6, 9)} ${cleaned.substring(9)}';
    }

    return phone;
  }
}
