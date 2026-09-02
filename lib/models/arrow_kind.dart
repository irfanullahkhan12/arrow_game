import 'package:flutter/material.dart';

import '../theme/game_theme.dart';

/// The special arrows. A [normal] arrow obeys every rule; the other four each
/// break one, which is what makes them worth buying.
///
/// Every special fires even when it is blocked, and every special clears the
/// arrows it touches on its way out — they only differ in the path they take
/// and what "touched" means for them.
enum ArrowKind {
  /// Plays by the rules: only leaves when its exit ray is clear.
  normal,

  /// Ink-black with a golden halo. Flies straight out and drags every arrow
  /// sitting on its exit ray with it.
  boost,

  /// Colour-cycling. Flies to the edge of the board, runs a full lap around
  /// the boundary, then shoots out — clearing everything it passes over.
  rainbow,

  /// Pure white. Cuts three zigzags across the board before leaving, so it
  /// reaches arrows a straight line never could.
  ghost,

  /// Orange, fuse-lit. Flies straight out and detonates along its own body:
  /// every arrow within two cells of it goes with it.
  bomb;

  bool get isSpecial => this != ArrowKind.normal;

  /// Shown in the rewards sheet and the power bar.
  String get label => switch (this) {
    ArrowKind.normal => 'Arrow',
    ArrowKind.boost => 'Black arrow',
    ArrowKind.rainbow => 'Rainbow arrow',
    ArrowKind.ghost => 'Ghost arrow',
    ArrowKind.bomb => 'Bomb arrow',
  };

  String get blurb => switch (this) {
    ArrowKind.normal => 'An ordinary arrow.',
    ArrowKind.boost => 'Fires even when blocked, and clears its whole row',
    ArrowKind.rainbow => 'Laps the whole board edge, clearing everything on it',
    ArrowKind.ghost => 'Zigzags across the board, clearing all it touches',
    ArrowKind.bomb => 'Blows up everything within two cells of it',
  };

  /// Price in coins.
  int get price => switch (this) {
    ArrowKind.normal => 0,
    ArrowKind.boost => 150,
    ArrowKind.rainbow => 200,
    ArrowKind.ghost => 200,
    ArrowKind.bomb => 250,
  };

  IconData get icon => switch (this) {
    ArrowKind.normal => Icons.north_east_rounded,
    ArrowKind.boost => Icons.bolt_rounded,
    ArrowKind.rainbow => Icons.auto_awesome_rounded,
    ArrowKind.ghost => Icons.ac_unit_rounded,
    ArrowKind.bomb => Icons.local_fire_department_rounded,
  };

  /// The colour that represents this arrow in the UI (buttons, badges).
  Color get tint => switch (this) {
    ArrowKind.normal => GameTheme.lilac,
    ArrowKind.boost => GameTheme.gold,
    ArrowKind.rainbow => const Color(0xFF3ED7F0),
    ArrowKind.ghost => const Color(0xFFEAF4FF),
    ArrowKind.bomb => const Color(0xFFFF7A1A),
  };

  /// The key this arrow's stock is saved under.
  String get prefsKey => 'p_kind_$name';

  static ArrowKind fromName(String? name) {
    for (final k in values) {
      if (k.name == name) return k;
    }
    return ArrowKind.normal;
  }

  /// The specials the player can own and place, in shop order.
  static const buyable = [
    ArrowKind.boost,
    ArrowKind.rainbow,
    ArrowKind.ghost,
    ArrowKind.bomb,
  ];
}
