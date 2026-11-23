#!/usr/bin/env python3
"""Merge one QA run's findings into findings.json and REPORT.md.

  python3 qa/report.py <outdir> [--previous <old findings.json>] [--known qa/known-issues.json]

Inputs in <outdir>: explore-findings.jsonl (explore.lua) and layout.jsonl (lint.py).
Layout findings that repeat on several pages are grouped into one finding with a page list.
Findings listed in known-issues.json (by id, with a reason) are kept but marked "known".
With --previous, each finding is marked new / still, and earlier ones that are gone are
listed as fixed.

Exit code: 1 when there is a new finding of high or medium severity that isn't known, else 0.
"""
import argparse, hashlib, json, os, re, sys

SEV_ORDER = {"high": 0, "medium": 1, "low": 2}


def load_jsonl(path):
    if not os.path.exists(path):
        return []
    with open(path) as fh:
        return [json.loads(l) for l in fh if l.strip()]


def group_layout(items):
    groups = {}
    for f in items:
        # digits out of the key: clock times, dates and counts change every run
        key = re.sub(r"\d+", "#", f["rule"] + "|" + f["message"] + "|" + str(f.get("text") or ""))
        g = groups.get(key)
        if not g:
            g = {
                "id": "L-" + hashlib.sha1(key.encode()).hexdigest()[:8],
                "kind": "layout", "rule": f["rule"], "severity": f["severity"],
                "message": f["message"], "pages": [], "at": f.get("at"), "text": f.get("text"),
            }
            if f.get("other_at"):
                g["other_at"] = f["other_at"]
            groups[key] = g
        if f["page"] not in g["pages"]:
            g["pages"].append(f["page"])
    out = list(groups.values())
    for g in out:
        g["count"] = len(g["pages"])
        # pages from the static scene first: those are the ones render.py can draw
        g["pages"].sort(key=lambda p: (p.startswith("explore--"), p))
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("outdir")
    ap.add_argument("--previous")
    ap.add_argument("--known")
    a = ap.parse_args()

    findings = load_jsonl(os.path.join(a.outdir, "explore-findings.jsonl"))
    for f in findings:
        f.setdefault("rule", f.get("kind"))
    findings += group_layout(load_jsonl(os.path.join(a.outdir, "layout.jsonl")))

    pics = os.path.join(a.outdir, "pictures")
    for f in findings:
        for page in f.get("pages", [])[:1]:
            png = os.path.join(pics, page + ".png")
            if os.path.exists(png):
                f["png"] = png

    known = {}
    if a.known and os.path.exists(a.known):
        with open(a.known) as fh:
            for k in json.load(fh):
                known[k["id"]] = k.get("reason", "")
    prev = {}
    if a.previous and os.path.exists(a.previous):
        with open(a.previous) as fh:
            for f in json.load(fh).get("findings", []):
                prev[f["id"]] = f

    for f in findings:
        if f["id"] in known:
            f["status"] = "known"
            f["known_reason"] = known[f["id"]]
        elif prev:
            f["status"] = "still" if f["id"] in prev else "new"
        else:
            f["status"] = "new"
    ids = {f["id"] for f in findings}
    fixed = [p for i, p in prev.items() if i not in ids and p.get("status") != "known"]

    findings.sort(key=lambda f: (f["status"] == "known", SEV_ORDER.get(f["severity"], 3), f["kind"], f["id"]))
    stats_line = ""
    sp = os.path.join(a.outdir, "explore-stats.txt")
    if os.path.exists(sp):
        stats_line = open(sp).read().strip()

    data = {"stats": stats_line, "findings": findings, "fixed": fixed}
    with open(os.path.join(a.outdir, "findings.json"), "w") as fh:
        json.dump(data, fh, indent=1)

    open_f = [f for f in findings if f["status"] != "known"]
    lines = ["# RUIN QA report", ""]
    if stats_line:
        lines += [stats_line, ""]
    counts = {s: sum(1 for f in open_f if f["severity"] == s) for s in ("high", "medium", "low")}
    lines += [f"Open: {counts['high']} high, {counts['medium']} medium, {counts['low']} low. "
              f"Known (accepted): {len(findings) - len(open_f)}. Fixed since last run: {len(fixed)}.", ""]
    if fixed:
        lines += ["## Fixed since last run", ""]
        lines += [f"- `{f['id']}` {f['message'][:140]}" for f in fixed]
        lines += [""]
    for sev in ("high", "medium", "low"):
        group = [f for f in open_f if f["severity"] == sev]
        if not group:
            continue
        lines += [f"## {sev.capitalize()}", ""]
        for f in group:
            msg = f["message"].split("\n")[0][:200]
            where = ", ".join((f.get("pages") or f.get("where") or [])[:4])
            lines.append(f"- `{f['id']}` **{f['rule']}** ({f['status']}, x{f.get('count', 1)}): {msg}")
            if where:
                lines.append(f"  - where: {where}")
            if f.get("png"):
                lines.append(f"  - picture: {f['png']}")
        lines.append("")
    with open(os.path.join(a.outdir, "REPORT.md"), "w") as fh:
        fh.write("\n".join(lines))

    bad = [f for f in open_f if f["status"] == "new" and f["severity"] in ("high", "medium")]
    print(f"report: {len(open_f)} open ({counts['high']} high, {counts['medium']} medium, {counts['low']} low), "
          f"{len(fixed)} fixed, {len(bad)} new high/medium", file=sys.stderr)
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
