class Conversation {
  Conversation({
    required this.id,
    required this.title,
    required this.isGroup,
    required this.createdAt,
    required this.updatedAt,
  });

  final int id;
  final String title;
  final bool isGroup;
  final DateTime createdAt;
  final DateTime updatedAt;

  factory Conversation.fromJson(Map<String, dynamic> json) {
    return Conversation(
      id: json['id'] as int,
      title: (json['title'] as String?) ?? '',
      isGroup: json['is_group'] as bool? ?? false,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }
}

