import 'package:flutter/material.dart';
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
      title: 'Arrow Escape',
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
