import '../design.dart';
import 'package:flutter/material.dart';
import '../services/tip_jar.dart';

class TipJarPage extends StatefulWidget {
  const TipJarPage({super.key, required this.jar});
  final TipJar jar;
  @override
  State<TipJarPage> createState() => _TipJarPageState();
}

class _TipJarPageState extends State<TipJarPage> {
  @override
  void initState() {
    super.initState();
    widget.jar.load();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: logPageAppBar(context, 'Support Little Log'),
    body: LogPageFrame(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: ListenableBuilder(
              listenable: widget.jar,
              builder: (context, _) {
                final jar = widget.jar;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Icon(
                      Icons.favorite_outline,
                      size: 40,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(height: LogSpacing.section),
                    Text(
                      'A little thanks goes a long way',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: LogSpacing.content),
                    const Text(
                      'If Little Log makes your day easier, you can '
                      'leave an optional tip to support its development.',
                    ),
                    const SizedBox(height: LogSpacing.content),
                    const Text(
                      'All features stay free. Tips are one-time '
                      'purchases, with no subscription or extra features.',
                    ),
                    const SizedBox(height: LogSpacing.section),
                    if (jar.loading)
                      const Center(child: CircularProgressIndicator())
                    else
                      for (final product in jar.products) ...[
                        OutlinedButton(
                          onPressed: jar.busy ? null : () => jar.buy(product),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            child: Text('Leave a ${product.price} tip'),
                          ),
                        ),
                        const SizedBox(height: LogSpacing.content),
                      ],
                    if (jar.message != null) ...[
                      const SizedBox(height: LogSpacing.content),
                      Semantics(liveRegion: true, child: Text(jar.message!)),
                    ],
                    const SizedBox(height: LogSpacing.field),
                    if (jar.canRetry)
                      TextButton(
                        onPressed: jar.load,
                        child: const Text('Retry'),
                      ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    ),
  );
}
