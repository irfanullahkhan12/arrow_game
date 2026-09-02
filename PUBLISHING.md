nhi?# Publishing to Google Play

Everything the repo can do is done. What is left is account work — keys,
console entries and store copy — that only you can do.

## 0. The application id

The app is published as:

```
com.bathan.arrownewneon
```

It is set in `android/app/build.gradle.kts` (both `namespace` and
`applicationId`), and the Kotlin sources live in
`android/app/src/main/kotlin/com/bathan/arrownewneon/`.

**This can never be changed after the first release goes live**, and the Play
Console app you create must use exactly this id.

## 1. The upload key — done

The keystore exists:

| | |
| --- | --- |
| Keystore | `C:\Users\Get\upload-keystore.jks` |
| Alias | `upload` |
| Passwords | in `android/key.properties` (gitignored, never committed) |
| Validity | 10000 days |
| Upload key SHA-256 | `42:C1:92:77:8E:D4:FF:0E:D6:74:08:70:5B:7E:86:1C:4F:F4:BE:14:55:E1:B3:5B:CA:9B:34:72:8A:64:D2:89` |

Gradle picks `key.properties` up automatically, so `flutter build appbundle
--release` produces an upload-signed bundle with no extra flags.

> ### ⚠️ Back these two files up, today
>
> - `C:\Users\Get\upload-keystore.jks`
> - `android/key.properties` — the passwords live **only** here
>
> Lose either one and this app can never be updated again: Play only accepts
> uploads signed with the same key. Put copies somewhere off this machine
> (password manager, encrypted drive, private repo), and turn on **Play App
> Signing** at your first upload so Google keeps a copy of the *signing* key
> too. Neither file is in git, by design.

## 1b. SHA-256 certificate fingerprints

Some consoles (Google Cloud OAuth, Play Games, Firebase, some ad partners) ask
you to register `com.bathan.arrownewneon` with a **SHA-256 certificate
fingerprint**. There are up to three different ones, and which you need depends
on which build you are registering.

**Debug key** — this machine only, for development builds:

```
keytool -list -v -keystore %USERPROFILE%\.android\debug.keystore ^
  -alias androiddebugkey -storepass android -keypass android
```

It is tied to this computer. A colleague's debug build has a different
fingerprint, so add each one you need.

**Upload key** — what signs the bundle you upload. Already listed in step 1;
to print it again:

```
keytool -list -v -keystore C:\Users\Get\upload-keystore.jks -alias upload
```

**Play App Signing key** — what Google re-signs the app with, so it is the
fingerprint *installed users actually have*. This is the one a production
registration needs. Get it from **Play Console → your app → Test and release →
Setup → App integrity → App signing key certificate**. It only exists after
your first upload.

Most consoles let you register several keys at once. The usual answer is to add
the debug key while developing and the Play App Signing key before release.

## 2. Fill in the money keys

Neither of these has a real value in the repo — the app ships with Google's
**test** ad units and no store key, which is exactly what you want while
developing.

**AdMob** — done. App id and all four unit ids are in the repo, and a debug
build automatically uses Google's test units instead, so only a release build
serves live ads.

**RevenueCat** — twelve steps, three of which are already done in the repo.
The full walkthrough (products, payments profile, Google Cloud service account,
entitlement, licence testing) is in [MONETIZATION.md](MONETIZATION.md).

Two things to know before you start: the app needs a **payments profile** in
Play Console before anyone can actually pay, and in-app purchases **cannot be
tested from a sideloaded APK** — the build has to come from a Play track and
the buyer has to be a licence tester.

Full detail for both is in [MONETIZATION.md](MONETIZATION.md).

## 3. Build the bundle

```
flutter build appbundle --release --dart-define=REVENUECAT_ANDROID_KEY=goog_XXXXXXXX
```

The AdMob ids are already baked in and switch to live automatically in a
release build.

Optionally add `--dart-define=AI_API_KEY=gsk_...` to switch the online board
designer on.

The bundle lands at `build/app/outputs/bundle/release/app-release.aab`. Sanity
check the same build on a device first:

```
flutter build apk --release <same --dart-define flags>
flutter install
```

Play those two things before uploading: a level past 20 (the hard boards), and
one of each purchase in a **licence-tester** account.

## 4. Version numbers

`pubspec.yaml` line `version: 1.0.0+1` — the part after `+` is the Play version
code and **must increase on every upload**. Bump it for each release.

## 5. Play Console

- **App content**: privacy policy URL (required — the app shows ads and takes
  payments), ads declaration **yes**, target audience, content rating
  questionnaire, data safety.
- **Data safety**: declare that the app collects an *advertising ID* (AdMob)
  and *purchase history* (billing). Nothing else leaves the device — the board
  state, coins and arrows are all in local shared preferences.
- **Store listing**: the icon is `assets/images/app_icon.png` (512×512 for the
  listing). You need a 1024×500 feature graphic and at least two phone
  screenshots — the level-20-and-up boards and the specials tray are the two
  that sell it.
- **App access**: no login, so "all functionality available without special
  access".
- **app-ads.txt**: publish one on your listed website and add the AdMob line,
  or a large share of ad requests get filtered as unauthorised.

## 6. Release track

Start on **internal testing**, add your own account as a tester, and confirm:

- ads appear (real ones, not the test ones — that is how you know the ids took);
- **Remove ads** actually silences the banner and the interstitial;
- **2000 coins** credits exactly 2000;
- **Restore purchases** brings the ad-free flag back after a reinstall.

Then promote to production.

## What is already done in the repo

- Release signing wired to `android/key.properties`, with a debug fallback so a
  dev machine still builds.
- `key.properties`, `*.jks` and `*.keystore` gitignored.
- `minSdk` 24 (AdMob's floor), `targetSdk` from the Flutter toolchain.
- App label "Arrow Escape", launcher icons generated from the app icon,
  adaptive icon included.
- Ads and purchases both degrade to nothing when their keys are absent, so a
  keyless build never crashes and never shows a broken store.
