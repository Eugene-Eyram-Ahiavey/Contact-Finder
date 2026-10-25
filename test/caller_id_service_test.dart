import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qara/models/contact.dart';
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

  test('requestCallerIdRole invokes native channel correctly', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
      if (methodCall.method == 'requestCallScreeningRole') {
        return true;
      }
      return null;
    });

    final granted = await CallerIdService.requestCallerIdRole();
    expect(granted, isTrue);
  });

  test('isOverlayPermissionGranted and requestOverlayPermission invoke native channel', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
      if (methodCall.method == 'isOverlayPermissionGranted') {
        return true;
      }
      if (methodCall.method == 'requestOverlayPermission') {
        return true;
      }
      return null;
    });

    final isGranted = await CallerIdService.isOverlayPermissionGranted();
    final requested = await CallerIdService.requestOverlayPermission();
    expect(isGranted, isTrue);
    expect(requested, isTrue);
  });

  test('syncContactsToCallDirectory formats payload and invokes native channel', () async {
    List<dynamic>? receivedPayload;

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
      if (methodCall.method == 'syncContactsToCallDirectory') {
        receivedPayload = methodCall.arguments as List<dynamic>;
        return true;
      }
      return null;
    });

    final testContacts = [
      Contact(
        id: '1',
        name: 'Kwame Mensah',
        phoneNumber: '0244123456',
        normalizedPhoneNumber: '+233244123456',
        location: 'Madina',
        notes: 'Interested in Sunday service',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ),
      Contact(
        id: '2',
        name: 'Ama Osei',
        phoneNumber: '0555987654',
        normalizedPhoneNumber: '+233555987654',
        location: 'Tema',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ),
    ];

    final result = await CallerIdService.syncContactsToCallDirectory(testContacts);
    expect(result, isTrue);
    expect(receivedPayload, isNotNull);
    expect(receivedPayload!.length, equals(2));
    expect((receivedPayload![0] as Map)['name'], equals('Kwame Mensah'));
    expect((receivedPayload![0] as Map)['normalizedPhone'], equals('+233244123456'));
    expect((receivedPayload![0] as Map)['location'], equals('Madina'));
    expect((receivedPayload![1] as Map)['name'], equals('Ama Osei'));
  });

  test('syncContactsToCallDirectory returns false on PlatformException', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
      throw PlatformException(code: 'ERROR', message: 'Failed to write App Group');
    });

    final result = await CallerIdService.syncContactsToCallDirectory([]);
    expect(result, isFalse);
  });

  test('openAppSettings invokes native channel and returns boolean', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
      if (methodCall.method == 'openAppSettings') {
        return true;
      }
      return null;
    });

    final result = await CallerIdService.openAppSettings();
    expect(result, isTrue);
  });
}
