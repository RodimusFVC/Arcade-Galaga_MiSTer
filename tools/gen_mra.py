#!/usr/bin/env python3
"""Generate MRAs for the Galaga core straight from MAME galaga.cpp.

Region placement matches rtl/ram_rom/rom_loader.sv; images are copied as dumped.
The Namco MCU mask ROMs come from MAME's device sets (namco5x.zip).
DIP switches and the input map come from the set's MAME INPUT_PORTS.

Release layout: a parent set (MAME parent 0) goes to <releases>/<Title>.mra with the
trailing parentheses dropped; a clone goes to
<releases>/_alternatives/_<Parent Title>/<Full Title>.mra.

Usage:
    gen_mra.py <driver.cpp[,driver.cpp...]> <releases_dir> [set ...]      (no sets: every supported set)
"""
import copy
import re
import sys
from pathlib import Path

MAME_VERSION = "0289"
RBF = "Galaga"
HISCORE_DAT = Path("/CybertronMD/Mame/plugins/hiscore/hiscore.dat")   # current file (user, 2026-09-27)
# hiscore.v header after START_WAIT: CHECK_WAIT 00FF, CHECK_HOLD 2, WRITE_HOLD 2, WRITE_REPEATCOUNT 1,
# WRITE_REPEATWAIT 1111, PAUSEPAD 0, CHANGEMASK 0
HISCORE_HEADER_TAIL = "00 FF 00 02 00 02 00 01 11 11 00 00"
# START_WAIT = last boot-time write to the hiscore.dat ranges, measured in MAME (write taps, 30 s, bytes rewritten
# every frame excluded), + 2 frames. Keyed by a reference set per distinct hiscore.dat layout.
HISCORE_INIT_FRAME = {'galaga': 863, 'gatsbee': 9, 'digdug': 183, 'xevious': 722, 'xeviousb': 1416, 'bosco': 1008, 'battles2': 99}
CLK_HZ, FRAME_HZ = 49_152_000, 60.61

# region -> (base in ioctl index 0, size taken)
REGIONS = {
    "maincpu": (0x00000, 0x04000),
    "sub":     (0x08000, 0x04000),
    "sub2":    (0x0C000, 0x04000),
    "gfx1":    (0x10000, 0x02000),
    "sub3":    (0x12000, 0x01000),
    "gfx2":    (0x14000, 0x04000),
    "gfx3":    (0x18000, 0x0A000),
    "proms":   (0x22000, 0x01000),
    "namco":   (0x23000, 0x00100),                  # waveform PROM; the timing PROM at 0x100 is not used
    "gfx4":    (0x24000, 0x04000),
    "52xx":    (0x28000, 0x03000),
}

# Namco MCU mask ROMs (MAME device sets): device -> (zip, file, crc, base, size)
MCU_ROMS = {
    "50xx": ("namco50.zip", "50xx.bin", "a0acbaf7", 0x2C000, 0x800),
    "51xx": ("namco51.zip", "51xx.bin", "c2f57ef8", 0x2C800, 0x400),
    "52xx": ("namco52.zip", "52xx.bin", "3257d11e", 0x2CC00, 0x400),
    "53xx": ("namco53.zip", "53xx.bin", "b326fecb", 0x2D000, 0x400),
    "54xx": ("namco54.zip", "54xx.bin", "ee7357e0", 0x2D400, 0x400),
}
# machine config -> MCUs on the board
MCUS = {"galaga": ("51xx", "54xx"), "galagab": ("51xx",), "gatsbee": ("51xx", "54xx"),
        "digdug": ("51xx", "53xx"), "dzigzag": ("51xx", "53xx"), "xevious": ("50xx", "51xx", "54xx"),
        "bosco": ("50xx", "51xx", "52xx", "54xx")}

# machine -> {region: (ioctl index, base, size) or None to drop}
REGION_OVERRIDE = {}

IGNORED_REGIONS = {"pals", "pals_vidbd", "user1"}   # dumps MAME does not use

# (machine config, init) pairs the board implements, -> board variant byte
SUPPORTED = {
    ("galaga", "init_galaga"): 0,
    ("galagab", "init_galaga"): 1,      # Gallag / Nebulous Bee: Z80 replaces the customs, no 54xx explosions
    ("gatsbee", "init_galaga"): 2,
    ("digdug", "empty_init"): 3,
    ("dzigzag", "empty_init"): 3,
    ("xevious", "init_xevious"): 5,
    ("xevious", "init_xevios"): 6,      # Xevios, Battles set 2: bootleg ROM bit order
    ("bosco", "empty_init"): 7,
}

# init -> (index 1 byte 2 CPU ROM decode, byte 3 gfx decode)
DECODE = {}
GFX_BY_MACHINE = {}

F_4WAY, F_WIDE, F_IMPULSE, F_VERT, F_ROT90 = 0x01, 0x02, 0x04, 0x10, 0x80
WIDE_INITS = set()
WIDE_MACHINES = set()

# port order on the board: DIP bytes 0-3 and input map bytes 16-47
PORTS = [("IN0",), ("IN1",), ("DSWA",), ("DSWB",)]

# control ids (Arcade-Galaga.sv)
CTL = {("JOYSTICK_UP", 1): 1, ("JOYSTICK_DOWN", 1): 2, ("JOYSTICK_LEFT", 1): 3, ("JOYSTICK_RIGHT", 1): 4,
       ("BUTTON1", 1): 5, ("BUTTON2", 1): 6, ("BUTTON3", 1): 7, ("BUTTON4", 1): 8,
       ("JOYSTICK_UP", 2): 9, ("JOYSTICK_DOWN", 2): 10, ("JOYSTICK_LEFT", 2): 11, ("JOYSTICK_RIGHT", 2): 12,
       ("BUTTON1", 2): 13, ("BUTTON2", 2): 14, ("BUTTON3", 2): 15, ("BUTTON4", 2): 16,
       ("BUTTON5", 1): 32, ("BUTTON6", 1): 33, ("BUTTON5", 2): 34, ("BUTTON6", 2): 35,
       ("COIN1", 0): 17, ("COIN2", 0): 18, ("START1", 0): 19, ("START2", 0): 20,
       ("TILT", 0): 21, ("SERVICE1", 0): 22, ("SERVICE2", 0): 22, ("SERVICE", 0): 22, ("COIN3", 0): 23}
TRACKBALL = {"TRACKBALL_X": 24, "TRACKBALL_Y": 28}   # ids 24-27 / 28-31 = counter bits 0-3
IGNORED_TYPES = {"UNUSED", "UNKNOWN"}
WORKING_HERE = {"schick"}                           # MAME NOT_WORKING, HW-confirmed playable on this core (2026-09-29)
RACK_HOLD, RACK_TOGGLE = 36, 37                     # Rack Test cheat button (no default pad mapping)

SERIES_BY_PARENT = {"galaga": ("Galaxian", "Shooter"), "bosco": ("Bosconian", "Shooter"),
                    "xevious": ("Xevious", "Shooter"), "sxevious": ("Xevious", "Shooter"),
                    "digdug": ("Dig Dug", "Maze")}
REGION_WORDS = [("US", "US"), ("Japan", "Japan"), ("Spanish", "Spain"), ("Italian", "Italy"), ("French", "France"),
                ("Brazil", "Brazil"), ("Argentina", "Argentina"), ("Greek", "Greece"), ("Hungarian", "Hungary")]

# ---------------------------------------------------------------- parsing

GAME_RE = re.compile(r'^GAME\(\s*([\w?]+),\s*(\w+),\s*(\w+),\s*(\w+),\s*(\w+),\s*\w+,\s*(\w+),\s*(ROT\d+),\s*"([^"]*)",\s*"([^"]*)",\s*([^)]*)\)', re.M)
LOAD_RE = re.compile(r'ROM_LOAD\(\s*"([^"]+)",\s*(0x[0-9a-fA-F]+),\s*(0x[0-9a-fA-F]+),\s*(?:BAD_DUMP\s+)?CRC\(([0-9a-fA-F]+)\)')
CONT_RE = re.compile(r'ROM_CONTINUE\(\s*(0x[0-9a-fA-F]+),\s*(0x[0-9a-fA-F]+)\s*\)')
NIB_RE = re.compile(r'ROM_LOAD_NIB_(LOW|HIGH)\s*\(\s*"([^"]+)",\s*(0x[0-9a-fA-F]+),\s*(0x[0-9a-fA-F]+),\s*CRC\(([0-9a-fA-F]+)\)')
RELOAD_RE = re.compile(r'ROM_RELOAD\(\s*(0x[0-9a-fA-F]+),\s*(0x[0-9a-fA-F]+)\s*\)')
FILL_RE = re.compile(r'ROM_FILL\(\s*(0x[0-9a-fA-F]+),\s*(0x[0-9a-fA-F]+),\s*(0x[0-9a-fA-F]+)\s*\)')
COPY_RE = re.compile(r'ROM_COPY\(\s*"([^"]+)",\s*(0x[0-9a-fA-F]+),\s*(0x[0-9a-fA-F]+),\s*(0x[0-9a-fA-F]+)\s*\)')
REGION_RE = re.compile(r'ROM_REGION\(\s*(0x[0-9a-fA-F]+),\s*"([^"]+)"')
MACRO_RE = re.compile(r'\b(PORT_\w+|INPUT_PORTS_\w+)\b(\s*\(((?:[^()"]|"[^"]*"|\([^()]*\))*)\))?')


def parse_games(src):
    games = {}
    for m in GAME_RE.finditer(src):
        year, name, parent, machine, inputs, init, rot, manuf, desc, flags = m.groups()
        games[name] = dict(year=year, name=name, parent=None if parent == "0" else parent,
                           machine=machine, inputs=inputs, init=init, rot=rot, manuf=manuf, desc=desc,
                           working="MACHINE_NOT_WORKING" not in flags)
    return games


def parse_roms(src, setname):
    m = re.search(r'ROM_START\(\s*%s\s*\)(.*?)ROM_END' % re.escape(setname), src, re.S)
    if not m:
        raise SystemExit(f"ROM_START({setname}) not found")
    segs, region, rsize, last = [], None, 0, None
    for line in m.group(1).splitlines():
        line = line.split("//")[0]
        if "NO_DUMP" in line:
            continue                                   # never dumped; MAME runs without it
        if (r := REGION_RE.search(line)):
            region, rsize, last = r.group(2), int(r.group(1), 16), None
        elif (l := LOAD_RE.search(line)):
            name, off, length, crc = l.group(1), int(l.group(2), 16), int(l.group(3), 16), l.group(4).lower()
            last = dict(name=name, crc=crc, src=0, dst=off, len=length, flen=length, region=region, rsize=rsize)
            segs.append(last)
        elif (c := CONT_RE.search(line)):
            off, length = int(c.group(1), 16), int(c.group(2), 16)
            nxt = dict(last, src=last["src"] + last["len"], dst=off, len=length)
            segs.append(nxt)
            last = nxt
        elif (n := NIB_RE.search(line)):
            # ROM_LOAD_NIB_LOW / _HIGH: two 4-bit PROMs sharing one byte; each gets its own slot, merged in the core
            half, name, off, length, crc = n.group(1), n.group(2), int(n.group(3), 16), int(n.group(4), 16), n.group(5).lower()
            last = dict(name=name, crc=crc, src=0, dst=off, len=length, flen=length,
                        region=f"{region}_n{'lo' if half == 'LOW' else 'hi'}", rsize=length)
            segs.append(last)
        elif (r := RELOAD_RE.search(line)):
            # ROM_RELOAD: the previous file loaded again at another offset
            base = next(s for s in reversed(segs) if s["name"] == last["name"] and s["src"] == 0)
            last = dict(base, dst=int(r.group(1), 16), len=int(r.group(2), 16))
            segs.append(last)
        elif (f := FILL_RE.search(line)):
            off, length, val = int(f.group(1), 16), int(f.group(2), 16), int(f.group(3), 16)
            segs.append(dict(name=None, crc=None, fill=val, src=0, dst=off, len=length, region=region, rsize=rsize))
            last = None
        elif (c := COPY_RE.search(line)):
            # ROM_COPY re-reads bytes already loaded into a region: slice the file loads that cover the source range
            sreg, sofs, dofs, length = c.group(1), int(c.group(2), 16), int(c.group(3), 16), int(c.group(4), 16)
            covered = 0
            for s in [s for s in segs if s["region"] == sreg]:
                lo, hi = max(s["dst"], sofs), min(s["dst"] + s["len"], sofs + length)
                if lo < hi:
                    segs.append(dict(s, src=s["src"] + lo - s["dst"], dst=dofs + lo - sofs, len=hi - lo,
                                     region=region, rsize=rsize))
                    covered += hi - lo
            if covered != length:
                raise SystemExit(f"{setname}: ROM_COPY source not fully loaded: {line.strip()}")
            last = None
        elif "ROM_" in line and any(k in line for k in ("ROM_LOAD", "ROM_COPY", "ROM_FILL", "ROM_RELOAD")):
            raise SystemExit(f"{setname}: unhandled ROM statement: {line.strip()}")
    return segs


def def_str(s):
    s = s.strip()
    m = re.fullmatch(r'DEF_STR\(\s*(\w+)\s*\)', s)
    if not m:
        return s.strip('"')
    w = m.group(1)
    c = re.fullmatch(r'(\d+)C_(\d+)C', w)
    if c:
        return f"{c.group(1)}C/{c.group(2)}C"
    return w.replace("_", " ")


def idle_level(arg, mask):
    """Released level from an IP_ACTIVE_LOW / IP_ACTIVE_HIGH keyword or a numeric default."""
    if arg == "IP_ACTIVE_LOW":
        return mask
    if arg == "IP_ACTIVE_HIGH":
        return 0
    return int(arg, 0) & mask


def split_args(a):
    out, depth, cur, q = [], 0, "", False
    for ch in a:
        if ch == '"':
            q = not q
        if not q and ch == "(":
            depth += 1
        elif not q and ch == ")":
            depth -= 1
        if ch == "," and depth == 0 and not q:
            out.append(cur.strip())
            cur = ""
        else:
            cur += ch
    if cur.strip():
        out.append(cur.strip())
    return out


def parse_inputs(src):
    """INPUT_PORTS name -> {tag: [field]}; field = dict(mask, kind, default, type, player, name, settings, fourway)."""
    blocks = {m.group(1): m.group(2) for m in re.finditer(
        r'INPUT_PORTS_START\(\s*(\w+)\s*\)(.*?)INPUT_PORTS_END', src, re.S)}
    cache = {}

    def build(name):
        if name in cache:
            return copy.deepcopy(cache[name])
        ports, cur, fld = {}, None, None
        body = "\n".join(l.split("//")[0] for l in blocks[name].splitlines())
        for m in MACRO_RE.finditer(body):
            mac, args = m.group(1), split_args(m.group(3) or "")
            if mac == "PORT_INCLUDE":
                ports.update(build(args[0]))
            elif mac in ("PORT_START", "PORT_MODIFY"):
                cur = args[0].strip('"')
                if mac == "PORT_START":
                    ports[cur] = []
                fld = None
            elif mac in ("PORT_BIT", "PORT_DIPNAME", "PORT_CONFNAME", "PORT_SERVICE", "PORT_SERVICE_NO_TOGGLE",
                         "PORT_DIPUNUSED", "PORT_DIPUNUSED_DIPLOC", "PORT_DIPUNKNOWN", "PORT_DIPUNKNOWN_DIPLOC"):
                mask = int(args[0], 0)
                ports[cur] = [f for f in ports[cur] if not (f["mask"] & mask)]
                if mac == "PORT_BIT":
                    low = args[1] == "IP_ACTIVE_LOW"
                    t = args[2].replace("IPT_", "")
                    if t in TRACKBALL:
                        low = False
                    fld = dict(mask=mask, kind="unused" if t in IGNORED_TYPES else "input",
                               default=mask if low else 0, type=t, player=1, name=None, settings=[], fourway=False)
                elif mac in ("PORT_DIPNAME", "PORT_CONFNAME"):
                    fld = dict(mask=mask, kind="dip", default=int(args[1], 0), name=def_str(args[2]), settings=[])
                elif mac == "PORT_SERVICE":
                    off = idle_level(args[1], mask)
                    on = off ^ mask
                    fld = dict(mask=mask, kind="dip", default=off, name="Service Mode", settings=[(off, "Off"), (on, "On")])
                elif mac == "PORT_SERVICE_NO_TOGGLE":
                    fld = dict(mask=mask, kind="input", default=idle_level(args[1], mask), type="SERVICE", player=0,
                               name=None, settings=[], fourway=False)
                else:
                    d = {"IP_ACTIVE_LOW": mask, "IP_ACTIVE_HIGH": 0}.get(args[1])
                    fld = dict(mask=mask, kind="unused", default=int(args[1], 0) if d is None else d)
                ports[cur].append(fld)
            elif mac in ("PORT_DIPSETTING", "PORT_CONFSETTING"):
                val = int(args[0], 0)
                if all(v != val for v, _ in fld["settings"]):   # PORT_CONDITION alternatives: first listing wins
                    fld["settings"].append((val, def_str(args[1])))
            elif mac == "PORT_PLAYER":
                fld["player"] = int(args[0])
            elif mac == "PORT_COCKTAIL":
                fld["player"] = 2
            elif mac == "PORT_4WAY":
                fld["fourway"] = True
            elif mac == "PORT_REVERSE":
                fld["reverse"] = True
            elif mac == "PORT_NAME":
                fld["name"] = args[0].strip('"')
            elif mac == "PORT_IMPULSE":
                fld["impulse"] = True
            elif mac == "PORT_TOGGLE":
                fld["toggle"] = True
            elif mac == "PORT_2WAY":
                fld["twoway"] = True
            elif mac in ("PORT_DIPLOCATION", "PORT_CODE", "PORT_8WAY", "PORT_CONDITION",
                         "PORT_SENSITIVITY", "PORT_KEYDELTA", "PORT_CUSTOM_MEMBER"):
                pass
            else:
                raise SystemExit(f"INPUT_PORTS({name}): unhandled {mac}")
        cache[name] = ports
        return copy.deepcopy(ports)

    return build


def place(segs, setname, machine):
    """-> {ioctl index: [segment with addr]}"""
    over = REGION_OVERRIDE.get(machine, {})
    out = {}
    for m in MCUS.get(machine, ()):
        z, fname, crc, base, size = MCU_ROMS[m]
        out.setdefault(0, []).append(dict(name=fname, crc=crc, src=0, dst=0, len=size, flen=size, region=m,
                                          rsize=size, addr=base, zip=z))
    for s in segs:
        if s["region"] in over:
            if over[s["region"]] is None:
                continue
            idx, base, size = over[s["region"]]
        elif s["region"] in IGNORED_REGIONS:
            continue
        elif s["region"] not in REGIONS:
            raise SystemExit(f"{setname}: unmapped region {s['region']}")
        else:
            idx, (base, size) = 0, REGIONS[s["region"]]
        if s["dst"] >= size:
            continue                                   # e.g. the namco timing PROM
        if s["dst"] + s["len"] > size:
            raise SystemExit(f"{setname}: {s['name']} overruns {s['region']}")
        a, e = base + s["dst"], base + s["dst"] + s["len"]
        kept = []
        for o in out.get(idx, []):                                  # later loads, copies and fills overwrite earlier bytes
            oe = o["addr"] + o["len"]
            if oe <= a or o["addr"] >= e:
                kept.append(o)
                continue
            if o["addr"] < a:
                kept.append(dict(o, len=a - o["addr"]))
            if oe > e:
                kept.append(dict(o, addr=e, src=o["src"] + e - o["addr"], len=oe - e))
        out[idx] = kept + [dict(s, addr=a)]
    for idx in out:
        out[idx].sort(key=lambda s: s["addr"])
        for a, b in zip(out[idx], out[idx][1:]):
            assert a["addr"] + a["len"] <= b["addr"], f"{setname}: overlap {a['name']} / {b['name']}"
    return out


def whole_file(seg, segs):
    """True when this segment is the file's only load (no ROM_CONTINUE pieces)."""
    return (sum(1 for s in segs if s["name"] == seg["name"] and s["crc"] == seg["crc"]) == 1 and seg["src"] == 0
            and seg["len"] == seg["flen"])

# ---------------------------------------------------------------- inputs -> MRA

def input_config(g, ports):
    """-> (idle bytes, dip list, input map, 4-way, P1 button names, trackball reverse flags, coin impulse)."""
    idle, dips, imap, fourway, buttons, tb_rev, impulse = [], [], [0] * 32, False, {}, 0, False
    for p, names in enumerate(PORTS):
        tag = next((n for n in names if n in ports), names[0])
        fields = ports.get(tag)
        if fields is None:
            idle.append(0xFF)
            continue
        level = 0xFF
        for f in fields:
            level = (level & ~f["mask"]) | (f["default"] & f["mask"])
            if f["kind"] == "dip":
                lo = (f["mask"] & -f["mask"]).bit_length() - 1
                hi = f["mask"].bit_length() - 1
                if f["mask"] != ((1 << (hi + 1)) - (1 << lo)):
                    raise SystemExit(f'{g["name"]}: non-contiguous DIP {f["name"]} mask {f["mask"]:#x}')
                vals = [v >> lo for v, _ in f["settings"]]
                ids = ",".join(n.replace(",", ";") for _, n in f["settings"])
                bits = f"{p * 8 + lo}" if lo == hi else f"{p * 8 + lo},{p * 8 + hi}"
                seq = vals == list(range(len(vals))) and len(vals) == 1 << (hi - lo + 1)
                dips.append((f["name"], bits, ids, None if seq else ",".join(str(v) for v in vals)))
                if f["name"].startswith("Rack Test") and lo == hi:
                    imap[p * 8 + lo] = RACK_TOGGLE if f.get("toggle") else RACK_HOLD   # button flips the DIP
            elif f["kind"] == "input":
                t, pl = f["type"], f["player"]
                if t == "CUSTOM" and f["mask"] == 0x0F and tag in ("IN0", "IN1") and ports.get("P1"):
                    # Club Pac-Man: P1 / P2 joysticks multiplexed onto bits 0-3 by latch Q5 / Q4 (the board gates them)
                    for pf in ports["P1" if tag == "IN0" else "P2"]:
                        if pf["kind"] == "input":
                            imap[p * 8 + pf["mask"].bit_length() - 1] = CTL[(pf["type"], pf["player"])]
                            fourway |= pf["fourway"]
                    continue
                if t == "CUSTOM":
                    continue                           # no handler: a fixed level, already in the idle byte
                if t in TRACKBALL:
                    if f["mask"] != 0x0F:
                        raise SystemExit(f'{g["name"]}: trackball mask {f["mask"]:#x} in {tag}')
                    for b in range(4):
                        imap[p * 8 + b] = TRACKBALL[t] + b
                    tb_rev |= (1 if t == "TRACKBALL_X" else 2) if f.get("reverse") else 0
                    continue
                key = (t, pl if t.startswith(("JOYSTICK", "BUTTON")) else 0)
                if key not in CTL:
                    raise SystemExit(f'{g["name"]}: unmapped input {t} player {pl} in {tag}')
                if f["mask"] & (f["mask"] - 1):
                    raise SystemExit(f'{g["name"]}: multi-bit input {t} in {tag}')
                imap[p * 8 + f["mask"].bit_length() - 1] = CTL[key]
                impulse |= t.startswith("COIN") and f.get("impulse", False)
                fourway |= f["fourway"]
                if t.startswith("BUTTON") and pl == 1:
                    buttons[int(t[6:])] = f["name"] or ("Fire" if t == "BUTTON1" else f"Button {t[6:]}")
        idle.append(level & 0xFF)
    return idle, dips, imap, fourway, buttons, tb_rev, impulse


def parse_hiscores(path):
    """hiscore.dat -> {set: [entry lines]}; sets listed together share the entry lines below them."""
    out, names, body = {}, [], False
    for line in path.read_text(encoding="latin-1").splitlines():
        line = line.strip()
        if not line or line.startswith(";"):
            names, body = ([], False) if not line else (names, body)
            continue
        if line.endswith(":"):
            if body:
                names, body = [], False
            names.append(line[:-1])
        elif line.startswith("@"):
            for n in names:
                out.setdefault(n, []).append(line)
            body = True
    return out


HISCORES = parse_hiscores(HISCORE_DAT) if HISCORE_DAT.exists() else {}


def hiscore_xml(g):
    lines = HISCORES.get(g["name"])
    if not lines:
        return ""
    ents = []
    for line in lines:
        f = line.split(",")
        if f[0] != "@:maincpu" or f[1] != "program":
            raise SystemExit(f'{g["name"]}: unsupported hiscore.dat line {line}')
        ents.append((int(f[2], 16), int(f[3], 16), int(f[4], 16), int(f[5], 16)))
    rows = "\n".join(f"            {a >> 24 & 0xFF:02X} {a >> 16 & 0xFF:02X} {a >> 8 & 0xFF:02X} {a & 0xFF:02X} "
                      f"{n >> 8:02X} {n & 0xFF:02X} {s:02X} {e:02X}" for a, n, s, e in ents)
    total = sum(n for _, n, _, _ in ents)
    ref = next((k for k in HISCORE_INIT_FRAME if HISCORES.get(k) == lines), None)
    if ref is None:
        print(f'{g["name"]}: hiscore not measured yet, left out')
        return ""
    wait = round((HISCORE_INIT_FRAME[ref] + 2) / FRAME_HZ * CLK_HZ)
    header = " ".join(f"{b:02X}" for b in wait.to_bytes(4, "big")) + " " + HISCORE_HEADER_TAIL
    return f"""
    <!-- Index 3: hiscore config (MAME hiscore.dat), index 4: saved scores -->
    <rom index="3" md5="none">
        <part>
            {header}
{rows}
        </part>
    </rom>
    <rom index="4"></rom>
    <nvram index="4" size="{total}"></nvram>
"""


def mra(g, games, segs, build_inputs):
    variant = SUPPORTED[(g["machine"], g["init"])]
    ports = build_inputs(g["inputs"])
    idle, dips, imap, fourway, buttons, tb_rev, impulse = input_config(g, ports)
    twoway = any(f.get("twoway") for fields in ports.values() for f in fields)
    flags = (F_4WAY if fourway else 0) | (F_IMPULSE if impulse else 0) | (F_WIDE if g["init"] in WIDE_INITS or g["machine"] in WIDE_MACHINES else 0) | \
            (F_VERT if g["rot"] in ("ROT90", "ROT270") else 0) | \
            (F_ROT90 if g["rot"] == "ROT90" else 0)
    nbtn = max(buttons) if buttons else 0
    names = ",".join([buttons.get(i, "Not Used") for i in range(1, 5)] + ["Coin", "Start 1P", "Start 2P", "Pause"] +
                     [buttons.get(i, "Not Used") for i in (5, 6)] +
                     ["Rack Test" if RACK_HOLD in imap or RACK_TOGGLE in imap else "Not Used"])
    parent = g["parent"] or g["name"]
    zipname = "|".join([f'{g["name"]}.zip'] + ([f'{g["parent"]}.zip'] if g["parent"] else []) +
                       [MCU_ROMS[m][0] for m in MCUS.get(g["machine"], ())])
    rotation = {"ROT0": "horizontal", "ROT270": "vertical (ccw)", "ROT90": "vertical (cw)"}[g["rot"]]
    bootleg = "yes" if "bootleg" in g["manuf"].lower() or "hack" in g["desc"].lower() else "no"
    top = games.get(parent, g)                         # parent may live in another driver (suprglob: epos)
    series, category = SERIES_BY_PARENT.get(parent, (title_case(clean_title(top["desc"])), "Shooter"))
    region = next((r for w, r in REGION_WORDS if w in g["desc"]), "World")

    def part_lines(isegs):
        lines, pos = [], 0
        for s in isegs:
            if s["addr"] > pos:
                lines.append(f'        <part repeat="0x{s["addr"] - pos:X}">00</part>')
            if s.get("fill") is not None:
                lines.append(f'        <part repeat="0x{s["len"]:X}">{s["fill"]:02X}</part>')
            elif whole_file(s, isegs):
                lines.append(f'        <part crc="{s["crc"]}" name="{s["name"]}"/>')
            else:
                lines.append(f'        <part crc="{s["crc"]}" name="{s["name"]}" offset="0x{s["src"]:X}" length="0x{s["len"]:X}"/>')
            pos = s["addr"] + s["len"]
        return "\n".join(lines)

    sdram = ""
    if 2 in segs:
        sdram = f"""
    <!-- Index 2: SDRAM (large banked ROM regions) -->
    <rom index="2" md5="none" zip="{zipname}">
{part_lines(segs[2])}
    </rom>
"""

    dip_lines = "\n".join(f'        <dip name="{n}" bits="{b}" ids="{i}"' + (f' values="{v}"' if v else "") + "/>"
                          for n, b, i, v in dips)
    rom_dec, gfx_dec = DECODE.get(g["init"], (0, 0))
    gfx_dec |= GFX_BY_MACHINE.get(g["machine"], 0)
    cfg = [variant, flags, rom_dec, gfx_dec, tb_rev] + [0] * 11 + imap
    cfg_rows = "\n".join("            " + " ".join(f"{b:02X}" for b in cfg[i:i + 16]) for i in range(0, len(cfg), 16))
    return f"""<misterromdescription>
    <name>{display_name(g)}</name>
    <region>{region}</region>
    <homebrew>no</homebrew>
    <bootleg>{bootleg}</bootleg>
    <version></version>
    <alternative></alternative>
    <platform></platform>
    <series>{series}</series>
    <year>{g["year"]}</year>
    <manufacturer>{g["manuf"]}</manufacturer>
    <category>{category}</category>

    <setname>{g["name"]}</setname>
    <parent>{parent}</parent>
    <mameversion>{MAME_VERSION}</mameversion>
    <rbf>{RBF}</rbf>
    <about></about>

    <resolution>15kHz</resolution>
    <rotation>{rotation}</rotation>
    <flip>yes</flip>

    <players>2 (alternating)</players>
    <joystick>{"2-way" if twoway else "4-way" if fourway else "8-way"}</joystick>
    <special_controls>{"trackball" if any(24 <= i < 32 for i in imap) else ""}</special_controls>
    <num_buttons>{nbtn}</num_buttons>
    <buttons names="{names}" default="A,Y,B,X,Select,Start,R,L"/>

    <switches default="{",".join(f"{b:02X}" for b in idle)}">
{dip_lines}
    </switches>

    <!-- Index 0: CPUs 0x00000/0x08000/0x0C000, gfx 0x10000, PROMs 0x22000, waveform 0x23000, MCUs 0x2C000 -->
    <rom index="0" md5="none" zip="{zipname}">
{part_lines(segs.get(0, []))}
    </rom>
{sdram}
    <!-- Index 1: board variant, flags, input map (see Arcade-Galaga.sv) -->
    <rom index="1">
        <part>
{cfg_rows}
        </part>
    </rom>
{hiscore_xml(g)}
    <remark>{remark(g)}</remark>
    <mratimestamp>20261003000000</mratimestamp>
</misterromdescription>
"""


def title_case(text):
    """Capitalise every word, small words included; acronyms (US, II, PCB) stay as written."""
    out = []
    for word in re.split(r"(\s+|[()/,-])", text):
        if word and word[0].isalpha():
            word = word[0].upper() + word[1:]
        out.append(word)
    return "".join(out)


def clean_title(desc):
    """Parent title: the description without its trailing parenthesised qualifiers."""
    return re.sub(r"(\s*\([^()]*\))+$", "", desc).strip()


def display_name(g):
    return title_case(clean_title(g["desc"]) if g["parent"] is None else g["desc"])


def remark(g):
    """'Title (Maker)', without repeating a maker the title already names."""
    m = re.fullmatch(r'bootleg \((.+)\)', g["manuf"])
    maker = f"{m.group(1)} bootleg" if m else g["manuf"]
    desc = title_case(g["desc"])
    return desc if maker.lower() in g["desc"].lower() else f"{desc} ({title_case(maker)})"


def safe(name):
    return re.sub(r'\s*/\s*', " - ", re.sub(r'[\\:*?"<>|]', "-", name))


def out_path(root, g, games):
    if g["parent"] is None:
        return root / f"{safe(display_name(g))}.mra"
    parent_title = display_name(games[g["parent"]]) if g["parent"] in games else title_case(clean_title(g["desc"]))
    return root / "_alternatives" / f"_{safe(parent_title)}" / f"{safe(display_name(g))}.mra"


def main():
    src = "\n".join(Path(f).read_text() for f in sys.argv[1].split(","))
    out_dir = Path(sys.argv[2])
    games = parse_games(src)
    build_inputs = parse_inputs(src)
    names = sys.argv[3:] or [n for n, g in games.items()
                             if (g["machine"], g["init"]) in SUPPORTED and (g["working"] or n in WORKING_HERE)]
    for name in names:
        g = games[name]
        if (g["machine"], g["init"]) not in SUPPORTED:
            raise SystemExit(f'{name}: board {g["machine"]} / {g["init"]} not implemented')
        segs = place(parse_roms(src, name), name, g["machine"])
        path = out_path(out_dir, g, games)
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(mra(g, games, segs, build_inputs))
        print(f'{name:12s} {path.relative_to(out_dir)}')


if __name__ == "__main__":
    main()
