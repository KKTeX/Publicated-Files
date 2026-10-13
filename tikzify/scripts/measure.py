#!/usr/bin/env python3
"""Measure geometry in a reference image numerically, in the grid frame of grid.py
(cm, origin bottom-left).  Use it when eyeballing the overlay is not precise
enough: printed figures, PDF figures, anything drawn with a ruler.

Usage
  measure.py REF.png --width-cm W [--row Y]... [--col X]... [--circle X,Y,RMIN,RMAX]...
             [--ellipse X,Y,RMAX]... [--trace X0,X1,Y0,Y1]... [--bbox X0,Y0,X1,Y1]...
             [--mean X0,Y0,X1,Y1]... [--ink dark|gray|any] [--smooth S]
             [--min-width W] [--json]

  --row Y       centres (cm) of ink runs crossing the horizontal line y = Y
                -> x positions of vertical lines, ticks, plate ends ...
  --col X       same along the vertical line x = X -> y positions of horizontal
                lines.  A line is only seen where the scan line crosses it: use
                --row for vertical lines and --col for horizontal ones.
  --circle      robust least-squares circle through the ink inside the annulus
                around (X,Y) between RMIN and RMAX -> centre, radius, stroke.
                Keep the band narrow: text, crossing lines and concentric arcs
                inside it pull the fit (a warning is printed when the fit looks bad).
  --ellipse     axis-aligned ellipse through the ink within RMAX of (X,Y)
                (perspective circles: disks, cylinder ends) -> centre, rx, ry.
  --trace       follow a curve: for each column between X0 and X1, the centre of
                the ink run(s) between Y0 and Y1 -> list of (x, y).  Put the band
                around one curve only; fit a formula to the points afterwards.
  --bbox        bounding box of the ink inside the region -> where a label or a
                block of text sits (place \\node's from this, not by eye).
  --mean        mean gray level (0 = black, 1 = white) inside the region -> the
                fill value for halftone areas (e.g. 0.72 -> black!28).
  --ink         dark (< 90, default: black lines), gray (110..200: gray fills,
                thick gray rails), any (< 200)
  --smooth S    blur by S px before classifying.  Use 2-4 on halftone / screened
                scans so gray dots merge into areas instead of hundreds of runs.
  --min-width W drop runs thinner than W cm (default 0.01, about 1 px at 300 dpi).
                The number of dropped runs is reported.
  --json        print one JSON object instead of text.
REF.png must be the reference_image printed by grid.py (same --width-cm).
Needs numpy and ImageMagick 7.
"""
import argparse
import json
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from _common import check_path, floats, need, positive, run  # noqa: E402

try:
    import numpy as np
except ImportError:
    sys.exit("error: measure.py needs numpy (pip install numpy)")


def load(path, smooth=0):
    r = run(["magick", "identify", "-format", "%w %h", path + "[0]"])
    w, h = map(int, r.stdout.split())
    blur = ["-blur", f"0x{smooth}"] if smooth else []
    raw = run(["magick", path + "[0]", "-background", "white", "-alpha", "remove",
               "-colorspace", "Gray"] + blur + ["-depth", "8", "gray:-"], binary=True).stdout
    if len(raw) != w * h:
        sys.exit(f"error: could not read {path} as a single image")
    return np.frombuffer(raw, np.uint8).reshape(h, w).astype(int)


def runs(idx):
    out = []
    for i in idx:
        if out and i - out[-1][-1] <= 2:
            out[-1].append(i)
        else:
            out.append([i])
    return out


def r3(v):
    return round(float(v), 3)


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0],
                                 formatter_class=argparse.RawDescriptionHelpFormatter,
                                 epilog=__doc__.split("Usage", 1)[1])
    ap.add_argument("ref")
    ap.add_argument("--width-cm", type=float, required=True)
    ap.add_argument("--row", type=float, action="append", default=[], metavar="Y")
    ap.add_argument("--col", type=float, action="append", default=[], metavar="X")
    ap.add_argument("--circle", action="append", default=[], metavar="X,Y,RMIN,RMAX")
    ap.add_argument("--ellipse", action="append", default=[], metavar="X,Y,RMAX")
    ap.add_argument("--trace", action="append", default=[], metavar="X0,X1,Y0,Y1")
    ap.add_argument("--bbox", action="append", default=[], metavar="X0,Y0,X1,Y1")
    ap.add_argument("--mean", action="append", default=[], metavar="X0,Y0,X1,Y1")
    ap.add_argument("--ink", default="dark", choices=["dark", "gray", "any"])
    ap.add_argument("--smooth", type=float, default=0, metavar="S")
    ap.add_argument("--min-width", type=float, default=0.01, metavar="W")
    ap.add_argument("--json", action="store_true")
    a = ap.parse_args()

    need("magick")
    positive(a.width_cm, "--width-cm")
    if not os.path.isfile(a.ref):
        sys.exit(f"error: {a.ref} not found")
    check_path(a.ref, "REF")
    img = load(a.ref, a.smooth)
    H, W = img.shape
    ppc = W / a.width_cm
    ink = {"dark": img < 90, "gray": (img > 110) & (img < 200), "any": img < 200}[a.ink]
    res = {"width_cm": a.width_cm, "height_cm": r3(H / ppc), "px_per_cm": r3(ppc)}
    text = []
    f = lambda v: "%.3f" % v

    def px_row(y):
        return min(H - 1, max(0, int(H - y * ppc)))

    def px_col(x):
        return min(W - 1, max(0, int(x * ppc)))

    def box(spec, what):
        x0, y0, x1, y1 = floats(spec, 4, what)
        x0, x1 = sorted((x0, x1))
        y0, y1 = sorted((y0, y1))
        c0, c1 = px_col(x0), px_col(x1) + 1
        r0, r1 = px_row(y1), px_row(y0) + 1
        if c1 - c0 < 1 or r1 - r0 < 1:
            sys.exit(f"error: {what} {spec} is empty or outside the image")
        return c0, c1, r0, r1

    def scan(line, as_x):
        kept, dropped = [], 0
        for g in runs(np.nonzero(line)[0]):
            wcm = len(g) / ppc
            if wcm < a.min_width:
                dropped += 1
                continue
            c = np.mean(g) / ppc
            kept.append({"at": r3(c if as_x else H / ppc - c), "width": r3(wcm)})
        return kept, dropped

    for key, vals, as_x in (("row", a.row, True), ("col", a.col, False)):
        for v in vals:
            if (as_x and not 0 <= v <= H / ppc) or (not as_x and not 0 <= v <= W / ppc):
                text.append(f"{key} {v}: outside image")
                continue
            line = ink[px_row(v)] if as_x else ink[:, px_col(v)]
            kept, dropped = scan(line, as_x)
            res.setdefault(key, []).append({"at": v, "runs": kept, "dropped_thin": dropped})
            axis = "x" if as_x else "y"
            text.append(f"{key} {'y' if as_x else 'x'}={v}: "
                        + ", ".join(f"{axis}={f(k['at'])} (w {f(k['width'])})" for k in kept)
                        + (f"  [{dropped} runs thinner than --min-width dropped]" if dropped else ""))

    ys_all, xs_all = None, None

    def ink_points():
        nonlocal ys_all, xs_all
        if ys_all is None:
            ys, xs = np.nonzero(ink)
            xs_all, ys_all = xs / ppc, (H - ys) / ppc
        return xs_all, ys_all

    for spec in a.circle:
        cx, cy, r0, r1 = floats(spec, 4, "--circle")
        X, Y = ink_points()
        d0 = np.hypot(X - cx, Y - cy)
        m = (d0 >= r0) & (d0 <= r1)
        X, Y = X[m], Y[m]
        if len(X) < 20:
            text.append(f"circle {spec}: too few ink pixels in the band")
            continue
        n0 = len(X)
        for _ in range(3):
            A = np.c_[2 * X, 2 * Y, np.ones_like(X)]
            sol = np.linalg.lstsq(A, X ** 2 + Y ** 2, rcond=None)[0]
            ccx, ccy = sol[0], sol[1]
            R = math.sqrt(max(0.0, sol[2] + ccx ** 2 + ccy ** 2))
            d = np.hypot(X - ccx, Y - ccy)
            mad = np.median(np.abs(d - R)) or 1 / ppc
            keep = np.abs(d - R) < 2.5 * mad + 1 / ppc
            if keep.all() or keep.sum() < 20:
                break
            X, Y, d = X[keep], Y[keep], d[keep]
        stroke = np.percentile(d, 85) - np.percentile(d, 15)
        warn = []
        if stroke > 0.15 * R or stroke > 0.12:
            warn.append("stroke much thicker than a line: the band probably holds no single circle")
        if len(X) < 0.5 * n0:
            warn.append(f"only {len(X)}/{n0} band pixels fit: text or crossing lines in the band?")
        if not r0 <= R <= r1:
            warn.append("fitted radius lies outside the band")
        res.setdefault("circle", []).append({"spec": spec, "centre": [r3(ccx), r3(ccy)], "r": r3(R),
                                             "stroke": r3(stroke), "pixels": int(len(X)),
                                             "warnings": warn})
        text.append(f"circle {spec}: centre ({f(ccx)},{f(ccy)}) r={f(R)} stroke ~{f(stroke)} cm, "
                    f"{len(X)} px used" + "".join(f"\n  WARNING: {w}" for w in warn))

    for spec in a.ellipse:
        cx, cy, rmax = floats(spec, 3, "--ellipse")
        X, Y = ink_points()
        m = np.hypot(X - cx, Y - cy) <= rmax
        X, Y = X[m], Y[m]
        if len(X) < 20:
            text.append(f"ellipse {spec}: too few ink pixels")
            continue
        # axis-aligned conic A u^2 + C v^2 + D u + E v + F = 0 around (cx, cy),
        # solved as the null vector of the design matrix (SVD).
        U, V = X - cx, Y - cy
        M = np.c_[U ** 2, V ** 2, U, V, np.ones_like(U)]
        Aq, Cq, Dq, Eq, Fq = np.linalg.svd(M, full_matrices=False)[2][-1]
        if Aq < 0:
            Aq, Cq, Dq, Eq, Fq = -Aq, -Cq, -Dq, -Eq, -Fq
        k = Dq ** 2 / (4 * Aq) + Eq ** 2 / (4 * Cq) - Fq if Aq > 0 and Cq > 0 else -1
        if k <= 0:
            text.append(f"ellipse {spec}: no ellipse fits (lines or text inside RMAX?)")
            continue
        ex, ey = cx - Dq / (2 * Aq), cy - Eq / (2 * Cq)
        rx, ry = math.sqrt(k / Aq), math.sqrt(k / Cq)
        res.setdefault("ellipse", []).append({"spec": spec, "centre": [r3(ex), r3(ey)],
                                              "rx": r3(rx), "ry": r3(ry)})
        text.append(f"ellipse {spec}: centre ({f(ex)},{f(ey)}) rx={f(rx)} ry={f(ry)}")

    for spec in a.trace:
        x0, x1, y0, y1 = floats(spec, 4, "--trace")
        x0, x1 = sorted((x0, x1))
        y0, y1 = sorted((y0, y1))
        pts = []
        for c in range(px_col(x0), px_col(x1) + 1, max(1, int(ppc * 0.05))):
            r_top, r_bot = px_row(y1), px_row(y0)
            col = ink[r_top:r_bot + 1, c]
            g = runs(np.nonzero(col)[0])
            if g:
                best = max(g, key=len)
                pts.append([r3(c / ppc), r3((H - (r_top + np.mean(best))) / ppc)])
        res.setdefault("trace", []).append({"spec": spec, "points": pts})
        text.append(f"trace {spec}: {len(pts)} points  "
                    + " ".join(f"({p[0]},{p[1]})" for p in pts))

    for spec in a.bbox:
        c0, c1, r0, r1 = box(spec, "--bbox")
        ys, xs = np.nonzero(ink[r0:r1, c0:c1])
        if not len(xs):
            text.append(f"bbox {spec}: no ink")
            continue
        bx0, bx1 = (c0 + xs.min()) / ppc, (c0 + xs.max() + 1) / ppc
        by0, by1 = (H - (r0 + ys.max() + 1)) / ppc, (H - (r0 + ys.min())) / ppc
        res.setdefault("bbox", []).append({"spec": spec, "box": [r3(bx0), r3(by0), r3(bx1), r3(by1)],
                                           "centre": [r3((bx0 + bx1) / 2), r3((by0 + by1) / 2)]})
        text.append(f"bbox {spec}: ({f(bx0)},{f(by0)}) -- ({f(bx1)},{f(by1)}), "
                    f"centre ({f((bx0 + bx1) / 2)},{f((by0 + by1) / 2)})")

    for spec in a.mean:
        c0, c1, r0, r1 = box(spec, "--mean")
        mv = float(img[r0:r1, c0:c1].mean()) / 255
        res.setdefault("mean", []).append({"spec": spec, "gray": r3(mv),
                                           "tikz": f"black!{round((1 - mv) * 100)}"})
        text.append(f"mean {spec}: gray {mv:.3f} -> fill=black!{round((1 - mv) * 100)}")

    if a.json:
        print(json.dumps(res, ensure_ascii=False))
    else:
        print("\n".join(text))


if __name__ == "__main__":
    main()
