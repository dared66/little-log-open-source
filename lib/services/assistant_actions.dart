import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../controller.dart';
import 'assistant_history.dart';

class AssistantRequest {
  AssistantRequest({
    required this.id,
    required this.action,
    required this.at,
    required this.deadline,
    this.kind,
    this.amount,
    this.unit,
  });
  bool _cancelled = false;
  bool get cancelled => _cancelled;
  final String id, action;
  final String? kind, unit;
  final double? amount;
  final DateTime at, deadline;

  static AssistantRequest? parse(Object? value) {
    if (value is! Map) return null;
    final id = value['id'],
        action = value['action'],
        at = value['at'],
        deadline = value['deadline'];
    if (id is! String ||
        id.isEmpty ||
        action is! String ||
        at is! int ||
        deadline is! int) {
      return null;
    }
    if (!{
      'add_diaper',
      'nursing_left',
      'nursing_right',
      'sleep',
      'pumping',
      'finish_sleep',
      'finish_nursing',
      'finish_pumping',
      'open_diaper',
      'open_nursing',
      'review_pumping',
      ...assistantHistoryQuestions.keys,
    }.contains(action)) {
      return null;
    }
    final kind = value['kind'];
    if (action == 'add_diaper' &&
        !{'wet', 'dirty', 'both', 'dry'}.contains(kind)) {
      return null;
    }
    final amount = value['amount'], unit = value['unit'];
    if (action == 'finish_pumping' &&
        (amount is! num || !['ml', 'oz'].contains(unit))) {
      return null;
    }
    return AssistantRequest(
      id: id,
      action: action,
      kind: kind is String ? kind : null,
      amount: amount is num ? amount.toDouble() : null,
      unit: unit is String ? unit : null,
      at: DateTime.fromMillisecondsSinceEpoch(at),
      deadline: DateTime.fromMillisecondsSinceEpoch(deadline),
    );
  }
}

/// Voice integrations await saved query results or the actual local write.
/// Requests are serialized and repeated delivery of an ID reuses its result.
class AssistantActions {
  AssistantActions({MethodChannel? channel})
    : _channel =
          channel ??
          MethodChannel(
            defaultTargetPlatform == TargetPlatform.android
                ? 'app.littlelog/assistant'
                : 'app.littlelog/siri',
          );
  final MethodChannel _channel;
  final Map<String, Future<Map<String, Object>>> _results = {};
  final Map<String, AssistantRequest> _requests = {};
  final Set<String> _cancelledIds = {};
  Future<void> _queue = Future.value();
  bool _disposed = false;

  Future<void> listen(Future<String> Function(AssistantRequest) execute) async {
    if (kIsWeb) return;
    Future<void> receive(Object? value) async {
      final parsed = AssistantRequest.parse(value);
      if (parsed == null || _disposed) return;
      final request = _requests.putIfAbsent(parsed.id, () => parsed);
      if (_cancelledIds.contains(request.id)) request._cancelled = true;
      final response = _results.putIfAbsent(request.id, () {
        final completed = Completer<Map<String, Object>>();
        _queue = _queue.then((_) async {
          try {
            if (_disposed ||
                request.cancelled ||
                DateTime.now().isAfter(request.deadline)) {
              throw StateError('The voice request expired. Try again.');
            }
            completed.complete({
              'id': request.id,
              'message': await execute(request),
              'query': assistantHistoryQuestions.containsKey(request.action),
            });
          } catch (error) {
            completed.complete({
              'id': request.id,
              'error': AppController.friendlyError(error),
              'query': assistantHistoryQuestions.containsKey(request.action),
            });
          }
        });
        return completed.future;
      });
      final result = await response;
      if (!_disposed) await _channel.invokeMethod<void>('complete', result);
    }

    _channel.setMethodCallHandler((call) async {
      if (call.method == 'cancelled') {
        final id = call.arguments;
        if (id is String) {
          _cancelledIds.add(id);
          _requests[id]?._cancelled = true;
        }
      } else if (call.method == 'received') {
        await receive(call.arguments);
      }
    });
    try {
      final pending = await _channel.invokeMethod<List<Object?>>('listen');
      for (final request in pending ?? []) {
        unawaited(receive(request));
      }
    } on MissingPluginException {
      // Desktop/web and test hosts may have no native assistant integration.
    }
  }

  void dispose() {
    _disposed = true;
    _channel.setMethodCallHandler(null);
  }
}

Future<String> executeAssistantRequest(
  AppController controller,
  AssistantRequest request,
) async {
  if (controller.loading) {
    final ready = Completer<void>();
    void check() {
      if (!controller.loading && !ready.isCompleted) ready.complete();
    }

    controller.addListener(check);
    try {
      check();
      final remaining = request.deadline.difference(DateTime.now());
      if (remaining.isNegative) {
        throw StateError('The voice request expired. Try again.');
      }
      await ready.future.timeout(
        remaining,
        onTimeout: () =>
            throw StateError('Little Log is still opening. Try again.'),
      );
    } finally {
      controller.removeListener(check);
    }
  }
  if (request.cancelled || DateTime.now().isAfter(request.deadline)) {
    throw StateError('The voice request expired. Try again.');
  }
  return controller.performAssistantAction(
    request.action,
    kind: request.kind,
    amount: request.amount,
    unit: request.unit,
    at: request.at,
  );
}
