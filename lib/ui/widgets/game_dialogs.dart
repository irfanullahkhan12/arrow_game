import 'package:flutter/material.dart';

import '../../models/arrow_kind.dart';
import '../../services/player_profile.dart';
import '../../theme/game_theme.dart';

/// What the player picked in one of the game dialogs.
enum GameChoice { next, newBoard, watchAd, restart, close }

/// The shell every dialog in the game shares: a glowing card with an emoji
/// badge, a title, a line of copy and a row of buttons.
class NeonDialog extends StatelessWidget {
  const NeonDialog({
    super.key,
    required this.badge,
    required this.title,
    required this.message,
    required this.actions,
    this.accent,
    this.extra,
  });

  final String badge;
  final String title;
  final String message;
  final List<Widget> actions;
  final Color? accent;
  final Widget? extra;

  @override
  Widget build(BuildContext context) {
    final tint = accent ?? GameTheme.accent;
    return Dialog(
      backgroundColor: GameTheme.card,
      elevation: 16,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(28),
        side: BorderSide(color: tint.withValues(alpha: 0.55), width: 1.6),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 30, 24, 22),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    tint.withValues(alpha: 0.45),
                    tint.withValues(alpha: 0.08),
                  ],
                ),
                boxShadow: [
                  BoxShadow(
                    color: tint.withValues(alpha: 0.35),
                    blurRadius: 26,
                  ),
                ],
              ),
              alignment: Alignment.center,
              child: Text(badge, style: const TextStyle(fontSize: 38)),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: GameTheme.font(
                color: tint,
                fontSize: 23,
                fontWeight: FontWeight.w900,
                letterSpacing: 0.6,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: GameTheme.font(
                color: GameTheme.inkSoft,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
            if (extra != null) ...[const SizedBox(height: 16), extra!],
            const SizedBox(height: 24),
            ...actions,
          ],
        ),
      ),
    );
  }
}

/// A filled neon button — the primary action of a dialog.
class NeonButton extends StatelessWidget {
  const NeonButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.color,
    this.outlined = false,
  });

  final String label;
  final VoidCallback onPressed;
  final IconData? icon;
  final Color? color;
  final bool outlined;

  @override
  Widget build(BuildContext context) {
    final tint = color ?? GameTheme.accent;
    final child = Row(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[Icon(icon, size: 17), const SizedBox(width: 8)],
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GameTheme.font(fontWeight: FontWeight.w800, fontSize: 13.5),
          ),
        ),
      ],
    );

    if (outlined) {
      return OutlinedButton(
        style: OutlinedButton.styleFrom(
          foregroundColor: tint,
          side: BorderSide(color: tint.withValues(alpha: 0.6), width: 1.5),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 22),
        ),
        onPressed: onPressed,
        child: child,
      );
    }
    return FilledButton(
      style: FilledButton.styleFrom(
        backgroundColor: tint,
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 22),
      ),
      onPressed: onPressed,
      child: child,
    );
  }
}

// ─── The dialogs ─────────────────────────────────────────────────────────────

/// Level cleared: shows the coins earned and offers the next level.
Future<GameChoice?> showWinDialog(
  BuildContext context, {
  required int level,
  required int coinsEarned,
  required int lifeBonus,
}) {
  return showDialog<GameChoice>(
    context: context,
    barrierDismissible: false,
    barrierColor: Colors.black.withValues(alpha: 0.55),
    builder: (context) => NeonDialog(
      badge: '🎉',
      title: 'Level $level Clear!',
      message: 'Every arrow found its way out.',
      accent: GameTheme.accentDeep,
      extra: Column(
        children: [
          _RewardRow(
            icon: Icons.monetization_on_rounded,
            color: GameTheme.coin,
            label: 'Level reward',
            value: '+${coinsEarned - lifeBonus}',
          ),
          if (lifeBonus > 0)
            _RewardRow(
              icon: Icons.favorite_rounded,
              color: GameTheme.heart,
              label: 'Lives left bonus',
              value: '+$lifeBonus',
            ),
        ],
      ),
      actions: [
        SizedBox(
          width: double.infinity,
          child: NeonButton(
            label: 'Next Level',
            icon: Icons.play_arrow_rounded,
            onPressed: () => Navigator.pop(context, GameChoice.next),
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          child: NeonButton(
            label: 'Replay this level',
            outlined: true,
            color: GameTheme.lilac,
            onPressed: () => Navigator.pop(context, GameChoice.newBoard),
          ),
        ),
      ],
    ),
  );
}

/// Out of lives: the ad here is the player's own choice, and it saves their
/// board — the single best-converting placement in a puzzle game.
Future<GameChoice?> showOutOfLivesDialog(
  BuildContext context, {
  required bool adReady,
}) {
  return showDialog<GameChoice>(
    context: context,
    barrierDismissible: false,
    barrierColor: Colors.black.withValues(alpha: 0.6),
    builder: (context) => NeonDialog(
      badge: '💔',
      title: 'Out of Lives',
      message: adReady
          ? 'Watch a short video to get 3 more lives and keep this board.'
          : 'No video available right now — start the board again.',
      accent: GameTheme.heart,
      actions: [
        if (adReady) ...[
          SizedBox(
            width: double.infinity,
            child: NeonButton(
              label: 'Watch & get 3 lives',
              icon: Icons.play_circle_fill_rounded,
              color: GameTheme.heart,
              onPressed: () => Navigator.pop(context, GameChoice.watchAd),
            ),
          ),
          const SizedBox(height: 10),
        ],
        SizedBox(
          width: double.infinity,
          child: NeonButton(
            label: 'Restart board',
            outlined: true,
            color: GameTheme.lilac,
            onPressed: () => Navigator.pop(context, GameChoice.restart),
          ),
        ),
      ],
    ),
  );
}

/// The daily gift, which grows with the streak.
Future<void> showDailyGiftDialog(BuildContext context, DailyGift gift) {
  return showDialog<void>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.55),
    builder: (context) => NeonDialog(
      badge: '🎁',
      title: 'Day ${gift.streak} Gift',
      message: gift.streak > 1
          ? 'Come back tomorrow — day ${gift.streak + 1} pays even more.'
          : 'Play every day and the gift keeps growing.',
      accent: GameTheme.gold,
      extra: Column(
        children: [
          _RewardRow(
            icon: Icons.monetization_on_rounded,
            color: GameTheme.coin,
            label: 'Coins',
            value: '+${gift.coins}',
          ),
          if (gift.arrow case final ArrowKind kind)
            _RewardRow(
              icon: kind.icon,
              color: kind.tint,
              label: kind.label,
              value: '+1',
            ),
          if (gift.hints > 0)
            _RewardRow(
              icon: Icons.lightbulb_rounded,
              color: GameTheme.lilac,
              label: 'Hints',
              value: '+${gift.hints}',
            ),
        ],
      ),
      actions: [
        SizedBox(
          width: double.infinity,
          child: NeonButton(
            label: 'Collect',
            icon: Icons.check_rounded,
            color: GameTheme.gold,
            onPressed: () => Navigator.pop(context),
          ),
        ),
      ],
    ),
  );
}

class _RewardRow extends StatelessWidget {
  const _RewardRow({
    required this.icon,
    required this.color,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final Color color;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Icon(icon, color: color, size: 17),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: GameTheme.font(
                color: GameTheme.inkSoft,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Text(
            value,
            style: GameTheme.font(
              color: color,
              fontSize: 13,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}
