import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
  void initState() {
    super.initState();
    _restoreSession();
  }

  Future<void> _restoreSession() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('auth_token');
    final userId = prefs.getInt('auth_user_id');
    if (token == null || userId == null) {
      return;
    }

    setState(() {
      _session = AuthSession(
        token: token,
        userId: userId,
        email: prefs.getString('auth_email') ?? '',
        username: prefs.getString('auth_username') ?? '',
        refCode: prefs.getString('auth_ref_code') ?? '',
      );
    });
  }

  Future<void> _persistSession(AuthSession session) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('auth_token', session.token);
    await prefs.setInt('auth_user_id', session.userId);
    await prefs.setString('auth_email', session.email);
    await prefs.setString('auth_username', session.username);
    await prefs.setString('auth_ref_code', session.refCode);
  }

  Future<void> _clearSession() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('auth_token');
    await prefs.remove('auth_user_id');
    await prefs.remove('auth_email');
    await prefs.remove('auth_username');
    await prefs.remove('auth_ref_code');
  }

  void _handleAuthenticated(AuthSession session) {
    setState(() {
      _session = session;
    });
    _persistSession(session);
  }

  void _handleSignOut() {
    setState(() {
      _session = null;
    });
    _clearSession();
  }

  @override
  Widget build(BuildContext context) {
    if (_session == null) {
      return LoginPage(
        onAuthenticated: _handleAuthenticated,
      );
    }

    return ChatShellPage(
      authToken: _session!.token,
      currentUserId: _session!.userId,
      refCode: _session!.refCode,
      onSignOut: _handleSignOut,
    );
  }
}
