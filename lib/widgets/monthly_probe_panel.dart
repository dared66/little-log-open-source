import 'package:flutter/material.dart';
import '../services/google_drive.dart';

/// Included only in builds explicitly enabling MONTHLY_PERMISSION_PROBE.
class MonthlyProbePanel extends StatefulWidget {
  const MonthlyProbePanel({super.key, required this.drive});
  final GoogleDrive drive;
  @override
  State<MonthlyProbePanel> createState() => _MonthlyProbePanelState();
}

class _MonthlyProbePanelState extends State<MonthlyProbePanel> {
  final folder = TextEditingController();
  final email = TextEditingController();
  final month = TextEditingController(text: '2026-09');
  bool busy = false;
  String status = 'Synthetic test only. Real family records are not modified.';
  Future<void> run(Future<String> Function() action) async {
    setState(() {
      busy = true;
      status = 'Running monthly access test…';
    });
    try {
      final result = await action();
      if (mounted) setState(() => status = result);
    } catch (e) {
      if (mounted) setState(() => status = e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  void dispose() {
    folder.dispose();
    email.dispose();
    month.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const Divider(height: 32),
      const Text(
        'Monthly sharing test',
        style: TextStyle(fontWeight: FontWeight.bold),
      ),
      TextField(
        controller: folder,
        decoration: const InputDecoration(
          labelText: 'Synthetic test folder ID',
        ),
      ),
      OutlinedButton(
        onPressed: busy
            ? null
            : () => run(() async {
                folder.text = await widget.drive.createMonthlyProbeFolder();
                return 'Created synthetic test folder: ${folder.text}';
              }),
        child: const Text('Create synthetic test folder'),
      ),
      TextField(
        controller: email,
        decoration: const InputDecoration(labelText: 'Test caregiver email'),
      ),
      OutlinedButton(
        onPressed: busy
            ? null
            : () => run(() async {
                await widget.drive.shareMonthlyProbe(
                  folder.text.trim(),
                  email.text.trim(),
                );
                return 'Test folder shared with ${email.text.trim()}. No email notification sent.';
              }),
        child: const Text('Share synthetic folder without email'),
      ),
      TextField(
        controller: month,
        decoration: const InputDecoration(labelText: 'Test month YYYY-MM'),
      ),
      OutlinedButton(
        onPressed: busy
            ? null
            : () => run(() async {
                final id = await widget.drive.createMonthlyProbeFile(
                  folder.text.trim(),
                  month.text.trim(),
                );
                return 'Created ${month.text.trim()}.csv: $id';
              }),
        child: const Text('Create synthetic month'),
      ),
      OutlinedButton(
        onPressed: busy
            ? null
            : () => run(
                () => widget.drive.verifyMonthlyProbe(folder.text.trim()),
              ),
        child: const Text('Verify monthly read and write'),
      ),
      SelectableText(status),
    ],
  );
}
