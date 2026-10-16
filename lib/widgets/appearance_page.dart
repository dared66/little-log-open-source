import 'package:flutter/material.dart';
import '../controller.dart';
import '../design.dart';

class AppearancePage extends StatefulWidget {
  const AppearancePage({super.key, required this.controller});
  final AppController controller;

  @override
  State<AppearancePage> createState() => _AppearancePageState();
}

class _AppearancePageState extends State<AppearancePage> {
  bool saving = false;
  String? error;

  Future<void> choose(ThemeMode mode) async {
    setState(() {
      saving = true;
      error = null;
    });
    try {
      await widget.controller.setThemeMode(mode);
    } catch (_) {
      if (mounted) {
        setState(() => error = 'Could not save appearance. Try again.');
      }
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: logPageAppBar(context, 'Appearance'),
    body: LogPageFrame(
      child: ListenableBuilder(
        listenable: widget.controller,
        builder: (context, _) => SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final mode in ThemeMode.values)
                    Card(
                      child: ListTile(
                        key: ValueKey('appearance-${mode.name}'),
                        leading: Icon(switch (mode) {
                          ThemeMode.system => Icons.brightness_auto_outlined,
                          ThemeMode.light => Icons.light_mode_outlined,
                          ThemeMode.dark => Icons.dark_mode_outlined,
                        }),
                        title: Text(appearanceLabel(mode)),
                        subtitle: mode == ThemeMode.system
                            ? const Text('Follow device settings')
                            : null,
                        selected: widget.controller.themeMode == mode,
                        selectedColor: logPalette(context).actionInk,
                        selectedTileColor: logPalette(context).actionTint,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(24),
                        ),
                        trailing: widget.controller.themeMode == mode
                            ? const Icon(Icons.check)
                            : null,
                        enabled: !saving,
                        onTap: () => choose(mode),
                      ),
                    ),
                  if (error != null)
                    Padding(
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
    ),
  );
}

String appearanceLabel(ThemeMode mode) => switch (mode) {
  ThemeMode.system => 'System',
  ThemeMode.light => 'Light',
  ThemeMode.dark => 'Dark',
};
