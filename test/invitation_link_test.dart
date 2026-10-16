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
