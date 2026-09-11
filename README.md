# Prepared

A per-boss gear/spec/talent/glyph loadout manager for **MoP Classic**, starting
with Siege of Orgrimmar. Set yourself up once per boss, per character, and get
an on-screen nudge if you pull without matching it.

## Install

1. Copy the whole `Prepared` folder into `World of Warcraft/_classic_/Interface/AddOns/`
   (the folder name must stay `Prepared` — it has to match the `.toc` filename).
2. Make sure `Prepared.toc`, `Compat.lua`, `Core.lua`, `Profiles.lua`,
   `Detection.lua`, `Alert.lua`, `Highlight.lua`, `UI.lua`, `PanelButton.lua`,
   the `Textures/` and `Bosses/` folders are all directly inside it.
3. Restart WoW or run `/reload`. Check the AddOns list at the character-select
   screen if it doesn't show up.

If it loads as "out of date," open `Prepared.toc` and check the `## Interface:`
line — bump it to (or add) whatever your client currently reports. You can get
that number in-game with:
```
/dump select(4, GetBuildInfo())
```

## Using it

- `/prep` — opens the config window. (Or click the Prepared badge that sits on
  the lower-right edge of the talent / glyph panel — left-click opens the
  window, right-click opens Options. Turn it off in **Options → General**.)
- `/prep check` — manually checks your current setup against whatever boss is
  currently selected.
- `/prep target` — prints your current target's exact name, so you can copy it
  into a boss's `name`/`targetNames` field if it's not matching.
- `/prep subzone` — prints the current sub-zone text, for setting a boss's
  `subZone` field.
- `/prep debug` — toggles a debug print whenever a trigger fires (targeting a
  boss, entering its zone, or a tracked kill), so you can confirm Prepared is
  recognizing things correctly.
- `/prep hl` — prints what the panel-highlighter can currently see (talent
  buttons, glyph sockets). Only needed if the highlights aren't showing up.

### Panel highlights while an alert is up

When the "SWITCH SETUP" banner is showing and you open Blizzard's talent or
glyph panel, Prepared washes what needs to change with a soft colour:

- **Talents** — for any tier that's wrong, the talent you currently have gets
  a **red** wash and the one to switch to gets a gently breathing **green**
  wash.
- **Glyphs** — since a saved major glyph just has to be socketed *somewhere*,
  the major sockets you can free up get a **red** wash and the glyph(s) to
  socket get a **green** wash in the browse list.

The highlights clear the moment the banner does. **Options → Panel Highlights**
has the knobs: enable/disable, style (soft wash / outline / both), an intensity
slider, and whether the "switch to this" marker gently pulses.

### Setting up a boss

Open `/prep`, pick your raid, and click a boss on the left. Each boss has:

- **Trigger** — a dropdown choosing *when* Prepared checks you against this
  boss's setup: **When I target it**, **When I enter its zone**, or **When
  another boss dies**. Most bosses start on "target"; a few start on a
  smarter default (in Siege of Orgrimmar, Fallen Protectors / Norushen /
  Galakras / Spoils / Paragons start on zone entry). Change it freely — your
  choice is saved per character. Picking "another boss dies" reveals a second
  dropdown to choose which boss.
- **Gear Set / Spec / Talents (6 tiers) / Major Glyphs (3 slots)** — each is
  a clickable slot. Click one to open a picker showing your real, live
  options (saved Equipment Manager sets, your class's specs, that tier's 3
  talent choices, or your known Major glyphs) — click an option to select
  it, or hit **Save Current** in the same dialog to instantly capture
  whatever you're actually using right now for just that one slot.
  Right-click a slot to drop back to inheriting the Global Default.
- **"(none)" on a talent or glyph slot** means *this should be empty* — not
  "don't care". Prepared then flags (and marks red in the panel) a talent
  you have in that tier, or — if any glyph slot is set to "(none)" — any
  major glyph socketed that isn't in your list. The **talent** the fix
  button can unlearn for you (it triggers the game's own confirm). For the
  **glyph** the button just opens the Glyphs panel so the red wash shows
  which socket — you clear it yourself (MoP has no click to empty a socket,
  and the API is Blizzard-only). Socket a different glyph over it, or leave
  it as a reminder.
- Picking a **glyph that's already in another slot** moves it — the other
  slot falls back to whatever the Global Default (or a "From:" profile) has
  for it, or goes to "(none)" if that would be the same glyph again.
- **Capture Everything Now** — the fast path: stand somewhere safe, set
  yourself up the way you want, and this grabs gear/spec/talents/glyphs all
  at once instead of clicking through every slot individually. Mix and
  match with the per-slot pickers as needed — capturing everything doesn't
  touch your trigger choice.
- **Note** — a free-text box for a per-boss reminder ("pop trinket at 30%",
  "swap to left"). It shows on the alert banner in gold. It's silent by
  default; tick **Announce in voice alert** to have it spoken too. Once
  ticked it's read via text-to-speech regardless of whether your Alert
  Sound is set to a sound effect or Text-to-speech (voice/volume in
  **Options → Alert Sound** apply either way). When Alert Sound *is* set
  to Text-to-speech, an announced note is folded after the "switch X"
  phrase instead of playing twice; when it's a sound effect, the note
  waits for **Note Delay** (also in Options, default 1.5s) to elapse
  first so it doesn't talk over the sound. A note alone (nothing to fix)
  still raises the banner. With **Options → Alert Sound → Minimal alerts**
  ticked, the spoken cue drops the per-category list and just says
  "changes required" (an announced note still reads in full).

Nothing here is pre-loaded with talent/glyph data, because that's 30+ specs
worth of choices that change with gear, tuning, and personal preference —
picking from your own live/known options is both simpler and always
correct.

### Getting warned — how triggers work

Each boss's trigger is independent — you might have one boss set to fire on
target, another on zone entry, and another chained off a different boss's
death, all in the same raid:

- **When I target it** — the moment you target a unit whose name matches
  this boss, Prepared checks you against its saved setup. This fires well
  before combat starts, so you actually have time to fix anything it flags.
- **When I enter its zone** — fires when `GetSubZoneText()` matches this
  boss's `subZone` field (set that field in the raid's data file first;
  most bosses don't have a distinct named sub-area, so this won't fire
  until you add one).
- **When another boss dies** — once the chosen boss dies, Prepared hides
  that boss's banner (if it was up) and starts tracking + silently
  pre-checking this one, so you're warned about the next pull without
  targeting anything. Death is detected by watching unit health directly
  (not the `BOSS_KILL` event, which post-dates MoP and isn't guaranteed to
  exist on this client).

You can also always select a boss manually in the UI and hit **Check This
Boss Now**, independent of any trigger — useful during raid prep before
you've targeted anything.

The banner is draggable; drag it wherever you want, it remembers position
for the session.

### Applying a saved setup

**Click the button under the alert banner** to handle the next mismatch, one
per press, in this order: gear set → spec → talents → major glyphs. The banner
re-checks after each press and the button relabels itself for the next step.
Out of combat only. (The banner body itself only drags and, on right-click,
dismisses — every fix goes through the one button.)

- **Gear set / cloak / trinkets** — one press equips all of them for you
  (Blizzard Equipment Manager for the set; trinkets go into whichever slot
  isn't already holding one you want). The button reads *Equip gear set +
  trinkets* etc. If a dual-spec swap is also due, it rides along on the same
  press — *Equip gear + switch to Frost*.
- **Talents / Glyphs** — Prepared can't change these directly (the APIs are
  Blizzard-only, and even opening the panels from an addon taints them). So the
  button walks you through it one press at a time: *Open talents* → *Unlearn
  tier 3, switch to X* → *Learn X*, or *Open glyphs* → *Socket X*. Each press
  drives Blizzard's own UI in a secure context, so it works with no taint — you
  just confirm the game's own reagent popups (Tome of the Clear Mind / Dust of
  Disappearance) when they appear. The panel is also highlighted (**red** =
  wrong, **green** = switch to this) while the alert is up, and the banner
  clears itself as each thing is fixed.
- **Spec** — if the boss's spec is your **other dual-spec** (sitting on your
  inactive talent group), the button does a one-click *Switch to Frost* — a
  free, instant talent-group swap. (That swap also brings over that group's own
  talents + glyphs; the banner then re-checks those and walks you through any
  that still don't match.) A real respec (a spec neither of your groups has)
  still needs a class trainer, so the button just opens the Specialization tab
  for that.

### Profiles

Each character can have several named **profiles** — e.g. *Healing* and
*Shadow* on a priest. A profile is a complete, independent set: its own
Global Default loadout plus its own per-boss setups. Pick the active profile
from the **Profile** dropdown at the top (it persists per character and is
what drives the in-raid reminders). **Manage…** opens a dialog to create,
rename, duplicate, or delete profiles.

**Basing a boss on another profile.** In any boss's detail panel the top-right
**Source** dropdown lets you point that boss at another profile ("From:
Healing"). That profile's setup for the boss then becomes the *base*: every
loadout slot shows what Healing gives (faded, tagged with Healing's initial),
but you can still click any slot to override it just for this profile — the
same way a slot overrides the Global Default. The layering, lowest to highest,
is: this profile's Global Default → Healing's Global Default → Healing's
per-boss setup → your per-boss overrides here. **Reset** drops your overrides
and goes back to Healing's base.

The **trigger** still comes wholesale from the source profile and is shown
read-only (edit it in that profile). A based boss is marked in the boss list —
*Immerseus (Healing)*. Deleting a profile that other profiles based bosses on
just reverts those bosses to their own setup.

**Copy from another profile.** The **Copy from** dropdown in the action row
takes this boss's set (loadout + trigger) from another profile and drops an
independent, editable copy into the active profile — unlike *Source*, there's
no live link afterwards. On the Global Default row it copies that profile's
Global Default set instead.

## Extending to new raids

Add a new file in `Bosses/`, e.g. `Bosses/BlackrockFoundry.lua`:

```lua
BossPrepData:RegisterInstance({
    key = "BRF",
    name = "Blackrock Foundry",
    order = 2,
    bosses = {
        { key = "GRUUL",      name = "Kargath Bladefist" },
        -- ...
    },
})
```

Then add one line to `Prepared.toc`, right under the SoO line:
```
Bosses\BlackrockFoundry.lua
```

That's the entire integration surface. The `name` field must match the exact
encounter name text WoW uses for that boss's `ENCOUNTER_START` event — if
you're not sure, pull the boss with `/prep debug` on and read the chat print,
then fix the name in the data file if it's off by a character.

## Known limitations

- Glyph auto-apply is best-effort only (Blizzard's glyph API is partly
  protected) — expect to confirm a popup or socket it by hand. Only the 3
  Major glyph slots are tracked; Minor glyphs are cosmetic and not covered.
- Gear/talent/glyph capture reads your *currently active* loadout, so make
  sure you're actually set up the way you want before hitting Capture (or
  before using a slot's "Save Current" option).
- Target-based and zone-based detection rely on the `name`/`targetNames`
  and `subZone` fields in the data file matching the game's actual text
  exactly. Use `/prep target` and `/prep subzone` to check.
- Talent auto-apply and gear-set-equip both refuse to run in combat, same as
  the default UI would.
- The talent/glyph panel highlights rely on Blizzard's frame names; if a
  client build renames them the outlines just won't appear (they never
  error). `/prep hl` shows which frames were found.
