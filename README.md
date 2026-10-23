# Stoa

A calm, two-state UI suite for **WoW Forever** (interface 16001).

- **World state:** the Grimoire console is open, with chat, party, minimap and quest notes in a bone-and-ink manuscript style.
- **Combat state:** the console folds to a thin spine and the **Halo** rises around your character: health and mana arcs, your spec's signature in the top slot, core buttons in a ring.

Layouts are built per **role** (Tank, Healer, Melee DPS, Ranged DPS), with a small **spec signature** on top. Changing spec swaps the layout automatically.

## Status

What works today:

| Area | What it does |
| --- | --- |
| Core | Event bus, modules, saved settings (account and per character) |
| Tokens | Bone, Tide and Graphite themes, one per class, and Your class (follows the character); all colour-blind safe; spacing and type scale |
| Roles | Maps each dual-spec slot to a role; set it in settings or use the class default |
| State | World and combat states with a 3 second calm-down |
| Movers | `/stoa unlock` to drag Stoa frames; positions saved per character |
| Social | Accept invites from friends and guild; decline duels, party and guild invites from strangers |
| Auto-invite | Friends and guildmates who whisper `inv` (in game or over Battle.net) get invited; optionally the keyword works in guild chat. Says so when the group is full or you aren't leader |
| Company | `/stoa friends` or a click on the console's Company page: online friends, Battle.net friends in this game, and guild, with level, zone and AWAY/BUSY. Click to whisper, Shift- or right-click to invite. The console names a few friends online when you're alone |
| Grimoire console | Out of combat, on a tooled leather panel whose lines take your theme accent: portrait seal (click to target yourself) with health and mana either side, and a Ready, Journey and Company page. Holds chat on its left page, with leather tabs standing on its top edge, and keeps bags and the game menu in its bottom-right corner. Strips the action bar art. Folds to a spine in combat |
| Halo | In combat: health and mana arcs, signature spell with cooldown, target and cast bar around your character |
| Reminders | Missing self-buffs as words: aura, seal and Righteous Fury for paladins, Inner Fire and Shadowform for priests. Under the Halo in combat, beside your role on the console out of it |
| Tank watch | For healers, a gold-lined leather plaque with a portrait coin at the Halo's upper left in combat: your focus or the group's tank, with a health word, shields and your buffs on them. Your click-casting bindings work on it |
| Target | A plaque like the tank watch, opposite it at the Halo's upper right, with portrait coin, level and kind, and an engraved bar; elite gets a doubled gold line and rare a silver one, each with the word. For any target, in or out of combat (a dead one dims and says DEAD): name, health, a HOSTILE cue, threat in words and auras. Right click for the unit menu |
| Party cards | Name and health percent, a thick health bar with shields on its end, and word pips for your buffs, Weakened Soul, dispels and low health. Rounded cards. A row under the Halo when you heal, with a grid of your click bindings on the left; a column on the left otherwise |
| Raid frames | When you heal, your group reads as a row under the combat bar at every size: ten players are two rows of party cards, twenty are compact rows of small cells with health filling the cell behind the name and one word (MAG, DIS, LOW, DEAD) in place of the percent; forty are two blocks of smaller cells side by side, groups 1-4 and 5-8. Otherwise one column per group on the left. `/stoa test raid`, `raid10` and `raid40` preview them |
| Click-casting | Fifteen bindings per role on party and raid cards: five mouse buttons, plain, Shift and Ctrl. `/stoa clicks` to edit |
| Action bars | Rounded-square icons with a hairline edge like the party cards, dim sockets for empty slots, Stoa type on keys and counts. Out of combat every console row shows (optionally only the main bar, with the rest on mouseover); in combat the bars step aside for the combat bar (your keys still work), or every row shows if the combat bar is off |
| Combat bar | In combat, a compact row of your main bar's spells under the Halo: rounded icons, keys underneath, cooldown sweeps; dimmed when unusable, blue when short of mana, faded with its key in the warning colour when out of range. Up to two more rows follow from the bottom-left and bottom-right bars, each a step smaller (Settings: Combat rows; healers default to one). Spells on a long cooldown sit dim until they're ready |
| Shadow | For Shadow Priests: coins on the Halo's right for Shadow Word: Pain (P), Devouring Plague (D) and Vampiric Embrace (V) on your target, draining as they run and in the warning colour when off. Timing is kept per target, so switching between mobs keeps each one's Pain. An outline on the combat bar's next press; Mind Flay's three ticks on the cast line; SHADOWFORM over the ring when you're out of form; a PAIN n/m count of nameplates carrying your Pain; Shadow Weaving stacks on the target plaque. `/stoa probe` in a fight reports what the game hides from addons |
| Discipline | For Disc Priests: coins on the Halo's right for Penance (P), Inner Focus (I) and Power Infusion (PI), pale gold when ready and draining while they come back, bone while Inner Focus waits on your next spell; SHIELDS and RENEW counts of the group members carrying yours; an outline on Greater Heal while Inner Focus is up. The signature slot watches Penance |
| Paladin | For Retribution: coins on the Halo's right for your seal (S) and, once you've judged Crusader, Wisdom, Light or Justice, that Judgement mark on the target (J, forty seconds, kept fresh by Holy Strike with Sacred Arbiter). For Protection: Seal of Fury (S, amber while another seal runs), Holy Shield (H) and Consecration on the ground (C). An outline on the combat bar's next press for both. As a tank in a group, TAUNT over the ring when your target is fighting someone else (Judgement with Seal of Fury taunts). With Twist of Light, the moment a main-hand swing lands the other seal of the pair (Command and Righteousness) is outlined and named under the coins, so the next swing carries both. The signature slot watches Holy Strike, or Templar's Bulwark for tanks |
| Blizzard windows | Quest, gossip, merchant, trainer, bags and tooltips on dark rounded panels, with light quest text in Stoa's type, dark rounded buttons, a quiet close cross and plain-word tabs |
| Minimap | Theme-coloured rings, serif zone name, wheel to zoom |
| Top of screen | Buffs as cropped icons in a hairline square with the time under them (pale gold when it runs short, amber edge for debuffs). Quest tracker headers in the display face over a hairline, bone quest titles, quiet minus and plus to fold. The zone above the minimap on a dark rounded panel with the clock beside it; tracking, calendar and the addon button wait for the mouse |
| Nameplates | Blizzard's plates in a rounded dark track: amber for every enemy, pale gold for neutral, blue for friends, grey only for tapped or dead; enemy players in class colour. A bone edge on your target, the level as a plain number shaded by difficulty, cast bars on the same rounded ground |
| Swing timer | Blizzard's swing timer (place it in Edit Mode) as a flat bar in the nameplates' rounded dark track: pale gold for the main hand, blue for the off hand, bone for ranged; amber words when out of range |
| Bags | Rounded item slots with a hairline edge; quality shown as an edge colour plus a corner mark for epic and above, item level on gear, free-slot count, money in g/s/c letters, a Sort button, and a combined or separate layout option |
| Character sheet | A Stoa panel, quality edges and item level on every equipment slot, WORN (under 30%) and BROKEN words for durability, an average item level line, and item levels in the inspect window |
| Damage meters | Blizzard's meter windows with no panel, just outlined words and faint bars (your own in the accent, names in class colour), side by side in the top-left corner |
| Comforts | Each its own setting, and Shift stops any of it: faster auto loot, a further camera, skip one-option gossip (on by default); accept quests, hand in quests (a choice of reward always waits for you), skip cinematics, quiet red errors in combat (off by default) |
| Merchants | Sells grey junk and repairs, from guild funds when allowed |
| Welcome | Once per character, a page to choose what each spec plays and the theme, with buttons to preview a party, practise combat or open settings |
| Backup | All of Stoa's settings as one line of text to keep safe, and a place to paste one back to restore it |
| Settings | Options > AddOns > Stoa |

Fonts are the main gap: see below.

## Commands

| Command | Does |
| --- | --- |
| `/stoa` | Open settings |
| `/stoa unlock` | Toggle frame moving |
| `/stoa reset` | Put moved frames back in their default spots |
| `/stoa safe` | Turn off every skin that touches Blizzard frames (chat, bags and menu, bar art, buttons, windows, bags, character sheet, top of screen, nameplates, swing timer, meters) and reload |
| `/stoa theme` | Cycle the themes (house, Your class, then each class) |
| `/stoa keywords inv, invite` | Set auto-invite keywords |
| `/stoa friends` | Open the Company roster |
| `/stoa welcome` | Open the welcome page: roles per spec, theme, previews |
| `/stoa backup` | Copy your settings as text, or paste a backup to restore it |
| `/stoa state` | Print the current state and role |
| `/stoa clicks` | Edit click-cast bindings for your current role |
| `/stoa test` | Show sample party cards without a group; `/stoa test raid`, `raid10` or `raid40` for a raid |
| `/stoa probe` | In a fight, print what the game hides from addons right now |
| `/stoa combat` | Practice combat out of combat: the console folds, the Halo, combat bar and group frames take their combat places. Again to end it |

## Install

Copy this folder into the game's AddOns folder and name it exactly `Stoa`:

- Beta: `World of Warcraft\_classic_beta_\Interface\AddOns\Stoa`
- Live (from launch): check the Forever folder name in your install, e.g. `World of Warcraft\_forever_\Interface\AddOns\Stoa`

## Forever notes

If a game patch raises the interface number before Stoa catches up, the AddOns list shows it as out of date: tick "Load out of date AddOns" there and it loads as before.


Forever runs the modern client, so Stoa follows Midnight-era rules: unit values can be secret in combat, and the combat log is closed to addons. Stoa never does maths on a value without checking `issecretvalue` first (see `Core/Util.lua`), and it skins Blizzard's own data rather than recalculating it.

## Fonts

Stoa ships with Tenor Sans for names and numbers and Inter SemiBold (18pt cut) for labels, in `Media/Fonts`. Both are under the SIL Open Font License; see `Media/Fonts/OFL.txt`. If a font file is missing, Stoa falls back to Cormorant Garamond if present, then the game's own fonts.

A font file that is new to the game is only picked up after a full restart of the game, not a `/reload`.
