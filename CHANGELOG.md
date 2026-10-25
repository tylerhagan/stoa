# Changelog

Each release has a `## <version>` heading matching the `## Version:` line in `Stoa.toc`. The release workflow uses that section as the release notes, so a tag without one fails.

Pushing a tag such as `v0.9.1` runs `.github/workflows/release.yml`, which builds `Stoa-<version>.zip` and publishes a GitHub Release.

To also publish to CurseForge, Wago and WoWInterface once the repository is public: add the project IDs to `Stoa.toc` (`## X-Curse-Project-ID`, `## X-Wago-ID`, `## X-WoWI-ID`), add `CF_API_KEY`, `WAGO_API_TOKEN` and `WOWI_API_TOKEN` as repository secrets, and add a step running `BigWigsMods/packager@v2` to the workflow (checkout with `fetch-depth: 0`). The `.pkgmeta` is already in place. The packager step is left out for now on purpose.

## Unreleased

Everything below is on the launch branch and not yet in a numbered release.

- Colour vision setting: Standard, Red-green, Blue-yellow or No colour, laid over any theme; also on the welcome page and `/stoa vision`. Each set is checked by `Tools/art/cvd_audit.py` (simulated colour blindness, CIEDE2000 difference, WCAG contrast).
- Tide's text is a step dimmer so its white warnings stand out; Druid's warning is pale yellow rather than near-white.
- Tooltip cards: edges in the unit's or item's colour, difficulty as a word (TRIVIAL to DEADLY, ELITE, RARE, BOSS), target, casting, threat, players' item level, an upgrade line against worn gear, owned counts, shorter cards in combat, cursor or console position.
- Stone behind windows: faint rings and grain in the theme's colour behind quest, merchant, bag and other windows and Stoa's own pages (new texture: restart the game once). A setting turns it off.
- Druid signatures (Balance, Cat, Bear, Restoration) and Mage signatures (Arcane, Fire, Frost), built on a shared signature kit (`Modules/Halo/Sign.lua`). Other classes get a main cooldown in the Halo's slot and the game's suggested next press. The power arc follows your power type. The launch check now only checks your own class's spells.
- Click grid folds to its title by default and opens while you hover a party or raid card or hold Shift; click its title to keep it open. A Click grid setting and `/stoa grid` choose always open, folded or hidden.
- Shift and drag moves quest, gossip, merchant, bag, character, spellbook, mail and similar windows; each remembers its spot.

- Discipline signature: coins on the Halo for Penance, Inner Focus and Power Infusion, SHIELDS and RENEW counts, and an outline on Greater Heal while Inner Focus is up.
- Twist of Light for Paladins: after a main-hand swing lands, the other seal of the pair is outlined and named so the next swing carries both.
- Vampiric Embrace coin for Shadow Priests now counts down from 30 seconds.
- 40-man healer layout: two blocks of smaller cells side by side, groups 1-4 and 5-8. `/stoa test raid40` previews it.
- Class themes, one per class, and a Your class theme that follows the character.
- Company roster: online friends, Battle.net friends in this game and guild on one page (`/stoa friends`), click to whisper, Shift- or right-click to invite.
- Auto-invite also answers whispers over Battle.net, and optionally the keyword in guild chat.
- Move any frame: per-role positions, overlays, an unlock bar with a grid, arrow-key nudging and a settings button.
- Bags and the character sheet in Stoa's dress: rounded item slots, quality edges, item levels, durability words and inspect levels.
- Error guard: timers, frame scripts and hooks into Blizzard code are guarded, and `/stoa report` prints your version, game build and any caught errors ready to copy.
- Launch check (`/stoa check`): spell IDs, game functions and Blizzard frames are checked once per game build.
- One-page docs site in `docs/`.
- Release packaging: `Tools/package.sh`, a tag-triggered GitHub release workflow and a `.pkgmeta`.

## 0.9.0

First numbered build, for the WoW Forever beta (interface 16001).

- Core: event bus, modules, account and per-character saved settings, a schema version, and a settings backup you can copy as text (`/stoa backup`).
- Two states: the Grimoire console out of combat (leather panel, chat on its left page, Ready, Journey and Company pages) and the Halo in combat (health and mana arcs, signature spell, target and cast bar), with a 3 second calm-down.
- Layouts per role (Tank, Healer, Melee DPS, Ranged DPS) following your dual-spec slots.
- Bone, Tide and Graphite themes.
- Tank watch and target plaques, party cards, raid frames for healing, and fifteen click-casting bindings per role.
- Combat bar with up to two extra rows, and rounded action bars.
- Shadow and Paladin (Retribution and Protection) signatures, and self-buff reminders.
- Skins for Blizzard windows, minimap, top of screen, nameplates, damage meters and the swing timer; `/stoa safe` turns them all off.
- Quality of life: friend and guild invite acceptance, auto-invite by whisper, stranger invites declined, and comforts such as faster loot and gossip skipping.
- Welcome page for roles, theme and previews (`/stoa welcome`).
