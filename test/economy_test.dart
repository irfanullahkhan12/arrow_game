import 'package:arowgame/main.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The money side of the game: what things cost, what they pay, and what
/// happens when the store is not there. A wrong number here is a wrong number
/// in someone's wallet, so every one of them is pinned down.
void main() {
  final profile = PlayerProfile.instance;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await profile.load();
  });

  group('prices and payouts', () {
    test('the catalogue is what it claims to be', () {
      expect(ArrowKind.boost.price, 150);
      expect(ArrowKind.rainbow.price, 200);
      expect(ArrowKind.ghost.price, 200);
      expect(ArrowKind.bomb.price, 250);
      expect(PlayerProfile.hintPrice, 60);
      expect(PlayerProfile.undoPrice, 90);
      expect(PlayerProfile.adCoins, 50);
      expect(IapService.coinPackAmount, 2000);
      // Nothing is free, and nothing costs more than the paid pack buys.
      for (final kind in ArrowKind.buyable) {
        expect(kind.price, greaterThan(0));
        expect(kind.price, lessThan(IapService.coinPackAmount));
      }
    });

    test('the coin pack is worth a real number of arrows', () {
      // The $4.99 pack should feel generous: eight black arrows, not one.
      expect(IapService.coinPackAmount ~/ ArrowKind.boost.price, 13);
      expect(IapService.coinPackAmount ~/ ArrowKind.bomb.price, 8);
    });
  });

  group('spending', () {
    test('a purchase costs exactly its price', () async {
      await profile.addCoins(1000 - profile.coins);
      expect(profile.coins, 1000);

      expect(await profile.spend(ArrowKind.bomb.price), isTrue);
      expect(profile.coins, 750);
      await profile.addArrows(ArrowKind.bomb, 1);
      expect(profile.stockOf(ArrowKind.bomb), 1);
    });

    test('coins never go negative and a refused buy costs nothing', () async {
      await profile.addCoins(-profile.coins);
      await profile.addCoins(40);
      expect(profile.coins, 40);

      expect(await profile.spend(ArrowKind.ghost.price), isFalse);
      expect(profile.coins, 40);
      expect(profile.stockOf(ArrowKind.ghost), 0);

      // Even a nonsense adjustment cannot push the wallet below zero.
      await profile.addCoins(-9999);
      expect(profile.coins, 0);
    });

    test('an arrow is only spent when there is one to spend', () async {
      // A fresh install already hands a couple of specials over, so empty the
      // rainbow shelf before testing what an empty shelf does.
      while (profile.stockOf(ArrowKind.rainbow) > 0) {
        await profile.useArrow(ArrowKind.rainbow);
      }
      await profile.addArrows(ArrowKind.rainbow, 1);
      expect(await profile.useArrow(ArrowKind.rainbow), isTrue);
      expect(profile.stockOf(ArrowKind.rainbow), 0);
      expect(await profile.useArrow(ArrowKind.rainbow), isFalse);
      expect(profile.stockOf(ArrowKind.rainbow), 0);
    });

    test('everything the player owns survives a reload', () async {
      await profile.addCoins(777 - profile.coins);
      await profile.addArrows(ArrowKind.ghost, 3);
      await profile.addHints(2);

      final hints = profile.hints;
      await profile.load();

      expect(profile.coins, 777);
      expect(profile.stockOf(ArrowKind.ghost), 3);
      expect(profile.hints, hints);
    });
  });

  group('the free arrow drip', () {
    test('a fresh install starts with two specials', () {
      expect(profile.totalArrows, PlayerProfile.freeArrowGrant);
    });

    test('every tenth level hands over two more, up to eight', () async {
      // Levels 1-9 pay nothing; 10 pays out.
      for (var level = 1; level < PlayerProfile.freeArrowEvery; level++) {
        expect(await profile.recordLevel(level), 0);
      }
      expect(await profile.recordLevel(10), PlayerProfile.freeArrowGrant);
      expect(profile.totalArrows, 4);

      expect(await profile.recordLevel(20), PlayerProfile.freeArrowGrant);
      expect(await profile.recordLevel(30), PlayerProfile.freeArrowGrant);
      expect(profile.totalArrows, PlayerProfile.freeArrowCap);

      // At the cap the drip stops, however many levels go by.
      expect(await profile.recordLevel(40), 0);
      expect(await profile.recordLevel(50), 0);
      expect(profile.totalArrows, PlayerProfile.freeArrowCap);

      // Spend one and the next milestone tops it back up — but only to eight.
      await profile.useArrow(ArrowKind.boost);
      expect(await profile.recordLevel(60), 1);
      expect(profile.totalArrows, PlayerProfile.freeArrowCap);
    });

    test('a milestone is only ever paid once', () async {
      expect(await profile.recordLevel(10), PlayerProfile.freeArrowGrant);
      expect(await profile.recordLevel(10), 0);
      // Replaying an earlier level pays nothing either.
      expect(await profile.recordLevel(4), 0);
    });

    test('the drip walks the set instead of stacking one kind', () async {
      await profile.recordLevel(10);
      await profile.recordLevel(20);
      expect(profile.totalArrows, PlayerProfile.freeArrowCap - 2);
      for (final kind in ArrowKind.buyable) {
        expect(profile.stockOf(kind), greaterThan(0), reason: kind.name);
      }
    });

    test('what the drip handed over survives a reload', () async {
      await profile.recordLevel(10);
      final total = profile.totalArrows;
      await profile.load();
      expect(profile.totalArrows, total);
      // And the milestone is not paid a second time after the reload.
      expect(await profile.recordLevel(10), 0);
    });
  });

  group('the daily gift', () {
    test('pays more every day and caps out', () async {
      var previous = 0;
      for (var day = 1; day <= 10; day++) {
        final gift = await profile.claimGift();
        expect(gift, isNotNull, reason: 'day $day should pay out');
        expect(gift!.streak, day);
        expect(gift.coins, greaterThanOrEqualTo(previous));
        expect(gift.coins, lessThanOrEqualTo(200));
        previous = gift.coins;
        // Pretend a day went by.
        profile.lastGiftDay = PlayerProfileTestHook.yesterdayKey();
      }
    });

    test('cannot be claimed twice in one day', () async {
      expect(await profile.claimGift(), isNotNull);
      expect(profile.canClaimGift, isFalse);
      final coins = profile.coins;
      expect(await profile.claimGift(), isNull);
      expect(profile.coins, coins);
    });

    test('every third day hands over a special arrow', () async {
      final arrows = <ArrowKind>[];
      for (var day = 1; day <= 12; day++) {
        final gift = await profile.claimGift();
        if (gift?.arrow case final ArrowKind kind) arrows.add(kind);
        profile.lastGiftDay = PlayerProfileTestHook.yesterdayKey();
      }
      expect(arrows.length, 4); // days 3, 6, 9, 12
      // It walks the set rather than handing out the same one forever.
      expect(arrows.toSet().length, ArrowKind.buyable.length);
    });
  });

  group('the store when it is not configured', () {
    test('a build with no key sells nothing and grants nothing', () async {
      final store = IapService.instance;
      expect(store.supported, isFalse);
      expect(store.configured, isFalse);

      final coins = profile.coins;
      expect(await store.buyCoinPack(), PurchaseOutcome.unavailable);
      expect(await store.buyRemoveAds(), PurchaseOutcome.unavailable);
      expect(await store.restore(), PurchaseOutcome.unavailable);
      // Crucially: no coins appear out of a failed purchase.
      expect(profile.coins, coins);
      expect(store.adsRemoved, isFalse);
    });

    test('prices fall back to readable strings', () {
      final store = IapService.instance;
      expect(store.priceOf(IapService.removeAdsId), r'$9.99');
      expect(store.priceOf(IapService.coinPackId), r'$4.99');
    });

    test('a cached ad-free flag turns the ads off before any load', () async {
      SharedPreferences.setMockInitialValues({'iap_ads_removed': true});
      await IapService.instance.loadCached();

      expect(IapService.instance.adsRemoved, isTrue);
      expect(AdsService.instance.adsRemoved, isTrue);
      expect(AdsService.instance.ready, isFalse);

      // And back off again for whatever runs next.
      SharedPreferences.setMockInitialValues({'iap_ads_removed': false});
      await IapService.instance.loadCached();
      expect(IapService.instance.adsRemoved, isFalse);
    });
  });
}

/// Small helper so the streak tests can move the clock without exposing a
/// setter on the profile itself.
class PlayerProfileTestHook {
  static String yesterdayKey() {
    final d = DateTime.now().subtract(const Duration(days: 1));
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-'
        '${d.day.toString().padLeft(2, '0')}';
  }
}
