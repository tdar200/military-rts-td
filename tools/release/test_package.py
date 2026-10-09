"""Release packaging checks (plan 2026-10-07-kestrel-depth, Task 28).
Run: cd tools/release && python3 -m unittest test_package -v

What is pinned here:
- godot3d/export_presets.cfg has a Linux and a Windows Desktop preset, both x86_64, whose filters keep the tests, the
  QA tools, the dev runtime dir, the capture gallery, docs and Godot .uid noise out of the pack, while every data file
  the game reads at runtime still ships.
- One version everywhere: godot3d/project.godot config/version, the Cargo workspace version (rts-server takes it,
  D4), and the rts-server entry in Cargo.lock.
- tools/release/package.sh refuses to start, with a message that says what is missing, when the Godot export
  templates or (for Windows) the Rust target or the MinGW linker are absent. These runs point HOME at an empty temp
  dir, so they never see the real machine's templates and never build anything.
- The packaging pipeline itself, run end to end with a fake Godot and a fake bridge (no export templates needed):
  the bridge lands beside the executable with its exec bit, VERSION is written, the archive is named
  ascension-<version>-linux-x86_64.tar.gz, and a pack carrying a dev file is refused.
- pck.py reads a Godot pack's file list and names any dev-only file in it.
"""
import fnmatch, os, pathlib, re, stat, subprocess, sys, tarfile, tempfile, tomllib, unittest, zipfile

HERE = pathlib.Path(__file__).resolve().parent
ROOT = HERE.parents[1]
sys.path.insert(0, str(HERE))

PRESETS = ROOT / "godot3d" / "export_presets.cfg"
PROJECT = ROOT / "godot3d" / "project.godot"
PACKAGE = HERE / "package.sh"
ENGINE = "4.7.2.stable"
# The dev-only trees and file kinds no export may carry (the brief's list; .superpowers and docs live outside godot3d).
MUST_EXCLUDE = ["tests/*", "tools/*", "runtime/*", "scripts/gallery/*", "art/*", "*.md", "*.uid", "*.sh", "*.py", "*.pyc"]


def read_cfg(path: pathlib.Path) -> dict:
    """Godot's ConfigFile text as {section: {key: value}}; quoted strings are unquoted, everything else stays text."""
    sections: dict = {}
    current = None
    for raw in path.read_text().splitlines():
        line = raw.strip()
        if not line or line.startswith(";"):
            continue
        m = re.fullmatch(r"\[(.+)\]", line)
        if m:
            current = sections.setdefault(m.group(1), {})
            continue
        key, _, value = line.partition("=")
        if len(value) >= 2 and value[0] == '"' and value[-1] == '"':
            value = value[1:-1]
        current[key] = value
    return sections


def presets() -> dict:
    """{preset name: (main section, options section)}."""
    cfg = read_cfg(PRESETS)
    out = {}
    for name, body in cfg.items():
        if re.fullmatch(r"preset\.\d+", name):
            out[body["name"]] = (body, cfg.get(name + ".options", {}))
    return out


def filters(text: str) -> list:
    return [p.strip() for p in text.split(",") if p.strip()]


def project_version() -> str:
    m = re.search(r'^config/version="([^"]*)"', PROJECT.read_text(), re.M)
    return m.group(1) if m else ""


def cargo_workspace_version() -> str:
    return tomllib.loads((ROOT / "Cargo.toml").read_text())["workspace"]["package"].get("version", "")


def ships(path: str, main: dict) -> bool:
    """Whether the preset's filters let a non-resource file at `path` (relative to res://) into the pack."""
    included = any(fnmatch.fnmatch(path, p) for p in filters(main.get("include_filter", "")))
    excluded = any(fnmatch.fnmatch(path, p) for p in filters(main.get("exclude_filter", "")))
    return included and not excluded


def run_package(*args, env=None, timeout=120):
    return subprocess.run(["bash", str(PACKAGE), *args], capture_output=True, text=True, env=env, timeout=timeout)


def bare_env(home: pathlib.Path, **extra) -> dict:
    """The current environment with HOME moved and every XDG override dropped, so templates resolve under `home`."""
    env = {k: v for k, v in os.environ.items() if not k.startswith("XDG_")}
    env["HOME"] = str(home)
    env.update(extra)
    return env


def write_exec(path: pathlib.Path, text: str) -> pathlib.Path:
    path.write_text(text)
    path.chmod(0o755)
    return path


class Presets(unittest.TestCase):
    def test_linux_and_windows_presets_are_x86_64(self):
        got = presets()
        self.assertEqual(set(got), {"Linux", "Windows Desktop"})
        self.assertEqual(got["Linux"][0]["platform"], "Linux")
        self.assertEqual(got["Windows Desktop"][0]["platform"], "Windows Desktop")
        for name, (main, options) in got.items():
            self.assertEqual(options.get("binary_format/architecture"), "x86_64", name)
            # package.sh expects the pack beside the executable (the bridge sits there too).
            self.assertEqual(options.get("binary_format/embed_pck"), "false", name)
            self.assertEqual(main.get("export_filter"), "all_resources", name)

    def test_filters_keep_dev_files_out_of_both_presets(self):
        for name, (main, _options) in presets().items():
            excluded = filters(main.get("exclude_filter", ""))
            for pattern in MUST_EXCLUDE:
                self.assertIn(pattern, excluded, f"{name} must exclude {pattern}")
            for dev in ["tests/fixtures/stub_bridge.sh", "tests/fixtures/kestrel_snapshot.json", "runtime/snapshot.json",
                        "tools/generate_assets.py", "README.md", "scripts/ui/README.md", "scripts/earthfront_3d.gd.uid"]:
                self.assertFalse(ships(dev, main), f"{name} would ship {dev}")

    def test_no_game_script_reads_an_imported_file_raw(self):
        """An imported file (a font, a texture, a sound) ships only in its imported form, so a raw read of its source
        works from source and fails in the export. The first exported smoke run drew the title without its UI fonts
        for exactly this reason (tokens.gd used FontFile.load_dynamic_font); load() the resource instead."""
        for script in (ROOT / "godot3d" / "scripts").rglob("*.gd"):
            if "gallery" in script.parts:
                continue
            text = script.read_text()
            self.assertNotIn("load_dynamic_font(", text, script.name)
            self.assertIsNone(re.search(r'(get_file_as_bytes|Image\.load_from_file)\("res://', text), script.name)

    def test_the_two_presets_ship_the_same_files(self):
        got = presets()
        for key in ["export_filter", "include_filter", "exclude_filter"]:
            self.assertEqual(got["Linux"][0].get(key), got["Windows Desktop"][0].get(key), key)

    def test_every_raw_file_the_game_reads_ships(self):
        """A FileAccess read of a res:// .json opens the raw file, not an imported resource, so only the include filter
        puts it in the pack. Every such path in the game's scripts (the gallery is a dev tool) must ship."""
        main = presets()["Linux"][0]
        found = set()
        for script in (ROOT / "godot3d" / "scripts").rglob("*.gd"):
            if "gallery" in script.parts:
                continue
            for path in re.findall(r'"res://([^"]+\.(?:json|txt|cfg|csv))"', script.read_text()):
                found.add(path)
        self.assertGreaterEqual(found, {"assets/audio/sfx/sfx_manifest.json", "assets/world/props_atlas.json"})
        for path in found:
            self.assertTrue((ROOT / "godot3d" / path).is_file(), path)
            self.assertTrue(ships(path, main), f"the game reads res://{path} but the presets leave it out")


class Version(unittest.TestCase):
    def test_project_version_is_the_cargo_workspace_version(self):
        self.assertRegex(project_version(), r"^\d+\.\d+\.\d+$")
        self.assertEqual(project_version(), cargo_workspace_version())

    def test_server_takes_the_workspace_version_and_the_core_crates_keep_theirs(self):
        server = tomllib.loads((ROOT / "crates/server/Cargo.toml").read_text())["package"]
        self.assertEqual(server.get("version"), {"workspace": True})
        # D4: P5 never touches crates/core or crates/data; render-shell stays with them.
        for crate in ["core", "data", "render-shell"]:
            package = tomllib.loads((ROOT / "crates" / crate / "Cargo.toml").read_text())["package"]
            self.assertEqual(package.get("version"), "0.1.0", crate)

    def test_cargo_lock_carries_the_server_version(self):
        lock = tomllib.loads((ROOT / "Cargo.lock").read_text())
        server = [p for p in lock["package"] if p["name"] == "rts-server"]
        self.assertEqual([p["version"] for p in server], [cargo_workspace_version()])

    def test_build_output_is_ignored(self):
        self.assertIn("/build/", (ROOT / ".gitignore").read_text().splitlines())


class Refusals(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.home = pathlib.Path(self.tmp.name) / "home"
        self.home.mkdir()

    def tearDown(self):
        self.tmp.cleanup()

    def templates(self, *names):
        d = self.home / ".local/share/godot/export_templates" / ENGINE
        d.mkdir(parents=True, exist_ok=True)
        for n in names:
            (d / n).write_bytes(b"")
        return d

    def fake_rustup(self, *targets) -> str:
        """A PATH whose rustup lists only `targets` (and nothing else from a real toolchain shadows it)."""
        bin_dir = pathlib.Path(self.tmp.name) / "bin"
        bin_dir.mkdir(exist_ok=True)
        write_exec(bin_dir / "rustup", "#!/bin/sh\nprintf '%s\\n' " + " ".join(targets) + "\n")
        return f"{bin_dir}:{os.environ['PATH']}"

    def test_unknown_mode_prints_usage(self):
        r = run_package("mac", env=bare_env(self.home))
        self.assertEqual(r.returncode, 2, r.stderr)
        self.assertIn("usage: tools/release/package.sh [linux|windows|all]", r.stderr)

    def test_linux_refuses_without_export_templates(self):
        r = run_package("linux", env=bare_env(self.home))
        self.assertEqual(r.returncode, 1, r.stdout + r.stderr)
        self.assertIn("Godot export templates for " + ENGINE + " are not installed", r.stderr)
        self.assertIn(str(self.home / ".local/share/godot/export_templates" / ENGINE / "linux_release.x86_64"), r.stderr)
        self.assertNotIn("Compiling", r.stdout + r.stderr, "nothing is built before the checks pass")

    def test_templates_follow_xdg_data_home(self):
        xdg = pathlib.Path(self.tmp.name) / "xdg"
        r = run_package("linux", env=bare_env(self.home, XDG_DATA_HOME=str(xdg)))
        self.assertEqual(r.returncode, 1)
        self.assertIn(str(xdg / "godot/export_templates" / ENGINE / "linux_release.x86_64"), r.stderr)

    def test_windows_refuses_without_its_template(self):
        self.templates("linux_release.x86_64")
        r = run_package("windows", env=bare_env(self.home))
        self.assertEqual(r.returncode, 1)
        self.assertIn("windows_release_x86_64.exe", r.stderr)

    def test_all_checks_every_platform_before_building(self):
        self.templates("linux_release.x86_64")
        r = run_package("all", env=bare_env(self.home))
        self.assertEqual(r.returncode, 1)
        self.assertIn("windows_release_x86_64.exe", r.stderr)
        self.assertNotIn("Compiling", r.stdout + r.stderr)

    def test_windows_refuses_without_the_rust_target(self):
        self.templates("windows_release_x86_64.exe")
        r = run_package("windows", env=bare_env(self.home, PATH=self.fake_rustup("x86_64-unknown-linux-gnu")))
        self.assertEqual(r.returncode, 1, r.stderr)
        self.assertIn("Rust target x86_64-pc-windows-gnu is not installed", r.stderr)
        self.assertIn("rustup target add x86_64-pc-windows-gnu", r.stderr)

    def test_windows_refuses_without_the_mingw_linker(self):
        self.templates("windows_release_x86_64.exe")
        env = bare_env(self.home, PATH=self.fake_rustup("x86_64-pc-windows-gnu"),
                       CARGO_TARGET_X86_64_PC_WINDOWS_GNU_LINKER="no-such-mingw-gcc-for-test")
        r = run_package("windows", env=env)
        self.assertEqual(r.returncode, 1, r.stderr)
        self.assertIn("MinGW linker no-such-mingw-gcc-for-test was not found", r.stderr)


class Pipeline(unittest.TestCase):
    """package.sh end to end with a fake Godot (writes an executable stub and a pack) and a fake bridge."""

    def setUp(self):
        import pck
        self.pck = pck
        self.tmp = tempfile.TemporaryDirectory()
        t = pathlib.Path(self.tmp.name)
        self.home = t / "home"
        tdir = self.home / ".local/share/godot/export_templates" / ENGINE
        tdir.mkdir(parents=True)
        for n in ["linux_release.x86_64", "windows_release_x86_64.exe"]:
            (tdir / n).write_bytes(b"")
        self.build = t / "build"
        self.version = project_version()
        self.bridge = write_exec(t / "godot-bridge", f"#!/bin/sh\n[ \"$1\" = --version ] && echo {self.version}\n")
        self.bridge_exe = t / "godot-bridge.exe"
        self.bridge_exe.write_bytes(b"MZ fake")
        self.pack_paths = t / "pack_paths.txt"
        self.pack_paths.write_text("\n".join(GOOD_PACK) + "\n")
        self.godot = write_exec(t / "godot", f"""#!/bin/sh
# fake Godot: --export-release <preset> <out> writes <out> and the pack beside it, and logs its arguments
echo "$@" >> "{t}/godot_args.txt"
while [ $# -gt 0 ]; do
  if [ "$1" = --export-release ]; then out="$3"; break; fi
  shift
done
printf 'engine' > "$out"
exec python3 "{HERE / 'pck.py'}" write "${{out%.*}}.pck" "{self.pack_paths}"
""")

    def tearDown(self):
        self.tmp.cleanup()

    def env(self, **extra):
        return bare_env(self.home, GODOT=str(self.godot), BRIDGE=str(self.bridge), BRIDGE_EXE=str(self.bridge_exe),
                        BUILD_DIR=str(self.build), **extra)

    def test_linux_package_layout(self):
        r = run_package("linux", env=self.env())
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        name = f"ascension-{self.version}-linux-x86_64"
        archive = self.build / f"{name}.tar.gz"
        self.assertTrue(archive.is_file(), r.stdout)
        with tarfile.open(archive) as tar:
            members = {m.name: m for m in tar.getmembers()}
            for f in ["ascension.x86_64", "ascension.pck", "godot-bridge", "VERSION"]:
                self.assertIn(f"{name}/{f}", members)
            self.assertTrue(members[f"{name}/godot-bridge"].mode & stat.S_IXUSR, "the bridge keeps its exec bit")
            self.assertTrue(members[f"{name}/ascension.x86_64"].mode & stat.S_IXUSR)
            self.assertEqual(tar.extractfile(f"{name}/VERSION").read().decode(), self.version + "\n")
            licences = [n for n in members if n.startswith(f"{name}/licenses/")]
            self.assertIn(f"{name}/licenses/FONT-LICENSES.md", licences)
            self.assertIn(f"{name}/licenses/kenney-city-kit-industrial.txt", licences)
            self.assertFalse(any("stub_bridge" in n or "/tests/" in n for n in members))
        args = (pathlib.Path(self.tmp.name) / "godot_args.txt").read_text()
        self.assertIn("--headless", args)
        self.assertIn('--export-release Linux', args)
        self.assertIn(f"--path {self.build}/.stage/godot3d", args, "the export runs on a staged copy")
        self.assertNotIn(f"--path {ROOT}/godot3d ", args)
        self.assertFalse((self.build / ".stage").exists(), "the stage is removed afterwards")

    def test_a_pack_with_a_dev_file_is_refused(self):
        self.pack_paths.write_text("\n".join(GOOD_PACK + ["tests/fixtures/stub_bridge.sh"]) + "\n")
        r = run_package("linux", env=self.env())
        self.assertEqual(r.returncode, 1, r.stdout + r.stderr)
        self.assertIn("tests/fixtures/stub_bridge.sh", r.stderr)
        self.assertFalse(list(self.build.glob("*.tar.gz")), "no archive is written")

    def test_a_bridge_of_another_version_is_refused(self):
        write_exec(self.bridge, "#!/bin/sh\necho 0.0.1\n")
        r = run_package("linux", env=self.env())
        self.assertEqual(r.returncode, 1)
        self.assertIn(f"godot-bridge reports version 0.0.1, the project is {self.version}", r.stderr)

    def test_windows_package_layout(self):
        r = run_package("windows", env=self.env())
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        name = f"ascension-{self.version}-windows-x86_64"
        with zipfile.ZipFile(self.build / f"{name}.zip") as z:
            names = set(z.namelist())
        for f in ["ascension.exe", "ascension.pck", "godot-bridge.exe", "VERSION"]:
            self.assertIn(f"{name}/{f}", names)
        self.assertIn('--export-release Windows Desktop', (pathlib.Path(self.tmp.name) / "godot_args.txt").read_text())


# A pack as Godot 4.7 writes it for this project (paths relative to res://), trimmed to what pck.check needs.
GOOD_PACK = [
    "project.binary", ".godot/global_script_class_cache.cfg", ".godot/uid_cache.bin",
    ".godot/exported/133200997/export-3070c538c03ee49b7677ff960a3f5195-main.scn", "main.tscn.remap",
    "scripts/earthfront_3d.gdc", "scripts/earthfront_3d.gd.remap", "scripts/bridge_launcher.gdc",
    "scripts/ui/title_screen.gdc", "assets/audio/sfx/sfx_manifest.json", "assets/world/props_atlas.json",
    ".godot/imported/Rajdhani-SemiBold.ttf-0123.fontdata", "assets/fonts/Rajdhani-SemiBold.ttf.import",
    "assets/fonts/Rajdhani-Bold.ttf.import", "assets/fonts/IBMPlexSans-VF.ttf.import",
    "assets/fonts/IBMPlexMono-Regular.ttf.import", "assets/fonts/IBMPlexMono-Medium.ttf.import",
]


class Pack(unittest.TestCase):
    def setUp(self):
        import pck
        self.pck = pck
        self.tmp = tempfile.TemporaryDirectory()
        self.path = pathlib.Path(self.tmp.name) / "t.pck"

    def tearDown(self):
        self.tmp.cleanup()

    def test_reads_back_the_paths_it_wrote_in_both_layouts(self):
        for fmt in (2, 3):
            self.pck.write_pack(self.path, GOOD_PACK, fmt=fmt)
            self.assertEqual(self.pck.read_paths(self.path), GOOD_PACK, f"format {fmt}")

    def test_a_clean_pack_passes(self):
        self.assertEqual(self.pck.problems(GOOD_PACK), [])

    def test_dev_files_are_named(self):
        dev = ["tests/fixtures/stub_bridge.sh", "tests/test_title.gdc", "tools/generate_assets.py", "runtime/snapshot.json",
               "scripts/gallery/capture.gdc", "art/earthfront_art_direction_v1.png.import", "README.md",
               "scripts/earthfront_3d.gd.uid", "docs/release/itch-checklist.md", ".superpowers/x.md",
               "settings.cfg", "replays/kestrel-1.rpl", "user/kestrel-2.rpl"]
        got = self.pck.problems(GOOD_PACK + dev)
        for d in dev:
            self.assertTrue(any(d in p for p in got), f"{d} not flagged in {got}")

    def test_missing_game_files_are_named(self):
        got = self.pck.problems([p for p in GOOD_PACK if "sfx_manifest" not in p and p != "project.binary"
                                 and p != "assets/fonts/IBMPlexSans-VF.ttf.import"])
        self.assertTrue(any("sfx_manifest.json" in p for p in got), got)
        self.assertTrue(any("IBMPlexSans-VF.ttf" in p for p in got), got)
        self.assertTrue(any("project.binary" in p for p in got), got)

    def test_not_a_pack(self):
        self.path.write_bytes(b"nope")
        with self.assertRaises(ValueError):
            self.pck.read_paths(self.path)


if __name__ == "__main__":
    unittest.main()
