import 'package:flutter/material.dart';

import '../../models/arrow_kind.dart';
import '../../services/ads_service.dart';
import '../../services/player_profile.dart';
import '../../theme/game_theme.dart';
import '../arrow_art.dart';

/// The special-arrow tray: a grid of the four specials, each showing the real
/// arrow it will put on the board. Pick one to place it, or buy one on the
/// spot. Returns the kind the player armed, or null if they backed out.
Future<ArrowKind?> showArrowPicker(BuildContext context) {
  return showModalBottomSheet<ArrowKind>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (context) => const _ArrowPicker(),
  );
}

class _ArrowPicker extends StatefulWidget {
  const _ArrowPicker();

  @override
  State<_ArrowPicker> createState() => _ArrowPickerState();
}

class _ArrowPickerState extends State<_ArrowPicker> {
  final _profile = PlayerProfile.instance;
  ArrowKind? _watching;

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: GameTheme.card,
          content: Text(
            message,
            style: GameTheme.font(
              color: GameTheme.ink,
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      );
  }

  Future<void> _buy(ArrowKind kind) async {
    if (!await _profile.spend(kind.price)) {
      _toast('Not enough coins — watch a video or top up in Rewards.');
      return;
    }
    await _profile.addArrows(kind, 1);
    if (mounted) setState(() {});
  }

  /// One free arrow for one video. This is the offer that pays for the game.
  Future<void> _watchFor(ArrowKind kind) async {
    if (_watching != null) return;
    setState(() => _watching = kind);
    final earned = await AdsService.instance.showRewarded();
    if (earned) await _profile.addArrows(kind, 1);
    if (!mounted) return;
    setState(() => _watching = null);
    _toast(
      earned
          ? '${kind.label} added. Tap an arrow to place it.'
          : 'No video available right now.',
    );
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    return Container(
      constraints: BoxConstraints(maxHeight: media.size.height * 0.86),
      decoration: BoxDecoration(
        color: GameTheme.card,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        border: Border.all(
          color: GameTheme.lilac.withValues(alpha: 0.45),
          width: 1.4,
        ),
      ),
      padding: EdgeInsets.fromLTRB(
        16,
        12,
        16,
        16 + media.viewPadding.bottom,
      ),
      child: ListenableBuilder(
        listenable: _profile,
        builder: (context, _) => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 42,
              height: 4,
              decoration: BoxDecoration(
                color: GameTheme.inkSoft.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Special arrows',
                    style: GameTheme.font(
                      color: GameTheme.ink,
                      fontSize: 17,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                Icon(
                  Icons.monetization_on_rounded,
                  color: GameTheme.coin,
                  size: 18,
                ),
                const SizedBox(width: 6),
                Text(
                  '${_profile.coins}',
                  style: GameTheme.font(
                    color: GameTheme.coin,
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Pick one, then tap any arrow on the board to turn it into that.',
                style: GameTheme.font(
                  color: GameTheme.inkSoft,
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            const SizedBox(height: 14),
            Flexible(
              child: GridView.count(
                shrinkWrap: true,
                crossAxisCount: 2,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 0.82,
                padding: EdgeInsets.zero,
                children: [
                  for (final kind in ArrowKind.buyable)
                    _ArrowCard(
                      kind: kind,
                      stock: _profile.stockOf(kind),
                      watching: _watching == kind,
                      busy: _watching != null,
                      adsOn: AdsService.instance.supported,
                      onUse: () => Navigator.pop(context, kind),
                      onBuy: () => _buy(kind),
                      onWatch: () => _watchFor(kind),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One tile: the arrow itself, what it does, and how to get it.
class _ArrowCard extends StatelessWidget {
  const _ArrowCard({
    required this.kind,
    required this.stock,
    required this.watching,
    required this.busy,
    required this.adsOn,
    required this.onUse,
    required this.onBuy,
    required this.onWatch,
  });

  final ArrowKind kind;
  final int stock;
  final bool watching;
  final bool busy;
  final bool adsOn;
  final VoidCallback onUse;
  final VoidCallback onBuy;
  final VoidCallback onWatch;

  @override
  Widget build(BuildContext context) {
    final owned = stock > 0;
    return Material(
      color: kind.tint.withValues(alpha: owned ? 0.15 : 0.06),
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: busy ? null : (owned ? onUse : onBuy),
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: kind.tint.withValues(alpha: owned ? 0.8 : 0.28),
              width: owned ? 1.7 : 1.1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // The real arrow, drawn by the same code the board uses.
              Stack(
                children: [
                  ArrowPreview(kind: kind, height: 50),
                  if (owned)
                    Positioned(
                      right: 0,
                      top: 0,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: kind.tint.withValues(alpha: 0.28),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          '×$stock',
                          style: GameTheme.font(
                            color: kind.tint,
                            fontSize: 11,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                kind.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GameTheme.font(
                  color: GameTheme.ink,
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 4),
              Expanded(
                child: Text(
                  kind.blurb,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: GameTheme.font(
                    color: GameTheme.inkSoft,
                    fontSize: 10,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              if (watching)
                const Center(
                  child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              else if (owned)
                _Action(
                  label: 'USE',
                  color: kind.tint,
                  filled: true,
                  onTap: busy ? null : onUse,
                )
              else
                Row(
                  children: [
                    if (adsOn) ...[
                      Expanded(
                        child: _Action(
                          label: 'FREE',
                          icon: Icons.play_arrow_rounded,
                          color: GameTheme.accent,
                          onTap: busy ? null : onWatch,
                        ),
                      ),
                      const SizedBox(width: 6),
                    ],
                    Expanded(
                      child: _Action(
                        label: '${kind.price}',
                        icon: Icons.monetization_on_rounded,
                        color: GameTheme.coin,
                        onTap: busy ? null : onBuy,
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Action extends StatelessWidget {
  const _Action({
    required this.label,
    required this.color,
    required this.onTap,
    this.icon,
    this.filled = false,
  });

  final String label;
  final Color color;
  final VoidCallback? onTap;
  final IconData? icon;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color.withValues(alpha: filled ? 0.9 : 0.18),
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(
                  icon,
                  color: filled ? Colors.white : color,
                  size: 13,
                ),
                const SizedBox(width: 4),
              ],
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GameTheme.font(
                    color: filled ? Colors.white : color,
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
