// Native voice-entry-point QA: synthetic data in an isolated in-memory log.
import 'package:flutter/material.dart';
import 'package:sembast/sembast_memory.dart';
import 'package:little_log/controller.dart';
import 'package:little_log/services/google_auth.dart';
import 'package:little_log/services/google_drive.dart';
import 'package:little_log/storage/repository.dart';
import 'package:little_log/main.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final auth = GoogleAuth();
  final c = AppController(
    Repository(await databaseFactoryMemory.openDatabase('voice-qa')),
    auth,
    GoogleDrive(auth),
  )..loading = false;
  await c.createLocal('Voice QA family', 'Robin QA');
  runApp(
    Directionality(
      textDirection: TextDirection.ltr,
      child: Stack(
        children: [
          LittleLogApp(controller: c),
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            child: Semantics(
              container: true,
              child: ListenableBuilder(
                listenable: c,
                builder: (_, _) {
                  int count(String method) =>
                      c.feeds.where((r) => r.method == method).length;
                  int diapers(String kind) =>
                      c.feeds.where((r) => r.diaperKind == kind).length;
                  final summary =
                      'VOICE_QA wet=${diapers('wet')} dirty=${diapers('dirty')} both=${diapers('both')} dry=${diapers('dry')} '
                      'sleepActive=${c.timers.where((t) => t.method == 'sleep').length} sleepSaved=${count('sleep')} '
                      'nursingActive=${c.nursing?.side ?? 'none'} nursingSaved=${count('nursing')} '
                      'pumpingActive=${c.timers.where((t) => t.method == 'pumping').length} pumpingSaved=${count('pumping')} '
                      'pumpingMl=${c.feeds.where((r) => r.method == 'pumping').fold<double>(0, (sum, r) => sum + (r.amountMl ?? 0))} '
                      'nursingPaused=${c.nursing?.paused ?? false} '
                      'pumpingPhase=${c.timers.where((t) => t.method == 'pumping').firstOrNull?.phase ?? 'none'}';
                  return Semantics(
                    label: summary,
                    excludeSemantics: true,
                    child: Material(
                      color: Colors.white,
                      child: Text(
                        summary,
                        style: const TextStyle(
                          color: Colors.black,
                          fontSize: 10,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    ),
  );
}
