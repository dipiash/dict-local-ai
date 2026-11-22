#!/usr/bin/env python3
"""Check the index snapshot of changed files without rewriting the worktree or index."""
import os
import plistlib
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path


def git(*args):
    return subprocess.check_output(("git", *args))


def run(tool, args, cwd, **kwargs):
    executable = shutil.which(tool)
    if executable is None:
        raise SystemExit(f"Missing {tool}. See docs/development.md for hook setup.")
    subprocess.run([executable, *args], cwd=cwd, check=True, **kwargs)


def main():
    os.chdir(os.fsdecode(git("rev-parse", "--show-toplevel").rstrip(b"\n")))
    subprocess.run(["git", "diff", "--cached", "--check"], check=True)
    raw = git("diff", "--cached", "--name-only", "--diff-filter=ACMRT", "-z")
    files = [Path(os.fsdecode(name)) for name in raw.split(b"\0") if name]
    if not files:
        return

    with tempfile.TemporaryDirectory(prefix="dict-staged-") as temporary:
        root = Path(temporary)
        subprocess.run(["git", "checkout-index", "--all", f"--prefix={root}/"], check=True)
        for path in files:
            if (root / path).is_symlink() or not (root / path).is_file():
                raise SystemExit(f"Unsupported staged entry: {path}")
        swift = [str(p) for p in files if p.suffix == ".swift"]
        shell = [str(p) for p in files if p.suffix == ".sh"]
        biome = [
            str(p) for p in files
            if p.suffix in {".json", ".jsonc", ".yml", ".yaml", ".md"}
            and p.parts[:2] != ("Resources", "Licenses")
        ]
        python = [str(p) for p in files if p.suffix == ".py"]
        workflows = [
            str(p) for p in files
            if p.parent == Path(".github/workflows") and p.suffix in {".yml", ".yaml"}
        ]
        if swift:
            run("swift", ["format", "lint", "--strict", "--", *swift], root)
            env = {**os.environ, "SCRIPT_INPUT_FILE_COUNT": str(len(swift))}
            env.update({f"SCRIPT_INPUT_FILE_{i}": str(root / p) for i, p in enumerate(swift)})
            run("swiftlint", ["lint", "--strict", "--use-script-input-files",
                              "--config", ".swiftlint.yml"], root, env=env)
        if shell:
            run("shellcheck", ["--external-sources", "--shell=bash", "--", *shell], root)
        if biome:
            run("biome", ["format", "--", *biome], root)
        if python:
            subprocess.run([sys.executable, "-m", "py_compile", "--", *python], cwd=root, check=True)
        for path in files:
            if path.suffix in {".plist", ".entitlements"}:
                with (root / path).open("rb") as file:
                    plistlib.load(file)
        if workflows:
            run("actionlint", ["-no-color", *workflows], root)


if __name__ == "__main__":
    try:
        main()
    except subprocess.CalledProcessError as failure:
        sys.exit(f"Staged check failed (exit {failure.returncode}).")
