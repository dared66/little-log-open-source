import '../design.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../controller.dart';
import '../models.dart';
import '../services/invitation_link_bridge.dart';

/// The same invitation contract in first setup and Family & sharing.
class InviteCaregiverForm extends StatefulWidget {
  const InviteCaregiverForm({
    super.key,
    required this.controller,
    required this.family,
    this.onSent,
    this.onBusy,
    this.onDone,
  });
  final AppController controller;
  final Family family;
  final VoidCallback? onSent;
  final ValueChanged<bool>? onBusy;
  final VoidCallback? onDone;
  @override
  State<InviteCaregiverForm> createState() => _InviteCaregiverFormState();
}

class _InviteCaregiverFormState extends State<InviteCaregiverForm> {
  final email = TextEditingController();
  final form = GlobalKey<FormState>();
  bool busy = false;
  String? error;
  String? sentTo;
  @override
  void dispose() {
    email.dispose();
    super.dispose();
  }

  Future<void> send() async {
    if (busy || !form.currentState!.validate()) return;
    final address = email.text.trim();
    setState(() {
      busy = true;
      error = null;
    });
    widget.onBusy?.call(true);
    try {
      await widget.controller.drive.invite(widget.family, address);
      if (!mounted) return;
      setState(() => sentTo = address);
      widget.onSent?.call();
    } catch (e) {
      if (mounted) setState(() => error = AppController.friendlyError(e));
    } finally {
      if (mounted) {
        setState(() => busy = false);
        widget.onBusy?.call(false);
      }
    }
  }

  Future<void> composeJoiningEmail() async {
    final recipient = sentTo;
    if (recipient == null) return;
    final details = {
      'subject': 'Join ${widget.family.babyName}’s Little Log',
      'body': widget.controller.drive.invitationInstructions(
        widget.family,
        recipient,
      ),
    };
    final draft = Uri(
      scheme: 'mailto',
      path: recipient,
      query: details.entries
          .map(
            (entry) =>
                '${Uri.encodeComponent(entry.key)}=${Uri.encodeComponent(entry.value)}',
          )
          .join('&'),
    );
    var opened = false;
    try {
      opened = await launchUrl(draft, mode: LaunchMode.externalApplication);
    } catch (_) {
      // The copy action below remains available if no email app can handle it.
    }
    if (!opened && mounted) {
      setState(
        () => error =
            'Email could not open. Use the menu to copy the invitation.',
      );
    }
  }

  Future<void> shareInvitation() async {
    final recipient = sentTo;
    if (recipient == null) return;
    try {
      await InvitationLinkBridge().share(
        widget.controller.drive.invitationInstructions(
          widget.family,
          recipient,
        ),
      );
    } catch (_) {
      if (mounted) {
        setState(
          () => error =
              'The share sheet could not open. Use the menu to copy the invitation.',
        );
      }
    }
  }

  Future<void> copyInvitation() async {
    await Clipboard.setData(
      ClipboardData(
        text: widget.controller.drive.invitationInstructions(
          widget.family,
          sentTo!,
        ),
      ),
    );
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Invitation copied')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = logPalette(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (sentTo != null) ...[
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: palette.surface,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.check_circle_outline,
                  color: palette.actionInk,
                  size: 24,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Invitation sent',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(sentTo!, style: TextStyle(color: palette.secondary)),
                      const SizedBox(height: 12),
                      const Text('They can now view and edit this log.'),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          if (widget.onDone != null) ...[
            FilledButton(onPressed: widget.onDone, child: const Text('Done')),
            const SizedBox(height: 12),
          ],
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.ios_share, size: 20),
                  label: const Text('Share invitation'),
                  onPressed: shareInvitation,
                ),
              ),
              const SizedBox(width: 8),
              PopupMenuButton<String>(
                tooltip: 'More ways to send',
                icon: const Icon(Icons.more_horiz),
                onSelected: (value) {
                  if (value == 'copy') {
                    copyInvitation();
                  } else {
                    composeJoiningEmail();
                  }
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'email', child: Text('Send by email')),
                  PopupMenuItem(value: 'copy', child: Text('Copy invitation')),
                ],
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Optional — share a copy directly.',
            style: TextStyle(fontSize: 13, color: palette.secondary),
          ),
          const SizedBox(height: 16),
          TextButton(
            onPressed: () => setState(() {
              sentTo = null;
              error = null;
              email.clear();
            }),
            child: const Text('Invite someone else'),
          ),
        ] else ...[
          Text(
            'Share ${widget.family.babyName}’s day with another caregiver.',
            style: TextStyle(color: palette.secondary, height: 1.5),
          ),
          const SizedBox(height: 24),
          const FieldLabel('Google email'),
          Form(
            key: form,
            child: TextFormField(
              controller: email,
              enabled: !busy,
              keyboardType: TextInputType.emailAddress,
              autofillHints: const [AutofillHints.email],
              autocorrect: false,
              textCapitalization: TextCapitalization.none,
              decoration: const InputDecoration(hintText: 'name@gmail.com'),
              validator: (value) =>
                  RegExp(
                    r'^[^\s@]+@[^\s@]+\.[^\s@]+$',
                  ).hasMatch(value?.trim() ?? '')
                  ? null
                  : 'Enter a valid email address.',
              onFieldSubmitted: (_) => send(),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'They’ll be able to view, add and edit entries.',
            style: TextStyle(fontSize: 13, color: palette.secondary),
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: busy ? null : send,
            child: Text(busy ? 'Sending invitation…' : 'Send invitation'),
          ),
        ],
        if (error != null) ...[
          const SizedBox(height: 12),
          Semantics(
            liveRegion: true,
            child: Text(
              error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        ],
      ],
    );
  }
}

class InviteCaregiverPage extends StatelessWidget {
  const InviteCaregiverPage({
    super.key,
    required this.controller,
    required this.family,
    this.onSent,
  });
  final AppController controller;
  final Family family;
  final VoidCallback? onSent;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: logPageAppBar(context, 'Invite a caregiver'),
    body: LogPageFrame(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: InviteCaregiverForm(
          controller: controller,
          family: family,
          onSent: onSent,
          onDone: () => Navigator.of(context).pop(),
        ),
      ),
    ),
  );
}
