import 'package:flutter/material.dart';

Widget googleButton(VoidCallback onPressed) => OutlinedButton.icon(
  onPressed: onPressed,
  icon: const Icon(Icons.login),
  label: const Text('Sign in with Google'),
);
