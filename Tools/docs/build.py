#!/usr/bin/env python3
"""Builds STOA's docs site into docs/ from README.md, CHANGELOG.md and Stoa.toc.

    python3 Tools/docs/build.py           write the pages
    python3 Tools/docs/build.py --check   fail if the pages are out of date

The README stays the source of truth: change a Status or Commands row there and
rebuild. Only the grouping of Status rows into sections lives here (GROUPS).
"""
import html
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT = os.path.join(ROOT, "docs")
HERE = os.path.dirname(os.path.abspath(__file__))

REPO = "https://github.com/tylerhagan/stoa"
CURSEFORGE = "https://www.curseforge.com/wow/addons/stoa"

# Status rows (by Area) for the Classes page, in the order they appear there.
CLASSES = [
    ("Warrior", "C69B6D", ["Warrior"]),
    ("Paladin", "F48CBA", ["Paladin"]),
    ("Hunter", "AAD372", ["Hunter"]),
    ("Rogue", "FFF468", ["Rogue"]),
    ("Priest", "FFFFFF", ["Shadow", "Discipline"]),
    ("Shaman", "0070DD", ["Shaman"]),
    ("Mage", "3FC7EB", ["Mage"]),
    ("Warlock", "8788EE", ["Warlock"]),
    ("Druid", "FF7C0A", ["Druid"]),
]

# Status rows (by Area) for the Features page, grouped.
GROUPS = [
    ("The two states", "The console out of combat, the Halo in it, and what rides on them.", [
        "State", "Console", "Halo", "Roles", "Per spec", "Combat bar", "Coin art", "Procs", "Game auras",
        "Reminders", "Mana play", "Swing timer", "Threat meter", "Timers", "Cooldown Manager"]),
    ("Groups", "Party and raid frames, healing and the people you play with.", [
        "Party cards", "Raid frames", "Click-casting", "Tank watch", "Target", "Pet", "Group buffs",
        "Dungeon kit", "Social", "Auto-invite", "Company"]),
    ("Around the screen", "Everything else the game draws, in STOA's dress.", [
        "Action bars", "At a glance", "Minimap", "Icon tray", "Top of screen", "Nameplates", "Chat", "Map",
        "Damage meters"]),
    ("Windows", "Blizzard's windows, kept and dressed.", [
        "Blizzard windows", "Windows", "Window stone", "More windows", "Moving windows", "Bags",
        "Character sheet", "Tooltips", "Trainer", "Mail", "Merchants"]),
    ("Levelling and gear", "Small helps on the road to sixty.", [
        "Quest reward", "Quest items", "Gear scores", "Gear for each spec", "Auto-uprank", "Restock",
        "Junk list", "Loot feed", "Gathering", "Emergency item", "Characters"]),
    ("Comfort and setup", "Settings, presets and the little things.", [
        "Welcome", "Presets", "Settings", "Saved setups", "Backup", "Movers", "Snapping", "Comforts",
        "Keybinding", "Away screen", "Tokens", "Colour vision"]),
    ("Safety and other addons", "How STOA keeps out of trouble and plays with others.", [
        "Launch check", "Error guard", "Other addons", "Leatrix Plus", "STOA's look for other addons",
        "OneForAll", "DoesItDie", "Pawn", "For other addons", "Shared core", "Core"]),
]

PAGES = [
    ("index.html", "Overview"),
    ("features.html", "Features"),
    ("classes.html", "Classes"),
    ("commands.html", "Commands"),
    ("install.html", "Install"),
    ("changelog.html", "Changelog"),
]

SHOTS = {
    "world": "In the world: the console along the bottom, with At a glance, Ready, Journey and Company.",
    "combat": "In combat: the console folds away and the Halo rises around your character.",
    "console": "The console up close.",
    "party-healer": "Healing a group: party cards under the combat bar and a watch card for the tank.",
    "tooltip-compare": "Tooltips: a calm card with an upgrade line against what you wear.",
    "training": "Training: what you can learn now and what comes next, with prices.",
    "settings": "Settings: every option on one searchable page, with a note on what each does.",
    "mail": "The mailbox, with Take gold and Open All.",
}


# Reading the sources --------------------------------------------------------------

def read(path):
    with open(os.path.join(ROOT, path), encoding="utf-8") as f:
        return f.read()


def sections(markdown):
    """Splits markdown into {heading: body} on '## ' headings."""
    out, name, lines = {}, None, []
    for line in markdown.splitlines():
        if line.startswith("## "):
            if name:
                out[name] = "\n".join(lines).strip()
            name, lines = line[3:].strip(), []
        elif name:
            lines.append(line)
    if name:
        out[name] = "\n".join(lines).strip()
    return out


def table(body):
    rows = []
    for line in body.splitlines():
        if not line.startswith("| ") or line.startswith("| ---"):
            continue
        cells = [c.strip().replace("\\|", "|") for c in re.split(r"(?<!\\)\|", line.strip())[1:-1]]
        rows.append(cells)
    return rows[1:]  # without the header row


def version():
    match = re.search(r"^## Version:\s*(\S+)", read("Stoa.toc"), re.M)
    return match.group(1) if match else "?"


def interface():
    match = re.search(r"^## Interface:\s*(\S+)", read("Stoa.toc"), re.M)
    return match.group(1) if match else "?"


# A small markdown subset: code, bold, links, lists, paragraphs ---------------------------

def inline(text):
    parts = re.split(r"(`[^`]+`)", text)
    out = []
    for part in parts:
        if part.startswith("`") and part.endswith("`") and len(part) > 1:
            out.append("<code>" + html.escape(part[1:-1]) + "</code>")
            continue
        part = html.escape(part, quote=False)
        part = re.sub(r"\*\*(.+?)\*\*", r"<strong>\1</strong>", part)
        part = re.sub(r"\[([^\]]+)\]\(([^)]+)\)", lambda m: '<a href="%s">%s</a>' % (link(m.group(2)), m.group(1)), part)
        out.append(part)
    return "".join(out)


def link(url):
    if url.startswith("http") or url.startswith("#"):
        return url
    return REPO + "/blob/main/" + url


def blocks(text):
    out, para, items = [], [], []

    def flush():
        if para:
            out.append("<p>" + inline(" ".join(para)) + "</p>")
            para.clear()
        if items:
            out.append("<ul>" + "".join("<li>" + inline(i) + "</li>" for i in items) + "</ul>")
            items.clear()

    for line in text.splitlines():
        s = line.strip()
        if not s or s.startswith("<") or s.startswith("!["):
            flush()
            continue
        m = re.match(r"^(?:[-*]|\d+\.)\s+(.*)", s)
        if m:
            if para:
                flush()
            items.append(m.group(1))
        elif items and line.startswith("  "):
            items[-1] += " " + s
        else:
            if items:
                flush()
            para.append(s)
    flush()
    return "\n".join(out)


def slug(text):
    return re.sub(r"[^a-z0-9]+", "-", text.lower()).strip("-")


# Page frame -------------------------------------------------------------------------

def css():
    with open(os.path.join(HERE, "site.css"), encoding="utf-8") as f:
        return f.read()


def page(file, title, description, body, ver):
    nav = "".join(
        '<a href="%s"%s>%s</a>' % (f, ' aria-current="page"' if f == file else "", name)
        for f, name in PAGES)
    full_title = "STOA" if file == "index.html" else "%s · STOA" % title
    return """<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
<title>{full_title}</title>
<meta name="description" content="{description}">
<meta property="og:title" content="{full_title}">
<meta property="og:description" content="{description}">
<meta property="og:image" content="screenshots/world.jpg">
<meta name="theme-color" content="#0d0d0f">
<link rel="icon" href="logo/stoa-essence-symbol.svg" type="image/svg+xml">
<link rel="preconnect" href="https://fonts.googleapis.com">
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Tenor+Sans&family=Inter:wght@400;500;600&display=swap">
<link rel="stylesheet" href="assets/site.css">
</head>
<body>
<a class="skip" href="#main">Skip to content</a>
<header class="top">
  <div class="bar">
    <a class="mark" href="index.html" aria-label="STOA home"><img src="logo/stoa-essence.svg" alt="STOA" width="116" height="35"></a>
    <nav class="pages" aria-label="Pages">{nav}</nav>
    <a class="get" href="{curseforge}">Download</a>
  </div>
</header>
<main id="main">
{body}
</main>
<footer class="foot">
  <div class="bar">
    <p>STOA {ver} for WoW Forever (interface {iface}). Made by Tyler.</p>
    <p><a href="{repo}">GitHub</a> · <a href="{curseforge}">CurseForge</a> · <a href="{repo}/issues/new/choose">Report a bug</a></p>
  </div>
</footer>
<script>{script}</script>
</body>
</html>
""".format(full_title=full_title, description=html.escape(description), nav=nav, body=body, ver=ver,
           iface=interface(), repo=REPO, curseforge=CURSEFORGE, script=SCRIPT)


SCRIPT = """
document.querySelectorAll('[data-filter]').forEach(function (input) {
  var scope = document.getElementById(input.getAttribute('data-filter'));
  var none = scope.querySelector('.none');
  input.addEventListener('input', function () {
    var q = input.value.trim().toLowerCase(), shown = 0;
    scope.querySelectorAll('[data-text]').forEach(function (row) {
      var hit = !q || row.getAttribute('data-text').indexOf(q) !== -1;
      row.hidden = !hit; if (hit) shown++;
    });
    scope.querySelectorAll('[data-group]').forEach(function (g) {
      g.hidden = !g.querySelector('[data-text]:not([hidden])');
    });
    if (none) none.hidden = shown !== 0;
  });
});
"""


def shot(name, cls="", eager=False):
    from_path = os.path.join(OUT, "screenshots", name + ".jpg")
    size = ""
    try:
        from PIL import Image
        w, h = Image.open(from_path).size
        size = ' width="%d" height="%d"' % (w, h)
    except Exception:
        pass
    alt = html.escape(SHOTS.get(name, name))
    return '<figure class="shot %s"><img src="screenshots/%s.jpg" alt="%s"%s%s><figcaption>%s</figcaption></figure>' % (
        cls, name, alt, size, "" if eager else ' loading="lazy"', inline(SHOTS.get(name, "")))


# Pages ------------------------------------------------------------------------------

def home(readme, ver):
    intro = readme.split("## ")[0]
    states = re.findall(r"^- \*\*(.+?):\*\* (.*)$", intro, re.M)
    roles = [l for l in intro.splitlines() if l.startswith("Layouts are built")]
    nots = sections(readme).get("What STOA is not", "")
    nots_lead, _, nots_list = nots.partition("\n\n")
    not_items = re.findall(r"^- \*\*(.+?)\*\* (.*)$", nots_list, re.M)
    cards = "".join(
        '<article class="state"><h3>%s</h3><p>%s</p></article>' % (html.escape(n), inline(t[:1].upper() + t[1:])) for n, t in states)
    nots_html = "".join('<li><strong>%s</strong> %s</li>' % (html.escape(n), inline(t)) for n, t in not_items)
    gallery = "".join(shot(n) for n in ["tooltip-compare", "training", "settings", "mail"])
    return """
<section class="hero">
  <div class="bar">
    <p class="eyebrow">A UI suite for WoW Forever</p>
    <h1>Calm out of combat.<br>Clear inside it.</h1>
    <p class="lede">STOA gives your screen two states. Out of combat a leather console along the bottom holds chat, your group, the minimap and notes. When a fight starts it folds away and the Halo rises around your character.</p>
    <p class="actions"><a class="btn primary" href="{cf}">Get it on CurseForge</a><a class="btn" href="{repo}/releases/latest">GitHub release {ver}</a></p>
    <p class="fit">Best on an ultrawide (21:9). Fits 16:9 and 16:10 too.</p>
  </div>
  {world}
</section>
<section class="bar block">
  <h2>Two states</h2>
  <div class="states">{cards}</div>
  <p class="note">{roles}</p>
  {combat}
</section>
<section class="bar block">
  <h2>Up close</h2>
  {console}
  {party}
  <div class="gallery">{gallery}</div>
  <p class="more"><a href="features.html">Every feature</a> · <a href="classes.html">What each class gets</a></p>
</section>
<section class="bar block">
  <h2>What STOA is not</h2>
  <p class="lead">{nots_lead}</p>
  <ul class="nots">{nots}</ul>
</section>
<section class="bar block cta">
  <h2>Try it</h2>
  <p>Install from the CurseForge app, or unpack the release zip into <code>_forever_\\Interface\\AddOns</code>. Restart the game the first time. <a href="install.html">Install notes</a></p>
</section>
""".format(cf=CURSEFORGE, repo=REPO, ver=ver, world=shot("world", "wide", eager=True), cards=cards,
           roles=inline(roles[0]) if roles else "", combat=shot("combat", "wide"), console=shot("console", "wide"),
           party=shot("party-healer", "wide"), gallery=gallery, nots_lead=inline(nots_lead.strip()), nots=nots_html)


def features(status):
    rows = {r[0]: r[1] for r in status}
    used = set()
    class_areas = {a for _, _, areas in CLASSES for a in areas}
    out = []
    toc = []
    for title, lead, areas in GROUPS:
        items = []
        for area in areas:
            if area not in rows:
                print("note: Status has no row '%s' (GROUPS in Tools/docs/build.py)" % area, file=sys.stderr)
                continue
            used.add(area)
            items.append(row(area, rows[area]))
        toc.append('<a href="#%s">%s</a>' % (slug(title), title))
        out.append('<section class="group" id="%s" data-group><h2>%s</h2><p class="lead">%s</p><dl class="rows">%s</dl></section>' % (
            slug(title), title, lead, "".join(items)))
    left = [a for a in rows if a not in used and a not in class_areas]
    if left:
        print("note: Status rows not in GROUPS, shown under More: %s" % ", ".join(left), file=sys.stderr)
        toc.append('<a href="#more">More</a>')
        out.append('<section class="group" id="more" data-group><h2>More</h2><dl class="rows">%s</dl></section>' % "".join(
            row(a, rows[a]) for a in left))
    return """
<section class="bar head">
  <h1>Features</h1>
  <p class="lede">Everything STOA does today, from the README's status table. Class signatures have <a href="classes.html">their own page</a>.</p>
  <div class="tools"><input type="search" placeholder="Search features" aria-label="Search features" data-filter="list"><nav class="jump" aria-label="Sections">{toc}</nav></div>
</section>
<div class="bar" id="list">{groups}<p class="none" hidden>Nothing matches. Try a shorter word.</p></div>
""".format(toc="".join(toc), groups="".join(out))


def row(area, text):
    return '<div class="row" id="%s" data-text="%s"><dt>%s</dt><dd>%s</dd></div>' % (
        slug(area), html.escape((area + " " + text).lower()), html.escape(area), inline(sentence(text)))


LABEL = re.compile(r"(?:^|(?<=\. ))(?:For )?([A-Z][A-Za-z ,'-]{1,30}?):\s")


def sentence(text):
    text = text.strip()
    if not text:
        return ""
    text = text[0].upper() + text[1:]
    return text if text.endswith((".", ")")) else text + "."


def signature(area, text, several):
    """Splits a class row into its intro and labelled parts (Protection:, Next press: ...)."""
    parts = LABEL.split(text)
    intro, pairs = parts[0], list(zip(parts[1::2], parts[2::2]))
    if several and pairs and not intro.strip():
        pairs[0] = (area, pairs[0][1])  # "For Shadow Priests:" reads as Shadow
    elif several:
        pairs.insert(0, (area, intro))
        intro = ""
    out = '<p class="intro">%s</p>' % inline(sentence(intro)) if intro.strip() else ""
    out += '<dl class="parts">' + "".join(
        '<div><dt>%s</dt><dd>%s</dd></div>' % (html.escape(label), inline(sentence(body))) for label, body in pairs) + "</dl>"
    return out


def classes(status):
    rows = {r[0]: r[1] for r in status}
    cards = []
    for name, colour, areas in CLASSES:
        body = "".join(signature(a, rows[a], len(areas) > 1) for a in areas if a in rows)
        cards.append('<section class="class" id="%s" style="--class:#%s"><h2>%s</h2><div>%s</div></section>' % (
            slug(name), colour, name, body))
    general = "".join(row(a, rows[a]) for a in ["Halo", "Procs", "Combat bar", "Coin art"] if a in rows)
    return """
<section class="bar head">
  <h1>Classes</h1>
  <p class="lede">Every class gets a signature: a few coins on the Halo, an outline on your next press and a word when something needs you. Layouts follow your role; the signature follows your spec.</p>
  <nav class="jump" aria-label="Classes">{toc}</nav>
</section>
<div class="bar classes">{cards}</div>
<section class="bar group"><h2>For every class</h2><dl class="rows">{general}</dl></section>
""".format(toc="".join('<a href="#%s">%s</a>' % (slug(n), n) for n, _, _ in CLASSES), cards="".join(cards),
           general=general)


def commands(rows):
    items = "".join(
        '<div class="row" data-text="%s"><dt><code>%s</code></dt><dd>%s</dd></div>' % (
            html.escape((c + " " + d).lower()), html.escape(c.strip("`")), inline(sentence(d))) for c, d in rows)
    return """
<section class="bar head">
  <h1>Commands</h1>
  <p class="lede">Type these in chat. Almost all of them also have a control in STOA's settings: <code>/stoa</code>.</p>
  <div class="tools"><input type="search" placeholder="Search commands" aria-label="Search commands" data-filter="cmds"></div>
</section>
<div class="bar" id="cmds"><dl class="rows cmds" data-group>{items}</dl><p class="none" hidden>No command matches.</p></div>
""".format(items=items)


def install(sec):
    parts = []
    for name in ["Install", "Reporting a bug", "Forever notes", "Fonts"]:
        if name in sec:
            parts.append('<section class="block" id="%s"><h2>%s</h2>%s</section>' % (slug(name), name, blocks(sec[name])))
    return """
<section class="bar head">
  <h1>Install</h1>
  <p class="lede">STOA is one folder named <code>Stoa</code> in your AddOns folder. Here is how to get it there, and what to know after.</p>
</section>
<div class="bar prose">{parts}</div>
""".format(parts="".join(parts))


def changelog(text):
    sec = sections(text)
    out = []
    for name, body in sec.items():
        if not re.match(r"^\[?\d", name):
            continue
        out.append('<section class="block release" id="v%s"><h2>%s</h2>%s</section>' % (slug(name), html.escape(name), blocks(body)))
    return """
<section class="bar head">
  <h1>Changelog</h1>
  <p class="lede">What changed in each release. The newest is first.</p>
</section>
<div class="bar prose">{out}</div>
""".format(out="".join(out))


# Build ------------------------------------------------------------------------------

def build():
    readme = read("README.md")
    sec = sections(readme)
    status = table(sec.get("Status", ""))
    cmds = table(sec.get("Commands", ""))
    ver = version()
    lede = "STOA: a focused, two-state UI suite for WoW Forever. The console out of combat, the Halo in it."
    files = {
        "index.html": page("index.html", "Overview", lede, home(readme, ver), ver),
        "features.html": page("features.html", "Features", "Everything STOA does, grouped.", features(status), ver),
        "classes.html": page("classes.html", "Classes", "What STOA shows for each class.", classes(status), ver),
        "commands.html": page("commands.html", "Commands", "Every /stoa command.", commands(cmds), ver),
        "install.html": page("install.html", "Install", "How to install STOA and report a bug.", install(sec), ver),
        "changelog.html": page("changelog.html", "Changelog", "What changed in each STOA release.", changelog(read("CHANGELOG.md")), ver),
        "assets/site.css": css(),
    }
    return files


def main():
    check = "--check" in sys.argv
    stale = []
    for name, content in build().items():
        path = os.path.join(OUT, name)
        old = None
        if os.path.exists(path):
            with open(path, encoding="utf-8") as f:
                old = f.read()
        if old == content:
            continue
        stale.append(name)
        if not check:
            os.makedirs(os.path.dirname(path), exist_ok=True)
            with open(path, "w", encoding="utf-8") as f:
                f.write(content)
    if check and stale:
        print("docs are out of date (run python3 Tools/docs/build.py): " + ", ".join(stale))
        sys.exit(1)
    print(("out of date: " if check else "wrote: ") + (", ".join(stale) or "nothing"))


if __name__ == "__main__":
    main()
