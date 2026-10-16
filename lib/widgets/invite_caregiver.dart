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
  });
  final AppController controller;
  final Family family;
  final VoidCallback? onSent;
  final ValueChanged<bool>? onBusy;
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
            'No email app opened. Copy the message below and send it by text or email.',
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
              'The share sheet could not open. Copy the message below and send it yourself.',
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (sentTo != null) ...[
        const Text(
          'Access granted',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: LogSpacing.label),
        Text(
          'Google Drive was asked to email the invitation to $sentTo. They can now view and add entries to this log.',
        ),
        const SizedBox(height: LogSpacing.content),
        ExpansionTile(
          tilePadding: EdgeInsets.zero,
          title: const Text('Share joining instructions'),
          subtitle: const Text('Optional, if they cannot find Google’s email'),
          children: [
            const Text(
              'The message includes the exact Google Drive file link and the steps to join in Little Log.',
            ),
            SelectableText(
              widget.controller.drive.invitationInstructions(
                widget.family,
                sentTo!,
              ),
            ),
            FilledButton.icon(
              icon: const Icon(Icons.ios_share),
              label: const Text('Share instructions'),
              onPressed: shareInvitation,
            ),
            OutlinedButton.icon(
              icon: const Icon(Icons.email_outlined),
              label: const Text('Compose joining email'),
              onPressed: composeJoiningEmail,
            ),
            OutlinedButton.icon(
              icon: const Icon(Icons.copy),
              label: const Text('Copy message to send'),
              onPressed: () async {
                await Clipboard.setData(
                  ClipboardData(
                    text: widget.controller.drive.invitationInstructions(
                      widget.family,
                      sentTo!,
                    ),
                  ),
                );
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Joining instructions copied'),
                    ),
                  );
                }
              },
            ),
          ],
        ),
        TextButton(
          onPressed: () => setState(() {
            sentTo = null;
            email.clear();
          }),
          child: const Text('Invite another caregiver'),
        ),
      ] else ...[
        Text(
          'Invite someone to ${widget.family.babyName}’s log. They can view the full history and add or change entries.',
        ),
        const SizedBox(height: LogSpacing.content),
        const Text(
          'Google Drive will email them instructions for joining Little Log.',
        ),
        const SizedBox(height: LogSpacing.field),
        const Text('Caregiver’s Google email'),
        const SizedBox(height: LogSpacing.label),
        Form(
          key: form,
          child: TextFormField(
            controller: email,
            enabled: !busy,
            keyboardType: TextInputType.emailAddress,
            autocorrect: false,
            textCapitalization: TextCapitalization.none,
            decoration: const InputDecoration(
              hintText: 'name@gmail.com',
              border: OutlineInputBorder(),
              enabledBorder: OutlineInputBorder(),
            ),
            validator: (value) =>
                RegExp(
                  r'^[^\s@]+@[^\s@]+\.[^\s@]+$',
                ).hasMatch(value?.trim() ?? '')
                ? null
                : 'Enter a valid email address.',
            onFieldSubmitted: (_) => send(),
          ),
        ),
        const SizedBox(height: LogSpacing.content),
        if (error != null) ...[
          Semantics(
            liveRegion: true,
            child: Text(
              error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
          const SizedBox(height: LogSpacing.label),
        ],
        FilledButton.icon(
          onPressed: busy ? null : send,
          icon: const Icon(Icons.person_add_outlined),
          label: Text(busy ? 'Sending invitation…' : 'Send invitation'),
        ),
        const SizedBox(height: LogSpacing.label),
        const Text('You can change or remove their access in Google Drive.'),
      ],
    ],
  );
}
