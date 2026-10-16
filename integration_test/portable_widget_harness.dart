import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

/// Portable widget checks override viewport size and density. OS keyboard
/// insets still use the actual screen's physical pixels, so they must not leak
/// into that simulated geometry. Tests can supply their own keyboard inset.
/// Safe-area pixels must likewise not retain native density in a fake viewport.
/// Actual native keyboard/layout checks live in session_stress_test.dart.
void portableWidgetChecks(void Function() register) {
  group('portable viewport', () {
    setUp(() {
      final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
      final dispatcher = binding.platformDispatcher;
      for (final view in dispatcher.views) {
        view.viewInsets = FakeViewPadding.zero;
        view.padding = FakeViewPadding.zero;
        view.viewPadding = FakeViewPadding.zero;
        addTearDown(view.resetViewInsets);
        addTearDown(view.resetPadding);
        addTearDown(view.resetViewPadding);
      }
    });
    register();
  });
}
