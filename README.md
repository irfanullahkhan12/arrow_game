# Arrow Escape

A neon arrow puzzle. Every arrow has to leave the board, and it can only leave
if nothing is standing in its exit ray. Tap one with a clear path and it flies
off; tap a blocked one and it thuds into whatever is in the way and costs a
life.

## Layout

```
lib/
  main.dart              app entry point + re-exports for tests/tooling
  theme/game_theme.dart  every colour and the app font, in one place
  models/                arrow piece + kind, palette, silhouettes, board data
  game/
    level_factory.dart   the level generator (see below)
    ai_designer.dart     online designer: draws a new outline per level
    flight_path.dart     the route a fired arrow travels
  services/
    game_store.dart      persistence + the home-screen widget bridge
    ads_service.dart     AdMob: banner, interstitial, rewarded, app-open
    iap_service.dart     RevenueCat: remove ads, coin pack
    notification_service.dart  the daily "come back" reminder
    player_profile.dart  coins, power-ups, daily streak, settings
    sound_service.dart   the pooled fire sounds
  ui/
    game_page.dart       the screen and all of the game's interaction
    game_painter.dart    the board, arrow by arrow
    arrow_art.dart       how one arrow is drawn — board and shop share it
    widgets/             loader, dialogs, rewards sheet, shared chrome
```

`package:arowgame/main.dart` re-exports the pieces tests need, so nothing
outside `lib/` has to know about the split.

## The level generator

`LevelFactory.generate` carves the board **backwards from the solution**: it
repeatedly cuts off an arrow whose exit ray is already clear of everything
still on the board. That is exactly the game's win condition, so the peel order
it produces *is* a solution — every board is solvable by construction and
nothing has to be generated-then-tested-then-thrown-away.

The silhouette is cut about 6 cells per arrow, a little more than the arrows
need, so the carver may leave a few gaps instead of having to tile the mask
exactly. Up to forty boards are cut per level and the one with the best
coverage and the fewest stubby arrows wins. Even a 120-arrow board lands in a
few hundred milliseconds, under a hard 1.4 s deadline with a constructive
fallback behind it, so no level can ever hang the game.

Arrow count is two per level: level 14 is a 28-arrow board, level 50 a
100-arrow one. Big boards overflow the screen on purpose — pinch to zoom, drag
to pan, and the floating fit button snaps everything back into view.

## Special arrows

Every special fires even when it is blocked, and clears the arrows it runs
over. They differ in the route they take, which `lib/game/flight_path.dart`
builds once for both the painter and the game logic — so what the player sees
being run over is exactly what fires.

| Arrow | Route | Price |
| --- | --- | --- |
| **Black** | Straight out, clearing its whole exit ray | 150 |
| **Rainbow** | To the edge, one full lap of the boundary, then out | 200 |
| **Ghost** (white) | Three zigzags across the board, then out | 200 |
| **Bomb** | Straight out, detonating everything within two cells | 250 |

They turn up on the board on their own every few levels (the rainbow from
level 12, the ghost from 18, the bomb from 25), and the player can buy one with
coins or a rewarded video and place it on any arrow they like.

## Board outlines

A board is carved out of a *silhouette* — anything that can answer "is this
point inside?" (`lib/models/silhouette.dart`). There are two sources, and the
game always has one:

**The online designer draws a new one every level.** It does not pick from a
menu: it returns a shape family plus numbers — a nine-point star with a hole
punched through it, a twelve-tooth gear, a blob with these harmonics — so the
outline is different every time, and the prompt carries a random design seed to
keep it that way. Every number is clamped on arrival
(`DesignedSilhouette`), so even a nonsense reply still yields a board that is
drawable and playable, and the solver always builds the actual arrows. Turn it
on with a key:

```
flutter run --dart-define=AI_API_KEY=gsk_...
```

**Twenty-five built-in shapes are the fallback.** No key, no network, a bad
reply, or an outline that cannot be sized for this level — any of those and the
game rotates through `BoardShape`: circle, diamond, plus, cross, heart, 5/6/8-
point stars, triangle, pentagon, hexagon, octagon, flower, gear, ring,
squircle, butterfly, shield, arrow, gem, moon, clover, hourglass, bowtie. One
per level, so twenty-four boards pass before anything repeats. The game never
needs the network.

## Home-screen widget and reminders

The **home-screen widget** shows the live board with the level above it, and
the game is playable there: tapping the board fires the next free arrow in a
background Dart isolate without opening the app. The board reaches it as a PNG
file — it used to be base64 inside shared preferences, which meant a few
hundred kilobytes of text decoded on every widget refresh and re-read by the
app on every `prefs.reload()`.

An ad cannot be shown *in* a widget: there is no activity to host one, and
AdMob's policy keeps ads inside the app's own screens. So boards finished on
the widget are counted (`GameStore.widgetGamesKey`), and every tenth one is
paid off with an interstitial the next time the app is opened.

The **daily reminder** fires at 19:30 local, carries the level the player is
actually on, and rotates through ten different lines so it never reads like the
same advert twice. A week is scheduled at a time and rebuilt on every app open,
so the level in it is never stale and nothing runs in the background. Android
13+ is asked for permission on first launch; refusing it changes nothing else.

## Running

```
flutter pub get
flutter run
```

Ads default to Google's **test** units and in-app purchases are off until a
RevenueCat key is baked in. See [MONETIZATION.md](MONETIZATION.md) for the ship
checklist, the ad unit ids and the two store products.

## Tests

```
flutter test
```

`test/level_progression_test.dart` walks levels 1–60 across three generations
each and asserts every board is solvable, well filled, and built in time.
