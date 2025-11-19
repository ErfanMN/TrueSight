class AuthSession {
  AuthSession({
    required this.token,
    required this.userId,
    required this.email,
    required this.username,
    required this.refCode,
  });

  final String token;
  final int userId;
  final String email;
  final String username;
  final String refCode;
}

