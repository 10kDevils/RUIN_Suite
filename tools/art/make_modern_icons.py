#!/usr/bin/env python3
"""Draws Pathfinder's modern-style icons into RUIN_Pathfinder/Media as 32-bit
TGA files: white glyphs on clear, tinted in game, drawn large and scaled down.

    python3 tools/art/make_modern_icons.py

Objective tracker: Disc, Ring (the quest marker's body and edge), Question,
Bang, Dots (what the marker says), Minus, Plus (collapse), Chevron, Check,
Slot (an item button's frame). Minimap: Search (tracking), Mail, Sun, Moon
(day and night), North (the N).
"""
import math, os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from make_art import Canvas, white

HERE = os.path.dirname(os.path.abspath(__file__))
MEDIA = os.path.join(HERE, "..", "..", "RUIN_Pathfinder", "Media")
K = 8
S = 64


def icon(name, draw):
    c = Canvas(S, S, K)
    draw(c)
    img = white(c.alpha(S, S))
    img.save(os.path.join(MEDIA, "Modern" + name + ".tga"), format="TGA")
    return img


def question(c):
    # a hook: from the left, over the top, down the right and in to the stem
    c.arc(32, 22, 13.5, 8, 180, 360)
    c.arc(32, 22, 13.5, 8, 0, 60)
    c.line([(38.5, 33.5), (32, 38.5), (32, 42)], 8)
    c.disc(32, 54, 5.2)


def bang(c):
    c.line([(32, 10), (32, 41)], 8.5)
    c.disc(32, 54, 5.4)


def dots(c):
    for x in (16, 32, 48):
        c.disc(x, 32, 6.2)


def minus(c):
    c.line([(16, 32), (48, 32)], 7)


def plus(c):
    c.line([(16, 32), (48, 32)], 7)
    c.line([(32, 16), (32, 48)], 7)


def chevron(c):
    c.line([(25, 15), (41, 32), (25, 49)], 7)


def check(c):
    c.line([(14, 33), (27, 46), (50, 19)], 7.5)


def slot(c):
    outer, inner = Canvas(S, S, K), Canvas(S, S, K)
    outer.rrect(2, 2, 62, 62, 9)
    inner.rrect(5.5, 5.5, 58.5, 58.5, 6)
    outer.cut(inner)
    c.add(outer)


def search(c):
    c.ring(27, 27, 15, 6.5)
    c.line([(38.5, 38.5), (52, 52)], 8)


def mail(c):
    body, hole = Canvas(S, S, K), Canvas(S, S, K)
    body.rrect(8, 15, 56, 49, 5)
    hole.rrect(13, 20, 51, 44, 2)
    body.cut(hole)
    c.add(body)
    c.line([(12, 19), (32, 35), (52, 19)], 5)


def sun(c):
    c.disc(32, 32, 11)
    for i in range(8):
        a = i * math.pi / 4
        c.line([(32 + math.cos(a) * 18, 32 + math.sin(a) * 18), (32 + math.cos(a) * 26, 32 + math.sin(a) * 26)], 5)


def moon(c):
    body, bite = Canvas(S, S, K), Canvas(S, S, K)
    body.disc(32, 32, 22)
    bite.disc(43, 24, 19)
    body.cut(bite)
    c.add(body)


def letter_n(c):
    c.line([(20, 47), (20, 17), (44, 47), (44, 17)], 7.5, caps=False)


def disc(c):
    c.disc(32, 32, 29)


def ring(c):
    c.ring(32, 32, 28.5, 4)


ICONS = {"Disc": disc, "Ring": ring, "Question": question, "Bang": bang, "Dots": dots, "Minus": minus,
         "Plus": plus, "Chevron": chevron, "Check": check, "Slot": slot, "Search": search, "Mail": mail,
         "Sun": sun, "Moon": moon, "North": letter_n}

if __name__ == "__main__":
    for n, f in ICONS.items():
        icon(n, f)
    print("wrote", len(ICONS), "icons to", os.path.normpath(MEDIA))
