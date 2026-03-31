import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../core/api/api_client.dart';

final notificationsProvider = FutureProvider.autoDispose<List<dynamic>>((ref) async {
  final dio = ref.watch(dioProvider);
  final resp = await dio.get('/api/v1/notifications/');
  // API may return a list or a paginated object
  final data = resp.data;
  if (data is List) return data;
  if (data is Map && data['results'] is List) return data['results'] as List<dynamic>;
  return [];
});

const _channelIcon = {
  'sms': Icons.sms_outlined,
  'email': Icons.email_outlined,
  'whatsapp': Icons.chat_outlined,
  'push': Icons.notifications_outlined,
};

const _channelColor = {
  'sms': Colors.blue,
  'email': Colors.deepPurple,
  'whatsapp': Color(0xFF25D366),
  'push': Colors.orange,
};

final _dtFormat = DateFormat('dd MMM y · HH:mm');

class NotificationsScreen extends ConsumerWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifs = ref.watch(notificationsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: () {
              HapticFeedback.lightImpact();
              ref.invalidate(notificationsProvider);
            },
          ),
        ],
      ),
      body: notifs.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.cloud_off_outlined, size: 56, color: Colors.grey),
              const SizedBox(height: 12),
              const Text('Could not load notifications',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: () {
                  HapticFeedback.mediumImpact();
                  ref.invalidate(notificationsProvider);
                },
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
        data: (list) => list.isEmpty
            ? const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.notifications_none, size: 64, color: Colors.grey),
                    SizedBox(height: 12),
                    Text('No notifications yet.',
                        style: TextStyle(color: Colors.grey, fontSize: 16)),
                    SizedBox(height: 4),
                    Text('Rent reminders and receipts will appear here.',
                        style: TextStyle(color: Colors.grey, fontSize: 12)),
                  ],
                ),
              )
            : RefreshIndicator(
                onRefresh: () async {
                  HapticFeedback.mediumImpact();
                  await ref.refresh(notificationsProvider.future);
                },
                child: ListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: list.length,
                  itemBuilder: (_, i) => _NotificationTile(n: list[i] as Map<String, dynamic>),
                ),
              ),
      ),
    );
  }
}

class _NotificationTile extends StatelessWidget {
  const _NotificationTile({required this.n});
  final Map<String, dynamic> n;

  @override
  Widget build(BuildContext context) {
    final channel = (n['channel'] as String? ?? 'push');
    final icon = _channelIcon[channel] ?? Icons.notifications_outlined;
    final color = _channelColor[channel] ?? Colors.grey;
    final sent = n['status'] == 'sent';
    final subject = (n['subject'] as String?)?.trim();
    final message = (n['message'] as String? ?? '').trim();
    final rawDate = n['sent_at'] ?? n['created_at'];
    final dateStr = _formatDate(rawDate);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: ListTile(
        onTap: () {
          HapticFeedback.selectionClick();
        },
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        leading: CircleAvatar(
          backgroundColor: color.withValues(alpha: 0.12),
          child: Icon(icon, color: color, size: 20),
        ),
        title: subject != null && subject.isNotEmpty
            ? Text(subject,
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14))
            : Text(channel.toUpperCase(),
                style: TextStyle(
                    fontWeight: FontWeight.w600, fontSize: 13, color: color)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (message.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(message,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13)),
              ),
            const SizedBox(height: 4),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: (sent ? Colors.green : Colors.red).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    sent ? 'Sent' : 'Failed',
                    style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: sent ? Colors.green : Colors.red),
                  ),
                ),
                const SizedBox(width: 8),
                Text(dateStr,
                    style: const TextStyle(fontSize: 11, color: Colors.grey)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _formatDate(dynamic raw) {
    if (raw == null) return '';
    try {
      return _dtFormat.format(DateTime.parse(raw.toString()).toLocal());
    } catch (_) {
      return raw.toString();
    }
  }
}
