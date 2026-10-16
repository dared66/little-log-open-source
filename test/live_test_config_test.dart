import 'package:flutter_test/flutter_test.dart';
import '../tool/live_test_config.dart';

void main() {
  test('live tests reject missing configuration and example accounts', () {
    expect(() => const LiveTestConfig().validate(), throwsStateError);
    expect(
      () => const LiveTestConfig(
        enabled: true,
        account: 'tester@example.com',
        owner: 'owner@example.com',
        fileId: 'synthetic-file',
      ).validate(),
      throwsStateError,
    );
  });

  const read = LiveTestConfig(
    enabled: true,
    account: 'tester@synthetic.invalid',
    owner: 'owner@synthetic.invalid',
    fileId: 'synthetic-file',
  );
  test('live read requires the selected account and owner', () {
    read.validate();
    read.checkAccount('tester@synthetic.invalid');
    read.checkOwner('owner@synthetic.invalid');
    expect(() => read.checkAccount(null), throwsStateError);
    expect(
      () => read.checkAccount('different@synthetic.invalid'),
      throwsStateError,
    );
    expect(
      () => read.checkOwner('different@synthetic.invalid'),
      throwsStateError,
    );
    expect(() => read.validate(requireBaby: true), throwsStateError);
  });

  test('creation needs a recipient even when no file exists yet', () {
    const create = LiveTestConfig(
      enabled: true,
      mode: 'create',
      account: 'tester@synthetic.invalid',
      owner: 'tester@synthetic.invalid',
    );
    expect(() => create.validate(requireFile: false), throwsStateError);
    const configured = LiveTestConfig(
      enabled: true,
      mode: 'create',
      account: 'tester@synthetic.invalid',
      owner: 'tester@synthetic.invalid',
      recipient: 'recipient@synthetic.invalid',
    );
    configured.validate(requireFile: false);
    expect(configured.validate, throwsStateError);
  });
}
