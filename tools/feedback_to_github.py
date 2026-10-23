#!/usr/bin/env python3
"""Post RUIN feedback from the game to GitHub issues.

Players send feedback from Settings > Feedback in the RUIN app. It reaches the
org admin's RUIN inside the game and is saved in the admin's account-wide
SavedVariables file:

    <WoW folder>/WTF/Account/<ACCOUNT>/SavedVariables/RUIN_Core.lua

Run this on the admin's computer (after logging out, or after /reload, so the
file is up to date). It creates one GitHub issue, labeled "feedback", for
each message it hasn't posted before, and remembers what it posted in
feedback_posted.json next to this script.

    python3 feedback_to_github.py --file ".../SavedVariables/RUIN_Core.lua"
    python3 feedback_to_github.py --find "<WoW folder>"     # look for the file
    python3 feedback_to_github.py --file ... --dry-run      # just show them

GitHub access, either:
  * the GitHub CLI, logged in once with `gh auth login`, or
  * a token in GITHUB_TOKEN (a fine-grained token with "Issues: read and
    write" on the repository).

No third-party packages needed (Python 3.8+).
"""
import argparse
import glob
import json
import os
import shutil
import subprocess
import sys
import urllib.request

REPO = "10kDevils/RUIN_Suite"
LABEL = "feedback"
HERE = os.path.dirname(os.path.abspath(__file__))
POSTED = os.path.join(HERE, "feedback_posted.json")


# --- a small reader for WoW SavedVariables (a Lua table literal) ------------
class LuaReader:
    def __init__(self, text):
        self.s, self.i = text, 0

    def ws(self):
        s = self.s
        while self.i < len(s):
            c = s[self.i]
            if c in " \t\r\n":
                self.i += 1
            elif s.startswith("--", self.i):
                if s.startswith("--[[", self.i):
                    end = s.find("]]", self.i)
                    self.i = len(s) if end < 0 else end + 2
                else:
                    end = s.find("\n", self.i)
                    self.i = len(s) if end < 0 else end + 1
            else:
                break

    def value(self):
        self.ws()
        s, c = self.s, self.s[self.i]
        if c == "{":
            return self.table()
        if c in "\"'":
            return self.string()
        for word, val in (("true", True), ("false", False), ("nil", None)):
            if s.startswith(word, self.i):
                self.i += len(word)
                return val
        j = self.i
        while j < len(s) and (s[j].isalnum() or s[j] in "+-.xX"):
            j += 1
        num = s[self.i:j]
        self.i = j
        try:
            return int(num, 0)
        except ValueError:
            return float(num)

    def string(self):
        q = self.s[self.i]
        self.i += 1
        out = []
        s = self.s
        while s[self.i] != q:
            c = s[self.i]
            if c == "\\":
                self.i += 1
                e = s[self.i]
                if e.isdigit():
                    j = self.i
                    while j < len(s) and j < self.i + 3 and s[j].isdigit():
                        j += 1
                    out.append(chr(int(s[self.i:j])))
                    self.i = j
                    continue
                out.append({"n": "\n", "t": "\t", "r": "\r", "\\": "\\", '"': '"', "'": "'", "\n": "\n"}.get(e, e))
                self.i += 1
            else:
                out.append(c)
                self.i += 1
        self.i += 1
        raw = "".join(out)
        try:
            return raw.encode("latin-1").decode("utf-8")
        except (UnicodeEncodeError, UnicodeDecodeError):
            return raw

    def table(self):
        self.i += 1
        result, n = {}, 1
        while True:
            self.ws()
            if self.s[self.i] == "}":
                self.i += 1
                break
            if self.s[self.i] == "[":
                self.i += 1
                key = self.value()
                self.ws()
                self.i += 1          # ]
                self.ws()
                self.i += 1          # =
                result[key] = self.value()
            else:
                save = self.i
                j = self.i
                while j < len(self.s) and (self.s[j].isalnum() or self.s[j] == "_"):
                    j += 1
                k = j
                while k < len(self.s) and self.s[k] in " \t\r\n":
                    k += 1
                if j > self.i and k < len(self.s) and self.s[k] == "=" and self.s[k + 1:k + 2] != "=":
                    key = self.s[self.i:j]
                    self.i = k + 1
                    result[key] = self.value()
                else:
                    self.i = save
                    result[n] = self.value()
                    n += 1
            self.ws()
            if self.s[self.i] in ",;":
                self.i += 1
        return result


def read_db(path):
    with open(path, "r", encoding="utf-8", errors="surrogateescape") as f:
        text = f.read()
    start = text.find("RUIN_DB")
    if start < 0:
        sys.exit("No RUIN_DB in %s: is this RUIN_Core.lua from SavedVariables?" % path)
    brace = text.find("{", start)
    return LuaReader(text[brace:]).value()


def as_list(t):
    if isinstance(t, dict):
        return [t[k] for k in sorted(k for k in t if isinstance(k, int))]
    return t or []


# --- GitHub -----------------------------------------------------------------
def create_issue(repo, title, body, labels):
    token = os.environ.get("GITHUB_TOKEN") or os.environ.get("GH_TOKEN")
    if token:
        req = urllib.request.Request(
            "https://api.github.com/repos/%s/issues" % repo,
            data=json.dumps({"title": title, "body": body, "labels": labels}).encode(),
            headers={"Authorization": "Bearer " + token, "Accept": "application/vnd.github+json",
                     "User-Agent": "ruin-feedback"}, method="POST")
        with urllib.request.urlopen(req) as r:
            return json.load(r)["html_url"]
    if not shutil.which("gh"):
        sys.exit("Install the GitHub CLI and run `gh auth login`, or set GITHUB_TOKEN.")
    cmd = ["gh", "issue", "create", "--repo", repo, "--title", title, "--body", body]
    for lab in labels:
        cmd += ["--label", lab]
    out = subprocess.run(cmd, capture_output=True, text=True)
    if out.returncode != 0:
        raise RuntimeError(out.stderr.strip())
    return out.stdout.strip()


def find_files(root):
    pattern = os.path.join(root, "**", "SavedVariables", "RUIN_Core.lua")
    return [p for p in glob.glob(pattern, recursive=True)]


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--file", help="the RUIN_Core.lua SavedVariables file of the org admin's account")
    ap.add_argument("--find", metavar="WOW_FOLDER", help="search this folder for RUIN_Core.lua files")
    ap.add_argument("--repo", default=REPO)
    ap.add_argument("--dry-run", action="store_true", help="show what would be posted, post nothing")
    a = ap.parse_args()

    if a.find:
        files = find_files(a.find)
        for f in files:
            print(f)
        if not files:
            print("No RUIN_Core.lua under", a.find)
        return
    if not a.file:
        ap.error("give --file (or --find to locate it)")

    db = read_db(a.file)
    inbox = as_list((db.get("feedback") or {}).get("inbox"))
    posted = {}
    if os.path.exists(POSTED):
        with open(POSTED) as f:
            posted = json.load(f)

    # skip what was posted already (by this script, or marked posted in the game)
    new = [e for e in inbox if isinstance(e, dict) and e.get("id") and e["id"] not in posted and not e.get("posted")]
    if not new:
        print("No new feedback (%d in the inbox, all posted)." % len(inbox))
        return
    for e in new:
        text = e.get("text", "")
        first = " ".join(text.split())[:60]
        title = "[%s] %s" % (e.get("cat", "Other"), first)
        body = "%s\n\n---\nFrom **%s**%s, sent in-game.\nRUIN Core %s on %s." % (
            text, e.get("by", "?"), (" (%s)" % e["gu"]) if e.get("gu") else "", e.get("v", "?"), e.get("cl", "?"))
        if a.dry_run:
            print("--- would post:", title)
            print(body, "\n")
            continue
        try:
            url = create_issue(a.repo, title, body, [LABEL])
        except Exception as err:            # the label may be missing: try without it
            print("  (retrying without the label: %s)" % err)
            url = create_issue(a.repo, title, body, [])
        posted[e["id"]] = url
        with open(POSTED, "w") as f:
            json.dump(posted, f, indent=1)
        print("Posted:", url)
    if not a.dry_run:
        print("Done. In the game, press Mark all posted on Settings > Feedback to tidy the inbox.")


if __name__ == "__main__":
    main()
