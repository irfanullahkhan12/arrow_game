/// Offline "level designer": each board is carved under one of these styles,
/// which bias the direction the arrows like to flow in. No network, no API —
/// endless variety for free, and the peeling carver still guarantees every
/// board is fully packed and solvable.
enum BoardStyle {
  freeform('Tangle'),
  waves('Waves'),
  pillars('Pillars'),
  spiral('Spiral'),
  stairs('Stairs'),
  zigzag('Zigzag'), // bends at nearly every cell
  serpent('Serpent'); // long winding runs with hairpin turns

  const BoardStyle(this.label);

  final String label;

  /// How much this style likes stepping [d] from cell ([x], [y]). Higher wins.
  /// Pure preference — the backtracking carver overrides it when it must.
  double score((int, int) d, int x, int y, int columns, int rows) {
    switch (this) {
      case BoardStyle.freeform:
      case BoardStyle.zigzag:
      case BoardStyle.serpent:
        return 0; // these flow from turnScore, not position
      case BoardStyle.waves:
        if (d.$2 != 0) return 0;
        return (y.isEven ? d.$1 : -d.$1).toDouble();
      case BoardStyle.pillars:
        if (d.$1 != 0) return 0;
        return (x.isEven ? d.$2 : -d.$2).toDouble();
      case BoardStyle.spiral:
        final cx = x - (columns - 1) / 2.0;
        final cy = y - (rows - 1) / 2.0;
        return (-cy * d.$1 + cx * d.$2) / (cx.abs() + cy.abs() + 1);
      case BoardStyle.stairs:
        return ((x + y).isEven ? (d.$1 - d.$2) : (d.$2 - d.$1)).toDouble();
    }
  }

  /// Bonus for turning vs going straight: zigzag loves bends, serpent loves
  /// long straight runs, freeform likes a gentle curl.
  double turnScore(bool isTurn) {
    switch (this) {
      case BoardStyle.zigzag:
        return isTurn ? 1.8 : -1.2;
      case BoardStyle.serpent:
        return isTurn ? -1.4 : 2.2;
      case BoardStyle.freeform:
        return isTurn ? 0.5 : 0;
      case BoardStyle.waves:
      case BoardStyle.pillars:
      case BoardStyle.spiral:
      case BoardStyle.stairs:
        return 0;
    }
  }

  /// How eagerly this style ends an arrow once it may — lower means longer
  /// arrows on average. Every style now leans long: the board should read as
  /// big chunky arrows, not a field of stubs.
  double get stopChance {
    switch (this) {
      case BoardStyle.serpent:
        return 0.03;
      case BoardStyle.zigzag:
        return 0.09;
      case BoardStyle.freeform:
        return 0.10;
      case BoardStyle.waves:
      case BoardStyle.pillars:
      case BoardStyle.spiral:
      case BoardStyle.stairs:
        return 0.06;
    }
  }
}
