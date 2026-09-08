#!/usr/bin/env python3
"""Exercise the real source-policy gate without mutating the checkout."""

from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parent.parent
# Deliberately pin the existing policy scope independently of the shell arrays.
TARGETS = (
    "GamaCore", "GamaPlugin", "GamaDraw", "GamaMacros", "GamaMacrosImpl",
    "gama", "GamaTUI", "GamaWASM", "GamaAppleUI", "GamaAppleShell",
    "GamaEmbed", "GamaEmbedABI", "GamaMLIR",
)


def scan(root):
    return subprocess.run(
        ["bash", str(root / "scripts/check-boundaries.sh"), "--source-policies-only"],
        capture_output=True, text=True, check=False, timeout=30,
    )


class BoundaryPathsTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="gama-boundary-paths-")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        (self.root / "scripts").mkdir()
        for name in ("check-boundaries.sh", "portable-global-state.py"):
            shutil.copy2(ROOT / "scripts" / name, self.root / "scripts" / name)
        (self.root / "Sources").mkdir()
        for source in (ROOT / "Sources").iterdir():
            (self.root / "Sources" / source.name).symlink_to(source)

    def assert_failure(self, diagnostic):
        result = scan(self.root)
        self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn(diagnostic, result.stderr)
        self.assertNotIn("OK — portable and platform-services source policies", result.stdout)

    def test_current_tree_passes(self):
        result = scan(ROOT)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("OK — portable and platform-services source policies", result.stdout)

    def test_each_missing_target_fails(self):
        for target in TARGETS:
            with self.subTest(target=target):
                path = self.root / "Sources" / target
                path.unlink()
                try:
                    self.assert_failure(f"error: boundary scan path is missing: Sources/{target}")
                finally:
                    path.symlink_to(ROOT / "Sources" / target)

    def test_file_cannot_replace_target_directory(self):
        for target in TARGETS:
            with self.subTest(target=target):
                path = self.root / "Sources" / target
                path.unlink()
                path.touch()
                try:
                    self.assert_failure(f"error: boundary scan path is not a directory: Sources/{target}")
                finally:
                    path.unlink()
                    path.symlink_to(ROOT / "Sources" / target)

    def test_directory_cannot_replace_target_file(self):
        # The inverse of the directory case: a same-named directory passes -e,
        # and the non-recursive grep that follows exits 2 on a directory, which
        # the `if` reads as no match — nested Swift would go unscanned.
        target = self.root / "Sources" / "GamaTUI"
        target.unlink()
        target.mkdir()
        shadow = target / "TerminalRescue.swift"
        shadow.mkdir()
        (shadow / "Nested.swift").write_text("let handler = sigaction(1, nil, nil)\n")
        try:
            self.assert_failure(
                "error: boundary scan path is not a regular file: Sources/GamaTUI/TerminalRescue.swift")
        finally:
            (shadow / "Nested.swift").unlink()
            shadow.rmdir()
            target.rmdir()
            target.symlink_to(ROOT / "Sources" / "GamaTUI")

    def test_existing_grep_policies_still_reject_violations(self):
        for target, source, diagnostic in (
            ("GamaCore", "let registry = ActionRegistry()", "process-global framework state detected"),
            ("GamaMacros", "import GamaPlatformServices", "a portable/framework target imported GamaPlatformServices"),
        ):
            with self.subTest(target=target):
                path = self.root / "Sources" / target
                path.unlink()
                path.mkdir()
                fixture = path / "Violation.swift"
                fixture.write_text(source + "\n")
                try:
                    self.assert_failure(diagnostic)
                finally:
                    fixture.unlink()
                    path.rmdir()
                    path.symlink_to(ROOT / "Sources" / target)


if __name__ == "__main__":
    unittest.main()
