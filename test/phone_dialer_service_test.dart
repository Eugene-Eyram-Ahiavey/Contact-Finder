import 'package:flutter_test/flutter_test.dart';
import 'package:qara/services/phone_dialer_service.dart';

void main() {
  group('PhoneDialerService Tests', () {
    test('safely rejects empty or whitespace-only phone numbers without throwing', () async {
      final resultEmpty = await PhoneDialerService.dial('');
      expect(resultEmpty, isFalse);

      final resultSpaces = await PhoneDialerService.dial('     ');
      expect(resultSpaces, isFalse);

      final resultSpecialCharsOnly = await PhoneDialerService.dial('---()');
      expect(resultSpecialCharsOnly, isFalse);
    });
  });
}
