import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:little_log/services/picker_native.dart' as native;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:little_log/services/google_auth.dart';
import 'support/invitation_harness.dart';

void main() {
  const channel = MethodChannel('app.littlelog/picker');
  testWidgets('native picker cancellation leaves authorization unchanged', (
    tester,
  ) async {
    late BuildContext context;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (c) {
            context = c;
            return const SizedBox();
          },
        ),
      ),
    );
    final auth = GoogleAuth()..user = HarnessAccount('receiver@example.com');
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      channel,
      (_) async => null,
    );
    addTearDown(() {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      );
      auth.dispose();
    });
    expect(
      await native.pickFamily(
        context,
        'synthetic',
        accountEmail: auth.user!.email,
        auth: auth,
      ),
      isNull,
    );
    expect(auth.driveConnected, isFalse);
  });
  testWidgets('targeted picker rejects a different Drive file', (tester) async {
    late BuildContext context;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (c) {
            context = c;
            return const SizedBox();
          },
        ),
      ),
    );
    final auth = GoogleAuth()..user = HarnessAccount('receiver@example.com');
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      expect(call.arguments['fileId'], 'owner123456789');
      return {'fileId': 'other123456789', 'accessToken': 'synthetic'};
    });
    addTearDown(() {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      );
      auth.dispose();
    });
    await expectLater(
      native.pickFamily(
        context,
        'synthetic',
        accountEmail: auth.user!.email,
        auth: auth,
        fileId: 'owner123456789',
      ),
      throwsA(predicate((e) => e.toString().contains('different Drive file'))),
    );
    expect(auth.driveConnected, isFalse);
  });
  testWidgets(
    'unsupported Android picker reports recovery instead of silent cancellation',
    (tester) async {
      late BuildContext context;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (c) {
              context = c;
              return const SizedBox();
            },
          ),
        ),
      );
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        _,
      ) async {
        throw PlatformException(
          code: 'picker_unavailable',
          message:
              'Update Google Play services, then try Find shared log again.',
        );
      });
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          null,
        ),
      );
      await expectLater(
        native.pickFamily(
          context,
          'synthetic',
          accountEmail: 'receiver@example.com',
        ),
        throwsA(
          predicate(
            (e) => e.toString().contains('Update Google Play services'),
          ),
        ),
      );
    },
  );
  test(
    'picker token is verified against the selected Google account',
    () async {
      final auth = GoogleAuth(
        verificationClient: MockClient((r) async {
          expect(r.url.path, '/drive/v3/about');
          expect(r.headers['authorization'], 'Bearer synthetic');
          return http.Response(
            '{"user":{"emailAddress":"receiver@example.com"}}',
            200,
          );
        }),
      )..user = HarnessAccount('receiver@example.com');
      await auth.acceptPickerToken(
        'synthetic',
        expectedEmail: 'receiver@example.com',
      );
      expect(await auth.accessToken(), 'synthetic');
      expect(auth.driveConnected, isTrue);
      auth.dispose();
    },
  );
  test(
    'picker rejects a different browser account without connecting Drive',
    () async {
      final auth = GoogleAuth(
        verificationClient: MockClient(
          (_) async => http.Response(
            '{"user":{"emailAddress":"other@example.com"}}',
            200,
          ),
        ),
      )..user = HarnessAccount('receiver@example.com');
      await expectLater(
        auth.acceptPickerToken(
          'synthetic',
          expectedEmail: 'receiver@example.com',
        ),
        throwsA(
          predicate((e) => e.toString().contains('different Google account')),
        ),
      );
      expect(auth.driveConnected, isFalse);
      auth.dispose();
    },
  );
  test(
    'account switch while picker is returning rejects the stale result',
    () async {
      final response = Completer<http.Response>();
      final auth = GoogleAuth(
        verificationClient: MockClient((_) => response.future),
      )..user = HarnessAccount('receiver@example.com');
      final pending = auth.acceptPickerToken(
        'synthetic',
        expectedEmail: 'receiver@example.com',
      );
      auth.user = HarnessAccount('other@example.com');
      response.complete(
        http.Response('{"user":{"emailAddress":"receiver@example.com"}}', 200),
      );
      await expectLater(pending, throwsStateError);
      expect(auth.driveConnected, isFalse);
      auth.dispose();
    },
  );
}
