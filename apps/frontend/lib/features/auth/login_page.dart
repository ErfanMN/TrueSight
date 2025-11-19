import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../../core/config.dart';
import '../../models/auth_session.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({
    super.key,
    required this.onAuthenticated,
  });

  final ValueChanged<AuthSession> onAuthenticated;

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _codeController = TextEditingController();

  bool _codeSent = false;
  bool _isRequestingCode = false;
  bool _isVerifying = false;
  String? _error;

  @override
  void dispose() {
    _emailController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _requestCode() async {
    final email = _emailController.text.trim();
    if (email.isEmpty) {
      setState(() {
        _error = 'Please enter your email.';
      });
      return;
    }

    setState(() {
      _isRequestingCode = true;
      _error = null;
    });

    try {
      final uri = Uri.parse('$backendBaseUrl/api/auth/request-code/');
      final response = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'email': email}),
      );

      if (response.statusCode != 200) {
        final body = jsonDecode(response.body) as Map<String, dynamic>;
        throw Exception(body['detail'] ?? 'Failed to request code');
      }

      setState(() {
        _codeSent = true;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
      });
    } finally {
      if (mounted) {
        setState(() {
          _isRequestingCode = false;
        });
      }
    }
  }

  Future<void> _verifyCode() async {
    final email = _emailController.text.trim();
    final code = _codeController.text.trim();

    if (email.isEmpty || code.isEmpty) {
      setState(() {
        _error = 'Please enter both email and code.';
      });
      return;
    }

    setState(() {
      _isVerifying = true;
      _error = null;
    });

    try {
      final uri = Uri.parse('$backendBaseUrl/api/auth/verify-code/');
      final response = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'email': email, 'code': code}),
      );

      if (response.statusCode != 200) {
        final body = jsonDecode(response.body) as Map<String, dynamic>;
        throw Exception(body['detail'] ?? 'Failed to verify code');
      }

      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final user = body['user'] as Map<String, dynamic>;

      final session = AuthSession(
        token: body['token'] as String,
        userId: user['id'] as int,
        email: (user['email'] as String?) ?? '',
        username: (user['username'] as String?) ?? '',
        refCode: (user['ref_code'] as String?) ?? '',
      );

      widget.onAuthenticated(session);
    } catch (e) {
      setState(() {
        _error = e.toString();
      });
    } finally {
      if (mounted) {
        setState(() {
          _isVerifying = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('TrueSight Chat'),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Sign in with email',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    labelText: 'Email',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                if (_codeSent)
                  TextField(
                    controller: _codeController,
                    decoration: const InputDecoration(
                      labelText: '4-character code',
                      border: OutlineInputBorder(),
                    ),
                  ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _error!,
                    style: TextStyle(color: Theme.of(context).colorScheme.error),
                  ),
                ],
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton(
                        onPressed: _isRequestingCode ? null : _requestCode,
                        child: _isRequestingCode
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Text('Send code'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ElevatedButton(
                        onPressed:
                            !_codeSent || _isVerifying ? null : _verifyCode,
                        child: _isVerifying
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Text('Verify'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                const Text(
                  'A 4-character code will be sent to your email. '
                  'For development, the code is printed in the Django console.',
                  style: TextStyle(fontSize: 12),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

