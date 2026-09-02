import 'package:flutter/material.dart';

import '../../models/arrow_kind.dart';
import '../../services/ads_service.dart';
import '../../services/iap_service.dart';
import '../../services/player_profile.dart';
import '../../theme/game_theme.dart';

/// The rewards sheet: every way to earn or spend, in one place.
///
/// Built for a young player: big glowing icons, three words at most on any
/// card, and the free-video row first because it is opt-in, it is the highest
/// paying format in the game, and it is what a child can actually afford.
/// Special arrows are not repeated here — they have their own tray, reached
/// from the Specials button.
Future<void> showShopSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (context) => const _ShopSheet(),
  );
}

class _ShopSheet extends StatefulWidget {
  const _ShopSheet();

  @override
  State<_ShopSheet> createState() => _ShopSheetState();
}

class _ShopSheetState extends State<_ShopSheet> {
  final _profile = PlayerProfile.instance;
  final _store = IapService.instance;

  /// Which free card is playing a video, if any.
  String? _watching;

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

  Future<void> _watchFor(String what) async {
    if (_watching != null) return;
    setState(() => _watching = what);
    final earned = await AdsService.instance.showRewarded();
    if (earned) {
      switch (what) {
        case 'coins':
          await _profile.addCoins(PlayerProfile.adCoins);
        case 'arrow':
          await _profile.addArrows(ArrowKind.boost, 1);
        case 'hint':
          await _profile.addHints(1);
      }
    }
    if (!mounted) return;
    setState(() => _watching = null);
    _toast(earned ? 'Reward added. Thanks!' : 'No video available right now.');
  }

  Future<void> _buy(int price, Future<void> Function() give) async {
    if (!await _profile.spend(price)) {
      _toast('Not enough coins — watch a video to top up.');
      return;
    }
    await give();
    if (mounted) setState(() {});
  }

  /// One place decides what to say about a purchase, so a cancel never reads
  /// like a failure and a failure never passes silently.
  Future<void> _purchase(
    Future<PurchaseOutcome> Function() run,
    String success,
  ) async {
    if (_store.busy) return;
    final outcome = await run();
    if (!mounted) return;
    setState(() {});
    switch (outcome) {
      case PurchaseOutcome.success:
        _toast(success);
      case PurchaseOutcome.cancelled:
        break; // the player closed the sheet themselves
      case PurchaseOutcome.failed:
        _toast('That did not go through. Nothing was charged.');
      case PurchaseOutcome.unavailable:
        _toast('The store is not available in this build.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final adsOn = AdsService.instance.supported;

    return Container(
      constraints: BoxConstraints(maxHeight: media.size.height * 0.9),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [GameTheme.card, GameTheme.bgTop],
        ),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
        border: Border.all(
          color: GameTheme.accent.withValues(alpha: 0.5),
          width: 1.6,
        ),
      ),
      child: ListenableBuilder(
        listenable: Listenable.merge([_profile, _store]),
        builder: (context, _) => SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(16, 10, 16, 18 + media.viewPadding.bottom),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 46,
                height: 5,
                decoration: BoxDecoration(
                  color: GameTheme.inkSoft.withValues(alpha: 0.45),
                  borderRadius: BorderRadius.circular(5),
                ),
              ),
              const SizedBox(height: 16),
              _Header(coins: _profile.coins),

              if (adsOn) ...[
                const _SectionLabel('🎬  FREE'),
                Row(
                  spacing: 10,
                  children: [
                    _FreeCard(
                      icon: Icons.bolt_rounded,
                      color: GameTheme.gold,
                      label: 'Arrow',
                      busy: _watching == 'arrow',
                      disabled: _watching != null,
                      onTap: () => _watchFor('arrow'),
                    ),
                    _FreeCard(
                      icon: Icons.monetization_on_rounded,
                      color: GameTheme.coin,
                      label: '+${PlayerProfile.adCoins}',
                      busy: _watching == 'coins',
                      disabled: _watching != null,
                      onTap: () => _watchFor('coins'),
                    ),
                    _FreeCard(
                      icon: Icons.lightbulb_rounded,
                      color: GameTheme.lilac,
                      label: 'Hint',
                      busy: _watching == 'hint',
                      disabled: _watching != null,
                      onTap: () => _watchFor('hint'),
                    ),
                  ],
                ),
              ],

              const _SectionLabel('🪙  SPEND'),
              Row(
                spacing: 12,
                children: [
                  _ShopTile(
                    icon: Icons.lightbulb_rounded,
                    color: GameTheme.lilac,
                    label: 'Hint',
                    owned: _profile.hints,
                    price: PlayerProfile.hintPrice,
                    onTap: () => _buy(
                      PlayerProfile.hintPrice,
                      () => _profile.addHints(1),
                    ),
                  ),
                  _ShopTile(
                    icon: Icons.undo_rounded,
                    color: GameTheme.accent,
                    label: 'Undo',
                    owned: _profile.undos,
                    price: PlayerProfile.undoPrice,
                    onTap: () => _buy(
                      PlayerProfile.undoPrice,
                      () => _profile.addUndos(1),
                    ),
                  ),
                ],
              ),

              const _SectionLabel('💎  STORE'),
              if (_store.adsRemoved)
                _StoreCard(
                  icon: Icons.verified_rounded,
                  color: GameTheme.lilac,
                  label: 'Ad-free',
                  action: 'OWNED',
                  onTap: null,
                )
              else
                _StoreCard(
                  icon: Icons.block_rounded,
                  color: GameTheme.lilac,
                  label: 'No Ads',
                  action: _store.priceOf(IapService.removeAdsId),
                  busy: _store.busy,
                  onTap: () => _purchase(
                    _store.buyRemoveAds,
                    'Ads are gone. Enjoy the quiet.',
                  ),
                ),
              const SizedBox(height: 10),
              _StoreCard(
                icon: Icons.savings_rounded,
                color: GameTheme.coin,
                label: '${IapService.coinPackAmount} Coins',
                action: _store.priceOf(IapService.coinPackId),
                busy: _store.busy,
                onTap: () => _purchase(
                  _store.buyCoinPack,
                  '+${IapService.coinPackAmount} coins added.',
                ),
              ),
              TextButton(
                onPressed: _store.busy
                    ? null
                    : () => _purchase(_store.restore, 'Purchases restored.'),
                child: Text(
                  'Restore',
                  style: GameTheme.font(
                    color: GameTheme.inkSoft,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
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

// ─── Pieces ──────────────────────────────────────────────────────────────────

class _Header extends StatelessWidget {
  const _Header({required this.coins});

  final int coins;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Text('🎁', style: TextStyle(fontSize: 30)),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            'Rewards',
            style: GameTheme.font(
              color: GameTheme.ink,
              fontSize: 24,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: GameTheme.coin.withValues(alpha: 0.16),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: GameTheme.coin.withValues(alpha: 0.55),
              width: 1.4,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.monetization_on_rounded,
                color: GameTheme.coin,
                size: 22,
              ),
              const SizedBox(width: 7),
              Text(
                '$coins',
                style: GameTheme.font(
                  color: GameTheme.coin,
                  fontSize: 19,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 22, 2, 12),
      child: Row(
        children: [
          Text(
            text,
            style: GameTheme.font(
              color: GameTheme.inkSoft,
              fontSize: 12,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.6,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Divider(
              color: GameTheme.inkSoft.withValues(alpha: 0.22),
              height: 1,
            ),
          ),
        ],
      ),
    );
  }
}

/// A big glowing disc — the thing a young player actually reads.
class _IconBadge extends StatelessWidget {
  const _IconBadge({
    required this.icon,
    required this.color,
    this.size = 58,
  });

  final IconData icon;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [
            color.withValues(alpha: 0.38),
            color.withValues(alpha: 0.08),
          ],
        ),
        border: Border.all(color: color.withValues(alpha: 0.6), width: 1.8),
        boxShadow: [
          BoxShadow(color: color.withValues(alpha: 0.35), blurRadius: 20),
        ],
      ),
      child: Icon(icon, color: color, size: size * 0.48),
    );
  }
}

/// One of the three "watch a video" cards.
class _FreeCard extends StatelessWidget {
  const _FreeCard({
    required this.icon,
    required this.color,
    required this.label,
    required this.onTap,
    this.busy = false,
    this.disabled = false,
  });

  final IconData icon;
  final Color color;
  final String label;
  final VoidCallback onTap;
  final bool busy;
  final bool disabled;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Opacity(
        opacity: disabled && !busy ? 0.5 : 1,
        child: Material(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(22),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: disabled ? null : onTap,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(22),
                border: Border.all(
                  color: color.withValues(alpha: 0.35),
                  width: 1.2,
                ),
              ),
              child: Column(
                children: [
                  if (busy)
                    SizedBox(
                      width: 58,
                      height: 58,
                      child: Center(
                        child: SizedBox(
                          width: 26,
                          height: 26,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.6,
                            color: color,
                          ),
                        ),
                      ),
                    )
                  else
                    _IconBadge(icon: icon, color: color),
                  const SizedBox(height: 10),
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GameTheme.font(
                      color: GameTheme.ink,
                      fontSize: 13,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: GameTheme.accent,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.play_arrow_rounded,
                          color: Colors.white,
                          size: 15,
                        ),
                        Text(
                          'FREE',
                          style: GameTheme.font(
                            color: Colors.white,
                            fontSize: 10.5,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A power-up you buy with coins.
class _ShopTile extends StatelessWidget {
  const _ShopTile({
    required this.icon,
    required this.color,
    required this.label,
    required this.owned,
    required this.price,
    required this.onTap,
  });

  final IconData icon;
  final Color color;
  final String label;
  final int owned;
  final int price;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Material(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(22),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.fromLTRB(12, 14, 12, 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(22),
              border: Border.all(
                color: color.withValues(alpha: 0.35),
                width: 1.2,
              ),
            ),
            child: Row(
              children: [
                _IconBadge(icon: icon, color: color, size: 50),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GameTheme.font(
                                color: GameTheme.ink,
                                fontSize: 14,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                          if (owned > 0) ...[
                            const SizedBox(width: 5),
                            Text(
                              '×$owned',
                              style: GameTheme.font(
                                color: color,
                                fontSize: 12,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 7),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 9,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: GameTheme.coin.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.monetization_on_rounded,
                              color: GameTheme.coin,
                              size: 14,
                            ),
                            const SizedBox(width: 4),
                            // The number gives way on a narrow phone rather
                            // than pushing the chip past the tile edge.
                            Flexible(
                              child: Text(
                                '$price',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: GameTheme.font(
                                  color: GameTheme.coin,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A real-money product: big icon, two words, one price button.
class _StoreCard extends StatelessWidget {
  const _StoreCard({
    required this.icon,
    required this.color,
    required this.label,
    required this.action,
    required this.onTap,
    this.busy = false,
  });

  final IconData icon;
  final Color color;
  final String label;
  final String action;
  final VoidCallback? onTap;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color.withValues(alpha: 0.13),
      borderRadius: BorderRadius.circular(24),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: busy ? null : onTap,
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: color.withValues(alpha: 0.45),
              width: 1.4,
            ),
          ),
          child: Row(
            children: [
              _IconBadge(icon: icon, color: color, size: 54),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GameTheme.font(
                    color: GameTheme.ink,
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              if (busy)
                const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2.4),
                )
              else
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: onTap == null
                        ? color.withValues(alpha: 0.25)
                        : color,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: onTap == null
                        ? null
                        : [
                            BoxShadow(
                              color: color.withValues(alpha: 0.45),
                              blurRadius: 14,
                              offset: const Offset(0, 4),
                            ),
                          ],
                  ),
                  child: Text(
                    action,
                    style: GameTheme.font(
                      color: onTap == null ? color : Colors.white,
                      fontSize: 13.5,
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
