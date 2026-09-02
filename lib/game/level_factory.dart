import 'dart:math' as math;
import 'dart:ui';

import '../models/arrow_kind.dart';
import '../models/arrow_piece.dart';
import '../models/board_data.dart';
import '../models/board_shape.dart';
import '../models/board_style.dart';
import '../models/palette.dart';
import '../models/silhouette.dart';
import 'ai_designer.dart';

/// Builds boards: the grid is sized to fit the level's arrows, the silhouette
/// and flow style rotate per level, and every board is provably fully-packed
/// and solvable. Pure and static so the home-widget background isolate can use
/// it too.
///
/// The carver works *backwards from the solution*: it repeatedly peels an
/// arrow off the board whose exit ray is already clear, which makes every
/// board solvable by construction — there is no "generate, then test, then
/// throw it away" loop that could spin for half a minute on an unlucky level.
class LevelFactory {
  static const minLen = 3; // hard floor — no stubbier than this
  static const softMinLen = 5; // preferred floor: keeps small arrows rare
  static const maxLen = 11; // long snakes allowed — mixed with medium ones

  /// Wall-clock ceiling for one board. Nothing here may ever hang the game:
  /// when the clock runs out, the constructive fallback takes over. Boards are
  /// built once per level, off the UI thread, behind the loader — so this can
  /// afford to be generous, and on the harder levels it is spent hunting for a
  /// board with as few opening moves as possible.
  static const _deadlineMs = 2200;

  static const _steps = <(int, int)>[(1, 0), (-1, 0), (0, 1), (0, -1)];

  static int _key(Offset cell, int columns) =>
      cell.dy.toInt() * columns + cell.dx.toInt();

  /// How many arrows level [level] holds: two per level, so level 14 is a
  /// 28-arrow board and level 50 a 100-arrow one. The silhouette grows with
  /// the count, and the fit button is what keeps a big board on screen.
  static int arrowCount(int level) => math.max(1, level) * 2;

  /// Board cells per arrow. Arrows average just under six cells, so this is
  /// really a slack setting: early boards get room to breathe, later ones are cut
  /// barely bigger than the arrows that have to fill them. Every gap is
  /// somewhere an arrow could have slipped through, so fewer gaps is harder.
  static double density(int level) {
    const roomy = 6.5;
    const packed = 6.05;
    final t = ((level - 1) / 22).clamp(0.0, 1.0);
    return roomy + (packed - roomy) * t;
  }

  /// The difficulty dial, and it swings both ways.
  ///
  /// Negative on the first levels: the generator is asked for boards with
  /// *plenty* of opening moves, so a new player can tap almost anything and
  /// see it fly. It crosses zero around level six and reaches full weight at
  /// twenty, where boards are chosen for having as few legal moves at a time
  /// as the generator can manage.
  static double difficultyWeight(int level) {
    final t = ((level - 1) / 19).clamp(0.0, 1.0);
    return -0.4 + 1.4 * t;
  }

  /// The one entry point: a solvable, fully-packed board for [level].
  static BoardData generate({
    required int level,
    required int generation,
    required int cleared,
    AiDesign? design,
  }) {
    final n = arrowCount(level);
    final seed = 7000 + level * 1013 + generation * 17;
    final rng = math.Random(seed);
    final clock = Stopwatch()..start();

    final style = BoardStyle.values[rng.nextInt(BoardStyle.values.length)];
    final palette =
        design?.palette ??
        (level <= 2 ? Palette.candy : Palette.generate(seed));

    // Outlines to try, best first: whatever the online designer drew, then
    // the built-in shape whose turn it is, then the one after that, then a
    // plain rectangle. Tiny early boards stay rectangular — a star needs room
    // to read as a star.
    final outlines = <Silhouette>[
      if (n >= 10) ...[
        if (design?.silhouette case final Silhouette drawn) drawn,
        _rotateShape(level),
        _rotateShape(level + 1),
      ],
      const PresetSilhouette(BoardShape.rectangle),
    ];

    // Each outline gets a slice of the clock. Masks are built lazily: sizing
    // an outline means testing every cell of every candidate grid against it,
    // so there is no point doing that for a shape we never reach.
    for (var m = 0; m < outlines.length; m++) {
      final outline = outlines[m];
      // The first outline is the one we actually want, so it gets most of the
      // clock; the rest share what is left as fallbacks.
      final maskDeadline = m == 0
          ? (_deadlineMs * 0.65).round()
          : (_deadlineMs * (0.65 + 0.35 * m / (outlines.length - 1))).round();
      if (clock.elapsedMilliseconds >= maskDeadline) continue;

      final mask = _buildMask(outline, n, rng, density(level));
      if (mask == null) continue;

      // The carver is greedy and takes a millisecond or two, so instead of
      // taking the first board that works we cut as many as the clock allows
      // and keep the best: well covered, few stubby arrows, and — on the
      // harder levels — as few opening moves as possible.
      List<List<Offset>>? best;
      var bestScore = double.negativeInfinity;
      final tighten = difficultyWeight(level);
      var attempt = 0;
      // One scratch buffer for the whole search — the ray sweep runs once per
      // arrow, and allocating a fresh grid each time was the hot spot.
      final rays = List<bool>.filled(mask.columns * mask.rows * 4, false);
      while (attempt < 200 && clock.elapsedMilliseconds < maskDeadline) {
        final ordered = _carveArrows(
          mask,
          n,
          math.Random(seed + attempt * 7919),
          attempt.isEven ? style : BoardStyle.freeform,
          rays,
          tighten,
        );
        attempt++;
        if (ordered == null) continue;

        var covered = 0;
        var stubs = 0;
        for (final path in ordered) {
          covered += path.length;
          if (path.length < softMinLen) stubs++;
        }
        // A board is hard when the player rarely has a choice. Among the
        // boards that fill the outline well, take the one that offers the
        // fewest opening moves.
        final openness = tighten == 0
            ? 0.0
            : _openness(ordered, mask.columns, mask.rows, rays);
        final score = covered * 3.0 - stubs * 6.0 - openness * 900 * tighten;
        if (score > bestScore) {
          bestScore = score;
          best = ordered;
        }
      }

      if (best != null) {
        final pieces = _assignColors(best, mask.columns, palette.length);
        _markSpecial(pieces, level);
        return BoardData(
          level: level,
          generation: generation,
          cleared: cleared,
          columns: mask.columns,
          rows: mask.rows,
          silhouette: outline,
          mask: mask.cells,
          pieces: pieces,
          palette: palette,
        );
      }
    }

    return _fallbackBoard(
      level: level,
      generation: generation,
      cleared: cleared,
      n: n,
      palette: palette,
      rng: math.Random(seed),
    );
  }

  /// Walks the whole built-in set, one shape per level, so a player sees
  /// twenty-four different boards before anything repeats. This is the
  /// fallback path — when the online designer is reachable it draws its own.
  static Silhouette _rotateShape(int level) {
    final shapes = BoardShape.shaped;
    return PresetSilhouette(shapes[(level - 1) % shapes.length]);
  }

  /// Roughly every 2–3 levels one arrow is dealt as a special (levels 2, 5, 7,
  /// 10, 12, …). Which special it is depends on the level: the black arrow
  /// from the start, then the rainbow, ghost and bomb as the boards get big
  /// enough for them to be worth having. Deterministic, so the app and the
  /// home-widget isolate always agree on which arrow it is.
  static void _markSpecial(List<ArrowPiece> pieces, int level) {
    if (pieces.length < 2) return;
    if (level % 5 != 0 && level % 5 != 2) return;
    final rng = math.Random(level * 7331);
    final pool = <ArrowKind>[
      ArrowKind.boost,
      if (level >= 12) ArrowKind.rainbow,
      if (level >= 18) ArrowKind.ghost,
      if (level >= 25) ArrowKind.bomb,
    ];
    pieces[rng.nextInt(pieces.length)].kind = pool[rng.nextInt(pool.length)];
  }

  // ── Mask building ─────────────────────────────────────────────────────────

  /// Scales the silhouette until its cell count fits N arrows of the level's
  /// [cellsPerArrow] density — see [density].
  static _Mask? _buildMask(
    Silhouette outline,
    int n,
    math.Random rng,
    double cellsPerArrow,
  ) {
    final targetArea = (n * cellsPerArrow).round().clamp(
      n * minLen,
      n * maxLen,
    );

    if (outline.isRectangle) {
      // Phone-ish aspect. Tiny levels get tiny boards.
      var rows = math.max(2, math.sqrt(targetArea / 0.72).round());
      var columns = math.max(n == 1 ? 1 : 2, (targetArea / rows).round());
      while (columns * rows > n * maxLen) {
        if (rows >= columns) {
          rows--;
        } else {
          columns--;
        }
      }
      while (columns * rows < n * minLen) {
        rows++;
      }
      return _Mask(columns, rows, {for (var i = 0; i < columns * rows; i++) i});
    }

    // Grow the silhouette until enough cells fall inside it. Outlines cover
    // roughly two thirds of their bounding box, so start the scan just under
    // the size that implies rather than from a 5-row grid.
    _Mask? best;
    var bestScore = 1 << 30;
    final firstRows = math.max(5, (math.sqrt(targetArea / 0.95) * 0.72).floor());
    for (var rows = firstRows; rows <= 80; rows++) {
      final columns = math.max(4, (rows * 0.95).round());
      final cells = <int>{};
      for (var y = 0; y < rows; y++) {
        for (var x = 0; x < columns; x++) {
          final nx = (x + 0.5) / columns * 2 - 1;
          final ny = (y + 0.5) / rows * 2 - 1;
          if (outline.contains(nx, ny)) cells.add(y * columns + x);
        }
      }
      final area = cells.length;
      if (area < n * minLen) continue;
      if (area > n * maxLen) break;
      final mask = _Mask(columns, rows, cells);
      if (!mask.isUsable(minLen)) continue;
      final score = (area - targetArea).abs();
      if (score < bestScore) {
        bestScore = score;
        best = mask;
      }
    }
    return best;
  }

  // ── Carving (backwards from the solution) ────────────────────────────────

  /// Cuts [n] oriented arrows out of [mask], in the order they will be peeled
  /// off: each arrow's exit ray is clear of every arrow still on the board at
  /// the moment it is picked, which is exactly the game's win condition. The
  /// board is therefore solvable by construction — no generate-then-test loop
  /// that can spin for half a minute on an unlucky level.
  ///
  /// The silhouette is cut a little larger than the arrows need, so the carver
  /// is free to leave a few gaps rather than having to tile the mask exactly.
  /// That is what keeps it fast, and it is also what the board is supposed to
  /// look like: chunky arrows with breathing room between them.
  static List<List<Offset>>? _carveArrows(
    _Mask mask,
    int n,
    math.Random random,
    BoardStyle style,
    List<bool> rays,
    double tighten,
  ) {
    final w = mask.columns;
    final h = mask.rows;
    final total = w * h;

    final present = List<bool>.filled(total, false);
    for (final i in mask.cells) {
      present[i] = true;
    }
    var remaining = mask.cells.length;

    final arrows = <List<int>>[];
    while (arrows.length < n) {
      final left = n - arrows.length;
      final headroom = math.min(maxLen, remaining - (left - 1) * minLen);
      if (headroom < minLen) return null;

      _exposedRays(present, w, h, rays);
      final heads = <(int, (int, int))>[];
      for (var i = 0; i < total; i++) {
        if (!present[i]) continue;
        final x = i % w;
        final y = i ~/ w;
        for (var di = 0; di < 4; di++) {
          if (!rays[i * 4 + di]) continue;
          final d = _steps[di];
          // The cell behind the head has to exist, or there is no shaft.
          final bx = x - d.$1;
          final by = y - d.$2;
          if (bx < 0 || by < 0 || bx >= w || by >= h) continue;
          if (!present[by * w + bx]) continue;
          heads.add((i, d));
        }
      }
      if (heads.isEmpty) return null;
      heads.shuffle(random);

      // The difficulty knob.
      //
      // An arrow whose head sits on the rim fires on turn one: its ray is
      // already outside the board. An arrow deeper in only fires once the
      // arrows in front of it have gone, because at the start their cells are
      // standing in its way. So on the harder levels, pick the deepest head
      // available — the one that exits down the channel earlier arrows left
      // behind — and the board turns into a chain of forced moves instead of
      // a field of free ones.
      if (tighten != 0) {
        final depth = <int, double>{};
        for (var i = 0; i < heads.length; i++) {
          final (cell, d) = heads[i];
          final x = cell % w;
          final y = cell ~/ w;
          final steps = switch (d) {
            (1, 0) => w - 1 - x,
            (-1, 0) => x,
            (0, 1) => h - 1 - y,
            _ => y,
          };
          depth[i] = math.min(steps, 12) * 1.4 * tighten + random.nextDouble();
        }
        final order = List.generate(heads.length, (i) => i)
          ..sort((a, b) => depth[b]!.compareTo(depth[a]!));
        final sorted = [for (final i in order) heads[i]];
        heads
          ..clear()
          ..addAll(sorted);
      }

      final desired = _sampleLength(random).clamp(minLen, headroom);

      List<int>? chosen;
      for (var t = 0; t < math.min(heads.length, 12); t++) {
        final (head, d) = heads[t];
        final path = _growPath(head, d, desired, present, w, h, style, random);
        if (path != null) {
          chosen = path;
          break;
        }
      }
      if (chosen == null) return null;

      for (final cell in chosen) {
        present[cell] = false;
        remaining--;
      }
      // Stored tail → head, which is the order the game reads.
      arrows.add(chosen.reversed.toList());
    }

    return [
      for (final path in arrows)
        [for (final i in path) Offset((i % w).toDouble(), (i ~/ w).toDouble())],
    ];
  }

  /// Arrow lengths, weighted: mostly medium-to-long, three-cell stubs rare.
  static const _lengthWeights = <int>[2, 7, 9, 7, 5, 3, 2, 1, 1]; // 3..11

  static int _sampleLength(math.Random random) {
    var total = 0;
    for (final weight in _lengthWeights) {
      total += weight;
    }
    var roll = random.nextInt(total);
    for (var i = 0; i < _lengthWeights.length; i++) {
      roll -= _lengthWeights[i];
      if (roll < 0) return minLen + i;
    }
    return maxLen;
  }

  /// For every cell and every direction, is the exit ray already clear of the
  /// arrows still on the board? Four running sweeps, so this costs one pass
  /// over the grid instead of walking every ray separately. Writes into the
  /// caller's [clear] buffer: this runs once per arrow, and allocating a fresh
  /// grid every time dominated the carver's cost on the big boards.
  static void _exposedRays(
    List<bool> present,
    int w,
    int h,
    List<bool> clear,
  ) {
    // Direction order matches [_steps]: right, left, down, up.
    for (var y = 0; y < h; y++) {
      var open = true; // is everything further right already gone?
      for (var x = w - 1; x >= 0; x--) {
        clear[(y * w + x) * 4] = open;
        if (present[y * w + x]) open = false;
      }
      open = true;
      for (var x = 0; x < w; x++) {
        clear[(y * w + x) * 4 + 1] = open;
        if (present[y * w + x]) open = false;
      }
    }
    for (var x = 0; x < w; x++) {
      var open = true;
      for (var y = h - 1; y >= 0; y--) {
        clear[(y * w + x) * 4 + 2] = open;
        if (present[y * w + x]) open = false;
      }
      open = true;
      for (var y = 0; y < h; y++) {
        clear[(y * w + x) * 4 + 3] = open;
        if (present[y * w + x]) open = false;
      }
    }
  }

  /// Grows one arrow backwards from [head] (which points along [d]) until it
  /// is [desired] cells long or runs out of room. Returns it head-first, or
  /// null if it could not even reach [minLen].
  static List<int>? _growPath(
    int head,
    (int, int) d,
    int desired,
    List<bool> present,
    int w,
    int h,
    BoardStyle style,
    math.Random random,
  ) {
    final back = (head ~/ w - d.$2) * w + (head % w - d.$1);
    final path = <int>[head, back];
    final used = <int>{head, back};

    while (path.length < desired) {
      final last = path.last;
      final lx = last % w;
      final ly = last ~/ w;
      (int, int)? lastDelta;
      if (path.length >= 2) {
        final prev = path[path.length - 2];
        lastDelta = (lx - prev % w, ly - prev ~/ w);
      }

      int? best;
      var bestScore = double.negativeInfinity;
      for (final step in _steps) {
        final nx = lx + step.$1;
        final ny = ly + step.$2;
        if (nx < 0 || ny < 0 || nx >= w || ny >= h) continue;
        final next = ny * w + nx;
        if (!present[next] || used.contains(next)) continue;

        // Prefer stepping into open cells: a path that dives into a corner
        // dies at three cells, and short arrows are exactly what we don't
        // want on the board.
        var freedom = 0;
        for (final probe in _steps) {
          final px = nx + probe.$1;
          final py = ny + probe.$2;
          if (px < 0 || py < 0 || px >= w || py >= h) continue;
          final cell = py * w + px;
          if (present[cell] && !used.contains(cell)) freedom++;
        }

        final score =
            style.score(step, lx, ly, w, h) * 2 +
            (lastDelta == null ? 0 : style.turnScore(step != lastDelta)) +
            freedom * 0.30 +
            random.nextDouble();
        if (score > bestScore) {
          bestScore = score;
          best = next;
        }
      }

      if (best == null) break;
      path.add(best);
      used.add(best);
    }

    return path.length >= minLen ? path : null;
  }

  /// How much choice the board hands the player on turn one: the share of
  /// arrows that can fire straight away, from 0 (a single legal move) to 1
  /// (tap anything).
  ///
  /// This is the sharpest read on difficulty there is, and it costs one sweep
  /// of the grid — cheap enough to score every candidate board with, which
  /// matters more than a more thorough measure taken half as often.
  ///
  /// An arrow is free at the start only if its whole exit ray is empty. Deep
  /// inside a packed board that almost never happens, because the arrows in
  /// front are still standing there; on the rim it always happens. So a board
  /// scores well here exactly when its arrows have to leave in order.
  static double _openness(
    List<List<Offset>> order,
    int w,
    int h,
    List<bool> rays,
  ) {
    if (order.isEmpty) return 1;
    final present = List<bool>.filled(w * h, false);
    for (final path in order) {
      for (final c in path) {
        present[c.dy.toInt() * w + c.dx.toInt()] = true;
      }
    }
    _exposedRays(present, w, h, rays);

    var free = 0;
    for (final path in order) {
      final head = path.last;
      final prev = path[path.length - 2];
      final dx = (head.dx - prev.dx).toInt();
      final dy = (head.dy - prev.dy).toInt();
      var di = 0;
      for (var i = 0; i < 4; i++) {
        if (_steps[i].$1 == dx && _steps[i].$2 == dy) {
          di = i;
          break;
        }
      }
      if (rays[(head.dy.toInt() * w + head.dx.toInt()) * 4 + di]) free++;
    }
    return free / order.length;
  }

  // ── Constructive fallback ────────────────────────────────────────────────

  /// Never fails, never slow: stacks the arrows into columns, every one
  /// pointing up. The top arrow of each column always has a clear ray, so the
  /// board peels from the top down — packed, solvable, and instant.
  static BoardData _fallbackBoard({
    required int level,
    required int generation,
    required int cleared,
    required int n,
    required Palette palette,
    required math.Random rng,
  }) {
    // Aim for a phone-ish rectangle.
    final avgLen = density(level);
    final columns = math.max(1, math.sqrt(n * avgLen / 1.4).round());
    final perColumn = (n / columns).ceil();

    final lengths = <int>[
      for (var i = 0; i < n; i++)
        softMinLen + rng.nextInt(maxLen - softMinLen + 1),
    ];

    var rows = 0;
    for (var c = 0; c < columns; c++) {
      var height = 0;
      for (var k = c * perColumn; k < math.min(n, (c + 1) * perColumn); k++) {
        height += lengths[k];
      }
      rows = math.max(rows, height);
    }

    final pieces = <ArrowPiece>[];
    final mask = <int>{};
    for (var c = 0; c < columns; c++) {
      var y = 0;
      for (var k = c * perColumn; k < math.min(n, (c + 1) * perColumn); k++) {
        final len = lengths[k];
        // Tail at the bottom, head at the top — the arrow points up.
        final cells = <Offset>[
          for (var i = len - 1; i >= 0; i--)
            Offset(c.toDouble(), (y + i).toDouble()),
        ];
        for (final cell in cells) {
          mask.add(cell.dy.toInt() * columns + cell.dx.toInt());
        }
        pieces.add(
          ArrowPiece(
            id: pieces.length,
            cells: cells,
            colorIndex: (pieces.length * 5) % palette.length,
          ),
        );
        y += len;
      }
    }

    _markSpecial(pieces, level);
    return BoardData(
      level: level,
      generation: generation,
      cleared: cleared,
      columns: columns,
      rows: math.max(rows, 1),
      silhouette: const PresetSilhouette(BoardShape.rectangle),
      mask: mask,
      pieces: pieces,
      palette: palette,
    );
  }

  // ── Colours ───────────────────────────────────────────────────────────────

  /// Touching arrows must not share a colour — on a packed board they would
  /// read as one shape.
  static List<ArrowPiece> _assignColors(
    List<List<Offset>> ordered,
    int columns,
    int paletteLength,
  ) {
    final count = ordered.length;

    final cellOwner = <int, int>{};
    for (var i = 0; i < count; i++) {
      for (final cell in ordered[i]) {
        cellOwner[_key(cell, columns)] = i;
      }
    }

    final neighbours = List.generate(count, (_) => <int>{});
    for (var i = 0; i < count; i++) {
      for (final cell in ordered[i]) {
        for (final d in _steps) {
          final other = cellOwner[_key(
            cell + Offset(d.$1.toDouble(), d.$2.toDouble()),
            columns,
          )];
          if (other != null && other != i) {
            neighbours[i].add(other);
            neighbours[other].add(i);
          }
        }
      }
    }

    final colorOf = List<int>.filled(count, -1);
    for (var i = 0; i < count; i++) {
      final used = <int>{};
      for (final nb in neighbours[i]) {
        if (colorOf[nb] >= 0) used.add(colorOf[nb]);
      }
      var chosen = i % paletteLength;
      for (var offset = 0; offset < paletteLength; offset++) {
        final candidate = (i * 7 + offset) % paletteLength;
        if (!used.contains(candidate)) {
          chosen = candidate;
          break;
        }
      }
      colorOf[i] = chosen;
    }

    return [
      for (var i = 0; i < count; i++)
        ArrowPiece(id: i, cells: ordered[i], colorIndex: colorOf[i]),
    ];
  }

  // ── Rules (shared by app + widget) ───────────────────────────────────────

  static bool isBlocked(
    ArrowPiece piece,
    List<ArrowPiece> pieces,
    int columns,
    int rows,
  ) {
    final occupied = <int>{};
    for (final other in pieces) {
      if (other.id == piece.id || other.removed) continue;
      for (final cell in other.cells) {
        occupied.add(_key(cell, columns));
      }
    }
    var cursor = piece.head + piece.direction.step;
    while (cursor.dx >= 0 &&
        cursor.dy >= 0 &&
        cursor.dx < columns &&
        cursor.dy < rows) {
      if (occupied.contains(_key(cursor, columns))) return true;
      cursor += piece.direction.step;
    }
    return false;
  }

  /// Can the whole board be cleared by only ever firing unblocked arrows?
  static bool isSolvable(List<ArrowPiece> source, int columns, int rows) {
    final remaining = source.map((e) => e.copy()).toList();
    var removedSomething = true;
    while (remaining.isNotEmpty && removedSomething) {
      removedSomething = false;
      final removable = remaining
          .where((piece) => !isBlocked(piece, remaining, columns, rows))
          .toList();
      if (removable.isNotEmpty) {
        remaining.removeWhere((p) => removable.any((e) => e.id == p.id));
        removedSomething = true;
      }
    }
    return remaining.isEmpty;
  }
}

class _Mask {
  const _Mask(this.columns, this.rows, this.cells);

  final int columns;
  final int rows;
  final Set<int> cells;

  /// Connected, and no pocket smaller than a single arrow.
  bool isUsable(int minLen) {
    if (cells.isEmpty) return false;
    final seen = <int>{};
    for (final start in cells) {
      if (seen.contains(start)) continue;
      var size = 0;
      final stack = <int>[start];
      seen.add(start);
      while (stack.isNotEmpty) {
        final cell = stack.removeLast();
        size++;
        final cx = cell % columns;
        final cy = cell ~/ columns;
        for (final d in const [(1, 0), (-1, 0), (0, 1), (0, -1)]) {
          final nx = cx + d.$1;
          final ny = cy + d.$2;
          if (nx < 0 || ny < 0 || nx >= columns || ny >= rows) continue;
          final n = ny * columns + nx;
          if (!cells.contains(n) || seen.contains(n)) continue;
          seen.add(n);
          stack.add(n);
        }
      }
      if (size < minLen) return false;
    }
    return true;
  }
}
