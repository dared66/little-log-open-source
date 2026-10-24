import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import '../config.dart';
import '../controller.dart';
import '../design.dart';
import '../models.dart';
import '../services/drive_invitation.dart';
import '../services/google_drive.dart';
import '../services/invitation_link.dart';
import '../services/picker.dart';
import 'google_button.dart';

enum OnboardingStage { tour, setup, create, local, join }

class OnboardingPage extends StatefulWidget {
  const OnboardingPage({
    super.key,
    required this.controller,
    this.initialStage = OnboardingStage.tour,
    this.invitation,
    this.addingBaby = false,
  });
  final AppController controller;
  final OnboardingStage initialStage;
  final InvitationLink? invitation;
  final bool addingBaby;

  @override
  State<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends State<OnboardingPage> {
  final baby = TextEditingController();
  final invitationLink = TextEditingController();
  final form = GlobalKey<FormState>();
  final errorKey = GlobalKey();
  final confirmationKey = GlobalKey();
  late OnboardingStage stage = widget.initialStage;
  bool busy = false;
  bool nameSubmitted = false;
  bool loadingLogs = false;
  String? loadedEmail;
  String? error;
  Family? selectedLog;
  String? selectingId;
  List<Map<String, String>>? logs;

  @override
  void initState() {
    super.initState();
    widget.controller.auth.addListener(accountChanged);
    if (widget.initialStage == OnboardingStage.tour) {
      stage = OnboardingStage.values.firstWhere(
        (value) => value.name == widget.controller.onboardingStep,
        orElse: () => OnboardingStage.tour,
      );
    }
    // Resume older setup checkpoints on the consolidated creation screen.
    if (stage == OnboardingStage.setup) stage = OnboardingStage.create;
    if (widget.controller.onboardingSyncedSetup &&
        widget.initialStage != OnboardingStage.join) {
      stage = OnboardingStage.create;
      baby.text = widget.controller.family?.babyName ?? '';
    }
  }

  @override
  void dispose() {
    widget.controller.auth.removeListener(accountChanged);
    baby.dispose();
    invitationLink.dispose();
    super.dispose();
  }

  void reveal(GlobalKey key) =>
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final target = key.currentContext;
        if (mounted && target != null) {
          Scrollable.ensureVisible(target, alignment: 0.2);
        }
      });

  void accountChanged() {
    if (!mounted) return;
    setState(() {
      if (loadedEmail != widget.controller.auth.user?.email) {
        logs = null;
        selectedLog = null;
        error = null;
      }
    });
  }

  void go(OnboardingStage next) => setState(() {
    stage = next;
    error = null;
    if (next == OnboardingStage.join) {
      logs = null;
      loadedEmail = null;
      selectedLog = null;
    }
    if (!widget.addingBaby) {
      unawaited(widget.controller.setOnboardingStep(next.name));
    }
  });

  Future<void> act(Future<void> Function() action) async {
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await action();
    } catch (e) {
      if (mounted) {
        setState(() => error = AppController.friendlyError(e));
        reveal(errorKey);
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> findLogs() async {
    final auth = widget.controller.auth;
    if (loadingLogs || auth.user == null || !auth.driveConnected) return;
    final email = auth.user!.email;
    setState(() {
      loadingLogs = true;
      loadedEmail = email; // Failed requests wait for an explicit retry.
      error = null;
      logs = null;
      selectedLog = null;
    });
    try {
      final found = await widget.controller.drive.listFamilies();
      final prioritized = [
        ...found.where((log) => log['ownedByMe'] != 'true'),
        ...found.where((log) => log['ownedByMe'] == 'true'),
      ];
      if (mounted && auth.user?.email == email) {
        setState(() => logs = prioritized);
      }
    } catch (e) {
      if (mounted && auth.user?.email == email) {
        setState(() => error = AppController.friendlyError(e));
        reveal(errorKey);
      }
    } finally {
      if (mounted) setState(() => loadingLogs = false);
    }
  }

  Future<void> chooseSharedLog({String? expectedFileId}) async {
    String? pickedFileId;
    await act(() async {
      final auth = widget.controller.auth;
      final email = auth.user?.email;
      if (email == null) return;
      final token = await auth.accessToken();
      if (!mounted) return;
      pickedFileId = await pickFamily(
        context,
        token,
        accountEmail: email,
        auth: auth,
        fileId: expectedFileId,
      );
    });
    if (mounted && pickedFileId != null) await preview(pickedFileId!);
  }

  bool get invitedAccountMatches {
    final invited = widget.invitation;
    final signedIn = widget.controller.auth.user?.email;
    return invited == null || signedIn?.toLowerCase() == invited.invitedEmail;
  }

  Future<void> openLinkedInvitation() async {
    final invited = widget.invitation;
    final auth = widget.controller.auth;
    if (invited == null || auth.user == null) return;
    if (!invitedAccountMatches) {
      setState(
        () => error =
            'This invitation is for ${invited.invitedEmail}. Switch to that Google account above.',
      );
      reveal(errorKey);
      return;
    }
    final existing = widget.controller.families
        .where(
          (family) =>
              family.driveFileId == invited.fileId &&
              family.accountId == auth.user!.id,
        )
        .firstOrNull;
    if (existing != null) {
      await act(() => widget.controller.select(existing));
      if (mounted &&
          widget.controller.family?.id == existing.id &&
          Navigator.of(context).canPop()) {
        Navigator.pop(context, true);
      }
      return;
    }
    await openExactLog(invited.fileId);
  }

  Future<void> openInvitationLink() async {
    final id = invitationFileId(invitationLink.text);
    if (id == null) {
      setState(
        () => error =
            'Enter the shared log’s Google Drive link, or ask the sender to share the invitation again.',
      );
      reveal(errorKey);
      return;
    }
    await openExactLog(id);
  }

  Future<void> openExactLog(String fileId) async {
    final account = widget.controller.auth.user;
    if (account == null || busy) return;
    var needsAuthorization = false;
    await act(() async {
      Family log;
      try {
        log = await widget.controller.drive.openFamily(fileId, account.id);
      } on CloudException catch (e) {
        if ((e.status == 404 && e.reason != 'trashed') ||
            (e.status == 403 && e.reason == 'appNotAuthorizedToFile')) {
          needsAuthorization = true;
          return;
        }
        rethrow;
      }
      if (mounted && widget.controller.auth.user?.id == account.id) {
        setState(() => selectedLog = log);
        reveal(confirmationKey);
      }
    });
    if (mounted &&
        needsAuthorization &&
        widget.controller.auth.user?.id == account.id) {
      await chooseSharedLog(expectedFileId: fileId);
    }
  }

  Future<void> preview(String fileId) => act(() async {
    final account = widget.controller.auth.user;
    if (account == null) return;
    setState(() {
      selectingId = fileId;
      selectedLog = null;
    });
    try {
      final baby = await widget.controller.drive.openFamily(fileId, account.id);
      if (mounted && widget.controller.auth.user?.id == account.id) {
        setState(() => selectedLog = baby);
        reveal(confirmationKey);
      }
    } on CloudException catch (e) {
      if (e.status == 403 || e.status == 404) {
        throw StateError(
          'This log could not be opened with ${account.email}. Check that this is the invited account and ask the sender to confirm your Editor access. If access is still shared, select the file again in Google Drive to allow Little Log to use it.',
        );
      }
      rethrow;
    } finally {
      if (mounted) setState(() => selectingId = null);
    }
  });

  Future<void> joinSelected() => act(() async {
    final baby = selectedLog;
    if (baby == null) return;
    final c = widget.controller;
    if (c.family == null) c.setJoiningFromOnboarding(true);
    try {
      await c.join(baby.driveFileId!, expectedFamilyId: baby.id);
      if (mounted && Navigator.of(context).canPop()) {
        Navigator.pop(context, true);
      }
    } finally {
      c.setJoiningFromOnboarding(false);
    }
  });

  String lastUpdatedLabel(String? value) {
    final updated = value == null ? null : DateTime.tryParse(value)?.toLocal();
    if (updated == null) return 'Last updated: unavailable';
    final locale = MaterialLocalizations.of(context);
    final date = locale.formatMediumDate(updated);
    final time = locale.formatTimeOfDay(
      TimeOfDay.fromDateTime(updated),
      alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context),
    );
    return 'Last updated: $date at $time';
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final account = c.auth.user;
    if (stage == OnboardingStage.join &&
        widget.invitation == null &&
        account != null &&
        c.auth.driveConnected &&
        !loadingLogs &&
        loadedEmail != account.email) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) findLogs();
      });
    }
    final canLeavePage = widget.addingBaby
        ? stage != OnboardingStage.join
        : widget.initialStage == OnboardingStage.join ||
              stage == OnboardingStage.tour;
    final showBack =
        stage != OnboardingStage.tour &&
        !(c.onboardingSyncedSetup && stage == OnboardingStage.create);
    return PopScope(
      canPop: !busy && !c.onboardingSyncedSetup && canLeavePage,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && !busy) back();
      },
      child: Theme(
        data: setupTheme(context),
        child: Scaffold(
          appBar: logPageAppBar(
            context,
            stage == OnboardingStage.create || stage == OnboardingStage.local
                ? 'New baby log'
                : stage == OnboardingStage.join
                ? widget.invitation == null
                      ? 'Join a shared log'
                      : 'Join ${widget.invitation!.babyName}’s log'
                : 'Little Log',
            showBackButton: showBack,
            onBack: busy ? () {} : back,
          ),
          body: LogPageFrame(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (stage == OnboardingStage.tour) ...welcome(),
                  if (stage == OnboardingStage.setup ||
                      stage == OnboardingStage.create)
                    ...create(),
                  if (stage == OnboardingStage.local) ...local(),
                  if (stage == OnboardingStage.join) ...joinView(),
                  if (error != null && stage != OnboardingStage.join)
                    Padding(
                      key: errorKey,
                      padding: const EdgeInsets.only(top: 16),
                      child: Semantics(
                        liveRegion: true,
                        child: Text(
                          error!,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> welcome() => [
    const Text(
      'Baby logs',
      style: TextStyle(fontSize: 28, fontWeight: FontWeight.w600),
    ),
    const SizedBox(height: 24),
    FilledButton(
      onPressed: () => go(OnboardingStage.create),
      child: const Text('New baby log'),
    ),
    const SizedBox(height: 12),
    OutlinedButton(
      onPressed: () => go(OnboardingStage.join),
      child: const Text('Join an existing baby log'),
    ),
  ];

  void back() {
    if (busy) return;
    if (widget.controller.onboardingSyncedSetup) {
      if (stage == OnboardingStage.local) go(OnboardingStage.create);
      return;
    }
    if (widget.addingBaby && stage == OnboardingStage.join) {
      go(OnboardingStage.create);
    } else if (widget.addingBaby ||
        widget.initialStage == OnboardingStage.join) {
      Navigator.maybePop(context);
    } else {
      go(OnboardingStage.tour);
    }
  }

  List<Widget> accountControls() {
    final c = widget.controller;
    if (!AppConfig.configured && c.auth.user == null) {
      return [const Text('Google Drive is unavailable in this build.')];
    }
    if (!c.auth.ready) {
      return [Text(c.auth.error ?? 'Preparing Google sign-in…')];
    }
    if (c.auth.user == null) {
      return [
        AbsorbPointer(
          absorbing: busy,
          child: googleButton(
            () => act(c.auth.signIn),
            primary: true,
            style: creationButtonStyle,
          ),
        ),
      ];
    }
    if (stage == OnboardingStage.join) {
      return [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: logPalette(context).surface,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.account_circle_outlined,
                    color: logPalette(context).secondary,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      c.auth.user!.email,
                      style: const TextStyle(fontWeight: FontWeight.w500),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (widget.invitation == null || invitedAccountMatches)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    onPressed: busy
                        ? null
                        : () => act(() async {
                            await c.auth.signOut();
                            loadedEmail = null;
                            logs = null;
                          }),
                    child: const Text('Use a different Google account'),
                  ),
                ),
            ],
          ),
        ),
        if (!c.auth.driveConnected) ...[
          const SizedBox(height: 16),
          FilledButton(
            onPressed: busy || c.auth.checkingDrive
                ? null
                : () => act(c.auth.authorize),
            child: Text(
              c.auth.checkingDrive ? 'Connecting…' : 'Connect Google Drive',
            ),
          ),
        ],
      ];
    }
    return [
      Row(
        children: [
          Icon(
            Icons.account_circle_outlined,
            color: logPalette(context).secondary,
          ),
          const SizedBox(width: 12),
          Expanded(child: Text(c.auth.user!.email)),
          IconButton(
            tooltip: 'Use a different Google account',
            onPressed: busy ? null : () => act(c.auth.signOut),
            icon: const Icon(Icons.swap_horiz),
          ),
        ],
      ),
      if (!c.auth.driveConnected) ...[
        const SizedBox(height: 16),
        FilledButton(
          style: creationButtonStyle,
          onPressed: busy || c.auth.checkingDrive
              ? null
              : () => act(c.auth.authorize),
          child: Text(
            c.auth.checkingDrive ? 'Connecting…' : 'Connect Google Drive',
          ),
        ),
      ],
    ];
  }

  ButtonStyle get creationButtonStyle => FilledButton.styleFrom(
    minimumSize: const Size(48, 52),
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
  );

  List<Widget> create() => creation(localOnly: false);
  List<Widget> local() => creation(localOnly: true);

  List<Widget> creation({required bool localOnly}) {
    final c = widget.controller;
    final canChangeStorage =
        !busy && (!c.onboardingSyncedSetup || c.family?.isLocal == true);
    final palette = logPalette(context);
    final outline = OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: palette.secondary),
    );
    Widget storageOption(
      String label,
      bool selected,
      OnboardingStage target,
    ) => Expanded(
      child: Semantics(
        selected: selected,
        child: OutlinedButton(
          onPressed: canChangeStorage ? () => go(target) : null,
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(48, 52),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 14),
            backgroundColor: selected ? palette.actionTint : palette.surface,
            foregroundColor: selected ? palette.actionInk : palette.ink,
            side: BorderSide(
              color: selected ? palette.actionInk : palette.secondary,
              width: selected ? 1.5 : 1,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          child: Text(label, textAlign: TextAlign.center),
        ),
      ),
    );
    return [
      const FieldLabel('Baby’s name'),
      Form(
        key: form,
        child: TextFormField(
          controller: baby,
          autovalidateMode: nameSubmitted
              ? AutovalidateMode.onUserInteraction
              : AutovalidateMode.disabled,
          readOnly: c.onboardingSyncedSetup,
          maxLength: 60,
          textCapitalization: TextCapitalization.words,
          textInputAction: TextInputAction.done,
          decoration: InputDecoration(
            counterText: '',
            fillColor: palette.surface,
            contentPadding: const EdgeInsets.all(16),
            border: outline,
            enabledBorder: outline,
            focusedBorder: outline.copyWith(
              borderSide: BorderSide(color: palette.actionInk, width: 2),
            ),
          ),
          validator: (value) => value == null || value.trim().isEmpty
              ? 'Enter your baby’s name.'
              : null,
        ),
      ),
      const SizedBox(height: 24),
      const FieldLabel('Storage'),
      IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            storageOption('Google Drive', !localOnly, OnboardingStage.create),
            const SizedBox(width: 8),
            storageOption('This device', localOnly, OnboardingStage.local),
          ],
        ),
      ),
      if (localOnly) ...[
        const SizedBox(height: 12),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.warning_amber_rounded,
              size: 18,
              color: palette.dark
                  ? const Color(0xFFE6BE76)
                  : const Color(0xFF805500),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Stored only on this device. Deleting the app can delete this log.',
                style: TextStyle(
                  fontSize: 13,
                  height: 1.4,
                  color: palette.secondary,
                ),
              ),
            ),
          ],
        ),
      ],
      const SizedBox(height: 24),
      if (!localOnly) ...accountControls(),
      if (localOnly || c.auth.driveConnected) ...[
        if (!localOnly) const SizedBox(height: 16),
        FilledButton(
          style: creationButtonStyle,
          onPressed: busy
              ? null
              : () async {
                  setState(() => nameSubmitted = true);
                  if (!form.currentState!.validate()) return;
                  FocusManager.instance.primaryFocus?.unfocus();
                  var created = false;
                  await act(() async {
                    if (!localOnly) {
                      await c.createSynced(baby.text);
                    } else if (c.onboardingSyncedSetup) {
                      await c.usePendingSetupLocally();
                    } else {
                      await c.createLocal(
                        '${baby.text.trim()}’s family',
                        baby.text,
                      );
                    }
                    created = true;
                  });
                  if (created && mounted && widget.addingBaby) {
                    Navigator.pop(context, true);
                  }
                },
          child: Text(
            busy
                ? 'Saving…'
                : c.onboardingSyncedSetup && !localOnly
                ? 'Retry saving to Google Drive'
                : 'Create baby log',
          ),
        ),
      ],
      if (widget.addingBaby && !c.onboardingSyncedSetup) ...[
        const SizedBox(height: 12),
        TextButton(
          onPressed: busy ? null : () => go(OnboardingStage.join),
          child: const Text('Join an existing baby log'),
        ),
      ],
      if (c.onboardingSyncedSetup && c.family?.isLocal == false) ...[
        const SizedBox(height: 12),
        const Text(
          'The shared log exists. Retry when Google Drive is available.',
        ),
      ],
    ];
  }

  List<Widget> joinView() {
    final c = widget.controller;
    if (selectedLog != null) {
      return [
        Column(
          key: confirmationKey,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (widget.invitation == null) ...[
              Text(
                selectedLog!.babyName,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: LogSpacing.label),
            ],
            Text(
              selectedLog!.ownerEmail == null
                  ? 'Owner unavailable'
                  : 'Owner: ${selectedLog!.ownerEmail}',
            ),
            if (c.families.any(
              (f) =>
                  f.babyName.toLowerCase() ==
                      selectedLog!.babyName.toLowerCase() &&
                  f.id != selectedLog!.id,
            ))
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  'You already have a separate log named ${selectedLog!.babyName}. Joining this log keeps both histories separate. It does not combine or delete entries.',
                ),
              ),
            const SizedBox(height: LogSpacing.field),
            FilledButton(
              onPressed: busy ? null : joinSelected,
              child: Text(busy ? 'Loading shared history…' : 'Join baby log'),
            ),
            if (widget.invitation == null)
              TextButton(
                onPressed: busy
                    ? null
                    : () => setState(() {
                        selectedLog = null;
                        error = null;
                      }),
                child: const Text('Back to shared logs'),
              ),
          ],
        ),

        if (error != null)
          Padding(
            key: errorKey,
            padding: const EdgeInsets.only(top: 16),
            child: Semantics(
              liveRegion: true,
              child: Text(
                error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          ),
      ];
    }
    return [
      ...accountControls(),
      if (error != null)
        Padding(
          key: errorKey,
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Semantics(
            liveRegion: true,
            child: Text(
              error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        ),
      if (c.auth.driveConnected) ...[
        const SizedBox(height: LogSpacing.section),
        if (widget.invitation != null) ...[
          if (!invitedAccountMatches) ...[
            Text(
              'Switch to ${widget.invitation!.invitedEmail} to accept this invitation.',
            ),
            const SizedBox(height: LogSpacing.content),
          ],
          FilledButton(
            onPressed: busy || loadingLogs
                ? null
                : !invitedAccountMatches
                ? () => act(() async {
                    await c.auth.signOut();
                    loadedEmail = null;
                    logs = null;
                  })
                : openLinkedInvitation,
            child: Text(
              !invitedAccountMatches
                  ? 'Switch account'
                  : c.families.any(
                      (family) =>
                          family.driveFileId == widget.invitation!.fileId &&
                          family.accountId == c.auth.user?.id,
                    )
                  ? 'Open log'
                  : 'Continue',
            ),
          ),
          const SizedBox(height: LogSpacing.content),
        ],
        if (widget.invitation == null) ...[
          TextField(
            controller: invitationLink,
            enabled: !busy && !loadingLogs,
            autocorrect: false,
            keyboardType: TextInputType.url,
            textCapitalization: TextCapitalization.none,
            decoration: InputDecoration(
              labelText: 'Shared log’s Google Drive link',
              suffixIcon: IconButton(
                tooltip: 'Paste link from clipboard',
                onPressed: busy || loadingLogs
                    ? null
                    : () async {
                        final data = await Clipboard.getData(
                          Clipboard.kTextPlain,
                        );
                        if (data?.text != null) {
                          invitationLink.text = data!.text!;
                        }
                      },
                icon: const Icon(Icons.content_paste, size: 20),
              ),
            ),
          ),
          const SizedBox(height: LogSpacing.content),
          FilledButton(
            onPressed: busy || loadingLogs ? null : openInvitationLink,
            child: const Text('Open log'),
          ),
          const SizedBox(height: LogSpacing.content),
          OutlinedButton.icon(
            onPressed: busy || loadingLogs ? null : () => chooseSharedLog(),
            icon: const Icon(Icons.folder_open),
            label: const Text('Browse shared logs'),
          ),
          const SizedBox(height: LogSpacing.label),
        ],
        if (widget.invitation == null) ...[
          const SizedBox(height: LogSpacing.section),
          const Divider(),
          const SizedBox(height: LogSpacing.content),
          const Text(
            'Your logs',
            style: TextStyle(fontSize: 19, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: LogSpacing.label),
          if (loadingLogs) const LinearProgressIndicator(),
          if (logs?.isEmpty == true)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text('No baby logs available yet.'),
            ),
        ],
        if (widget.invitation == null) ...[
          for (final log in logs ?? const <Map<String, String>>[])
            Card(
              key: ValueKey('available-log-${log['id']}'),
              margin: const EdgeInsets.only(bottom: 12),
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: busy ? null : () => preview(log['id']!),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        log['babyName'] ?? 'Baby',
                        style: const TextStyle(
                          fontSize: 21,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: LogSpacing.detail),
                      Text(
                        log['ownedByMe'] == 'true'
                            ? 'Your log'
                            : 'Shared with you',
                        style: TextStyle(color: logPalette(context).secondary),
                      ),
                      const SizedBox(height: LogSpacing.label),
                      Text(
                        log['ownerEmail']?.isNotEmpty == true
                            ? 'Owner: ${log['ownerEmail']}'
                            : 'Owner: unavailable',
                      ),
                      if (log['ownedByMe'] != 'true' &&
                          log['sharedByEmail']?.isNotEmpty == true &&
                          log['sharedByEmail']?.toLowerCase() !=
                              log['ownerEmail']?.toLowerCase())
                        Text('Shared by: ${log['sharedByEmail']}'),
                      Text(lastUpdatedLabel(log['modifiedTime'])),
                      if (selectingId == log['id'])
                        const Text('Checking this baby’s log…'),
                    ],
                  ),
                ),
              ),
            ),
        ],
        if (widget.invitation == null)
          OutlinedButton(
            onPressed: loadingLogs || busy ? null : findLogs,
            child: Text(error == null ? 'Refresh logs' : 'Try again'),
          ),
      ],
    ];
  }
}
