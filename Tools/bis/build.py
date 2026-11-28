#!/usr/bin/env python3
"""Build Data/BiS.lua from a WoWSims Forever checkout.

WoWSims Forever (github.com/wowsims/forever, MIT licence) keeps a simmed
gear set for each spec build, an item database with every item's stats and
sources, and stat weights per build. This script reads the sets each spec's
presets.ts actually offers, ranks the next items for each slot by the
build's stat weights (the alternates), and writes one Lua table STOA reads.

    python3 Tools/bis/build.py /path/to/wowsims/forever [--out Data/BiS.lua]

The output is deterministic, so a run that finds nothing new leaves the file
unchanged (the weekly workflow opens a pull request only when it changes).
"""
import argparse
import base64
import json
import os
import re
import subprocess
import sys
import zlib

# STOA's slot order, matching the game's inventory slot ids.
SLOTS = [
    ("HEAD", 1), ("NECK", 2), ("SHOULDER", 3), ("BACK", 15), ("CHEST", 5),
    ("WRIST", 9), ("HANDS", 10), ("WAIST", 6), ("LEGS", 7), ("FEET", 8),
    ("FINGER1", 11), ("FINGER2", 12), ("TRINKET1", 13), ("TRINKET2", 14),
    ("MAINHAND", 16), ("OFFHAND", 17), ("RANGED", 18),
]
# WoWSims' siml slot words, in the same order.
SIML = ["head", "neck", "shoulder", "back", "chest", "wrist", "hands", "waist", "legs", "feet",
        "finger1", "finger2", "trinket1", "trinket2", "main_hand", "off_hand", "ranged"]
# WoWSims ItemType for each slot.
ITEM_TYPE = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 11, 12, 12, 13, 13, 14]

# Every build STOA offers: class file, STOA role, WoWSims spec folder, the
# build's name, its gear source, the weights to rank alternates by (the
# presets.ts name, or None for no alternates) and "preraid" or "raid".
# Only sets the spec's presets.ts imports are listed: the others in a
# gear_sets folder are leftovers WoWSims no longer offers.
BUILDS = [
    ("PRIEST", "RANGED", "priest/dps", "Shadow", "defaults.siml", "Shadow", "preraid"),
    ("PRIEST", "HEALER", "priest/healer", "Healer", "gear_sets/preraid.gear.json", "Disc Raid Healing", "preraid"),
    ("PALADIN", "MELEE", "paladin/retribution", "Unsealed Wrath", "gear_sets/default.gear.siml", "Unsealed Wrath", "preraid"),
    ("PALADIN", "MELEE", "paladin/retribution", "Holy Shock", "gear_sets/holy_shock.gear.siml", "Holy Shock", "preraid"),
    ("PALADIN", "TANK", "paladin/protection", "Protection", "gear_sets/default.gear.siml", None, "preraid"),
    ("PALADIN", "HEALER", "paladin/holy", "Holy", "gear_sets/default.gear.json", None, "preraid"),
    ("DRUID", "RANGED", "druid/balance", "Balance", "defaults.siml", "Default", "preraid"),
    ("DRUID", "MELEE", "druid/feralcat", "Cat", "gear_sets/pre_raid.gear.siml", "Cat", "preraid"),
    ("DRUID", "MELEE", "druid/feralcat", "Cat, level 60", "gear_sets/default.gear.siml", "Cat", "preraid"),
    ("DRUID", "TANK", "druid/feralbear", "Bear", "gear_sets/default.gear.siml", "Bear", "preraid"),
    ("HUNTER", "RANGED", "hunter/dps", "Weave", "gear_sets/prebis_weave.gear.siml", "Weave", "preraid"),
    ("HUNTER", "RANGED", "hunter/dps", "Weave, cheap", "gear_sets/prebis_weave_cheap.gear.siml", "Weave", "preraid"),
    ("HUNTER", "RANGED", "hunter/dps", "Turret", "gear_sets/prebis_turret.gear.siml", "Turret", "preraid"),
    ("HUNTER", "RANGED", "hunter/dps", "Turret, cheap", "gear_sets/prebis_turret_cheap.gear.siml", "Turret", "preraid"),
    ("HUNTER", "MELEE", "hunter/dps", "Melee", "gear_sets/prebis_melee.gear.siml", "Melee", "preraid"),
    ("HUNTER", "MELEE", "hunter/dps", "Melee, cheap", "gear_sets/prebis_melee_cheap.gear.siml", "Melee", "preraid"),
    ("MAGE", "RANGED", "mage/dps", "Arcane", "gear_sets/preraid.gear.json", None, "preraid"),
    ("MAGE", "RANGED", "mage/dps", "Fire", "gear_sets/preraidFire.gear.json", None, "preraid"),
    ("MAGE", "RANGED", "mage/dps", "Frost", "gear_sets/preraidFrost.gear.json", None, "preraid"),
    ("ROGUE", "MELEE", "rogue/dps", "Combat, swords", "gear_sets/sinister.gear.json", "Combat SS", "preraid"),
    ("ROGUE", "MELEE", "rogue/dps", "Combat, daggers", "gear_sets/backstab.gear.json", "Combat BS", "preraid"),
    ("ROGUE", "MELEE", "rogue/dps", "Mutilate", "gear_sets/muti.gear.json", "Asn Muti", "preraid"),
    ("ROGUE", "MELEE", "rogue/dps", "Subtlety", "gear_sets/hemo.gear.json", "Subtlety Hemo", "preraid"),
    ("SHAMAN", "RANGED", "shaman/elemental", "Elemental", "defaults.siml", "Default", "preraid"),
    ("SHAMAN", "RANGED", "shaman/elemental", "Elemental, budget", "gear_sets/budget.gear.siml", "Default", "preraid"),
    ("SHAMAN", "MELEE", "shaman/enhancement", "Enhancement", "builds/default.build.json", "Default", "preraid"),
    ("WARLOCK", "RANGED", "warlock/dps", "Destruction", "gear_sets/destro.gear.json", None, "preraid"),
    ("WARLOCK", "RANGED", "warlock/dps", "Affliction", "gear_sets/aff_wrack.gear.json", None, "preraid"),
    ("WARLOCK", "RANGED", "warlock/dps", "SM/Ruin", "gear_sets/sm_ruin.gear.json", None, "preraid"),
    ("WARLOCK", "RANGED", "warlock/dps", "Demo, fire", "gear_sets/demo_fire_brand.gear.json", None, "preraid"),
    ("WARLOCK", "RANGED", "warlock/dps", "Demo, shadow", "gear_sets/demo_shadow_brand.gear.json", None, "preraid"),
    ("WARRIOR", "MELEE", "warrior/dps", "Fury", "gear_sets/prebis_fury.gear.json", "Fury", "preraid"),
    ("WARRIOR", "MELEE", "warrior/dps", "Fury, two-hand", "gear_sets/prebis_fury_2h.gear.json", "Fury 2H", "preraid"),
    ("WARRIOR", "MELEE", "warrior/dps", "Arms", "gear_sets/prebis_arms.gear.json", "Arms", "preraid"),
    ("WARRIOR", "TANK", "warrior/protection", "Balanced", "gear_sets/prebis_balanced.gear.json", "Balanced", "preraid"),
    ("WARRIOR", "TANK", "warrior/protection", "Offensive", "gear_sets/prebis_offensive.gear.json", "Offensive", "preraid"),
]

# The armour each class wears at 60; alternates only come from it.
ARMOR = {"WARRIOR": 4, "PALADIN": 4, "HUNTER": 3, "SHAMAN": 3, "ROGUE": 2, "DRUID": 2,
         "PRIEST": 1, "MAGE": 1, "WARLOCK": 1}
CLASS_ID = {"WARRIOR": 1, "PALADIN": 2, "HUNTER": 3, "ROGUE": 4, "PRIEST": 5, "SHAMAN": 7,
            "MAGE": 8, "WARLOCK": 9, "DRUID": 11}
# Builds whose weights value spell power rank their weapon slots too; for a
# physical build a weapon's damage isn't in the weights, so its weapons get
# no alternates.
SPELL_STATS = {4, 5, 6, 7, 8, 9, 10, 11}
ALTERNATES = 2
# Raids: their drops are never pre-raid alternates.
RAID_ZONES = {2717, 2159, 2677, 1977, 3429, 3428, 3456, 19}
PROFESSIONS = {1: "Alchemy", 2: "Blacksmithing", 3: "Enchanting", 4: "Engineering", 5: "Herbalism",
               6: "Mining", 7: "Skinning", 8: "Leatherworking", 9: "Tailoring", 10: "Fishing",
               11: "Tailoring", 12: "Cooking", 13: "First Aid", 14: "Jewelcrafting"}


def load(root):
    with open(os.path.join(root, "assets/database/db.json")) as f:
        db = json.load(f)
    with open(os.path.join(root, "sim/siml/names.json")) as f:
        names = json.load(f)["items"]
    return db, names


def read_gear(root, folder, source, names):
    """The set as 17 entries of (item id, suffix words or None)."""
    path = os.path.join(root, "ui/specs", folder, source)
    if path.endswith(".json"):
        with open(path) as f:
            data = json.load(f)
        items = data["player"]["equipment"]["items"] if "player" in data else data["items"]
        out = []
        for entry in items[:17]:
            out.append((entry.get("id"), None) if entry else (None, None))
        while len(out) < 17:
            out.append((None, None))
        return out
    out = {}
    with open(path) as f:
        text = f.read()
    if source.endswith("defaults.siml"):
        block = re.search(r"^gear:\n((?:[ \t]+.*\n)+)", text, re.M)
        text = block.group(1) if block else ""
    for line in text.splitlines():
        parts = line.split()
        if len(parts) < 2 or parts[0] not in SIML:
            continue
        name = parts[1]
        suffix = None
        if len(parts) > 2 and parts[2].startswith("of_"):
            suffix = re.sub(r"_\d+$", "", parts[2]).replace("_", " ")
            suffix = suffix[0:3] + suffix[3:].title()
        if name not in names:
            sys.exit(f"unknown item name {name!r} in {folder}/{source}")
        out[parts[0]] = (names[name], suffix)
    return [out.get(word, (None, None)) for word in SIML]


def _varint(data, i):
    value = shift = 0
    while True:
        byte = data[i]
        i += 1
        value |= (byte & 0x7F) << shift
        shift += 7
        if byte < 0x80:
            return value, i


def _fields(data):
    i, out = 0, []
    while i < len(data):
        key, i = _varint(data, i)
        field, wire = key >> 3, key & 7
        if wire == 0:
            value, i = _varint(data, i)
        elif wire == 2:
            size, i = _varint(data, i)
            value, i = data[i:i + size], i + size
        elif wire == 5:
            value, i = data[i:i + 4], i + 4
        elif wire == 1:
            value, i = data[i:i + 8], i + 8
        else:
            raise ValueError(f"wire type {wire}")
        out.append((field, wire, value))
    return out


def read_link(link):
    """The gear of a WoWSims share link (…/?i=g#<base64 zlib proto>)."""
    blob = link.split("#", 1)[1]
    raw = zlib.decompress(base64.b64decode(blob + "=" * (-len(blob) % 4)))
    player = next(v for f, w, v in _fields(raw) if f == 3 and w == 2)
    equipment = next(v for f, w, v in _fields(player) if f == 3 and w == 2)
    out = []
    for f, w, v in _fields(equipment):
        if f == 1 and w == 2:
            item = {ff: vv for ff, ww, vv in _fields(v) if ww == 0}
            out.append((item.get(1), None))
    while len(out) < 17:
        out.append((None, None))
    return out[:17]


def resolver(items, cls):
    """Finds an item by its name as players write it: the exact name, the
    one your class may use when several share it, or a random-suffix item
    ("Master's Boots of Shadow Wrath" is Master's Boots with that suffix)."""
    by_name = {}
    for item in items.values():
        by_name.setdefault(item["name"].lower(), []).append(item)

    def pick(found):
        found = sorted(found, key=lambda i: (bool(i.get("classAllowlist")) and CLASS_ID[cls] not in i["classAllowlist"], -i.get("quality", 0), i["id"]))
        return found[0]["id"]

    def find(name):
        if isinstance(name, int):
            return name, None
        name = re.sub(r"\s*\+[\d-]+$", "", name.strip())
        found = by_name.get(name.lower())
        if found:
            return pick(found), None
        m = re.match(r"^(.*?) (of (?:the )?[A-Z][\w' ]+)$", name)
        if m and by_name.get(m.group(1).lower()):
            return pick(by_name[m.group(1).lower()]), m.group(2)
        sys.exit(f"no item named {name!r}")
    return find


# A named list's slots, as WoWSims slot words.
SLOT_KEYS = [k for k, _ in SLOTS]
TYPE_SLOTS = {1: [0], 2: [1], 3: [2], 4: [3], 5: [4], 6: [5], 7: [6], 8: [7], 9: [8], 10: [9],
              11: [10, 11], 12: [12, 13], 14: [16]}


def read_named(extra, items, cls):
    """A list written by players: "slots" maps STOA slot keys to a list of
    names or ids (the pick first, then alternates), or "items" is a plain
    list placed by each item's own slot."""
    find = resolver(items, cls)
    gear = [(None, None)] * 17
    alts = [[] for _ in range(17)]
    for key, names in (extra.get("slots") or {}).items():
        at = SLOT_KEYS.index(key)
        found = [find(n) for n in names]
        gear[at] = found[0]
        alts[at] = [f[0] for f in found[1:]]
    for name in extra.get("items") or []:
        item_id, suffix = find(name)
        kind = items[item_id].get("type")
        if kind == 13:
            hand = items[item_id].get("handType")
            spots = [15] if hand == 3 else [14, 15]
        else:
            spots = TYPE_SLOTS.get(kind, [])
        for at in spots:
            if gear[at][0] is None:
                gear[at] = (item_id, suffix)
                break
    return gear, alts


def read_weights(root, folder):
    """Every makePresetEpWeights in the spec's presets.ts, by its name."""
    with open(os.path.join(root, "ui/specs", folder, "presets.ts")) as f:
        text = f.read()
    stat_ids = {}
    with open(os.path.join(root, "proto/common.proto")) as f:
        for m in re.finditer(r"^\s*(Stat\w+)\s*=\s*(\d+);", f.read(), re.M):
            stat_ids.setdefault(m.group(1), int(m.group(2)))
    out = {}
    for m in re.finditer(r"makePresetEpWeights\(\s*'([^']+)'\s*,\s*Stats\.fromMap\(\s*\{(.*?)\}", text, re.S):
        weights = {}
        for s in re.finditer(r"\[Stat\.(Stat\w+)\]\s*:\s*(-?[\d.]+)", m.group(2)):
            weights[stat_ids[s.group(1)]] = float(s.group(2))
        out[m.group(1)] = weights
    return out


def item_stats(item):
    option = item.get("scalingOptions", {}).get("0", {})
    return {int(k): v for k, v in option.get("stats", {}).items()}


def score(item, weights):
    return sum(weights.get(k, 0) * v for k, v in item_stats(item).items())


def is_raid(item):
    return any("drop" in s and s["drop"].get("zoneId") in RAID_ZONES for s in item.get("sources", []))


def usable(item, cls):
    allow = item.get("classAllowlist")
    if allow and CLASS_ID[cls] not in allow:
        return False
    return True


def alternates(items, cls, slot, picked, weights, taken):
    """The next items for a slot by the build's weights, best first."""
    best = picked and items.get(picked[0])
    if not best or not weights:
        return []
    kind = ITEM_TYPE[slot]
    if kind in (13, 14) and not (SPELL_STATS & {k for k, v in weights.items() if v > 0}):
        return []
    # Gear WoWSims values above nothing: an item the weights can't value
    # (its worth is an effect) isn't ranked.
    floor = score(best, weights) * 0.6
    pool = []
    for item in items.values():
        if item.get("type") != kind or item["id"] in taken or item.get("randomSuffixOptions"):
            continue
        if item.get("quality", 0) < 2 or item.get("phase", 1) > 1 or is_raid(item):
            continue
        if not usable(item, cls) or not item.get("sources"):
            continue
        if any("pvp" in s for s in item["sources"]):
            continue
        if kind <= 10 and kind not in (2, 4) and item.get("armorType") != ARMOR[cls]:
            continue
        if kind == 13 and (item.get("handType") != best.get("handType") or item.get("weaponType") != best.get("weaponType")):
            continue
        if kind == 14 and item.get("rangedWeaponType") != best.get("rangedWeaponType"):
            continue
        value = score(item, weights)
        if value <= floor or item.get("itemEffects"):
            continue
        pool.append((-value, item["name"], item["id"]))
    pool.sort()
    return [entry[2] for entry in pool[:ALTERNATES]]


def describe(item, zones, npcs):
    """Where an item comes from, as short records STOA shows."""
    out = []
    for s in item.get("sources", []):
        if "drop" in s:
            d = s["drop"]
            out.append(("drop", zones.get(d.get("zoneId"), ""), npcs.get(d.get("npcId"), ""), 0))
        elif "soldBy" in s:
            v = s["soldBy"]
            out.append(("vendor", zones.get(v.get("zoneId"), ""), v.get("npcName", ""), v.get("faction", 0)))
        elif "quest" in s:
            q = s["quest"]
            out.append(("quest", zones.get(q.get("zoneId"), ""), q.get("name", ""), q.get("faction", 0)))
        elif "crafted" in s:
            out.append(("crafted", PROFESSIONS.get(s["crafted"].get("profession"), "Crafted"), "", 0))
        elif "rep" in s:
            r = s["rep"]
            out.append(("rep", r.get("_faction", ""), "", r.get("factionId", 0)))
        elif "pvp" in s:
            out.append(("pvp", "", "", 0))
    # One record per kind and faction: the first (the game lists the
    # likeliest first), so a vendor sold in both capitals keeps one each.
    seen, kept = set(), []
    for rec in out:
        key = (rec[0], rec[3])
        if key not in seen:
            seen.add(key)
            kept.append(rec)
    return kept or [("world", "", "", 0)]


def lua_str(value):
    return '"' + str(value).replace("\\", "\\\\").replace('"', '\\"') + '"'


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("wowsims")
    parser.add_argument("--out", default=os.path.join(os.path.dirname(__file__), "../../Data/BiS.lua"))
    parser.add_argument("--lists", help="a JSON file of lists other people made (kept out of the repo)")
    parser.add_argument("--strings", help="where to write those lists as import strings")
    args = parser.parse_args()
    root = args.wowsims
    db, names = load(root)
    items = {i["id"]: i for i in db["items"]}
    zones = {z["id"]: z["name"] for z in db["zones"]}
    npcs = {n["id"]: n["name"] for n in db["npcs"]}
    factions = {f["id"]: f["name"] for f in db.get("factions", [])}
    for item in items.values():
        for s in item.get("sources", []):
            if "rep" in s:
                s["rep"]["_faction"] = factions.get(s["rep"].get("repFactionId"), "Reputation")
    try:
        stamp = subprocess.check_output(["git", "-C", root, "log", "-1", "--format=%cs %h"], text=True).split()
    except Exception:
        stamp = ["unknown", "unknown"]

    # Lists other people made (WoWSims links, guide tables, guild sheets):
    # by default they become import strings for your own copy (--strings),
    # and only an entry marked "ship": true joins the builds STOA ships.
    order = list(BUILDS)
    personal = []
    if args.lists:
        with open(args.lists) as f:
            for extra in json.load(f):
                if extra.get("link"):
                    source = "link:" + extra["link"]
                else:
                    source = "named:" + json.dumps(extra)
                row = (extra["class"], extra["role"], extra.get("folder", ""), extra["name"], source,
                       extra.get("weights"), extra.get("phase", "preraid"))
                if not extra.get("ship"):
                    personal.append((row, extra.get("credit", "")))
                    continue
                at = next((i for i, b in enumerate(order) if b[0] == row[0] and b[1] == row[1]), len(order) - 1)
                while at + 1 < len(order) and order[at + 1][:2] == row[:2] and order[at + 1][4].startswith(("link:", "named:")):
                    at += 1
                order.insert(at + 1, row)

    used = set()
    builds = []
    def gear_of(cls, folder, source):
        given = None
        if source.startswith("link:"):
            gear = read_link(source[5:])
        elif source.startswith("named:"):
            gear, given = read_named(json.loads(source[6:]), items, cls)
        else:
            gear = read_gear(root, folder, source, names)
        return gear, given

    strings = []
    for (cls, role, folder, name, source, _, phase), credit in personal:
        gear, given = gear_of(cls, folder, source)
        fields = []
        for index, (item_id, suffix) in enumerate(gear):
            if not item_id or item_id not in items:
                fields.append("")
                continue
            alts = list(given[index]) if given else []
            used.add(item_id)
            used.update(a for a in alts if a in items)
            fields.append("+".join(str(i) for i in [item_id] + alts) + (("~" + suffix) if suffix else ""))
        clean = lambda t: str(t).replace("|", "/")
        strings.append((name, "STOA-BIS1|" + "|".join([cls, role, clean(name), clean(credit)]) + "|" + ";".join(fields)))

    for cls, role, folder, name, source, weight_name, phase in order:
        given = None
        if source.startswith("link:"):
            gear = read_link(source[5:])
        elif source.startswith("named:"):
            gear, given = read_named(json.loads(source[6:]), items, cls)
        else:
            gear = read_gear(root, folder, source, names)
        weights = read_weights(root, folder).get(weight_name) if weight_name and folder else None
        taken = {g[0] for g in gear if g[0]}
        slots = []
        for index, (item_id, suffix) in enumerate(gear):
            if not item_id or item_id not in items:
                slots.append(None)
                continue
            alts = given[index] if given else alternates(items, cls, index, (item_id, suffix), weights, taken)
            # Rings and trinkets share one pool: the second slot's
            # alternates repeat the first's.
            if index in (11, 13):
                alts = slots[index - 1]["alt"] if slots[index - 1] else alts
            used.add(item_id)
            used.update(alts)
            slots.append({"id": item_id, "sfx": suffix, "alt": alts})
        builds.append({"class": cls, "role": role, "name": name, "phase": phase, "slots": slots})

    lines = [
        "-- Generated by Tools/bis/build.py from WoWSims Forever (github.com/wowsims/forever,",
        "-- MIT licence, copyright the wowsims team). Do not edit by hand: run the script.",
        "local _, ns = ...",
        "local Stoa = ns.Stoa",
        "",
        "Stoa.BiSData = {",
        f"\tdate = {lua_str(stamp[0])},",
        f"\tcommit = {lua_str(stamp[1])},",
        "\tslots = { " + ", ".join(f"{{ {lua_str(k)}, {v} }}" for k, v in SLOTS) + " },",
        "\tbuilds = {",
    ]
    for b in builds:
        lines.append(f"\t\t{{ class = {lua_str(b['class'])}, role = {lua_str(b['role'])}, name = {lua_str(b['name'])}, phase = {lua_str(b['phase'])}, slots = {{")
        for slot in b["slots"]:
            if not slot:
                lines.append("\t\t\tfalse,")
                continue
            parts = [str(slot["id"])]
            parts.append(lua_str(slot["sfx"]) if slot["sfx"] else "nil")
            parts.append("{ " + ", ".join(str(a) for a in slot["alt"]) + " }" if slot["alt"] else "nil")
            lines.append("\t\t\t{ " + ", ".join(parts) + " },")
        lines.append("\t\t} },")
    lines.append("\t},")
    lines.append("\t-- Item id = { name, quality, { kind, place, who, faction }, ... }.")
    lines.append("\titems = {")
    for item_id in sorted(used):
        item = items[item_id]
        recs = ", ".join("{ " + ", ".join([lua_str(r[0]), lua_str(r[1]), lua_str(r[2]), str(r[3])]) + " }"
                         for r in describe(item, zones, npcs))
        lines.append(f"\t\t[{item_id}] = {{ {lua_str(item['name'])}, {item.get('quality', 1)}, {recs} }},")
    lines.append("\t},")
    lines.append("}")
    out = os.path.normpath(args.out)
    with open(out, "w") as f:
        f.write("\n".join(lines) + "\n")
    if args.strings:
        with open(args.strings, "w") as f:
            for name, line in strings:
                f.write(f"{name}\n{line}\n\n")
    print(f"{out}: {len(builds)} builds, {len(strings)} import strings, {len(used)} items, WoWSims {stamp[0]} {stamp[1]}")


if __name__ == "__main__":
    main()
