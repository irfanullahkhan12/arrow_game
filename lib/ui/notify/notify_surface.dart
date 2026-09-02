import 'dart:ui';

import 'package:flutter/material.dart';

import 'notify_style.dart';

/// The shared shell every notification is built on: rounded, shadowed, and
/// painted in one of the three skins.
///
/// Keeping the skin logic here is what makes solid / gradient / glass a
/// one-word change on any component rather than three copies of each widget.
class NotifySurface extends StatelessWidget {
  const NotifySurface({
    super.key,
    required this.palette,
    required this.skin,
    required this.child,
    this.radius = NotifyStyle.radius,
    this.padding = NotifyStyle.padCompact,
    this.onTap,
    this.accentEdge = false,
  });

  final NotifyPalette palette;
  final NotifySkin skin;
  final Widget child;
  final double radius;
  final EdgeInsets padding;
  final VoidCallback? onTap;

  /// Draws a thick bar of the tone down the leading edge — the quiet way to
  /// colour-code a notification whose body has to stay readable.
  final bool accentEdge;

  /// True when the content sits on the tone itself and must be drawn in
  /// [NotifyPalette.onColor].
  bool get onColor => skin == NotifySkin.gradient;

  @override
  Widget build(BuildContext context) {
    final corner = BorderRadius.circular(radius);

    Widget content = Padding(padding: padding, child: child);
    if (accentEdge) {
      content = Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(width: 5, color: palette.base),
          Expanded(child: content),
        ],
      );
    }

    Widget surface = switch (skin) {
      NotifySkin.solid => DecoratedBox(
        decoration: BoxDecoration(
          color: palette.surface,
          borderRadius: corner,
          border: Border.all(
            color: palette.base.withValues(alpha: 0.22),
            width: 1.2,
          ),
        ),
        child: content,
      ),
      NotifySkin.gradient => DecoratedBox(
        decoration: BoxDecoration(
          gradient: palette.gradient,
          borderRadius: corner,
        ),
        child: content,
      ),
      // Frosted: blur whatever is behind, then a translucent wash of the tone
      // and a bright hairline along the top edge to catch the light.
      NotifySkin.glass => BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: palette.surface.withValues(alpha: 0.55),
            borderRadius: corner,
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.28),
              width: 1.2,
            ),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                palette.base.withValues(alpha: 0.22),
                palette.deep.withValues(alpha: 0.06),
              ],
            ),
          ),
          child: content,
        ),
      ),
    };

    surface = ClipRRect(borderRadius: corner, child: surface);

    if (onTap != null) {
      surface = Stack(
        children: [
          surface,
          Positioned.fill(
            child: Material(
              color: Colors.transparent,
              child: InkWell(borderRadius: corner, onTap: onTap),
            ),
          ),
        ],
      );
    }

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: corner,
        boxShadow: [
          BoxShadow(
            color: palette.shadow,
            blurRadius: skin == NotifySkin.gradient ? 22 : 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: surface,
    );
  }
}

/// The round tone-coloured badge that leads most notifications.
class NotifyIcon extends StatelessWidget {
  const NotifyIcon({
    super.key,
    required this.palette,
    required this.icon,
    this.onColor = false,
    this.size = 40,
  });

  final NotifyPalette palette;
  final IconData icon;
  final bool onColor;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: onColor
            ? palette.onColor.withValues(alpha: 0.22)
            : palette.base.withValues(alpha: 0.14),
      ),
      child: Icon(
        icon,
        size: size * 0.52,
        color: onColor ? palette.onColor : palette.base,
      ),
    );
  }
}

/// A text action — the secondary button shape used across the set.
class NotifyAction extends StatelessWidget {
  const NotifyAction({
    super.key,
    required this.label,
    required this.color,
    required this.onTap,
    this.filled = false,
  });

  final String label;
  final Color color;
  final VoidCallback onTap;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: filled ? color : color.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(NotifyStyle.radiusSmall),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Text(
            label,
            style: NotifyStyle.action(filled ? Colors.white : color),
          ),
        ),
      ),
    );
  }
}
