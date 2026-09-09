import 'package:flutter/material.dart';
import '../../core/notification_polling_service.dart';
import 'notification_center_screen.dart';

/// Drop into any AppBar's `actions` for the same bell-with-unread-badge the web
/// dashboard has (NotificationBell.jsx). Reads from NotificationPollingService's
/// shared count rather than polling itself — several of these can be mounted at
/// once (every IndexedStack tab stays alive), and only one poller should exist.
class NotificationBellAction extends StatelessWidget {
  const NotificationBellAction({super.key});

  Future<void> _open(BuildContext context) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const NotificationCenterScreen()));
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: NotificationPollingService.unreadCount,
      builder: (context, unreadCount, _) {
        return Stack(
          clipBehavior: Clip.none,
          children: [
            IconButton(icon: const Icon(Icons.notifications_outlined), onPressed: () => _open(context)),
            if (unreadCount > 0)
              Positioned(
                top: 6,
                right: 6,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                  constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                  decoration: BoxDecoration(color: Colors.red, borderRadius: BorderRadius.circular(999)),
                  child: Text(
                    unreadCount > 9 ? '9+' : '$unreadCount',
                    style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
