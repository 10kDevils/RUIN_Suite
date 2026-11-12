#!/usr/bin/env python3
"""Turns the two faction extracts into Pathfinder's quest data files (RUIN_Pathfinder/QuestData)."""
import re, sys, os
src, out = sys.argv[1], sys.argv[2]
A = open(os.path.join(src, "Alliance.lua")).read().splitlines()
H = open(os.path.join(src, "Horde.lua")).read().splitlines()
fields = open(os.path.join(src, "Alliance.lua.fields")).read()
def fix(lines):
    res = []
    for l in lines:
        m = re.match(r'^F\(function\((\w)\)$', l)
        if m: res.append('F("%s", function(%s)' % (m.group(1), m.group(1))); continue
        if l.startswith('F(function(_, z)'): l = 'F("z", function(z)' + l[len('F(function(_, z)'):]
        res.append(l)
    return res
A, H = fix(A), fix(H)
head = """-- RUIN Quest Data: WoW Forever's quests, NPCs, objects and items for RUIN
-- Pathfinder. Built from QuestieDB's Forever database (see NOTICE); licensed
-- under the GNU GPL v3 (see LICENSE).
RUIN_QuestData = RUIN_QuestData or { q = {}, n = {}, o = {}, i = {}, z = {} }
local D = RUIN_QuestData
"""
fieldLua = "D.fields = {\n" + "\n".join("    " + l.replace("=", " = ", 1) + "," for l in fields.strip().splitlines()) + "\n}\n"
f_def = "local function F(which, fn) fn(D[which]) end\n"
with open(os.path.join(out, "Data.lua"), "w") as f:
    f.write(head + fieldLua + f_def + "\n".join(l for l in A if not l.startswith("--")) + "\n")
# Horde: only the rows that differ
amap = {}
for l in A:
    m = re.match(r'^(\w)\[(\d+)\]=', l)
    if m: amap[(m.group(1), m.group(2))] = l
diff = []
for l in H:
    m = re.match(r'^(\w)\[(\d+)\]=', l)
    if m and amap.get((m.group(1), m.group(2))) != l: diff.append(l)
with open(os.path.join(out, "Horde.lua"), "w") as f:
    f.write("-- The rows that are different for the Horde (see LICENSE and NOTICE),\n")
    f.write("-- put in by Pathfinder once it knows your faction.\n")
    f.write("local D = RUIN_QuestData\nD.faction = D.faction or {}\n")
    f.write("D.faction.Horde = function(q, n, o, i)\n")
    f.write("\n".join(diff) + "\nend\n")
print("Data.lua rows:", sum(1 for l in A if re.match(r'^\w\[\d+\]=', l)), " Horde rows:", len(diff))
