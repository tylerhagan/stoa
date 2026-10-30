# Changelog

Each release has a `## <version>` heading matching the `## Version:` line in `Stoa.toc`. The release workflow uses that section as the release notes, so a tag without one fails.

Pushing a tag such as `v0.9.1` runs `.github/workflows/release.yml`, which builds `Stoa-<version>.zip` and publishes a GitHub Release.

To also publish to CurseForge, Wago and WoWInterface once the repository is public: add the project IDs to `Stoa.toc` (`## X-Curse-Project-ID`, `## X-Wago-ID`, `## X-WoWI-ID`), add `CF_API_KEY`, `WAGO_API_TOKEN` and `WOWI_API_TOKEN` as repository secrets, and add a step running `BigWigsMods/packager@v2` to the workflow (checkout with `fetch-depth: 0`). The `.pkgmeta` is already in place. The packager step is left out for now on purpose.

## Unreleased

Everything below is on the launch branch and not yet in a numbered release.

- Health and power bars glide to a new value instead of jumping (Settings > Look, on by default).
- Buff words on party cards and group buff reminders match spells in the game's own language, not just English.
- Read the game's Cooldown Manager (Settings > Cooldowns, off for now): Halo coins and the next-press outline ask the game's Cooldown Manager whether a spell is ready or a buff is up, which it knows in combat. `/stoa cdm` shows what it tracks and what Stoa can read.
- Game settings Stoa changes (far camera, map fade, target plate size, combined bags, proc art) are noted with what they held before; switching the part off puts them back, unless you've changed them since. `/stoa restore` puts them all back.
- Hairlines and borders stay exactly one screen pixel at any UI scale or resolution.
- `/stoa report` also lists your screen size and UI scale, game language, the game settings Stoa holds and your other addons.
- Stoa stays off (and leaves its settings alone) when loaded on a game version other than WoW Forever.
- Icon tray: other addons' minimap buttons gather into one small button below the map; click it for a tray of their icons (`/stoa tray`).
- Pawn: with Pawn installed, Stoa's upgrade marks give Pawn's answer, and Stoa leaves Pawn's own marks to it.
- Training page (`/stoa trainer`): spells waiting now and at the next two training levels, with prices learned from your trainer; right-click to skip a spell. The Journey line shows the cost.
- With DoesItDie installed, the target plaque shows how much your DoTs will still deal on its health bar, and a skull over the portrait when they'll kill it.
- Combat switch: choose how long the console waits after a fight (1, 3, 5 or 8 seconds), wait for your group between pulls, keep the console open in combat, or fold without the slide. The console and the Halo are one choice (fold with the Halo, open with the Halo, open with no Halo), so the console never folds with no Halo to replace it.
- The welcome page is now a step-by-step wizard: start (by hand, a saved setup from any alt, or as Stoa ships), specs, look (every class theme), in combat, how much, other addons (when found) and a summary; one reload on Finish.
- Saved setups: each character's setup is kept account-wide at logout; load it on an alt from the backup page, the welcome page or `/stoa setups`.
- Stoa's look for Questie's tracker, Bagnon's bags and Details' meters, offered once (`/stoa looks`); Stoa's fonts in LibSharedMedia.
- Details, Skada and Recount join the "two addons, one job" check; Leatrix Plus's switches win where it and Stoa do the same job.
- Spell art behind the letter in the Halo's coins (a setting).
- OneForAll: Stoa works beside it. Small jobs both do (fast loot, junk, repairs, loot feed, quest help, camera, window moving, chat copy, upgrade marks, invites, duels) go to OneForAll while its switch is on; Stoa keeps the minimap and chat rail and waits for OneForAll's welcome page. At a glance gets Library Books and Dungeon guide lines.
- Other addons: when a known bag, nameplate, chat, tooltip, bar, minimap, group frame, click-casting, window mover or map addon is loaded, Stoa asks which one should do the job, and its own part waits until you choose; `/stoa addons` asks again. A whole UI like ElvUI or SpartanUI doesn't work beside Stoa: Stoa says so and offers to turn either off.
- Tally is now called At a glance; `/stoa glance` (the old `/stoa tally` still works).
- New console art: a bigger medallion ring held by a slender brass bracket either side; the portrait is a size larger (new textures: restart the game once).
- The Stoa wordmark on the welcome page and the logo as the addon's icon.
- Small figures: gear wear as ten cells and bags as a column each on Ready; the XP bar shows rest and where an hour at your pace takes you, with a pace line chart; At a glance lines carry slim bars, bag columns and a gold-an-hour chart.
- At a glance follows where you are (world, dungeon, raid sets, with pinned lines in all), explains each line on hover and opens the matching window on click.
- Procs: the game's own proc art either side of the Halo and its proc glow on the combat bar, for the game's proc events and for procs Stoa reads itself (a spell turning usable, costing nothing or casting much faster); `/stoa procs test`.
- Game-drawn auras: a helper for Forever's aura container, which shows buffs and debuffs with real timers in combat; `/stoa auras` tests it on launch day.
- Nameplate styles: Stoa, Bold, Inline, Brass and Slim; the target marked by edge, arrows or glow; other plates can fade and the target can grow.
- Chat: a time column on each line, more space between lines, the chat buttons in one quiet column, and a quiet typing strip.
- Buffs as a list (name and time left), click grid shows each spell's cost and dims what you can't afford.
- Comforts: hide other people's duel results and drunken lines, decline duels, release in battlegrounds, accept resurrections.

- Minimap: a square with rounded corners by default, framed like Stoa's windows; the round map is a setting (new texture: restart the game once).
- Shared core for every feature: spellbook ranks and costs, item worth and junk, the group as a list, mana and the five-second rule, show rules (combat, group, raid, solo, target, mouseover), settings per spec, and unit events for just the units that matter. Raid cells redraw at most ten times a second.
- Combat rows, the click grid, the bar tray and the tally now keep their own setting in each spec.
- Mana play: a quiet spark for the five-second rule and regen ticks, cast cost shaded on your mana, and druid mana while shapeshifted, on the Halo and the console.
- Auto-uprank: new spell ranks replace older ones on your bars (`/stoa uprank`).
- Quest rewards: the best choice is marked UPGRADE or VALUE.
- Junk list: mark items from the bag, sold with the greys; `/stoa junk`.
- Loot feed above the chat, with gold an hour and loot value for the tally; `/stoa loot`.
- Threat meter under the damage meters, and PULLING AGGRO on the target plaque for non-tanks.
- Raid marker strip for tanks and leaders, Shift-click for world markers.
- Group buff reminders on the console's Ready page and during ready checks.
- Chat: clickable web addresses with a copy box, copy chat, and chat kept across reloads.
- Map: fades while you move; zone level ranges on the map and minimap.
- Tooltips: herb and ore nodes show the skill they need against yours.
- Unlock mode: frames snap to edges, centres and other frames (Shift drops freely); a frame snapped to another moves with it.
- Welcome page presets: Full, Quiet and Classic feel; `/stoa preset`.
- `StoaAPI` for other addons: tally lines, Stoa's messages, colours and fonts.
- Colour vision setting: Standard, Red-green, Blue-yellow or No colour, laid over any theme; also on the welcome page and `/stoa vision`. Each set is checked by `Tools/art/cvd_audit.py` (simulated colour blindness, CIEDE2000 difference, WCAG contrast).
- Tide's text is a step dimmer so its white warnings stand out; Druid's warning is pale yellow rather than near-white.
- Tally beside the chat: up to eight chosen numbers (stats, gear, gold, professions, world, LibDataBroker feeds), role defaults, right-click picker and /stoa tally.
- Windows: header band (tinted by the window's job), shadow line, dark footer tray, wells, tabs dressed under the window, 10px corners; the stone softer and fading towards the top.
- Tooltip cards: a header band with room around the name, rank outlines (elite gold, rare silver, boss heavier gold) with the rank or item quality colour fading across the header, difficulty as a word (TRIVIAL to DEADLY, ELITE, RARE, BOSS), target, casting, threat, players' item level, an upgrade line against worn gear, owned counts, shorter cards in combat, cursor or console position.
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
- Console art re-cut from the new leather painting: the brass ring runs whole under the seal. Painted ornament setting (minimap frame, plaque coins, Halo signature slot) with the lean leather-and-brass minimap frames and the slim-inner coin ring (new textures: restart the game once).
- Raid markers go through the game's /tm command on secure buttons, as Forever blocks addons from marking directly.
- Quest items: a small row beside the Halo with a button for each item your quests ask you to use.
- Emergency item: your healthstone, best healing potion or bandage beside the Halo, lit with LOW when your health is under 40%.
- Timers: flights show where you're going and the time left (known flight times, or timed and remembered the first time); breath, fatigue and feign death in the same slim bar. `/stoa timers` shows a sample.
- Gear scores by Stoa's own stat weights for your class and role, shifting with level: tooltips show UPGRADE +n%, bags mark upgrades UP, quest rewards pick by score.
- Trainer: Journey counts the new spells and ranks waiting at your trainer, with a note on level up and `/stoa trainer` to list them.
- When the game hides auras, buff reminders and aura lists stand down instead of calling a buff missing.
- Settings kept per spec (combat rows, click grid, bar tray, At a glance) now stay with the character: a second character no longer starts with the first one's values.
- Small helpers every module used its own copy of (safe calls, aura lookups, hiding textures) live once in `Core/Util.lua`.
- The README says what Stoa is not.
- The welcome page shows Full as the chosen start and, as you hover Quiet or Classic feel, says exactly what each changes against it.
- One combat clock: the Halo's coins, combat bar and procs share a single 0.2 s tick that runs only in combat, and the Halo and console listen to player and target events only, so a raid's unit events no longer wake them.
- The offline load test fails on any game function Stoa calls that Forever's UI source doesn't have (`Tools/sim/api.txt`, built by `Tools/sim/apilist.py` from Blizzard's source).
- `Tools/sim/run.py`: an offline load test that loads every file under a mock of the game, fires the login and combat events (with secret values) and runs every `/stoa` command.

## 0.9.0

First numbered build, for the WoW Forever beta (interface 16001).

- Core: event bus, modules, account and per-character saved settings, a schema version, and a settings backup you can copy as text (`/stoa backup`).
- Two states: the Console out of combat (leather panel, chat on its left page, Ready, Journey and Company pages) and the Halo in combat (health and mana arcs, signature spell, target and cast bar), with a 3 second calm-down.
- Layouts per role (Tank, Healer, Melee DPS, Ranged DPS) following your dual-spec slots.
- Bone, Tide and Graphite themes.
- Tank watch and target plaques, party cards, raid frames for healing, and fifteen click-casting bindings per role.
- Combat bar with up to two extra rows, and rounded action bars.
- Shadow and Paladin (Retribution and Protection) signatures, and self-buff reminders.
- Skins for Blizzard windows, minimap, top of screen, nameplates, damage meters and the swing timer; `/stoa safe` turns them all off.
- Quality of life: friend and guild invite acceptance, auto-invite by whisper, stranger invites declined, and comforts such as faster loot and gossip skipping.
- Welcome page for roles, theme and previews (`/stoa welcome`).
