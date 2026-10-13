#!/usr/bin/env python3
"""Turn vector sources (SVG, PDF, EPS) into a *raw* TikZ draft in cm, y-up.

The draft is exact geometry, not a finished figure: use it as the coordinate
source, then rewrite it semantically (nodes, styles, named coordinates) as
described in SKILL.md.  Text in PDFs is recovered as \\node's from
pdftotext -bbox instead of glyph outlines.

Usage
  svg2tikz.py INPUT.{svg,pdf,eps} [--page 1] [--crop X,Y,W,H] [--width-cm 12] [--digits 2] [-o OUT.tikz]

  Supported: path (all commands incl. arcs), rect (rounded), circle, ellipse, line,
  polyline, polygon, text (tspan positions are ignored), use/symbol, nested
  transforms, fill/stroke/width/dash/opacity from attributes, inline style and
  simple <style> rules (.class / #id / tag).  Ignored: gradients, clip paths,
  masks, filters, markers.  Elements with display:none are skipped.

  --crop      keep only this region, in source user units with a top-left origin
              (pt for PDF: read them off `pdftoppm -r 72 -png`, where 1 px = 1 pt).
              Elements entirely outside are dropped; the region's corner becomes (0,0).

  --width-cm  rescale so the drawing is this wide (default: keep real size).
Python 3.7+, stdlib only; PDF needs poppler (pdftocairo, pdftotext), EPS also
Ghostscript.  All extracted text is TeX-escaped, so a malicious file cannot
inject TeX code.
"""
import argparse
import html
import math
import os
import re
import sys
import tempfile
import xml.etree.ElementTree as ET

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from _common import floats, need, positive, tex_escape, write_text  # noqa: E402
from _common import run as _run  # noqa: E402

MAX_ELEMENTS = 200000
CSS = {}          # selector ('.cls', '#id', 'tag') -> {prop: value}

UNIT_CM = {"": 2.54 / 96, "px": 2.54 / 96, "pt": 2.54 / 72, "pc": 2.54 / 6,
           "mm": 0.1, "cm": 1.0, "in": 2.54}
NUM = r"[-+]?(?:\d*\.\d+|\d+\.?)(?:[eE][-+]?\d+)?"


def num(v, default=0.0):
    m = re.search(NUM, v or "")
    return float(m.group()) if m else default


def length_cm(v):
    m = re.fullmatch(r"\s*(%s)\s*([a-z%%]*)\s*" % NUM, v or "")
    if not m or m.group(2) == "%":
        return None
    return float(m.group(1)) * UNIT_CM.get(m.group(2), UNIT_CM[""])


# ---------- affine matrices (a b c d e f) as in SVG ----------
def mul(m, n):
    a, b, c, d, e, f = m
    A, B, C, D, E, F = n
    return (a * A + c * B, b * A + d * B, a * C + c * D, b * C + d * D,
            a * E + c * F + e, b * E + d * F + f)


def parse_transform(s):
    m = (1, 0, 0, 1, 0, 0)
    for fn, args in re.findall(r"(\w+)\s*\(([^)]*)\)", s or ""):
        v = [float(x) for x in re.findall(NUM, args)]
        if fn == "matrix":
            t = tuple(v)
        elif fn == "translate":
            t = (1, 0, 0, 1, v[0], v[1] if len(v) > 1 else 0)
        elif fn == "scale":
            t = (v[0], 0, 0, v[1] if len(v) > 1 else v[0], 0, 0)
        elif fn == "rotate":
            r = math.radians(v[0])
            t = (math.cos(r), math.sin(r), -math.sin(r), math.cos(r), 0, 0)
            if len(v) == 3:
                t = mul(mul((1, 0, 0, 1, v[1], v[2]), t), (1, 0, 0, 1, -v[1], -v[2]))
        elif fn == "skewX":
            t = (1, 0, math.tan(math.radians(v[0])), 1, 0, 0)
        elif fn == "skewY":
            t = (1, math.tan(math.radians(v[0])), 0, 1, 0, 0)
        else:
            continue
        m = mul(m, t)
    return m


def apply(m, x, y):
    a, b, c, d, e, f = m
    return a * x + c * y + e, b * x + d * y + f


# ---------- path data -> list of (cmd, points) with absolute cubic curves ----------
def arc_to_cubics(x1, y1, rx, ry, phi, fa, fs, x2, y2):
    if (x1, y1) == (x2, y2):
        return []                      # SVG spec: zero-length arc is omitted
    if rx == 0 or ry == 0:
        return [((x2, y2),)]
    phi = math.radians(phi)
    cp, sp = math.cos(phi), math.sin(phi)
    dx, dy = (x1 - x2) / 2, (y1 - y2) / 2
    x1p, y1p = cp * dx + sp * dy, -sp * dx + cp * dy
    rx, ry = abs(rx), abs(ry)
    lam = x1p ** 2 / rx ** 2 + y1p ** 2 / ry ** 2
    if lam > 1:
        rx, ry = rx * math.sqrt(lam), ry * math.sqrt(lam)
    num = rx ** 2 * ry ** 2 - rx ** 2 * y1p ** 2 - ry ** 2 * x1p ** 2
    den = rx ** 2 * y1p ** 2 + ry ** 2 * x1p ** 2
    co = math.sqrt(max(0, num / den)) * (-1 if fa == fs else 1) if den else 0.0
    cxp, cyp = co * rx * y1p / ry, -co * ry * x1p / rx
    cx = cp * cxp - sp * cyp + (x1 + x2) / 2
    cy = sp * cxp + cp * cyp + (y1 + y2) / 2

    def ang(ux, uy, vx, vy):
        a = math.atan2(ux * vy - uy * vx, ux * vx + uy * vy)
        return a

    t1 = ang(1, 0, (x1p - cxp) / rx, (y1p - cyp) / ry)
    dt = ang((x1p - cxp) / rx, (y1p - cyp) / ry, (-x1p - cxp) / rx, (-y1p - cyp) / ry)
    if not fs and dt > 0:
        dt -= 2 * math.pi
    elif fs and dt < 0:
        dt += 2 * math.pi
    n = max(1, math.ceil(abs(dt) / (math.pi / 2) - 1e-9))
    d = dt / n
    k = 4 / 3 * math.tan(d / 4)
    out = []

    def pt(t):
        return (cx + rx * math.cos(t) * cp - ry * math.sin(t) * sp,
                cy + rx * math.cos(t) * sp + ry * math.sin(t) * cp)

    def dpt(t):
        return (-rx * math.sin(t) * cp - ry * math.cos(t) * sp,
                -rx * math.sin(t) * sp + ry * math.cos(t) * cp)

    for i in range(n):
        a0, a1 = t1 + i * d, t1 + (i + 1) * d
        p0, p3 = pt(a0), pt(a1)
        d0, d1 = dpt(a0), dpt(a1)
        out.append(((p0[0] + k * d0[0], p0[1] + k * d0[1]),
                    (p3[0] - k * d1[0], p3[1] - k * d1[1]), p3))
    return out


NUM_RE = re.compile(NUM)


def path_tokens(d):
    """Tokenise path data.  Arc flags are single characters and may be written
    without separators (a20 20 0 1040 0), so they are read one char at a time."""
    out, i, cmd, argn = [], 0, None, 0
    while i < len(d):
        ch = d[i]
        if ch in " ,\t\n\r\f":
            i += 1
            continue
        if ch in "MmLlHhVvCcSsQqTtAaZz":
            out.append(ch)
            cmd, argn = ch, 0
            i += 1
            continue
        if cmd in ("A", "a") and argn % 7 in (3, 4) and ch in "01":
            out.append(ch)
            argn += 1
            i += 1
            continue
        m = NUM_RE.match(d, i)
        if not m:
            break                      # garbage: keep what was parsed so far
        out.append(m.group())
        argn += 1
        i = m.end()
    return out


class _Truncated(Exception):
    pass


def parse_path(d):
    try:
        return _parse_path(d)
    except _Truncated as e:
        return e.args[0]


def _parse_path(d):
    toks = path_tokens(d)
    i, cmd = 0, None
    cur = start = (0.0, 0.0)
    last_c = last_q = None
    segs = []  # ('M',p) ('L',p) ('C',c1,c2,p) ('Z',)

    def nums(k):
        nonlocal i
        chunk = toks[i:i + k]
        if len(chunk) < k or any(t.isalpha() for t in chunk):
            raise _Truncated(segs)
        i += k
        return [float(t) for t in chunk]

    while i < len(toks):
        if re.fullmatch(r"[A-Za-z]", toks[i]):
            cmd = toks[i]
            i += 1
            if cmd in "Zz":
                segs.append(("Z",))
                cur = start
                last_c = last_q = None
                continue
        if cmd is None:
            break
        rel = cmd.islower()
        C = cmd.upper()
        ox, oy = cur if rel else (0, 0)
        if C == "M":
            x, y = nums(2)
            cur = start = (ox + x, oy + y)
            segs.append(("M", cur))
            cmd = "l" if rel else "L"
            last_c = last_q = None
        elif C == "L":
            x, y = nums(2)
            cur = (ox + x, oy + y)
            segs.append(("L", cur))
            last_c = last_q = None
        elif C == "H":
            (x,) = nums(1)
            cur = ((cur[0] if rel else 0) + x, cur[1])
            segs.append(("L", cur))
            last_c = last_q = None
        elif C == "V":
            (y,) = nums(1)
            cur = (cur[0], (cur[1] if rel else 0) + y)
            segs.append(("L", cur))
            last_c = last_q = None
        elif C in "CS":
            if C == "C":
                v = nums(6)
                c1 = (ox + v[0], oy + v[1])
                v = v[2:]
            else:
                v = nums(4)
                c1 = (2 * cur[0] - last_c[0], 2 * cur[1] - last_c[1]) if last_c else cur
            c2, p = (ox + v[0], oy + v[1]), (ox + v[2], oy + v[3])
            segs.append(("C", c1, c2, p))
            last_c, last_q, cur = c2, None, p
        elif C in "QT":
            if C == "Q":
                v = nums(4)
                q = (ox + v[0], oy + v[1])
                v = v[2:]
            else:
                v = nums(2)
                q = (2 * cur[0] - last_q[0], 2 * cur[1] - last_q[1]) if last_q else cur
            p = (ox + v[0], oy + v[1])
            c1 = (cur[0] + 2 / 3 * (q[0] - cur[0]), cur[1] + 2 / 3 * (q[1] - cur[1]))
            c2 = (p[0] + 2 / 3 * (q[0] - p[0]), p[1] + 2 / 3 * (q[1] - p[1]))
            segs.append(("C", c1, c2, p))
            last_q, last_c, cur = q, None, p
        elif C == "A":
            rx, ry, ph, fa, fs, x, y = nums(7)
            p = (ox + x, oy + y)
            for seg in arc_to_cubics(cur[0], cur[1], rx, ry, ph, int(fa), int(fs), *p):
                segs.append(("L", seg[0]) if len(seg) == 1 else ("C",) + seg)
            cur = p
            last_c = last_q = None
        else:
            i += 1
    return segs


# ---------- style ----------
NAMED = {"black": (0, 0, 0), "white": (255, 255, 255), "red": (255, 0, 0),
         "green": (0, 128, 0), "blue": (0, 0, 255), "gray": (128, 128, 128),
         "grey": (128, 128, 128), "yellow": (255, 255, 0), "orange": (255, 165, 0)}


def parse_color(v):
    if not v or v in ("none", "transparent"):
        return None
    v = v.strip()
    if v.startswith("#"):
        h = v[1:]
        if len(h) in (3, 4):
            h = "".join(c * 2 for c in h[:3])
        try:
            return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))
        except ValueError:
            return (0, 0, 0)
    m = re.fullmatch(r"rgb\(\s*([\d.]+)(%?)\s*,\s*([\d.]+)%?\s*,\s*([\d.]+)%?\s*\)", v)
    if m:
        f = 2.55 if m.group(2) else 1
        return tuple(round(float(m.group(i)) * f) for i in (1, 3, 4))
    return NAMED.get(v.lower(), (0, 0, 0))


STYLE_KEYS = ("fill", "stroke", "stroke-width", "stroke-dasharray", "opacity",
              "fill-opacity", "stroke-opacity", "font-size", "fill-rule", "display")


def parse_decls(text):
    st = {}
    for part in (text or "").split(";"):
        if ":" in part:
            k, v = part.split(":", 1)
            if k.strip() in STYLE_KEYS:
                st[k.strip()] = v.replace("!important", "").strip()
    return st


def load_css(root):
    """Simple <style> rules: .class, #id and tag selectors (comma lists ok)."""
    for el in root.iter():
        if el.tag.split("}")[-1] != "style" or not el.text:
            continue
        text = re.sub(r"/\*.*?\*/", "", el.text, flags=re.S)
        for sels, body in re.findall(r"([^{}]+)\{([^{}]*)\}", text):
            decls = parse_decls(body)
            for sel in sels.split(","):
                sel = sel.strip()
                if re.fullmatch(r"[.#]?[A-Za-z_][\w-]*", sel):
                    CSS.setdefault(sel, {}).update(decls)


def own_style(el):
    # precedence: presentation attributes < <style> rules < inline style
    st = {k: el.get(k) for k in STYLE_KEYS if el.get(k) is not None}
    st.update(CSS.get(el.tag.split("}")[-1], {}))
    for cls in (el.get("class") or "").split():
        st.update(CSS.get("." + cls, {}))
    if el.get("id"):
        st.update(CSS.get("#" + el.get("id"), {}))
    st.update(parse_decls(el.get("style")))
    return st


def fmtnum(v, digits=2):
    t = ("%%.%df" % digits % v).rstrip("0").rstrip(".")
    return "0" if t in ("", "-0", "0", "-") else t


def fmtpt(v):
    return fmtnum(v, 2) + "pt"


class Emitter:
    def __init__(self, to_cm, scale, digits, crop=None):
        self.to_cm, self.scale, self.dg, self.crop = to_cm, scale, digits, crop
        self.colors, self.lines = {}, []

    def c(self, p):
        x, y = self.to_cm(p)
        return "(%s,%s)" % (fmtnum(x, self.dg), fmtnum(y, self.dg))

    def color(self, rgb):
        if rgb == (0, 0, 0):
            return "black"
        if rgb == (255, 255, 255):
            return "white"
        if rgb not in self.colors:
            self.colors[rgb] = "c%d" % (len(self.colors) + 1)
        return self.colors[rgb]

    def opts(self, st, m):
        o = []
        fill, stroke = parse_color(st.get("fill", "black")), parse_color(st.get("stroke"))
        if stroke:
            o.append("draw=" + self.color(stroke))
            w = num(st.get("stroke-width"), 1.0)
            lin = math.sqrt(abs(m[0] * m[3] - m[1] * m[2]))
            pt = w * lin * self.scale / 2.54 * 72.27
            if abs(pt - 0.4) > 0.05:
                o.append("line width=" + fmtpt(pt))
            da = st.get("stroke-dasharray")
            if da and da != "none":
                v = [float(x) * lin * self.scale / 2.54 * 72.27 for x in re.findall(NUM, da)]
                if len(v) % 2:
                    v *= 2
                o.append("dash pattern=" + " ".join(
                    "%s %s" % ("on" if k % 2 == 0 else "off", fmtpt(x)) for k, x in enumerate(v)))
        if fill:
            o.append("fill=" + self.color(fill))
        if st.get("_extra"):
            o.append(st["_extra"])
        if st.get("fill-rule") == "evenodd" and fill:
            o.append("even odd rule")
        for k, key in (("opacity", "opacity"), ("fill-opacity", "fill opacity"),
                       ("stroke-opacity", "draw opacity")):
            if k in st:
                v = max(0.0, min(1.0, num(st[k], 1.0)))
                if v < 1:
                    o.append("%s=%s" % (key, fmtnum(v, 3)))
        return o

    def outside(self, pts):
        if not self.crop or not pts:
            return False
        x, y, w, h = self.crop
        xs, ys = [p[0] for p in pts], [p[1] for p in pts]
        return max(xs) < x or min(xs) > x + w or max(ys) < y or min(ys) > y + h

    def add(self, line):
        if len(self.lines) >= MAX_ELEMENTS:
            sys.exit(f"error: more than {MAX_ELEMENTS} elements; the file is too large or "
                     "self-referencing (use --crop to convert a part)")
        self.lines.append(line)

    def path(self, segs, st, m):
        o = self.opts(st, m)
        if not o or self.outside([apply(m, *p) for s in segs for p in s[1:]]):
            return
        while segs and segs[-1][0] == "M":   # dangling moveto after closepath
            segs = segs[:-1]
        parts = []
        for s in segs:
            if s[0] == "M":
                parts.append(self.c(apply(m, *s[1])))
            elif s[0] == "L":
                parts.append("-- " + self.c(apply(m, *s[1])))
            elif s[0] == "C":
                parts.append(".. controls %s and %s .. %s" % tuple(self.c(apply(m, *p)) for p in s[1:]))
            elif s[0] == "Z":
                parts.append("-- cycle")
        if parts:
            self.add("\\path[%s] %s;" % (",".join(o), " ".join(parts)))

    def text(self, p, s, size_pt, anchor="base west"):
        if self.outside([p]):
            return
        s = tex_escape(s)
        fs = "" if not size_pt or abs(size_pt - 10) < 1.5 else \
            ",font=\\fontsize{%s}{%s}\\selectfont" % (fmtnum(size_pt, 1), fmtnum(size_pt * 1.2, 1))
        self.add("\\node[anchor=%s,inner sep=0pt%s] at %s {%s};" % (anchor, fs, self.c(p), s))


def walk(el, m, st, em, ids, skip_glyphs, depth=0, active=frozenset()):
    tag = el.tag.split("}")[-1]
    if tag in ("defs", "clipPath", "mask", "symbol", "metadata", "title", "desc", "style",
               "linearGradient", "radialGradient", "pattern", "marker", "filter"):
        return
    if depth > 200:
        return
    m = mul(m, parse_transform(el.get("transform")))
    st = {**st, **own_style(el)}
    if st.get("display", "").strip() == "none":
        return
    g = lambda k, dflt=0.0: num(el.get(k), dflt)
    if tag in ("svg", "g", "a", "switch"):
        if depth and tag == "svg":
            m = mul(m, (1, 0, 0, 1, g("x"), g("y")))
        for ch in el:
            walk(ch, m, st, em, ids, skip_glyphs, depth + 1, active)
    elif tag == "use":
        ref = (el.get("{http://www.w3.org/1999/xlink}href") or el.get("href") or "").lstrip("#")
        if skip_glyphs and ref.startswith("glyph"):
            return
        tgt = ids.get(ref)
        if tgt is not None and ref not in active:          # skip reference cycles
            m2 = mul(m, (1, 0, 0, 1, g("x"), g("y")))
            act = active | {ref}
            if tgt.tag.split("}")[-1] == "symbol":
                for ch in tgt:
                    walk(ch, m2, st, em, ids, skip_glyphs, depth + 1, act)
            else:
                walk(tgt, m2, st, em, ids, skip_glyphs, depth + 1, act)
    elif tag == "path":
        em.path(parse_path(el.get("d", "")), st, m)
    elif tag == "rect":
        x, y, w, h = g("x"), g("y"), g("width"), g("height")
        rx = g("rx") or g("ry")
        if rx:
            lin = math.sqrt(abs(m[0] * m[3] - m[1] * m[2]))
            st = {**st, "_extra": "rounded corners=%.2gpt" % (rx * lin * em.scale / 2.54 * 72.27)}
        em.path([("M", (x, y)), ("L", (x + w, y)), ("L", (x + w, y + h)), ("L", (x, y + h)), ("Z",)], st, m)
    elif tag in ("circle", "ellipse"):
        cx, cy = g("cx"), g("cy")
        rx = g("r") if tag == "circle" else g("rx")
        ry = g("r") if tag == "circle" else g("ry")
        if rx <= 0 or ry <= 0:
            return
        segs = [("M", (cx + rx, cy))]
        segs += [("C",) + s for s in arc_to_cubics(cx + rx, cy, rx, ry, 0, 0, 1, cx - rx, cy)]
        segs += [("C",) + s for s in arc_to_cubics(cx - rx, cy, rx, ry, 0, 0, 1, cx + rx, cy)]
        em.path(segs + [("Z",)], st, m)
    elif tag == "line":
        em.path([("M", (g("x1"), g("y1"))), ("L", (g("x2"), g("y2")))], {**st, "fill": "none"}, m)
    elif tag in ("polyline", "polygon"):
        v = [float(x) for x in re.findall(NUM, el.get("points", ""))]
        pts = list(zip(v[::2], v[1::2]))
        if pts:
            segs = [("M", pts[0])] + [("L", p) for p in pts[1:]]
            if tag == "polygon":
                segs.append(("Z",))
            else:
                st = {**st, "fill": st.get("fill", "none") if "fill" in own_style(el) else "none"}
            em.path(segs, st, m)
    elif tag == "image":
        w, h = g("width"), g("height")
        pts = [apply(m, x, y) for x, y in ((0, 0), (w, 0), (0, h), (w, h))]
        if not em.outside(pts):
            xs, ys = [p[0] for p in pts], [p[1] for p in pts]
            ll, ur = em.c((min(xs), max(ys))), em.c((max(xs), min(ys)))
            em.add("%% raster image %dx%d px placed at %s -- %s (cm): trace it with "
                            "grid.py (extract: pdfimages -png); its lower-left %s is the grid origin"
                            % (w, h, ll, ur, ll))
    elif tag == "text":
        s = "".join(el.itertext()).strip()
        if s:
            fs = st.get("font-size")
            lin = math.sqrt(abs(m[0] * m[3] - m[1] * m[2]))
            size = num(fs, 0) * lin * em.scale / 2.54 * 72.27 if fs else None
            anchor = {"middle": "base", "end": "base east"}.get(el.get("text-anchor"), "base west")
            em.text(apply(m, g("x"), g("y")), s, size, anchor)   # ElementTree already decoded entities


def pdf_words(pdf, page):
    r = _run(["pdftotext", "-f", str(page), "-l", str(page), "-bbox-layout", pdf, "-"], check=False)
    out = []
    for line in re.findall(r"<line[^>]*>(.*?)</line>", r.stdout, re.S):
        words = re.findall(r'<word xMin="([\d.]+)" yMin="([\d.]+)" xMax="([\d.]+)" yMax="([\d.]+)">(.*?)</word>', line)
        if not words:
            continue
        x0 = min(float(w[0]) for w in words)
        y1 = max(float(w[3]) for w in words)
        y0 = min(float(w[1]) for w in words)
        text = " ".join(html.unescape(w[4]) for w in words)
        # CJK glyph boxes are ~1 em tall; Latin boxes include ascender+descender (~1.25 em)
        em_h = (y1 - y0) / (1.0 if re.search(r"[\u3000-\u9fff\uff00-\uffef]", text) else 1.25)
        out.append((x0, y1 - (y1 - y0) * 0.22, text, em_h))
    return out


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0],
                                 formatter_class=argparse.RawDescriptionHelpFormatter,
                                 epilog=__doc__.split("Usage", 1)[1])
    ap.add_argument("input")
    ap.add_argument("--page", type=int, default=1)
    ap.add_argument("--width-cm", type=float)
    ap.add_argument("--crop")
    ap.add_argument("--digits", type=int, default=2)
    ap.add_argument("-o", "--out")
    a = ap.parse_args()

    src = os.path.abspath(a.input)
    if not os.path.isfile(src):
        sys.exit(f"error: {a.input} not found")
    if a.width_cm is not None:
        positive(a.width_cm, "--width-cm")
    if a.page < 1:
        sys.exit("error: --page starts at 1")
    ext = os.path.splitext(src)[1].lower()
    with tempfile.TemporaryDirectory(prefix="svg2tikz-") as tmp:
        words = []
        if ext in (".eps", ".ps"):
            need("gs")
            pdf = os.path.join(tmp, "in.pdf")
            _run(["gs", "-q", "-dNOPAUSE", "-dBATCH", "-dSAFER", "-dEPSCrop", "-sDEVICE=pdfwrite",
                  "-o", pdf, src])
            src, ext = pdf, ".pdf"
        if ext == ".pdf":
            need("pdftocairo", "pdftotext")
            svg = os.path.join(tmp, "in.svg")
            _run(["pdftocairo", "-svg", "-f", str(a.page), "-l", str(a.page), src, svg])
            words = pdf_words(src, a.page)
            src = svg
        try:
            root = ET.parse(src).getroot()
        except ET.ParseError as e:
            sys.exit(f"error: cannot parse SVG: {e}")
    load_css(root)
    ids = {el.get("id"): el for el in root.iter() if el.get("id")}
    vb = [float(x) for x in re.findall(NUM, root.get("viewBox") or "")]
    wcm = length_cm(root.get("width"))
    hcm = length_cm(root.get("height"))
    if len(vb) == 4 and vb[2] > 0 and vb[3] > 0:
        vx, vy, vw, vh = vb
        unit = (wcm / vw) if wcm else UNIT_CM[""]
    else:
        unit = UNIT_CM[""]
        vx = vy = 0
        vw = (wcm or 0) / unit
        vh = (hcm or 0) / unit
    crop = None
    if a.crop:
        crop = tuple(floats(a.crop, 4, "--crop"))
        if crop[2] <= 0 or crop[3] <= 0:
            sys.exit("error: --crop width and height must be > 0")
        vx, vy, vw, vh = crop
    if vw <= 0 or vh <= 0:
        sys.exit("error: cannot determine the drawing size (no usable width/height/viewBox); "
                 "pass --crop X,Y,W,H")
    if a.width_cm:
        unit = a.width_cm / vw
    H = vh * unit

    em = Emitter(lambda p: ((p[0] - vx) * unit, H - (p[1] - vy) * unit), unit, a.digits, crop)
    walk(root, (1, 0, 0, 1, 0, 0), {}, em, ids, skip_glyphs=bool(words))
    # pdftotext reports pt in the page frame, the same user units as pdftocairo's svg.
    for x, y, txt, size in words:
        em.text((x, y), txt, size * unit / 2.54 * 72.27)

    out = ["% raw draft from " + tex_escape(os.path.basename(a.input)).replace("\n", " ")
           + " -- rewrite semantically before use",
           "\\begin{tikzpicture}"]
    out += ["  \\definecolor{%s}{RGB}{%d,%d,%d}" % ((n,) + rgb) for rgb, n in em.colors.items()]
    out += ["  " + l for l in em.lines]
    out.append("\\end{tikzpicture}")
    text = "\n".join(out) + "\n"
    if a.out:
        write_text(a.out, text)
        print(f"wrote {a.out}: {len(em.lines)} elements, {len(em.colors)} colours, "
              f"{vw * unit:.2f} x {H:.2f} cm", file=sys.stderr)
    else:
        sys.stdout.write(text)


if __name__ == "__main__":
    main()
