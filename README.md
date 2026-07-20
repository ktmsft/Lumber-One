# Lumber One

Lumber One tracks every housing lumber across your warband, shows who has what, where to gather more, lets you set goals, and personalize it all with three skins and a resizable window.

https://www.curseforge.com/wow/addons/lumber-one

Type `/lumber` to open it. Drag the title bar to move it, the bottom-right corner
to resize.

## Good to know

**Bags update instantly. Bank and Warband numbers are remembered from your last
bank visit.** The game only lets addons look inside your bank while a bank window
is open, so Lumber One remembers what it last saw. It still notices when you spend
lumber crafting — even straight from the Warband bank — and drops the count right
away. What it can't see until your next bank visit is lumber *added* to the bank by
another character. Hover the title bar to check how fresh each character's numbers
are.

**Alts count automatically.** Each character adds its own lumber the first time it
logs in. Nothing to set up.

**The Warband bank is never double-counted**, even though every character can see it.

**It marks what you can gather where you're standing.** Walk into Grizzly Hills and
Coldwind gets a marker next to it. And if you loot a lumber somewhere it didn't know
about, it remembers that zone for next time — so the list gets better as you play.

## Commands

| | |
|---|---|
| `/lumber` | open or close the window |
| `/lumber options` | settings |
| `/lumber skin wood` | change style — `wood`, `nature` or `blizzard` |
| `/lumber goals` | show or hide the goal boxes |
| `/lumber zone` | show or hide the gather-here marker |
| `/lumber hidezero` | hide lumber you have none of |
| `/lumber scale 1.2` | resize (0.5 to 2.0) |
| `/lumber opacity 0.6` | fade the window (0.2 to 1.0) |
| `/lumber lock` | stop it moving |
| `/lumber reset` | put it back in the middle |
| `/lumber chars` | list your characters and when each was last seen |
| `/lumber learned` | zones it worked out for itself by watching your loot |
| `/lumber forgetzones` | clear those learned zones |
| `/lumber forget <Name-Realm>` | drop a deleted character |
| `/lumber help` | all of the above |

## Trouble?

**No marker showing?** Most zones don't have gatherable lumber, so nothing showing
is usually correct. It also has to be switched on — check "Mark lumber you can
gather here" in the options.

**Bank number looks high?** If another character *added* lumber to the bank, this
one won't see it until you next open a bank — see above. (Lumber you *spend* drops
right away, so it never reads too high for long.)

**Deleted a character?** `/lumber forget Name-Realm` drops it from your totals.
`/lumber chars` lists them.

---

The code is MIT licensed (see LICENSE.txt). The frame border art was made with a combination of photoshop, tablet and utilizing some help from AI tools.
