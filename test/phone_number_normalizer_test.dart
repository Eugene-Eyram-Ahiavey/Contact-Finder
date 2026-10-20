import 'package:flutter_test/flutter_test.dart';
import 'package:evangelism_caller_id/utils/phone_number_normalizer.dart';

void main() {
  group('PhoneNumberNormalizer Tests', () {
    test('normalizes standard 10-digit Ghanaian local numbers with leading zero', () {
      // MTN Ghana
      expect(PhoneNumberNormalizer.normalize('0244123456'), '+233244123456');
      expect(PhoneNumberNormalizer.normalize('0551122334'), '+233551122334');
      // Telecel / Vodafone Ghana
      expect(PhoneNumberNormalizer.normalize('0201234567'), '+233201234567');
      // AT / AirtelTigo Ghana
      expect(PhoneNumberNormalizer.normalize('0277889900'), '+233277889900');
    });

    test('normalizes Ghanaian numbers with spaces, hyphens, and brackets', () {
      expect(PhoneNumberNormalizer.normalize('024 412 3456'), '+233244123456');
      expect(PhoneNumberNormalizer.normalize('024-412-3456'), '+233244123456');
      expect(PhoneNumberNormalizer.normalize('(024) 412-3456'), '+233244123456');
      expect(PhoneNumberNormalizer.normalize(' 024.412.3456 '), '+233244123456');
    });

    test('normalizes numbers already starting with +233 or 233', () {
      expect(PhoneNumberNormalizer.normalize('+233244123456'), '+233244123456');
      expect(PhoneNumberNormalizer.normalize('233244123456'), '+233244123456');
      expect(PhoneNumberNormalizer.normalize('+233 24 412 3456'), '+233244123456');
    });

    test('normalizes numbers starting with international prefix 00', () {
      expect(PhoneNumberNormalizer.normalize('00233244123456'), '+233244123456');
      expect(PhoneNumberNormalizer.normalize('002348031234567'), '+2348031234567');
    });

    test('preserves foreign international numbers correctly', () {
      // Nigeria (+234)
      expect(PhoneNumberNormalizer.normalize('+2348031234567'), '+2348031234567');
      // United Kingdom (+44)
      expect(PhoneNumberNormalizer.normalize('+447911123456'), '+447911123456');
      // United States (+1)
      expect(PhoneNumberNormalizer.normalize('+14155552671'), '+14155552671');
    });

    test('rejects invalid or malformed numbers', () {
      expect(PhoneNumberNormalizer.normalize(null), isNull);
      expect(PhoneNumberNormalizer.normalize(''), isNull);
      expect(PhoneNumberNormalizer.normalize('   '), isNull);
      expect(PhoneNumberNormalizer.normalize('123'), isNull); // Too short
      expect(PhoneNumberNormalizer.normalize('abcd'), isNull); // Non-numeric
      expect(PhoneNumberNormalizer.isValid('invalid'), isFalse);
      expect(PhoneNumberNormalizer.isValid('0244123456'), isTrue);
    });

    test('converts normalized E.164 string to iOS CallKit Int64', () {
      final normalized = PhoneNumberNormalizer.normalize('0244123456');
      final callKitInt = PhoneNumberNormalizer.toCallKitInt64(normalized);
      expect(callKitInt, 233244123456);
      expect(PhoneNumberNormalizer.toCallKitInt64(null), isNull);
    });

    test('formats phone numbers cleanly for human UI display', () {
      expect(
        PhoneNumberNormalizer.formatForDisplay('0244123456'),
        '024 412 3456',
      );
      expect(
        PhoneNumberNormalizer.formatForDisplay('+233244123456'),
        '+233 24 412 3456',
      );
    });
  });
}
