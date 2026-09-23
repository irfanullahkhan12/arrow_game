import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:home_widget/home_widget.dart';

import 'services/game_store.dart';
import 'theme/game_theme.dart';
import 'ui/game_page.dart';

// The game is split across `models/`, `game/`, `services/`, `ui/` and
// `theme/`. These re-exports keep `package:arowgame/main.dart` the one import
// anything outside `lib/` (tests, tooling) needs.
export 'game/ai_designer.dart';
export 'game/flight_path.dart';
export 'game/level_factory.dart';
export 'models/arrow_kind.dart';
export 'models/arrow_piece.dart';
export 'models/board_data.dart';
export 'models/board_shape.dart';
export 'models/board_style.dart';
export 'models/palette.dart';
export 'models/shape_math.dart';
export 'models/silhouette.dart';
export 'services/ads_service.dart';
export 'services/game_store.dart';
export 'services/iap_service.dart';
export 'services/player_profile.dart';
export 'theme/game_theme.dart';
export 'ui/game_page.dart';
export 'ui/arrow_art.dart';
export 'ui/game_painter.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Android 15 lays every app out edge to edge whether it asked to or not, so
  // ask to: this is Flutter's half of `enableEdgeToEdge()`, and saying it out
  // loud is what gives the phones still on Android 10-14 the same layout
  // instead of two different ones to test. The bars are left transparent —
  // the neon backdrop is meant to run under them — and every inset they cover
  // is paid back by the SafeArea inside the page and by the banner below it.
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(GameTheme.systemBars);
  HomeWidget.registerInteractivityCallback(widgetBackgroundCallback);
  // Ads and the store are started from the game page's boot, in that order:
  // what the player has already paid for decides whether ads run at all.
  runApp(const ArrowEscapeApp());
}

class ArrowEscapeApp extends StatelessWidget {
  const ArrowEscapeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Arrows Neon',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: GameTheme.accent,
          brightness: Brightness.dark,
        ),
        scaffoldBackgroundColor: GameTheme.bgTop,
        useMaterial3: true,
        // Google Font "Unbounded" via the google_fonts package.
        textTheme: GoogleFonts.unboundedTextTheme(
          ThemeData(brightness: Brightness.dark).textTheme,
        ),
      ),
      home: const GamePage(),
    );
  }
}
