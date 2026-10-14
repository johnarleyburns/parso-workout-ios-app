import os, sys, unittest
sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
import testflight_release_notes as t

PRS = {42: {"title": "Fix sync", "body": "x\n<!-- claude-issue:42 -->"},
       45: {"title": "HR zones", "body": "Closes #45 and relates to #46"}}
TITLES = {42: "Fix Watch sync", 45: "HR zones", 46: "Zone UI"}


class Notes(unittest.TestCase):
    def run_collect(self, commits):
        return t.collect(commits, PRS.get, lambda i: TITLES.get(i, "?"))

    def test_squash_merges_and_unrelated_commits(self):
        prs, issues = self.run_collect([
            {"sha": "a", "message": "Fix sync (#42)"},
            {"sha": "b", "message": "docs tweak"},
            {"sha": "c", "message": "HR zones (#45)"}])
        self.assertEqual(sorted(prs), [42, 45])
        self.assertEqual(sorted(issues), [42, 45, 46])

    def test_merge_commit_and_empty_range(self):
        _, issues = self.run_collect([{"sha": "a", "message": "Merge pull request #42 from x/y"}])
        self.assertEqual(list(issues), [42])
        prs, issues = self.run_collect([])
        self.assertIn("No tracked issues", t.build_notes("Cadence", 1, "abcdef123", prs, issues, "u"))

    def test_notes_format_and_rerun_determinism(self):
        _, issues = self.run_collect([{"sha": "a", "message": "Fix sync (#42)"}])
        a = t.build_notes("Cadence", 127, "a83f21c9", {}, issues, "u")
        self.assertIn("Cadence — Build 127", a)
        self.assertIn("- #42 — Fix Watch sync", a)
        self.assertTrue(a.endswith("GitHub commit: a83f21c"))
        self.assertEqual(a, t.build_notes("Cadence", 127, "a83f21c9", {}, issues, "u"))

    def test_truncation_links_changelog(self):
        issues = {i: "x" * 80 for i in range(1, 200)}
        n = t.build_notes("Cadence", 1, "abcdef123", {}, issues, "https://gh/compare")
        self.assertLessEqual(len(n), t.NOTES_LIMIT)
        self.assertIn("https://gh/compare", n)


if __name__ == "__main__":
    unittest.main()
