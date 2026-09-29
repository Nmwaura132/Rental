import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers/user_role_provider.dart';
import '../../core/theme/kasa_tokens.dart';

/// The "More" tab for landlords and the "Me" tab for tenants.
///
/// It holds what does not earn a tab of its own: the tenants directory,
/// reports, the tax statement, notifications and the profile. Rows only link
/// to screens that already exist; nothing here loads data, so it opens
/// instantly and has no loading or error state to design.
class MoreScreen extends ConsumerWidget {
  const MoreScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final role = ref.watch(userRoleProvider).valueOrNull;
    final isTenant = role == 'tenant';
    final cs = Theme.of(context).colorScheme;

    // Scaffold(extendBody: true) hands the bar's height down as bottom padding,
    // so the last row is never tucked under it.
    final bottomClear = MediaQuery.of(context).padding.bottom;

    final groups = <_Group>[
      if (!isTenant) ...[
        _Group('People', [
          _Row(
            icon: Icons.people_outline_rounded,
            title: 'Tenants',
            subtitle: 'Everyone living in your units',
            onTap: () => context.push('/tenants'),
          ),
        ]),
        _Group('Finance', [
          _Row(
            icon: Icons.description_outlined,
            title: 'Reports',
            subtitle: 'Rent roll, arrears and collections',
            onTap: () => context.push('/reports'),
          ),
          _Row(
            icon: Icons.receipt_long_outlined,
            title: 'Tax statement',
            subtitle: 'KRA monthly rental income',
            onTap: () => context.push('/tax'),
          ),
        ]),
      ],
      _Group('Account', [
        _Row(
          icon: Icons.notifications_none_rounded,
          title: 'Notifications',
          onTap: () => context.push('/notifications'),
        ),
        _Row(
          icon: Icons.person_outline_rounded,
          title: 'Profile and settings',
          onTap: () => context.push('/profile'),
        ),
      ]),
    ];

    return Scaffold(
      backgroundColor: cs.kasaBg,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: Text(isTenant ? 'Me' : 'More'),
      ),
      body: ListView(
        padding: EdgeInsets.fromLTRB(
          KasaSpace.gutter,
          KasaSpace.sm,
          KasaSpace.gutter,
          KasaSpace.xxl + bottomClear,
        ),
        children: [
          for (final g in groups) ...[
            _GroupHeader(g.title),
            _GroupList(g.rows),
            const SizedBox(height: KasaSpace.xl),
          ],
        ],
      ),
    );
  }
}

class _Group {
  const _Group(this.title, this.rows);
  final String title;
  final List<_Row> rows;
}

class _Row {
  const _Row({
    required this.icon,
    required this.title,
    required this.onTap,
    this.subtitle,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;
}

class _GroupHeader extends StatelessWidget {
  const _GroupHeader(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: KasaSpace.sm),
      // A heading, not a decoration: screen readers can jump between groups.
      child: Semantics(
        header: true,
        child: Text(
          title,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: cs.onSurfaceVariant,
                fontWeight: FontWeight.w500,
              ),
        ),
      ),
    );
  }
}

class _GroupList extends StatelessWidget {
  const _GroupList(this.rows);

  final List<_Row> rows;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(KasaRadius.md),
        border: Border.all(color: cs.kasaStroke, width: KasaBorders.hairline),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0) Divider(height: 1, thickness: 1, color: cs.kasaStroke),
            _RowTile(rows[i]),
          ],
        ],
      ),
    );
  }
}

class _RowTile extends StatelessWidget {
  const _RowTile(this.row);

  final _Row row;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return InkWell(
      onTap: row.onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 64),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: KasaSpace.lg,
            vertical: KasaSpace.md,
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(KasaRadius.sm),
                ),
                child: Icon(row.icon, size: 20, color: cs.onSurface),
              ),
              const SizedBox(width: KasaSpace.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      row.title,
                      style: tt.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
                    ),
                    if (row.subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        row.subtitle!,
                        style: tt.bodyMedium?.copyWith(
                          color: cs.onSurfaceVariant,
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: cs.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}
