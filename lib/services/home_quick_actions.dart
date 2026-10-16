import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Handles launcher shortcuts delivered before or after the Flutter engine starts.
class HomeQuickActions {
  HomeQuickActions({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel('app.littlelog/quick_actions');
  final MethodChannel _channel;
  static const actions = {'diaper', 'nursing_left', 'nursing_right', 'sleep'};

  Future<void> listen(ValueChanged<String> onAction) async {
    if (kIsWeb) return;
    void receive(Object? value) {
      if (value is String && actions.contains(value)) onAction(value);
    }

    _channel.setMethodCallHandler((call) async {
      if (call.method == 'received') receive(call.arguments);
    });
    try {
      receive(await _channel.invokeMethod<String>('listen'));
    } on MissingPluginException {
      // Tests and desktop/web hosts have no launcher integration.
    }
  }

  void dispose() => _channel.setMethodCallHandler(null);
}
