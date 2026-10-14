"""Pure release-note generation for TestFlight "What to Test".

Network calls (GitHub, App Store Connect) are injected by the caller so the
logic is testable offline: see scripts/tests/test_testflight_release_notes.py.
"""
import re

MARKER = re.compile(r"<!--\s*claude-issue:(\d+)\s*-->")
KEYWORD = re.compile(
    r"\b(?:fix(?:es|ed)?|close[sd]?|resolve[sd]?|relates?\s+to|refs?)\s+#(\d+)", re.I)
SQUASH_PR = re.compile(r"\(#(\d+)\)\s*$")
MERGE_PR = re.compile(r"^Merge pull request #(\d+)\b")
NOTES_LIMIT = 4000  # App Store Connect whatsNew limit


def issue_numbers(text):
    """Issue numbers referenced by marker or closing keyword, in order, unique."""
    found = []
    for rx in (MARKER, KEYWORD):
        for m in rx.finditer(text or ""):
            n = int(m.group(1))
            if n not in found:
                found.append(n)
    return found


def pr_number(message):
    """PR number from a squash ("title (#12)") or merge-commit subject."""
    subject = (message or "").splitlines()[0] if message else ""
    m = SQUASH_PR.search(subject) or MERGE_PR.match(subject)
    return int(m.group(1)) if m else None


def collect(commits, pr_lookup, issue_title):
    """Map commits in the build range to PRs and issues.

    commits: [{"sha", "message"}]; pr_lookup(n) -> {"title", "body"} or None;
    issue_title(n) -> str. Unrelated commits (no PR) are ignored.
    """
    prs, issues = {}, {}
    for c in commits:
        n = pr_number(c["message"])
        if n is None or n in prs:
            continue
        pr = pr_lookup(n) or {"title": "", "body": ""}
        prs[n] = pr["title"]
        for i in issue_numbers(pr["body"]) + issue_numbers(c["message"]):
            issues.setdefault(i, issue_title(i))
    return prs, issues


def build_notes(app, build, sha, prs, issues, compare_url, limit=NOTES_LIMIT):
    head = f"{app} — Build {build}\n\nIncluded changes:\n"
    foot = f"\nGitHub commit: {sha[:7]}"
    lines = [f"- #{n} — {t}" for n, t in sorted(issues.items())]
    lines += [f"- PR #{n} — {t}" for n, t in sorted(prs.items())
              if not any(f"#{n} " in l for l in lines)] if not issues else []
    if not lines:
        lines = ["- No tracked issues in this build."]
    body = "\n".join(lines)
    if len(head + body + foot) > limit:
        keep, tail = [], f"\n…and more. Full changelog: {compare_url}"
        for l in lines:
            if len(head + "\n".join(keep + [l]) + tail + foot) > limit:
                break
            keep.append(l)
        body = "\n".join(keep) + tail
    return head + body + foot
