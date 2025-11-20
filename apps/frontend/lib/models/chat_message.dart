class ChatMessage {
  ChatMessage({
    required this.id,
    required this.conversationId,
    required this.content,
    required this.createdAt,
    this.senderId,
    this.senderName,
    this.senderAvatarColor,
  });

  final int id;
  final int conversationId;
  final String content;
  final DateTime createdAt;
  final int? senderId;
  final String? senderName;
  final String? senderAvatarColor;

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    final sender = json['sender'] as Map<String, dynamic>?;

    return ChatMessage(
      id: json['id'] as int,
      conversationId: json['conversation'] as int,
      content: json['content'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
      senderId: sender != null ? sender['id'] as int? : null,
      senderName: sender != null
          ? (sender['display_name'] as String? ??
              sender['username'] as String? ??
              '')
          : null,
      senderAvatarColor:
          sender != null ? sender['avatar_color'] as String? : null,
    );
  }
}
