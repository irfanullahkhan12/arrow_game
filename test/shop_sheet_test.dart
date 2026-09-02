import 'package:arowgame/main.dart';
import 'package:arowgame/ui/widgets/shop_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    // Start with nothing owned, so a stock badge can only come from a buy.
    SharedPreferences.setMockInitialValues({
      'p_coins': 500,
      'p_hints': 0,
      'p_undos': 0,
    });
    await PlayerProfile.instance.load();
  });

  Future<void> openSheet(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2160);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showShopSheet(context),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('the sheet leads with the balance and the store', (
    tester,
  ) async {
    await openSheet(tester);

    expect(find.text('Rewards'), findsOneWidget);
    expect(find.text('500'), findsOneWidget);

    // Both real-money products, at their fallback prices.
    expect(find.text('No Ads'), findsOneWidget);
    expect(find.text(r'$9.99'), findsOneWidget);
    expect(find.text('${IapService.coinPackAmount} Coins'), findsOneWidget);
    expect(find.text(r'$4.99'), findsOneWidget);
    expect(find.text('Restore'), findsOneWidget);

    // Power-ups are one word and a price, not a paragraph.
    expect(find.text('Hint'), findsOneWidget);
    expect(find.text('Undo'), findsOneWidget);
    expect(find.text('${PlayerProfile.hintPrice}'), findsOneWidget);
    expect(find.text('${PlayerProfile.undoPrice}'), findsOneWidget);

    // Special arrows live in their own tray; the sheet does not repeat them.
    for (final kind in ArrowKind.buyable) {
      expect(find.text(kind.label), findsNothing);
      expect(find.text(kind.blurb), findsNothing);
    }
  });

  testWidgets('buying a hint costs exactly its price', (tester) async {
    await openSheet(tester);

    await tester.tap(find.text('Hint'));
    await tester.pumpAndSettle();

    expect(PlayerProfile.instance.hints, 1);
    expect(PlayerProfile.instance.coins, 500 - PlayerProfile.hintPrice);
    // The tile now shows the stock next to the name.
    expect(find.text('×1'), findsOneWidget);
    expect(PlayerProfile.instance.undos, 0);
  });

  testWidgets('a purchase the player cannot afford is refused', (tester) async {
    await PlayerProfile.instance.addCoins(-480); // leaves 20
    await openSheet(tester);

    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();

    expect(PlayerProfile.instance.coins, 20);
    expect(find.textContaining('Not enough coins'), findsOneWidget);
  });

  testWidgets('with no store key the paid rows say so and charge nothing', (
    tester,
  ) async {
    await openSheet(tester);
    final coins = PlayerProfile.instance.coins;

    await tester.tap(find.text(r'$4.99'));
    await tester.pumpAndSettle();

    expect(PlayerProfile.instance.coins, coins);
    expect(find.textContaining('not available'), findsOneWidget);
  });
}
