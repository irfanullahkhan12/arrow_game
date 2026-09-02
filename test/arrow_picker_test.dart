import 'package:arowgame/main.dart';
import 'package:arowgame/ui/widgets/arrow_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() async {
    // No network in a test: fall back to the bundled font silently.
    GoogleFonts.config.allowRuntimeFetching = false;
    SharedPreferences.setMockInitialValues({
      'p_coins': 500,
      ArrowKind.boost.prefsKey: 1,
      ArrowKind.rainbow.prefsKey: 0,
      ArrowKind.ghost.prefsKey: 0,
      ArrowKind.bomb.prefsKey: 0,
    });
    await PlayerProfile.instance.load();
  });

  Future<void> openPicker(WidgetTester tester) async {
    // A phone-shaped surface: the tray is a two-column grid and the default
    // 800×600 test window is nothing like the screen it ships on.
    tester.view.physicalSize = const Size(1080, 2160);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showArrowPicker(context),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  /// Taps the price button on [kind]'s tile, scrolling it into view first.
  Future<void> tapPrice(WidgetTester tester, ArrowKind kind) async {
    final button = find.widgetWithText(InkWell, '${kind.price}').first;
    await tester.ensureVisible(button);
    await tester.pumpAndSettle();
    await tester.tap(button);
    await tester.pumpAndSettle();
  }

  testWidgets('the tray is a grid of every special', (tester) async {
    await openPicker(tester);

    expect(find.byType(GridView), findsOneWidget);
    for (final kind in ArrowKind.buyable) {
      expect(find.text(kind.label), findsOneWidget);
      // Each tile paints the real arrow it is selling.
      expect(
        find.byWidgetPredicate((w) => w is ArrowPreview && w.kind == kind),
        findsOneWidget,
      );
    }
    // Owned arrows offer USE; the rest show what they cost.
    expect(find.text('USE'), findsOneWidget);
    expect(find.text('${ArrowKind.rainbow.price}'), findsWidgets);
    expect(find.text('${ArrowKind.bomb.price}'), findsWidgets);
  });

  testWidgets('picking an owned arrow arms it', (tester) async {
    await openPicker(tester);
    await tester.tap(find.text('USE'));
    await tester.pumpAndSettle();

    // The sheet closed; the stock is only spent once it is placed on a piece.
    expect(find.text(ArrowKind.boost.label), findsNothing);
    expect(PlayerProfile.instance.stockOf(ArrowKind.boost), 1);
  });

  testWidgets('buying with coins adds one to the stock', (tester) async {
    await openPicker(tester);
    await tapPrice(tester, ArrowKind.bomb);

    final profile = PlayerProfile.instance;
    expect(profile.stockOf(ArrowKind.bomb), 1);
    expect(profile.coins, 500 - ArrowKind.bomb.price);
    // Now that it is owned, it offers USE too.
    expect(find.text('USE'), findsNWidgets(2));
  });

  testWidgets('an arrow the player cannot afford is refused', (tester) async {
    await PlayerProfile.instance.addCoins(-460); // leaves 40
    await openPicker(tester);
    await tapPrice(tester, ArrowKind.ghost);

    expect(PlayerProfile.instance.stockOf(ArrowKind.ghost), 0);
    expect(PlayerProfile.instance.coins, 40);
    expect(find.textContaining('Not enough coins'), findsOneWidget);
  });
}
