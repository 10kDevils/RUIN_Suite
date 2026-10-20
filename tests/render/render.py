#!/usr/bin/env python3
"""Draw render.lua's layout dumps as PNG screenshots (needs Playwright + Chromium).

    python3 render/render.py <dumpdir> [<pngdir>]

Each page becomes <pngdir>/<page>.png, cropped to the RUIN window.
"""
import html, json, math, pathlib, re, sys

def rgba(c, a=1.0):
    if not c:
        return "transparent"
    r, g, b = [max(0, min(1, float(x))) for x in c[:3]]
    al = (float(c[3]) if len(c) > 3 and c[3] is not None else 1.0) * a
    return f"rgba({round(r*255)},{round(g*255)},{round(b*255)},{al:.3f})"

CODE = re.compile(r"\|c([0-9a-fA-F]{8})|\|r|\|T[^|]*\|t|\|H[^|]*\|h|\|h|\|n|\n")

def markup(text, base):
    out, stack, pos = [], [], 0
    for m in CODE.finditer(text):
        out.append(html.escape(text[pos:m.start()]))
        tok = m.group(0)
        if tok.startswith("|c"):
            hx = m.group(1)[2:]
            out.append(f'<span style="color:#{hx}">')
            stack.append(1)
        elif tok == "|r":
            if stack:
                stack.pop()
                out.append("</span>")
        elif tok.startswith("|T"):
            out.append('<i class="ic"></i>')
        elif tok in ("|n", "\n"):
            out.append("<br>")
        pos = m.end()
    out.append(html.escape(text[pos:]))
    out.extend("</span>" for _ in stack)
    return "".join(out)

def clipcss(e, ox, oy):
    c = e.get("clip")
    if not c:
        return ""
    x, y, w, h = c["x"] - e["x"], c["y"] - e["y"], c["w"], c["h"]
    return f"clip-path: inset({y}px {e['w']-(x+w)}px {e['h']-(y+h)}px {x}px);"

def region(e, ox, oy):
    x, y, w, h, a = e["x"] - ox, e["y"] - oy, e["w"], e["h"], e.get("a", 1)
    base = f"left:{x:.1f}px;top:{y:.1f}px;width:{max(w,0):.1f}px;height:{max(h,0):.1f}px;opacity:{a:.3f};" + clipcss(e, ox, oy)
    k = e["k"]
    if k == "t":
        style = base
        if e.get("grad"):
            g = e["grad"]
            if g["dir"] == "HORIZONTAL":
                style += f"background:linear-gradient(to right,{rgba(g['c1'])},{rgba(g['c2'])});"
            else:
                style += f"background:linear-gradient(to top,{rgba(g['c1'])},{rgba(g['c2'])});"
        elif e.get("color"):
            style += f"background:{rgba(e['color'])};"
        elif e.get("tex"):
            tex = e["tex"].lower()
            tint = e.get("vertex")
            if "icons" in tex or tex.isdigit():
                col = rgba(tint) if tint else "#5b4a2e"
                style += f"background:linear-gradient(135deg,{col},#22190d);outline:1px solid rgba(0,0,0,.6);"
            else:
                col = rgba(tint) if tint else "rgba(170,170,170,.55)"
                style += f"background:{col};"
        if e.get("round"):
            style += "border-radius:50%;"
        if e.get("rot"):
            style += f"transform:rotate({-float(e['rot'])}rad);"
        return f'<div class="r" style="{style}"></div>'
    if k == "s":
        size = e.get("size") or 12
        jh = {"LEFT": "left", "RIGHT": "right"}.get(e.get("jh"), "center")
        jv = {"TOP": "flex-start", "BOTTOM": "flex-end"}.get(e.get("jv"), "center")
        wrap = e.get("wrap", True) and e.get("explicitW")
        style = base + f"font-size:{size}px;line-height:{size+2}px;color:{rgba(e.get('color') or [1,.82,0,1])};"
        style += f"display:flex;align-items:{jv};justify-content:{ {'left':'flex-start','right':'flex-end','center':'center'}[jh] };text-align:{jh};"
        if not wrap:
            style += "white-space:nowrap;"
            if e.get("explicitW"):
                style += "overflow:hidden;"
        inner = markup(e.get("text") or "", e.get("color"))
        if not wrap and e.get("explicitW"):
            inner = f'<span style="overflow:hidden;text-overflow:ellipsis;max-width:100%">{inner}</span>'
        else:
            inner = f"<span>{inner}</span>"
        return f'<div class="r s" style="{style}">{inner}</div>'
    if k == "chk":
        mark = '<span style="color:#ffd200;font-size:14px;line-height:1">&#10003;</span>' if e.get("on") else ""
        return (f'<div class="r" style="{base}background:#0b0b0b;border:1px solid #8b7a4a;box-sizing:border-box;'
                f'display:flex;align-items:center;justify-content:center">{mark}</div>')
    if k == "inp":
        return f'<div class="r" style="{base}background:#050505;border:1px solid #6e6e6e;box-sizing:border-box;border-radius:2px"></div>'
    if k == "bar":
        th = max(18, h * float(e.get("frac", .5)))
        return (f'<div class="r" style="{base}background:rgba(255,255,255,.05);border:1px solid rgba(255,255,255,.12);box-sizing:border-box">'
                f'<div style="position:absolute;left:2px;right:2px;top:2px;height:{th:.0f}px;background:rgba(200,200,200,.35)"></div></div>')
    return ""

def page_html(dump):
    regs = dump["regions"]
    # crop to the RUIN window: the largest region drawn
    win = max(regs, key=lambda e: e["w"] * e["h"] if e["k"] == "t" else 0)
    ox, oy, W, H = win["x"] - 6, win["y"] - 6, win["w"] + 12, win["h"] + 12
    body = "\n".join(region(e, ox, oy) for e in regs)
    return f"""<!doctype html><html><head><meta charset="utf-8"><style>
html,body{{margin:0;background:#1a1d22}}
#c{{position:relative;width:{W:.0f}px;height:{H:.0f}px;overflow:hidden;font-family:'DejaVu Sans Condensed','Arial Narrow',Arial,sans-serif;background:#2b2f36}}
.r{{position:absolute;box-sizing:border-box}}
.s{{text-shadow:1px -1px 0 #000}}
.ic{{display:inline-block;width:1em;height:1em;background:#5b4a2e;vertical-align:-2px;margin:0 1px}}
</style></head><body><div id="c">{body}</div></body></html>""", (W, H)

def main():
    src = pathlib.Path(sys.argv[1])
    dst = pathlib.Path(sys.argv[2] if len(sys.argv) > 2 else src)
    dst.mkdir(parents=True, exist_ok=True)
    names = [n for n in (src / "index.txt").read_text().split() if n]
    from playwright.sync_api import sync_playwright
    with sync_playwright() as p:
        b = p.chromium.launch()
        pg = b.new_page(device_scale_factor=1.25)
        for n in names:
            doc, (W, H) = page_html(json.loads((src / f"{n}.json").read_text()))
            (dst / f"{n}.html").write_text(doc)
            pg.set_viewport_size({"width": int(W) + 2, "height": int(H) + 2})
            pg.set_content(doc)
            pg.locator("#c").screenshot(path=str(dst / f"{n}.png"))
        b.close()
    print(f"drew {len(names)} pages to {dst}")

if __name__ == "__main__":
    main()
