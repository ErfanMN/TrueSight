import 'package:flutter/material.dart';

import 'features/auth/login_page.dart';
import 'features/chat/chat_shell_page.dart';
import 'models/auth_session.dart';

class TrueSightChatApp extends StatelessWidget {
  const TrueSightChatApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'TrueSight Chat',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF0F172A),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: const _RootShell(),
    );
  }
}

class _RootShell extends StatefulWidget {
  const _RootShell({super.key});

  @override
  State<_RootShell> createState() => _RootShellState();
}

class _RootShellState extends State<_RootShell> {
  AuthSession? _session;

  @override
  Widget build(BuildContext context) {
    if (_session == null) {
      return LoginPage(
        onAuthenticated: (session) {
          setState(() {
            _session = session;
          });
        },
      );
    }

    return ChatShellPage(
      authToken: _session!.token,
      currentUserId: _session!.userId,
      refCode: _session!.refCode,
    );
  }
}
