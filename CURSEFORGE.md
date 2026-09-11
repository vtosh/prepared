# Prepared

Per-boss gear / spec / talent / glyph loadout reminders for **MoP Classic**
raids. Set your ideal loadout once per boss, per character — Prepared
watches for the pull and throws up an alert the moment something doesn't
match, so you're never mid-fight before noticing you forgot to swap a glyph.

## Features

**Per-boss loadouts, per character.** Save your gear set, spec, all 6 talent
tiers, and your 3 major glyphs for each boss. Everything is built from your
own real, live options (Equipment Manager sets, your class's specs, your
known glyphs) — nothing pre-filled, no guessing.

**Smart triggers.** Each boss checks you automatically when you target it,
when you enter its zone, or when a previous boss in the encounter dies — no
manual pre-pull checklist required.

**On-screen alert, your choice of cue.** A "SWITCH SETUP" banner spells out
exactly what to change. Pair it with a sound effect — Raid Warning, Ready
Check, and more, including anything another addon has registered via
LibSharedMedia — or full text-to-speech that reads out which categories
need switching.

**One button fixes it.** The alert's button walks you through every
mismatch one press at a time: equip the gear set, swap dual-spec, learn the
right talent, socket the right glyph. It drives Blizzard's own panels
directly, so there's no risky addon-side automation.

**Talent/glyph panel highlighting.** Open the talent or glyph panel while an
alert is up and see exactly what's wrong (red) and what to switch to
(green), right on Blizzard's own UI.

**Per-boss notes.** Leave yourself a reminder — "pop trinket at 30%", "swap
to left" — that shows on the banner, with the option to have it read aloud
too.

**Multiple profiles per character.** Keep a Healing and a DPS profile (or
however many you need), each with its own full set of per-boss loadouts.
Base one profile's boss setup on another's and just override what's
different.

## Getting started

Type `/prep` to open the config window (or click the badge that appears on
the talent/glyph panel), pick your raid, and set up a boss. `/prep check`
re-checks your current setup against whatever boss is being tracked.

## Currently supports

Siege of Orgrimmar. Source and issue tracker: [github.com/vtosh/prepared](https://github.com/vtosh/prepared).

## Good to know

- Glyph auto-apply is best-effort — Blizzard's glyph API is partly
  protected, so you may need to confirm a popup or socket a glyph by hand.
  Only the 3 Major glyph slots are tracked; Minor glyphs aren't.
- Gear-set and talent changes both refuse to run in combat, same as the
  default UI.
- Capture reads your *currently equipped/active* loadout, so make sure
  you're actually set up the way you want before capturing it.
