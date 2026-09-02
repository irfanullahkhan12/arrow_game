import 'dart:async';
import 'dart:isolate';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../game/ai_designer.dart';
import '../game/flight_path.dart';
import '../game/level_factory.dart';
import '../models/arrow_kind.dart';
import '../models/arrow_piece.dart';
import '../models/board_data.dart';
import '../services/ads_service.dart';
import '../services/game_store.dart';
import '../services/iap_service.dart';
import '../services/notification_service.dart';
import '../services/player_profile.dart';
import '../services/sound_service.dart';
import '../theme/game_theme.dart';
import 'game_painter.dart';
import 'widgets/arrow_picker.dart';
import 'widgets/game_dialogs.dart';
import 'notify/notify_gallery.dart';
import 'widgets/loading_screen.dart';
import 'widgets/neon_widgets.dart';
import 'widgets/power_row.dart';
import 'widgets/shop_sheet.dart';

class GamePage extends StatefulWidget {
  const GamePage({super.key});

  @override
  State<GamePage> createState() => _GamePageState();
}

class _GamePageState extends State<GamePage>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  static const _maxLives = 5;

  /// Cells never shrink below this: the arrows have to stay chunky. Bigger
  /// boards overflow the screen instead, and the player pans / zooms — or
  /// taps the fit button to snap everything back into view.
  static const _minCell = 56.0;
  static const _maxCell = 112.0;
  static const _boardPad = 14.0;

  final _profile = PlayerProfile.instance;

  BoardData? _board;
  int _lives = _maxLives;
  bool _generating = false; // next board is being built off-thread
  String _tip = GameFacts.random();

  // Extra cells past the board edge a flying arrow travels, sized in build so
  // every arrow fully leaves the phone screen before it disappears.
  int _overshootCells = 6;

  AiDesign? _nextDesign; // prefetched by the online AI, if available

  // Move animation: each firing arrow owns its own controller, so several
  // arrows can fly at once and each one completes its full animation.
  final Map<int, AnimationController> _flights = {};

  // Bump-and-return when a blocked arrow is tapped.
  late final AnimationController _bumpController;
  late final Animation<double> _bumpAnim;
  int? _bumpPieceId;
  int? _bumpBlockerId;
  Offset _bumpStep = Offset.zero;
  double _bumpCells = 0;

  /// Shared slow pulse behind the hint ring and the convert-mode shimmer.
  late final AnimationController _pulseController;

  /// Every new board lands rather than appears: it fades up and settles from
  /// slightly small, which reads as "here is your puzzle" instead of a jump
  /// cut between levels.
  late final AnimationController _introController;

  // ── View transform ───────────────────────────────────────────────────────
  final TransformationController _zoom = TransformationController();
  late final AnimationController _zoomController;
  Animation<Matrix4>? _zoomAnim;
  Size? _viewport;
  Size? _content;
  bool _needsFit = true;

  // ── Power-ups ────────────────────────────────────────────────────────────
  int? _hintPieceId;
  Timer? _hintTimer;
  /// The special the player has armed: the next arrow they tap becomes this.
  ArrowKind? _convertKind;
  final List<int> _undoStack = [];

  bool get _convertMode => _convertKind != null;

  bool get _pulsing => _hintPieceId != null || _convertMode;

  /// Runs the shared pulse only while the hint ring or the convert-mode
  /// shimmer is on screen.
  void _syncPulse() {
    if (_pulsing) {
      if (!_pulseController.isAnimating) {
        _pulseController.repeat(reverse: true);
      }
    } else if (_pulseController.isAnimating) {
      _pulseController.stop();
      _pulseController.value = 0;
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    SoundService.instance.start();

    _bumpController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 430),
    ); // painter repaints from this directly — no setState per tick
    _bumpController.addStatusListener((status) {
      if (status == AnimationStatus.completed && mounted) {
        setState(() {
          _bumpPieceId = null;
          _bumpBlockerId = null;
        });
      }
    });
    // Quick lunge out, a beat pressed against the blocker, slower drift back.
    _bumpAnim = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween(
          begin: 0.0,
          end: 1.0,
        ).chain(CurveTween(curve: Curves.easeOutCubic)),
        weight: 30,
      ),
      TweenSequenceItem(tween: ConstantTween<double>(1.0), weight: 10),
      TweenSequenceItem(
        tween: Tween(
          begin: 1.0,
          end: 0.0,
        ).chain(CurveTween(curve: Curves.easeInOutCubic)),
        weight: 60,
      ),
    ]).animate(_bumpController);

    // Only runs while something needs it: a repeating controller wired into
    // the painter would repaint the whole board 60 times a second forever.
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );

    _introController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 520),
      value: 1,
    );

    _zoomController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
    )..addListener(() {
      final anim = _zoomAnim;
      if (anim != null) _zoom.value = anim.value;
    });

    _boot();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _hintTimer?.cancel();
    SoundService.instance.dispose();
    for (final controller in _flights.values) {
      controller.dispose();
    }
    _bumpController.dispose();
    _pulseController.dispose();
    _introController.dispose();
    _zoomController.dispose();
    _zoom.dispose();
    super.dispose();
  }

  /// First run: settings, saved board (or a fresh level 1), daily gift. The
  /// loader stays up for all of it.
  Future<void> _boot() async {
    await _profile.load();
    GameTheme.dark = _profile.dark;
    // What the player owns is settled before any ad can load; the store
    // itself catches up in the background.
    await IapService.instance.loadCached();
    unawaited(IapService.instance.initialize());
    unawaited(AdsService.instance.initialize());

    final saved = await GameStore.load();
    final board =
        saved ?? await _build(level: 1, generation: 0, cleared: 0);
    if (!mounted) return;
    setState(() {
      _board = board;
      _resetTransients();
      _needsFit = true;
    });
    // Push the board to the home-screen widget on launch too: without this a
    // freshly installed widget sits empty until the first level is cleared.
    unawaited(GameStore.save(board));
    unawaited(_prefetchDesign());
    unawaited(_setUpReminders(board.level));
    await _catchUpWidgetGames();
    await _maybeShowDailyGift();
  }

  /// Boards finished out on the home-screen widget still owe an ad break, and
  /// a widget has nowhere to show one — no activity to host it, and AdMob's
  /// policy keeps ads inside the app's own screens. So they are counted there
  /// and paid here, one interstitial per [_widgetGamesPerAd].
  static const _widgetGamesPerAd = 10;

  Future<void> _catchUpWidgetGames() async {
    final played = await GameStore.takeWidgetGames();
    if (!mounted || played < _widgetGamesPerAd) return;
    await AdsService.instance.showInterstitialNow();
  }

  /// Asks once for permission, then lays down a week of daily reminders
  /// carrying the level the player is actually on.
  Future<void> _setUpReminders(int level) async {
    final notifications = NotificationService.instance;
    await notifications.initialize();
    await notifications.requestPermission();
    await notifications.scheduleDaily(level: level);
  }

  /// The widget may have played moves while the app was backgrounded — pick
  /// up its state whenever we come back, and hand it the latest board (as a
  /// PNG) whenever we leave.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final board = _board;
    if (state == AppLifecycleState.resumed) {
      _restoreState();
      unawaited(_catchUpWidgetGames());
      unawaited(AdsService.instance.onAppResumed());
    }
    if (state == AppLifecycleState.paused) {
      AdsService.instance.onAppPaused();
      if (board != null) GameStore.save(board);
    }
  }

  Future<void> _restoreState() async {
    if (_generating) return;
    final saved = await GameStore.load();
    if (!mounted || saved == null) return;
    setState(() {
      _board = saved;
      _resetTransients();
      _needsFit = true;
    });
    unawaited(_prefetchDesign());
  }

  void _resetTransients() {
    _lives = _maxLives;
    _hintTimer?.cancel();
    _hintPieceId = null;
    _convertKind = null;
    _undoStack.clear();
    _pulseController.stop();
    _pulseController.value = 0;
    final oldFlights = _flights.values.toList();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      for (final controller in oldFlights) {
        controller.dispose();
      }
    });
    _flights.clear();
    _bumpController.reset();
    _bumpPieceId = null;
    _bumpBlockerId = null;
    _introController.forward(from: 0);
  }

  /// Ask the online AI (if configured) to draw the NEXT board while this one
  /// is being played — zero wait when it arrives, silent fallback otherwise.
  /// A fresh outline is fetched after every board, so no two levels get the
  /// same design.
  Future<void> _prefetchDesign() async {
    final board = _board;
    if (board == null || !AiDesigner.enabled) return;
    _nextDesign = await AiDesigner.design(board.level + 1);
  }

  /// The carver can take a moment on big levels — run it off the UI thread so
  /// the app never freezes while the next board is being built.
  Future<BoardData> _build({
    required int level,
    required int generation,
    required int cleared,
    AiDesign? design,
  }) async {
    try {
      return await Isolate.run(
        () => LevelFactory.generate(
          level: level,
          generation: generation,
          cleared: cleared,
          design: design,
        ),
      );
    } catch (_) {
      return LevelFactory.generate(
        level: level,
        generation: generation,
        cleared: cleared,
        design: design,
      );
    }
  }

  Future<void> _newBoard({int? level, bool countClear = false}) async {
    final current = _board;
    if (_generating || current == null) return;
    setState(() {
      _generating = true;
      _tip = GameFacts.random();
    });

    final newLevel = level ?? current.level;
    final generation = current.generation + 1;
    final cleared = current.cleared + (countClear ? 1 : 0);
    // Whatever the designer drew last is used for this board, whichever board
    // it is — next level, replay, or a fresh shuffle — and then thrown away so
    // the next one gets a new outline.
    final design = _nextDesign;
    _nextDesign = null;

    final board = await _build(
      level: newLevel,
      generation: generation,
      cleared: cleared,
      design: design,
    );

    if (!mounted) return;
    setState(() {
      _board = board;
      _generating = false;
      _resetTransients();
      _needsFit = true;
    });
    unawaited(GameStore.save(board));
    unawaited(_prefetchDesign());
    unawaited(NotificationService.instance.scheduleDaily(level: board.level));
  }

  // ── Daily gift ────────────────────────────────────────────────────────────

  Future<void> _maybeShowDailyGift() async {
    if (!_profile.canClaimGift) return;
    // Give the board a beat to appear first.
    await Future<void>.delayed(const Duration(milliseconds: 500));
    if (!mounted) return;
    await _claimGift();
  }

  Future<void> _claimGift() async {
    final gift = await _profile.claimGift();
    if (!mounted || gift == null) return;
    await showDailyGiftDialog(context, gift);
  }

  // ── View transform ────────────────────────────────────────────────────────

  /// Scales and centres the board so all of it is on screen — the one job of
  /// the floating button, and what runs automatically on every new board.
  void _fitBoard({bool animate = true}) {
    final viewport = _viewport;
    final content = _content;
    if (viewport == null || content == null) return;
    if (content.width <= 0 || content.height <= 0) return;

    // Leave a sliver of margin so the board's glow is not clipped.
    final scale = math.min(
      viewport.width * 0.98 / content.width,
      viewport.height * 0.98 / content.height,
    );
    final s = scale.clamp(0.1, 1.0);
    final target = Matrix4.identity()
      ..translateByDouble(
        (viewport.width - content.width * s) / 2,
        (viewport.height - content.height * s) / 2,
        0,
        1,
      )
      ..scaleByDouble(s, s, 1, 1);

    if (!animate) {
      _zoomController.stop();
      _zoom.value = target;
      return;
    }
    _zoomAnim = Matrix4Tween(begin: _zoom.value, end: target).animate(
      CurvedAnimation(parent: _zoomController, curve: Curves.easeOutCubic),
    );
    _zoomController.forward(from: 0);
  }

  // ── Tap logic ─────────────────────────────────────────────────────────────

  /// Walks the exit ray of [piece], reporting the first arrow in the way (if
  /// any) and how many empty cells sit before it.
  ({ArrowPiece? blocker, int freeCells}) _lookAhead(ArrowPiece piece) {
    final board = _board!;
    final owner = <int, ArrowPiece>{};
    for (final other in board.pieces) {
      // Arrows already flying out no longer block anyone.
      if (other.removed || other.id == piece.id) continue;
      if (_flights.containsKey(other.id)) continue;
      for (final cell in other.cells) {
        owner[cell.dy.toInt() * board.columns + cell.dx.toInt()] = other;
      }
    }

    final step = piece.direction.step;
    var cursor = piece.head + step;
    var free = 0;

    while (cursor.dx >= 0 &&
        cursor.dy >= 0 &&
        cursor.dx < board.columns &&
        cursor.dy < board.rows) {
      final other = owner[cursor.dy.toInt() * board.columns + cursor.dx.toInt()];
      if (other != null) return (blocker: other, freeCells: free);
      free++;
      cursor += step;
    }
    return (blocker: null, freeCells: free);
  }

  /// Every piece the flight route of [piece] passes over, with the distance
  /// (in cells travelled from [piece]'s head) at which the route first touches
  /// it — sorted nearest-first.
  ///
  /// This walks the exact same route the painter draws, so what the player
  /// sees being run over is what fires: the black arrow's straight line, the
  /// rainbow's lap of the boundary, the ghost's zigzag.
  List<({ArrowPiece piece, int distance})> _piecesOnPath(ArrowPiece piece) {
    final board = _board!;
    final owner = <int, ArrowPiece>{};
    for (final other in board.pieces) {
      if (other.removed || other.id == piece.id) continue;
      if (_flights.containsKey(other.id)) continue;
      for (final cell in other.cells) {
        owner[cell.dy.toInt() * board.columns + cell.dx.toInt()] = other;
      }
    }

    final route = _flightPath(piece).route;
    final body = piece.cells.length - 1;
    final hit = <int, ({ArrowPiece piece, int distance})>{};
    for (var i = piece.cells.length; i < route.length; i++) {
      final cell = route[i];
      if (cell.dx < 0 ||
          cell.dy < 0 ||
          cell.dx >= board.columns ||
          cell.dy >= board.rows) {
        continue;
      }
      final other = owner[cell.dy.toInt() * board.columns + cell.dx.toInt()];
      if (other != null && !hit.containsKey(other.id)) {
        hit[other.id] = (piece: other, distance: i - body);
      }
    }
    return hit.values.toList()
      ..sort((a, b) => a.distance.compareTo(b.distance));
  }

  /// The bomb does not clear a line, it clears an area: everything within
  /// [_blastRadius] cells of any part of its body.
  static const _blastRadius = 2;

  List<({ArrowPiece piece, int distance})> _piecesInBlast(ArrowPiece piece) {
    final board = _board!;
    final hits = <({ArrowPiece piece, int distance})>[];
    for (final other in board.pieces) {
      if (other.removed || other.id == piece.id) continue;
      if (_flights.containsKey(other.id)) continue;
      var nearest = 1 << 20;
      for (final a in other.cells) {
        for (final b in piece.cells) {
          final d = ((a.dx - b.dx).abs() + (a.dy - b.dy).abs()).toInt();
          if (d < nearest) nearest = d;
        }
      }
      if (nearest <= _blastRadius) {
        hits.add((piece: other, distance: math.max(1, nearest)));
      }
    }
    return hits..sort((a, b) => a.distance.compareTo(b.distance));
  }

  /// The route this arrow flies, built exactly as the painter builds it.
  FlightPath _flightPath(ArrowPiece piece) {
    final board = _board!;
    return buildFlightPath(
      piece,
      columns: board.columns,
      rows: board.rows,
      overshootCells: _overshootCells,
      mask: board.mask,
    );
  }

  Future<void> _tapPiece(ArrowPiece piece) async {
    if (_convertMode) {
      await _convertToSpecial(piece);
      return;
    }
    if (_flights.containsKey(piece.id) || piece.removed) return;

    if (_hintPieceId == piece.id) {
      _hintTimer?.cancel();
      setState(() => _hintPieceId = null);
      _syncPulse();
    }

    if (piece.special) {
      // Boost arrow: fires any time — no blocked check. Arrows on its ray
      // fire one by one, each at the moment the boost's head reaches it —
      // the nearest first, farther ones later.
      final targets = piece.kind == ArrowKind.bomb
          ? _piecesInBlast(piece)
          : _piecesOnPath(piece);
      final travel = _flightPath(piece).travel;
      final fired = <int>{};
      _firePiece(
        piece,
        onProgress: (controller) {
          final advance =
              travel * Curves.easeInOutQuart.transform(controller.value);
          for (final target in targets) {
            if (fired.contains(target.piece.id)) continue;
            if (advance < target.distance) break; // sorted nearest-first
            fired.add(target.piece.id);
            _firePiece(target.piece);
          }
        },
      );
      return;
    }

    final ahead = _lookAhead(piece);
    if (ahead.blocker != null) {
      setState(() {
        _lives--;
        _bumpPieceId = piece.id;
        _bumpBlockerId = ahead.blocker!.id;
        _bumpStep = piece.direction.step;
        // Travel the empty run, plus a little extra so the tip visibly
        // presses against the blocker.
        _bumpCells = math.min(ahead.freeCells + 0.35, 2.2);
      });
      _bumpController.forward(from: 0);
      SoundService.instance.playMiss();
      _snack('🚧', 'Blocked! Move the arrow in the way first.');

      if (_lives <= 0) await _outOfLives();
      return;
    }

    _firePiece(piece);
  }

  Future<void> _outOfLives() async {
    // The miss thud lands first, then the game-over sting under the dialog.
    await Future<void>.delayed(const Duration(milliseconds: 400));
    if (!mounted) return;
    SoundService.instance.playGameOver();
    final choice = await showOutOfLivesDialog(
      context,
      adReady: AdsService.instance.rewardedReady,
    );
    if (!mounted) return;
    if (choice == GameChoice.watchAd) {
      final earned = await AdsService.instance.showRewarded();
      if (!mounted) return;
      if (earned) {
        setState(() => _lives = 3);
        return;
      }
    }
    await _newBoard();
  }

  /// Launches [piece]: its own sound, its own animation controller — so any
  /// number of arrows can be in flight at once, each completing fully.
  /// [onProgress] is called every animation tick (used by the boost arrow to
  /// fire the arrows it touches along the way).
  Future<void> _firePiece(
    ArrowPiece piece, {
    void Function(AnimationController)? onProgress,
  }) async {
    if (_flights.containsKey(piece.id) || piece.removed) return;

    SoundService.instance.playFire(piece);

    // A straight shot is always 900 ms; the arrows that take the long way
    // round get time proportional to the distance they cover, so they read as
    // travelling rather than teleporting.
    final travel = _flightPath(piece).travel;
    final duration = switch (piece.kind) {
      ArrowKind.rainbow || ArrowKind.ghost => Duration(
        milliseconds: (420 + travel * 26).clamp(900, 2800).round(),
      ),
      _ => const Duration(milliseconds: 900),
    };

    final controller = AnimationController(vsync: this, duration: duration);
    // No setState per tick: the painter listens to flight controllers
    // directly, so animation frames repaint only the canvas instead of
    // rebuilding the whole widget tree.
    if (onProgress != null) {
      controller.addListener(() => onProgress(controller));
    }
    setState(() => _flights[piece.id] = controller);

    await controller.forward();
    if (!mounted) {
      controller.dispose();
      return;
    }

    setState(() {
      piece.removed = true;
      _flights.remove(piece.id);
      _undoStack.add(piece.id);
    });
    // Dispose after the rebuild has detached the painter from it.
    WidgetsBinding.instance.addPostFrameCallback((_) => controller.dispose());

    final board = _board;
    if (board == null) return;

    // Save once the volley has landed, not on every single arrow; the
    // widget-PNG render only happens on wins (and new boards / app pause).
    if (_flights.isEmpty) {
      unawaited(GameStore.save(board, pushWidget: board.won));
    }

    if (board.won && _flights.isEmpty) {
      await Future<void>.delayed(const Duration(milliseconds: 260));
      if (mounted) await _onLevelCleared(board);
    }
  }

  Future<void> _onLevelCleared(BoardData board) async {
    final lifeBonus = _lives * 8;
    final reward = 20 + board.level * 2 + lifeBonus;
    await _profile.addCoins(reward);
    await _profile.recordLevel(board.level);
    if (!mounted) return;

    final choice = await showWinDialog(
      context,
      level: board.level,
      coinsEarned: reward,
      lifeBonus: lifeBonus,
    );
    if (!mounted) return;

    // One interstitial per five finished games — never mid-game.
    await AdsService.instance.onGameFinished();
    if (!mounted) return;

    await _newBoard(
      level: choice == GameChoice.newBoard ? board.level : board.level + 1,
      countClear: true,
    );
  }

  // ── Power-ups ─────────────────────────────────────────────────────────────

  Future<void> _useHint() async {
    final board = _board;
    if (board == null || _generating) return;
    if (!await _profile.useHint()) {
      // Out of hints: buy one with coins if they are there, otherwise the
      // rewards sheet has a video that gives one away.
      if (!await _buyThen(PlayerProfile.hintPrice, _profile.addHints)) return;
      if (!await _profile.useHint()) return;
    }
    ArrowPiece? target;
    for (final piece in board.pieces) {
      if (piece.removed || _flights.containsKey(piece.id)) continue;
      if (piece.special ||
          !LevelFactory.isBlocked(
            piece,
            board.pieces,
            board.columns,
            board.rows,
          )) {
        target = piece;
        break;
      }
    }
    if (!mounted) return;
    if (target == null) {
      _snack('🤔', 'No arrow can fire — try a black arrow or a new board.');
      return;
    }
    setState(() => _hintPieceId = target!.id);
    _syncPulse();
    _hintTimer?.cancel();
    _hintTimer = Timer(const Duration(seconds: 5), () {
      if (!mounted) return;
      setState(() => _hintPieceId = null);
      _syncPulse();
    });
  }

  Future<void> _useUndo() async {
    final board = _board;
    if (board == null || _generating) return;
    if (_undoStack.isEmpty) {
      _snack('↩️', 'Nothing to undo yet.');
      return;
    }
    if (!await _profile.useUndo()) {
      if (!await _buyThen(PlayerProfile.undoPrice, _profile.addUndos)) return;
      if (!await _profile.useUndo()) return;
    }
    final id = _undoStack.removeLast();
    final piece = board.pieces.firstWhere((p) => p.id == id);
    if (!mounted) return;
    setState(() {
      piece.removed = false;
      if (_lives < _maxLives) _lives++;
    });
    unawaited(GameStore.save(board, pushWidget: false));
  }

  /// Tapping a special on the power row. Owning one arms it; owning none
  /// buys one on the spot if the coins are there, and otherwise opens the
  /// tray, where a video will earn it for free.
  Future<void> _tapSpecial(ArrowKind kind) async {
    if (_generating) return;

    // Tap the armed one again to put it away.
    if (_convertKind == kind) {
      setState(() => _convertKind = null);
      _syncPulse();
      return;
    }

    if (_profile.stockOf(kind) <= 0) {
      if (!_profile.canAfford(kind.price)) {
        final picked = await showArrowPicker(context);
        if (!mounted || picked == null) return;
        if (_profile.stockOf(picked) <= 0) return;
        setState(() => _convertKind = picked);
        _syncPulse();
        _snack(
          _kindEmoji(picked),
          'Tap any arrow to turn it into a ${picked.label.toLowerCase()}.',
        );
        return;
      }
      if (!await _profile.spend(kind.price)) return;
      await _profile.addArrows(kind, 1);
      if (!mounted) return;
    }

    setState(() => _convertKind = kind);
    _syncPulse();
    _snack(
      _kindEmoji(kind),
      'Tap any arrow to turn it into a ${kind.label.toLowerCase()}.',
    );
  }

  Future<void> _convertToSpecial(ArrowPiece piece) async {
    final board = _board;
    final kind = _convertKind;
    if (board == null || kind == null) return;

    void disarm() {
      setState(() => _convertKind = null);
      _syncPulse();
    }

    if (piece.special || piece.removed) {
      disarm();
      return;
    }
    if (!await _profile.useArrow(kind)) {
      if (!mounted) return;
      disarm();
      return;
    }
    if (!mounted) return;
    setState(() {
      piece.kind = kind;
      _convertKind = null;
    });
    _syncPulse();
    unawaited(GameStore.save(board, pushWidget: false));
    _snack(
      _kindEmoji(kind),
      '${kind.label} ready — ${kind.blurb.toLowerCase()}.',
    );
  }

  static String _kindEmoji(ArrowKind kind) => switch (kind) {
    ArrowKind.rainbow => '🌈',
    ArrowKind.ghost => '👻',
    ArrowKind.bomb => '💣',
    _ => '🖤',
  };

  /// Buys one of something with coins. Falls back to the rewards sheet when
  /// the player cannot afford it, and reports whether they now own one.
  Future<bool> _buyThen(int price, Future<void> Function(int) give) async {
    if (!await _profile.spend(price)) {
      if (mounted) await showShopSheet(context);
      return false;
    }
    await give(1);
    return true;
  }

  void _snack(String emoji, String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: GameTheme.card,
          elevation: 6,
          duration: const Duration(milliseconds: 1400),
          margin: const EdgeInsets.fromLTRB(24, 0, 24, 20),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: BorderSide(
              color: GameTheme.lilac.withValues(alpha: 0.5),
              width: 1.4,
            ),
          ),
          content: Row(
            children: [
              Text(emoji, style: const TextStyle(fontSize: 18)),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  message,
                  style: GameTheme.font(
                    color: GameTheme.ink,
                    fontWeight: FontWeight.w600,
                    fontSize: 12.5,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
  }

  // ── Settings ──────────────────────────────────────────────────────────────

  Future<void> _toggleSound() async {
    await _profile.setSound(!_profile.soundOn);
    if (mounted) setState(() {});
  }

  Future<void> _toggleTheme() async {
    await _profile.setDark(!_profile.dark);
    GameTheme.dark = _profile.dark;
    if (mounted) setState(() {});
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final board = _board;
    if (board == null) {
      return Scaffold(
        backgroundColor: GameTheme.bgTop,
        body: LoadingScreen(message: 'Loading your board…', tip: _tip),
      );
    }

    return Scaffold(
      backgroundColor: GameTheme.bgTop,
      extendBodyBehindAppBar: true,
      // The body runs all the way to the bottom edge of the screen, so the
      // banner can sit flush against it with nothing underneath.
      extendBody: true,
      appBar: _appBar(board),
      body: NeonBackground(
        // The banner sits outside the safe area on purpose: it is pinned to
        // the very bottom edge of the screen, and everything else keeps its
        // inset above it.
        child: Column(
          children: [
            Expanded(
              child: SafeArea(
                bottom: false,
                child: Column(
                  children: [
                    _hud(board),
                    Expanded(child: _boardArea(board)),
                    _powerBar(),
                  ],
                ),
              ),
            ),
            const BannerAdSlot(),
          ],
        ),
      ),
    );
  }

  PreferredSizeWidget _appBar(BoardData board) {
    return AppBar(
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      systemOverlayStyle: GameTheme.dark
          ? SystemUiOverlayStyle.light
          : SystemUiOverlayStyle.dark,
      centerTitle: true,
      leadingWidth: 86,
      leading: Center(
        child: NeonPill(
          glow: GameTheme.gold,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('⭐', style: TextStyle(fontSize: 13)),
              const SizedBox(width: 4),
              Text(
                '${board.cleared}',
                style: GameTheme.font(
                  color: GameTheme.ink,
                  fontWeight: FontWeight.w900,
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
      ),
      title: NeonPill(
        glow: GameTheme.accent,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
        child: Text(
          'LEVEL ${board.level}',
          style: GameTheme.font(
            color: GameTheme.accentDeep,
            fontWeight: FontWeight.w900,
            fontSize: 15,
            letterSpacing: 2.4,
          ),
        ),
      ),
      actions: [
        Padding(
          padding: const EdgeInsets.only(right: 10),
          child: PopupMenuButton<String>(
            tooltip: 'Menu',
            offset: const Offset(0, 52),
            color: GameTheme.card,
            elevation: 10,
            shadowColor: GameTheme.cardShadow,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
            ),
            onSelected: (value) {
              switch (value) {
                case 'theme':
                  _toggleTheme();
                case 'sound':
                  _toggleSound();
                case 'new':
                  _newBoard();
                case 'shop':
                  showShopSheet(context);
                case 'notify':
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const NotifyGallery(),
                    ),
                  );
              }
            },
            itemBuilder: (context) => [
              _menuItem(
                'theme',
                GameTheme.dark
                    ? Icons.light_mode_rounded
                    : Icons.dark_mode_rounded,
                GameTheme.dark ? 'Light Theme' : 'Dark Theme',
                GameTheme.lilac,
              ),
              const PopupMenuDivider(height: 1),
              _menuItem(
                'sound',
                _profile.soundOn
                    ? Icons.volume_off_rounded
                    : Icons.volume_up_rounded,
                _profile.soundOn ? 'Sound Off' : 'Sound On',
                GameTheme.accent,
              ),
              const PopupMenuDivider(height: 1),
              _menuItem(
                'shop',
                Icons.card_giftcard_rounded,
                'Rewards',
                GameTheme.gold,
              ),
              const PopupMenuDivider(height: 1),
              _menuItem(
                'notify',
                Icons.notifications_active_rounded,
                'Notification kit',
                GameTheme.lilac,
              ),
              const PopupMenuDivider(height: 1),
              _menuItem(
                'new',
                Icons.refresh_rounded,
                'New Board',
                GameTheme.accentDeep,
              ),
            ],
            child: Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: GameTheme.card,
                shape: BoxShape.circle,
                border: Border.all(
                  color: GameTheme.accent.withValues(alpha: 0.45),
                  width: 1.2,
                ),
                boxShadow: [
                  BoxShadow(
                    color: GameTheme.accent.withValues(alpha: 0.3),
                    blurRadius: 14,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: const Icon(
                Icons.more_vert_rounded,
                color: GameTheme.accent,
                size: 22,
              ),
            ),
          ),
        ),
      ],
    );
  }

  PopupMenuItem<String> _menuItem(
    String value,
    IconData icon,
    String label,
    Color color,
  ) {
    return PopupMenuItem<String>(
      value: value,
      height: 46,
      child: Row(
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 17, color: color),
          ),
          const SizedBox(width: 12),
          Text(
            label,
            style: GameTheme.font(
              color: GameTheme.ink,
              fontWeight: FontWeight.w700,
              fontSize: 13.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _hud(BoardData board) {
    return ListenableBuilder(
      listenable: _profile,
      builder: (context, _) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
        child: Row(
          children: [
            NeonPill(
              glow: GameTheme.coin,
              onTap: () => showShopSheet(context),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.monetization_on_rounded,
                    color: GameTheme.coin,
                    size: 16,
                  ),
                  const SizedBox(width: 6),
                  // Coins count up to their new total: a reward you watch
                  // arrive is worth more than one that is simply there.
                  TweenAnimationBuilder<double>(
                    tween: Tween(end: _profile.coins.toDouble()),
                    duration: const Duration(milliseconds: 600),
                    curve: Curves.easeOutCubic,
                    builder: (context, value, _) => Text(
                      '${value.round()}',
                      style: GameTheme.font(
                        color: GameTheme.ink,
                        fontWeight: FontWeight.w900,
                        fontSize: 13,
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(Icons.add_rounded, color: GameTheme.coin, size: 14),
                ],
              ),
            ),
            if (_profile.canClaimGift) ...[
              const SizedBox(width: 8),
              NeonPill(
                glow: GameTheme.gold,
                onTap: _claimGift,
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
                child: const Text('🎁', style: TextStyle(fontSize: 15)),
              ),
            ],
            const Spacer(),
            ...List.generate(_maxLives, (i) {
              final alive = i < _lives;
              return AnimatedScale(
                duration: const Duration(milliseconds: 260),
                scale: alive ? 1.0 : 0.8,
                child: Padding(
                  padding: const EdgeInsets.only(left: 3),
                  child: Icon(
                    alive
                        ? Icons.favorite_rounded
                        : Icons.favorite_border_rounded,
                    color: alive
                        ? GameTheme.heart
                        : GameTheme.heart.withValues(alpha: 0.28),
                    size: 20,
                  ),
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _boardArea(BoardData board) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 0),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final fitCell = math.min(
            (constraints.maxWidth - _boardPad * 2) / board.columns,
            (constraints.maxHeight - _boardPad * 2) / board.rows,
          );
          final cell = fitCell < _minCell
              ? _minCell
              // tiny early levels shouldn't fill the screen
              : math.min(fitCell, _maxCell);

          // Enough extra cells that a flying arrow clears the whole screen,
          // not just the board card.
          _overshootCells =
              ((constraints.maxWidth + constraints.maxHeight) / cell).ceil();

          final boardSize = Size(cell * board.columns, cell * board.rows);
          _viewport = constraints.biggest;
          _content = Size(
            boardSize.width + _boardPad * 2,
            boardSize.height + _boardPad * 2,
          );

          if (_needsFit) {
            _needsFit = false;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) _fitBoard(animate: false);
            });
          }

          return Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned.fill(
                child: ClipRect(
                  child: InteractiveViewer(
                    transformationController: _zoom,
                    // Free movement: pinch to zoom, drag to pan, anywhere.
                    // The fit button is what brings the board back.
                    constrained: false,
                    boundaryMargin: const EdgeInsets.all(double.infinity),
                    minScale: 0.12,
                    maxScale: 6,
                    child: AnimatedBuilder(
                      animation: _introController,
                      builder: (context, child) {
                        final t = _introController.value;
                        return Opacity(
                          opacity: Curves.easeOut.transform(t),
                          child: Transform.scale(
                            scale:
                                0.93 +
                                0.07 * Curves.easeOutBack.transform(t),
                            child: child,
                          ),
                        );
                      },
                      child: _boardCard(board, boardSize, cell),
                    ),
                  ),
                ),
              ),

              // Building-next-level loader
              if (_generating)
                Positioned.fill(
                  child: ColoredBox(
                    color: Colors.black.withValues(alpha: 0.55),
                    child: Center(
                      child: LoadingScreen(
                        compact: true,
                        message: 'Building level ${board.level}…',
                        tip: _tip,
                      ),
                    ),
                  ),
                ),

              // The one board control: snap everything back into view.
              Positioned(
                right: 4,
                bottom: 4,
                child: FloatingActionButton(
                  heroTag: 'fit',
                  mini: true,
                  backgroundColor: GameTheme.card,
                  foregroundColor: GameTheme.accent,
                  elevation: 8,
                  shape: CircleBorder(
                    side: BorderSide(
                      color: GameTheme.accent.withValues(alpha: 0.55),
                      width: 1.4,
                    ),
                  ),
                  tooltip: 'Fit board to screen',
                  onPressed: _fitBoard,
                  child: const Icon(Icons.center_focus_strong_rounded),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _boardCard(BoardData board, Size boardSize, double cell) {
    return Container(
      padding: const EdgeInsets.all(_boardPad),
      decoration: BoxDecoration(
        gradient: const RadialGradient(
          center: Alignment(-0.2, -0.4),
          radius: 1.1,
          colors: [GameTheme.boardFill, GameTheme.boardFillDeep],
        ),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(
          color: GameTheme.boardEdge.withValues(alpha: 0.85),
          width: 2.4,
        ),
        boxShadow: const [
          BoxShadow(color: GameTheme.boardGlow, blurRadius: 30, spreadRadius: 1),
        ],
      ),
      child: SizedBox.fromSize(
        size: boardSize,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapUp: (details) {
            final piece = _pieceAt(details.localPosition, cell);
            if (piece != null) _tapPiece(piece);
          },
          child: CustomPaint(
            size: boardSize,
            painter: GamePainter(
              columns: board.columns,
              rows: board.rows,
              pieces: board.pieces,
              palette: board.palette,
              mask: board.mask,
              flights: Map.of(_flights),
              overshootCells: _overshootCells,
              bumpPieceId: _bumpPieceId,
              bumpBlockerId: _bumpBlockerId,
              bumpStep: _bumpStep,
              bumpCells: _bumpCells,
              bump: _bumpAnim,
              hintPieceId: _hintPieceId,
              pulse: _pulsing ? _pulseController : null,
              convertMode: _convertMode,
            ),
          ),
        ),
      ),
    );
  }

  Widget _powerBar() {
    return ListenableBuilder(
      listenable: _profile,
      builder: (context, _) => Padding(
        padding: const EdgeInsets.fromLTRB(10, 12, 10, 6),
        child: PowerRow(
          items: [
            PowerItem(
              icon: Icons.lightbulb_rounded,
              color: GameTheme.lilac,
              label: 'Hint',
              owned: _profile.hints,
              price: PlayerProfile.hintPrice,
              onTap: _useHint,
            ),
            PowerItem(
              icon: Icons.undo_rounded,
              color: GameTheme.accent,
              label: 'Undo',
              owned: _profile.undos,
              price: PlayerProfile.undoPrice,
              onTap: _useUndo,
            ),
            for (final kind in ArrowKind.buyable)
              PowerItem(
                icon: kind.icon,
                color: kind.tint,
                label: _shortLabel(kind),
                owned: _profile.stockOf(kind),
                price: kind.price,
                armed: _convertKind == kind,
                onTap: () => _tapSpecial(kind),
              ),
            PowerItem(
              icon: Icons.card_giftcard_rounded,
              color: GameTheme.coin,
              label: 'Rewards',
              badge: _profile.canClaimGift ? 'GIFT' : null,
              onTap: () => showShopSheet(context),
            ),
          ],
        ),
      ),
    );
  }

  /// One word per arrow, because seven circles have to share a phone width.
  static String _shortLabel(ArrowKind kind) => switch (kind) {
    ArrowKind.boost => 'Black',
    ArrowKind.rainbow => 'Rainbow',
    ArrowKind.ghost => 'Ghost',
    ArrowKind.bomb => 'Bomb',
    ArrowKind.normal => 'Arrow',
  };

  ArrowPiece? _pieceAt(Offset point, double cell) {
    final board = _board;
    if (board == null) return null;
    final active = board.pieces.where((e) => !e.removed).toList().reversed;
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
