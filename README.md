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
| Tokens | Bone, Tide and Graphite themes, all colour-blind safe; spacing and type scale |
| Roles | Maps each dual-spec slot to a role; set it in settings or use the class default |
| State | World and combat states with a 3 second calm-down, plus Alt to peek at the console |
| Movers | `/stoa unlock` to drag Stoa frames; positions saved per character |
| Social | Accept invites from friends and guild; decline duels, party and guild invites from strangers |
| Auto-invite | Friends and guildmates who whisper `inv` get invited |
| Grimoire console | Out of combat, on a tooled leather panel whose lines take your theme accent: portrait seal, health and mana, fellowship and who is online. Holds chat on its left page, with leather tabs standing on its top edge, and keeps bags and the game menu in its bottom-right corner. Strips the action bar art. Folds to a spine in combat |
| Halo | In combat: health and mana arcs, signature spell with cooldown, target and cast bar around your character |
| Reminders | Missing self-buffs as words: aura, seal and Righteous Fury for paladins, Inner Fire and Shadowform for priests. Under the Halo in combat, beside your role on the console out of it |
| Tank watch | For healers, over the Halo in combat: your focus or the group's tank, with a health word, shields and your buffs on them |
| Target | Beside the Halo in and out of combat: name, health, a HOSTILE cue and threat in words |
| Party cards | Name and health percent, a thick health bar with shields on its end, and word pips for your buffs, Weakened Soul, dispels and low health. Rounded cards. A row under the Halo when you heal, with a grid of your click bindings on the left; a column on the left otherwise |
| Raid frames | The same cards, one row per group under the Halo when you heal, one column per group on the left otherwise, for 10, 20 and 40 |
| Click-casting | Fifteen bindings per role on party and raid cards: five mouse buttons, plain, Shift and Ctrl. `/stoa clicks` to edit |
| Action bars | Rounded-square icons with a hairline edge like the party cards, dim sockets for empty slots, Stoa type on keys and counts |
| Blizzard windows | Quest, gossip, merchant, trainer, bags and tooltips on dark rounded panels, with light quest text in Stoa's type, dark rounded buttons, a quiet close cross and plain-word tabs |
| Minimap | Theme-coloured rings, serif zone name, wheel to zoom |
| Merchants | Sells grey junk and repairs, from guild funds when allowed |
| Settings | Options > AddOns > Stoa |

Fonts are the main gap: see below.

## Commands

| Command | Does |
| --- | --- |
| `/stoa` | Open settings |
| `/stoa unlock` | Toggle frame moving |
| `/stoa reset` | Put moved frames back in their default spots |
| `/stoa safe` | Turn off every skin that touches Blizzard frames (chat, bags and menu, bar art, buttons, windows) and reload |
| `/stoa theme` | Cycle Bone, Tide, Graphite |
| `/stoa keywords inv, invite` | Set auto-invite keywords |
| `/stoa state` | Print the current state and role |
| `/stoa clicks` | Edit click-cast bindings for your current role |
| `/stoa test` | Show sample party cards without a group; `/stoa test raid` for a raid grid |

## Install

Copy this folder into the game's AddOns folder and name it exactly `Stoa`:

- Beta: `World of Warcraft\_classic_beta_\Interface\AddOns\Stoa`
- Live (from launch): check the Forever folder name in your install, e.g. `World of Warcraft\_forever_\Interface\AddOns\Stoa`

## Forever notes

Forever runs the modern client, so Stoa follows Midnight-era rules: unit values can be secret in combat, and the combat log is closed to addons. Stoa never does maths on a value without checking `issecretvalue` first (see `Core/Util.lua`), and it skins Blizzard's own data rather than recalculating it.

## Fonts

Stoa ships with Tenor Sans for names and numbers and Inter SemiBold (18pt cut) for labels, in `Media/Fonts`. Both are under the SIL Open Font License; see `Media/Fonts/OFL.txt`. If a font file is missing, Stoa falls back to Cormorant Garamond if present, then the game's own fonts.

A font file that is new to the game is only picked up after a full restart of the game, not a `/reload`.
