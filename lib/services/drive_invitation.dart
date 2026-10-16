/// A Drive file link identifies the exact log the sender shared. Never infer
/// identity from a baby's name: different accounts can have logs with that name.
String? invitationFileId(String input) {
  final value = input.trim();
  final uri = Uri.tryParse(value);
  if (uri == null || uri.scheme != 'https' || uri.host != 'drive.google.com') {
    return null;
  }
  String? id;
  final segments = uri.pathSegments;
  if (segments.length >= 3 && segments[0] == 'file' && segments[1] == 'd') {
    id = segments[2];
  } else if (uri.path == '/open') {
    id = uri.queryParameters['id'];
  }
  return id != null && RegExp(r'^[A-Za-z0-9_-]{10,200}$').hasMatch(id)
      ? id
      : null;
}
