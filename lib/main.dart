import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';

void main() => runApp(const ArrowEscapeApp());

class ArrowEscapeApp extends StatelessWidget {
  const ArrowEscapeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Arrow Escape',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF0A0E1A)),
        scaffoldBackgroundColor: const Color(0xFF0A0E1A),
        useMaterial3: true,
      ),
      home: const GamePage(),
    );
  }
}

// ─── Direction ───────────────────────────────────────────────────────────────

enum ArrowDirection { up, right, down, left }

extension ArrowDirectionX on ArrowDirection {
  Offset get step => switch (this) {
    ArrowDirection.up => const Offset(0, -1),
    ArrowDirection.right => const Offset(1, 0),
    ArrowDirection.down => const Offset(0, 1),
    ArrowDirection.left => const Offset(-1, 0),
  };

  ArrowDirection get leftTurn => switch (this) {
    ArrowDirection.up => ArrowDirection.left,
    ArrowDirection.left => ArrowDirection.down,
    ArrowDirection.down => ArrowDirection.right,
    ArrowDirection.right => ArrowDirection.up,
  };

  ArrowDirection get rightTurn => switch (this) {
    ArrowDirection.up => ArrowDirection.right,
    ArrowDirection.right => ArrowDirection.down,
    ArrowDirection.down => ArrowDirection.left,
    ArrowDirection.left => ArrowDirection.up,
  };
}

// ─── Arrow piece ─────────────────────────────────────────────────────────────

class ArrowPiece {
  ArrowPiece({required this.id, required this.cells, this.removed = false});

  final int id;
  final List<Offset> cells;
  bool removed;

  Offset get head => cells.last;

  ArrowDirection get direction {
    final delta = cells.last - cells[cells.length - 2];
    if (delta.dx > 0) return ArrowDirection.right;
    if (delta.dx < 0) return ArrowDirection.left;
    if (delta.dy > 0) return ArrowDirection.down;
    return ArrowDirection.up;
  }

  ArrowPiece copy() =>
      ArrowPiece(id: id, cells: List<Offset>.from(cells), removed: removed);
}

// ─── Palette ──────────────────────────────────────────────────────────────────

class ArrowPalette {
  // Neon palette: one distinct colour per arrow slot (cycles for extra arrows)
  static const _neonColors = [
    Color(0xFF00F5FF), // cyan
    Color(0xFFFF2D78), // hot pink
    Color(0xFF7CFF50), // lime
    Color(0xFFFFD600), // amber
    Color(0xFFBF40FF), // violet
    Color(0xFF00FFAA), // mint
    Color(0xFFFF6B00), // orange
    Color(0xFF40BFFF), // sky
    Color(0xFFFF4040), // red
    Color(0xFFB0FF00), // yellow-green
    Color(0xFF00B3FF), // azure
    Color(0xFFFF00C8), // magenta
    Color(0xFF80FFD0), // seafoam
    Color(0xFFFFB800), // gold
    Color(0xFF9966FF), // purple
  ];

  static Color forId(int id) => _neonColors[id % _neonColors.length];

  // Glow colour is same hue, slightly softer
  static Color glowForId(int id) => forId(id).withOpacity(0.55);
}

// ─── Particle (burst on removal) ─────────────────────────────────────────────

class Particle {
  Particle({
    required this.position,
    required this.velocity,
    required this.color,
    required this.life,
  });

  Offset position;
  Offset velocity;
  final Color color;
  double life; // 1 → 0
}

// ─── Level data ──────────────────────────────────────────────────────────────

class LevelData {
  const LevelData({
    required this.columns,
    required this.rows,
    required this.arrowCount,
    required this.minLength,
    required this.maxLength,
  });

  final int columns;
  final int rows;
  final int arrowCount;
  final int minLength;
  final int maxLength;
}

// ─── Game page ───────────────────────────────────────────────────────────────

class GamePage extends StatefulWidget {
  const GamePage({super.key});

  @override
  State<GamePage> createState() => _GamePageState();
}

class _GamePageState extends State<GamePage> with TickerProviderStateMixin {
  static const _levels = <LevelData>[
    LevelData(columns: 9, rows: 12, arrowCount: 9, minLength: 3, maxLength: 6),
    LevelData(
      columns: 10,
      rows: 13,
      arrowCount: 12,
      minLength: 4,
      maxLength: 7,
    ),
    LevelData(
      columns: 11,
      rows: 14,
      arrowCount: 15,
      minLength: 4,
      maxLength: 8,
    ),
  ];

  int _levelIndex = 0;
  int _lives = 3;
  int _generation = 0;
  late List<ArrowPiece> _pieces;

  // Move animation
  late final AnimationController _moveController;
  final Set<int> _movingPieceIds = {};
  Timer? _moveDelayTimer;

  // Ambient pulse animation (drives dot-grid breathing)
  late final AnimationController _pulseController;

  // Particle system
  final List<Particle> _particles = [];
  late final AnimationController _particleController;

  // Shake on blocked tap
  late final AnimationController _shakeController;
  late final Animation<double> _shakeAnim;

  // Scale-pop on successful tap
  late final AnimationController _popController;

  // Hovered / pressed piece for highlight
  int? _hoveredId;

  // Track cell size for particles
  double _lastCellSize = 40;

  @override
  void initState() {
    super.initState();

    _moveController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..addListener(() => setState(() {}));

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2800),
    )..repeat(reverse: true);

    _particleController =
        AnimationController(
            vsync: this,
            duration: const Duration(milliseconds: 16),
          )
          ..addListener(_stepParticles)
          ..repeat();

    _shakeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 380),
    );
    _shakeAnim = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0, end: -8), weight: 1),
      TweenSequenceItem(tween: Tween(begin: -8, end: 8), weight: 2),
      TweenSequenceItem(tween: Tween(begin: 8, end: -5), weight: 2),
      TweenSequenceItem(tween: Tween(begin: -5, end: 5), weight: 2),
      TweenSequenceItem(tween: Tween(begin: 5, end: 0), weight: 1),
    ]).animate(CurvedAnimation(parent: _shakeController, curve: Curves.linear));

    _popController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
    );

    _loadLevel();
  }

  @override
  void dispose() {
    _moveController.dispose();
    _pulseController.dispose();
    _particleController.dispose();
    _shakeController.dispose();
    _popController.dispose();
    super.dispose();
  }

  // ── Level generation (unchanged logic) ────────────────────────────────────

  void _loadLevel() {
    final level = _levels[_levelIndex];
    _pieces = _generateSolvableLevel(
      level,
      seed: 5000 + (_levelIndex * 1000) + _generation,
    );
    _lives = 3;
    _movingPieceIds.clear();
    _moveController.reset();
    _particles.clear();
  }

  List<ArrowPiece> _generateSolvableLevel(
    LevelData level, {
    required int seed,
  }) {
    for (var boardAttempt = 0; boardAttempt < 250; boardAttempt++) {
      final random = math.Random(seed + boardAttempt);
      final pieces = <ArrowPiece>[];
      final occupied = <String>{};

      for (var id = 0; id < level.arrowCount; id++) {
        List<Offset>? path;
        for (var attempt = 0; attempt < 180 && path == null; attempt++) {
          final candidate = _makeRandomPath(level, random);
          if (candidate.length < level.minLength) continue;
          if (id == 0 && _cornerCount(candidate) == 0) continue;
          if (candidate.any((cell) => occupied.contains(_key(cell)))) continue;
          path = candidate;
        }
        if (path == null) break;
        pieces.add(ArrowPiece(id: id, cells: path));
        occupied.addAll(path.map(_key));
      }

      if (pieces.length == level.arrowCount && _isSolvable(pieces)) {
        return pieces;
      }
    }
    return _fallbackLevel(level);
  }

  List<Offset> _makeRandomPath(LevelData level, math.Random random) {
    final targetLength =
        level.minLength + random.nextInt(level.maxLength - level.minLength + 1);
    var direction = ArrowDirection.values[random.nextInt(4)];
    var current = Offset(
      1 + random.nextInt(level.columns - 2).toDouble(),
      1 + random.nextInt(level.rows - 2).toDouble(),
    );

    final path = <Offset>[current];
    final used = <String>{_key(current)};
    var turns = 0;

    while (path.length < targetLength) {
      final choices = <ArrowDirection>[direction];
      if (turns < 3 && random.nextDouble() < .68) {
        choices
          ..add(direction.leftTurn)
          ..add(direction.rightTurn);
      }
      choices.shuffle(random);

      Offset? next;
      ArrowDirection? selected;
      for (final choice in choices) {
        final candidate = current + choice.step;
        if (candidate.dx < 0 ||
            candidate.dy < 0 ||
            candidate.dx >= level.columns ||
            candidate.dy >= level.rows ||
            used.contains(_key(candidate)))
          continue;
        next = candidate;
        selected = choice;
        break;
      }
      if (next == null || selected == null) break;
      if (selected != direction) turns++;
      direction = selected;
      current = next;
      path.add(current);
      used.add(_key(current));
    }

    if (path.length < level.minLength) return const [];
    return path;
  }

  int _cornerCount(List<Offset> cells) {
    var corners = 0;
    for (var i = 1; i < cells.length - 1; i++) {
      final before = cells[i] - cells[i - 1];
      final after = cells[i + 1] - cells[i];
      if (before != after) corners++;
    }
    return corners;
  }

  bool _isSolvable(List<ArrowPiece> source) {
    final remaining = source.map((e) => e.copy()).toList();
    var removedSomething = true;
    while (remaining.isNotEmpty && removedSomething) {
      removedSomething = false;
      final removable = remaining
          .where((piece) => !_isBlockedIn(piece, remaining))
          .toList();
      if (removable.isNotEmpty) {
        remaining.removeWhere((p) => removable.any((e) => e.id == p.id));
        removedSomething = true;
      }
    }
    return remaining.isEmpty;
  }

  List<ArrowPiece> _fallbackLevel(LevelData level) {
    final pieces = <ArrowPiece>[];
    var id = 0;
    for (var y = 1; y < level.rows - 1 && id < level.arrowCount; y += 2) {
      final leftToRight = y.isOdd;
      final cells = leftToRight
          ? <Offset>[
              Offset(1, y.toDouble()),
              Offset(2, y.toDouble()),
              Offset(3, y.toDouble()),
            ]
          : <Offset>[
              Offset((level.columns - 2).toDouble(), y.toDouble()),
              Offset((level.columns - 3).toDouble(), y.toDouble()),
              Offset((level.columns - 4).toDouble(), y.toDouble()),
            ];
      pieces.add(ArrowPiece(id: id++, cells: cells));
    }
    return pieces;
  }

  String _key(Offset cell) => '${cell.dx.toInt()}:${cell.dy.toInt()}';

  bool _isBlocked(ArrowPiece piece) =>
      _isBlockedIn(piece, _pieces.where((e) => !e.removed).toList());

  bool _isBlockedIn(ArrowPiece piece, List<ArrowPiece> pieces) {
    final occupied = <String>{};
    for (final other in pieces) {
      if (other.id == piece.id || other.removed) continue;
      occupied.addAll(other.cells.map(_key));
    }
    var cursor = piece.head + piece.direction.step;
    final level = _levels[_levelIndex];
    while (cursor.dx >= 0 &&
        cursor.dy >= 0 &&
        cursor.dx < level.columns &&
        cursor.dy < level.rows) {
      if (occupied.contains(_key(cursor))) return true;
      cursor += piece.direction.step;
    }
    return false;
  }

  // ── Particle helpers ──────────────────────────────────────────────────────

  void _spawnParticles(ArrowPiece piece) {
    final rng = math.Random();
    final color = ArrowPalette.forId(piece.id);
    final cell = _lastCellSize;

    // Burst at head's original position (where tail will pass through)
    final head = piece.head;
    final cx = (head.dx + 0.5) * cell;
    final cy = (head.dy + 0.5) * cell;

    for (var i = 0; i < 26; i++) {
      final angle = rng.nextDouble() * math.pi * 2;
      final speed = 1.8 + rng.nextDouble() * 4.2;
      _particles.add(
        Particle(
          position: Offset(cx, cy),
          velocity: Offset(math.cos(angle) * speed, math.sin(angle) * speed),
          color: color,
          life: 1.0,
        ),
      );
    }
  }

  /// Returns the animation progress value [0..1] at which the tail of [piece]
  /// will reach the head's original grid position during the exit animation.
  /// At that exact moment the burst should fire.
  double _burstThreshold(ArrowPiece piece) {
    final level = _levels[_levelIndex];
    final head = piece.head;

    final stepsToOutside = switch (piece.direction) {
      ArrowDirection.up => head.dy.toInt() + 2,
      ArrowDirection.right => level.columns - head.dx.toInt() + 1,
      ArrowDirection.down => level.rows - head.dy.toInt() + 1,
      ArrowDirection.left => head.dx.toInt() + 2,
    };

    final bodyLength = (piece.cells.length - 1).toDouble();
    final travelDistance = stepsToOutside + bodyLength;

    // Tail reaches head position when tail has travelled = stepsToOutside units.
    // tailDistance = travelDistance * progress  →  progress = stepsToOutside / travelDistance
    return (stepsToOutside / travelDistance).clamp(0.0, 1.0);
  }

  void _stepParticles() {
    if (_particles.isEmpty) return;
    setState(() {
      for (final p in _particles) {
        p.position += p.velocity;
        p.velocity = p.velocity * 0.93; // friction
        p.life -= 0.028;
      }
      _particles.removeWhere((p) => p.life <= 0);
    });
  }

  // ── Tap logic (unchanged behaviour) ──────────────────────────────────────

  Future<void> _tapPiece(ArrowPiece piece) async {
    if (_movingPieceIds.contains(piece.id) || piece.removed) return;

    if (_isBlocked(piece)) {
      setState(() => _lives--);
      _shakeController.forward(from: 0);
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFF1A0010),
            duration: const Duration(milliseconds: 650),
            content: Row(
              children: [
                Icon(Icons.block, color: Colors.redAccent.shade100, size: 18),
                const SizedBox(width: 8),
                const Text(
                  'Blocked! Pehle raaste wala arrow nikalo.',
                  style: TextStyle(color: Colors.white70),
                ),
              ],
            ),
          ),
        );

      if (_lives <= 0) {
        await Future<void>.delayed(const Duration(milliseconds: 350));
        if (!mounted) return;
        _resetLevel();
      }
      return;
    }

    // Add piece to moving set
    setState(() {
      _movingPieceIds.add(piece.id);
    });

    // Reset delay timer to collect multi-touch taps
    _moveDelayTimer?.cancel();
    _moveDelayTimer = Timer(const Duration(milliseconds: 200), () async {
      // Start animation for all selected pieces
      if (_moveController.status == AnimationStatus.dismissed) {
        // Calculate burst thresholds for all pieces
        final thresholds = <int, double>{};
        for (final id in _movingPieceIds) {
          final p = _pieces.firstWhere((e) => e.id == id);
          thresholds[id] = _burstThreshold(p);
        }
        final burstFired = <int, bool>{};

        void onTick() {
          for (final id in _movingPieceIds) {
            if (!burstFired.containsKey(id) || !burstFired[id]!) {
              final threshold = thresholds[id]!;
              if (_moveController.value >= threshold) {
                burstFired[id] = true;
                final p = _pieces.firstWhere((e) => e.id == id);
                _spawnParticles(p);
              }
            }
          }
        }

        _moveController.addListener(onTick);
        await _moveController.forward(from: 0);
        _moveController.removeListener(onTick);

        if (!mounted) return;

        setState(() {
          for (final id in _movingPieceIds) {
            final p = _pieces.firstWhere((e) => e.id == id);
            p.removed = true;
          }
          _movingPieceIds.clear();
          _moveController.reset();
        });

        if (_pieces.every((e) => e.removed)) {
          await Future<void>.delayed(const Duration(milliseconds: 220));
          if (mounted) _showWinDialog();
        }
      }
    });
  }

  void _resetLevel() {
    setState(() {
      _generation++;
      _loadLevel();
    });
  }

  void _showWinDialog() {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => Dialog(
        backgroundColor: const Color(0xFF0D1424),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('🎉', style: TextStyle(fontSize: 48)),
              const SizedBox(height: 12),
              const Text(
                'Level Clear!',
                style: TextStyle(
                  color: Color(0xFF00F5FF),
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.4,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Saare arrows safely escape ho gaye.',
                style: TextStyle(color: Colors.white54, fontSize: 14),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 28),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF00F5FF),
                        side: const BorderSide(color: Color(0xFF00F5FF)),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      onPressed: () {
                        Navigator.pop(context);
                        setState(() {
                          _generation++;
                          _loadLevel();
                        });
                      },
                      child: const Text('Random'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF00F5FF),
                        foregroundColor: const Color(0xFF0A0E1A),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      onPressed: () {
                        Navigator.pop(context);
                        setState(() {
                          _levelIndex = (_levelIndex + 1) % _levels.length;
                          _generation++;
                          _loadLevel();
                        });
                      },
                      child: const Text('Next Level'),
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

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final level = _levels[_levelIndex];

    return Scaffold(
      backgroundColor: const Color(0xFF0A0E1A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0A0E1A),
        elevation: 0,
        title: Text(
          'LEVEL ${_levelIndex + 1}',
          style: const TextStyle(
            color: Color(0xFF00F5FF),
            fontWeight: FontWeight.w900,
            fontSize: 18,
            letterSpacing: 3,
          ),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            tooltip: 'New random board',
            onPressed: _resetLevel,
            icon: const Icon(Icons.casino_outlined, color: Color(0xFF00F5FF)),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(
            height: 1,
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Colors.transparent,
                  Color(0xFF00F5FF),
                  Colors.transparent,
                ],
              ),
            ),
          ),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            // ── HUD ──────────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Tap the arrow with a clear exit',
                      style: TextStyle(
                        color: Colors.white38,
                        fontWeight: FontWeight.w500,
                        fontSize: 13,
                        letterSpacing: 0.4,
                      ),
                    ),
                  ),
                  // Life indicators as neon hearts
                  ...List.generate(3, (i) {
                    final alive = i < _lives;
                    return AnimatedOpacity(
                      duration: const Duration(milliseconds: 300),
                      opacity: alive ? 1.0 : 0.25,
                      child: Padding(
                        padding: const EdgeInsets.only(left: 6),
                        child: Icon(
                          alive
                              ? Icons.favorite_rounded
                              : Icons.favorite_border_rounded,
                          color: alive
                              ? const Color(0xFFFF2D78)
                              : Colors.white24,
                          size: 22,
                          shadows: alive
                              ? [
                                  const Shadow(
                                    color: Color(0xFFFF2D78),
                                    blurRadius: 10,
                                  ),
                                ]
                              : null,
                        ),
                      ),
                    );
                  }),
                ],
              ),
            ),

            // ── Board ────────────────────────────────────────────────────
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: AnimatedBuilder(
                  animation: _shakeAnim,
                  builder: (context, child) => Transform.translate(
                    offset: Offset(_shakeAnim.value, 0),
                    child: child,
                  ),
                  child: AnimatedBuilder(
                    animation: _pulseController,
                    builder: (context, child) {
                      return LayoutBuilder(
                        builder: (context, constraints) {
                          final cell = math.min(
                            constraints.maxWidth / level.columns,
                            constraints.maxHeight / level.rows,
                          );
                          _lastCellSize = cell;
                          final boardSize = Size(
                            cell * level.columns,
                            cell * level.rows,
                          );

                          return Center(
                            child: SizedBox.fromSize(
                              size: boardSize,
                              child: Listener(
                                behavior: HitTestBehavior.opaque,
                                onPointerDown: (details) {
                                  final piece = _pieceAt(
                                    details.localPosition,
                                    cell,
                                  );
                                  if (piece != null) _tapPiece(piece);
                                },
                                child: Stack(
                                  children: [
                                    // Main game canvas
                                    CustomPaint(
                                      size: boardSize,
                                      painter: GamePainter(
                                        columns: level.columns,
                                        rows: level.rows,
                                        pieces: _pieces,
                                        movingPieceIds: _movingPieceIds,
                                        moveProgress: Curves.easeInOutQuart
                                            .transform(_moveController.value),
                                        pulseValue: _pulseController.value,
                                        particles: _particles,
                                        hoveredId: _hoveredId,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  ArrowPiece? _pieceAt(Offset point, double cell) {
    final active = _pieces.where((e) => !e.removed).toList().reversed;
    for (final piece in active) {
      for (var i = 0; i < piece.cells.length - 1; i++) {
        final a = _centerOf(piece.cells[i], cell);
        final b = _centerOf(piece.cells[i + 1], cell);
        if (_distanceToSegment(point, a, b) <= cell * .42) return piece;
      }
    }
    return null;
  }

  Offset _centerOf(Offset cellPosition, double cell) =>
      Offset((cellPosition.dx + .5) * cell, (cellPosition.dy + .5) * cell);

  double _distanceToSegment(Offset p, Offset a, Offset b) {
    final ab = b - a;
    final lengthSquared = ab.dx * ab.dx + ab.dy * ab.dy;
    if (lengthSquared == 0) return (p - a).distance;
    final ap = p - a;
    final t = ((ap.dx * ab.dx + ap.dy * ab.dy) / lengthSquared).clamp(0.0, 1.0);
    final closest = a + ab * t;
    return (p - closest).distance;
  }
}

// ─── Painter ──────────────────────────────────────────────────────────────────

class GamePainter extends CustomPainter {
  GamePainter({
    required this.columns,
    required this.rows,
    required this.pieces,
    required this.movingPieceIds,
    required this.moveProgress,
    required this.pulseValue,
    required this.particles,
    this.hoveredId,
  });

  final int columns;
  final int rows;
  final List<ArrowPiece> pieces;
  final Set<int> movingPieceIds;
  final double moveProgress;
  final double pulseValue;
  final List<Particle> particles;
  final int? hoveredId;

  @override
  void paint(Canvas canvas, Size size) {
    final cell = math.min(size.width / columns, size.height / rows);

    _drawGrid(canvas, size, cell);
    _drawBoardBorder(canvas, size, cell);

    // Draw non-moving arrows first (back to front)
    for (final piece in pieces) {
      if (piece.removed || movingPieceIds.contains(piece.id)) continue;
      _drawArrow(canvas, piece, cell, false, 0, size);
    }

    // Draw moving arrows on top
    for (final piece in pieces) {
      if (piece.removed || !movingPieceIds.contains(piece.id)) continue;
      _drawArrow(canvas, piece, cell, true, moveProgress, size);
    }

    // Particles
    _drawParticles(canvas, cell);
  }

  // ── Grid (animated dot grid) ───────────────────────────────────────────

  void _drawGrid(Canvas canvas, Size size, double cell) {
    final basePulse = 0.5 + 0.5 * pulseValue; // 0.5 → 1.0
    for (var x = 0; x <= columns; x++) {
      for (var y = 0; y <= rows; y++) {
        // Slight ripple: dots near centre pulse slightly bigger
        final cx = columns / 2.0;
        final cy = rows / 2.0;
        final distFromCenter = math.sqrt(
          math.pow(x - cx, 2) + math.pow(y - cy, 2),
        );
        final maxDist = math.sqrt(math.pow(cx, 2) + math.pow(cy, 2));
        final wave = 1.0 - (distFromCenter / maxDist) * 0.5;

        final radius = 1.2 + 0.8 * basePulse * wave;
        final opacity = 0.18 + 0.18 * basePulse * wave;

        final paint = Paint()
          ..color = const Color(0xFF00F5FF).withOpacity(opacity)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.2);
        canvas.drawCircle(Offset(x * cell, y * cell), radius, paint);

        // Inner solid dot
        canvas.drawCircle(
          Offset(x * cell, y * cell),
          0.6,
          Paint()..color = const Color(0xFF00F5FF).withOpacity(opacity * 0.8),
        );
      }
    }
  }

  // ── Subtle board border glow ──────────────────────────────────────────

  void _drawBoardBorder(Canvas canvas, Size size, double cell) {
    final w = columns * cell;
    final h = rows * cell;
    final rect = Rect.fromLTWH(0, 0, w, h);
    final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(4));

    final borderPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..color = const Color(0xFF00F5FF).withOpacity(0.12 + 0.08 * pulseValue)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);

    canvas.drawRRect(rrect, borderPaint);
  }

  // ── Arrow drawing ─────────────────────────────────────────────────────

  void _drawArrow(
    Canvas canvas,
    ArrowPiece piece,
    double cell,
    bool isMoving,
    double progress,
    Size size,
  ) {
    final color = ArrowPalette.forId(piece.id);
    final glowColor = ArrowPalette.glowForId(piece.id);
    final strokeW = math.max(3.0, cell * .10);

    Offset center(Offset p) => Offset((p.dx + .5) * cell, (p.dy + .5) * cell);

    final cellsToDraw = isMoving
        ? _movingSnakePoints(piece, progress)
        : List<Offset>.from(piece.cells);

    if (cellsToDraw.length < 2) return;

    // Build path
    final path = Path()
      ..moveTo(center(cellsToDraw.first).dx, center(cellsToDraw.first).dy);
    for (var i = 1; i < cellsToDraw.length; i++) {
      final pt = center(cellsToDraw[i]);
      path.lineTo(pt.dx, pt.dy);
    }

    // 1. Wide glow layer
    canvas.drawPath(
      path,
      Paint()
        ..isAntiAlias = true
        ..color = glowColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeW * 3.5
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, strokeW * 1.8),
    );

    // 2. Mid glow layer
    canvas.drawPath(
      path,
      Paint()
        ..isAntiAlias = true
        ..color = color.withOpacity(0.55)
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeW * 2.0
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, strokeW * 0.6),
    );

    // 3. Bright core stroke
    canvas.drawPath(
      path,
      Paint()
        ..isAntiAlias = true
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeW
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );

    // ── Arrowhead ──────────────────────────────────────────────────────
    final head = center(cellsToDraw.last);
    final previous = center(cellsToDraw[cellsToDraw.length - 2]);
    final vector = head - previous;
    if (vector.distance <= .001) return;

    final direction = vector / vector.distance;
    final perpendicular = Offset(-direction.dy, direction.dx);
    final arrowSize = cell * .36;
    final back = head - direction * arrowSize;

    final headPath = Path()
      ..moveTo(head.dx, head.dy)
      ..lineTo(
        (back + perpendicular * arrowSize * .62).dx,
        (back + perpendicular * arrowSize * .62).dy,
      )
      ..moveTo(head.dx, head.dy)
      ..lineTo(
        (back - perpendicular * arrowSize * .62).dx,
        (back - perpendicular * arrowSize * .62).dy,
      );

    // Glow arrowhead
    canvas.drawPath(
      headPath,
      Paint()
        ..isAntiAlias = true
        ..color = glowColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeW * 2.8
        ..strokeCap = StrokeCap.round
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, strokeW * 1.4),
    );

    // Bright arrowhead
    canvas.drawPath(
      headPath,
      Paint()
        ..isAntiAlias = true
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeW
        ..strokeCap = StrokeCap.round,
    );

    // ── Head dot ──────────────────────────────────────────────────────
    canvas.drawCircle(
      head,
      strokeW * 0.9,
      Paint()
        ..color = Colors.white
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, strokeW * 0.8),
    );
    canvas.drawCircle(head, strokeW * 0.55, Paint()..color = Colors.white);
  }

  // ── Particles ─────────────────────────────────────────────────────────

  void _drawParticles(Canvas canvas, double cell) {
    for (final p in particles) {
      final radius = (2.5 + p.life * 3) * (cell / 40);
      canvas.drawCircle(
        p.position,
        radius,
        Paint()
          ..color = p.color.withOpacity(p.life.clamp(0.0, 1.0))
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, radius * 1.5),
      );
      // Bright inner dot
      canvas.drawCircle(
        p.position,
        radius * 0.4,
        Paint()..color = Colors.white.withOpacity(p.life * 0.9),
      );
    }
  }

  // ── Snake animation helpers (unchanged logic) ─────────────────────────

  List<Offset> _movingSnakePoints(ArrowPiece piece, double progress) {
    final route = List<Offset>.from(piece.cells);
    final direction = piece.direction.step;
    final head = piece.head;

    final stepsToOutside = switch (piece.direction) {
      ArrowDirection.up => head.dy.toInt() + 2,
      ArrowDirection.right => columns - head.dx.toInt() + 1,
      ArrowDirection.down => rows - head.dy.toInt() + 1,
      ArrowDirection.left => head.dx.toInt() + 2,
    };

    final bodyLength = (piece.cells.length - 1).toDouble();
    for (var i = 1; i <= stepsToOutside + piece.cells.length + 1; i++) {
      route.add(head + direction * i.toDouble());
    }

    final travelDistance = stepsToOutside + bodyLength;
    final tailDistance = travelDistance * progress.clamp(0.0, 1.0);
    final headDistance = tailDistance + bodyLength;

    return _slicePolyline(route, tailDistance, headDistance);
  }

  List<Offset> _slicePolyline(
    List<Offset> route,
    double startDistance,
    double endDistance,
  ) {
    if (route.length < 2 || endDistance <= startDistance) return const [];

    final result = <Offset>[];
    var travelled = 0.0;

    for (var i = 0; i < route.length - 1; i++) {
      final a = route[i];
      final b = route[i + 1];
      final segmentLength = (b - a).distance;
      final segmentStart = travelled;
      final segmentEnd = travelled + segmentLength;

      if (segmentEnd < startDistance) {
        travelled = segmentEnd;
        continue;
      }
      if (segmentStart > endDistance) break;

      final localStart = ((startDistance - segmentStart) / segmentLength).clamp(
        0.0,
        1.0,
      );
      final localEnd = ((endDistance - segmentStart) / segmentLength).clamp(
        0.0,
        1.0,
      );

      final startPoint = Offset.lerp(a, b, localStart)!;
      final endPoint = Offset.lerp(a, b, localEnd)!;

      if (result.isEmpty || (result.last - startPoint).distance > .001) {
        result.add(startPoint);
      }
      if ((result.last - endPoint).distance > .001) {
        result.add(endPoint);
      }

      travelled = segmentEnd;
      if (segmentEnd >= endDistance) break;
    }

    return result;
  }

  @override
  bool shouldRepaint(covariant GamePainter oldDelegate) =>
      oldDelegate.pieces != pieces ||
      oldDelegate.movingPieceIds != movingPieceIds ||
      oldDelegate.moveProgress != moveProgress ||
      oldDelegate.pulseValue != pulseValue ||
      oldDelegate.particles != particles ||
      oldDelegate.hoveredId != hoveredId;
}
