# Lumber One

Every housing lumber, counted across every character you have. Make it sawed.

![Lumber One](https://example.com/screenshot.png)

## What it does

One line per lumber type, showing how much you have **across your whole account** —
bags, bank, and the Warband bank, added up. Set a goal and the row turns green when
you get there.

Type `/lumber` to open it. Drag the title bar to move it, the bottom-right corner
to resize.

## Good to know

**Bags update instantly. Bank and Warband numbers come from your last bank visit.**
That's not laziness — the game only lets addons see inside your bank while a bank
window is actually open. So Lumber One remembers what it saw last time. Hover the
title bar to check how fresh each character's numbers are.

**Alts count automatically.** Each character adds its own lumber the first time it
logs in. Nothing to set up.

**The Warband bank is never double-counted**, even though every character can see it.

## Commands

| | |
|---|---|
| `/lumber` | open or close the window |
| `/lumber options` | settings |
| `/lumber skin wood` | change style — `wood`, `nature` or `blizzard` |
| `/lumber goals` | show or hide the goal boxes |
| `/lumber hidezero` | hide lumber you have none of |
| `/lumber scale 1.2` | resize (0.5 to 2.0) |
| `/lumber lock` | stop it moving |
| `/lumber reset` | put it back in the middle |
| `/lumber chars` | list your characters and when each was last seen |
| `/lumber forget <Name-Realm>` | drop a deleted character |
| `/lumber help` | all of the above |

## Contributing

Run the tests with `luajit tests/test_lumberone.lua` — about 35 checks over the
counting logic. `UI.lua` isn't covered by them.

Build the CurseForge zip with `.\tools\build.ps1`. It runs the tests first and
ships only the files the addon actually loads.

Adding a lumber type is one entry in `Data.lua`. Adding a frame style is one entry
in the `SKINS` table in `UI.lua` — each style works out its own frame width from the
proportions of its art, so nothing else needs touching.

`tools/key_art.ps1` rebuilds `images/keyed/` from the art in `images/`. Read its
header before touching the art — the source images have no usable transparency and
that script is what puts it back.

MIT licensed. See LICENSE.txt.
