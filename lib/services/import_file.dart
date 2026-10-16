import 'dart:convert';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/services.dart';
import 'family_csv.dart';

class ImportFile {
  const ImportFile(this.name, this.contents);
  final String name;
  final String contents;

  static Future<ImportFile?> choose() async {
    try {
      final file = await openFile(
        acceptedTypeGroups: const [
          XTypeGroup(
            label: 'Exports',
            extensions: ['csv', 'json'],
            uniformTypeIdentifiers: [
              'public.comma-separated-values-text',
              'public.json',
            ],
            mimeTypes: ['text/csv', 'application/csv', 'application/json'],
          ),
        ],
      );
      return file == null ? null : await read(file);
    } on PlatformException {
      throw const FormatException(
        'The file could not be opened. Choose it again.',
      );
    }
  }

  static Future<ImportFile> read(XFile file) async {
    try {
      return await _read(file);
    } on FormatException {
      rethrow;
    } catch (_) {
      throw const FormatException(
        'The file could not be read. Choose it again.',
      );
    }
  }

  static Future<ImportFile> _read(XFile file) async {
    if (await file.length() > FamilyCsv.maxBytes) {
      throw const FormatException('Choose a file smaller than 10 MB.');
    }
    final bytes = <int>[];
    await for (final chunk in file.openRead()) {
      if (bytes.length + chunk.length > FamilyCsv.maxBytes) {
        throw const FormatException('Choose a file smaller than 10 MB.');
      }
      bytes.addAll(chunk);
    }
    String text;
    try {
      text = utf8.decode(bytes);
    } on FormatException {
      throw const FormatException(
        'This file is not a UTF-8 CSV or JSON export.',
      );
    }
    if (text.startsWith('\ufeff')) text = text.substring(1);
    if (text.trim().isEmpty) throw const FormatException('This file is empty.');
    return ImportFile(file.name, text);
  }
}
