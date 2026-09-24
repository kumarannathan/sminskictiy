#!/usr/bin/env python3
"""Block-balance check for Luau files (no interpreter on this machine).
Tokenises properly: strings and comments are skipped in one pass, so a "--"
inside a string or a quote inside a comment cannot confuse it."""
import sys, re

def strip(src):
    out, i, n = [], 0, len(src)
    while i < n:
        c = src[i]
        if src.startswith("--[[", i):
            j = src.find("]]", i); i = n if j < 0 else j + 2
        elif src.startswith("--", i):
            j = src.find("\n", i); i = n if j < 0 else j
        elif c in "\"'":
            q = c; i += 1
            while i < n and src[i] != q:
                i += 2 if src[i] == "\\" else 1
            i += 1; out.append('""')
        elif src.startswith("[[", i):
            j = src.find("]]", i); i = n if j < 0 else j + 2; out.append('""')
        else:
            out.append(c); i += 1
    return "".join(out)

def depth(src):
    d, prev = 0, None
    for t in re.findall(r"\b(function|if|for|while|repeat|do|end|until)\b", strip(src)):
        if t in ("function", "if", "repeat", "for", "while"): d += 1
        elif t == "do" and prev not in ("for", "while"): d += 1
        elif t in ("end", "until"): d -= 1
        prev = t
    return d

bad = 0
for f in sys.argv[1:]:
    d = depth(open(f).read())
    print(f"{f:40} {'ok' if d == 0 else 'UNBALANCED (%+d)' % d}")
    bad += d != 0
sys.exit(1 if bad else 0)
