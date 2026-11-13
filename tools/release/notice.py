#!/usr/bin/env python3
"""Writes RUIN_Core/ReleaseNotice.lua: this release's version, date and
highlights, signed with the RUIN release key (the RUIN_RELEASE_SEED secret,
64 hex characters). Players' RUIN checks the signature against the public key
in RUIN_Core/Release.lua and passes the notice on to anyone running an older
version, so everyone hears about a new version on GitHub and CurseForge from
inside the game, and nobody can fake one.

    RUIN_RELEASE_SEED=<hex> python3 tools/release/notice.py            # write the notice
    python3 tools/release/notice.py --keygen                          # a new key pair
The signature scheme is RUIN's (Crypto.lua): the Ed25519 curve and equations,
with H64(x) = SHA256(0x00 || x) || SHA256(0x01 || x) in place of SHA-512.
"""
import hashlib, os, re, sys, time

p = 2**255 - 19
L = 2**252 + 27742317777372353535851937790883648493
d = -121665 * pow(121666, p - 2, p) % p
I = pow(2, (p - 1) // 4, p)

def H64(m): return hashlib.sha256(b"\0" + m).digest() + hashlib.sha256(b"\1" + m).digest()
def inv(x): return pow(x, p - 2, p)
def xrecover(y):
    xx = (y * y - 1) * inv(d * y * y + 1)
    x = pow(xx, (p + 3) // 8, p)
    if (x * x - xx) % p: x = x * I % p
    if x % 2: x = p - x
    return x
By = 4 * inv(5) % p
Bx = xrecover(By)
B = (Bx, By, 1, Bx * By % p)
def add(P, Q):
    x1, y1, z1, t1 = P; x2, y2, z2, t2 = Q
    A = (y1 - x1) * (y2 - x2) % p; Bb = (y1 + x1) * (y2 + x2) % p
    C = t1 * 2 * d * t2 % p; D = z1 * 2 * z2 % p
    E, F, G, H = Bb - A, D - C, D + C, Bb + A
    return (E * F % p, G * H % p, F * G % p, E * H % p)
def mul(s, P):
    Q = (0, 1, 1, 0)
    while s:
        if s & 1: Q = add(Q, P)
        P = add(P, P); s >>= 1
    return Q
def enc(P):
    x, y, z, t = P; zi = inv(z); x = x * zi % p; y = y * zi % p
    return (y | ((x & 1) << 255)).to_bytes(32, "little")
def clamp(h):
    a = int.from_bytes(h[:32], "little"); a &= (1 << 254) - 8; a |= 1 << 254; return a
def public(seed): return enc(mul(clamp(H64(seed)), B))
def sign(seed, m):
    h = H64(seed); a = clamp(h); pk = enc(mul(a, B))
    r = int.from_bytes(H64(h[32:] + m), "little") % L
    R = enc(mul(r, B)); k = int.from_bytes(H64(R + pk + m), "little") % L
    return R + ((r + k * a) % L).to_bytes(32, "little")

def lua_str(s): return '"' + s.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n") + '"'

def highlights(version):
    """Up to five headlines from curseforge/<version>.md (its bold lead-ins)."""
    path = os.path.join("curseforge", version + ".md")
    if not os.path.exists(path): return []
    out = []
    for line in open(path, encoding="utf-8"):
        m = re.match(r"\s*-\s*\*\*(.+?)\*\*", line)
        if m:
            out.append(m.group(1).strip().rstrip(".:")[:90])
        if len(out) == 5: break
    return out

def main():
    if "--keygen" in sys.argv:
        seed = os.urandom(32)
        print("RUIN_RELEASE_SEED (secret):", seed.hex())
        print("public key (Release.lua):  ", public(seed).hex())
        return
    seed_hex = os.environ.get("RUIN_RELEASE_SEED", "").strip()
    if not re.fullmatch(r"[0-9a-fA-F]{64}", seed_hex):
        print("No RUIN_RELEASE_SEED; the build carries no signed release notice.")
        return
    seed = bytes.fromhex(seed_hex)
    toc = open("RUIN_Core/RUIN_Core.toc", encoding="utf-8").read()
    version = re.search(r"^## Version:\s*(\S+)", toc, re.M).group(1)
    t = int(time.time())
    notes = highlights(version)
    msg = ("RUINR1|%s|%d|%s" % (version, t, "\n".join(notes))).encode("utf-8")
    sig = sign(seed, msg).hex()
    lines = ["-- RUIN Core: this release's signed notice (written by tools/release/notice.py at build time).",
             "local ADDON, ns = ...",
             "ns.RELEASE_NOTICE = { v = %s, t = %d, notes = { %s }, s = %s }" % (
                 lua_str(version), t, ", ".join(lua_str(n) for n in notes), lua_str(sig))]
    open("RUIN_Core/ReleaseNotice.lua", "w", encoding="utf-8").write("\n".join(lines) + "\n")
    print("Signed the release notice for", version, "with", len(notes), "highlights; public key", public(seed).hex())

if __name__ == "__main__":
    main()
