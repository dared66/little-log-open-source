import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:little_log/activity_details.dart';
import 'package:little_log/main.dart';
import 'package:little_log/models.dart';
import 'package:little_log/services/invitation_link.dart';
import 'package:little_log/widgets/onboarding.dart';
import 'elapsed_icon_preference_test.dart' show localController;

void main() {
  testWidgets('duplicate invitation delivery before a frame opens one route', (
    t,
  ) async {
    final c = await localController(t);
    await t.pumpWidget(LittleLogApp(controller: c));
    await t.pumpAndSettle();
    const invited = Family(
      id: 'shared',
      name: 'Shared',
      babyName: 'Shared',
      driveFileId: 'csv123456789',
      accountId: 'sender',
    );
    for (var i = 0; i < 2; i++) {
      await t.binding.defaultBinaryMessenger.handlePlatformMessage(
        'app.littlelog/invitation',
        const StandardMethodCodec().encodeMethodCall(
          MethodCall(
            'received',
            InvitationLink.forFamily(invited, 'caregiver@example.com'),
          ),
        ),
        (_) {},
      );
    }
    await t.pumpAndSettle();
    expect(find.byType(OnboardingPage, skipOffstage: false), findsOneWidget);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets(
    'stopped pumping review waits until the app can select its baby',
    (t) async {
      final c = await localController(t);
      final baby = c.family!;
      await t.runAsync(() async {
        final start = DateTime.now().subtract(const Duration(minutes: 3));
        final timer = ActivityTimer(
          id: 'pump-a',
          familyId: baby.id,
          method: 'pumping',
          startedAt: start,
        );
        await c.repository.startTimer(timer);
        await c.performLiveTimerAction(
          sessionId: timer.id,
          familyId: baby.id,
          method: 'pumping',
          action: 'pause',
          at: DateTime.now(),
        );
        await c.finishLiveTimer(
          sessionId: timer.id,
          familyId: baby.id,
          method: 'pumping',
          at: DateTime.now(),
        );
        await c.createLocal('Other', 'Other');
      });
      await t.pumpWidget(LittleLogApp(controller: c));
      await t.pumpAndSettle();
      c.syncing = true;
      c.pendingPumpingReview = (familyId: baby.id, sessionId: 'pump-a');
      await t.runAsync(c.refresh);
      await t.pump(const Duration(milliseconds: 500));
      expect(c.pendingPumpingReview, isNotNull);
      c.syncing = false;
      await t.runAsync(c.refresh);
      await t.pumpAndSettle();
      await t.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await t.pumpAndSettle();
      expect(c.family!.id, baby.id);
      expect(c.pendingPumpingReview, isNull);
      await t.pumpWidget(const SizedBox());
    },
  );
  testWidgets('a stale pumping handoff clears without opening another timer', (
    t,
  ) async {
    final c = await localController(t);
    await t.pumpWidget(LittleLogApp(controller: c));
    await t.pumpAndSettle();
    c.pendingPumpingReview = (
      familyId: c.family!.id,
      sessionId: 'already-saved',
    );
    await t.runAsync(c.refresh);
    await t.pumpAndSettle();
    expect(c.pendingPumpingReview, isNull);
    expect(c.timers, isEmpty);
    await t.pumpWidget(const SizedBox());
  });
}
