#!/usr/bin/env python3
"""Draws RUIN's own interface art into RUIN_Core/Media as 32-bit TGA files.

    python3 tools/art/make_art.py

- Icon<Name>.tga   64x64   one white glyph per module, tinted in game (tabs)
- Badge<Name>.tga  64x64   the glyph on a dark rounded tile edged in the
                           module's color (page headers, the AddOns list)
- Art<Name>.tga    512x128 the line drawing on the right of a page header,
                           white with a fade to the left, tinted in game
- Check.tga, Chevron.tga   small control glyphs

Everything is drawn large and scaled down, so edges are smooth. The colors
below must match RUIN_Core/Theme.lua.
"""
import math, os, random
from PIL import Image, ImageChops, ImageDraw, ImageFilter

HERE = os.path.dirname(os.path.abspath(__file__))
MEDIA = os.path.join(HERE, "..", "..", "RUIN_Core", "Media")
SS = 4          # supersampling

COLORS = {
    "Guild":      (0.90, 0.72, 0.38),
    "Finder":     (0.82, 0.31, 0.54),
    "Muster":     (0.85, 0.38, 0.17),
    "Pathfinder": (0.31, 0.60, 0.23),
    "Codex":      (0.54, 0.32, 0.84),
    "Exchange":   (0.84, 0.60, 0.16),
    "Settings":   (0.33, 0.72, 0.85),
    "Planner":    (0.36, 0.62, 0.78),
}


class Canvas:
    """An alpha-only drawing surface in design units (w x h), drawn at k times the size."""

    def __init__(self, w, h, k):
        self.w, self.h, self.k = w, h, k
        self.img = Image.new("L", (int(w * k), int(h * k)), 0)
        self.d = ImageDraw.Draw(self.img)

    def _p(self, pts):
        return [(x * self.k, y * self.k) for x, y in pts]

    def disc(self, x, y, r, a=255):
        k = self.k
        self.d.ellipse([(x - r) * k, (y - r) * k, (x + r) * k, (y + r) * k], fill=a)

    def ring(self, x, y, r, w, a=255):
        k = self.k
        self.d.ellipse([(x - r) * k, (y - r) * k, (x + r) * k, (y + r) * k], outline=a, width=max(1, int(round(w * k))))

    def arc(self, x, y, r, w, start, end, a=255):
        k = self.k
        self.d.arc([(x - r) * k, (y - r) * k, (x + r) * k, (y + r) * k], start, end, fill=a, width=max(1, int(round(w * k))))

    def line(self, pts, w, a=255, caps=True):
        self.d.line(self._p(pts), fill=a, width=max(1, int(round(w * self.k))), joint="curve")
        if caps:
            for x, y in pts:
                self.disc(x, y, w / 2, a)

    def poly(self, pts, a=255):
        self.d.polygon(self._p(pts), fill=a)

    def outline(self, pts, w, a=255):
        self.line(list(pts) + [pts[0]], w, a)

    def rect(self, x0, y0, x1, y1, a=255):
        self.d.rectangle([x0 * self.k, y0 * self.k, x1 * self.k, y1 * self.k], fill=a)

    def rrect(self, x0, y0, x1, y1, r, a=255):
        self.d.rounded_rectangle([x0 * self.k, y0 * self.k, x1 * self.k, y1 * self.k], radius=r * self.k, fill=a)

    def cut(self, other):
        """Erase where `other` (a Canvas) is drawn."""
        self.img = ImageChops.subtract(self.img, other.img)
        self.d = ImageDraw.Draw(self.img)

    def add(self, other):
        self.img = ImageChops.lighter(self.img, other.img)
        self.d = ImageDraw.Draw(self.img)

    def alpha(self, out_w, out_h):
        return self.img.resize((out_w, out_h), Image.LANCZOS)


def save(name, rgba):
    path = os.path.join(MEDIA, name + ".tga")
    rgba.save(path, format="TGA")
    return path


def white(alpha):
    """A white image with this alpha (so the game can tint it)."""
    w = Image.new("L", alpha.size, 255)
    return Image.merge("RGBA", (w, w, w, alpha))


# ---------------------------------------------------------------------------
# Glyphs: one per module, in a 64 x 64 box
# ---------------------------------------------------------------------------
def glyph_finder(c):       # a magnifying glass: finding people
    c.ring(27, 27, 18, 6)
    c.line([(41, 41), (55, 55)], 8)


def glyph_muster(c):       # a rally flag on its pole
    c.line([(15, 8), (15, 57)], 6)
    c.poly([(20, 10), (56, 10), (45, 23), (56, 36), (20, 36)])


def glyph_pathfinder(c):   # a compass, needle to the north-east
    c.ring(32, 32, 25, 5)
    c.poly([(47, 17), (37, 37), (17, 47), (27, 27)])
    hole = Canvas(64, 64, c.k)
    hole.disc(32, 32, 3.2)
    c.cut(hole)


def glyph_codex(c):        # an open book
    c.poly([(6, 14), (29, 19), (29, 54), (6, 49)])
    c.poly([(35, 19), (58, 14), (58, 49), (35, 54)])
    lines = Canvas(64, 64, c.k)
    for y in (27, 36):
        lines.line([(11, y - 2), (24, y + 1)], 2.6)
        lines.line([(40, y + 1), (53, y - 2)], 2.6)
    c.cut(lines)


def glyph_exchange(c):     # a merchant's scales
    c.line([(32, 10), (32, 52)], 5)
    c.line([(20, 54), (44, 54)], 5.5)
    c.line([(10, 17), (54, 17)], 5)
    c.disc(32, 12, 5)
    for x in (12, 52):
        c.line([(x, 17), (x - 9, 35)], 2.2)
        c.line([(x, 17), (x + 9, 35)], 2.2)
        k = c.k
        c.d.pieslice([(x - 11) * k, (35 - 9) * k, (x + 11) * k, (35 + 9) * k], 0, 180, fill=255)


def glyph_settings(c):     # a gear
    c.disc(32, 32, 18)
    for i in range(8):
        a = math.pi / 4 * i
        ca, sa = math.cos(a), math.sin(a)
        def pt(r, t):
            return (32 + ca * r - sa * t, 32 + sa * r + ca * t)
        c.poly([pt(14, -6), pt(26, -4.6), pt(26, 4.6), pt(14, 6)])
    hole = Canvas(64, 64, c.k)
    hole.disc(32, 32, 8)
    c.cut(hole)


def glyph_planner(c):      # a checklist
    for i, y in enumerate((16, 32, 48)):
        c.line([(9, y), (13, y + 4), (20, y - 5)], 3.6)
        c.line([(28, y), (56 - i * 7, y)], 4.6)


GLYPHS = {
    "Finder": glyph_finder, "Muster": glyph_muster, "Pathfinder": glyph_pathfinder, "Codex": glyph_codex,
    "Exchange": glyph_exchange, "Settings": glyph_settings, "Planner": glyph_planner,
}


def glyph_alpha(name, size=64):
    c = Canvas(64, 64, SS * 2)
    GLYPHS[name](c)
    return c.alpha(size, size)


def lighten(col, t):
    return tuple(v + (1 - v) * t for v in col)


def solid(size, col, alpha):
    r, g, b = [Image.new("L", size, int(round(max(0, min(1, v)) * 255))) for v in col]
    return Image.merge("RGBA", (r, g, b, alpha))


def badge(name, col, art=None):
    """The module's glyph on a dark rounded tile edged in its color."""
    N = 64
    tile = Canvas(N, N, SS * 2)
    tile.rrect(1, 1, N - 1, N - 1, 13)
    inner = Canvas(N, N, SS * 2)
    inner.rrect(3, 3, N - 3, N - 3, 11)
    ta, ia = tile.alpha(N, N), inner.alpha(N, N)
    out = Image.new("RGBA", (N, N), (0, 0, 0, 0))
    out = Image.alpha_composite(out, solid((N, N), lighten(col, 0.08), ta))               # the edge
    # the face: navy, a little lighter and warmer toward the top
    face = Image.new("RGBA", (N, N))
    px = face.load()
    for y in range(N):
        t = y / (N - 1)
        base = (0.105 - 0.050 * t, 0.140 - 0.060 * t, 0.200 - 0.080 * t)
        mixed = tuple(base[i] + (col[i] - base[i]) * (0.16 - 0.10 * t) for i in range(3))
        for x in range(N):
            px[x, y] = tuple(int(round(v * 255)) for v in mixed) + (255,)
    face.putalpha(ia)
    out = Image.alpha_composite(out, face)
    if art is not None:
        g = art.resize((46, 46), Image.LANCZOS)
        layer = Image.new("RGBA", (N, N), (0, 0, 0, 0))
        layer.paste(g, (9, 9), g)
        out = Image.alpha_composite(out, layer)
    else:
        g = glyph_alpha(name, 40)
        ga = Image.new("L", (N, N), 0)
        ga.paste(g, (12, 12))
        out = Image.alpha_composite(out, solid((N, N), lighten(col, 0.38), ga))
    return out


# ---------------------------------------------------------------------------
# Header art: 256 x 64 design units, drawn into 512 x 128
# ---------------------------------------------------------------------------
AW, AH = 256, 64


def fade_left(alpha, start=28, end=128):
    """Fade the drawing out toward the left (design units)."""
    w, h = alpha.size
    k = w / AW
    ramp = Image.new("L", (w, 1))
    rp = ramp.load()
    for x in range(w):
        t = (x / k - start) / (end - start)
        t = max(0.0, min(1.0, t))
        rp[x, 0] = int(round(255 * t * t * (3 - 2 * t)))
    return ImageChops.multiply(alpha, ramp.resize((w, h)))


def art_canvas():
    return Canvas(AW, AH, 2 * SS)


def art_guild(c):
    emblem = Image.open(os.path.join(MEDIA, "EmblemTall.tga")).convert("RGBA")
    c.line([(92, 8), (250, 8)], 1.6, 235)
    for x in (92, 250):
        c.disc(x, 8, 2.6, 235)
    for i, x in enumerate((126, 171, 216)):
        big = i == 1
        hw, top, bot = (17 if big else 14), 8, (52 if big else 44)
        pts = [(x - hw, top), (x + hw, top), (x + hw, bot), (x, bot - 9), (x - hw, bot)]
        c.poly(pts, 46 if big else 34)
        c.outline(pts, 1.4, 225)
        c.line([(x - hw + 3, top + 4), (x + hw - 3, top + 4)], 1, 120)
        if not big:
            c.poly([(x, 16), (x + 6, 23), (x, 30), (x - 6, 23)], 210)
    return ("guild-emblem", emblem)


def art_finder(c):
    rnd = random.Random(7)
    nodes = [(60 + rnd.random() * 188, 6 + rnd.random() * 52) for _ in range(26)]
    nodes += [(206, 31), (150, 20), (176, 48), (232, 14)]
    for i, a in enumerate(nodes):
        for b in nodes[i + 1:]:
            d = math.hypot(a[0] - b[0], a[1] - b[1])
            if d < 34:
                c.line([a, b], 0.8, int(120 - d * 2.2), caps=False)
    for (x, y) in nodes[:-4]:
        c.disc(x, y, 1.7, 215)
    for r, a in ((13, 120), (22, 78), (31, 44)):       # a ping going out from the one you found
        c.ring(206, 31, r, 1.1, a)
    for (x, y) in nodes[-4:]:
        c.disc(x, y, 3.4, 255)
        c.ring(x, y, 6.4, 1.2, 190)


def art_muster(c):
    def rope(x, sag, y0, x0=96, x1=250):
        t = (x - x0) / (x1 - x0)
        return y0 + sag * 4 * t * (1 - t)
    for y0, sag, a, n, size in ((6, 9, 120, 12, 9), (10, 20, 235, 10, 13)):
        pts = [(x, rope(x, sag, y0)) for x in range(96, 251, 2)]
        c.line(pts, 1.3, a, caps=False)
        for i in range(n):
            x = 96 + (i + 0.5) * (154 / n)
            y = rope(x, sag, y0)
            hw = size * 0.46
            tri = [(x - hw, y + 0.5), (x + hw, y + 0.5), (x, y + size)]
            c.poly(tri, int(a * (0.75 if i % 2 == 0 else 0.30)))
            c.outline(tri, 1.0, a)
    for x in (96, 250):
        c.line([(x, 4), (x, 62)], 2.2, 235)
        c.disc(x, 4, 3, 235)


def trail_points():
    """The route in Pathfinder's header (Theme.lua walks a dot along the same points)."""
    return [(98 + i * 6.6, 32 - math.sin(i * 0.45) * 15) for i in range(23)]


def art_pathfinder(c):
    # contour lines of the country the trail crosses
    for j in range(7):
        y0 = 5 + j * 9.5
        pts = [(x, y0 + 5.5 * math.sin(x * 0.034 + j * 0.9) + 2.5 * math.sin(x * 0.081 + j * 2.1)) for x in range(20, 257, 3)]
        c.line(pts, 0.9, 78, caps=False)
    for (cx, cy, rx, ry) in ((122, 50, 24, 9), (206, 13, 28, 9)):
        for s, a in ((1.0, 90), (0.62, 106), (0.28, 124)):
            pts = []
            for t in range(0, 361, 6):
                q = math.radians(t)
                wob = 1 + 0.10 * math.sin(3 * q + cx)
                pts.append((cx + rx * s * wob * math.cos(q), cy + ry * s * wob * math.sin(q)))
            c.line(pts, 0.9, a, caps=False)
    pts = trail_points()
    for (x, y) in pts[1:-1]:
        c.disc(x, y, 1.45, 240)
    x, y = pts[0]
    c.poly([(x, y - 5), (x + 5, y), (x, y + 5), (x - 5, y)], 255)
    x, y = pts[-1]
    c.line([(x - 5, y - 5), (x + 5, y + 5)], 2.4, 255)
    c.line([(x - 5, y + 5), (x + 5, y - 5)], 2.4, 255)


def art_codex(c):
    cx, cy = 208, 32
    c.ring(cx, cy, 28, 1.6, 235)
    c.ring(cx, cy, 23, 0.9, 130)
    c.ring(cx, cy, 10, 1.1, 170)
    for i in range(36):
        a = math.radians(i * 10)
        r0, r1 = (23.6, 27.2) if i % 3 else (22.2, 27.2)
        c.line([(cx + r0 * math.cos(a), cy + r0 * math.sin(a)), (cx + r1 * math.cos(a), cy + r1 * math.sin(a))], 0.8, 190, caps=False)
    for off in (0, 60):
        tri = [(cx + 21.5 * math.cos(math.radians(off - 90 + k * 120)), cy + 21.5 * math.sin(math.radians(off - 90 + k * 120))) for k in range(3)]
        c.outline(tri, 1.0, 150)
    c.poly([(cx, cy - 5.5), (cx + 4.2, cy), (cx, cy + 5.5), (cx - 4.2, cy)], 240)
    # the page beside it: an illuminated initial and lines of script
    rnd = random.Random(11)
    c.outline([(64, 10), (78, 10), (78, 24), (64, 24)], 1.2, 190)
    c.poly([(71, 12.5), (75.5, 17), (71, 21.5), (66.5, 17)], 150)
    for row in range(6):
        y = 12 + row * 8.2
        x = 84 if row < 2 else 64
        end = 166 - (22 if row == 5 else 0)
        while x < end:
            w = 5 + rnd.random() * 15
            c.line([(x, y), (min(end, x + w), y)], 1.5, 96 + int(rnd.random() * 50))
            x += w + 4


def ledger_points():
    """The trend line in Exchange's header (Theme.lua runs a dot along the same points)."""
    return [(70 + 13 * i, 46 - i * 1.9 + 5.5 * math.sin(i * 0.9)) for i in range(14)]


def art_exchange(c):
    for y in (10, 24, 38, 52):
        c.line([(56, y), (252, y)], 0.7, 40, caps=False)
    pts = ledger_points()
    rnd = random.Random(5)
    for i, (x, y) in enumerate(pts):
        up = i == 0 or y <= pts[i - 1][1]
        body = 3.5 + rnd.random() * 6
        top, bot = y - body, y + body
        c.line([(x, top - 3 - rnd.random() * 3), (x, bot + 3 + rnd.random() * 3)], 0.9, 170, caps=False)
        if up:
            c.rect(x - 3.2, top, x + 3.2, bot, 215)
        else:
            c.rect(x - 3.2, top, x + 3.2, bot, 50)
            c.outline([(x - 3.2, top), (x + 3.2, top), (x + 3.2, bot), (x - 3.2, bot)], 0.9, 200)
    smooth = [(x, y - 9) for (x, y) in pts]
    c.line(smooth, 1.3, 140, caps=False)
    x, y = smooth[-1]
    c.disc(x, y, 2.6, 255)


def gear(c, cx, cy, r, teeth, w, a, turn=0.0):
    pts = []
    n = teeth * 4
    for i in range(n):
        ang = turn + 2 * math.pi * (i + 0.5) / n - math.pi / n
        rr = r if (i % 4) in (0, 1) else r * 0.80
        pts.append((cx + rr * math.cos(ang), cy + rr * math.sin(ang)))
    c.outline(pts, w, a)
    c.ring(cx, cy, r * 0.36, w, a)


def art_settings(c):
    gear(c, 214, 36, 24, 11, 1.5, 230)
    gear(c, 172, 19, 14, 8, 1.2, 150, turn=0.2)
    for i, (y, knob) in enumerate(((14, 0.72), (32, 0.30), (50, 0.56))):   # sliders
        x0, x1 = 60, 142
        kx = x0 + (x1 - x0) * knob
        c.line([(x0, y), (x1, y)], 1.2, 80)
        c.line([(x0, y), (kx, y)], 1.6, 190)
        c.disc(kx, y, 3.6, 255)


ART = {
    "Guild": art_guild, "Finder": art_finder, "Muster": art_muster, "Pathfinder": art_pathfinder,
    "Codex": art_codex, "Exchange": art_exchange, "Settings": art_settings,
}


def make_art(name):
    c = art_canvas()
    extra = ART[name](c)
    alpha = c.alpha(AW * 2, AH * 2)
    if extra and extra[0] == "guild-emblem":
        # the winged R on the middle banner
        em = extra[1].getchannel("A").crop((3, 7, 125, 121)).resize((44, 41), Image.LANCZOS)
        layer = Image.new("L", alpha.size, 0)
        layer.paste(em, (171 * 2 - 22, 12 * 2))
        alpha = ImageChops.lighter(alpha, layer)
    return white(fade_left(alpha))


def control(name, draw, size=32):
    c = Canvas(32, 32, SS * 2)
    draw(c)
    save(name, white(c.alpha(size, size)))


def main():
    made = []
    for name in GLYPHS:
        made.append(save("Icon" + name, white(glyph_alpha(name))))
    for name, col in COLORS.items():
        if name == "Guild":
            emblem = Image.open(os.path.join(MEDIA, "EmblemIcon.tga")).convert("RGBA")
            made.append(save("BadgeGuild", badge(name, col, art=emblem)))
        else:
            made.append(save("Badge" + name, badge(name, col)))
    for name in ART:
        made.append(save("Art" + name, make_art(name)))
    control("Check", lambda c: c.line([(7, 17), (13, 23), (25, 9)], 4.4))
    control("Chevron", lambda c: c.line([(9, 12.5), (16, 19.5), (23, 12.5)], 3.4))
    print("drew %d textures into %s" % (len(made) + 2, os.path.normpath(MEDIA)))


if __name__ == "__main__":
    main()
