# Store listing copy

Everything here is checked against what the shipped build actually does. Play
rejected an earlier draft under the Metadata policy, so three rules apply to
anything added later:

- **No promotional or ranking words** anywhere in the title, icon, developer
  name or graphics — no "new", "free", "best", "top", "#1", "sale".
- **No call to action** — "download now", "install today" and the like are the
  exact phrasing the policy names.
- **No keyword lists.** A block of comma-separated search terms at the bottom
  is keyword stuffing, and it is what the policy means by excessive metadata.

And every sentence has to be true of a release build. The AI board designer,
for one, only runs when `AI_API_KEY` is passed at build time, and production
builds do not pass one — so it cannot be advertised.

## Title (30 characters max)

```
Arrows Neon: Puzzle
```

## Short description (80 characters max)

```
Fire every arrow off the board. A blocked arrow costs you a life.
```

## Full description

```
A neon puzzle about getting every arrow off the board.

Every arrow points somewhere, and it can only leave in that direction, and only if nothing is standing in its way. Tap an arrow with a clear path and it flies off. Tap a blocked one and it thuds into whatever is in front of it, and costs you a life. Working out the right order is the whole puzzle.

HOW IT PLAYS
- Every board is built so that it can be solved
- Boards start at two arrows and grow past a hundred
- 25 board shapes: circles, stars, gears, hearts, moons and more
- Pinch to zoom and drag to pan on larger boards
- Hints and undo for when you are stuck

SPECIAL ARROWS
Specials fire even when they are blocked, and clear what they touch on the way out.
- Black arrow: flies straight out and takes every arrow in its path with it
- Rainbow arrow: runs a full lap of the board's edge, clearing everything it passes
- Ghost arrow: cuts three zigzags across the board before it leaves
- Bomb arrow: clears every arrow within two cells of it

You start with two specials and get two more every ten levels, until you are holding eight. You can also buy them with coins, or earn them by watching a video.

COINS AND DAILY GIFT
- Earn coins for every board you clear
- A daily gift that grows the more days in a row you play
- A one-time purchase removes the ads

HOME SCREEN WIDGET
Play your current board straight from the home screen, without opening the app. An optional reminder at 19:30 keeps your streak going.

Plays offline. Contains ads and optional in-app purchases.
```

## What was cut, and why

| Old line | Why it went |
| --- | --- |
| "Download Arrow Escape now and prove your puzzle-solving skills!" | A call to action. The policy names this one outright. |
| "AI-powered board generation creates unique outlines every level" | Untrue of a release build — see above. The 25 shapes are not a "fallback", they are how every board is drawn. |
| "Keywords: puzzle, brain teaser, … free puzzle …" | Keyword stuffing, and "free" is a price claim. |
| "60+ levels with progressive difficulty" | Levels are generated on demand and do not stop at 60. |
| "Optimized for phones and tablets" | Nothing in the build makes this true beyond Flutter's own layout. |
| "Beautiful neon graphics", "Satisfying sound effects", "masterpieces" | Puffery. The rejection asked for a concise, accurate description. |
| "PERFECT FOR: puzzle enthusiasts / brain training / …" | Five lines that describe the audience rather than the app. |
| Emoji section headers | Not banned in a description, but after a metadata rejection plain headings are the safer read. |
| "never get stuck!" | Boards are always solvable, but a player can still lose every life. |
