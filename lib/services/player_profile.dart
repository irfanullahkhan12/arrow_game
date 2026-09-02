import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/arrow_kind.dart';

/// Everything the player owns and every setting they have chosen, persisted in
/// shared preferences and shared with the HUD through [ChangeNotifier].
class PlayerProfile extends ChangeNotifier {
  PlayerProfile._();

  static final PlayerProfile instance = PlayerProfile._();

  static const _kCoins = 'p_coins';
  static const _kBoosts = 'p_boosts'; // legacy: black arrows only
  static const _kHints = 'p_hints';
  static const _kUndos = 'p_undos';
  static const _kBest = 'p_best_level';
  static const _kGames = 'p_games';
  static const _kStreak = 'p_streak';
  static const _kLastGift = 'p_last_gift';
  static const _kSound = 'sound_on';
  static const _kDark = 'dark_theme';

  /// Prices, in coins. Special arrows price themselves — see [ArrowKind].
  static const hintPrice = 60;
  static const undoPrice = 90;

  /// What one rewarded ad is worth.
  static const adCoins = 50;

  int coins = 0;

  /// How many of each special arrow are waiting to be placed.
  final Map<ArrowKind, int> arrows = {};

  int hints = 1;
  int undos = 1;
  int bestLevel = 1;
  int gamesPlayed = 0;
  int streak = 0; // consecutive days the daily gift was claimed
  String lastGiftDay = '';

  bool soundOn = true;
  bool dark = true;

  bool _loaded = false;
  bool get loaded => _loaded;

  int stockOf(ArrowKind kind) => arrows[kind] ?? 0;

  /// Total specials on hand, across every kind.
  int get totalArrows =>
      ArrowKind.buyable.fold(0, (sum, kind) => sum + stockOf(kind));

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    coins = prefs.getInt(_kCoins) ?? 100;
    for (final kind in ArrowKind.buyable) {
      arrows[kind] = prefs.getInt(kind.prefsKey) ?? 0;
    }
    // Carry over the stock saved before the other specials existed.
    final legacy = prefs.getInt(_kBoosts);
    if (legacy != null) {
      arrows[ArrowKind.boost] = (arrows[ArrowKind.boost] ?? 0) + legacy;
      await prefs.remove(_kBoosts);
    } else if (prefs.getInt(ArrowKind.boost.prefsKey) == null) {
      arrows[ArrowKind.boost] = 1; // one to try on a fresh install
    }
    hints = prefs.getInt(_kHints) ?? 3;
    undos = prefs.getInt(_kUndos) ?? 1;
    bestLevel = prefs.getInt(_kBest) ?? 1;
    gamesPlayed = prefs.getInt(_kGames) ?? 0;
    streak = prefs.getInt(_kStreak) ?? 0;
    lastGiftDay = prefs.getString(_kLastGift) ?? '';
    soundOn = prefs.getBool(_kSound) ?? true;
    dark = prefs.getBool(_kDark) ?? true;
    _loaded = true;
    notifyListeners();
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kCoins, coins);
    for (final kind in ArrowKind.buyable) {
      await prefs.setInt(kind.prefsKey, stockOf(kind));
    }
    await prefs.setInt(_kHints, hints);
    await prefs.setInt(_kUndos, undos);
    await prefs.setInt(_kBest, bestLevel);
    await prefs.setInt(_kGames, gamesPlayed);
    await prefs.setInt(_kStreak, streak);
    await prefs.setString(_kLastGift, lastGiftDay);
    await prefs.setBool(_kSound, soundOn);
    await prefs.setBool(_kDark, dark);
  }

  Future<void> _commit() async {
    notifyListeners();
    await _save();
  }

  // ── Currency ─────────────────────────────────────────────────────────────

  Future<void> addCoins(int amount) async {
    coins = math.max(0, coins + amount);
    await _commit();
  }

  bool canAfford(int price) => coins >= price;

  /// Spends [price] coins if the player has them.
  Future<bool> spend(int price) async {
    if (coins < price) return false;
    coins -= price;
    await _commit();
    return true;
  }

  // ── Special arrows ───────────────────────────────────────────────────────

  Future<void> addArrows(ArrowKind kind, int n) async {
    arrows[kind] = stockOf(kind) + n;
    await _commit();
  }

  Future<bool> useArrow(ArrowKind kind) async {
    if (stockOf(kind) <= 0) return false;
    arrows[kind] = stockOf(kind) - 1;
    await _commit();
    return true;
  }

  // ── Power-ups ────────────────────────────────────────────────────────────

  Future<void> addHints(int n) async {
    hints += n;
    await _commit();
  }

  Future<bool> useHint() async {
    if (hints <= 0) return false;
    hints--;
    await _commit();
    return true;
  }

  Future<void> addUndos(int n) async {
    undos += n;
    await _commit();
  }

  Future<bool> useUndo() async {
    if (undos <= 0) return false;
    undos--;
    await _commit();
    return true;
  }

  // ── Progress ─────────────────────────────────────────────────────────────

  Future<void> recordLevel(int level) async {
    gamesPlayed++;
    if (level > bestLevel) bestLevel = level;
    await _commit();
  }

  // ── Daily gift ───────────────────────────────────────────────────────────

  static String _dayKey(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  bool get canClaimGift => lastGiftDay != _dayKey(DateTime.now());

  /// Coins the next gift is worth — it grows with the streak, which is what
  /// makes coming back tomorrow worth something.
  int get giftCoins => math.min(60 + streak * 20, 200);

  /// Claims today's gift. Returns null if it was already taken today.
  Future<DailyGift?> claimGift() async {
    final now = DateTime.now();
    final today = _dayKey(now);
    if (lastGiftDay == today) return null;

    final yesterday = _dayKey(now.subtract(const Duration(days: 1)));
    streak = lastGiftDay == yesterday ? streak + 1 : 1;

    // Every third day hands over a special arrow, cycling through the set so
    // a returning player eventually meets all of them.
    final kind = streak % 3 == 0
        ? ArrowKind.buyable[(streak ~/ 3 - 1) % ArrowKind.buyable.length]
        : null;

    final gift = DailyGift(
      coins: math.min(60 + (streak - 1) * 20, 200),
      arrow: kind,
      hints: streak.isEven ? 1 : 0,
      streak: streak,
    );

    lastGiftDay = today;
    coins += gift.coins;
    if (kind != null) arrows[kind] = stockOf(kind) + 1;
    hints += gift.hints;
    await _commit();
    return gift;
  }

  // ── Settings ─────────────────────────────────────────────────────────────

  Future<void> setSound(bool on) async {
    soundOn = on;
    await _commit();
  }

  Future<void> setDark(bool on) async {
    dark = on;
    await _commit();
  }
}

class DailyGift {
  const DailyGift({
    required this.coins,
    required this.arrow,
    required this.hints,
    required this.streak,
  });

  final int coins;

  /// The special arrow in today's gift, if there is one.
  final ArrowKind? arrow;
  final int hints;
  final int streak;
}

/// One-line tips and arrow trivia, shown while a level is being built so the
/// loading moment teaches something instead of just spinning.
class GameFacts {
  static const tips = <String>[
    'Tip: clear the arrows blocking the edges first — they open the board.',
    'Tip: a long arrow needs a long runway. Check its whole path before tapping.',
    'Did you know? The oldest known arrowheads are over 60,000 years old.',
    'Tip: the black arrow fires even when blocked, and takes its whole row out.',
    'Tip: the rainbow arrow laps the entire board edge before it leaves.',
    'Tip: the ghost arrow zigzags, so it reaches arrows a straight shot cannot.',
    'Tip: the bomb arrow clears everything within two cells of it.',
    'Tip: pinch to zoom, drag to pan — the ⦿ button snaps the board back.',
    'Did you know? A modern compound bow launches an arrow at about 100 m/s.',
    'Tip: two arrows pointing at each other can never both leave. Move one aside.',
    'Tip: your daily gift grows every day you come back in a row.',
    'Did you know? Fletching — the feathers on an arrow — makes it spin for accuracy.',
    'Tip: stuck? A hint highlights an arrow that can fire right now.',
    'Did you know? "Toxophilite" is the proper word for an archery lover.',
    'Tip: the corner arrows usually have the clearest exit.',
  ];

  static String random([math.Random? rng]) =>
      tips[(rng ?? math.Random()).nextInt(tips.length)];
}
