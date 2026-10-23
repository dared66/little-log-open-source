import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../design.dart';
import '../services/assistant_history.dart';

enum VoiceAssistant { siri, google }

VoiceAssistant? get deviceVoiceAssistant {
  if (kIsWeb) return null;
  return switch (defaultTargetPlatform) {
    TargetPlatform.iOS => VoiceAssistant.siri,
    TargetPlatform.android => VoiceAssistant.google,
    _ => null,
  };
}

/// Settings exposes only the assistant supported by the current mobile platform.
class AssistantHelpTile extends StatelessWidget {
  const AssistantHelpTile({super.key});

  @override
  Widget build(BuildContext context) {
    final assistant = deviceVoiceAssistant;
    if (assistant == null) return const SizedBox.shrink();
    return Card(
      child: ListTile(
        key: const ValueKey('assistant-help'),
        leading: const Icon(Icons.help_outline),
        title: const Text('Help'),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => AssistantHelpPage(assistant: assistant),
          ),
        ),
      ),
    );
  }
}

class AssistantHelpPage extends StatelessWidget {
  const AssistantHelpPage({super.key, required this.assistant});
  final VoiceAssistant assistant;

  String phrase(String command, {bool question = false}) {
    final text = command.replaceFirst(RegExp(r'\?$'), '');
    final sentence = '${text[0].toLowerCase()}${text.substring(1)}';
    final invocation = assistant == VoiceAssistant.siri
        ? 'Hey Siri, $sentence in Little Log'
        : 'Hey Google, open Little Log and $sentence';
    return '“$invocation${question ? '?' : '.'}”';
  }

  List<AssistantHelpTopic> get topics {
    final siri = assistant == VoiceAssistant.siri;
    String question(String action) => switch (action) {
      'last_sleep' when siri => 'When was the last sleep?',
      'last_wake' => 'When did my baby last wake up?',
      'sleep_status' => 'Is my baby asleep?',
      _ => assistantHistoryQuestions[action]!,
    };
    return [
      AssistantHelpTopic(
        title: 'Diapers',
        questions: [
          question('last_diaper'),
          question('last_wet_diaper'),
          question('last_dirty_diaper'),
        ],
        actions: const [
          'Add a wet diaper',
          'Add a dirty diaper',
          'Add a wet and dirty diaper',
          'Add a dry diaper',
        ],
        questionNote: 'A wet and dirty diaper counts for both questions.',
        actionNote: 'Records a change at the time you ask.',
      ),
      AssistantHelpTopic(
        title: 'Feeding',
        questions: [
          question('last_feed'),
          question('last_bottle'),
          question('last_nursing'),
          question('last_solids'),
          'How long since the last feed?',
        ],
        actions: const [
          'Start nursing on the left side',
          'Start nursing on the right side',
          'Finish nursing',
        ],
        questionNote:
            'Feed includes bottle, nursing and solids. Nursing uses the session’s start time, including an active session.',
        actionNote:
            'Pause nursing in Little Log before asking to finish. Finishing saves the paused session. Bottle and solids entries are added in the app.',
      ),
      AssistantHelpTopic(
        title: 'Sleep',
        questions: [
          question('last_sleep'),
          question('last_wake'),
          question('sleep_status'),
          'How long has my baby been awake?',
          'How long has my baby been asleep?',
        ],
        actions: const ['Start sleep', 'Finish sleep'],
        questionNote:
            'Sleep status uses the active timer. Wake-up uses a saved sleep end time; an entry with only a duration cannot provide it.',
        actionNote:
            'Finishing sleep stops the active timer and saves the session.',
      ),
      AssistantHelpTopic(
        title: 'Pumping',
        questions: [question('last_pumping')],
        actions: [
          'Start pumping',
          siri ? 'Finish pumping' : 'Finish pumping with 90 milliliters',
        ],
        questionNote:
            'Uses the session’s start time, including an active timer.',
        actionNote: siri
            ? 'Siri asks for the pumped amount and units before saving.'
            : 'Pause pumping in Little Log before asking to finish. Include the amount and units to save, or enter them in the app.',
      ),
    ];
  }

  Widget examples(
    BuildContext context,
    String title,
    List<String> commands,
    String note, {
    bool questions = false,
  }) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(title, style: helpLabelStyle(context)),
      const SizedBox(height: LogSpacing.content),
      for (final command in commands)
        Padding(
          padding: const EdgeInsets.only(bottom: LogSpacing.content),
          child: SelectableText(
            key: PageStorageKey('assistant-phrase-${assistant.name}-$command'),
            phrase(command, question: questions),
            style: helpBodyStyle(context),
          ),
        ),
      Text(note, style: helpNoteStyle(context)),
    ],
  );

  TextStyle helpBodyStyle(BuildContext context) => Theme.of(
    context,
  ).textTheme.bodyLarge!.copyWith(fontSize: 15, letterSpacing: 0, height: 1.4);

  TextStyle helpLabelStyle(BuildContext context) => helpBodyStyle(
    context,
  ).copyWith(fontSize: 13, fontWeight: FontWeight.w600);

  TextStyle helpNoteStyle(BuildContext context) => helpBodyStyle(
    context,
  ).copyWith(fontSize: 13, color: logPalette(context).secondary);

  Widget helpSection(
    BuildContext context, {
    required String id,
    required String title,
    required List<Widget> children,
    bool nested = false,
  }) {
    final tile = ExpansionTile(
      key: PageStorageKey('assistant-help-$id'),
      shape: const Border(),
      collapsedShape: const Border(),
      minTileHeight: nested ? 44 : 52,
      dense: true,
      visualDensity: VisualDensity.standard,
      tilePadding: EdgeInsets.symmetric(horizontal: nested ? 0 : 16),
      childrenPadding: EdgeInsets.fromLTRB(
        nested ? 0 : 16,
        4,
        nested ? 0 : 16,
        12,
      ),
      expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
      title: Text(
        title,
        style: helpBodyStyle(context).copyWith(
          fontSize: nested ? 15 : 17,
          fontWeight: nested ? FontWeight.w500 : FontWeight.w600,
          height: 1.3,
        ),
      ),
      children: children,
    );
    return nested
        ? DecoratedBox(
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: Theme.of(
                    context,
                  ).colorScheme.outlineVariant.withValues(alpha: .45),
                ),
              ),
            ),
            child: tile,
          )
        : Card(
            clipBehavior: Clip.antiAlias,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            child: tile,
          );
  }

  Widget topicSection(BuildContext context, AssistantHelpTopic topic) =>
      helpSection(
        context,
        id: topic.title,
        title: topic.title,
        nested: true,
        children: [
          examples(
            context,
            'Ask',
            topic.questions,
            topic.questionNote,
            questions: true,
          ),
          const SizedBox(height: LogSpacing.field),
          examples(context, 'Log or time', topic.actions, topic.actionNote),
        ],
      );

  Widget voiceHelp(BuildContext context) {
    final siri = assistant == VoiceAssistant.siri;
    return helpSection(
      context,
      id: 'voice-help',
      title: siri ? 'Shortcuts and Siri help' : 'Google Assistant help',
      nested: true,
      children: [
        if (siri) ...[
          Padding(
            padding: const EdgeInsets.only(bottom: LogSpacing.label),
            child: Text('Use Shortcuts', style: helpLabelStyle(context)),
          ),
          Text(
            'Open Shortcuts, add an action and search for Little Log. Choose an action and its details. Give the shortcut a name you can say to Siri, such as “Last diaper.”',
            style: helpBodyStyle(context),
          ),
          const SizedBox(height: LogSpacing.field),
          Padding(
            padding: const EdgeInsets.only(bottom: LogSpacing.label),
            child: Text(
              'If Siri doesn’t recognize a request',
              style: helpLabelStyle(context),
            ),
          ),
          Text(
            'Try an example exactly as written, including “in Little Log.” You can also run the action from Shortcuts.',
            style: helpBodyStyle(context),
          ),
          const SizedBox(height: LogSpacing.field),
          Padding(
            padding: const EdgeInsets.only(bottom: LogSpacing.label),
            child: Text(
              'Unlocking your iPhone',
              style: helpLabelStyle(context),
            ),
          ),
          Text(
            'These actions open Little Log. Siri may ask you to unlock your iPhone before continuing.',
            style: helpBodyStyle(context),
          ),
        ] else ...[
          Padding(
            padding: const EdgeInsets.only(bottom: LogSpacing.label),
            child: Text(
              'If a command doesn’t open Little Log',
              style: helpLabelStyle(context),
            ),
          ),
          Text(
            'Check that Google Assistant is enabled and set to English (United States). Use the Google Play version of Little Log; voice actions also need to be available for your installation.',
            style: helpBodyStyle(context),
          ),
          const SizedBox(height: LogSpacing.field),
          Padding(
            padding: const EdgeInsets.only(bottom: LogSpacing.label),
            child: Text(
              'If your phone uses Gemini',
              style: helpLabelStyle(context),
            ),
          ),
          Text(
            'Little Log’s voice commands are built for Google Assistant. Use Quick Log if your assistant cannot run them.',
            style: helpBodyStyle(context),
          ),
        ],
        const SizedBox(height: LogSpacing.field),
        Padding(
          padding: const EdgeInsets.only(bottom: LogSpacing.label),
          child: Text('How answers work', style: helpLabelStyle(context)),
        ),
        Text(
          'Questions read saved entries and active timers without changing them. Missing history is reported instead of guessed.',
          style: helpBodyStyle(context),
        ),
      ],
    );
  }

  Widget setupGuide(BuildContext context, SetupHelpTopic guide) => helpSection(
    context,
    id: guide.id,
    title: guide.title,
    nested: true,
    children: [
      for (var index = 0; index < guide.steps.length; index++)
        Padding(
          padding: const EdgeInsets.only(bottom: LogSpacing.content),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 22,
                child: Text(
                  '${index + 1}.',
                  style: helpBodyStyle(
                    context,
                  ).copyWith(color: logPalette(context).secondary),
                ),
              ),
              Expanded(
                child: Text(guide.steps[index], style: helpBodyStyle(context)),
              ),
            ],
          ),
        ),
      if (guide.note != null) Text(guide.note!, style: helpNoteStyle(context)),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final siri = assistant == VoiceAssistant.siri;
    return Scaffold(
      appBar: logPageAppBar(context, 'Help'),
      body: LogPageFrame(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          children: [
            helpSection(
              context,
              id: 'voice',
              title: siri ? 'Use Siri' : 'Use Google Assistant',
              children: [
                Text(
                  siri
                      ? 'Include “in Little Log” in your request, as shown in the examples.'
                      : 'Use Google Assistant in English (United States). Command availability depends on your device and app installation.',
                  style: helpBodyStyle(context),
                ),
                const SizedBox(height: LogSpacing.content),
                Text(
                  'Requests use the baby selected in Little Log.',
                  style: helpBodyStyle(context),
                ),
                const SizedBox(height: LogSpacing.content),
                for (final topic in topics) topicSection(context, topic),
                voiceHelp(context),
              ],
            ),
            helpSection(
              context,
              id: 'setup',
              title: 'Setup and troubleshooting',
              children: [
                for (final guide in setupHelpTopics) setupGuide(context, guide),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class AssistantHelpTopic {
  const AssistantHelpTopic({
    required this.title,
    required this.questions,
    required this.actions,
    required this.questionNote,
    required this.actionNote,
  });

  final String title, questionNote, actionNote;
  final List<String> questions, actions;
}

class SetupHelpTopic {
  const SetupHelpTopic({
    required this.id,
    required this.title,
    required this.steps,
    this.note,
  });
  final String id, title;
  final List<String> steps;
  final String? note;
}

const setupHelpTopics = [
  SetupHelpTopic(
    id: 'drive',
    title: 'Connect Google Drive',
    steps: [
      'Open Settings and tap Sign in with Google. Choose the account you want to use for this baby.',
      'If shown, tap Connect Google Drive and allow access.',
      'For a log saved only on this device, tap Save log to Google Drive.',
    ],
    note:
        'Signing in alone does not upload a device-only log. The Drive log stays private until you share it.',
  ),
  SetupHelpTopic(
    id: 'invite',
    title: 'Invite a caregiver',
    steps: [
      'Select the baby you want to share and open Settings. Save the log to Google Drive first if it is device-only.',
      'Scroll to Invite a caregiver. Enter their Google email and tap Share invitation.',
      'Choose an app in the share sheet to send the invitation. The menu also offers Copy invitation.',
    ],
    note: 'Sharing one baby’s log does not share your other logs.',
  ),
  SetupHelpTopic(
    id: 'join',
    title: 'Join an invitation',
    steps: [
      'Open the Little Log invitation link.',
      'Sign in with the Google account that was invited. Connect Google Drive if asked.',
      'If the link does not open, choose Join an existing baby log and paste the Drive link.',
      'Tap Open log. Approve the invited file if Google asks.',
      'Check the baby and owner, then tap Join baby log.',
    ],
    note:
        'Joining keeps your existing logs separate. It does not combine histories.',
  ),
  SetupHelpTopic(
    id: 'missing-invitation',
    title: 'Can’t find a shared log',
    steps: [
      'Check that the Google account shown in Little Log matches the email the caregiver invited.',
      'Ask the sender for a copy using Share invitation.',
      'Use the file link to join, or tap Browse shared logs and look in Shared with me.',
    ],
    note:
        'First-time access may require selecting the invited file in Google’s authorization screen.',
  ),
  SetupHelpTopic(
    id: 'sync',
    title: 'Entries aren’t syncing',
    steps: [
      'Check that both caregivers selected the same shared log. Compare the Log reference in Settings if the baby names match.',
      'Check your internet connection and the Google account shown in Settings. Reconnect Google Drive if asked.',
      'Return to Log and pull down to refresh, or tap Refresh beside the sync status. Check the status for entries waiting to sync or an error.',
    ],
    note:
        'Offline entries stay on the device until they sync. Running timers stay on the device where they started; completed entries sync to Drive.',
  ),
  SetupHelpTopic(
    id: 'drive-access',
    title: 'Drive log or access is unavailable',
    steps: [
      'Check that you are signed in to the Google account linked to this log.',
      'Ask the owner to check that the file is not in Google Drive Trash and that your invited email still has Editor access.',
      'After access is restored, return to Little Log and tap Retry sync or refresh the Log.',
    ],
    note:
        'To change someone’s access, open Settings → Data & storage → Open file in Google Drive and manage sharing there. Entries saved on this device remain available while sync is unavailable.',
  ),
  SetupHelpTopic(
    id: 'backup-recovery',
    title: 'Back up, import or recover entries',
    steps: [
      'To keep a separate backup, open Settings → Data & storage → Export baby log. Tap Copy JSON and save the text as a .json file somewhere safe.',
      'To import a Little Log backup or Nara Baby export, select the destination baby, then open Settings → Import and recovery → Choose file.',
      'Review the import before tapping Import these entries. If needed, return to Import and recovery and use Undo last import when available.',
    ],
    note:
        'Export includes local entries and active timers. Changes to a shared log also sync to caregivers. Export device-only or unsynced entries before removing the app or changing devices.',
  ),
];
