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
  bool submitted = false;
  String? error;
  String? sentTo;
  @override
  void dispose() {
    email.dispose();
    super.dispose();
  }

  Future<void> send() async {
    if (busy) return;
    setState(() => submitted = true);
    if (!form.currentState!.validate()) return;
    FocusManager.instance.primaryFocus?.unfocus();
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
    return Theme(
      data: setupTheme(context),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (sentTo != null) ...[
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: palette.surface,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Invitation sent',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      PopupMenuButton<String>(
                        padding: EdgeInsets.zero,
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
                          PopupMenuItem(
                            value: 'email',
                            child: Text('Send by email'),
                          ),
                          PopupMenuItem(
                            value: 'copy',
                            child: Text('Copy invitation'),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(sentTo!, style: TextStyle(color: palette.secondary)),
                ],
              ),
            ),
            const SizedBox(height: 24),
            if (widget.onDone != null) ...[
              FilledButton(onPressed: widget.onDone, child: const Text('Done')),
              const SizedBox(height: 12),
            ],
            OutlinedButton.icon(
              icon: const Icon(Icons.ios_share, size: 20),
              label: const Text('Share invitation'),
              onPressed: shareInvitation,
            ),
            const SizedBox(height: 16),
            TextButton(
              onPressed: () => setState(() {
                sentTo = null;
                error = null;
                email.clear();
                submitted = false;
              }),
              child: const Text('Invite someone else'),
            ),
          ] else ...[
            const FieldLabel('Google email'),
            Form(
              key: form,
              child: TextFormField(
                controller: email,
                autovalidateMode: submitted
                    ? AutovalidateMode.onUserInteraction
                    : AutovalidateMode.disabled,
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
      ),
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
