import 'package:flutter/material.dart';

Widget googleButton(
  VoidCallback onPressed, {
  bool primary = false,
  ButtonStyle? style,
}) => primary
    ? FilledButton(
        onPressed: onPressed,
        style: style,
        child: const Text('Sign in with Google'),
      )
    : OutlinedButton.icon(
        onPressed: onPressed,
        style: style,
        icon: const Icon(Icons.login),
        label: const Text('Sign in with Google'),
      );
