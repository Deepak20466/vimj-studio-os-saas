import 'package:flutter/material.dart';
import '../../core/api_client.dart';
import '../../core/app_theme.dart';
import '../../core/models.dart';

class NotificationCenterScreen extends StatefulWidget {
  const NotificationCenterScreen({super.key});

  @override
  State<NotificationCenterScreen> createState() => _NotificationCenterScreenState();
}

class _NotificationCenterScreenState extends State<NotificationCenterScreen> {
  List<AppNotification> _items = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final data = await ApiClient.instance.get('/notifications') as Map<String, dynamic>;
      _items = (data['items'] as List).map((e) => AppNotification.fromJson(e as Map<String, dynamic>)).toList();
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _markRead(AppNotification n) async {
    if (n.isRead) return;
    try {
      await ApiClient.instance.put('/notifications/${n.id}/read');
      if (mounted) {
        setState(() {
          final i = _items.indexWhere((x) => x.id == n.id);
          if (i != -1) {
            _items[i] = AppNotification(
              id: n.id, type: n.type, title: n.title, message: n.message,
              link: n.link, delayMinutes: n.delayMinutes, isRead: true, createdAt: n.createdAt,
            );
          }
        });
      }
    } on ApiException {
      // best-effort
    }
  }

  Future<void> _markAllRead() async {
    try {
      await ApiClient.instance.put('/notifications/read-all');
      _load();
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  String _timeAgo(String iso) {
    final dt = DateTime.tryParse(iso);
    if (dt == null) return '';
    final diff = DateTime.now().toUtc().difference(dt.toUtc());
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  @override
  Widget build(BuildContext context) {
    final hasUnread = _items.any((n) => !n.isRead);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications'),
        actions: [
          if (hasUnread) TextButton(onPressed: _markAllRead, child: const Text('Mark all read', style: TextStyle(color: Colors.white))),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: _items.isEmpty
                  ? ListView(children: const [Padding(padding: EdgeInsets.all(32), child: Center(child: Text('No notifications yet.')))])
                  : ListView.separated(
                      padding: const EdgeInsets.all(12),
                      itemCount: _items.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 6),
                      itemBuilder: (context, i) {
                        final n = _items[i];
                        return Card(
                          color: n.isRead ? null : AppColors.brandOrange.withOpacity(0.08),
                          child: ListTile(
                            onTap: () => _markRead(n),
                            title: Text(n.title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                            subtitle: Text(n.message, style: const TextStyle(fontSize: 12.5)),
                            trailing: Text(_timeAgo(n.createdAt), style: const TextStyle(fontSize: 11, color: AppColors.textMuted)),
                          ),
                        );
                      },
                    ),
            ),
    );
  }
}
