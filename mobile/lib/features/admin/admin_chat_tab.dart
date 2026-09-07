import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/api_client.dart';
import '../../core/app_theme.dart';
import '../../core/auth_storage.dart';
import '../../core/models.dart';

const _pollInterval = Duration(seconds: 5);

class AdminChatTab extends StatefulWidget {
  const AdminChatTab({super.key});

  @override
  State<AdminChatTab> createState() => _AdminChatTabState();
}

class _AdminChatTabState extends State<AdminChatTab> {
  bool _loading = true;
  List<ChatThreadSummary> _threads = [];
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _load();
    _timer = Timer.periodic(_pollInterval, (_) => _load(silent: true));
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) setState(() => _loading = true);
    try {
      final data = await ApiClient.instance.get('/chat/threads') as List;
      final threads = data.map((e) => ChatThreadSummary.fromJson(e as Map<String, dynamic>)).toList();
      if (mounted) setState(() => _threads = threads);
    } on ApiException catch (_) {
      // best-effort background poll
    } finally {
      if (mounted && !silent) setState(() => _loading = false);
    }
  }

  String _timeAgo(String? iso) {
    if (iso == null) return '';
    final dt = DateTime.tryParse(iso);
    if (dt == null) return '';
    final seconds = DateTime.now().difference(dt).inSeconds;
    if (seconds < 60) return 'just now';
    final minutes = seconds ~/ 60;
    if (minutes < 60) return '${minutes}m ago';
    final hours = minutes ~/ 60;
    if (hours < 24) return '${hours}h ago';
    return '${hours ~/ 24}d ago';
  }

  @override
  Widget build(BuildContext context) {
    return _loading
        ? const Center(child: CircularProgressIndicator())
        : RefreshIndicator(
            onRefresh: () => _load(),
            child: _threads.isEmpty
                ? ListView(children: const [Padding(padding: EdgeInsets.all(32), child: Center(child: Text('No conversations yet.')))])
                : ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: _threads.length,
                    itemBuilder: (context, i) {
                      final t = _threads[i];
                      return Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          leading: const CircleAvatar(backgroundColor: AppColors.brandLight, child: Icon(Icons.person, color: AppColors.brandOrange)),
                          title: Text(t.coachName, style: const TextStyle(fontWeight: FontWeight.bold)),
                          subtitle: Text(t.lastMessage ?? 'No messages yet', maxLines: 1, overflow: TextOverflow.ellipsis),
                          trailing: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(_timeAgo(t.lastMessageAt), style: const TextStyle(fontSize: 11, color: AppColors.textMuted)),
                              if (t.unreadCount > 0) ...[
                                const SizedBox(height: 4),
                                CircleAvatar(radius: 10, backgroundColor: AppColors.danger, child: Text('${t.unreadCount}', style: const TextStyle(fontSize: 11, color: Colors.white))),
                              ],
                            ],
                          ),
                          onTap: () async {
                            await Navigator.of(context).push(MaterialPageRoute(builder: (_) => _ChatConversationScreen(coachId: t.coachId, coachName: t.coachName)));
                            _load();
                          },
                        ),
                      );
                    },
                  ),
          );
  }
}

class _ChatConversationScreen extends StatefulWidget {
  final int coachId;
  final String coachName;
  const _ChatConversationScreen({required this.coachId, required this.coachName});

  @override
  State<_ChatConversationScreen> createState() => _ChatConversationScreenState();
}

class _ChatConversationScreenState extends State<_ChatConversationScreen> {
  List<ChatMessage> _messages = [];
  bool _loading = true;
  bool _sending = false;
  int? _myUserId;
  final _draftCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  Timer? _timer;
  int _lastId = 0;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    final session = await AuthStorage.load();
    _myUserId = session?.userId;
    await _loadInitial();
    ApiClient.instance.put('/chat/read', query: {'coach_id': widget.coachId}).catchError((_) => null);
    _timer = Timer.periodic(_pollInterval, (_) => _poll());
  }

  Future<void> _loadInitial() async {
    setState(() => _loading = true);
    try {
      final data = await ApiClient.instance.get('/chat/messages', query: {'coach_id': widget.coachId}) as List;
      _messages = data.map((e) => ChatMessage.fromJson(e as Map<String, dynamic>)).toList();
      if (_messages.isNotEmpty) _lastId = _messages.last.id;
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) {
        setState(() => _loading = false);
        _scrollToBottom();
      }
    }
  }

  Future<void> _poll() async {
    try {
      final data = await ApiClient.instance.get('/chat/messages', query: {'coach_id': widget.coachId, 'since_id': _lastId}) as List;
      if (data.isEmpty || !mounted) return;
      final newMessages = data.map((e) => ChatMessage.fromJson(e as Map<String, dynamic>)).toList();
      setState(() => _messages.addAll(newMessages));
      _lastId = _messages.last.id;
      _scrollToBottom();
      ApiClient.instance.put('/chat/read', query: {'coach_id': widget.coachId}).catchError((_) => null);
    } catch (_) {
      // best-effort poll
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) _scrollCtrl.jumpTo(_scrollCtrl.position.maxScrollExtent);
    });
  }

  Future<void> _send() async {
    final text = _draftCtrl.text.trim();
    if (text.isEmpty) return;
    setState(() => _sending = true);
    try {
      final data = await ApiClient.instance.post('/chat/messages', body: {'message': text, 'coach_id': widget.coachId}) as Map<String, dynamic>;
      final msg = ChatMessage.fromJson(data);
      setState(() {
        _messages.add(msg);
        _lastId = msg.id;
        _draftCtrl.clear();
      });
      _scrollToBottom();
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _draftCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  String _timeLabel(String iso) {
    final dt = DateTime.tryParse(iso);
    if (dt == null) return '';
    return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.coachName)),
      body: Column(
        children: [
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _messages.isEmpty
                    ? const Center(child: Text('No messages yet. Say hello!'))
                    : ListView.builder(
                        controller: _scrollCtrl,
                        padding: const EdgeInsets.all(12),
                        itemCount: _messages.length,
                        itemBuilder: (context, i) {
                          final m = _messages[i];
                          final mine = m.senderId == _myUserId;
                          return Align(
                            alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
                            child: Container(
                              margin: const EdgeInsets.symmetric(vertical: 4),
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
                              decoration: BoxDecoration(
                                color: mine ? AppColors.brandOrange : AppColors.brandLight,
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (!mine) Text(m.senderName, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.brandOrangeDark)),
                                  Text(m.message, style: TextStyle(color: mine ? Colors.white : AppColors.text)),
                                  const SizedBox(height: 2),
                                  Text(_timeLabel(m.createdAt), style: TextStyle(fontSize: 10, color: mine ? Colors.white70 : AppColors.textMuted)),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _draftCtrl,
                      decoration: const InputDecoration(hintText: 'Type a message...'),
                      onSubmitted: (_) => _send(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    onPressed: _sending ? null : _send,
                    icon: const Icon(Icons.send),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
