import '../models.dart';

/// The link identifies a file and intended account, but is not an access
/// credential. Google Drive still checks the receiver's account and grants
/// Little Log per-file access through its picker.
class InvitationLink {
  const InvitationLink({
    required this.fileId,
    required this.invitedEmail,
    required this.babyName,
  });

  final String fileId;
  final String invitedEmail;
  final String babyName;

  static final _fileIdPattern = RegExp(r'^[A-Za-z0-9_-]{10,200}$');
  static final _emailPattern = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');

  static InvitationLink? parse(String raw) {
    final uri = Uri.tryParse(raw);
    if (uri == null || uri.scheme != 'littlelog' || uri.host != 'join') {
      return null;
    }
    final fileId = uri.queryParameters['file'];
    final email = uri.queryParameters['to'];
    final babyName = uri.queryParameters['baby'];
    if (fileId == null ||
        !_fileIdPattern.hasMatch(fileId) ||
        email == null ||
        !_emailPattern.hasMatch(email) ||
        babyName == null ||
        babyName.trim().isEmpty ||
        babyName.length > 60) {
      return null;
    }
    return InvitationLink(
      fileId: fileId,
      invitedEmail: email.toLowerCase(),
      babyName: babyName.trim(),
    );
  }

  static String forFamily(Family family, String email) {
    final id = family.driveFileId;
    if (id == null || !_fileIdPattern.hasMatch(id)) {
      throw StateError('Save this baby’s log to Google Drive before inviting.');
    }
    final recipient = email.trim().toLowerCase();
    if (!_emailPattern.hasMatch(recipient)) {
      throw const FormatException('Enter a valid Google email address.');
    }
    return Uri(
      scheme: 'littlelog',
      host: 'join',
      queryParameters: {'file': id, 'to': recipient, 'baby': family.babyName},
    ).toString();
  }
}
