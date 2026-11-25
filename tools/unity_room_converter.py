#!/usr/bin/env python3
"""Unity -> Godot room converter (Phase P1). Stdlib only; run with `python -I`.

Reads the Sunnyland tileset .png.meta and DirtCave0..3 .unity scenes and writes
  tools/room_data/tileset.json
  tools/room_data/dirt_cave_N.json
  tools/room_previews/dirt_cave_N.png   (composited preview, stdlib PNG codec)

Units: 1 Unity unit = 16 px, y negated. Tile cell (x, y) -> Godot cell (x + ox, -(y + oy) - 1)
where (ox, oy) is the (integer) world offset of the Tilemap GameObject.
Unity YAML is parsed with regexes (custom tags make YAML libraries unusable).
"""
import json
import os
import re
import struct
import sys
import zlib

UNITY = r"D:\UnityProjects\SilkMelody\Assets"
TILESET_PNG = UNITY + r"\Misc\TilesetSprite\Sunnyland\artwork\Environment\sunnyland_tileset.png"
SCENE_DIR = UNITY + r"\Scene\Level\DirtCaveArea"
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DATA_DIR = os.path.join(ROOT, "tools", "room_data")
PREVIEW_DIR = os.path.join(ROOT, "tools", "room_previews")
PX = 16.0
ROOMS = [0, 1, 2, 3]
LAYER_NAMES = ["Background", "Tilemap", "Foreground"]
DISABLED_TARGETS = {"DirtCave4", "DirtCave14"}  # unported rooms

TILESET_GUID = "261212b977f594d5dbc48631a5c1295c"
CHANGE_LEVEL_SCRIPT_GUID = "dfc45ec56bf48ea4c93e9f0c4369f658"
PREFAB_GUIDS = {  # from each <prefab>.prefab.meta
    "17b5050de626d824fbe5295147c07027": "Crawling",
    "acccdb896f8eb4447b0fdb823253d53c": "Dipsa",
    "9aec5bbe4071f5b4684844efc738145a": "Crabber",
    "5471ba155617b754fadabe72d6802bf3": "RestChair",
    "ba19acb34ed04654a9855dd604a9ffac": "Tenroh",
}

WARNINGS = []


def warn(msg):
    WARNINGS.append(msg)
    print("WARNING:", msg)


# ---------------------------------------------------------------- PNG codec
def png_decode(path):
    with open(path, "rb") as f:
        data = f.read()
    assert data[:8] == b"\x89PNG\r\n\x1a\n"
    pos = 8
    idat = b""
    while pos < len(data):
        ln, = struct.unpack(">I", data[pos:pos + 4])
        typ = data[pos + 4:pos + 8]
        chunk = data[pos + 8:pos + 8 + ln]
        pos += 12 + ln
        if typ == b"IHDR":
            w, h, depth, ctype, _, _, interlace = struct.unpack(">IIBBBBB", chunk)
            assert depth == 8 and ctype == 6 and interlace == 0, "need 8-bit RGBA non-interlaced"
        elif typ == b"IDAT":
            idat += chunk
    raw = zlib.decompress(idat)
    bpp = 4
    stride = w * bpp
    out = bytearray(h * stride)
    prev = bytearray(stride)
    p = 0
    for y in range(h):
        ft = raw[p]
        line = bytearray(raw[p + 1:p + 1 + stride])
        p += 1 + stride
        if ft == 1:
            for i in range(bpp, stride):
                line[i] = (line[i] + line[i - bpp]) & 255
        elif ft == 2:
            for i in range(stride):
                line[i] = (line[i] + prev[i]) & 255
        elif ft == 3:
            for i in range(stride):
                a = line[i - bpp] if i >= bpp else 0
                line[i] = (line[i] + ((a + prev[i]) >> 1)) & 255
        elif ft == 4:
            for i in range(stride):
                a = line[i - bpp] if i >= bpp else 0
                b = prev[i]
                c = prev[i - bpp] if i >= bpp else 0
                pa, pb, pc = abs(b - c), abs(a - c), abs(a + b - 2 * c)
                pr = a if (pa <= pb and pa <= pc) else (b if pb <= pc else c)
                line[i] = (line[i] + pr) & 255
        out[y * stride:(y + 1) * stride] = line
        prev = line
    return w, h, out


def png_encode(path, w, h, rgba):
    def chunk(t, d):
        c = struct.pack(">I", len(d)) + t + d
        return c + struct.pack(">I", zlib.crc32(t + d) & 0xFFFFFFFF)
    raw = bytearray()
    stride = w * 4
    for y in range(h):
        raw.append(0)
        raw += rgba[y * stride:(y + 1) * stride]
    png = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 6, 0, 0, 0)) \
        + chunk(b"IDAT", zlib.compress(bytes(raw), 9)) + chunk(b"IEND", b"")
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "wb") as f:
        f.write(png)


# ---------------------------------------------------------------- tileset
def parse_tileset_meta(img_h):
    """Returns (fileid -> (ax, ay), list of all [ax, ay])."""
    text = open(TILESET_PNG + ".meta", encoding="utf8").read()
    id_to_name = {}
    for m in re.finditer(r"213: (\d+)\n\s+second: (\S+)", text):
        id_to_name[int(m.group(1))] = m.group(2)
    rects = {}
    for m in re.finditer(
            r"- serializedVersion: 2\n\s+name: (\S+)\n\s+rect:\n\s+serializedVersion: 2\n"
            r"\s+x: (\d+)\n\s+y: (\d+)\n\s+width: (\d+)\n\s+height: (\d+)", text):
        rects[m.group(1)] = tuple(int(m.group(i)) for i in range(2, 6))
    fid_to_atlas = {}
    for fid, name in id_to_name.items():
        x, y, w, h = rects[name]
        assert w == 16 and h == 16 and x % 16 == 0 and (img_h - y - h) % 16 == 0
        fid_to_atlas[fid] = (x // 16, (img_h - y - h) // 16)  # Unity rect y is from the bottom
    return fid_to_atlas


# ---------------------------------------------------------------- scene parsing
class Scene:
    def __init__(self, path):
        text = open(path, encoding="utf8").read()
        self.blocks = {}  # fileID -> (classId, stripped, body)
        parts = re.split(r"^--- !u!(\d+) &(-?\d+)( stripped)?\n", text, flags=re.M)
        for i in range(1, len(parts), 4):
            self.blocks[int(parts[i + 1])] = (int(parts[i]), bool(parts[i + 2]), parts[i + 3])
        self.go_name = {}
        self.go_comps = {}
        self.go_active = {}
        self.transform_of_go = {}
        for fid, (cls, _, body) in self.blocks.items():
            if cls == 1:
                self.go_name[fid] = re.search(r"m_Name: (.*)", body).group(1).strip()
                self.go_comps[fid] = [int(c) for c in re.findall(r"component: \{fileID: (-?\d+)\}", body)]
                self.go_active[fid] = re.search(r"m_IsActive: (\d)", body).group(1) == "1"
        for fid, (cls, _, body) in self.blocks.items():
            if cls == 4:
                m = re.search(r"m_GameObject: \{fileID: (-?\d+)\}", body)
                if m and int(m.group(1)) in self.go_name:
                    self.transform_of_go[int(m.group(1))] = fid
        # prefab instances: transform fileID of root -> instance id
        self.prefab_instances = {}
        for fid, (cls, _, body) in self.blocks.items():
            if cls == 1001:
                guid = re.search(r"m_SourcePrefab: \{[^}]*guid: (\w+)", body).group(1)
                father = int(re.search(r"m_TransformParent: \{fileID: (-?\d+)\}", body).group(1))
                mods = {}
                name = None
                for mm in re.finditer(r"- target: \{fileID: (-?\d+)[^}]*\}\n\s+propertyPath: (\S+)\n\s+value: (.*)\n", body):
                    path, val = mm.group(2), mm.group(3).strip()
                    mods.setdefault(int(mm.group(1)), {})[path] = val
                    if path == "m_Name":
                        name = val
                self.prefab_instances[fid] = dict(guid=guid, father=father, mods=mods, name=name)

    def _vec(self, body, key):
        m = re.search(key + r": \{x: ([-\d.e]+), y: ([-\d.e]+), z: ([-\d.e]+)\}", body)
        return [float(m.group(i)) for i in (1, 2, 3)]

    def transform_local(self, tid):
        """Return (local_pos, local_scale, father_tid) for a transform block."""
        cls, stripped, body = self.blocks[tid]
        if stripped:  # stripped prefab transform -> values come from the instance's modifications
            inst_id = int(re.search(r"m_PrefabInstance: \{fileID: (-?\d+)\}", body).group(1))
            inst = self.prefab_instances[inst_id]
            tgt = int(re.search(r"m_CorrespondingSourceObject: \{fileID: (-?\d+)", body).group(1))
            mods = inst["mods"].get(tgt, {})
            pos = [float(mods.get("m_LocalPosition." + a, 0)) for a in "xyz"]
            scl = [float(mods.get("m_LocalScale." + a, 1)) for a in "xyz"]
            rz = float(mods.get("m_LocalRotation.z", 0))
            if abs(rz) > 1e-6:
                warn("rotated prefab transform %d (ignored)" % tid)
            return pos, scl, inst["father"]
        rot = self._vec_q(body)
        if abs(rot[2]) > 1e-6 or abs(rot[0]) > 1e-6 or abs(rot[1]) > 1e-6:
            warn("rotated transform %d (rotation ignored)" % tid)
        return (self._vec(body, "m_LocalPosition"), self._vec(body, "m_LocalScale"),
                int(re.search(r"m_Father: \{fileID: (-?\d+)\}", body).group(1)))

    def _vec_q(self, body):
        m = re.search(r"m_LocalRotation: \{x: ([-\d.e]+), y: ([-\d.e]+), z: ([-\d.e]+), w: ([-\d.e]+)\}", body)
        return [float(m.group(i)) for i in (1, 2, 3, 4)]

    def world(self, tid):
        """World position + lossy scale of a transform (parents resolved, rotation ignored)."""
        pos, scl, father = self.transform_local(tid)
        if father == 0:
            return pos, scl
        ppos, pscl = self.world(father)
        return ([ppos[0] + pscl[0] * pos[0], ppos[1] + pscl[1] * pos[1], ppos[2] + pscl[2] * pos[2]],
                [pscl[0] * scl[0], pscl[1] * scl[1], pscl[2] * scl[2]])

    def instance_world(self, inst):
        """World position of a prefab instance's root."""
        root = None
        for tgt, mods in inst["mods"].items():
            if "m_LocalPosition.x" in mods:
                root = mods
        pos = [float(root.get("m_LocalPosition." + a, 0)) for a in "xyz"]
        if inst["father"] != 0:
            ppos, pscl = self.world(inst["father"])
            pos = [ppos[i] + pscl[i] * pos[i] for i in range(3)]
        return pos


def px(v):
    return round(v * PX, 3)


def p2(x, y):
    return [px(x), px(-y)]


def parse_tiles(body, fid_to_atlas, tm_name):
    """Return list of (cx, cy, atlas_x, atlas_y, flip_h, flip_v) in Unity cell coords, plus tile index count."""
    i_sprites = body.index("m_TileSpriteArray:")
    i_matrix = body.index("m_TileMatrixArray:")
    i_color = body.index("m_TileColorArray:")
    sprite_fids = [int(m.group(1)) for m in re.finditer(
        r"m_Data: \{fileID: (-?\d+), guid: (\w+)", body[i_sprites:i_matrix])]
    for m in re.finditer(r"m_Data: \{fileID: (-?\d+), guid: (\w+)", body[i_sprites:i_matrix]):
        if m.group(2) != TILESET_GUID:
            warn("%s: tile sprite from another texture guid %s" % (tm_name, m.group(2)))
    # m_Data entries with fileID 0 (no guid) are empty slots; keep slot alignment
    sprite_slots = []
    for m in re.finditer(r"- m_RefCount: \d+\n\s+m_Data: \{fileID: (-?\d+)", body[i_sprites:i_matrix]):
        sprite_slots.append(int(m.group(1)))
    matrices = []
    for m in re.finditer(r"- m_RefCount: \d+\n\s+m_Data:\n((?:\s+e\d\d: .*\n)+)", body[i_matrix:i_color]):
        vals = dict(re.findall(r"(e\d\d): (\S+)", m.group(1)))
        matrices.append({k: float(v) for k, v in vals.items()})
    tiles = []
    n_entries = 0
    i_tiles = body.index("m_Tiles:")
    for m in re.finditer(
            r"- first: \{x: (-?\d+), y: (-?\d+), z: (-?\d+)\}\n\s+second:\n\s+serializedVersion: \d+\n"
            r"\s+m_TileIndex: (\d+)\n\s+m_TileSpriteIndex: (\d+)\n\s+m_TileMatrixIndex: (\d+)", body[i_tiles:i_sprites]):
        n_entries += 1
        x, y, z, _, si, mi = (int(m.group(i)) for i in range(1, 7))
        fid = sprite_slots[si]
        if fid not in fid_to_atlas:
            warn("%s: tile (%d,%d) has unknown sprite fileID %d" % (tm_name, x, y, fid))
            continue
        mat = matrices[mi]
        if mat["e01"] != 0 or mat["e10"] != 0:
            warn("%s: tile (%d,%d) has rotation/transpose matrix (unsupported, drawn unrotated)" % (tm_name, x, y))
        if mat["e03"] != 0 or mat["e13"] != 0 or abs(abs(mat["e00"]) - 1) > 1e-6 or abs(abs(mat["e11"]) - 1) > 1e-6:
            warn("%s: tile (%d,%d) has translation/scale matrix %s" % (tm_name, x, y, mat))
        ax, ay = fid_to_atlas[fid]
        tiles.append((x, y, ax, ay, mat["e00"] < 0, mat["e11"] < 0, z))
    return tiles, n_entries


def convert_room(n, fid_to_atlas):
    path = os.path.join(SCENE_DIR, "DirtCave%d.unity" % n)
    sc = Scene(path)
    room = {"name": "DirtCave%d" % n, "layers": {}, "layer_unity_counts": {}, "entries": [], "exits": [],
            "player_start": None, "enemies": [], "rest_chairs": [], "tile_offsets": {}}

    # tilemaps
    for fid, (cls, _, body) in sc.blocks.items():
        if cls != 1839735485:
            continue
        go = int(re.search(r"m_GameObject: \{fileID: (-?\d+)\}", body).group(1))
        name = sc.go_name[go]
        if name not in LAYER_NAMES:
            warn("room %d: unexpected tilemap %s" % (n, name))
            continue
        wpos, wscl = sc.world(sc.transform_of_go[go])
        anchor = re.search(r"m_TileAnchor: \{x: ([-\d.]+), y: ([-\d.]+)", body)
        ox, oy = wpos[0], wpos[1]
        if abs(ox - round(ox)) > 1e-6 or abs(oy - round(oy)) > 1e-6 or wscl[:2] != [1.0, 1.0]:
            warn("room %d %s: non-integer tilemap offset/scale %s %s" % (n, name, wpos, wscl))
        if float(anchor.group(1)) != 0.5 or float(anchor.group(2)) != 0.5:
            warn("room %d %s: non-default tile anchor" % (n, name))
        ox, oy = int(round(ox)), int(round(oy))
        room["tile_offsets"][name] = [ox, oy]
        tiles, count = parse_tiles(body, fid_to_atlas, "DirtCave%d/%s" % (n, name))
        cells = []
        for (x, y, ax, ay, fh, fv, z) in tiles:
            if z != 0:
                warn("room %d %s: tile z != 0" % (n, name))
            cells.append([x + ox, -(y + oy) - 1, ax, ay, int(fh), int(fv)])
        cells.sort(key=lambda c: (c[1], c[0]))
        room["layers"][name] = cells
        room["layer_unity_counts"][name] = count
    room["unity_total_tiles"] = sum(room["layer_unity_counts"].values())

    # GameObjects: Entry markers, exits
    for go, name in sc.go_name.items():
        comps = sc.go_comps[go]
        tid = sc.transform_of_go.get(go)
        if tid is None:
            continue
        wpos, wscl = sc.world(tid)
        if re.match(r"Entry\d+$", name):
            room["entries"].append({"name": name, "pos": p2(wpos[0], wpos[1])})
            continue
        trigger = None
        box = None
        for c in comps:
            cls, _, body = sc.blocks[c]
            if cls == 114 and CHANGE_LEVEL_SCRIPT_GUID in body:
                trigger = dict(re.findall(r"^\s+(levelName|spawnPosName): (.*)$", body, flags=re.M))
            if cls == 61:
                mo = re.search(r"m_Offset: \{x: ([-\d.e]+), y: ([-\d.e]+)\}", body)
                ms = re.search(r"m_Size: \{x: ([-\d.e]+), y: ([-\d.e]+)\}", body)
                en = re.search(r"m_Enabled: (\d)", body).group(1)
                box = dict(offset=[float(mo.group(1)), float(mo.group(2))],
                           size=[float(ms.group(1)), float(ms.group(2))], enabled=en == "1",
                           trigger=re.search(r"m_IsTrigger: (\d)", body).group(1) == "1")
        if trigger is not None:
            if box is None:
                warn("room %d: ChangeLevelTrigger %s without BoxCollider2D" % (n, name))
                continue
            if not sc.go_active[go] or not box["enabled"]:
                warn("room %d: exit %s inactive/disabled in Unity" % (n, name))
            lvl, spawn = trigger["levelName"].strip(), trigger["spawnPosName"].strip()
            room["exits"].append({
                "name": name,
                "pos": p2(wpos[0], wpos[1]),
                "size": [px(abs(box["size"][0] * wscl[0])), px(abs(box["size"][1] * wscl[1]))],
                "offset": p2(box["offset"][0] * wscl[0], box["offset"][1] * wscl[1]),
                "level_name": lvl,
                "spawn_pos_name": spawn,
                "disabled": lvl in DISABLED_TARGETS,
            })

    # prefab instances
    counters = {}
    for fid, inst in sorted(sc.prefab_instances.items()):
        kind = PREFAB_GUIDS.get(inst["guid"])
        if kind is None:
            continue
        wp = sc.instance_world(inst)
        pos = p2(wp[0], wp[1])
        uname = inst["name"] or kind  # m_Name modification, else prefab root name
        if kind == "Tenroh":
            room["player_start"] = {"pos": pos, "unity_name": uname}
        elif kind == "RestChair":
            room["rest_chairs"].append({"name": uname, "pos": pos, "name_overridden": inst["name"] is not None})
        else:
            room["enemies"].append({"type": kind, "unity_name": uname, "pos": pos})
    room["entries"].sort(key=lambda e: e["name"])
    room["exits"].sort(key=lambda e: e["name"])
    room["enemies"].sort(key=lambda e: (e["type"], e["pos"]))
    return room


# ---------------------------------------------------------------- preview
def render_preview(room, tw, th, tex, path):
    cells_all = [c for l in LAYER_NAMES for c in room["layers"].get(l, [])]
    xs = [c[0] for c in cells_all]
    ys = [c[1] for c in cells_all]
    minx, maxx, miny, maxy = min(xs), max(xs) + 1, min(ys), max(ys) + 1
    # include markers
    pts = [e["pos"] for e in room["entries"]] + [x["pos"] for x in room["exits"]] + \
          [e["pos"] for e in room["enemies"]] + [c["pos"] for c in room["rest_chairs"]]
    if room["player_start"]:
        pts.append(room["player_start"]["pos"])
    for p in pts:
        minx = min(minx, int(p[0] // 16) - 1)
        maxx = max(maxx, int(p[0] // 16) + 2)
        miny = min(miny, int(p[1] // 16) - 1)
        maxy = max(maxy, int(p[1] // 16) + 2)
    W, H = (maxx - minx) * 16, (maxy - miny) * 16
    buf = bytearray(W * H * 4)
    for i in range(0, len(buf), 4):
        buf[i:i + 4] = b"\x18\x1a\x22\xff"

    def blend(x, y, r, g, b, a):
        if 0 <= x < W and 0 <= y < H:
            i = (y * W + x) * 4
            buf[i] = (buf[i] * (255 - a) + r * a) // 255
            buf[i + 1] = (buf[i + 1] * (255 - a) + g * a) // 255
            buf[i + 2] = (buf[i + 2] * (255 - a) + b * a) // 255

    for lname in LAYER_NAMES:
        for (gx, gy, ax, ay, fh, fv) in room["layers"].get(lname, []):
            for yy in range(16):
                for xx in range(16):
                    sx = ax * 16 + (15 - xx if fh else xx)
                    sy = ay * 16 + (15 - yy if fv else yy)
                    si = (sy * tw + sx) * 4
                    a = tex[si + 3]
                    if a:
                        blend((gx - minx) * 16 + xx, (gy - miny) * 16 + yy, tex[si], tex[si + 1], tex[si + 2], a)

    def box(cx, cy, w, h, col, fill=60, edge=255):
        x0 = int(round(cx - minx * 16 - w / 2))
        y0 = int(round(cy - miny * 16 - h / 2))
        for yy in range(int(h)):
            for xx in range(int(w)):
                on_edge = xx < 1 or yy < 1 or xx >= int(w) - 1 or yy >= int(h) - 1
                blend(x0 + xx, y0 + yy, col[0], col[1], col[2], edge if on_edge else fill)

    for e in room["exits"]:
        col = (140, 140, 140) if e["disabled"] else (255, 40, 40)
        box(e["pos"][0] + e["offset"][0], e["pos"][1] + e["offset"][1], e["size"][0], e["size"][1], col)
    for e in room["entries"]:
        box(e["pos"][0], e["pos"][1], 8, 8, (40, 255, 60), 200)
    if room["player_start"]:
        box(room["player_start"]["pos"][0], room["player_start"]["pos"][1], 12, 20, (60, 120, 255), 150)
    ecol = {"Crawling": (255, 160, 0), "Dipsa": (200, 60, 255), "Crabber": (255, 100, 160)}
    for e in room["enemies"]:
        box(e["pos"][0], e["pos"][1], 14, 12, ecol[e["type"]], 160)
    for c in room["rest_chairs"]:
        box(c["pos"][0], c["pos"][1], 16, 16, (255, 240, 40), 160)
    png_encode(path, W, H, buf)
    return W, H


# ---------------------------------------------------------------- main
def main():
    tw, th, tex = png_decode(TILESET_PNG)
    fid_to_atlas = parse_tileset_meta(th)
    atlas_cells = sorted(set(fid_to_atlas.values()), key=lambda c: (c[1], c[0]))
    os.makedirs(DATA_DIR, exist_ok=True)
    with open(os.path.join(DATA_DIR, "tileset.json"), "w") as f:
        json.dump({"texture": "res://assets/tiles/sunnyland_tileset.png", "tile_size": 16,
                   "image_size": [tw, th], "tiles": [list(c) for c in atlas_cells]}, f, indent=1)
    print("tileset: %dx%d, %d sprites" % (tw, th, len(atlas_cells)))
    for n in ROOMS:
        room = convert_room(n, fid_to_atlas)
        got = sum(len(v) for v in room["layers"].values())
        print("DirtCave%d: unity tiles %d, converted %d %s | entries %d exits %d enemies %d chairs %d start %s" % (
            n, room["unity_total_tiles"], got, {k: len(v) for k, v in room["layers"].items()},
            len(room["entries"]), len(room["exits"]), len(room["enemies"]), len(room["rest_chairs"]),
            room["player_start"]["pos"] if room["player_start"] else None))
        flips = sum(1 for l in room["layers"].values() for c in l if c[4] or c[5])
        room["flipped_tiles"] = flips
        with open(os.path.join(DATA_DIR, "dirt_cave_%d.json" % n), "w") as f:
            json.dump(room, f, indent=None, separators=(",", ":"))
        w, h = render_preview(room, tw, th, tex, os.path.join(PREVIEW_DIR, "dirt_cave_%d.png" % n))
        print("  preview %dx%d, flipped tiles %d" % (w, h, flips))
    print("warnings:", len(WARNINGS))
    return 1 if WARNINGS else 0


if __name__ == "__main__":
    sys.exit(main())
