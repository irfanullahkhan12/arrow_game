import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'player_profile.dart';

/// What came back from a purchase attempt.
enum PurchaseOutcome {
  success,

  /// The player backed out of the store sheet — not an error, say nothing.
  cancelled,

  /// The store refused it, or the network dropped.
  failed,

  /// No store on this platform, or the app was built without a key.
  unavailable,
}

/// In-app purchases, through RevenueCat.
///
/// Two products, both one-off (non-subscription):
///
/// | Product | Price | What the player gets |
/// | --- | --- | --- |
/// | `remove_ads` | $9.99 | Banner, interstitial and app-open ads never show again |
/// | `coins_2000` | $4.99 | 2000 coins, once per purchase |
///
/// Rewarded video stays available after "remove ads" — the player has to tap
/// a button to see one, and it is how they earn arrows without paying.
///
/// Ship it by putting the ids in Play Console and RevenueCat, then baking the
/// key in at build time:
///
/// ```
/// flutter build appbundle --dart-define=REVENUECAT_ANDROID_KEY=goog_xxx
/// ```
///
/// Without a key the service reports [configured] false, the store rows say so
/// and nothing else in the game changes.
class IapService extends ChangeNotifier {
  IapService._();

  static final IapService instance = IapService._();

  // ── Catalogue ────────────────────────────────────────────────────────────

  static const removeAdsId = String.fromEnvironment(
    'IAP_REMOVE_ADS',
    defaultValue: 'remove_ads',
  );
  static const coinPackId = String.fromEnvironment(
    'IAP_COIN_PACK',
    defaultValue: 'coins_2000',
  );

  /// The RevenueCat entitlement that "remove ads" unlocks.
  static const entitlementId = String.fromEnvironment(
    'RC_ENTITLEMENT',
    defaultValue: 'no_ads',
  );

  /// Coins handed over by one [coinPackId] purchase.
  static const coinPackAmount = 2000;

  /// Shown until the store hands back its own localised prices.
  static const removeAdsFallbackPrice = r'$9.99';
  static const coinPackFallbackPrice = r'$4.99';

  /// RevenueCat's *public* Google Play SDK key. It is meant to ship inside
  /// the app and is safe here; the secret `sk_` key must never be.
  /// Overridable at build time for a second project or a staging account.
  static const _androidKey = String.fromEnvironment(
    'REVENUECAT_ANDROID_KEY',
    defaultValue: 'goog_wVwCLhGOIWtUSyllzXEypjSXxTX',
  );
  static const _iosKey = String.fromEnvironment('REVENUECAT_IOS_KEY');

  /// `--dart-define=IAP_DEBUG=true` turns on RevenueCat's own logcat output and
  /// makes this service narrate what the store said. Off by default: the logs
  /// are noisy and name product ids and prices.
  static const _verbose = bool.fromEnvironment('IAP_DEBUG');

  static const _adsRemovedKey = 'iap_ads_removed';

  // ── State ────────────────────────────────────────────────────────────────

  bool _configured = false;
  bool _adsRemoved = false;
  bool _busy = false;
  final Map<String, StoreProduct> _products = {};

  /// True once RevenueCat is up and a purchase can actually be started.
  bool get configured => _configured;

  /// True while a purchase or restore is in flight.
  bool get busy => _busy;

  /// The player has bought "remove ads". Cached in prefs, so it survives an
  /// offline launch and is applied before the first banner would have loaded.
  bool get adsRemoved => _adsRemoved;

  bool get supported =>
      !kIsWeb && (Platform.isAndroid || Platform.isIOS) && _key.isNotEmpty;

  static String get _key => Platform.isIOS ? _iosKey : _androidKey;

  /// The store's own localised price, or the fallback if it is not known yet.
  String priceOf(String productId) =>
      _products[productId]?.priceString ??
      (productId == removeAdsId
          ? removeAdsFallbackPrice
          : coinPackFallbackPrice);

  /// Reads what the player already owns off the device. Fast, offline, and
  /// awaited before the first ad could load: a player who paid should never
  /// see a banner again just because they opened the app on a plane.
  Future<void> loadCached() async {
    final prefs = await SharedPreferences.getInstance();
    final owned = prefs.getBool(_adsRemovedKey) ?? false;
    if (owned == _adsRemoved) return;
    _adsRemoved = owned;
    notifyListeners();
  }

  /// Brings RevenueCat up and reconciles with the store. Safe to leave
  /// running in the background — [loadCached] has already answered the only
  /// question the first frame needs.
  Future<void> initialize() async {
    await loadCached();
    if (!supported || _configured) return;
    try {
      if (_verbose) await Purchases.setLogLevel(LogLevel.debug);
      await Purchases.configure(PurchasesConfiguration(_key));
      _configured = true;
      _log('configured, key ...${_key.substring(_key.length - 6)}');
      Purchases.addCustomerInfoUpdateListener(_apply);
      await _refreshProducts();
      final info = await Purchases.getCustomerInfo();
      _log(
        'customer ${info.originalAppUserId}, '
        'active entitlements ${info.entitlements.active.keys.toList()}, '
        'purchased ${info.allPurchasedProductIdentifiers}',
      );
      _apply(info);
    } catch (e) {
      // A store that will not start must never break the game.
      _configured = false;
      _log('configure FAILED: $e');
    }
    notifyListeners();
  }

  Future<void> _refreshProducts() async {
    try {
      final products = await Purchases.getProducts(
        [removeAdsId, coinPackId],
        // Both are one-off products; without this Play returns nothing.
        productCategory: ProductCategory.nonSubscription,
      );
      for (final product in products) {
        _products[product.identifier] = product;
      }
      final listing = products
          .map((p) => '${p.identifier}=${p.priceString}')
          .join(', ');
      _log('store returned ${products.length}/2 products: $listing');
      for (final id in const [removeAdsId, coinPackId]) {
        if (!_products.containsKey(id)) _log('MISSING from store: $id');
      }
    } catch (e) {
      // Prices stay on the fallback strings.
      _log('getProducts FAILED: $e');
    }
  }

  /// Reads "does this customer own remove-ads" out of a [CustomerInfo].
  ///
  /// The entitlement is the right answer, but a project that has not wired one
  /// up in the RevenueCat dashboard would leave every payer still seeing ads —
  /// so a straight look at what they have bought is the backstop.
  Future<void> _apply(CustomerInfo info) async {
    final owned =
        info.entitlements.active.containsKey(entitlementId) ||
        info.allPurchasedProductIdentifiers.contains(removeAdsId);
    if (owned == _adsRemoved) return;
    _adsRemoved = owned;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_adsRemovedKey, owned);
    notifyListeners();
  }

  // ── Buying ───────────────────────────────────────────────────────────────

  Future<PurchaseOutcome> buy(String productId) async {
    if (!supported || !_configured) return PurchaseOutcome.unavailable;
    if (_busy) return PurchaseOutcome.failed;

    var product = _products[productId];
    if (product == null) {
      await _refreshProducts();
      product = _products[productId];
    }
    if (product == null) return PurchaseOutcome.unavailable;

    _busy = true;
    notifyListeners();
    try {
      final result = await Purchases.purchase(
        PurchaseParams.storeProduct(product),
      );
      await _apply(result.customerInfo);
      // Coins are consumable, so they are granted here and only here — a
      // restore must never hand them out a second time.
      if (productId == coinPackId) {
        await PlayerProfile.instance.addCoins(coinPackAmount);
      }
      return PurchaseOutcome.success;
    } on PlatformException catch (e) {
      final code = PurchasesErrorHelper.getErrorCode(e);
      _log('purchase $productId -> $code (${e.message})');
      return code == PurchasesErrorCode.purchaseCancelledError
          ? PurchaseOutcome.cancelled
          : PurchaseOutcome.failed;
    } catch (_) {
      return PurchaseOutcome.failed;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  static void _log(String message) {
    // ignore: avoid_print
    if (_verbose || kDebugMode) print('[iap] $message');
  }

  Future<PurchaseOutcome> buyRemoveAds() => buy(removeAdsId);

  Future<PurchaseOutcome> buyCoinPack() => buy(coinPackId);

  /// Brings back a "remove ads" bought on another device or before a reinstall.
  /// Consumables are deliberately not re-granted.
  Future<PurchaseOutcome> restore() async {
    if (!supported || !_configured) return PurchaseOutcome.unavailable;
    if (_busy) return PurchaseOutcome.failed;
    _busy = true;
    notifyListeners();
    try {
      await _apply(await Purchases.restorePurchases());
      return _adsRemoved ? PurchaseOutcome.success : PurchaseOutcome.failed;
    } catch (_) {
      return PurchaseOutcome.failed;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }
}
