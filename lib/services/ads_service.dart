import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import 'iap_service.dart';

/// Every AdMob unit the game uses.
///
/// **A debug build never serves a live ad.** Tapping your own real ad is
/// invalid traffic, and AdMob suspends accounts for it — so `flutter run` and
/// any other debug build get Google's official test units, and only a release
/// build reaches the live ones. Nothing has to be remembered at build time.
///
/// The application id itself is in `AndroidManifest.xml`.
///
/// Any unit can still be pointed somewhere else explicitly, in either mode:
///
/// ```
/// flutter build appbundle --dart-define=ADMOB_BANNER=ca-app-pub-xxx/yyy
/// ```
class AdUnits {
  // ── Live units (release builds) ──────────────────────────────────────────
  static const _liveBanner = 'ca-app-pub-6348610614764189/7520236637';
  static const _liveInterstitial = 'ca-app-pub-6348610614764189/4745522187';
  static const _liveRewarded = 'ca-app-pub-6348610614764189/4271256760';
  static const _liveAppOpen = 'ca-app-pub-6348610614764189/6151314642';

  // ── Google's official test units (debug builds) ──────────────────────────
  static const _testBanner = 'ca-app-pub-3940256099942544/6300978111';
  static const _testInterstitial = 'ca-app-pub-3940256099942544/1033173712';
  static const _testRewarded = 'ca-app-pub-3940256099942544/5224354917';
  static const _testAppOpen = 'ca-app-pub-3940256099942544/9257395921';

  // ── Build-time overrides ─────────────────────────────────────────────────
  static const _bannerOverride = String.fromEnvironment('ADMOB_BANNER');
  static const _interstitialOverride = String.fromEnvironment(
    'ADMOB_INTERSTITIAL',
  );
  static const _rewardedOverride = String.fromEnvironment('ADMOB_REWARDED');
  static const _appOpenOverride = String.fromEnvironment('ADMOB_APP_OPEN');

  /// An explicit `--dart-define` wins; otherwise live in release, test in
  /// debug.
  static String _pick(String override, String live, String test) {
    if (override.isNotEmpty) return override;
    return kDebugMode ? test : live;
  }

  static String get banner => _pick(_bannerOverride, _liveBanner, _testBanner);

  static String get interstitial =>
      _pick(_interstitialOverride, _liveInterstitial, _testInterstitial);

  static String get rewarded =>
      _pick(_rewardedOverride, _liveRewarded, _testRewarded);

  static String get appOpen =>
      _pick(_appOpenOverride, _liveAppOpen, _testAppOpen);

  /// True when the ids in use are Google's test units — the banner shows a
  /// "Test Ad" label anyway, but this makes the reason explicit.
  static bool get usingTestUnits => banner == _testBanner;
}

/// Owns every ad in the game and the rules about when they may show.
///
/// Rules, in one place so they are easy to tune:
///  * a banner is pinned to the bottom of the play screen at all times;
///  * an interstitial runs after every [gamesPerInterstitial] finished games,
///    never during a game and never back-to-back with another full-screen ad;
///  * rewarded ads are always opt-in — the player taps a button for a boost
///    arrow, a hint, or an extra life;
///  * an app-open ad may run when the player comes back after being away for
///    a while.
class AdsService {
  AdsService._();

  static final AdsService instance = AdsService._();

  /// Number of finished games between two interstitials.
  static const gamesPerInterstitial = 5;

  /// Nothing full-screen may run within this window of the previous one.
  static const _fullScreenCooldown = Duration(seconds: 45);

  /// The player must have been away at least this long for an app-open ad.
  static const _appOpenMinAway = Duration(minutes: 2);

  bool _initialised = false;
  bool _disabled = false; // no-op on desktop/web and after a fatal init error
  DateTime? _lastFullScreen;

  InterstitialAd? _interstitial;
  RewardedAd? _rewarded;
  AppOpenAd? _appOpen;
  bool _loadingRewarded = false;

  int _gamesSinceInterstitial = 0;

  /// True once the plugin is up; the banner slot waits on this.
  bool get ready => _initialised && !_disabled && !adsRemoved;

  /// The player bought the ad-free upgrade. Banner, interstitial and app-open
  /// all stop; rewarded video stays, because that one is opt-in and is how
  /// arrows are earned without paying.
  bool get adsRemoved => IapService.instance.adsRemoved;

  /// Ads only exist on the two mobile platforms.
  bool get supported =>
      !kIsWeb && !_disabled && (Platform.isAndroid || Platform.isIOS);

  Future<void> initialize() async {
    if (_initialised || !supported) return;
    try {
      await MobileAds.instance.initialize();
      _initialised = true;
      preloadRewarded(); // opt-in video works with or without the upgrade
      if (!adsRemoved) {
        _preloadInterstitial();
        _preloadAppOpen();
      }
    } catch (_) {
      _disabled = true; // a broken ad SDK must never break the game
    }
  }

  // ── Interstitial: one per N games ────────────────────────────────────────

  void _preloadInterstitial() {
    if (!ready || _interstitial != null) return;
    InterstitialAd.load(
      adUnitId: AdUnits.interstitial,
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) => _interstitial = ad,
        onAdFailedToLoad: (_) => _interstitial = null,
      ),
    );
  }

  /// Call once per finished game (level cleared, or a fresh board taken).
  /// Shows an interstitial on every [gamesPerInterstitial]th call.
  Future<void> onGameFinished() async {
    _gamesSinceInterstitial++;
    if (_gamesSinceInterstitial < gamesPerInterstitial) {
      _preloadInterstitial();
      return;
    }
    _gamesSinceInterstitial = 0;
    await _showInterstitial();
  }

  /// How many more games until the next interstitial — the HUD shows this so
  /// the break is never a surprise.
  int get gamesUntilInterstitial =>
      (gamesPerInterstitial - _gamesSinceInterstitial).clamp(
        0,
        gamesPerInterstitial,
      );

  /// Shows one now, if there is one and nothing else has just been shown.
  /// Used for boards the player finished out on the home-screen widget, which
  /// cannot host an ad of its own.
  Future<void> showInterstitialNow() => _showInterstitial();

  Future<void> _showInterstitial() async {
    if (!ready || _cooling) {
      _preloadInterstitial();
      return;
    }
    final ad = _interstitial;
    if (ad == null) {
      _preloadInterstitial();
      return;
    }
    _interstitial = null;
    final done = Completer<void>();
    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (ad) {
        ad.dispose();
        _preloadInterstitial();
        if (!done.isCompleted) done.complete();
      },
      onAdFailedToShowFullScreenContent: (ad, _) {
        ad.dispose();
        _preloadInterstitial();
        if (!done.isCompleted) done.complete();
      },
    );
    _lastFullScreen = DateTime.now();
    await ad.show();
    return done.future;
  }

  bool get _cooling {
    final last = _lastFullScreen;
    return last != null && DateTime.now().difference(last) < _fullScreenCooldown;
  }

  // ── Rewarded: the player asks for these ──────────────────────────────────

  /// Rewarded video ignores the ad-free upgrade — the player asks for these.
  bool get _rewardedReadyToLoad =>
      _initialised && !_disabled && !kIsWeb;

  /// A rewarded ad is loaded and can be shown right now.
  bool get rewardedReady => _rewarded != null;

  void preloadRewarded() {
    if (!_rewardedReadyToLoad || _rewarded != null || _loadingRewarded) return;
    _loadingRewarded = true;
    RewardedAd.load(
      adUnitId: AdUnits.rewarded,
      request: const AdRequest(),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: (ad) {
          _rewarded = ad;
          _loadingRewarded = false;
        },
        onAdFailedToLoad: (_) {
          _rewarded = null;
          _loadingRewarded = false;
        },
      ),
    );
  }

  /// Shows a rewarded ad. Resolves true only if the player actually earned
  /// the reward — i.e. they watched it through.
  Future<bool> showRewarded() async {
    if (!_rewardedReadyToLoad) return false;
    final ad = _rewarded;
    if (ad == null) {
      preloadRewarded();
      return false;
    }
    _rewarded = null;

    var earned = false;
    final done = Completer<bool>();
    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (ad) {
        ad.dispose();
        preloadRewarded();
        if (!done.isCompleted) done.complete(earned);
      },
      onAdFailedToShowFullScreenContent: (ad, _) {
        ad.dispose();
        preloadRewarded();
        if (!done.isCompleted) done.complete(false);
      },
    );
    _lastFullScreen = DateTime.now();
    await ad.show(onUserEarnedReward: (_, _) => earned = true);
    return done.future;
  }

  // ── App open: only after a real absence ──────────────────────────────────

  void _preloadAppOpen() {
    if (!ready || _appOpen != null) return;
    AppOpenAd.load(
      adUnitId: AdUnits.appOpen,
      request: const AdRequest(),
      adLoadCallback: AppOpenAdLoadCallback(
        onAdLoaded: (ad) => _appOpen = ad,
        onAdFailedToLoad: (_) => _appOpen = null,
      ),
    );
  }

  DateTime? _backgroundedAt;

  void onAppPaused() => _backgroundedAt = DateTime.now();

  /// Call when the app comes back to the foreground.
  Future<void> onAppResumed() async {
    final away = _backgroundedAt;
    _backgroundedAt = null;
    if (!ready || _cooling) return;
    if (away == null || DateTime.now().difference(away) < _appOpenMinAway) {
      return;
    }
    final ad = _appOpen;
    if (ad == null) {
      _preloadAppOpen();
      return;
    }
    _appOpen = null;
    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (ad) {
        ad.dispose();
        _preloadAppOpen();
      },
      onAdFailedToShowFullScreenContent: (ad, _) {
        ad.dispose();
        _preloadAppOpen();
      },
    );
    _lastFullScreen = DateTime.now();
    await ad.show();
  }
}

// ─── Banner slot ─────────────────────────────────────────────────────────────

/// The permanent bottom banner. Reserves its own height so the board never
/// jumps when the ad finally fills, and quietly renders nothing on platforms
/// without ads.
class BannerAdSlot extends StatefulWidget {
  const BannerAdSlot({super.key});

  @override
  State<BannerAdSlot> createState() => _BannerAdSlotState();
}

class _BannerAdSlotState extends State<BannerAdSlot> {
  /// The most screen the ad may take. A puzzle board is the reason anyone
  /// opened the app; an anchored adaptive banner is allowed up to 15% of the
  /// screen, which is far more than this game can spare.
  static const _maxHeight = 60;

  BannerAd? _banner;
  double _height = 0;
  int _attempts = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_banner == null) _load();
  }

  Future<void> _load() async {
    if (!AdsService.instance.supported || AdsService.instance.adsRemoved) {
      return;
    }
    // The service may still be booting when the first frame lands.
    await AdsService.instance.initialize();
    if (!mounted || !AdsService.instance.ready) return;

    final width = MediaQuery.sizeOf(context).width.truncate();

    // Inline adaptive, not anchored: it fills the full screen width — so the
    // ad reaches both edges with no bars beside it — while letting us cap the
    // height. The real height is only known once it has loaded.
    final banner = BannerAd(
      adUnitId: AdUnits.banner,
      size: AdSize.getInlineAdaptiveBannerAdSize(width, _maxHeight),
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (ad) async {
          final rendered = await (ad as BannerAd).getPlatformAdSize();
          if (!mounted) return;
          setState(
            () => _height = (rendered?.height ?? _maxHeight)
                .toDouble()
                .clamp(1, _maxHeight.toDouble()),
          );
        },
        onAdFailedToLoad: (ad, _) {
          ad.dispose();
          if (!mounted) return;
          setState(() {
            _banner = null;
            _height = 0;
          });
          // A couple of quiet retries — no fill on the first request is
          // normal, especially on a fresh install.
          if (_attempts++ < 3) {
            Future<void>.delayed(
              Duration(seconds: 8 * _attempts),
              () => mounted ? _load() : null,
            );
          }
        },
      ),
    );
    setState(() => _banner = banner);
    await banner.load();
  }

  @override
  void dispose() {
    _banner?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Rebuilt when the ad-free upgrade lands, so the banner goes at once.
    return ListenableBuilder(
      listenable: IapService.instance,
      builder: (context, _) => _buildSlot(context),
    );
  }

  Widget _buildSlot(BuildContext context) {
    if (!AdsService.instance.supported || AdsService.instance.adsRemoved) {
      return const SizedBox.shrink();
    }
    final banner = _banner;
    // Nothing until it has actually filled: an empty reserved strip is just a
    // bar of dead space above the system bar.
    if (banner == null || _height <= 0) return const SizedBox.shrink();

    // The ad sits on the bottom edge itself — full width, no padding, no
    // background, and no safe-area inset underneath it.
    return MediaQuery.removePadding(
      context: context,
      removeBottom: true,
      child: SizedBox(
        width: double.infinity,
        height: _height,
        child: AdWidget(ad: banner),
      ),
    );
  }
}
