# Changelog

Each release has a `## <version>` heading matching the `## Version:` line in `Stoa.toc`. The release workflow uses that section as the release notes, so a tag without one fails.

Pushing a tag such as `v1.0.1` runs `.github/workflows/release.yml`, which builds `Stoa-<version>.zip`, publishes a GitHub Release and uploads the same zip to CurseForge (project 1772375, newest WoW Forever game version) when the `CF_API_KEY` secret is set.

## 1.1.5

- Target plaque: the health bar is red again on a hostile target at full health (a theme pass was turning it back to the health colour), and the percent sign sits right after the number.
- Target plaque restyled: the portrait is a round medallion in a gold ring breaking the plaque's right edge, with the level on a badge at its foot; a thicker rounded health bar carries the percent and the health; a fine line under it shows the target's mana, rage or energy; and the target's cast shows as a small bar with the spell and time left (warm while it can be interrupted). Out of combat on the full console the plaque docks on the gold rim, as tall as your medallion and without its portrait (the level leads the caption instead): its left end fits round the medallion with a gold line following its ring, and at its right end the gold edge runs on round a rounded corner, then flows straight out of the curve into a long sweep down at 45 degrees into the rim like the medallion's flourish. The target of target stands behind that sweep as a lower slab of its own, with a softer gold edge, the same sweep at its end and the plaque's shadow falling on it. Creatures the game lists as "Not specified" no longer show that as their kind. Docked, it never fades with Fade frames out of combat, since it's part of the console, and its rows sit high so the health bar keeps clear of the rim. Without the console's art it rests just above the console instead. In a fight it moves beside the Halo as the full plaque. The art is new, so it needs a full restart of the game.
- Tooltips: under the sell price of a stack, an "Each" line with what one of them sells for.
- Experience bar: quests you've finished but not handed in show as a paler gold stretch past the fill, to where turning them in takes you; hovering the bar adds the count and the experience to Blizzard's tooltip in the corner (or shows its own when you aren't rested). Waits while OneForAll's own quest XP marker is on.
- Your buffs at hand (on by default): out of combat, small icons left of the Halo for your own long buffs when one is missing or has under a tenth of its time left (30 seconds to 2 minutes): Inner Fire, Fortitude, Divine Spirit and Shadowform for priests, an aura, a blessing and Righteous Fury for paladins, Mark of the Wild and Omen of Clarity for druids, Arcane Intellect and an armor for mages, Demon Armor for warlocks, Lightning or Water Shield for shamans, Trueshot Aura for hunters. They're drawn in your theme's colour. A missing one breathes softly, an ending one shows its time left. Click to cast; a buff you choose between (aura, blessing, armor, shield) casts the one you had on last. Hidden in a fight.
- What's new note brought up to 1.1.5.
- With OneForAll, STOA asks once whether to switch off OneForAll's low-rank check and info bar, which double up on STOA's Uprank and console.
- Sparkle: objects up close now get the plate the sparkle hangs on (the game only gives an object one with its interact plate setting on, which STOA now turns on for objects and keeps off for NPCs). Without it the sparkle had nowhere to sit.
- Interact icon up close also turns on the game's own sparkle on quest items lying in the world (its loot glow), as OneForAll's Quest loot sparkles does. Switching it off may need a restart of the game to take full effect.
- OneForAll, reviewed against 6.2.5: its Sparkle on herbs & ore, Quest loot sparkles, Hide error messages and Collect minimap buttons now count as shared jobs, so STOA's own copy waits while that switch is on. Before, STOA's combat errors switch turned the red text back on after every fight even with OneForAll hiding it, and both could try to gather the minimap icons.
- Sparkle steps aside for other addons that sparkle (Sparkles, Goldspark, NodeSight, or OneForAll with its sparkle on), so two glows never stack on one object.
- Focus: its block sits a little lower, so its panel no longer overlaps the target of target's.
- Sparkle on what's up close (on by default, with Interact icon up close): the herb, ore, chest or quest object the game's icon marks gets a soft gold glow with a few twinkling stars, so it's easy to spot. NPCs don't sparkle. The art is new, so it needs a full restart of the game.
- Interact icon up close no longer shows over low-priority things such as chairs and furniture, only things worth using (herbs, ore, quest objects, chests).
- Accept quests leaves low-level (grey) quests alone: they're never picked from an NPC's list or accepted for you.
- Chat tabs: a whisper arriving in a chat window you aren't looking at (such as a Whispers tab) puts a gold dot on its tab that pulses a few times and stays until you open it.
- Shift to stop the comforts now also counts a press in the last moment (the NPC's window or the loot opens a beat after you click, often after Shift is let go), and a talk begun with Shift stays yours until the NPC's windows close, so picking a quest from the list doesn't auto-accept it.
- Talents and spellbook window: its dark header now rises fully above the window, so the talent art no longer covers its lower half.

## 1.1.4

- A short what's new note shows once after updating, for your shield and your class mark. /stoa news shows it again.
- Your shield: a painted silver shield with a soft drop shadow, whose fill drains smoothly as it soaks up damage, the emptied part dark slate. It sits in the open corner left of the medallion's ring while the full console is open, and under the Halo's health number in every layout. A switch under Combat turns it off.
- Your class mark: the buff your class keeps up, a painted silver emblem like the shield, emptying as it runs out. Warriors get Battle Shout (a horn), rogues Slice and Dice (a dagger), paladins their seal, shamans Lightning or Water Shield (an orb, by charges) and priests Inner Fire (a flame, by charges). It sits under the Halo's power number, and beside the shield left of the medallion. In a fight timers run from your own cast and charges hold at the last count seen. A switch under Combat turns it off.
- The experience bar in STOA's dress: a thin flat bar in a rounded dark track, experience in the accent like the medallion's bezel, the rested stretch in blue with a fine blue line where it ends, and Blizzard's segment dividers as fine dark notches. Reputation, honor and the other bars that share its place get the same track, reputation coloured by standing. Edit Mode still places it, and a switch under Windows turns it off.
- The experience bar fades out in a fight and back after, like the console (a switch under Windows), and its notches show only over the filled part.
- Missing Inner Fire, or a missing seal in a fight, shows as the class mark empty and dimmed, in place of the warning words above the bars and in the console's Ready column. Without the mark (switched off, or the Slim console out of a fight) the words stay.
- Fixed: your shield could show as all dark slate while it was up. In a fight the amount is secret and was handed to the fill with a glide, and a secret can't glide, so the fill stayed empty; it is now set straight. A measure of what the shield held also expires after a minute, so one taken when the amount was nothing can't leave later shields dark.
- The shield and class marks redrawn simpler (a clean shape with one highlight) so they read at their small size, and the line where they drain shows more clearly.
- Hovering the shield or the class mark beside the medallion says what it is: how much damage the shield still absorbs, or the buff with its time or charges left (or that it's missing) and what it does.
- Highlight quest objects is now Interact icon up close: Forever's client has no outline round objects (Blizzard cut the option), so only the game's icon over the object you can use, within reach, is turned on. The outline settings earlier versions set are handed back.
- Bags: items your quests still need (an item goal in your quest log not yet met, such as Scaber Stalk 2/5) get an accent edge, and junk selling never sells them.
- The Halo's timer coins (DoTs and buffs you keep up, such as Shadow Word: Pain and Devouring Plague) fade to a faint outline when they're off instead of turning orange, like an unticked line on a checklist; they keep their place, and pale gold still marks the last seconds.
- What's new: lines about one class or a few now carry class tags in class colour beside the headline, and the note is a little wider to fit them.
- Character window: the close cross sits level with your name in the header instead of halfway down it.
- At a glance: long labels shortened so they fit beside their figure: Gold rate, and Enchant, Smithing, Engineer, Leather, Jewels and Scribe for the long profession names.

## 1.1.3

- Focus: STOA hid Blizzard's focus frame without showing the focus anywhere unless you healed it. Your focus now has a small block under the target of target, friend or foe, in and out of combat, and can be moved. A switch under Combat brings back Blizzard's instead.
- A short what's new note shows once after updating, for target of target and focus, the shield, druid form mana and Speed. /stoa news shows it again.
- The console's gold medallion lines no longer reappear over the folded console after a window opens for the first time.
- Send Mail: the Mine button no longer covers Postage. It is now a small arrow inside the To box that lists your characters and recent names. The mail window's header is a little shorter, so the To and Postage rows no longer touch it.
- Druids: mana while in cat or bear form now shows in combat too (it only showed out of combat).
- Target of target: who your target is targeting shows to the right of the target plaque, a name and a thin health line, and says YOU when it is you. Click it to target them. It takes the target's look: a small panel beside the plaque, bare words beside the words-only target. A switch under Combat turns it off.
- Drawn glyphs replace font symbols: close crosses, fold plus and minus, the mail window's page chevrons, the Shift arrow on the combat bar and the dot between words are now STOA's own art, and several lines read with plain punctuation instead.
- At a glance: a Speed line you can add (under Stats), your movement speed as a percentage of plain running.
- Training page: Mind Soothe, Shackle Undead and spells Forever opened to every race (Devouring Plague, Fear Ward) are no longer left out. Visit your class trainer once so STOA sees what it offers.
- The shield tag on party cards and the tank watch card is now a small shield that empties as the shield absorbs damage, with its timer beside it, in place of the word SHLD.
- New, off by default: Highlight quest objects (Settings, Everyday) turns on the game's own outline around things you can use in the world and the icon over the nearest one. Switching it off puts the game's settings back.

## 1.1.2

- STOA Slim's Edit Mode layout no longer shows the ranged swing bar. The saved layout refreshes at your next login.
- Removed "Hide the bars until mouseover": the bars along the bottom always show out of combat. The what's new note now mentions Your own mix.
- Tooltips: the title and the line under it sat 2 px further in than the lines below; all now share the game's left margin (seen on the bags' money list).
- Quest lines on tooltips no longer step in from the other lines or carry a gold rule; they keep their slightly lighter box and line up with the rest of the card.
- Fixed a stray indent on one line of the bags' money list and other tooltips, left over from a quest box on the tooltip before. In the money list, the character you are on now has its sum in bright text and the others are quieter.
- The kill skull on nameplates is smaller, in plain bone, and sits at the left end of the bar instead of above its right end.
- With Does It Die installed, the welcome's Other addons step now asks who marks the nameplates (STOA's marks or Does It Die's), so the question after login is not needed.
- The DoT stretch on the target bar and on nameplates is now fine dark diagonal stripes, a faint dark wash and a soft inner shadow at its left edge over the bar's own colour, with a fine dark line where the health will land, so it reads as damage on its way on a bar of any colour.
- What's new: after an update that brings something worth knowing, your first login shows a short note once per account (this time: Slim, Minimal and the quest list folding in combat). New installs don't see it, small fixes don't bring it back, and `/stoa news` shows it again.
- The healer's party row hangs a little lower under the Halo, clear of the cast bar and the reminder words, and the sample party (`/stoa test`) moves the combat bar below it as a real one does. Without the combat bar, the pet row sits under the party row instead of on it.
- Two more hidden widths from the game in a fight (the click grid's names, words set before their face loaded) can no longer raise an error.
- Settings, Setup: a new group, Your own mix, puts the parts of the layout in one place to mix as you like: Console (Full, Slim line or None), Party when not healing (Cards or Strips), Target (Plaque or Words only), Target and party out of combat (Full strength or Faint) and Health and mana out of combat (On the console or Faint arcs). They replace six switches that were spread over three pages. How much STOA still sets them all at once, and the welcome page's How much STOA step has a Mix your own button that opens the group.
- Healing a raid: the grid sits right under the Halo like the party row, with the combat bar's rows below it, so it stays clear of the action bars out of combat.
- Action bars: the "Extra rows on mouseover" setting is gone. It hid your second and third bars out of combat until the mouse was over them, which left players unable to find the bars the combat rows mirror; the old Quiet preset turned it on. Every row now shows out of combat for everyone. "Hide the bars until mouseover" stays for those who want the bars away, and is off unless you turn it on.
- Does It Die: STOA's nameplate marks used to wait, without saying so, until you found and turned off Does It Die's own "Show on nameplates". STOA now asks once whether to use its marks and turns that switch for you, and Settings, Combat has one choice, DoT marks on nameplates (STOA, Does It Die or Neither), that sets both sides.
- Housekeeping: six functions nothing called any more are gone.

## 1.1.1

- Full keeps the party cards and the solid target plaque. The party strips and the target without a panel that 1.1.0 gave everyone now come with Slim and Minimal only; each still has its own setting (Party as strips when not healing, Target without a panel). Each character is set once from the console it uses.
- Party: a hidden width from the game in a fight no longer switches the party frames off (their health then stopped updating). Tags judge their width from the letters instead. The same goes for a hidden bar width under the tags, which raised an error on targeting in a fight.
- The tank watch shows your Shield, Renew and Weakened Soul as the same tags the party cards carry, in place of a line of words, and a friendly target carries them too.
- The healer's party row sits right under the Halo and stays there: it no longer moves when a fight starts or ends, so it can't be caught on top of the combat bar or the action bars. The combat bar's rows (and your pet's row) stand below it while you heal a party.
- The emergency item steps under the party or raid frames when they share its spot beside the Halo.
- Money across your characters (the bag's money hover, `/stoa alts`): a character's gold is no longer written down as 0 while it loads in or logs out. Characters already showing 0 correct themselves the next time you log in on them.

## 1.1.0

- Slim console (How much STOA: Slim, or Settings: Slim console): the console as one plain line a quarter of the height. Level and experience on the left, health and mana either side of a small portrait, and a word each for Ready, Journey and Company on the right; mouse over those and their pages open on a card. Chat and the action bars stand above the line, on STOA's own Edit Mode layout for it ("Stoa Slim"), and At a glance is left out. It still folds in a fight.
- Minimal (How much STOA: Minimal): no console at all. Out of combat your health and mana rest as two faint arcs around your character and the Halo rises in a fight; the target plaque and party cards rest faint until a fight starts or the mouse is over them. STOA's look and comforts stay. Each part is its own setting too: Faint health and mana out of combat, Fade frames out of combat.
- Action bars: Hide the bars until mouseover (off by default) rests every bar along the bottom, the main bar too, out of combat.
- With the console off, changing the In combat setting no longer raises an error.
- Finish and reload on the Welcome page, and "Use STOA's" when two addons do one job, now reload with the click itself. The game sometimes refused the reload STOA asked for and left you to type /reload.
- Minimal: Blizzard's gryphons and bar art stay hidden, the game menu and bags rest as the quiet tray in the bottom right corner, and the chat stands in the bottom left. With the console off nothing was looking after them.
- Slim: the "Stoa Slim" Edit Mode layout hides the Cooldown Manager's rows and moves the swing timers up clear of the bars. A saved one updates at the next login while it is the active layout.
- Changing Combat rows during practice combat no longer hides the combat bar until practice ends.
- Slim: the portrait seal fades out with the line in a fight instead of peeking over it.
- Slim: the hover card sits above the quest list, which was reading through it.
- Party, when you tank or deal damage: thin strips beside the Halo in place of the cards. A name, health and a hairline bar each, with a word when you can act; they rest faint while everyone is fine, turn amber below half health and brighten under the mouse or as your target. Healers keep the cards. A spot saved for the old cards is let go once. (Settings: Party as strips when not healing.)
- Target: words and a bar over the world with a small portrait, level with the Halo, in place of the solid plaque. (Settings: Target without a panel.)
- STOA's Edit Mode layouts hang the quest tracker a little lower, so "All Objectives" no longer runs into the coordinates under the minimap. Saved layouts update at the next login while active.
- Minimal has its own Edit Mode layout, "Stoa Minimal", with the Cooldown Manager's rows hidden.
- The quest list folds to its header in combat (it used to dim) and comes back after; hover the header to open it. Practice combat folds it too. Settings: Fold quest list in combat.
- Welcome page: Slim's description fits its card again (it ran a third line into the next card).
- Quiet: no longer hides the extra bar rows until mouseover, and has its own Edit Mode layout, "Stoa Quiet", with the Cooldown Manager's rows hidden.
- STOA describes itself as a focused UI, not a calm one.

## 1.0.1

- Combat rows: clicking a button with the mouse casts it again (it did nothing with the game's "cast on key down" setting on).
- Party cards, raid cells and the tank watch: hovering shows where that player is (their zone) under the usual tooltip.
- Company: inviting a Battle.net friend goes through Battle.net, so it finds them (it asked for their server's inner realm name and got "Cannot find player").
- Combat rows are back in their first order: your main bar, then the bottom-left bar (Action Bar 2), then the bottom-right bar (Action Bar 3).
- Bags: the reagent bag opens with the combined bag as its bottom section, under a quiet label with its free slots, in the same ten columns, above the footer (Settings: Reagents in the bag). It opens and closes with the combined bag.
- Bags: currencies you tick "Show on Backpack" in the Currency tab sit in the footer beside the free count, in place of the game's own row.
- Bags: the search box runs the bag's full width.
- Bags: hover your money for every character's gold, richest first, and the total.
- Money shows the game's gold, silver and copper coin icons after each amount, as the money hover does (bags, trainer, loot tally, console).
- RestedXP: the STOA look comes back after a relog. RestedXP loads before STOA, so it drew its own theme until something changed it.
- In a fight Forever hides everyone's auras from addons, so your Shield, Renew and Weakened Soul on the party cards, the tank watch and the Discipline SHIELDS / RENEW count now come from your own casts (who you cast on and how long it lasts). A shield that breaks early still shows until its time is up.
- Party cards: tags stay inside the card. One that would run past the edge drops its timer first, then steps out.
- Party cards: buff tags drop their vowels to fit more on a card (SHLD, RNW, RJV, MNDNG, FRDM...).
- RestedXP: the waypoint arrow in the STOA look is matte black with a pale edge and soft glow, so it still shows in caves and at night.

## 1.0.0

The first release for WoW Forever's launch: every class has a signature, and every part of the screen is in STOA's dress. Settings from 0.9 carry over. Below is everything that changed since 0.9.0.

- RestedXP in STOA's look: a STOA theme for its guide window in your theme's colours and type, offered like Bagnon's and Details' (/stoa looks).
- Tooltips: quest lines sit in their own box with an accent rule, the quest name in the accent and your count picked out; finished objectives go quiet.
- Upgrades for healers: "Increases damage and healing" now counts in full, so a healer's wand or staff with it no longer scores as nothing.
- Upgrades: a slot only counts as empty when nothing is in it, so a worn wand or weapon the game reads oddly is no longer "empty".
- Discipline: SHIELDS and RENEW sit beside the lowest coin, clear of the mana number.
- At a glance: clicking a profession opens that profession, and clicking a stat opens the character sheet without an error.
- Quest rewards: when your weapon has no stats, UPGRADE now goes to the choice worth most, not the first one listed.
- Combat rows: two rows now show Action Bars 1 and 3; three rows add Action Bar 2.
- Cast bar: pressing another spell mid-cast no longer hides the bar; a fail or stop only ends it once nothing is casting.
- Does It Die on nameplates: STOA's nameplates show your DoTs' damage left as a bone stretch and a small skull when they'll kill, once Does It Die's own "Show on nameplates" is Off. The Welcome suggests Does It Die to DoT classes that don't have it.
- Raid markers: the marker strip for group leaders is gone, as its buttons did not mark in game.
- Target card: the name is set again a moment after each new target, so it no longer comes out blank; stack counts on its aura icons sit inside the corner with an outline, and clear when an aura has none.
- Guild & Communities: a slimmer header band, and the channel dropdown, chat, member list and online count start a little lower, so they sit clear of the header.
- Console: section headings such as READY are set again each time the console shows, so one that came out blank at login fills in.
- Moving windows: the world map joins the Shift-drag windows while it is windowed; maximised it keeps filling the screen.
- Target card: the aura icons above or below it show their tooltip on hover.
- Blocked actions: when the game refuses an addon a protected call ("Interface action failed because of an AddOn"), `/stoa report` now lists the addon and function it named. Every reload STOA asks for says so in chat if the game blocked it, so you can type /reload to finish.
- Hostile red: enemies get their own red (a `hostile` colour in every theme) on nameplates, the target card and tooltip names, apart from the amber the warnings use, so a hostile reads at a glance. Colour vision modes keep their own safe pick for it.
- Mailbox: the inbox is a row taller with Take gold on, so Take gold and Open All share one row and the Prev and Next page buttons have their own below (Take gold used to sit on Prev).
- Welcome: Finish reloads even when one of its settling steps fails (another addon's switch, a layout the game won't take); the failure is kept for /stoa report instead of leaving a chat line and no reload.
- Console corner: the bag slots and game menu are a quiet tray now. Their stone frames, backings and sockets are gone; the menu glyphs and the bags themselves rest in bone and warm to the accent under the mouse, sitting on the console's brass edge. Bag windows name themselves in label size and long names end in an ellipsis before the close cross.
- Settings: the toggles' knob and the theme swatches in dropdowns draw again (they were created without a texture, so a switch read as a plain gold bar). Threat meter rows are rounded bars; At a glance's hover is rounded; STOA's own pages share one margin; buttons sink while pressed and go muted while disabled.
- Settings: every switch has a description now (party and raid frame hiding, chat air, merchant selling and repairs, invites, duels, raids when full), Shift held while opening a merchant keeps your greys and gold, and the DoT settings group is named DoT kill marks.
- Text size: a setting in Look (Standard, Larger, Largest) scales every STOA size together, and the smallest text never drops below 13 pixels on the screen whatever the UI scale, so captions, tooltips and nameplate cast names stay readable on a tall monitor at a low UI scale. Every outlined word over the world now carries the same soft shadow.
- Class signatures checked against Forever's launch notes: Shadow Word: Death is back in the Shadow next press (it arrives at level 32), Twist of Light is gone from the Paladin signature (Forever removed the talent), the Warlock coin is named Bane of Agony. Settings and the welcome page say what's true now: settings are per character, setup is a few short steps. The repo carries a LICENSE (all rights reserved; fonts under the OFL).
- The threat meter sits to the left of the combat bar in a fight, instead of at the screen's edge under the damage meters.
- Every Blizzard window (map, character, spellbook and the rest) wears one header: a dark embossed metal plate, full width, rising a little above the window, with the title larger in the display face.
- Settings are per character: each keeps its own, and a new character starts from the last one's (Saved setups still copies another's). The combat bar's keys sit small in each button's corner (⇧ for Shift) and every row is the same size on the same columns. In combat the quest list dims to the quest you're working on, and the game's damage numbers are drawn smaller so they cover less of the Halo.
- Narrow screens and large UI scales: the console's pages keep clear of health, mana and the action bars, dropping a column instead of overlapping; the chat wraps sooner; and STOA's Edit Mode layout has a compact version (bars stacked under the medallion) that STOA switches to and from by screen width (`/stoa editmode wide` keeps the wide one).
- More procs: Hammer of Wrath and Infusion of Light (Paladin), Searing Light (Priest), Eclipse (Druid), Maelstrom Weapon (Shaman), Conflagrate (Warlock) and Cutthroat (Rogue). Procs only the game can see (Redoubt, Vengeance, Reckoning, Martyrdom, Nature's Grace, Rapid Killing, Quick Shots, Remorseless Attacks, Thousand Cuts) show as small game-drawn coins above the Halo. Proc art is found by file ID, with STOA's own arc if a picture is ever missing; `/stoa procs list`.
- Tooltips grow by the room the header adds, so the last line no longer runs over the bottom edge.
- Launch night: the stone behind windows is much fainter (it read far too strong in the game), the world map's border no longer lays a panel and stone over the map, gossip options read light on the dark window, and At a glance names where you are quietly beside its heading.
- Every class has a signature now. Warriors: Rend, Sunder Armor and Battle Shout coins (Sunder, Thunder Clap and Demoralizing Shout for tanks), SUNDER n/5 and your stance under them, TAUNT for tanks. Rogues: Slice and Dice, Rupture and your big cooldown, COMBO n under them (the game drew combo points on frames Stoa hides). Hunters: Hunter's Mark, Serpent Sting and Rapid Fire, NO ASPECT when none is up. Warlocks: Corruption, Curse of Agony and Immolate coins, SHARDS n and TAP. Shamans: Flame Shock, your shield with its charges and Earth Shock (Nature's Swiftness and Mana Tide for healers), TOTEMS n/4, and the game's totem bar now moves under the Halo instead of vanishing with the player frame. Each has a next-press outline of its own before falling back to the game's suggestion.
- The Training page's icons get their round mask again.
- Shadow: the next-press outline follows a `/castsequence` macro on your bars. The macro lights when its next step is the press, and so does that spell's own button (Combat > Shadow priest).

- Pets: a pet plaque in a fight, its health as an inner arc on the Halo, a pet row under the combat bar, a pet coin on the medallion (click to feed), pet reminders, and pet cells under party cards for healers. Settings > Combat > Your pet.
- Restock: each character keeps a list of things to carry (candles, ammo, poisons, food, water) and how many; vendors top it up in whole bundles. Settings > Comforts, `/stoa restock`.
- Mail: Take gold beside Open All, a line saying what Open All took, and a Mine button listing your characters and people you mailed lately.
- Characters: every character notes its level, money, rest, lockouts, bags and bank. Item tooltips count copies on your other characters; `/stoa alts` lists them.
- Gear for each spec: the equipment set you wore in a spec goes back on when you change to it.
- Hover keybinding: `/stoa bind` or `/stoa kb`.
- Away screen: the camera turns round your character with your name, rest, time away and whispers while you're away. `/stoa away` to see it.
- Fixed the trainer page's rounded icon mask path.
- The stone behind windows is stronger, its rings clear from just under the header down.
- Stoa's own settings window (`/stoa`, or the button under Options > AddOns > Stoa): ten pages in the order you look for things, a search box that also knows other words (camera, aggro, clique...), and a notes column saying what the setting under the mouse does, what it usually is, whether it waits for a reload, if it changes one of the game's settings and the `/stoa` words for it. Choices are drawn in the theme, with theme colours in the theme list and keys to move through it. A footer counts changes waiting for a reload with a Reload button, and "Defaults for this page" puts a page back.
- Everything that was only a `/stoa` command now has a control: invite words, items to always sell, spells you skip at the trainer, minimap icons kept out of the tray, At a glance lines for each place with pins, sample party and raid frames, the proc and logging samples, putting windows and frames back, loot totals, rank upgrades, the launch check and safe mode.
- On a pull countdown (Combat page): when a leader starts the game's pull countdown in a raid, the console folds and the Halo rises straight away; a cancelled countdown, or no fight soon after, opens it again. In raids by default, or any group, or never.
- "Fold without the slide" is now "How the console folds: Slide or Instantly", and proc art explains what the game does and what Stoa changes.
- Logging reminder: entering a dungeon or raid with combat logging off, a plaque says NOT LOGGING with a Start logging button (for Warcraft Logs); logging Stoa started stops when you leave. Settings > Comforts, `/stoa log`.
- Share layout (`/stoa layout`, or on the backup page): a short line with where your frames sit in every role and the look, safe to post for others; importing one keeps the rest of your setup.
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
