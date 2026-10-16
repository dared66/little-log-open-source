/// Public schema for private, explicitly enabled live-test definitions.
/// Never import this into the shipped app or print these values in test output.
class LiveTestConfig {
  const LiveTestConfig({
    this.enabled = const bool.fromEnvironment('RUN_LIVE_DRIVE'),
    this.account = const String.fromEnvironment('LIVE_ACCOUNT'),
    this.owner = const String.fromEnvironment('LIVE_OWNER'),
    this.fileId = const String.fromEnvironment('LIVE_FILE_ID'),
    this.recipient = const String.fromEnvironment('LIVE_RECIPIENT'),
    this.babyName = const String.fromEnvironment('LIVE_QA_BABY'),
    this.mode = const String.fromEnvironment('LIVE_MODE', defaultValue: 'read'),
  });

  final bool enabled;
  final String account, owner, fileId, recipient, babyName, mode;

  void validate({bool requireBaby = false, bool requireFile = true}) {
    bool realAccount(String value) =>
        value.contains('@') && !value.toLowerCase().endsWith('@example.com');
    if (!enabled ||
        !realAccount(account) ||
        !realAccount(owner) ||
        !{'read', 'create'}.contains(mode) ||
        (requireFile && fileId.trim().isEmpty) ||
        (requireBaby && babyName.trim().isEmpty) ||
        (mode == 'create' && !realAccount(recipient))) {
      throw StateError(
        'Explicit live-test opt-in and private configuration are required.',
      );
    }
  }

  void checkAccount(String? signedInEmail) {
    if (signedInEmail != account) {
      throw StateError(
        'The signed-in account is not the configured test account.',
      );
    }
  }

  void checkOwner(String? ownerEmail) {
    if (ownerEmail != owner) {
      throw StateError(
        'The selected file is not owned by the configured test owner.',
      );
    }
  }
}
