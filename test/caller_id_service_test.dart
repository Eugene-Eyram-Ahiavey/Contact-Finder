import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qara/services/caller_id_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('com.mode.qara/caller_id');

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('isCallerIdEnabled returns true when native channel reports true', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
      if (methodCall.method == 'isCallScreeningRoleHeld') {
        return true;
      }
      return null;
    });

    final isEnabled = await CallerIdService.isCallerIdEnabled();
    expect(isEnabled, isTrue);
  });

  test('isCallerIdEnabled returns false when native channel reports false', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
      if (methodCall.method == 'isCallScreeningRoleHeld') {
        return false;
      }
      return null;
    });

    final isEnabled = await CallerIdService.isCallerIdEnabled();
    expect(isEnabled, isFalse);
  });

  test('isCallerIdEnabled handles PlatformException gracefully without crashing', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
      throw PlatformException(code: 'UNAVAILABLE', message: 'Channel failed');
    });

    final isEnabled = await CallerIdService.isCallerIdEnabled();
    expect(isEnabled, isFalse);
  });
}
