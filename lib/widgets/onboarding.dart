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
  });
  final AppController controller;
  final OnboardingStage initialStage;
  final InvitationLink? invitation;

  @override
  State<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends State<OnboardingPage> {
  static const _contentWidth = 480.0;
  static const _gutter = 28.0;
  final baby = TextEditingController();
  final invitationLink = TextEditingController();
  final form = GlobalKey<FormState>();
  final errorKey = GlobalKey();
  final confirmationKey = GlobalKey();
  late OnboardingStage stage = widget.initialStage;
  int slide = 0;
  bool busy = false;
  bool loadingLogs = false;
  String? loadedEmail;
  String? error;
  Family? selectedLog;
  String? selectingId;
  List<Map<String, String>>? logs;

  static const slides = [
    (
      'Less remembering. More caring.',
      'Feeds, sleep, diapers, and the little details of each day stay together.',
      Icons.favorite_outline,
    ),
    (
      'Everyone caring for your baby stays in the loop.',
      'Caregivers can add to the same completed history, so handoffs are easier.',
      Icons.people_outline,
    ),
    (
      'Your baby’s history, in your hands.',
      'Save on your device, or connect Google Drive to sync and share with caregivers. You can log offline with either option.',
      Icons.cloud_outlined,
    ),
  ];

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
    unawaited(widget.controller.setOnboardingStep(next.name));
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
    await chooseSharedLog(expectedFileId: invited.fileId);
  }

  Future<void> openInvitationLink() async {
    final id = invitationFileId(invitationLink.text);
    if (id == null) {
      setState(
        () => error =
            'Paste the Google Drive file link for the shared log. It starts with https://drive.google.com/file/d/. Ask the sender to copy the joining instructions if you only received a Drive notification.',
      );
      reveal(errorKey);
      return;
    }
    await chooseSharedLog(expectedFileId: id);
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
    final canLeavePage =
        widget.initialStage == OnboardingStage.join ||
        (stage == OnboardingStage.tour && slide == 0);
    final pinTourActions =
        MediaQuery.sizeOf(context).height >= 600 &&
        MediaQuery.textScalerOf(context).scale(14) <= 21;
    final showBack =
        !((stage == OnboardingStage.tour &&
                slide == 0 &&
                widget.initialStage == OnboardingStage.tour) ||
            (c.onboardingSyncedSetup && stage == OnboardingStage.create));
    return PopScope(
      canPop: !busy && !c.onboardingSyncedSetup && canLeavePage,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && !busy) back();
      },
      child: Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: false,
          centerTitle: false,
          titleSpacing: 0,
          toolbarHeight: (16 + MediaQuery.textScalerOf(context).scale(22) * 1.3)
              .clamp(kToolbarHeight, double.infinity)
              .toDouble(),
          title: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: _contentWidth),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: _gutter),
                child: Row(
                  children: [
                    if (showBack) ...[
                      IconButton(
                        tooltip: 'Back',
                        icon: const Icon(Icons.arrow_back),
                        onPressed: busy ? null : back,
                      ),
                      const SizedBox(width: 8),
                    ],
                    const Expanded(
                      child: Text(
                        'Little Log',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: _contentWidth),
              child: Column(
                children: [
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(
                        _gutter,
                        20,
                        _gutter,
                        20,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (stage == OnboardingStage.tour) ...[
                            ...tour(),
                            if (!pinTourActions) ...[
                              const SizedBox(height: 32),
                              ...tourActions(),
                            ],
                          ],
                          if (stage == OnboardingStage.setup) ...setup(),
                          if (stage == OnboardingStage.create) ...create(),
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
                  if (stage == OnboardingStage.tour && pinTourActions)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(
                        _gutter,
                        8,
                        _gutter,
                        18,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: tourActions(),
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

  List<Widget> tour() {
    final item = slides[slide];
    return [
      Align(
        alignment: Alignment.centerRight,
        child: TextButton(
          style: TextButton.styleFrom(
            padding: EdgeInsets.zero,
            alignment: Alignment.centerRight,
          ),
          onPressed: () => setState(() => slide = slides.length - 1),
          child: const Text('Skip introduction'),
        ),
      ),
      const SizedBox(height: 28),
      CircleAvatar(
        radius: 42,
        backgroundColor: logPalette(context).actionTint,
        child: Icon(item.$3, size: 42, color: logPalette(context).actionInk),
      ),
      const SizedBox(height: 32),
      Text(
        item.$1,
        style: TextStyle(
          fontSize: 32,
          height: 1.12,
          fontWeight: FontWeight.w700,
          color: logPalette(context).actionInk,
        ),
      ),
      const SizedBox(height: 18),
      Text(
        item.$2,
        style: TextStyle(
          fontSize: 17,
          height: 1.5,
          color: logPalette(context).secondary,
        ),
      ),
      if (slide == 0) ...[
        const SizedBox(height: LogSpacing.section),
        Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: const [
                Row(
                  children: [
                    Icon(Icons.local_drink_outlined, size: 19),
                    SizedBox(width: 12),
                    Expanded(child: Text('8:15  Bottle · 120 ml')),
                  ],
                ),
                SizedBox(height: LogSpacing.content),
                Row(
                  children: [
                    Icon(Icons.bedtime_outlined, size: 19),
                    SizedBox(width: 12),
                    Expanded(child: Text('9:40  Nap started')),
                  ],
                ),
                SizedBox(height: LogSpacing.content),
                Row(
                  children: [
                    Icon(Icons.child_care_outlined, size: 19),
                    SizedBox(width: 12),
                    Expanded(child: Text('11:05  Diaper changed')),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
      const SizedBox(height: 32),
      Row(
        children: [
          for (var i = 0; i < slides.length; i++)
            Padding(
              padding: const EdgeInsets.only(right: 7),
              child: CircleAvatar(
                radius: 4,
                backgroundColor: i == slide
                    ? logPalette(context).actionInk
                    : Theme.of(context).colorScheme.outlineVariant,
              ),
            ),
        ],
      ),
    ];
  }

  List<Widget> tourActions() => [
    FilledButton(
      onPressed: () => slide < slides.length - 1
          ? setState(() => slide++)
          : go(OnboardingStage.setup),
      child: Text(slide < slides.length - 1 ? 'Next' : 'Set up my baby'),
    ),
    const SizedBox(height: 10),
    OutlinedButton(
      onPressed: () => go(OnboardingStage.join),
      child: const Text('Join an existing baby log'),
    ),
    const SizedBox(height: LogSpacing.label),
    Text(
      'Use an invitation from a parent or caregiver.',
      textAlign: TextAlign.center,
      style: TextStyle(color: logPalette(context).secondary, height: 1.4),
    ),
  ];

  void back() {
    if (busy) return;
    if (widget.controller.onboardingSyncedSetup) {
      if (stage == OnboardingStage.local) go(OnboardingStage.create);
      return;
    }
    if (widget.initialStage == OnboardingStage.join) {
      Navigator.maybePop(context);
    } else if (stage == OnboardingStage.tour) {
      if (slide > 0) setState(() => slide--);
    } else if (stage == OnboardingStage.create ||
        stage == OnboardingStage.local) {
      go(OnboardingStage.setup);
    } else {
      go(OnboardingStage.tour);
    }
  }

  List<Widget> setup() => [
    Text(
      'Set up my baby',
      style: TextStyle(
        fontSize: 29,
        fontWeight: FontWeight.w700,
        color: logPalette(context).actionInk,
      ),
    ),
    const SizedBox(height: 10),
    Text(
      'Where would you like to save your baby’s log?',
      style: TextStyle(color: logPalette(context).secondary, height: 1.5),
    ),
    const SizedBox(height: LogSpacing.section),
    storageOption(
      icon: Icons.cloud_outlined,
      title: 'Google Drive',
      description:
          'Keep a synced copy in your Google Drive and share the log with caregivers. You can still log offline.',
      action: 'Use Google Drive',
      onPressed: () => go(OnboardingStage.create),
      primary: true,
    ),
    const SizedBox(height: LogSpacing.field),
    storageOption(
      icon: Icons.phone_iphone,
      title: 'This device only',
      description:
          'Save without a Google account. The log won’t sync or be shared with caregivers. You can connect Google Drive later in Settings.',
      action: 'Save only on this device',
      onPressed: () => go(OnboardingStage.local),
    ),
  ];

  Widget storageOption({
    required IconData icon,
    required String title,
    required String description,
    required String action,
    required VoidCallback onPressed,
    bool primary = false,
  }) => Card(
    margin: EdgeInsets.zero,
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(icon, color: logPalette(context).actionInk),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: LogSpacing.content),
          Text(
            description,
            style: TextStyle(color: logPalette(context).secondary, height: 1.5),
          ),
          const SizedBox(height: LogSpacing.field),
          if (primary)
            FilledButton(onPressed: onPressed, child: Text(action))
          else
            OutlinedButton(onPressed: onPressed, child: Text(action)),
        ],
      ),
    ),
  );

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
          child: googleButton(() => act(c.auth.signIn)),
        ),
      ];
    }
    if (stage == OnboardingStage.join) {
      return [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: logPalette(context).surface,
            borderRadius: BorderRadius.circular(20),
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
      ListTile(
        contentPadding: EdgeInsets.zero,
        leading: const Icon(Icons.account_circle_outlined),
        title: Text(c.auth.user!.email),
        subtitle: Text(
          stage == OnboardingStage.join
              ? 'Joining with this Google account'
              : 'Google account',
        ),
      ),
      TextButton(
        onPressed: busy
            ? null
            : () => act(() async {
                await c.auth.signOut();
                loadedEmail = null;
                logs = null;
              }),
        child: const Text('Use a different Google account'),
      ),
      if (!c.auth.driveConnected)
        FilledButton(
          onPressed: busy || c.auth.checkingDrive
              ? null
              : () => act(c.auth.authorize),
          child: Text(
            c.auth.checkingDrive
                ? 'Checking Google Drive…'
                : 'Connect Google Drive',
          ),
        ),
    ];
  }

  List<Widget> create() {
    final c = widget.controller;
    return [
      Icon(
        Icons.cloud_outlined,
        size: 46,
        color: logPalette(context).actionInk,
      ),
      const SizedBox(height: LogSpacing.section),
      Text(
        'Set up with Google Drive',
        style: TextStyle(
          fontSize: 29,
          fontWeight: FontWeight.w700,
          color: logPalette(context).actionInk,
        ),
      ),
      const SizedBox(height: 10),
      Text(
        'Save your baby’s completed history to your Google Drive and share it with caregivers.',
        style: TextStyle(color: logPalette(context).secondary, height: 1.5),
      ),
      const SizedBox(height: LogSpacing.section),
      ...accountControls(),
      const SizedBox(height: LogSpacing.section),
      Form(
        key: form,
        child: TextFormField(
          controller: baby,
          readOnly: c.onboardingSyncedSetup,
          maxLength: 60,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            labelText: 'Baby’s name',
            hintText: 'e.g. Robin',
            counterText: '',
          ),
          validator: (value) => value == null || value.trim().isEmpty
              ? 'Enter your baby’s name.'
              : null,
        ),
      ),
      const SizedBox(height: LogSpacing.content),
      FilledButton(
        onPressed: busy || !c.auth.driveConnected
            ? null
            : () {
                if (form.currentState!.validate()) {
                  act(() => c.createSynced(baby.text));
                }
              },
        child: Text(
          busy
              ? 'Saving…'
              : c.onboardingSyncedSetup
              ? 'Retry saving to Google Drive'
              : 'Create baby log',
        ),
      ),
      const SizedBox(height: LogSpacing.content),
      if (!c.onboardingSyncedSetup || c.family?.isLocal == true)
        TextButton(
          onPressed: busy ? null : () => go(OnboardingStage.local),
          child: const Text('Save only on this device'),
        )
      else
        const Text(
          'Your shared log was created. Retry saving when Drive is available.',
        ),
    ];
  }

  List<Widget> local() {
    final c = widget.controller;
    return [
      Icon(Icons.phone_iphone, size: 46, color: logPalette(context).actionInk),
      const SizedBox(height: LogSpacing.section),
      Text(
        'Set up on this device',
        style: TextStyle(
          fontSize: 29,
          fontWeight: FontWeight.w700,
          color: logPalette(context).actionInk,
        ),
      ),
      const SizedBox(height: 10),
      Text(
        'Entries stay only on this device without syncing or sharing. You can connect Google Drive later in Settings. If you lose this device or remove the app, you could lose the log.',
        style: TextStyle(color: logPalette(context).secondary, height: 1.5),
      ),
      const SizedBox(height: LogSpacing.section),
      Form(
        key: form,
        child: TextFormField(
          controller: baby,
          readOnly: c.onboardingSyncedSetup,
          maxLength: 60,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            labelText: 'Baby’s name',
            counterText: '',
          ),
          validator: (value) => value == null || value.trim().isEmpty
              ? 'Enter your baby’s name.'
              : null,
        ),
      ),
      const SizedBox(height: LogSpacing.content),
      FilledButton(
        onPressed: busy
            ? null
            : () {
                if (!form.currentState!.validate()) return;
                act(() async {
                  if (c.onboardingSyncedSetup) {
                    await c.usePendingSetupLocally();
                  } else {
                    await c.createLocal(
                      '${baby.text.trim()}’s family',
                      baby.text,
                    );
                  }
                });
              },
        child: Text(busy ? 'Saving…' : 'Create baby log'),
      ),
    ];
  }

  List<Widget> joinView() {
    final c = widget.controller;
    if (selectedLog != null) {
      return [
        const Text(
          'Ready to join',
          style: TextStyle(fontSize: 28, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 12),
        Text(
          'Confirm the log shared with you.',
          style: TextStyle(color: logPalette(context).secondary),
        ),
        const SizedBox(height: 24),

        Card(
          key: confirmationKey,
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  selectedLog!.babyName,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: LogSpacing.label),
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
                const SizedBox(height: LogSpacing.label),
                const Text('You’ll see existing entries and can add your own.'),
                const SizedBox(height: LogSpacing.content),
                FilledButton(
                  onPressed: busy ? null : joinSelected,
                  child: Text(
                    busy ? 'Loading shared history…' : 'Join baby log',
                  ),
                ),
                TextButton(
                  onPressed: busy
                      ? null
                      : () => setState(() {
                          selectedLog = null;
                          error = null;
                        }),
                  child: const Text('Choose a different baby'),
                ),
              ],
            ),
          ),
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
      Text(
        widget.invitation == null
            ? 'Join a shared log'
            : 'Join ${widget.invitation!.babyName}’s log',
        style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w600),
      ),
      const SizedBox(height: 12),
      Text(
        widget.invitation == null
            ? 'Use the Google account your caregiver invited.'
            : 'Invited as ${widget.invitation!.invitedEmail}',
        style: TextStyle(color: logPalette(context).secondary, height: 1.5),
      ),
      const SizedBox(height: 24),
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
          Text(
            invitedAccountMatches
                ? 'Choose the shared log in Google Drive to continue.'
                : 'Switch to ${widget.invitation!.invitedEmail} to accept this invitation.',
          ),
          const SizedBox(height: LogSpacing.content),
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
          const Text('Paste the Drive link from your invitation.'),
          const SizedBox(height: LogSpacing.content),
          TextField(
            controller: invitationLink,
            enabled: !busy && !loadingLogs,
            autocorrect: false,
            keyboardType: TextInputType.url,
            textCapitalization: TextCapitalization.none,
            decoration: const InputDecoration(
              labelText: 'Shared log’s Google Drive link',
              hintText: 'https://drive.google.com/file/d/…/view',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: LogSpacing.label),
          TextButton.icon(
            onPressed: busy || loadingLogs
                ? null
                : () async {
                    final data = await Clipboard.getData(Clipboard.kTextPlain);
                    if (data?.text != null) invitationLink.text = data!.text!;
                  },
            icon: const Icon(Icons.content_paste),
            label: const Text('Paste link from clipboard'),
          ),
          const SizedBox(height: LogSpacing.label),
          FilledButton(
            onPressed: busy || loadingLogs ? null : openInvitationLink,
            child: const Text('Open this shared log in Google Drive'),
          ),
          const SizedBox(height: LogSpacing.content),
          const Text('Or find the log in Google Drive.'),
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
          const Text('Previously connected logs'),
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
              margin: EdgeInsets.zero,
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
                            ? 'Your own log — not the invitation'
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
                          log['sharedByEmail']?.isNotEmpty == true)
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
            child: Text(error == null ? 'Refresh available logs' : 'Try again'),
          ),
      ],
    ];
  }
}
