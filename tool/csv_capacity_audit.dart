import 'dart:convert';
import 'dart:io';
import 'package:little_log/models.dart';
import 'package:little_log/services/family_csv.dart';

void main() {
  const family = Family(
    id: '11111111-1111-4111-8111-111111111111',
    name: 'Synthetic family',
    babyName: 'Synthetic baby',
  );
  for (final count in [1000, 7300, 21900, 36500]) {
    final feeds = List.generate(
      count,
      (i) => Feeding(
        id: '22222222-2222-4222-8222-${i.toString().padLeft(12, '0')}',
        familyId: family.id,
        at: DateTime.utc(2026).add(Duration(minutes: i * 72)),
        method: 'bottle',
        amountMl: 90,
        note: 'Synthetic note for capacity testing, fifty chars...',
        author: 'caregiver@example.com',
      ),
    );
    final encodeTimes = <int>[], decodeTimes = <int>[];
    var bytes = 0;
    try {
      for (var r = 0; r < 4; r++) {
        final timer = Stopwatch()..start();
        final csv = FamilyCsv(family, feeds).encode();
        timer.stop();
        if (r > 0) encodeTimes.add(timer.elapsedMicroseconds);
        bytes = utf8.encode(csv).length;
        timer.reset();
        timer.start();
        final decoded = FamilyCsv.decode(csv);
        timer.stop();
        if (decoded.feeds.length != count) throw StateError('Count mismatch');
        if (r > 0) decodeTimes.add(timer.elapsedMicroseconds);
      }
      encodeTimes.sort();
      decodeTimes.sort();
      stdout.writeln(
        jsonEncode({
          'records': count,
          'bytes': bytes,
          'encode_ms': encodeTimes[1] / 1000,
          'decode_ms': decodeTimes[1] / 1000,
        }),
      );
    } catch (e) {
      stdout.writeln(jsonEncode({'records': count, 'error': e.toString()}));
    }
  }
}
