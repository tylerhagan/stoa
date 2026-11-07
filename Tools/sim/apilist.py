"""Build Tools/sim/api.txt, the list of names the WoW Forever client really has.

The list comes from Blizzard's own UI source for Forever (branch `forever` of
https://github.com/Gethe/wow-ui-source). The whole tree is only a few MB, so
this shallow-clones it into Tools/sim/.cache/ (over HTTPS; the raw and API
endpoints are not needed) and reads three things from it:

  * Blizzard_APIDocumentationGenerated/*.lua: every `Namespace = "C_Foo"` file
    gives C_Foo.Bar for each function; files without a namespace give global
    functions; files with `Type = "ScriptObject"` give widget methods.
  * every .lua file: `function Name(`, `function C_Foo.Bar(`, and top-level
    `Name = ...` globals; `function XMixin:Method(` gives extra widget methods
    (templates such as BackdropTemplate add methods in Lua).
  * engine functions: capitalised names Blizzard's Lua calls in three or more
    files that nothing in the tree defines or documents (CreateFrame,
    IsInGroup, ...). These are the C-side API.
  * every .xml file: named frames, fonts, textures (`name="Foo"`), and
    `CreateFrame("Frame", "Foo"` in Lua.

Output sections (comment lines start with #): global functions, C_ namespaces
and C_Foo.Bar functions, other globals (named frames, tables, constants), and
widget methods. Run:  python3 Tools/sim/apilist.py [--refresh]

With --src DIR it reads a folder the game client exported itself instead
(launch Wow.exe with -console, then at the login screen type
`exportInterfaceFiles code` in the ` console; DIR is the BlizzardInterfaceCode
folder it writes next to Wow.exe). That is the exact build Tyler has
installed, which can be newer than the Gethe mirror.
"""
import os
import re
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
CACHE = os.path.join(HERE, ".cache")
SRC = os.path.join(CACHE, "wow-ui-source")
URL = "https://github.com/Gethe/wow-ui-source"
BRANCH = "forever"


def fetch(refresh):
    if os.path.isdir(os.path.join(SRC, ".git")) and not refresh:
        return
    if os.path.isdir(SRC):
        subprocess.check_call(["rm", "-rf", SRC])
    os.makedirs(CACHE, exist_ok=True)
    env = dict(os.environ, GIT_LFS_SKIP_SMUDGE="1")
    subprocess.check_call(["git", "clone", "--depth", "1", "--branch", BRANCH, URL, SRC], env=env)


def read(path):
    with open(path, encoding="utf-8", errors="replace") as f:
        return f.read()


# A function entry; its simple `Key = value,` lines may carry Namespace = "",
# which makes it a global even inside a C_ namespace file (legacy aliases).
FUNC = re.compile(r'\{\s*Name = "(\w+)",\s*Type = "Function",((?:\n\t\t\t\w+ = [^\n{]*,)*)')
KIND = re.compile(r'^\tType = "(\w+)"', re.M)
NAMESPACE = re.compile(r'^\s*Namespace = "(\w+)"', re.M)
ENUM = re.compile(r'\{\s*Name = "(\w+)",\s*Type = "Enumeration"')


def main():
    global SRC
    origin = "%s (branch %s)" % (URL, BRANCH)
    if "--src" in sys.argv:
        SRC = os.path.abspath(sys.argv[sys.argv.index("--src") + 1])
        origin = "a client export (%s)" % os.path.basename(SRC)
    else:
        fetch("--refresh" in sys.argv)
    funcs, ns, nsfuncs, other, methods = set(), set(), set(), set(), set()
    docs = os.path.join(SRC, "Interface/AddOns/Blizzard_APIDocumentationGenerated")
    for fn in sorted(os.listdir(docs)):
        if not fn.endswith(".lua"):
            continue
        text = read(os.path.join(docs, fn))
        kind = KIND.search(text)
        entries = FUNC.findall(text)
        if kind and kind.group(1) == "ScriptObject":
            methods.update(n for n, _ in entries)
            continue
        m = NAMESPACE.search(text)
        for n, extra in entries:
            override = re.search(r'\bNamespace = "(\w*)"', extra)
            space = override.group(1) if override else (m.group(1) if m else "")
            if space:
                ns.add(space)
                nsfuncs.add(space + "." + n)
            else:
                funcs.add(n)
        if m:
            ns.add(m.group(1))
        if ENUM.search(text):
            other.add("Enum")

    luadef = re.compile(r"^\s*function\s+([A-Za-z_]\w*)\s*\(", re.M)
    nsdef = re.compile(r"^\s*function\s+(C_\w+)\.(\w+)\s*\(", re.M)
    mixdef = re.compile(r"^\s*function\s+\w*Mixin[:.](\w+)\s*\(", re.M)
    toplevel = re.compile(r"^([A-Za-z_]\w*)\s*=", re.M)
    xmlname = re.compile(r'<\w+[^>]*?\sname="([A-Za-z_]\w*)"')
    createframe = re.compile(r'CreateFrame\(\s*"\w+"\s*,\s*"([A-Za-z_]\w*)"')
    called = re.compile(r"(?<![\w.:])([A-Z][A-Za-z0-9_]+)\s*\(")
    localdef = re.compile(r"local\s+function\s+(\w+)|local\s+(\w+)\s*=|function\s+\w+\s*\(([^)]*)\)")
    calls, scoped = {}, set()
    for root, _, files in os.walk(os.path.join(SRC, "Interface")):
        if root.startswith(docs):
            continue
        for fn in files:
            path = os.path.join(root, fn)
            if fn.endswith(".lua"):
                t = read(path)
                funcs.update(luadef.findall(t))
                for a, b in nsdef.findall(t):
                    ns.add(a)
                    nsfuncs.add(a + "." + b)
                methods.update(mixdef.findall(t))
                other.update(toplevel.findall(t))
                other.update(createframe.findall(t))
                for m in localdef.finditer(t):
                    scoped.update(x for x in re.split(r"[\s,]+", " ".join(g or "" for g in m.groups())) if x)
                for name in set(called.findall(t)):
                    calls[name] = calls.get(name, 0) + 1
            elif fn.endswith(".xml"):
                other.update(xmlname.findall(read(path)))
    other -= funcs
    other = {n for n in other if "$" not in n}
    # Engine functions: Blizzard's Lua calls them in several files but nothing
    # in the tree defines or documents them (CreateFrame, IsInGroup, ...).
    engine = {n for n, c in calls.items()
              if c >= 3 and n not in funcs and n not in other and n not in scoped and n not in ns}

    out = ["# Generated by Tools/sim/apilist.py from %s. Do not edit." % origin]
    out += ["# section: global functions"] + sorted(funcs)
    out += ["# section: C_ namespaces and functions"] + sorted(ns) + sorted(nsfuncs)
    out += ["# section: engine functions called by Blizzard Lua but not documented"] + sorted(engine)
    out += ["# section: named frames and other globals"] + sorted(other)
    out += ["# section: widget methods"] + sorted(methods)
    with open(os.path.join(HERE, "api.txt"), "w") as f:
        f.write("\n".join(out) + "\n")
    print("funcs %d, namespaces %d, ns functions %d, other globals %d, widget methods %d"
          % (len(funcs), len(ns), len(nsfuncs), len(other), len(methods)))


main()
