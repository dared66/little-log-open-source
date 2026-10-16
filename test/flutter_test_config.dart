import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

// Host tests do not have native Live Activity / notification plugins. Tests of
// the action handoff can replace this default handler with their own journal.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  binding.defaultBinaryMessenger.setMockMethodCallHandler(
    const MethodChannel('little_log/live_activity'),
    (call) async => call.method == 'pendingStops' ? <Object?>[] : null,
  );
  await testMain();
}
