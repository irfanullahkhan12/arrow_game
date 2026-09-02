import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../theme/game_theme.dart';

/// One circle on the power row.
class PowerItem {
  const PowerItem({
    required this.icon,
    required this.color,
    required this.label,
    required this.onTap,
    this.owned = 0,
    this.price = 0,
    this.badge,
    this.armed = false,
  });

  final IconData icon;
  final Color color;
  final String label;
  final VoidCallback onTap;

  /// How many the player has. Zero dims the circle and shows the price.
  final int owned;

  /// Coin price, shown when nothing is owned. Zero hides the price chip.
  final int price;

  /// Overrides the badge entirely — used for the rewards gift flag.
  final String? badge;

  /// This one is armed and waiting for the player to tap an arrow.
  final bool armed;

  bool get has => owned > 0;
}

/// Everything the player reaches for mid-game, in one bordered row: hints,
/// undo, every special arrow, and rewards at the end.
///
/// Items the player owns glow in their own colour with a count; the rest are
/// dimmed and wear their price, and tapping one buys it. Nothing is hidden —
/// a child can see the whole toy box and what each piece costs.
///
/// It is alive: the rainbow rim turns slowly, the circles pop in one after
/// another when a board loads, an armed arrow breathes, and a count that
/// changes bounces so the reward is felt and not just displayed.
class PowerRow extends StatefulWidget {
  const PowerRow({super.key, required this.items});

  final List<PowerItem> items;

  @override
  State<PowerRow> createState() => _PowerRowState();
}

class _PowerRowState extends State<PowerRow> with TickerProviderStateMixin {
  /// Turns the rim and breathes the armed circle. Slow on purpose: this is
  /// the only thing on screen animating while the player thinks.
  late final AnimationController _sweep = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 6),
  )..repeat();

  /// Runs once, to deal the circles in.
  late final AnimationController _entrance = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 750),
  )..forward();

  static const _rim = <Color>[
    Color(0xFFFF3D8B),
    Color(0xFFFFC61A),
    Color(0xFF56E03A),
    Color(0xFF00C2FF),
    Color(0xFF9B4DFF),
    Color(0xFFFF3D8B),
  ];

  @override
  void dispose() {
    _sweep.dispose();
    _entrance.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _sweep,
      builder: (context, child) {
        final turn = _sweep.value * 2 * math.pi;
        return Container(
          // The rim is a gradient, drawn as a 2px frame behind the card, and
          // it rotates.
          padding: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(26),
            gradient: LinearGradient(
              colors: _rim,
              begin: Alignment(math.cos(turn), math.sin(turn)),
              end: Alignment(-math.cos(turn), -math.sin(turn)),
            ),
            boxShadow: [
              BoxShadow(
                color: GameTheme.accent.withValues(alpha: 0.30),
                blurRadius: 16,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: child,
        );
      },
      child: Container(
        decoration: BoxDecoration(
          color: GameTheme.card,
          borderRadius: BorderRadius.circular(24),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 7),
        child: Row(
          children: [
            for (var i = 0; i < widget.items.length; i++)
              _PowerCircle(
                item: widget.items[i],
                sweep: _sweep,
                // Dealt left to right.
                entrance: CurvedAnimation(
                  parent: _entrance,
                  curve: Interval(
                    (i * 0.07).clamp(0.0, 0.6),
                    (i * 0.07 + 0.4).clamp(0.1, 1.0),
                    curve: Curves.easeOutBack,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _PowerCircle extends StatelessWidget {
  const _PowerCircle({
    required this.item,
    required this.sweep,
    required this.entrance,
  });

  final PowerItem item;
  final Animation<double> sweep;
  final Animation<double> entrance;

  @override
  Widget build(BuildContext context) {
    final live = item.has || item.price == 0;
    final tint = item.color;

    return Expanded(
      child: Material(
        color: item.armed ? tint.withValues(alpha: 0.18) : Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: item.onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Stack(
                  clipBehavior: Clip.none,
                  alignment: Alignment.center,
                  children: [
                    AnimatedBuilder(
                      // Only the armed circle keeps ticking; the rest settle
                      // once they have been dealt in.
                      animation: item.armed
                          ? Listenable.merge([sweep, entrance])
                          : entrance,
                      builder: (context, child) {
                        // An armed arrow breathes, so it is obvious the next
                        // tap belongs to it and not to the board.
                        final breathe = item.armed
                            ? 0.5 + 0.5 * math.sin(sweep.value * 2 * math.pi * 3)
                            : 0.0;
                        final pop = entrance.value.clamp(0.0, 2.0);
                        return Transform.scale(
                          scale: pop * (1 + 0.07 * breathe),
                          child: Opacity(
                            opacity: entrance.value.clamp(0.0, 1.0),
                            child: child,
                          ),
                        );
                      },
                      child: Opacity(
                        opacity: live ? 1 : 0.45,
                        child: _disc(tint),
                      ),
                    ),
                    Positioned(
                      top: -5,
                      right: -4,
                      child: FadeTransition(
                        opacity: entrance,
                        // A count that changes pops, so earning one is felt.
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 260),
                          transitionBuilder: (child, animation) =>
                              ScaleTransition(scale: animation, child: child),
                          child: _badge(tint),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  item.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GameTheme.font(
                    color: live
                        ? GameTheme.ink
                        : GameTheme.inkSoft.withValues(alpha: 0.7),
                    fontSize: 8,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _disc(Color tint) {
    return Container(
      width: 38,
      height: 38,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [
            tint.withValues(alpha: 0.42),
            tint.withValues(alpha: 0.10),
          ],
        ),
        border: Border.all(
          color: tint.withValues(alpha: item.armed ? 1 : 0.65),
          width: item.armed ? 2.2 : 1.6,
        ),
        boxShadow: [
          BoxShadow(
            color: tint.withValues(alpha: item.has ? 0.38 : 0.12),
            blurRadius: 14,
          ),
        ],
      ),
      child: Icon(item.icon, color: tint, size: 19),
    );
  }

  Widget _badge(Color tint) {
    final override = item.badge;
    if (override != null) {
      return _chip(override, GameTheme.gold, icon: null);
    }
    if (item.has) return _chip('${item.owned}', tint, icon: null);
    if (item.price > 0) {
      return _chip(
        '${item.price}',
        GameTheme.coin,
        icon: Icons.monetization_on_rounded,
      );
    }
    return const SizedBox.shrink();
  }

  Widget _chip(String text, Color color, {required IconData? icon}) {
    return Container(
      // The key is what makes a changed count animate instead of just
      // redrawing.
      key: ValueKey('$text$icon'),
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
      decoration: BoxDecoration(
        color: GameTheme.card,
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: color.withValues(alpha: 0.8), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, color: color, size: 8),
            const SizedBox(width: 2),
          ],
          Text(
            text,
            style: GameTheme.font(
              color: color,
              fontSize: 8.5,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}
