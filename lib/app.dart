import 'package:flutter/material.dart';
import 'core/theme.dart';
import 'features/auth/auth_gate.dart';

class PhamoryApp extends StatelessWidget {
  const PhamoryApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PharmaStock',
      debugShowCheckedModeBanner: false,
      theme: buildPhamoryTheme(),
      home: const AuthGate(),
    );
  }
}