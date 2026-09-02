import 'package:flutter/material.dart';

import 'notify_style.dart';
import 'notify_surface.dart';

/// The five in-app notification shapes, all built on [NotifySurface] so a
/// change of tone or skin is a one-word edit on any of them.
///
///  * [NotifyToast]  — bottom-anchored, auto-dismissing, icon + message + action
///  * [NotifyBanner] — top-anchored alert strip
///  * [NotifyCard]   — a row in a notification inbox
///  * [NotifyPill]   — a capsule for "Saved" / "Copied"
///  * [NotifyRich]   — thumbnail, two actions, the one that asks for a decision
///
/// Every one takes [compact] so the same call site can be tested tight or
/// roomy, and none of them position themselves — see the presenter functions
/// at the bottom for that.

// ─── Toast ───────────────────────────────────────────────────────────────────

class NotifyToast extends StatelessWidget {
  const NotifyToast({
    super.key,
    required this.message,
    this.title,
    this.tone = NotifyTone.brand,
    this.skin = NotifySkin.solid,
    this.icon,
    this.actionLabel,
    this.onAction,
    this.compact = true,
  });

  final String message;
  final String? title;
  final NotifyTone tone;
  final NotifySkin skin;
  final IconData? icon;
  final String? actionLabel;
  final VoidCallback? onAction;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final palette = NotifyStyle.of(tone, Theme.of(context).brightness);
    final onColor = skin == NotifySkin.gradient;

    return NotifySurface(
      palette: palette,
      skin: skin,
      padding: compact ? NotifyStyle.padCompact : NotifyStyle.padExpanded,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          NotifyIcon(
            palette: palette,
            icon: icon ?? NotifyStyle.iconFor(tone),
            onColor: onColor,
            size: compact ? 34 : 42,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (title != null) ...[
                  Text(
                    title!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: NotifyStyle.title(palette, onColor: onColor),
                  ),
                  const SizedBox(height: 2),
                ],
                Text(
                  message,
                  maxLines: compact ? 2 : 4,
                  overflow: TextOverflow.ellipsis,
                  style: title == null
                      ? NotifyStyle.title(palette, onColor: onColor)
                      : NotifyStyle.body(palette, onColor: onColor),
                ),
              ],
            ),
          ),
          if (actionLabel != null) ...[
            const SizedBox(width: 10),
            NotifyAction(
              label: actionLabel!,
              color: onColor ? palette.onColor : palette.base,
              onTap: onAction ?? () {},
            ),
          ],
        ],
      ),
    );
  }
}

// ─── Top banner ──────────────────────────────────────────────────────────────

class NotifyBanner extends StatelessWidget {
  const NotifyBanner({
    super.key,
    required this.title,
    this.message,
    this.tone = NotifyTone.info,
    this.skin = NotifySkin.solid,
    this.icon,
    this.onDismiss,
    this.compact = false,
  });

  final String title;
  final String? message;
  final NotifyTone tone;
  final NotifySkin skin;
  final IconData? icon;
  final VoidCallback? onDismiss;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final palette = NotifyStyle.of(tone, Theme.of(context).brightness);
    final onColor = skin == NotifySkin.gradient;

    return NotifySurface(
      palette: palette,
      skin: skin,
      // A leading colour bar, so the tone reads even at a glance from the top
      // of the screen where the eye only passes through.
      accentEdge: skin == NotifySkin.solid,
      padding: compact
          ? const EdgeInsets.fromLTRB(12, 10, 8, 10)
          : const EdgeInsets.fromLTRB(14, 14, 10, 14),
      child: Row(
        children: [
          Icon(
            icon ?? NotifyStyle.iconFor(tone),
            color: onColor ? palette.onColor : palette.base,
            size: compact ? 20 : 24,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: NotifyStyle.title(palette, onColor: onColor),
                ),
                if (message != null && !compact) ...[
                  const SizedBox(height: 3),
                  Text(
                    message!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: NotifyStyle.body(palette, onColor: onColor),
                  ),
                ],
              ],
            ),
          ),
          if (onDismiss != null)
            IconButton(
              onPressed: onDismiss,
              visualDensity: VisualDensity.compact,
              icon: Icon(
                Icons.close_rounded,
                size: 18,
                color: onColor
                    ? palette.onColor.withValues(alpha: 0.8)
                    : palette.body,
              ),
            ),
        ],
      ),
    );
  }
}

// ─── Inbox card ──────────────────────────────────────────────────────────────

class NotifyCard extends StatelessWidget {
  const NotifyCard({
    super.key,
    required this.title,
    required this.body,
    required this.timestamp,
    this.tone = NotifyTone.brand,
    this.skin = NotifySkin.solid,
    this.icon,
    this.avatar,
    this.unread = false,
    this.onTap,
    this.compact = false,
  });

  final String title;
  final String body;
  final String timestamp;
  final NotifyTone tone;
  final NotifySkin skin;
  final IconData? icon;

  /// An image to use instead of the icon badge — a sender's face, say.
  final ImageProvider? avatar;
  final bool unread;
  final VoidCallback? onTap;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final palette = NotifyStyle.of(tone, Theme.of(context).brightness);
    final onColor = skin == NotifySkin.gradient;

    return NotifySurface(
      palette: palette,
      skin: skin,
      onTap: onTap,
      padding: compact
          ? const EdgeInsets.fromLTRB(12, 12, 12, 12)
          : NotifyStyle.padExpanded,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (avatar != null)
            CircleAvatar(radius: compact ? 18 : 22, backgroundImage: avatar)
          else
            NotifyIcon(
              palette: palette,
              icon: icon ?? NotifyStyle.iconFor(tone),
              onColor: onColor,
              size: compact ? 36 : 44,
            ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: NotifyStyle.title(palette, onColor: onColor),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      timestamp,
                      style: NotifyStyle.meta(palette, onColor: onColor),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  body,
                  maxLines: compact ? 1 : 3,
                  overflow: TextOverflow.ellipsis,
                  style: NotifyStyle.body(palette, onColor: onColor),
                ),
              ],
            ),
          ),
          // The unread mark is a dot, not a badge: it says "new" without
          // competing with the title for attention.
          if (unread) ...[
            const SizedBox(width: 10),
            Container(
              width: 9,
              height: 9,
              margin: const EdgeInsets.only(top: 6),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: onColor ? palette.onColor : palette.base,
                boxShadow: [
                  BoxShadow(
                    color: palette.base.withValues(alpha: 0.6),
                    blurRadius: 8,
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ─── Floating pill ───────────────────────────────────────────────────────────

class NotifyPill extends StatelessWidget {
  const NotifyPill({
    super.key,
    required this.label,
    this.tone = NotifyTone.success,
    this.skin = NotifySkin.solid,
    this.icon,
  });

  final String label;
  final NotifyTone tone;
  final NotifySkin skin;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final palette = NotifyStyle.of(tone, Theme.of(context).brightness);
    final onColor = skin == NotifySkin.gradient;

    return NotifySurface(
      palette: palette,
      skin: skin,
      radius: NotifyStyle.radiusPill,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon ?? Icons.check_rounded,
            size: 17,
            color: onColor ? palette.onColor : palette.base,
          ),
          const SizedBox(width: 8),
          Text(
            label,
            style: NotifyStyle.title(palette, onColor: onColor),
          ),
        ],
      ),
    );
  }
}

// ─── Rich card ───────────────────────────────────────────────────────────────

class NotifyRich extends StatelessWidget {
  const NotifyRich({
    super.key,
    required this.title,
    required this.body,
    required this.primaryLabel,
    this.secondaryLabel,
    this.onPrimary,
    this.onSecondary,
    this.tone = NotifyTone.brand,
    this.skin = NotifySkin.gradient,
    this.icon,
    this.thumbnail,
    this.compact = false,
  });

  final String title;
  final String body;
  final String primaryLabel;
  final String? secondaryLabel;
  final VoidCallback? onPrimary;
  final VoidCallback? onSecondary;
  final NotifyTone tone;
  final NotifySkin skin;
  final IconData? icon;

  /// A picture to lead with. Falls back to a large icon badge.
  final ImageProvider? thumbnail;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final palette = NotifyStyle.of(tone, Theme.of(context).brightness);
    final onColor = skin == NotifySkin.gradient;

    return NotifySurface(
      palette: palette,
      skin: skin,
      padding: NotifyStyle.padExpanded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (thumbnail != null)
                ClipRRect(
                  borderRadius: BorderRadius.circular(NotifyStyle.radiusSmall),
                  child: Image(
                    image: thumbnail!,
                    width: compact ? 48 : 62,
                    height: compact ? 48 : 62,
                    fit: BoxFit.cover,
                  ),
                )
              else
                NotifyIcon(
                  palette: palette,
                  icon: icon ?? NotifyStyle.iconFor(tone),
                  onColor: onColor,
                  size: compact ? 48 : 62,
                ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: NotifyStyle.title(
                        palette,
                        onColor: onColor,
                      ).copyWith(fontSize: 16),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      body,
                      maxLines: compact ? 2 : 3,
                      overflow: TextOverflow.ellipsis,
                      style: NotifyStyle.body(palette, onColor: onColor),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              if (secondaryLabel != null) ...[
                NotifyAction(
                  label: secondaryLabel!,
                  color: onColor ? palette.onColor : palette.body,
                  onTap: onSecondary ?? () {},
                ),
                const SizedBox(width: 10),
              ],
              NotifyAction(
                label: primaryLabel,
                color: onColor ? palette.onColor : palette.base,
                filled: !onColor,
                onTap: onPrimary ?? () {},
              ),
            ],
          ),
        ],
      ),
    );
  }
}
