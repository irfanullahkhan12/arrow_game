# Monetization

Everything below is wired up in the app already, except where it says
**Not built yet**. Ad units live in
[`lib/services/ads_service.dart`](lib/services/ads_service.dart); the rules
about *when* an ad may show live in the same file, in one place, so they are
easy to tune.

## Ship checklist

### AdMob

**Already done.** The app id is in `android/app/src/main/AndroidManifest.xml`
and the four unit ids are in `lib/services/ads_service.dart`:

| Unit | Id |
| --- | --- |
| App | `ca-app-pub-6348610614764189~9024889999` |
| Banner | `…/7520236637` |
| Interstitial | `…/4745522187` |
| Rewarded | `…/4271256760` |
| App open | `…/6151314642` |

**A debug build never touches them.** `flutter run` and any other debug build
get Google's official test units instead, because tapping your own live ad is
invalid traffic and AdMob suspends accounts for it. Live units only load in a
release build — nothing to remember, nothing to pass on the command line. Two
tests in `test/ad_units_test.dart` hold that in place and also check that the
manifest app id and the four units belong to the same account, which is the
usual reason a correct-looking setup never fills.

To point a unit somewhere else anyway (either mode):

```
flutter build appbundle --release --dart-define=ADMOB_BANNER=ca-app-pub-xxx/yyy
```

Still to do on the AdMob side:

1. **app-ads.txt** — publish one on the website listed on your Play listing and
   add your AdMob line, or a large share of requests get filtered as
   unauthorised.
2. **Consent (UMP)** — required for EU/UK traffic and it directly affects fill
   rate there. `google_mobile_ads` ships the UMP SDK; call it before
   `MobileAds.instance.initialize()`.
3. Fill in AdMob's **app details** (link the app to its Play listing once it is
   live, so AdMob can verify it).

### RevenueCat (in-app purchases)

This follows the standard twelve-step Play Billing + RevenueCat route. Three of
those steps are already done in this repo, and one is not needed here — the
notes say which.

**Before you start**

- Google Play developer account (one-time $25).
- The AAB uploaded to at least one track. Play will not show the in-app
  products page until a build with the billing permission is up there.
- A free RevenueCat account.
- Package name `com.bathan.arrownewneon` — already set, and not a
  `com.example.*` name, which Play rejects.

---

#### Step 1 — Billing permission ✅ done

`<uses-permission android:name="com.android.vending.BILLING"/>` is in
`android/app/src/main/AndroidManifest.xml`. (The Play Billing library merges it
in anyway, but it is written out so it is visible.)

#### Step 2 — Create the products (Play Console)

**Monetize with Play → Products → One-time products → Create product.**

> The page used to be called *In-app products*. In the current console it is
> **One-time products**, in the left rail under **Monetize with Play →
> Products**, beside *App pricing*, *Subscriptions* and *Play Points*. If the
> list is empty and the button is greyed out, the app has no uploaded bundle
> yet — see the note below.

Create one product each:

| Field | Product 1 | Product 2 |
| --- | --- | --- |
| **Product ID** | `remove_ads` | `coins_2000` |
| **Name** | Remove Ads | 2000 Coins |
| **Description** | No banner or full-screen ads, ever | A pile of coins for arrows and power-ups |
| **Purchase type** | Buy | Buy |
| **Price** | $9.99 | $4.99 |

Set both to **Active**.

> **Decide the ids before you click create — they can never be changed.** These
> two are what `lib/services/iap_service.dart` asks for. Some guides suggest
> baking the price into the id (`remove_ads_9usd`); that only helps until you
> change the price, so plain ids are used here. If you want different ones, do
> **not** edit the code — pass them at build time:
>
> ```
> --dart-define=IAP_REMOVE_ADS=remove_ads_9usd
> --dart-define=IAP_COIN_PACK=coins_2000_5usd
> ```

#### Step 3 — Payments profile (Play Console)

**Monetize with Play → Monetization setup** (or the *Get started* /
*Payments profile* prompt on that page). Legal name, address, bank account for
payouts, tax details. One-time setup.

Products can be created without it, but **nobody can actually pay until it is
complete** — a test purchase will work and a real one will not.

#### Step 4 — RevenueCat project + Play app

revenuecat.com → **New Project** → add an app of type **Google Play Store** →
package name `com.bathan.arrownewneon`. Leave the credentials box for step 7.

#### Step 5 — Google Cloud service account

At console.cloud.google.com:

1. Create or pick a project.
2. **APIs & Services → Library** → enable **both**:
   - Google Play Android Developer API
   - Google Play Developer Reporting API
3. **IAM & Admin → Service Accounts → Create service account**, name it
   `revenuecat`.
4. Open it → **Keys → Add key → Create new key → JSON**. Keep the file safe.
5. Copy the service-account email
   (`revenuecat@<project>.iam.gserviceaccount.com`).

#### Step 6 — Give it permission (Play Console)

**Users and permissions → Invite new users** → paste that email → grant:

- ☑ View app information
- ☑ View financial data, orders
- ☑ Manage orders and subscriptions

A service account never "accepts" the invite; access starts immediately, though
it can take a few minutes to propagate.

#### Step 7 — Upload the JSON to RevenueCat

Back in the app config from step 4, drop the `.json` in and save. A green tick
means RevenueCat can talk to Google.

#### Step 8 — Entitlement

**Entitlements → New**, identifier exactly:

| Entitlement | Unlocks |
| --- | --- |
| `no_ads` | Banner, interstitial and app-open ads stop |

One is enough. The coin pack deliberately has none — see the next step.

#### Step 9 — Import the products and attach

**Products → Import** — RevenueCat reads them from Play using the service
account. Then:

| Product | Attach to |
| --- | --- |
| `remove_ads` | `no_ads` |
| `coins_2000` | **nothing** |

Leaving the coin pack unattached is what keeps it **repurchasable**. An
entitlement means "owns it forever", which is exactly wrong for a consumable —
the player would be able to buy coins once and never again. The coins are
granted by the app the moment the purchase succeeds (`IapService.buy`) and
never on a restore, so they can never be minted twice.

> If a *second* coin purchase is ever refused during testing, this is the first
> thing to check.

#### Step 10 — Offering — **not needed for this app** ⏭️

Most guides tell you to build an Offering and read `offerings.current` in code.
This game does not: `IapService` calls

```dart
Purchases.getProducts([removeAdsId, coinPackId],
    productCategory: ProductCategory.nonSubscription)
```

which fetches by product id directly. Two fixed products with fixed prices do
not need a dashboard-managed paywall, and skipping it removes a whole class of
setup mistake — including the classic one where a new project's demo `default`
offering is still full of Test Store products and the app finds nothing to
sell.

Creating an Offering anyway does no harm; it is simply ignored.

#### Step 11 — Integration code ✅ done

`lib/services/iap_service.dart` already does all four pieces: configure at
startup, purchase, restore, and check ownership on launch. All you supply is
the **public** SDK key:

```
flutter build appbundle --release --dart-define=REVENUECAT_ANDROID_KEY=goog_xxxxxxxx
```

The `goog_` key is meant to ship inside the app and is safe there. The secret
`sk_` key must **never** go in the app — this project has nowhere to put one,
by design.

Without the key `IapService.configured` stays false: the store rows still
render at fallback prices and a tap says the store is not available. Nothing
else in the game changes.

#### Step 12 — Test with licence testers

1. **Play Console → Settings → Licence testing** → add your Gmail.
2. Add the same Gmail as a tester on the **Internal testing** track and open
   the opt-in link on the phone.
3. **Install from Google Play, not from a local APK.**

> **In-app purchases cannot be tested from a sideloaded or `flutter install`
> build.** The app has to come from a Play track, signed with the key Play
> knows, and the buyer has to be a licence tester. This is the single most
> common reason "the buy button does nothing".

What to confirm on that build:

- **2000 Coins** → balance rises by exactly 2000, and it can be bought a
  second time.
- **Remove Ads** → banner disappears at once, no interstitial after the fifth
  game, and the row reads "Ad-free — OWNED".
- Reinstall → **Restore** brings ad-free back and does **not** hand out coins.

---

#### Mistakes this project already rules out

| Common mistake | Why it cannot happen here |
| --- | --- |
| Product id typo between code and console | Ids are constants in one file, overridable by `--dart-define` |
| `com.example.*` package | Package is `com.bathan.arrownewneon` |
| Demo Test-Store offering left in place | The app never reads offerings |
| Secret `sk_` key shipped in the app | Only the public key is ever read |
| Entitlement name mismatch | `no_ads` is one constant, and ownership also falls back to checking the purchased product id |
| Coins granted twice on restore | Coins are granted only in the purchase path |

## What is running now

| Placement | Where | Why it earns |
| --- | --- | --- |
| **Anchored adaptive banner** | Pinned under the power-up bar, every screen | Always-on impressions; adaptive sizing fills better than a fixed 320×50 |
| **Interstitial, 1 per 5 games** | After a level is cleared, never mid-game | The natural break point — the player has already "finished" something |
| **Rewarded: free special arrow** | Specials tray + rewards sheet | Highest eCPM format in the game, and fully opt-in; one video per arrow |
| **Rewarded: +50 coins** | Rewards sheet | Feeds the coin sinks below |
| **Rewarded: free hint** | Rewards sheet, and whenever hints hit zero | Caught at the exact moment of need |
| **Rewarded: 3 extra lives** | The "Out of Lives" dialog | Best-converting placement in any puzzle game: it saves progress the player cares about |
| **App-open** | On return, only after 2+ minutes away and never within 45 s of another full-screen ad | Free extra impression per session without hurting the session itself |

Two guards keep the experience sane, and both matter for retention (retention
is what actually decides revenue):

* `_fullScreenCooldown` — no full-screen ad within 45 s of another.
* `_appOpenMinAway` — an app-open ad needs a real absence, not an ad return.

## Coin sinks (why watching an ad is worth it)

Coins arrive from cleared levels, the daily gift, and rewarded video. They
leave through the rewards sheet and the specials tray: hint (60), undo (90),
black arrow (150), rainbow arrow (200), ghost arrow (200), bomb arrow (250). A
currency with nothing to buy stops motivating video views, so keep at least one
sink slightly out of reach — that is what the bomb is for.

## Retention features that raise ad revenue

Ad revenue is impressions × eCPM, and impressions come from sessions. These
are in the app because they bring the player back:

* **Daily gift with a streak** — day 1 pays 60 coins, and each consecutive day
  adds 20 up to 200. Every third day also hands over a special arrow, cycling
  through the four kinds so a returning player meets all of them.
* **Lives + revive** — losing costs something, so the revive ad has value.
* **Best level / stars** — visible progress.
* **Loading tips** — turns the build-the-level moment into something to read.

## Worth adding next (not built yet)

1. **More coin packs.** One price point converts badly; a 500 / 2000 / 6000
   ladder with a "best value" badge on the middle one typically lifts revenue
   per payer. The plumbing is already there — add the product ids to
   `IapService` and a row to the sheet.
2. **A starter bundle.** A one-time $1.99 offer (coins + one of each arrow)
   shown once around level 10 converts far better than a bare coin pack,
   because it is the cheapest thing in the shop and it is time-limited.
3. **Mediation.** AdMob mediation with AppLovin MAX / Unity Ads / Meta usually
   lifts eCPM 20–50 % once the app has a few thousand daily users. No code
   changes beyond adding the adapters.
4. **Rewarded interstitial before a hard level** — an opt-in "watch to start
   with an extra life" offer. `RewardedInterstitialAd` is in the same plugin.
5. **A/B the interstitial cadence.** `gamesPerInterstitial` is a single
   constant; try 4 vs 5 vs 6 and watch day-7 retention, not just eCPM.
6. **Remote config** (Firebase) so cadence, prices and rewards can change
   without shipping a build.
7. **Store optimisation.** The icon in `assets/images/app_icon.png` is the
   single biggest lever on install rate; pair it with a 15-second gameplay
   video showing a black arrow clearing a whole row.
8. **Consent (UMP).** Required for EU/UK traffic and it directly affects fill
   rate there. `google_mobile_ads` ships the UMP SDK — call it before
   `MobileAds.instance.initialize()`.
