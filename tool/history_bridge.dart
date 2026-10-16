import 'dart:convert';
import 'dart:io';
import 'package:little_log/services/family_csv.dart';
import 'package:little_log/services/history_bridge.dart';

Map<String, String> arguments(List<String> args) {
  if (args.isEmpty || !['from-nara', 'to-nara'].contains(args.first)) {
    throw const FormatException(
      'Usage: dart run tool/history_bridge.dart from-nara|to-nara --input FILE|- --output FILE [--base-csv FILE] [--caregivers FILE]',
    );
  }
  final options = <String, String>{'command': args.first};
  for (var i = 1; i < args.length; i += 2) {
    if (i + 1 >= args.length ||
        ![
          '--input',
          '--output',
          '--base-csv',
          '--caregivers',
        ].contains(args[i])) {
      throw const FormatException('Unknown or incomplete option.');
    }
    if (options.containsKey(args[i])) {
      throw const FormatException('Duplicate option.');
    }
    options[args[i].substring(2)] = args[i + 1];
  }
  if (options['input'] == null ||
      options['output'] == null ||
      options['output'] == '-' ||
      options['input'] != '-' &&
          File(options['input']!).absolute.path ==
              File(options['output']!).absolute.path) {
    throw const FormatException('Choose distinct input and output files.');
  }
  if (options['command'] == 'to-nara' &&
      (options.containsKey('base-csv') || options.containsKey('caregivers'))) {
    throw const FormatException(
      'Base CSV and caregiver mapping apply only to from-nara.',
    );
  }
  return options;
}

Future<void> main(List<String> args) async {
  try {
    final opts = arguments(args);
    final input = opts['input'] == '-'
        ? await stdin.transform(utf8.decoder).join()
        : await File(opts['input']!).readAsString();
    String output;
    int records;
    if (opts['command'] == 'from-nara') {
      final base = opts['base-csv'] == null
          ? null
          : FamilyCsv.decode(await File(opts['base-csv']!).readAsString());
      Map<String, String> caregivers = const {};
      if (opts['caregivers'] != null) {
        final parsed = jsonDecode(
          await File(opts['caregivers']!).readAsString(),
        );
        if (parsed is! Map ||
            parsed.entries.any((e) => e.key is! String || e.value is! String)) {
          throw const FormatException(
            'Caregiver mapping must be a JSON object of names.',
          );
        }
        caregivers = parsed.cast<String, String>();
      }
      final csv = HistoryBridge.naraToCsv(
        input,
        base: base,
        caregivers: caregivers,
      );
      output = csv.encode();
      records = csv.feeds
          .where((f) => !f.deleted && f.method != 'profile')
          .length;
    } else {
      final csv = FamilyCsv.decode(input);
      output = HistoryBridge.csvToNara(csv);
      records = csv.feeds
          .where((f) => !f.deleted && f.method != 'profile')
          .length;
    }
    final destination = File(opts['output']!);
    await destination.parent.create(recursive: true);
    final temporary = File('${destination.path}.tmp.$pid');
    try {
      await temporary.writeAsString(output, flush: true);
      await temporary.rename(destination.path);
    } finally {
      if (await temporary.exists()) await temporary.delete();
    }
    stdout.writeln(
      '${opts['command'] == 'from-nara' ? 'Little Log CSV' : 'Nara-shaped bridge JSON'} saved: $records active activities.',
    );
  } catch (error) {
    stderr.writeln(
      error is FormatException
          ? error.message
          : 'Conversion failed: ${error.runtimeType}',
    );
    exitCode = 1;
  }
}
