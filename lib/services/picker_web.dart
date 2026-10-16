import 'dart:js_interop';
import 'package:flutter/material.dart';
import '../config.dart';
import 'google_auth.dart';

@JS('littleLogPick')
external JSPromise<JSString?> _pick(
  JSString token,
  JSString key,
  JSString appId,
  JSString? fileId,
);

Future<String?> pickFamily(
  BuildContext context,
  String token, {
  String? accountEmail,
  GoogleAuth? auth,
  String? fileId,
}) async {
  final result = await _pick(
    token.toJS,
    AppConfig.pickerKey.toJS,
    AppConfig.projectNumber.toJS,
    fileId?.toJS,
  ).toDart;
  final pickedFileId = result?.toDart;
  if (fileId != null && pickedFileId != null && pickedFileId != fileId) {
    throw StateError(
      'That is a different Drive file. Open the invitation link from the sender and try again.',
    );
  }
  return pickedFileId;
}
