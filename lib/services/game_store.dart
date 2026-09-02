import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:home_widget/home_widget.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../game/level_factory.dart';
import '../models/board_data.dart';
import '../theme/game_theme.dart';
import '../ui/game_painter.dart';

class GameStore {
  static const _stateKey = 'board_state';
  static const _widgetProvider = 'ArrowWidgetProvider';

  /// Boards finished from inside the home-screen widget, waiting to be
  /// counted the next time the app is opened. See [takeWidgetGames].
  static const widgetGamesKey = 'widget_games';

  /// The widget renders at this width. Small enough that the PNG stays well
  /// inside the RemoteViews bitmap budget with nothing left to rescale on the
  /// Android side.
  static const widgetBoardWidth = 520.0;

  static Future<BoardData?> load() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload(); // the widget isolate may have written newer state
    final raw = prefs.getString(_stateKey);
    if (raw == null) return null;
    return BoardData.fromJson(raw);
  }

  /// [pushWidget] renders the board to a PNG for the home-screen widget —
  /// that is expensive, so mid-game saves skip it and only board changes,
  /// wins, and app-pause refresh the widget.
  static Future<void> save(BoardData board, {bool pushWidget = true}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_stateKey, board.toJson());
    if (pushWidget) await _pushWidget(board);
  }

  /// Renders the board to a PNG and hands it to the home-screen widget.
  ///
  /// The image goes to a **file**, and only its path is stored. Preferences
  /// are not a place for a few hundred kilobytes of base64: it was decoded on
  /// every widget refresh and re-read by the app on every `prefs.reload()`.
  static Future<void> _pushWidget(BoardData board) async {
    if (!Platform.isAndroid) return;
    try {
      final png = await renderBoardPng(board, width: widgetBoardWidth);
      final dir = await getApplicationSupportDirectory();
      final file = File('${dir.path}/widget_board.png');
      await file.writeAsBytes(png, flush: true);

      final left = board.pieces.where((p) => !p.removed).length;
      await HomeWidget.saveWidgetData('board_png_path', file.path);
      await HomeWidget.saveWidgetData('widget_level', 'LEVEL ${board.level}');
      await HomeWidget.saveWidgetData(
        'widget_status',
        left == 0 ? 'Cleared!' : '$left arrows left',
      );
      await HomeWidget.updateWidget(name: _widgetProvider);
    } catch (error, stack) {
      // Widget refresh must never break the game — but a silent failure here
      // is a widget that quietly shows a stale board forever, so say so while
      // developing.
      debugPrint('widget refresh failed: $error');
      debugPrint('$stack');
    }
  }

  /// How many boards the player finished from the widget since the app was
  /// last opened, resetting the counter as it reads it.
  static Future<int> takeWidgetGames() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final games = prefs.getInt(widgetGamesKey) ?? 0;
    if (games > 0) await prefs.setInt(widgetGamesKey, 0);
    return games;
  }
}

/// Draws a board into a PNG (used for the home-screen widget). Runs fine in
/// the widget's background isolate — no widget tree involved.
Future<Uint8List> renderBoardPng(BoardData board, {double width = 700}) async {
  final cell = width / board.columns;
  final size = Size(width, cell * board.rows);
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);

  canvas.drawRRect(
    RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(36)),
    Paint()..color = GameTheme.boardFill,
  );
  GamePainter(
    columns: board.columns,
    rows: board.rows,
    pieces: board.pieces,
    palette: board.palette,
    mask: board.mask,
    flights: const {},
    bumpPieceId: null,
    bumpBlockerId: null,
    bumpStep: Offset.zero,
    bumpCells: 0,
    bump: const AlwaysStoppedAnimation(0),
  ).paint(canvas, size);

  final image = await recorder
      .endRecording()
      .toImage(size.width.round(), size.height.round());
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  return bytes!.buffer.asUint8List();
}

// ─── Widget background callback ──────────────────────────────────────────────

/// Runs in a background isolate when the user presses a button on the
/// home-screen widget — the game is playable without opening the app.
@pragma('vm:entry-point')
Future<void> widgetBackgroundCallback(Uri? uri) async {
  if (uri == null) return;
  // This runs in its own isolate, which starts with no plugins attached —
  // without this, writing the board PNG would throw.
  ui.DartPluginRegistrant.ensureInitialized();

  var board = await GameStore.load();
  board ??= LevelFactory.generate(level: 1, generation: 0, cleared: 0);

  switch (uri.host) {
    case 'play':
      // Play one move: remove the first arrow with a clear exit.
      final free = board.pieces
          .where(
            (p) =>
                !p.removed &&
                !LevelFactory.isBlocked(
                  p,
                  board!.pieces,
                  board.columns,
                  board.rows,
                ),
          )
          .toList();
      if (free.isNotEmpty) {
        free.first.removed = true;
      }
      if (board.won) {
        // A board finished out here counts towards the interstitial the app
        // shows when it is next opened. An ad cannot be rendered in a widget:
        // there is no activity to host one, and AdMob's policy does not allow
        // ads outside the app's own screens.
        final prefs = await SharedPreferences.getInstance();
        await prefs.reload();
        await prefs.setInt(
          GameStore.widgetGamesKey,
          (prefs.getInt(GameStore.widgetGamesKey) ?? 0) + 1,
        );

        board = LevelFactory.generate(
          level: board.level + 1,
          generation: board.generation + 1,
          cleared: board.cleared + 1,
        );
      }
    case 'new':
      board = LevelFactory.generate(
        level: board.level,
        generation: board.generation + 1,
        cleared: board.cleared,
      );
  }

  await GameStore.save(board);
}
