"""Read a Godot 4 pack (.pck) and check what it carries (plan 2026-10-07-kestrel-depth, Task 28).

  python3 tools/release/pck.py check <file.pck>    list problems (dev-only files in, game files missing); exit 1 on any
  python3 tools/release/pck.py list <file.pck>     print every path in the pack, one per line
  python3 tools/release/pck.py write <out.pck> <paths.txt>   write a minimal pack holding those paths (test fakes)

The pack layout read here is the unencrypted one Godot 4 writes: "GDPC", the pack format, the engine version, flags and
the file base, then (format 3 and later) the directory offset; 16 reserved words; the directory is a count followed by
entries of path length, path (padded to 4 bytes), offset, size, MD5 and flags. Format 2 puts the directory right after
the header. Paths are stored relative to res:// (older packs spell the res:// prefix; it is stripped here).
"""
import hashlib, re, struct, sys
from pathlib import Path

MAGIC = b"GDPC"
DIR_ENCRYPTED = 1

# Nothing from these trees, or of these kinds, belongs in a player's pack: tests (fixtures, the stub bridge), QA and
# asset tools, the dev bridge's runtime dir, the capture gallery, concept art, docs, the SDD ledger, Godot .uid noise,
# and anything a player's own session writes (settings, records, replays, runtime flags and packets).
FORBIDDEN_DIRS = ("tests/", "tools/", "runtime/", "scripts/gallery/", "art/", "docs/", ".superpowers/", "replays/", "build/")
FORBIDDEN_SUFFIXES = (".md", ".uid", ".sh", ".py", ".pyc", ".rpl", ".flag")
FORBIDDEN_NAMES = {"settings.cfg", "records.cfg", "override.cfg", "export_presets.cfg", "snapshot.json", "match.json",
                   "commands.txt", "replay_speed.txt", "stub_bridge.sh"}
# What the game cannot start without: the project settings, its main scene, the client and its bridge launcher, and the
# two JSON data files it reads raw (only the presets' include filter ships them), and the UI fonts' import remaps
# (scripts/ui/tokens.gd loads them; without them the UI falls back to Godot's default font).
REQUIRED = [
    ("project.binary", r"project\.binary"),
    ("the main scene (main.tscn)", r"main\.tscn(\.remap)?|main\.scn"),
    ("scripts/earthfront_3d.gd", r"scripts/earthfront_3d\.gd[c]?"),
    ("scripts/bridge_launcher.gd", r"scripts/bridge_launcher\.gd[c]?"),
    ("assets/audio/sfx/sfx_manifest.json", r"assets/audio/sfx/sfx_manifest\.json"),
    ("assets/world/props_atlas.json", r"assets/world/props_atlas\.json"),
] + [(f"assets/fonts/{f} (imported)", rf"assets/fonts/{re.escape(f)}\.import") for f in [
    "Rajdhani-SemiBold.ttf", "Rajdhani-Bold.ttf", "IBMPlexSans-VF.ttf", "IBMPlexMono-Regular.ttf", "IBMPlexMono-Medium.ttf"]]


def _clean(path: str) -> str:
    return path[len("res://"):] if path.startswith("res://") else path


def read_paths(pck) -> list:
    """Every file path in the pack, relative to res://, in directory order. ValueError when it is not a readable pack."""
    data = Path(pck).read_bytes()
    if len(data) < 24 or data[:4] != MAGIC:
        raise ValueError(f"{pck} is not a Godot pack (no GDPC header)")
    fmt = struct.unpack_from("<I", data, 4)[0]
    flags = struct.unpack_from("<I", data, 20)[0] if fmt >= 2 else 0
    if flags & DIR_ENCRYPTED:
        raise ValueError(f"{pck} has an encrypted directory")
    if fmt >= 3:
        at = struct.unpack_from("<Q", data, 32)[0]
    elif fmt == 2:
        at = 4 + 4 + 12 + 4 + 8 + 16 * 4
    else:
        raise ValueError(f"{pck}: pack format {fmt} is not a Godot 4 pack")
    try:
        count = struct.unpack_from("<I", data, at)[0]
        at += 4
        paths = []
        for _ in range(count):
            length = struct.unpack_from("<I", data, at)[0]
            at += 4
            paths.append(_clean(data[at:at + length].rstrip(b"\0").decode("utf-8")))
            at += length + 8 + 8 + 16 + (4 if fmt >= 2 else 0)
    except (struct.error, UnicodeDecodeError) as e:
        raise ValueError(f"{pck}: unreadable directory ({e})") from e
    return paths


def write_pack(out, paths, fmt=3) -> None:
    """A minimal valid pack whose files hold their own path as content (Godot 4.7 writes format 3 and later)."""
    blobs = [p.encode() for p in paths]
    header_len = 4 + 4 + 12 + 4 + 8 + (8 if fmt >= 3 else 0) + 16 * 4
    entries = b""
    for p, blob in zip(paths, blobs):
        name = p.encode()
        name += b"\0" * (-len(name) % 4)
        entries += struct.pack("<I", len(name)) + name
        entries += struct.pack("<QQ", 0, len(blob)) + hashlib.md5(blob).digest() + struct.pack("<I", 0)
    directory = struct.pack("<I", len(paths)) + entries
    body = b"".join(blobs)
    if fmt >= 3:
        file_base = header_len
        header = MAGIC + struct.pack("<IIIIIQQ", fmt, 4, 7, 2, 0, file_base, header_len + len(body))
        data = header + b"\0" * 64 + body + directory
    else:
        file_base = header_len + len(directory)
        header = MAGIC + struct.pack("<IIIIIQ", fmt, 4, 2, 0, 0, file_base)
        data = header + b"\0" * 64 + directory + body
    Path(out).write_bytes(data)


def problems(paths) -> list:
    """What is wrong with a pack holding `paths`: each dev-only file in it, then each game file missing from it."""
    out = []
    for p in paths:
        name = p.rsplit("/", 1)[-1]
        if p.startswith(FORBIDDEN_DIRS) or p.endswith(FORBIDDEN_SUFFIXES) or name in FORBIDDEN_NAMES:
            out.append(f"dev-only file in the pack: {p}")
    for label, pattern in REQUIRED:
        if not any(re.fullmatch(pattern, p) for p in paths):
            out.append(f"missing from the pack: {label}")
    return out


def main(argv) -> int:
    if len(argv) == 3 and argv[1] in ("check", "list"):
        try:
            paths = read_paths(argv[2])
        except (OSError, ValueError) as e:
            print(f"pck.py: {e}", file=sys.stderr)
            return 1
        if argv[1] == "list":
            print("\n".join(paths))
            return 0
        found = problems(paths)
        for f in found:
            print(f"pck.py: {f}", file=sys.stderr)
        size = Path(argv[2]).stat().st_size
        print(f"pck.py: {argv[2]}: {len(paths)} files, {size / 1e6:.1f} MB, {'REFUSED' if found else 'ok'}")
        return 1 if found else 0
    if len(argv) == 4 and argv[1] == "write":
        write_pack(argv[2], [l for l in Path(argv[3]).read_text().splitlines() if l.strip()])
        return 0
    print("usage: pck.py check|list <file.pck> | write <out.pck> <paths.txt>", file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
