import 'package:flutter_test/flutter_test.dart';
import 'package:little_log/models.dart';
import 'package:little_log/services/invitation_link.dart';

void main() {
  test('invitation link binds a file and invited Google account', () {
    const family = Family(
      id: 'family',
      name: 'Lila’s family',
      babyName: 'Lila',
      driveFileId: 'owner123456789',
      accountId: 'owner',
    );
    final link = InvitationLink.forFamily(family, ' Wife@Example.com ');
    final parsed = InvitationLink.parse(link)!;
    expect(parsed.fileId, 'owner123456789');
    expect(parsed.invitedEmail, 'wife@example.com');
    expect(parsed.babyName, 'Lila');
  });

  test(
    'email link preserves the exact log without sending recipient data to the host',
    () {
      const family = Family(
        id: 'family',
        name: 'Family',
        babyName: 'Robin & Alex',
        driveFileId: 'owner123456789',
      );
      final link = InvitationLink.webForFamily(family, 'caregiver@example.com');
      final uri = Uri.parse(link);
      expect(uri.scheme, 'https');
      expect(uri.host, 'krupapc.dev');
      expect(uri.query, isEmpty);
      expect(InvitationLink.parse(link)!.babyName, 'Robin & Alex');
      expect(InvitationLink.parse(link)!.invitedEmail, 'caregiver@example.com');
      expect(
        InvitationLink.parse(
          link.replaceFirst('krupapc.dev', 'untrusted.example'),
        ),
        isNull,
      );
    },
  );

  test('rejects unrelated and malformed app links', () {
    expect(
      InvitationLink.parse('littlelog://wrong?file=owner123456789'),
      isNull,
    );
    expect(
      InvitationLink.parse(
        'https://drive.google.com/file/d/owner123456789/view',
      ),
      isNull,
    );
    expect(
      InvitationLink.parse(
        'littlelog://join?file=short&to=a%40b.com&baby=Lila',
      ),
      isNull,
    );
  });
}
