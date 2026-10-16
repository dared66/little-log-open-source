import 'dart:io';
import 'package:integration_test/integration_test.dart';
import 'package:sembast/sembast_io.dart';
import '../test/flow_journey_test.dart' as journey;

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  var index = 0;
  journey.runJourney(
    native: true,
    openDatabase: () async {
      // An isolated, real on-device database; never touch the user's log.
      final directory = await Directory.systemTemp.createTemp('little-log-qa-');
      return databaseFactoryIo.openDatabase('${directory.path}/review.db');
    },
    checkpoint: (tester, title) async {
      // Visible checkpoints in CI output also locate any mid-journey failure.
      // ignore: avoid_print
      print('CHECKPOINT: $title');
      if (!const bool.fromEnvironment('CAPTURE_REVIEW')) return;
      if (!RegExp(
        r'Welcome$|Today / empty|bottle / saved on Today|Bottle / validation|Bottle / details|Nursing / switch|Sleep / review|History / filtered|Family / storage|Activity / swipe|Settings / unit|Growth /|Health /',
      ).hasMatch(title)) {
        return;
      }
      if (Platform.isAndroid && index == 0) {
        await binding.convertFlutterSurfaceToImage();
        await tester.pump();
      }
      await binding.takeScreenshot(
        '${(++index).toString().padLeft(2, '0')}-${title.replaceAll(RegExp(r'[^a-zA-Z0-9]+'), '-')}',
      );
    },
  );
}
