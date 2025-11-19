import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

void main() {
  runApp(const TrueSightChatApp());
}

const String backendBaseUrl = 'http://localhost:8000';

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
      home: const ChatShellPage(),
    );
  }
}

class ChatShellPage extends StatefulWidget {
  const ChatShellPage({super.key});

  @override
  State<ChatShellPage> createState() => _ChatShellPageState();
}

class _ChatShellPageState extends State<ChatShellPage> {
  final List<Conversation> _conversations = [];
  Conversation? _selectedConversation;
  bool _isLoadingConversations = false;
  String? _conversationsError;

  final List<ChatMessage> _messages = [];
  bool _isLoadingMessages = false;
  String? _messagesError;

  final TextEditingController _messageController = TextEditingController();
  bool _isSending = false;

  @override
  void initState() {
    super.initState();
    _loadConversations();
  }

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  Future<void> _loadConversations() async {
    setState(() {
      _isLoadingConversations = true;
      _conversationsError = null;
    });

    try {
      final uri = Uri.parse('$backendBaseUrl/api/conversations/');
      final response = await http.get(uri);

      if (response.statusCode != 200) {
        throw Exception('Failed to load conversations (${response.statusCode})');
      }

      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final items = (body['results'] as List<dynamic>? ?? [])
          .map((e) => Conversation.fromJson(e as Map<String, dynamic>))
          .toList();

      setState(() {
        _conversations
          ..clear()
          ..addAll(items);
        if (_conversations.isNotEmpty && _selectedConversation == null) {
          _selectedConversation = _conversations.first;
          _loadMessagesForConversation(_selectedConversation!);
        }
      });
    } catch (e) {
      setState(() {
        _conversationsError = e.toString();
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingConversations = false;
        });
      }
    }
  }

  Future<void> _loadMessagesForConversation(Conversation conversation) async {
    setState(() {
      _isLoadingMessages = true;
      _messagesError = null;
    });

    try {
      final uri = Uri.parse(
        '$backendBaseUrl/api/conversations/${conversation.id}/messages/',
      );
      final response = await http.get(uri);

      if (response.statusCode != 200) {
        throw Exception('Failed to load messages (${response.statusCode})');
      }

      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final items = (body['results'] as List<dynamic>? ?? [])
          .map((e) => ChatMessage.fromJson(e as Map<String, dynamic>))
          .toList();

      setState(() {
        _messages
          ..clear()
          ..addAll(items);
      });
    } catch (e) {
      setState(() {
        _messagesError = e.toString();
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingMessages = false;
        });
      }
    }
  }

  Future<void> _sendMessage() async {
    if (_selectedConversation == null) return;
    final text = _messageController.text.trim();
    if (text.isEmpty) return;

    setState(() {
      _isSending = true;
    });

    try {
      final uri = Uri.parse(
        '$backendBaseUrl/api/conversations/${_selectedConversation!.id}/messages/',
      );
      final response = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'content': text}),
      );

      if (response.statusCode != 201) {
        throw Exception('Failed to send message (${response.statusCode})');
      }

      _messageController.clear();

      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final created = ChatMessage.fromJson(body);
      setState(() {
        _messages.add(created);
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error sending message: $e')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isSending = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('TrueSight Chat'),
        centerTitle: false,
        actions: [
          IconButton(
            onPressed: _isLoadingConversations ? null : _loadConversations,
            tooltip: 'Refresh conversations',
            icon: _isLoadingConversations
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh),
          ),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final isWide = constraints.maxWidth >= 800;

          if (isWide) {
            return Row(
              children: [
                SizedBox(
                  width: 280,
                  child: _ConversationList(
                    conversations: _conversations,
                    selectedConversationId: _selectedConversation?.id,
                    isLoading: _isLoadingConversations,
                    error: _conversationsError,
                    onConversationSelected: (conversation) {
                      setState(() {
                        _selectedConversation = conversation;
                      });
                      _loadMessagesForConversation(conversation);
                    },
                  ),
                ),
                const VerticalDivider(width: 1),
                Expanded(
                  child: _ConversationArea(
                    conversation: _selectedConversation,
                    messages: _messages,
                    isLoading: _isLoadingMessages,
                    error: _messagesError,
                    messageController: _messageController,
                    onSendPressed: _isSending ? null : _sendMessage,
                  ),
                ),
              ],
            );
          }

          // Simple stacked layout on narrow screens.
          return Column(
            children: [
              SizedBox(
                height: 260,
                child: _ConversationList(
                  conversations: _conversations,
                  selectedConversationId: _selectedConversation?.id,
                  isLoading: _isLoadingConversations,
                  error: _conversationsError,
                  onConversationSelected: (conversation) {
                    setState(() {
                      _selectedConversation = conversation;
                    });
                    _loadMessagesForConversation(conversation);
                  },
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: _ConversationArea(
                  conversation: _selectedConversation,
                  messages: _messages,
                  isLoading: _isLoadingMessages,
                  error: _messagesError,
                  messageController: _messageController,
                  onSendPressed: _isSending ? null : _sendMessage,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _ConversationList extends StatelessWidget {
  const _ConversationList({
    required this.conversations,
    required this.selectedConversationId,
    required this.isLoading,
    required this.error,
    required this.onConversationSelected,
  });

  final List<Conversation> conversations;
  final int? selectedConversationId;
  final bool isLoading;
  final String? error;
  final ValueChanged<Conversation> onConversationSelected;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      color: colorScheme.surfaceVariant.withOpacity(0.3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Text(
                  'Conversations',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const Spacer(),
                if (isLoading)
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
              ],
            ),
          ),
          const Divider(height: 1),
          if (error != null)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                error!,
                style: TextStyle(color: colorScheme.error),
              ),
            )
          else if (conversations.isEmpty && !isLoading)
            const Padding(
              padding: EdgeInsets.all(12),
              child: Text('No conversations yet.'),
            )
          else
            Expanded(
              child: ListView.separated(
                itemCount: conversations.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final conversation = conversations[index];
                  final isSelected = conversation.id == selectedConversationId;

                  return Material(
                    color:
                        isSelected ? colorScheme.primaryContainer : Colors.transparent,
                    child: ListTile(
                      dense: true,
                      title: Text(
                        conversation.title.isNotEmpty
                            ? conversation.title
                            : 'Conversation ${conversation.id}',
                      ),
                      subtitle: Text(
                        conversation.isGroup ? 'Group chat' : 'Direct chat',
                      ),
                      onTap: () => onConversationSelected(conversation),
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

class _ConversationArea extends StatelessWidget {
  const _ConversationArea({
    required this.conversation,
    required this.messages,
    required this.isLoading,
    required this.error,
    required this.messageController,
    required this.onSendPressed,
  });

  final Conversation? conversation;
  final List<ChatMessage> messages;
  final bool isLoading;
  final String? error;
  final TextEditingController messageController;
  final VoidCallback? onSendPressed;

  @override
  Widget build(BuildContext context) {
    if (conversation == null) {
      return const _EmptyChatPlaceholder();
    }

    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      children: [
        if (isLoading)
          const LinearProgressIndicator(minHeight: 2)
        else
          const SizedBox(height: 2),
        Expanded(
          child: error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      error!,
                      style: TextStyle(color: colorScheme.error),
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              : messages.isEmpty
                  ? const Center(
                      child: Text('No messages yet.'),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: messages.length,
                      itemBuilder: (context, index) {
                        final msg = messages[index];
                        final isOwn = msg.senderUsername == 'demo';

                        return Align(
                          alignment: isOwn
                              ? Alignment.centerRight
                              : Alignment.centerLeft,
                          child: Container(
                            margin: const EdgeInsets.symmetric(vertical: 4),
                            padding: const EdgeInsets.symmetric(
                              vertical: 8,
                              horizontal: 12,
                            ),
                            decoration: BoxDecoration(
                              color: isOwn
                                  ? colorScheme.primaryContainer
                                  : colorScheme.surfaceVariant,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (!isOwn)
                                  Text(
                                    msg.senderUsername ?? 'user',
                                    style: Theme.of(context)
                                        .textTheme
                                        .labelSmall
                                        ?.copyWith(
                                          color: colorScheme.onSurfaceVariant,
                                        ),
                                  ),
                                if (!isOwn) const SizedBox(height: 2),
                                Text(msg.content),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
        ),
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.all(8),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: messageController,
                  minLines: 1,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    hintText: 'Type a message…',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                onPressed: onSendPressed,
                icon: const Icon(Icons.send),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _EmptyChatPlaceholder extends StatelessWidget {
  const _EmptyChatPlaceholder();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.chat_bubble_outline_rounded,
                size: 64,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(height: 16),
              Text(
                'Welcome to TrueSight Chat',
                style: Theme.of(context).textTheme.headlineSmall,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'Select a conversation on the left\n'
                'or create one in the Django admin.\n'
                'You are currently using a demo user.',
                style: Theme.of(context).textTheme.bodyMedium,
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

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
