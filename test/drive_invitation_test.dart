import 'package:flutter_test/flutter_test.dart';
import 'package:little_log/services/drive_invitation.dart';

void main() {
  test('only exact Google Drive file links identify an invited log', () {
    expect(
      invitationFileId(' https://drive.google.com/file/d/csv123456789/view '),
      'csv123456789',
    );
    expect(
      invitationFileId('https://drive.google.com/open?id=csv123456789'),
      'csv123456789',
    );
    expect(invitationFileId('csv123456789'), isNull);
    expect(
      invitationFileId('https://evil.com/file/d/csv123456789/view'),
      isNull,
    );
    expect(
      invitationFileId('https://drive.google.com/file/d/short/view'),
      isNull,
    );
  });
}
