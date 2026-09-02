import 'package:flutter/material.dart';

import '../../theme/game_theme.dart';

/// The page backdrop: a soft vertical gradient in the current theme.
class NeonBackground extends StatelessWidget {
  const NeonBackground({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [GameTheme.bgTop, GameTheme.bgMid, GameTheme.bgBottom],
        ),
      ),
      child: child,
    );
  }
}

/// A rounded card pill — the shape every HUD chip and button shares.
class NeonPill extends StatelessWidget {
  const NeonPill({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
    this.glow,
    this.onTap,
  });

  final Widget child;
  final EdgeInsets padding;
  final Color? glow;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final tint = glow ?? GameTheme.lilac;
    final pill = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: GameTheme.card,
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: tint.withValues(alpha: 0.45), width: 1.2),
        boxShadow: [
          BoxShadow(
            color: tint.withValues(alpha: 0.28),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: child,
    );
    if (onTap == null) return pill;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(30),
        onTap: onTap,
        child: pill,
      ),
    );
  }
}
