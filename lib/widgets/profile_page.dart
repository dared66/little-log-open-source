import '../design.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../controller.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key, required this.controller});
  final AppController controller;
  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  late final String familyId, babyName;
  DateTime? birthDate;
  String? gender;
  TimeOfDay? nightStart, nightEnd;
  bool saving = false;
  String? error;
  @override
  void initState() {
    super.initState();
    familyId = widget.controller.family!.id;
    babyName = widget.controller.family!.babyName;
    final p = widget.controller.babyProfile;
    birthDate = DateTime.tryParse(p['birthDate'] as String? ?? '');
    gender = p['gender'] as String?;
    TimeOfDay? time(Object? v) {
      if (v is! String) return null;
      final x = v.split(':');
      return TimeOfDay(hour: int.parse(x[0]), minute: int.parse(x[1]));
    }

    nightStart = time(p['nightStart']);
    nightEnd = time(p['nightEnd']);
  }

  String clock(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: logPageAppBar(context, '$babyName’s profile'),
    body: LogPageFrame(
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Birth date'),
            subtitle: Text(
              birthDate == null
                  ? 'Not recorded'
                  : DateFormat.yMMMd().format(birthDate!),
            ),
            trailing: const Icon(Icons.calendar_today),
            onTap: saving
                ? null
                : () async {
                    final date = await showDatePicker(
                      context: context,
                      initialDate: birthDate ?? DateTime.now(),
                      firstDate: DateTime(1900),
                      lastDate: DateTime.now(),
                    );
                    if (date != null && mounted) {
                      setState(() => birthDate = date);
                    }
                  },
          ),
          if (birthDate != null)
            Text(
              'Age: ${DateTime.now().difference(birthDate!).inDays ~/ 7} weeks, ${DateTime.now().difference(birthDate!).inDays % 7} days',
            ),
          const SizedBox(height: LogSpacing.section),
          DropdownButtonFormField<String>(
            isExpanded: true,
            initialValue: gender ?? 'UNSPECIFIED',
            decoration: const InputDecoration(labelText: 'Sex (optional)'),
            items: const [
              DropdownMenuItem(
                value: 'UNSPECIFIED',
                child: Text('Not recorded'),
              ),
              DropdownMenuItem(value: 'FEMALE', child: Text('Female')),
              DropdownMenuItem(value: 'MALE', child: Text('Male')),
              DropdownMenuItem(value: 'OTHER', child: Text('Other')),
            ],
            onChanged: saving ? null : (v) => setState(() => gender = v),
          ),
          const SizedBox(height: LogSpacing.section),
          const SectionHeading(title: 'Night hours'),
          const Text(
            'Saved with the baby’s profile and shared with caregivers. Daily history still uses calendar days.',
          ),
          const SizedBox(height: LogSpacing.content),
          for (final start in [true, false])
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(start ? 'Night begins' : 'Night ends'),
              subtitle: Text(
                (start ? nightStart : nightEnd)?.format(context) ??
                    'Not recorded',
              ),
              onTap: saving
                  ? null
                  : () async {
                      final t = await showTimePicker(
                        context: context,
                        initialTime:
                            (start ? nightStart : nightEnd) ??
                            const TimeOfDay(hour: 19, minute: 0),
                      );
                      if (t != null && mounted) {
                        setState(() {
                          if (start) {
                            nightStart = t;
                          } else {
                            nightEnd = t;
                          }
                        });
                      }
                    },
            ),
          const SizedBox(height: LogSpacing.section),
          FilledButton(
            onPressed: saving
                ? null
                : () async {
                    setState(() {
                      saving = true;
                      error = null;
                    });
                    try {
                      await widget.controller.saveBabyProfile({
                        if (birthDate != null)
                          'birthDate': DateFormat(
                            'yyyy-MM-dd',
                          ).format(birthDate!),
                        'gender': ?gender,
                        if (nightStart != null)
                          'nightStart': clock(nightStart!),
                        if (nightEnd != null) 'nightEnd': clock(nightEnd!),
                      }, familyId);
                      if (context.mounted) Navigator.pop(context);
                    } catch (e) {
                      if (mounted) {
                        setState(() {
                          saving = false;
                          error = AppController.friendlyError(e);
                        });
                      }
                    }
                  },
            child: Text(saving ? 'Saving…' : 'Save profile'),
          ),
          if (error != null) Text(error!),
        ],
      ),
    ),
  );
}
