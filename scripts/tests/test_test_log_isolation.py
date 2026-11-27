from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]


class TestLogIsolationTests(unittest.TestCase):
    def test_swift_test_logs_go_to_an_isolated_directory(self):
        script = (ROOT / "scripts/development/test.sh").read_text()
        self.assertIn('DICT_LOG_DIR="$log_dir"', script)
        self.assertIn("mktemp -d", script)
        self.assertIn("rm -rf", script)

    def test_task_delegates_swift_tests_to_development_script(self):
        taskfile = (ROOT / "Taskfile.yml").read_text()
        self.assertNotIn("swift test", taskfile)
        self.assertNotIn("xctest", taskfile)
        self.assertIn("scripts/development/test.sh", taskfile)


if __name__ == "__main__":
    unittest.main()
