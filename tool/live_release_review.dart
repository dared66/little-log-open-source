// Opt-in live release review: real Google services and production widgets,
// with a separate on-device database so existing user history is untouched.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sembast/sembast_io.dart';
import 'package:little_log/controller.dart';
import 'package:little_log/main.dart';
import 'package:little_log/models.dart';
import 'package:little_log/services/google_auth.dart';
import 'package:little_log/services/google_drive.dart';
import 'package:little_log/storage/repository.dart';

Future<void> main() async {
  if (!const bool.fromEnvironment('RUN_LIVE_RELEASE_REVIEW')) {
    throw StateError('Explicit live review opt-in required.');
  }
  WidgetsFlutterBinding.ensureInitialized();
  final directory = await getApplicationSupportDirectory();
  final repo = Repository(
    await databaseFactoryIo.openDatabase(
      '${directory.path}/live-release-review.db',
    ),
  );
  final auth = GoogleAuth();
  final drive = GoogleDrive(auth);
  final c = AppController(repo, auth, drive);
  await c.initialize();
  final platform = Platform.isIOS ? 'iOS' : 'Android';
  if ((await repo.families()).isEmpty) {
    await c.createLocal('Release review', 'Local $platform 1022');
    await repo.add(
      Feeding(
        id: newId.v4(),
        familyId: c.family!.id,
        at: DateTime.now().toUtc(),
        method: 'bottle',
        amountMl: 17,
        note: 'Device-only control. Must never upload.',
      ),
    );
    await c.createLocal('Release review', 'Release $platform 1022');
    final now = DateTime.now().toUtc();
    for (final record in [
      Feeding(
        id: newId.v4(),
        familyId: c.family!.id,
        at: now.subtract(const Duration(days: 2)),
        method: 'bottle',
        amountMl: 73,
        note: 'Live backup: older history',
      ),
      Feeding(
        id: newId.v4(),
        familyId: c.family!.id,
        at: now.subtract(const Duration(minutes: 15)),
        method: 'diaper',
        diaperKind: 'wet',
        note: 'Live backup: recent history',
      ),
      Feeding(
        id: newId.v4(),
        familyId: c.family!.id,
        at: now.subtract(const Duration(minutes: 5)),
        method: 'bottle',
        amountMl: 41,
        note: 'Live backup: latest history',
      ),
    ]) {
      await repo.add(record);
    }
    await c.refresh();
  }
  runApp(LittleLogApp(controller: c));
  var reading = false;
  var sequence = 0;
  Future<void> snapshot() async {
    if (reading) return;
    reading = true;
    final result = <String, Object?>{
      'at': DateTime.now().toUtc().toIso8601String(),
      'platform': platform,
      'account': auth.user?.email,
      'connected': auth.driveConnected,
      'selected': c.family?.id,
      'message': c.message,
      'local': [
        for (final f in await repo.families())
          {
            'family': f.toJson(),
            'history': [
              for (final e in await repo.feeds(f.id, includeDeleted: true))
                e.toJson(),
            ],
          },
      ],
    };
    try {
      if (auth.user != null && auth.driveConnected) {
        final cloud = GoogleDrive(auth);
        try {
          result['driveFiles'] = await cloud.listFamilies();
          result['remote'] = [
            for (final f in await repo.families())
              if (!f.isLocal && f.accountId == auth.user!.id)
                {
                  'familyId': f.id,
                  'fileId': f.driveFileId,
                  'history': [
                    for (final e in (await cloud.readFeeds(f)).feeds)
                      e.toJson(),
                  ],
                },
          ];
        } finally {
          cloud.dispose();
        }
      }
    } catch (e) {
      result['readErrorType'] = e.runtimeType.toString();
    }
    final out = Directory('${directory.path}/live-release-review');
    await out.create(recursive: true);
    final text = const JsonEncoder.withIndent('  ').convert(result);
    await File(
      '${out.path}/${(++sequence).toString().padLeft(4, '0')}.json',
    ).writeAsString(text);
    await File('${out.path}/latest.json').writeAsString(text);
    reading = false;
  }

  unawaited(snapshot());
  Timer.periodic(const Duration(seconds: 15), (_) => unawaited(snapshot()));
}
