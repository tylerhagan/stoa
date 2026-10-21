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
| Grimoire console | Out of combat: portrait seal, health and mana, fellowship and who is online. Holds chat on its left page and strips the action bar art. Folds to a spine in combat |
| Halo | In combat: health and mana arcs, signature spell with cooldown, target and cast bar around your character |
| Party cards | Large beside the Halo when you heal, compact on the left otherwise. Click to target, right click for the menu |
| Settings | Options > AddOns > Stoa |

Click-casting, raid frames and the minimap come next.

## Commands

| Command | Does |
| --- | --- |
| `/stoa` | Open settings |
| `/stoa unlock` | Toggle frame moving |
| `/stoa theme` | Cycle Bone, Tide, Graphite |
| `/stoa keywords inv, invite` | Set auto-invite keywords |
| `/stoa state` | Print the current state and role |

## Install

Copy this folder into the game's AddOns folder and name it exactly `Stoa`:

- Beta: `World of Warcraft\_classic_beta_\Interface\AddOns\Stoa`
- Live (from launch): check the Forever folder name in your install, e.g. `World of Warcraft\_forever_\Interface\AddOns\Stoa`

## Forever notes

Forever runs the modern client, so Stoa follows Midnight-era rules: unit values can be secret in combat, and the combat log is closed to addons. Stoa never does maths on a value without checking `issecretvalue` first (see `Core/Util.lua`), and it skins Blizzard's own data rather than recalculating it.

## Fonts

The design uses Cormorant Garamond and Inter (both SIL Open Font License). Drop the `.ttf` files named in `Core/Tokens.lua` into `Media/Fonts`. Until then Stoa falls back to the game's fonts.
