import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'invitation_link.dart';

class InvitationLinkBridge {
  InvitationLinkBridge({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel('app.littlelog/invitation');

  final MethodChannel _channel;

  Future<void> listen(ValueChanged<InvitationLink> onInvitation) async {
    if (kIsWeb) return;
    _channel.setMethodCallHandler((call) async {
      if (call.method != 'received') return;
      final link = InvitationLink.parse(call.arguments as String? ?? '');
      if (link != null) onInvitation(link);
    });
    String? initial;
    try {
      initial = await _channel.invokeMethod<String>('listen');
    } on MissingPluginException {
      return; // Widget tests and platforms without native link handling.
    }
    final link = InvitationLink.parse(initial ?? '');
    if (link != null) onInvitation(link);
  }

  Future<void> share(String message) async {
    await _channel.invokeMethod<void>('share', {'message': message});
  }

  void dispose() => _channel.setMethodCallHandler(null);
}
