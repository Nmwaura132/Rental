import 'package:flutter/material.dart';

import '../theme/kasa_fonts.dart';
import '../theme/kasa_tokens.dart';
import 'kasa_logo.dart';
import 'kasa_primitives.dart';

/// The layout pieces every Kasa 2.0 screen is built from. They mirror the
/// canvas's `.actionbar`, `.appbar`, `.list`/`.row`, `.notice`, `.unit`,
/// `.sec-h` and `.kv` classes, so a screen is mostly arrangement.

// ─── Action bar ───────────────────────────────────────────────────────────────

/// The one primary action of a screen, pinned above the tab bar.
///
/// Pass as the screen Scaffold's `bottomNavigationBar`: inside the tab shell
/// that places it directly above the tabs, where the design keeps it.
class KasaActionBar extends StatelessWidget {
  const KasaActionBar({super.key, required this.children});

  /// Usually one KasaButton; a leading icon-only button may sit before it.
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: cs.kasaBg,
        border: Border(top: BorderSide(color: cs.kasaStroke)),
      ),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: SafeArea(
        top: false,
        // WHY the Column: a Scaffold hands its bottomNavigationBar the whole
        // screen height as the upper bound, and KasaButton grows to fill the
        // height it is given — so without this the bar covered the screen.
        // A min-sized Column lets the button take its own height.
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                for (var i = 0; i < children.length; i++) ...[
                  if (i > 0) const SizedBox(width: 8),
                  i == children.length - 1 ? Expanded(child: children[i]) : children[i],
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ─── App bars ─────────────────────────────────────────────────────────────────

/// A tab's home: the wordmark on the left, the viewer's initials on the right.
class KasaHomeAppBar extends StatelessWidget implements PreferredSizeWidget {
  const KasaHomeAppBar({super.key, required this.name, required this.onProfile});

  final String name;
  final VoidCallback onProfile;

  @override
  Size get preferredSize => const Size.fromHeight(60);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return AppBar(
      toolbarHeight: 60,
      backgroundColor: cs.kasaBg,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      titleSpacing: 16,
      automaticallyImplyLeading: false,
      title: const KasaWordmark(fontSize: 22),
      actions: [
        IconButton(
          tooltip: 'Profile',
          onPressed: onProfile,
          icon: KasaAvatar(name: name, size: 36),
        ),
        const SizedBox(width: 4),
      ],
    );
  }
}

// ─── Lists ────────────────────────────────────────────────────────────────────

/// Rows grouped in one card, separated by hairlines.
class KasaListGroup extends StatelessWidget {
  const KasaListGroup({super.key, required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: cs.kasaCard,
        borderRadius: BorderRadius.circular(KasaRadius.sm),
        border: Border.all(color: cs.kasaStroke),
      ),
      child: Column(
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) Divider(height: 1, thickness: 1, color: cs.kasaStroke),
            children[i],
          ],
        ],
      ),
    );
  }
}

/// A tinted square behind a row's icon. [tone] picks the status tint; null
/// is the neutral surface.
class KasaLeadIcon extends StatelessWidget {
  const KasaLeadIcon(this.icon, {super.key, this.tone});
  final IconData icon;
  final KasaStatusKind? tone;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final pair = tone == null ? null : cs.statusPair(tone!);
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: pair?.bg ?? cs.kasaElev,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Icon(icon, size: 20, color: pair?.fg ?? cs.onSurface),
    );
  }
}

class KasaListRow extends StatelessWidget {
  const KasaListRow({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    this.trailing,
    this.onTap,
    this.tight = false,
  });

  final String title;
  final String? subtitle;
  final Widget? leading;

  /// Defaults to a chevron when the row is tappable.
  final Widget? trailing;
  final VoidCallback? onTap;

  /// 52 tall instead of 64, for single-fact rows.
  final bool tight;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: tight ? 52 : 64),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 12, 10),
          child: Row(
            children: [
              if (leading != null) ...[leading!, const SizedBox(width: 12)],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: KasaFont.sans(
                            fontSize: 16, fontWeight: FontWeight.w600, color: cs.onSurface)),
                    if (subtitle != null) ...[
                      const SizedBox(height: 4),
                      Text(subtitle!,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: KasaFont.sans(fontSize: 14, color: cs.kasaTextSub)),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              trailing ??
                  (onTap != null
                      ? Icon(Icons.chevron_right_rounded, color: cs.kasaTextSub)
                      : const SizedBox.shrink()),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Section header and key/value ────────────────────────────────────────────

class KasaSectionHeader extends StatelessWidget {
  const KasaSectionHeader(this.title, {super.key, this.trailing});
  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Expanded(
          child: Text(title,
              style: KasaFont.sans(
                  fontSize: 16, fontWeight: FontWeight.w600, color: cs.onSurface)),
        ),
        if (trailing != null) trailing!,
      ],
    );
  }
}

/// "Rent ........ KES 25,000": a muted label and its value.
class KasaKeyValue extends StatelessWidget {
  const KasaKeyValue(this.label, this.value, {super.key, this.strong = false});
  final String label;
  final Widget value;

  /// Label in full text colour, for totals.
  final bool strong;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 36),
      child: Row(
        children: [
          Expanded(
            child: Text(label,
                style: KasaFont.sans(
                  fontSize: 14,
                  fontWeight: strong ? FontWeight.w600 : FontWeight.w400,
                  color: strong ? cs.onSurface : cs.kasaTextSub,
                )),
          ),
          value,
        ],
      ),
    );
  }
}

// ─── Notice ───────────────────────────────────────────────────────────────────

enum KasaNoticeTone { info, warn, bad }

/// A tinted banner: "Moving out 31 Oct", "4 readings missing".
class KasaNotice extends StatelessWidget {
  const KasaNotice({
    super.key,
    required this.icon,
    required this.title,
    this.body,
    this.tone = KasaNoticeTone.info,
  });

  final IconData icon;
  final String title;
  final String? body;
  final KasaNoticeTone tone;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final pair = cs.statusPair(switch (tone) {
      KasaNoticeTone.info => KasaStatusKind.notice,
      KasaNoticeTone.warn => KasaStatusKind.due,
      KasaNoticeTone.bad => KasaStatusKind.overdue,
    });
    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        decoration: BoxDecoration(
          color: pair.bg,
          borderRadius: BorderRadius.circular(KasaRadius.sm),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Icon(icon, size: 20, color: pair.fg),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: KasaFont.sans(
                          fontSize: 16, fontWeight: FontWeight.w600, color: pair.fg)),
                  if (body != null) ...[
                    const SizedBox(height: 4),
                    Text(body!, style: KasaFont.sans(fontSize: 14, color: cs.onSurface)),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Unit tile ────────────────────────────────────────────────────────────────

/// One unit in a property's grid: its number, who lives there, its status.
class KasaUnitTile extends StatelessWidget {
  const KasaUnitTile({
    super.key,
    required this.number,
    required this.occupant,
    required this.state,
    this.onTap,
  });

  final String number;
  final String occupant;

  /// The server's unit state: paid, due, arrears, vacant or notice.
  final String? state;
  final VoidCallback? onTap;

  static (KasaStatusKind, String)? statusFor(String? state) => switch (state) {
        'paid' => (KasaStatusKind.paid, 'Paid'),
        'due' => (KasaStatusKind.due, 'Due'),
        'arrears' => (KasaStatusKind.overdue, 'Arrears'),
        'vacant' => (KasaStatusKind.vacant, 'Vacant'),
        'notice' => (KasaStatusKind.notice, 'Notice'),
        _ => null,
      };

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final status = statusFor(state);
    return Material(
      color: cs.kasaCard,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: cs.kasaStroke),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 104),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(number,
                    style: KasaFont.sans(
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                      color: cs.onSurface,
                    ).copyWith(fontFeatures: const [FontFeature.tabularFigures()])),
                Text(occupant,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: KasaFont.sans(fontSize: 13, color: cs.kasaTextSub)),
                if (status != null) KasaStatusChip(kind: status.$1, label: status.$2),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
