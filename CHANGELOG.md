# Changelog

## 1.0.2

**New — it tells you where to gather.** A marker appears next to any lumber you can
gather in the zone you're standing in. Pick how it looks in the options panel:
a golden log, a green dot, a yellow diamond, or the lumber's own icon.

**Knows about alts you haven't logged into.** If you already use DataStore (the
backend behind Altoholic and friends), Lumber One will borrow what it knows about
characters it hasn't seen for itself. Nothing to set up, and nothing changes if you
don't have it — those characters just count themselves the first time they log in,
as before.

**It learns as you play.** Loot a lumber somewhere it didn't know about and it
remembers that zone. `/lumber learned` shows what it's picked up, `/lumber
forgetzones` clears it. Only actual looting counts, so buying at the auction house
won't teach it that lumber grows in Valdrakken.

- **Fixed lumber spent on crafting still being counted.** Work orders take
  reagents straight from the Warband bank, which the addon only had a snapshot of
  from your last bank visit — so the total never dropped. It now notices the
  shortfall without needing you to visit a bank.
- Added an opacity slider, and `/lumber opacity`.
- Fixed the options panel failing to open at all.
- Fixed pulling a lumber from the mailbox being mistaken for gathering it there.
- Fixed the Nature skin's bottom border not drawing, and its side rails now repeat
  instead of stretching.
- Tightened the window: narrower goal boxes, less dead space, and the close button
  no longer sits over the goal column.

## 1.0.0

First release.

- Counts all twelve housing lumbers across your whole account — bags, bank and
  Warband bank, added together.
- Alts count themselves. Log in once on a character and its lumber joins the total.
- Set a goal per lumber. The row turns green when you hit it.
- Hover a lumber to see who's holding it, how much is in bags versus bank, and
  where to go chop more.
- Hover the title bar to see how fresh each character's numbers are.
- Three frame styles: Wood, Nature, and plain Blizzard.
- Drag the title bar to move it, the bottom-right corner to resize.
- Options panel for style, opacity, and hiding the goal boxes or lumber you have
  none of.
