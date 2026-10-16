import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../config.dart';
import 'google_auth.dart';

const _picker = MethodChannel('app.littlelog/picker');

Future<String?> pickFamily(
  BuildContext context,
  String token, {
  String? accountEmail,
  GoogleAuth? auth,
  String? fileId,
}) async {
  Map<String, String>? result;
  try {
    result = await _picker.invokeMapMethod<String, String>('pickFamily', {
      'email': accountEmail,
      'clientId': AppConfig.iosClientId,
      'fileId': ?fileId,
    });
  } on PlatformException catch (e) {
    throw StateError(
      e.message ?? 'Google Drive could not be opened. Please try again.',
    );
  }
  if (result == null) return null; // User cancelled; do not alter their log.
  final pickedFileId = result['fileId'];
  final accessToken = result['accessToken'];
  if (pickedFileId == null || accessToken == null || auth == null) {
    throw StateError('Google did not return a selected log. Please try again.');
  }
  if (fileId != null && pickedFileId != fileId) {
    throw StateError(
      'That is a different Drive file. Open the invitation link from the sender and try again.',
    );
  }
  await auth.acceptPickerToken(accessToken, expectedEmail: accountEmail!);
  return pickedFileId;
}
