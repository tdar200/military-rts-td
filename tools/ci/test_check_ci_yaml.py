import subprocess, sys, pathlib, unittest
HERE = pathlib.Path(__file__).parent
CI = HERE.parent.parent / ".github/workflows/ci.yml"

class CiYaml(unittest.TestCase):
    def test_workflow_has_the_three_jobs(self):
        import yaml
        jobs = yaml.safe_load(CI.read_text())["jobs"]
        self.assertTrue({"check", "godot", "python-tools"} <= set(jobs))
    def test_checker_accepts_the_workflow(self):
        r = subprocess.run([sys.executable, str(HERE / "check_ci_yaml.py"), str(CI)])
        self.assertEqual(r.returncode, 0)
    def test_checker_rejects_a_step_without_run_or_uses(self):
        bad = HERE / "_bad.yml"
        bad.write_text("jobs:\n  x:\n    runs-on: ubuntu-latest\n    steps:\n      - name: nothing\n")
        try:
            self.assertNotEqual(subprocess.run([sys.executable, str(HERE / "check_ci_yaml.py"), str(bad)]).returncode, 0)
        finally:
            bad.unlink()

    def _run(self, text):
        tmp = HERE / "_tmp.yml"
        tmp.write_text(text)
        try:
            return subprocess.run([sys.executable, str(HERE / "check_ci_yaml.py"), str(tmp)], capture_output=True).returncode
        finally:
            tmp.unlink()

    def test_checker_accepts_a_minimal_valid_workflow(self):
        self.assertEqual(self._run("jobs:\n  x:\n    runs-on: ubuntu-latest\n    steps:\n      - run: echo hi\n      - uses: actions/checkout@v4\n"), 0)

    def test_checker_rejects_a_job_without_runs_on_and_bad_yaml(self):
        self.assertNotEqual(self._run("jobs:\n  x:\n    steps:\n      - run: echo hi\n"), 0)
        self.assertNotEqual(self._run("jobs: [unclosed\n"), 0)


if __name__ == "__main__":
    unittest.main()
