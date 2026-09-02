#!/usr/bin/env python3
"""Exercises blast-io.py against a throwaway $HOME: the state file round
trip, the installer, and every refusal that guards them."""
import json
import os
import shutil
import stat
import subprocess
import sys
import tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
HELPER = os.path.join(ROOT, "blast-io.py")
FAILED = []


def run(args, home, env=None):
    e = {"PATH": os.environ.get("PATH", ""), "HOME": home}
    e.update(env or {})
    return subprocess.run([sys.executable, HELPER] + args, env=e, capture_output=True)


def check(name, cond, detail=""):
    print(("ok   " if cond else "FAIL ") + name + (("  " + detail) if detail and not cond else ""))
    if not cond:
        FAILED.append(name)


def fresh_home():
    home = tempfile.mkdtemp(prefix="blast-home-")
    os.chmod(home, 0o700)
    return home


def test_state_roundtrip():
    home = fresh_home()
    try:
        r = run(["read"], home)
        check("read: absent state is empty and ok", r.returncode == 0 and r.stdout == b"")
        state = json.dumps({"version": 1, "best": {"score": 42}})
        r = run(["write"], home, {"BLAST_STATE": state})
        check("write: creates the state file", r.returncode == 0, r.stderr.decode())
        path = os.path.join(home, ".local", "state", "blast", "blast.json")
        st = os.lstat(path)
        check("write: file is 0600 regular", stat.S_ISREG(st.st_mode) and stat.S_IMODE(st.st_mode) == 0o600)
        dst = os.lstat(os.path.dirname(path))
        check("write: directory is 0700", stat.S_IMODE(dst.st_mode) == 0o700)
        r = run(["read"], home)
        check("read: returns what was written", r.returncode == 0 and r.stdout.decode() == state)
        leftovers = [f for f in os.listdir(os.path.dirname(path)) if f.endswith(".tmp")]
        check("write: no temp files left behind", leftovers == [])
        r = run(["write"], home, {"BLAST_STATE": "not json"})
        check("write: refuses non-JSON with exit 3", r.returncode == 3)
        r = run(["write"], home, {"BLAST_STATE": json.dumps({"x": "y" * 130000})})
        check("write: refuses oversized state with exit 3", r.returncode == 3)
        r = run(["read"], home)
        check("write: refused writes left the file intact", r.stdout.decode() == state)
    finally:
        shutil.rmtree(home)


def test_state_refusals():
    home = fresh_home()
    try:
        sdir = os.path.join(home, ".local", "state", "blast")
        os.makedirs(sdir, 0o700)
        victim = os.path.join(home, "victim")
        with open(victim, "w") as f:
            f.write("precious")
        os.symlink(victim, os.path.join(sdir, "blast.json"))
        r = run(["write"], home, {"BLAST_STATE": "{}"})
        check("write: refuses a symlink destination", r.returncode == 1 and b"refusing" in r.stderr, r.stderr.decode())
        with open(victim) as f:
            check("write: symlink target untouched", f.read() == "precious")
        r = run(["read"], home)
        check("read: refuses a symlink state file", r.returncode == 1, r.stderr.decode())
        os.unlink(os.path.join(sdir, "blast.json"))
        with open(os.path.join(sdir, "blast.json"), "w") as f:
            f.write("{}" + " " * 300000)
        r = run(["read"], home)
        check("read: refuses an oversized state file", r.returncode == 1 and b"large" in r.stderr, r.stderr.decode())
        os.unlink(os.path.join(sdir, "blast.json"))
        shutil.rmtree(sdir)
        os.symlink(home, sdir)
        r = run(["write"], home, {"BLAST_STATE": "{}"})
        check("write: refuses a symlinked state directory", r.returncode == 1, r.stderr.decode())
        check("write: symlinked directory target untouched", not os.path.exists(os.path.join(home, "blast.json")))
        r = run(["read"], home)
        check("read: refuses a symlinked state directory", r.returncode == 1, r.stderr.decode())
    finally:
        shutil.rmtree(home)


def test_install():
    home = fresh_home()
    try:
        r = run(["install"], home)
        check("install: succeeds into an empty home", r.returncode == 0, r.stderr.decode())
        desktop = os.path.join(home, ".local", "share", "applications", "Blast.desktop")
        icon = os.path.join(home, ".local", "share", "icons", "hicolor", "scalable", "apps", "blast.svg")
        with open(os.path.join(ROOT, "Blast.desktop"), "rb") as f:
            want_desktop = f.read()
        with open(os.path.join(ROOT, "assets", "icon.svg"), "rb") as f:
            want_icon = f.read()
        check("install: desktop entry matches the source", os.path.isfile(desktop) and open(desktop, "rb").read() == want_desktop)
        check("install: icon matches the source", os.path.isfile(icon) and open(icon, "rb").read() == want_icon)
        check("install: files are 0644", stat.S_IMODE(os.lstat(desktop).st_mode) == 0o644 and stat.S_IMODE(os.lstat(icon).st_mode) == 0o644)
        check("install: created directories are 0755", stat.S_IMODE(os.lstat(os.path.dirname(desktop)).st_mode) == 0o755)
        check("install: prints the two published paths", r.stdout.count(b"\n") == 2)
        r = run(["install"], home)
        check("install: rerun is a no-op success", r.returncode == 0 and open(desktop, "rb").read() == want_desktop)
        leftovers = [f for f in os.listdir(os.path.dirname(desktop)) if f.endswith(".tmp")]
        check("install: no temp files left behind", leftovers == [])

        # A symlink where the desktop entry goes: refused, target untouched.
        os.unlink(desktop)
        victim = os.path.join(home, "victim.desktop")
        with open(victim, "w") as f:
            f.write("precious")
        os.symlink(victim, desktop)
        r = run(["install"], home)
        check("install: refuses a symlink destination", r.returncode == 1 and b"refusing" in r.stderr, r.stderr.decode())
        check("install: symlink target untouched", open(victim).read() == "precious")
        check("install: symlink itself untouched", os.path.islink(desktop))
        os.unlink(desktop)

        # A symlink as a directory component: refused.
        apps = os.path.dirname(desktop)
        os.rmdir(apps)
        elsewhere = tempfile.mkdtemp(prefix="blast-elsewhere-")
        try:
            os.symlink(elsewhere, apps)
            r = run(["install"], home)
            check("install: refuses a symlinked directory component", r.returncode == 1 and b"untrusted" in r.stderr, r.stderr.decode())
            check("install: nothing written through the symlink", os.listdir(elsewhere) == [])
        finally:
            shutil.rmtree(elsewhere)
        os.unlink(apps)

        # A plain file where a directory belongs: refused.
        with open(apps, "w") as f:
            f.write("not a dir")
        r = run(["install"], home)
        check("install: refuses a file where a directory belongs", r.returncode == 1, r.stderr.decode())
    finally:
        shutil.rmtree(home)


def test_misc():
    home = fresh_home()
    try:
        r = run(["bogus"], home)
        check("usage: unknown command exits 3", r.returncode == 3)
        r = run(["request", "GET", "http://example.com/v1/leaderboard"], home)
        check("request: refuses plain http to a remote host", r.returncode == 3 and b"https" in r.stderr)
        r = run(["request", "PUT", "https://example.com/"], home)
        check("request: refuses methods outside GET/POST/DELETE", r.returncode == 3)
        r = run(["read"], "relative/home")
        check("read: refuses a relative HOME", r.returncode == 1)
    finally:
        shutil.rmtree(home)


if __name__ == "__main__":
    test_state_roundtrip()
    test_state_refusals()
    test_install()
    test_misc()
    if FAILED:
        print("\n%d failed" % len(FAILED))
        sys.exit(1)
    print("\nall passed")
