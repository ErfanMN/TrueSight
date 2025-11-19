class ChatMessage {
  ChatMessage({
    required this.id,
    required this.conversationId,
    required this.content,
    required this.createdAt,
    this.senderId,
    this.senderUsername,
  });

  final int id;
  final int conversationId;
  final String content;
  final DateTime createdAt;
  final int? senderId;
  final String? senderUsername;

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    final sender = json['sender'] as Map<String, dynamic>?;

    return ChatMessage(
      id: json['id'] as int,
      conversationId: json['conversation'] as int,
      content: json['content'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
      senderId: sender != null ? sender['id'] as int? : null,
      senderUsername: sender != null ? sender['username'] as String? : null,
    );
  }
}

