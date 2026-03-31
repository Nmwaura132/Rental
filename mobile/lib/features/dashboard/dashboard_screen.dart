import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/api/api_client.dart';
import '../../core/utils/currency.dart';

const _storage = FlutterSecureStorage();

final dashboardProvider = FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  final dio = ref.watch(dioProvider);
  final resp = await dio.get('/api/v1/payments/dashboard/');
  return resp.data as Map<String, dynamic>;
});

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stats = ref.watch(dashboardProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Dashboard'),
        actions: [
          IconButton(
            icon: const Icon(Icons.notifications_outlined),
            tooltip: 'Notifications',
            onPressed: () => context.go('/notifications'),
          ),
          IconButton(
            icon: const Icon(Icons.account_circle_outlined),
            tooltip: 'Profile',
            onPressed: () => context.go('/profile'),
          ),
        ],
      ),
      body: stats.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.cloud_off_outlined, size: 56, color: Colors.grey),
              const SizedBox(height: 12),
              const Text('Could not load dashboard',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              const Text('Check your connection and try again.',
                  style: TextStyle(color: Colors.grey, fontSize: 13)),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: () => ref.invalidate(dashboardProvider),
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
        data: (data) => RefreshIndicator(
          onRefresh: () => ref.refresh(dashboardProvider.future),
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _WelcomeBanner(),
                const SizedBox(height: 16),
                if (data.containsKey('properties')) ...[
                  _LandlordStats(data: data),
                ] else ...[
                  _TenantStats(data: data),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _WelcomeBanner extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String?>(
      future: _storage.read(key: 'user_name'),
      builder: (_, snap) => Text(
        'Hello, ${snap.data ?? 'there'} 👋',
        style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
      ),
    );
  }
}

class _LandlordStats extends StatelessWidget {
  const _LandlordStats({required this.data});
  final Map<String, dynamic> data;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            _StatCard(
              label: 'Properties',
              value: '${data['properties']}',
              icon: Icons.home_work,
              onTap: () => context.go('/properties'),
            ),
            const SizedBox(width: 12),
            _StatCard(
              label: 'Total Units',
              value: '${data['total_units']}',
              icon: Icons.meeting_room,
              onTap: () => context.go('/properties'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            _StatCard(
              label: 'Occupied',
              value: '${data['occupied_units']}',
              icon: Icons.people,
              color: Colors.green,
              onTap: () => context.go('/tenants'),
            ),
            const SizedBox(width: 12),
            _StatCard(
              label: 'Vacant',
              value: '${data['vacant_units']}',
              icon: Icons.door_front_door,
              color: Colors.orange,
              onTap: () => context.go('/properties'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _BigStatCard(
          label: 'Collected This Month',
          value: formatCurrency(toDouble(data['monthly_collected_kes'])),
          icon: Icons.payments,
          color: Colors.green,
          onTap: () => context.go('/invoices'),
        ),
        const SizedBox(height: 12),
        _BigStatCard(
          label: 'Overdue Amount',
          value: formatCurrency(toDouble(data['overdue_amount_kes'])),
          subtitle: '${data['overdue_invoices'] ?? 0} invoices overdue',
          icon: Icons.warning_amber,
          color: Colors.red,
          onTap: () => context.go('/invoices'),
        ),
      ],
    );
  }
}

class _TenantStats extends StatelessWidget {
  const _TenantStats({required this.data});
  final Map<String, dynamic> data;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        _BigStatCard(
          label: 'Outstanding Balance',
          value: formatCurrency(toDouble(data['outstanding_balance'])),
          icon: Icons.account_balance_wallet,
          color: toDouble(data['outstanding_balance']) > 0 ? Colors.red : Colors.green,
          onTap: () => context.go('/invoices'),
        ),
        if (data['next_due_date'] != null) ...[
          const SizedBox(height: 12),
          _BigStatCard(
            label: 'Next Payment Due',
            value: formatCurrency(toDouble(data['next_due_amount'])),
            subtitle: 'Due: ${data['next_due_date']}',
            icon: Icons.calendar_today,
            color: Colors.orange,
            onTap: () => context.go('/invoices'),
          ),
        ],
        if (data['unit_number'] != null) ...[
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('My Unit', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  _InfoRow('Property', data['property_name']),
                  _InfoRow('Unit', data['unit_number']),
                  _InfoRow('Monthly Rent', formatCurrency(toDouble(data['monthly_rent']))),
                  _InfoRow('Lease', '${_fmtDate(data['lease_start'])} – ${_fmtDate(data['lease_end'])}'),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Card(
            color: Colors.green.shade50,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('How to Pay (M-Pesa)', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  const _InfoRow('1. Go to', 'Lipa na M-Pesa → Pay Bill'),
                  _InfoRow('2. Business No.', data['mpesa_paybill'] ?? '—'),
                  _InfoRow('3. Account No.', data['unit_number']),
                  _InfoRow('4. Amount', formatCurrency(toDouble(data['monthly_rent']))),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({required this.label, required this.value, required this.icon, this.color, this.onTap});
  final String label, value;
  final IconData icon;
  final Color? color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Card(
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, color: color ?? Theme.of(context).colorScheme.primary, size: 28),
                const SizedBox(height: 8),
                Text(value, style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold)),
                Text(label, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _BigStatCard extends StatelessWidget {
  const _BigStatCard({required this.label, required this.value, required this.icon, this.subtitle, this.color, this.onTap});
  final String label, value;
  final String? subtitle;
  final IconData icon;
  final Color? color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        onTap: onTap,
        leading: CircleAvatar(
          backgroundColor: (color ?? Theme.of(context).colorScheme.primary).withValues(alpha: 0.15),
          child: Icon(icon, color: color ?? Theme.of(context).colorScheme.primary),
        ),
        title: Text(value, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
        subtitle: Text(subtitle ?? label),
        trailing: const Icon(Icons.chevron_right),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow(this.label, this.value);
  final String label;
  final dynamic value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.grey, fontSize: 13)),
          Flexible(
            child: Text(
              '${value ?? '—'}',
              style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13),
              textAlign: TextAlign.end,
            ),
          ),
        ],
      ),
    );
  }
}

String _fmtDate(dynamic iso) {
  if (iso == null) return '—';
  final d = DateTime.tryParse(iso.toString());
  return d == null ? '—' : DateFormat('d MMM yyyy').format(d);
}
