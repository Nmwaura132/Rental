import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../core/api/api_client.dart';
import '../../core/widgets/kasa_primitives.dart';
import '../../core/theme/kasa_tokens.dart';

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

class NotificationsScreen extends ConsumerStatefulWidget {
  const NotificationsScreen({super.key});

  @override
  ConsumerState<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends ConsumerState<NotificationsScreen> {
  String _tab = 'all';

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final notifs = ref.watch(notificationsProvider);

    return Scaffold(
      backgroundColor: cs.kasaBg,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Header row ───────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back_ios_new, size: 20),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    onPressed: () => context.pop(),
                  ),
                  Expanded(
                    child: Center(
                      child: Text(
                        'NOTIFICATIONS',
                        style: GoogleFonts.spaceGrotesk(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.04,
                          color: cs.onSurface,
                        ),
                      ),
                    ),
                  ),
                  GestureDetector(
                    onTap: () {
                      HapticFeedback.lightImpact();
                      ref.invalidate(notificationsProvider);
                    },
                    child: Text(
                      'MARK READ',
                      style: GoogleFonts.spaceGrotesk(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.04,
                        color: cs.secondary,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // ── Filter chips row ─────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () {
                      HapticFeedback.selectionClick();
                      setState(() => _tab = 'all');
                    },
                    child: KasaChip(
                      label: 'ALL',
                      variant: _tab == 'all'
                          ? KasaChipVariant.primary
                          : KasaChipVariant.neutral,
                    ),
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: () {
                      HapticFeedback.selectionClick();
                      setState(() => _tab = 'unread');
                    },
                    child: KasaChip(
                      label: 'UNREAD',
                      variant: _tab == 'unread'
                          ? KasaChipVariant.primary
                          : KasaChipVariant.neutral,
                    ),
                  ),
                ],
              ),
            ),

            // ── Body ─────────────────────────────────────────────────────────
            Expanded(
              child: notifs.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => _ErrorState(
                  onRetry: () {
                    HapticFeedback.mediumImpact();
                    ref.invalidate(notificationsProvider);
                  },
                ),
                data: (rawList) {
                  List<dynamic> list = rawList;
                  if (_tab == 'unread') {
                    list = list.where((n) => n['is_read'] != true).toList();
                  }

                  if (list.isEmpty) return const _EmptyState();

                  return RefreshIndicator(
                    onRefresh: () async {
                      HapticFeedback.mediumImpact();
                      ref.invalidate(notificationsProvider);
                      await ref.read(notificationsProvider.future);
                    },
                    child: ListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                      itemCount: list.length,
                      itemBuilder: (_, i) =>
                          _NotificationTile(n: list[i] as Map<String, dynamic>),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Notification Tile ──────────────────────────────────────────────────────────

class _NotificationTile extends StatelessWidget {
  const _NotificationTile({required this.n});
  final Map<String, dynamic> n;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final channel = (n['channel'] as String? ?? 'push');
    final icon = _channelIcon[channel] ?? Icons.notifications_outlined;
    final accentColor = _channelColor[channel] ?? Colors.grey;
    final bool isUnread = n['is_read'] != true;
    final sent = n['status'] == 'sent';
    final subject = (n['subject'] as String?)?.trim();
    final message = (n['message'] as String? ?? '').trim();
    final rawDate = n['sent_at'] ?? n['created_at'];
    final dateStr = _formatDate(rawDate);

    // Build the left border: 6px primary if unread, else standard 2px stroke
    final borderLeft = BorderSide(
      color: isUnread ? cs.primary : cs.kasaStroke,
      width: isUnread ? 6.0 : KasaBorders.card,
    );
    final borderOther = BorderSide(color: cs.kasaStroke, width: KasaBorders.card);

    return GestureDetector(
      onTap: () => HapticFeedback.selectionClick(),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: BorderRadius.circular(KasaRadius.md),
          border: Border(
            left: borderLeft,
            right: borderOther,
            top: borderOther,
            bottom: borderOther,
          ),
          boxShadow: [
            BoxShadow(
              color: cs.kasaShadow,
              offset: const Offset(KasaBorders.shadow, KasaBorders.shadow),
              blurRadius: 0,
            ),
          ],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Icon box ────────────────────────────────────────────────────
            Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: cs.kasaStroke, width: KasaBorders.card),
                  ),
                  alignment: Alignment.center,
                  child: Icon(icon, color: accentColor, size: 18),
                ),
                if (isUnread)
                  Positioned(
                    top: -2,
                    right: -2,
                    child: Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: cs.primary,
                        shape: BoxShape.circle,
                        border: Border.all(color: cs.surface, width: 1.5),
                      ),
                    ),
                  ),
              ],
            ),

            const SizedBox(width: 12),

            // ── Content ─────────────────────────────────────────────────────
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Heading + status chip row
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          subject != null && subject.isNotEmpty
                              ? subject
                              : channel.toUpperCase(),
                          style: GoogleFonts.spaceGrotesk(
                            fontSize: 13,
                            fontWeight: isUnread ? FontWeight.w700 : FontWeight.w600,
                            color: cs.onSurface,
                            height: 1.2,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      // Status pill (sent / failed)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: (sent
                              ? Colors.green
                              : Colors.red
                          ).withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(KasaRadius.pill),
                          border: Border.all(
                            color: (sent ? Colors.green : Colors.red)
                                .withValues(alpha: 0.4),
                            width: 1,
                          ),
                        ),
                        child: Text(
                          sent ? 'SENT' : 'FAILED',
                          style: GoogleFonts.spaceGrotesk(
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                            color: sent ? Colors.green : Colors.red,
                            letterSpacing: 0.04,
                          ),
                        ),
                      ),
                    ],
                  ),

                  if (message.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      message,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: cs.kasaTextSub,
                        height: 1.4,
                      ),
                    ),
                  ],

                  const SizedBox(height: 6),

                  // Timestamp
                  Text(
                    dateStr,
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: cs.kasaTextSub,
                    ),
                  ),
                ],
              ),
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

// ── Empty state ────────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.notifications_none, size: 56, color: cs.kasaTextSub),
          const SizedBox(height: 16),
          Text(
            'NO NOTIFICATIONS',
            style: GoogleFonts.spaceGrotesk(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: cs.onSurface,
              letterSpacing: 0.04,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Rent reminders and receipts appear here.',
            style: GoogleFonts.inter(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: cs.kasaTextSub,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Error state ────────────────────────────────────────────────────────────────

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.onRetry});
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off_outlined, size: 56, color: cs.kasaTextSub),
            const SizedBox(height: 16),
            Text(
              'COULD NOT LOAD',
              style: GoogleFonts.spaceGrotesk(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: cs.onSurface,
                letterSpacing: 0.04,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Check your connection and try again.',
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: cs.kasaTextSub,
              ),
            ),
            const SizedBox(height: 24),
            KasaButton(
              label: 'Retry',
              leading: const Icon(Icons.refresh, size: 18),
              onTap: onRetry,
              fullWidth: false,
            ),
          ],
        ),
      ),
    );
  }
}
