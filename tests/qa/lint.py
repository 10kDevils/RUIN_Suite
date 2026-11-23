#!/usr/bin/env python3
"""Layout linter for RUIN's simulated UI dumps (tests/render/*.json).

Reads every <page>.json in a directory (written by render/render.lua or qa/explore.lua),
looks for visual problems and writes findings as JSON lines on stdout / to --out.

Rules (id -> meaning)
  offscreen         a visible region sits partly or fully outside the 1600x900 screen
  text-overflow     one-line text is wider than its box and not clipped away on purpose
  text-clipped      wrapped text needs more height than its box has
  text-overlap      two pieces of text draw over each other
  low-contrast      text colour is too close to what is drawn behind it (ratio < 2.5)
  bad-text          visible text that looks like a bug: nil, NaN, %s, unmatched |c, table:, etc.
  clipped-away      a visible control/text lies entirely outside its scroll/clip area
  empty-page        a page dump with almost nothing on it
  tiny-text         text drawn smaller than 8px

Fonts are stand-ins, so width checks carry a tolerance. Treat "low" severity as hints.
"""
import json, os, re, sys, glob, argparse, hashlib

SCREEN_W, SCREEN_H = 1600, 900


def plain(s):
    s = str(s or "")
    s = re.sub(r"\|c[0-9a-fA-F]{8}", "", s)
    s = s.replace("|r", "")
    s = re.sub(r"\|H.*?\|h(.*?)\|h", r"\1", s)
    s = re.sub(r"\|T.*?\|t", "WW", s)
    s = re.sub(r"\|A.*?\|a", "WW", s)
    return s.replace("|n", "\n")


def line_width(line, size):
    w = 0.0
    for ch in line:
        b = ord(ch)
        if b >= 128:
            w += 0.25 if b < 0x2E80 else 1.0
        elif re.match(r"[A-Z0-9MW@%]", ch):
            w += 0.66
        elif re.match(r"[iljI.,:;'!|]", ch):
            w += 0.30
        elif ch == " ":
            w += 0.30
        else:
            w += 0.54
    return w * size


def text_extent(r):
    """(width, height, lines) the text really needs inside r."""
    size = r.get("size") or 12
    s = plain(r.get("text"))
    lines, widest = 0, 0.0
    maxw = r["w"]
    for raw in s.split("\n"):
        w = line_width(raw, size)
        if r.get("wrap") and maxw > 0 and w > maxw + 0.5:
            lines += int((w + maxw - 0.01) // maxw)
            widest = maxw
        else:
            lines += 1
            # a one-line text with a set width is cut off (with "...") at its box edge in game
            if r.get("explicitW") and maxw > 0 and not r.get("wrap"):
                w = min(w, maxw)
            widest = max(widest, w)
    return widest, lines * (size + 2), lines


def text_box(r):
    w, h, _ = text_extent(r)
    jh = r.get("jh", "CENTER")
    if jh == "LEFT":
        x = r["x"]
    elif jh == "RIGHT":
        x = r["x"] + r["w"] - w
    else:
        x = r["x"] + (r["w"] - w) / 2
    jv = r.get("jv", "MIDDLE")
    if jv == "TOP":
        y = r["y"]
    elif jv == "BOTTOM":
        y = r["y"] + r["h"] - h
    else:
        y = r["y"] + (r["h"] - h) / 2
    return x, y, w, h


def clipped(box, clip):
    """Part of box (x,y,w,h) that survives the clip rect dict; None if none."""
    if not clip:
        return box
    x1, y1 = max(box[0], clip["x"]), max(box[1], clip["y"])
    x2, y2 = min(box[0] + box[2], clip["x"] + clip["w"]), min(box[1] + box[3], clip["y"] + clip["h"])
    if x2 <= x1 or y2 <= y1:
        return None
    return (x1, y1, x2 - x1, y2 - y1)


def inter(a, b):
    x1, y1 = max(a[0], b[0]), max(a[1], b[1])
    x2, y2 = min(a[0] + a[2], b[0] + b[2]), min(a[1] + a[3], b[1] + b[3])
    return max(0, x2 - x1) * max(0, y2 - y1)


def lum(c):
    def f(v):
        return v / 12.92 if v <= 0.03928 else ((v + 0.055) / 1.055) ** 2.4
    return 0.2126 * f(c[0]) + 0.7152 * f(c[1]) + 0.0722 * f(c[2])


def contrast(a, b):
    la, lb = lum(a), lum(b)
    hi, lo = max(la, lb), min(la, lb)
    return (hi + 0.05) / (lo + 0.05)


BAD = [
    (re.compile(r"\bnil\b"), "contains 'nil'"),
    (re.compile(r"\bNaN\b|\binf\b|-inf\b"), "contains NaN/inf"),
    (re.compile(r"%[sdif]"), "unformatted placeholder"),
    (re.compile(r"table: 0x|function: 0x"), "raw Lua value"),
    (re.compile(r"\{\w+\}"), "unfilled {placeholder}"),
    (re.compile(r"\bundefined\b|\bnull\b"), "contains undefined/null"),
]


def bad_color_codes(s):
    s = str(s or "")
    opens = len(re.findall(r"\|c[0-9a-fA-F]{8}", s))
    closes = s.count("|r")
    if opens > closes + 1:
        return "unclosed |c colour code"
    if re.search(r"\|c(?![0-9a-fA-F]{8})", s):
        return "malformed |c colour code"
    return None


def backdrop_at(regions, idx, px, py):
    """Colour behind point (px,py) from textures drawn before region idx."""
    col = (0.0, 0.0, 0.0)
    for r in regions[:idx]:
        if r.get("k") != "t":
            continue
        if not (r["x"] <= px <= r["x"] + r["w"] and r["y"] <= py <= r["y"] + r["h"]):
            continue
        c = r.get("color")
        g = r.get("grad")
        if g:
            c1, c2 = g["c1"], g["c2"]
            c = [(c1[i] + c2[i]) / 2 for i in range(4)]
        if not c:
            continue
        a = (c[3] if len(c) > 3 else 1.0) * r.get("a", 1)
        col = tuple(col[i] * (1 - a) + c[i] * a for i in range(3))
    return col


def occluded(regions, idx, box):
    """True when a mostly opaque texture drawn after region idx covers the middle of box
    (text behind a dialog or a dropdown list is not visible in game)."""
    cx, cy = box[0] + box[2] / 2, box[1] + box[3] / 2
    for r in regions[idx + 1:]:
        if r.get("k") != "t":
            continue
        c = r.get("color")
        g = r.get("grad")
        a = None
        if g:
            a = min(g["c1"][3] if len(g["c1"]) > 3 else 1, g["c2"][3] if len(g["c2"]) > 3 else 1)
        elif c:
            a = c[3] if len(c) > 3 else 1
        elif r.get("tex"):
            a = 0.9
        if a is None or a * r.get("a", 1) < 0.85:
            continue
        vis = clipped((r["x"], r["y"], r["w"], r["h"]), r.get("clip"))
        # covered when the panel hides most of the text (not just its middle point)
        if vis and vis[2] * vis[3] > box[2] * box[3] and inter(vis, box) >= 0.5 * max(1, box[2] * box[3]):
            return True
    return False


def finding(page, rule, sev, msg, region=None, extra=None):
    key = f"{rule}|{page}|{msg}"
    fid = "L-" + hashlib.sha1(key.encode()).hexdigest()[:8]
    f = {"id": fid, "kind": "layout", "rule": rule, "severity": sev, "page": page, "message": msg}
    if region is not None:
        f["at"] = {k: round(region[k]) for k in ("x", "y", "w", "h") if k in region}
        if region.get("text"):
            f["text"] = plain(region["text"])[:80]
    if extra:
        f.update(extra)
    return f


def lint_page(page, data):
    regs = data["regions"]
    W, H = data.get("w", SCREEN_W), data.get("h", SCREEN_H)
    out = []
    texts = []
    if len(regs) < 8 and not page.startswith("explore--"):
        out.append(finding(page, "empty-page", "medium", f"only {len(regs)} regions drawn"))
    for i, r in enumerate(regs):
        if r.get("a", 1) <= 0.05:
            continue
        k = r.get("k")
        if k not in ("t", "s", "chk", "inp"):
            continue
        # offscreen (ignore full-screen backdrops)
        vis = clipped((r["x"], r["y"], r["w"], r["h"]), r.get("clip"))
        if vis is not None and r["w"] < W * 0.95 and (vis[0] < -2 or vis[1] < -2 or vis[0] + vis[2] > W + 2 or vis[1] + vis[3] > H + 2):
            out.append(finding(page, "offscreen", "high" if k == "s" else "medium",
                               "region extends beyond the screen", r))
        clip = r.get("clip")
        if clip and k in ("s", "chk", "inp") and inter((r["x"], r["y"], r["w"], r["h"]),
                                                      (clip["x"], clip["y"], clip["w"], clip["h"])) == 0 \
                and r["w"] > 0 and r["h"] > 0:
            out.append(finding(page, "clipped-away", "low", "visible control lies outside its clip area", r))
        if k != "s":
            continue
        text = r.get("text")
        size = r.get("size") or 12
        if size < 8:
            out.append(finding(page, "tiny-text", "low", f"text drawn at {size}px", r))
        w, h, lines = text_extent(r)
        # a text box with a clip rect narrower than the text is truncated on purpose only if clipped
        full = line_width(plain(text).split("\n")[0], size)
        if r.get("explicitW") and not r.get("wrap") and "\n" not in plain(text) and full > r["w"] * 1.12 + 3 and r["w"] > 0:
            out.append(finding(page, "text-overflow", "low",
                               f"one-line text needs ~{round(full)}px but its box is {round(r['w'])}px, so it is cut off with '...'", r))
        if r.get("wrap") and h > r["h"] + (size + 2) * 0.9 and r["h"] > 0:
            out.append(finding(page, "text-clipped", "medium",
                               f"wrapped text needs ~{lines} lines (~{round(h)}px) but its box is {round(r['h'])}px", r))
        for pat, why in BAD:
            if pat.search(plain(text)):
                out.append(finding(page, "bad-text", "medium", why + ": " + plain(text)[:60], r))
                break
        cc = bad_color_codes(text)
        if cc:
            out.append(finding(page, "bad-text", "medium", cc + ": " + str(text)[:60], r))
        # contrast
        col = r.get("color") or [1, 1, 1, 1]
        if isinstance(col, list) and len(col) >= 3 and "|c" not in str(text):
            bx, by, bw, bh = text_box(r)
            bg = backdrop_at(regs, i, bx + bw / 2, by + bh / 2)
            ratio = contrast(col[:3], bg)
            if ratio < 2.5 and plain(text).strip():
                out.append(finding(page, "low-contrast", "medium",
                                   f"text contrast {ratio:.1f}:1 against its background", r))
        if plain(text).strip():
            tb = text_box(r)
            cb = clipped(tb, r.get("clip"))
            if cb is not None and cb[2] * cb[3] >= 0.5 * max(1, tb[2] * tb[3]) and not occluded(regs, i, cb):
                texts.append((i, r, cb))
    # overlaps
    for a in range(len(texts)):
        ia, ra, ba = texts[a]
        for b in range(a + 1, len(texts)):
            ib, rb, bb = texts[b]
            ov = inter(ba, bb)
            if ov <= 0:
                continue
            small = min(ba[2] * ba[3], bb[2] * bb[3])
            if small > 0 and ov / small > 0.35 and ov > 40:
                ca, cb = ra.get("clip"), rb.get("clip")
                # text from another window showing through a see-through panel (the pop-out chat's
                # Opacity setting) is what the player chose: report it as low
                sev = "high"
                if page.endswith("popout") or "popout" in page:
                    sev = "low"
                out.append(finding(page, "text-overlap", sev,
                                   f"'{plain(ra['text'])[:30]}' overlaps '{plain(rb['text'])[:30]}'", ra,
                                   {"other_at": {k: round(rb[k]) for k in ("x", "y", "w", "h")}}))
    # dedupe by id
    seen, uniq = set(), []
    for f in out:
        if f["id"] in seen:
            continue
        seen.add(f["id"])
        uniq.append(f)
    return uniq


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("dir")
    ap.add_argument("--out")
    args = ap.parse_args()
    findings = []
    for path in sorted(glob.glob(os.path.join(args.dir, "*.json"))):
        page = os.path.splitext(os.path.basename(path))[0]
        if page in ("findings", "layout-findings"):
            continue
        with open(path) as fh:
            data = json.load(fh)
        if not isinstance(data, dict) or "regions" not in data:
            continue
        findings.extend(lint_page(page, data))
    text = "\n".join(json.dumps(f) for f in findings)
    if args.out:
        with open(args.out, "w") as fh:
            fh.write(text + ("\n" if text else ""))
    print(f"lint: {len(findings)} layout findings", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
