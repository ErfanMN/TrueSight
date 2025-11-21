import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:flutter/services.dart';

import '../../core/config.dart';
import '../../models/chat_message.dart';
import '../../models/conversation.dart';
import '../../widgets/hexagon_logo.dart';

class ChatShellPage extends StatefulWidget {
  const ChatShellPage({
    super.key,
    required this.authToken,
    required this.currentUserId,
    required this.refCode,
    required this.onSignOut,
  });

  final String authToken;
  final int currentUserId;
  final String refCode;
  final VoidCallback onSignOut;

  @override
  State<ChatShellPage> createState() => _ChatShellPageState();
}

enum _ChatMenuAction { profile, signOut }

class _ChatShellPageState extends State<ChatShellPage> {
  final List<Conversation> _conversations = [];
  Conversation? _selectedConversation;
  bool _isLoadingConversations = false;
  String? _conversationsError;
  bool _hasMoreConversations = false;

  final List<ChatMessage> _messages = [];
  bool _isLoadingMessages = false;
  String? _messagesError;
  bool _hasMoreMessages = false;
  bool _isLoadingOlderMessages = false;

  final TextEditingController _messageController = TextEditingController();
  bool _isSending = false;
  String _displayName = '';
  String _email = '';

  final FocusNode _inputFocusNode = FocusNode();
  Timer? _pollTimer;
  Timer? _typingDebounce;
  bool _typingNotified = false;
  String? _presenceText;
  String? _typingText;

  @override
  void initState() {
    super.initState();
    _loadProfile();
    _loadConversations();
    _pollTimer = Timer.periodic(
      const Duration(seconds: 3),
      (_) {
        if (_selectedConversation != null && !_isLoadingMessages) {
          _loadMessagesForConversation(
            _selectedConversation!,
            silent: true,
          );
          _loadConversationTypingAndPresence();
        }
      },
    );
  }

  Map<String, String> get _authHeaders => {
        'Authorization': 'Token ${widget.authToken}',
      };

  @override
  void dispose() {
    _messageController.dispose();
    _inputFocusNode.dispose();
    _pollTimer?.cancel();
    _typingDebounce?.cancel();
    super.dispose();
  }

  Future<void> _loadProfile() async {
    try {
      final uri = Uri.parse('$backendBaseUrl/api/auth/me/profile/');
      final response = await http.get(uri, headers: _authHeaders);
      if (response.statusCode != 200) {
        return;
      }
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final displayName = (body['display_name'] as String?) ?? '';
      final email = (body['email'] as String?) ?? '';
      setState(() {
        _displayName = displayName;
        _email = email;
      });
      if (displayName.isEmpty && mounted) {
        await _showEditProfileDialog(requireName: true);
      }
    } catch (_) {
      // ignore for now
    }
  }

  Future<void> _showEditProfileDialog({bool requireName = false}) async {
    final controller = TextEditingController(text: _displayName);
    String? error;

    await showDialog<void>(
      context: context,
      barrierDismissible: !requireName,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const Text('Profile'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'This is the name others will see.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: controller,
                    decoration: InputDecoration(
                      labelText: 'Display name',
                      hintText: 'e.g. Erfan',
                      errorText: error,
                    ),
                  ),
                ],
              ),
              actions: [
                if (!requireName)
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                ElevatedButton(
                  onPressed: () async {
                    final name = controller.text.trim();
                    if (name.isEmpty) {
                      setState(() {
                        error = 'Please enter a name.';
                      });
                      return;
                    }
                    try {
                      final uri =
                          Uri.parse('$backendBaseUrl/api/auth/me/profile/');
                      final response = await http.patch(
                        uri,
                        headers: {
                          'Content-Type': 'application/json',
                          ..._authHeaders,
                        },
                        body: jsonEncode({'display_name': name}),
                      );
                      if (response.statusCode != 200) {
                        throw Exception('Failed to update profile');
                      }
                      setState(() {
                        _displayName = name;
                      });
                      if (context.mounted) {
                        Navigator.of(context).pop();
                      }
                    } catch (e) {
                      setState(() {
                        error = e.toString();
                      });
                    }
                  },
                  child: const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _loadConversations({bool append = false}) async {
    setState(() {
      _isLoadingConversations = true;
      _conversationsError = null;
    });

    try {
      final offset = append ? _conversations.length : 0;
      final uri = Uri.parse(
        '$backendBaseUrl/api/conversations/?limit=20&offset=$offset',
      );
      final response = await http.get(uri, headers: _authHeaders);

      if (response.statusCode != 200) {
        throw Exception('Failed to load conversations (${response.statusCode})');
      }

      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final items = (body['results'] as List<dynamic>? ?? [])
          .map((e) => Conversation.fromJson(e as Map<String, dynamic>))
          .toList();

      setState(() {
        if (!append) {
          _conversations.clear();
        }
        _conversations.addAll(items);
        _hasMoreConversations = (body['has_more'] as bool?) ?? false;
        if (!append &&
            _conversations.isNotEmpty &&
            _selectedConversation == null) {
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

  Future<void> _loadMessagesForConversation(
    Conversation conversation, {
    bool silent = false,
  }) async {
    if (!silent) {
      setState(() {
        _isLoadingMessages = true;
        _messagesError = null;
      });
    }

    try {
      final uri = Uri.parse(
        '$backendBaseUrl/api/conversations/${conversation.id}/messages/',
      );
      final response = await http.get(uri, headers: _authHeaders);

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
        _hasMoreMessages = (body['has_more'] as bool?) ?? false;
        _isLoadingOlderMessages = false;
      });
    } catch (e) {
      setState(() {
        _messagesError = e.toString();
      });
    } finally {
      if (mounted && !silent) {
        setState(() {
          _isLoadingMessages = false;
        });
      }
    }
  }

  Future<void> _loadOlderMessages() async {
    final conversation = _selectedConversation;
    if (conversation == null) return;
    if (_messages.isEmpty || !_hasMoreMessages) return;

    setState(() {
      _isLoadingOlderMessages = true;
    });

    try {
      final oldestId = _messages.first.id;
      final uri = Uri.parse(
        '$backendBaseUrl/api/conversations/${conversation.id}/messages/?before=$oldestId',
      );
      final response = await http.get(uri, headers: _authHeaders);

      if (response.statusCode != 200) {
        throw Exception(
          'Failed to load older messages (${response.statusCode})',
        );
      }

      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final items = (body['results'] as List<dynamic>? ?? [])
          .map((e) => ChatMessage.fromJson(e as Map<String, dynamic>))
          .toList();

      setState(() {
        _messages.insertAll(0, items);
        _hasMoreMessages = (body['has_more'] as bool?) ?? false;
      });
    } catch (e) {
      setState(() {
        _messagesError = e.toString();
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingOlderMessages = false;
        });
      }
    }
  }

  Future<void> _loadConversationTypingAndPresence() async {
    final conversation = _selectedConversation;
    if (conversation == null) return;

    try {
      final uri = Uri.parse(
        '$backendBaseUrl/api/conversations/${conversation.id}/typing/',
      );
      final response = await http.get(uri, headers: _authHeaders);
      if (response.statusCode != 200) {
        return;
      }
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final participants = (body['participants'] as List<dynamic>? ?? [])
          .cast<Map<String, dynamic>>();
      final typingIds = (body['typing_ids'] as List<dynamic>? ?? [])
          .map((e) => e as int)
          .toList();

      // Presence text
      String? presenceText;
      if (participants.isNotEmpty) {
        if (conversation.isGroup) {
          final onlineCount = participants
              .where((p) => (p['is_online'] as bool?) ?? false)
              .length;
          if (onlineCount > 0) {
            presenceText = '$onlineCount online';
          }
        } else {
          Map<String, dynamic>? other;
          try {
            other = participants.firstWhere(
              (p) => (p['id'] as int?) != widget.currentUserId,
            );
          } catch (_) {
            other = participants.first;
          }

          if (other != null) {
            final isOnline = (other['is_online'] as bool?) ?? false;
            if (isOnline) {
              presenceText = 'Online';
            } else {
              final lastSeenStr = other['last_seen_at'] as String?;
              if (lastSeenStr != null) {
                final lastSeen = DateTime.tryParse(lastSeenStr);
                if (lastSeen != null) {
                  final now = DateTime.now().toUtc();
                  final diff = now.difference(lastSeen.toUtc());
                  if (diff.inMinutes < 1) {
                    presenceText = 'Last seen just now';
                  } else if (diff.inMinutes < 60) {
                    presenceText = 'Last seen ${diff.inMinutes} min ago';
                  } else if (diff.inHours < 24) {
                    presenceText = 'Last seen ${diff.inHours} h ago';
                  } else {
                    presenceText = 'Last seen ${diff.inDays} d ago';
                  }
                }
              }
            }
          }
        }
      }

      // Typing text (exclude self)
      String? typingText;
      final typingOthers = typingIds
          .where((id) => id != widget.currentUserId)
          .toSet();

      if (typingOthers.isNotEmpty) {
        final names = <String>[];
        for (final p in participants) {
          final id = p['id'] as int?;
          if (id != null && typingOthers.contains(id)) {
            final displayName =
                (p['display_name'] as String?)?.trim().isNotEmpty == true
                    ? (p['display_name'] as String)
                    : ((p['username'] as String?) ?? 'User');
            names.add(displayName);
          }
        }
        if (names.isNotEmpty) {
          if (names.length == 1) {
            typingText = '${names.first} is typing…';
          } else if (names.length == 2) {
            typingText = '${names[0]} and ${names[1]} are typing…';
          } else {
            typingText = 'Several people are typing…';
          }
        }
      }

      if (!mounted) return;
      setState(() {
        _presenceText = presenceText;
        _typingText = typingText;
      });
    } catch (_) {
      // Ignore for now; presence is best-effort.
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
        headers: {
          'Content-Type': 'application/json',
          ..._authHeaders,
        },
        body: jsonEncode({'content': text}),
      );

      if (response.statusCode != 201) {
        throw Exception('Failed to send message (${response.statusCode})');
      }

      _messageController.clear();
      // Reset typing status once the message is sent.
      _setTyping(isTyping: false);

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

  Future<void> _setTyping({required bool isTyping}) async {
    final conversation = _selectedConversation;
    if (conversation == null) return;

    if (isTyping == _typingNotified) return;
    _typingNotified = isTyping;

    try {
      final uri = Uri.parse(
        '$backendBaseUrl/api/conversations/${conversation.id}/typing/',
      );
      await http.post(
        uri,
        headers: {
          'Content-Type': 'application/json',
          ..._authHeaders,
        },
        body: jsonEncode({'is_typing': isTyping}),
      );
    } catch (_) {
      // typing is best-effort
    }
  }

  Future<void> _showStartConversationDialog() async {
    final controller = TextEditingController();
    String? error;

    await showDialog<void>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const Text('Start new chat'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Ask your friend for their 6-character ID and enter it below.',
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: controller,
                    textCapitalization: TextCapitalization.characters,
                    decoration: InputDecoration(
                      labelText: 'Friend code',
                      hintText: 'ABC123',
                      errorText: error,
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () async {
                    final code = controller.text.trim().toUpperCase();
                    if (code.length != 6) {
                      setState(() {
                        error = 'Code must be 6 characters.';
                      });
                      return;
                    }
                    try {
                      await _startConversationByRefCode(code);
                      if (context.mounted) {
                        Navigator.of(context).pop();
                      }
                    } catch (e) {
                      setState(() {
                        error = e.toString();
                      });
                    }
                  },
                  child: const Text('Start'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _startConversationByRefCode(String refCode) async {
    final uri = Uri.parse('$backendBaseUrl/api/conversations/start/');
    final response = await http.post(
      uri,
      headers: {
        'Content-Type': 'application/json',
        ..._authHeaders,
      },
      body: jsonEncode({'ref_code': refCode}),
    );

    if (response.statusCode != 201) {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      throw Exception(body['detail'] ?? 'Failed to start conversation');
    }

    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final conversation = Conversation.fromJson(body);

    setState(() {
      final index =
          _conversations.indexWhere((c) => c.id == conversation.id);
      if (index >= 0) {
        _conversations[index] = conversation;
      } else {
        _conversations.insert(0, conversation);
      }
      _selectedConversation = conversation;
    });

    await _loadMessagesForConversation(conversation);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            const HexagonLogo(size: 24),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('TrueSight Chat'),
                if (_displayName.isNotEmpty)
                  Text(
                    _displayName,
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
              ],
            ),
          ],
        ),
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
          PopupMenuButton<_ChatMenuAction>(
            onSelected: (value) {
              switch (value) {
                case _ChatMenuAction.profile:
                  _showEditProfileDialog(requireName: false);
                  break;
                case _ChatMenuAction.signOut:
                  widget.onSignOut();
                  break;
              }
            },
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: _ChatMenuAction.profile,
                child: Text('Profile & settings'),
              ),
              PopupMenuItem(
                value: _ChatMenuAction.signOut,
                child: Text('Sign out'),
              ),
            ],
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
                  child: ConversationList(
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
                    onStartNewConversation: _showStartConversationDialog,
                    ownRefCode: widget.refCode,
                    hasMore: _hasMoreConversations,
                    onLoadMore: _hasMoreConversations
                        ? () => _loadConversations(append: true)
                        : null,
                  ),
                ),
                const VerticalDivider(width: 1),
                Expanded(
                  child: ConversationArea(
                    conversation: _selectedConversation,
                    messages: _messages,
                    currentUserId: widget.currentUserId,
                    isLoading: _isLoadingMessages,
                    error: _messagesError,
                    messageController: _messageController,
                    onSendPressed: _isSending ? null : _sendMessage,
                    inputFocusNode: _inputFocusNode,
                    presenceText: _presenceText,
                    typingText: _typingText,
                    hasMoreMessages: _hasMoreMessages,
                    isLoadingOlderMessages: _isLoadingOlderMessages,
                    onLoadOlderMessages:
                        _hasMoreMessages ? _loadOlderMessages : null,
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
                child: ConversationList(
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
                  onStartNewConversation: _showStartConversationDialog,
                  ownRefCode: widget.refCode,
                  hasMore: _hasMoreConversations,
                  onLoadMore: _hasMoreConversations
                      ? () => _loadConversations(append: true)
                      : null,
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: ConversationArea(
                  conversation: _selectedConversation,
                  messages: _messages,
                  currentUserId: widget.currentUserId,
                  isLoading: _isLoadingMessages,
                  error: _messagesError,
                  messageController: _messageController,
                  onSendPressed: _isSending ? null : _sendMessage,
                  inputFocusNode: _inputFocusNode,
                  presenceText: _presenceText,
                  typingText: _typingText,
                  hasMoreMessages: _hasMoreMessages,
                  isLoadingOlderMessages: _isLoadingOlderMessages,
                  onLoadOlderMessages:
                      _hasMoreMessages ? _loadOlderMessages : null,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class ConversationList extends StatelessWidget {
  const ConversationList({
    super.key,
    required this.conversations,
    required this.selectedConversationId,
    required this.isLoading,
    required this.error,
    required this.onConversationSelected,
    required this.onStartNewConversation,
    required this.ownRefCode,
    required this.hasMore,
    required this.onLoadMore,
  });

  final List<Conversation> conversations;
  final int? selectedConversationId;
  final bool isLoading;
  final String? error;
  final ValueChanged<Conversation> onConversationSelected;
  final VoidCallback onStartNewConversation;
  final String ownRefCode;
  final bool hasMore;
  final VoidCallback? onLoadMore;

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
                const SizedBox(width: 8),
                if (ownRefCode.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: colorScheme.outlineVariant,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          ownRefCode,
                          style: Theme.of(context)
                              .textTheme
                              .labelSmall
                              ?.copyWith(color: colorScheme.onSurfaceVariant),
                        ),
                        const SizedBox(width: 4),
                        InkWell(
                          onTap: () async {
                            await Clipboard.setData(
                              ClipboardData(text: ownRefCode),
                            );
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Your ID copied to clipboard'),
                                  duration: Duration(seconds: 1),
                                ),
                              );
                            }
                          },
                          child: const Icon(
                            Icons.copy,
                            size: 16,
                          ),
                        ),
                      ],
                    ),
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
          Expanded(
            child: Builder(
              builder: (context) {
                if (error != null) {
                  return Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(
                      error!,
                      style: TextStyle(color: colorScheme.error),
                    ),
                  );
                }
                if (conversations.isEmpty && !isLoading) {
                  return const Padding(
                    padding: EdgeInsets.all(12),
                    child: Text('No conversations yet.'),
                  );
                }
                final totalCount =
                    conversations.length + (hasMore ? 1 : 0);

                return ListView.separated(
                  itemCount: totalCount,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    if (hasMore && index == conversations.length) {
                      return ListTile(
                        dense: true,
                        onTap: onLoadMore,
                        title: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            if (isLoading)
                              const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              ),
                            if (isLoading) const SizedBox(width: 8),
                            Text(
                              'Load more conversations',
                              style:
                                  Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                      );
                    }

                    final conversation = conversations[index];
                    final isSelected = conversation.id == selectedConversationId;

                    return Material(
                      color: isSelected
                          ? colorScheme.primaryContainer
                          : Colors.transparent,
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
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: colorScheme.primary,
                    foregroundColor: Colors.white,
                ),
                onPressed: onStartNewConversation,
                icon: const Icon(Icons.chat_outlined),
                label: const Text('New chat'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class ConversationArea extends StatelessWidget {
  const ConversationArea({
    super.key,
    required this.conversation,
    required this.messages,
    required this.currentUserId,
    required this.isLoading,
    required this.error,
    required this.messageController,
    required this.onSendPressed,
    required this.inputFocusNode,
    this.presenceText,
    this.typingText,
    this.hasMoreMessages = false,
    this.isLoadingOlderMessages = false,
    this.onLoadOlderMessages,
  });

  final Conversation? conversation;
  final List<ChatMessage> messages;
  final int currentUserId;
  final bool isLoading;
  final String? error;
  final TextEditingController messageController;
  final VoidCallback? onSendPressed;
  final FocusNode inputFocusNode;
  final String? presenceText;
  final String? typingText;
  final bool hasMoreMessages;
  final bool isLoadingOlderMessages;
  final VoidCallback? onLoadOlderMessages;

  Color _avatarColorFromHex(String? hex, Color fallback) {
    if (hex == null || hex.isEmpty) return fallback;
    try {
      final cleaned = hex.replaceFirst('#', '');
      return Color(int.parse('FF$cleaned', radix: 16));
    } catch (_) {
      return fallback;
    }
  }

  Widget _buildAvatar(BuildContext context, ChatMessage msg, bool isOwn) {
    final colorScheme = Theme.of(context).colorScheme;
    final baseColor =
        _avatarColorFromHex(msg.senderAvatarColor, colorScheme.secondary);
    final initials =
        (msg.senderName?.isNotEmpty ?? false) ? msg.senderName![0].toUpperCase() : '?';
    return CircleAvatar(
      radius: 16,
      backgroundColor: baseColor.withOpacity(0.9),
      child: Text(
        initials,
        style: Theme.of(context)
            .textTheme
            .labelSmall
            ?.copyWith(color: colorScheme.onSecondary),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (conversation == null) {
      return const EmptyChatPlaceholder();
    }

    final colorScheme = Theme.of(context).colorScheme;

    final title = conversation!.title.isNotEmpty
        ? conversation!.title
        : 'Conversation ${conversation!.id}';

    return Column(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          decoration: BoxDecoration(
            color: colorScheme.surfaceVariant.withOpacity(0.6),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.25),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
            border: Border(
              bottom: BorderSide(
                color: colorScheme.outlineVariant.withOpacity(0.8),
              ),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.w600),
                    ),
                  ),
                  if (presenceText != null && typingText == null)
                    Padding(
                      padding: const EdgeInsets.only(left: 12),
                      child: Text(
                        presenceText!,
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(
                              color: colorScheme.onSurfaceVariant
                                  .withOpacity(0.85),
                            ),
                      ),
                    ),
                ],
              ),
              if (typingText != null) ...[
                const SizedBox(height: 4),
                Text(
                  typingText!,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colorScheme.primary,
                        fontStyle: FontStyle.italic,
                      ),
                ),
              ],
            ],
          ),
        ),
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
                  : LayoutBuilder(
                      builder: (context, constraints) {
                        final maxBubbleWidth =
                            constraints.maxWidth * 0.65; // max ~65% width

                        final totalCount =
                            messages.length + (hasMoreMessages ? 1 : 0);

                        return ListView.builder(
                          padding: const EdgeInsets.all(16),
                          itemCount: totalCount,
                          itemBuilder: (context, index) {
                            if (hasMoreMessages && index == 0) {
                              return Padding(
                                padding:
                                    const EdgeInsets.only(bottom: 12.0),
                                child: Center(
                                  child: TextButton.icon(
                                    onPressed: isLoadingOlderMessages
                                        ? null
                                        : onLoadOlderMessages,
                                    icon: isLoadingOlderMessages
                                        ? const SizedBox(
                                            width: 16,
                                            height: 16,
                                            child:
                                                CircularProgressIndicator(
                                              strokeWidth: 2,
                                            ),
                                          )
                                        : const Icon(Icons.history),
                                    label: const Text('Load older messages'),
                                  ),
                                ),
                              );
                            }

                            final msgIndex =
                                hasMoreMessages ? index - 1 : index;
                            final msg = messages[msgIndex];
                            final isOwn = msg.senderId != null &&
                                msg.senderId == currentUserId;

                            final bubble = Container(
                              padding: const EdgeInsets.symmetric(
                                vertical: 8,
                                horizontal: 12,
                              ),
                              decoration: BoxDecoration(
                                gradient: isOwn
                                    ? LinearGradient(
                                        colors: [
                                          colorScheme.primary
                                              .withOpacity(0.95),
                                          colorScheme.primary
                                              .withOpacity(0.80),
                                        ],
                                      )
                                    : LinearGradient(
                                        colors: [
                                          colorScheme.surfaceVariant
                                              .withOpacity(0.9),
                                          colorScheme.surface
                                              .withOpacity(0.9),
                                        ],
                                      ),
                                borderRadius: BorderRadius.circular(18),
                                border: Border.all(
                                  color: isOwn
                                      ? colorScheme.primary.withOpacity(0.4)
                                      : colorScheme.surfaceVariant
                                          .withOpacity(0.6),
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.25),
                                    blurRadius: 6,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (!isOwn)
                                    Text(
                                      (msg.senderName?.isNotEmpty ?? false)
                                          ? msg.senderName!
                                          : 'User',
                                      style: Theme.of(context)
                                          .textTheme
                                          .labelSmall
                                          ?.copyWith(
                                            color: colorScheme.secondary
                                                .withOpacity(0.9),
                                          ),
                                    ),
                                  if (!isOwn) const SizedBox(height: 2),
                                  Text(
                                    msg.content,
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodyMedium
                                        ?.copyWith(
                                          color: isOwn
                                              ? colorScheme.onPrimary
                                              : colorScheme.onSurface,
                                        ),
                                  ),
                                  if (isOwn) const SizedBox(height: 2),
                                  if (isOwn)
                                    Align(
                                      alignment: Alignment.centerRight,
                                      child: Icon(
                                        msg.readByAll
                                            ? Icons.done_all
                                            : Icons.done,
                                        size: 14,
                                        color: colorScheme.onPrimary
                                            .withOpacity(
                                                msg.readByAll ? 0.95 : 0.7),
                                      ),
                                    ),
                                ],
                              ),
                            );

                            return Padding(
                              padding:
                                  const EdgeInsets.symmetric(vertical: 4),
                              child: Row(
                                mainAxisAlignment: isOwn
                                    ? MainAxisAlignment.end
                                    : MainAxisAlignment.start,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (!isOwn)
                                    _buildAvatar(context, msg, isOwn),
                                  if (!isOwn) const SizedBox(width: 8),
                                  ConstrainedBox(
                                    constraints: BoxConstraints(
                                      maxWidth: maxBubbleWidth,
                                    ),
                                    child: IntrinsicWidth(
                                      child: bubble,
                                    ),
                                  ),
                                  if (isOwn) const SizedBox(width: 8),
                                  if (isOwn)
                                    _buildAvatar(context, msg, isOwn),
                                ],
                              ),
                            );
                          },
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
                child: RawKeyboardListener(
                  focusNode: inputFocusNode,
                  onKey: (event) {
                    if (event is! RawKeyDownEvent) return;
                    if (event.logicalKey == LogicalKeyboardKey.enter) {
                      final isCtrlPressed = event.isControlPressed;
                      if (isCtrlPressed) {
                        final text = messageController.text;
                        final selection = messageController.selection;
                        final insertionIndex = selection.isValid
                            ? selection.start
                            : text.length;
                        final newText = text.replaceRange(
                          insertionIndex,
                          insertionIndex,
                          '\n',
                        );
                        messageController.text = newText;
                        messageController.selection = TextSelection.fromPosition(
                          TextPosition(offset: insertionIndex + 1),
                        );
                      } else {
                        onSendPressed?.call();
                      }
                    }
                  },
                  child: TextField(
                    controller: messageController,
                    minLines: 1,
                    maxLines: 4,
                    onChanged: (value) {
                      // Typing indicator: mark as typing immediately,
                      // then clear a short time after the user stops.
                      final shellState =
                          context.findAncestorStateOfType<_ChatShellPageState>();
                      shellState?._typingDebounce?.cancel();
                      shellState?._setTyping(isTyping: true);
                      shellState?._typingDebounce = Timer(
                        const Duration(seconds: 3),
                        () => shellState?._setTyping(isTyping: false),
                      );
                    },
                    decoration: const InputDecoration(
                      hintText: 'Type a message…',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
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

class EmptyChatPlaceholder extends StatelessWidget {
  const EmptyChatPlaceholder({super.key});

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
                'You are currently logged in with your email.',
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
