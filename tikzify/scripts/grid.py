#!/usr/bin/env python3
"""Overlay a labelled TikZ coordinate grid on a raster figure.

The grid is expressed in TikZ units (cm by default): origin at the bottom-left
of the image, x to the right, y upward -- exactly the frame you write the
tikzpicture in.  Reading coordinates off this image replaces guessing.

Usage:
  grid.py IMAGE [--width-cm 12 | --dpi 300] [--step 0.5] [--clean [--no-autocrop]]
          [--crop WxH+X+Y] [--mask X0,Y0,X1,Y1]... [--frame X0,Y0,X1,Y1]
          [--zoom X0,Y0,X1,Y1] [-o OUT]

  --width-cm  physical width the whole image should map to (= intended figure
              width in the document).  Height follows the aspect ratio.
  --dpi       instead of --width-cm, for scans whose resolution is known: keep the
              printed size (width_cm = pixels / dpi * 2.54).
  --step      minor grid step in cm (major lines every 1 cm get labels).
  --clean     grayscale + normalise + deskew + background flattening.  Use for
              phone photos of paper / whiteboards.  The cleaned image is also
              written next to OUT as *-clean.png and should be passed to
              build.py --ref.
  --frame     X0,Y0,X1,Y1 in the grid cm of a previous run (same --width-cm):
              keep only this part (cut away paper edges, desk, unrelated notes).
              Scale is kept; the frame's lower-left corner becomes the new origin
              and the printed width_cm is what build.py --ref-width-cm needs.
  --mask      X0,Y0,X1,Y1 (cm, same frame as --frame): paint the region white, e.g.
              a caption that sits beside part of the figure.  Repeatable.  Applied
              before --frame, in the coordinates of the unframed grid.
  --zoom      crop to a region given in grid cm (x0,y0,x1,y1) and upscale it,
              keeping the *global* labels.  For reading small details.  Give it the
              same IMAGE/--frame/--mask as the run whose coordinates you use.
  --crop      WxH+X+Y in source pixels, applied first (desk, page edges).
  -o OUT      grid image to write.  Default: work/IMAGE-grid.png next to IMAGE.
              Working images (-src, -clean, -framed, -up, -zoomsrc) go next to OUT;
              files there that this script did not create are never overwritten.

Prints the mapping (px <-> cm) so it can be reused in build.py --ref.
Requires ImageMagick 7 (`magick`).  Python 3.7+, stdlib only.
"""
import argparse
import json
import math
import os
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from _common import check_path, floats, need, positive, read_text, write_text  # noqa: E402
from _common import run as _run  # noqa: E402

FONT_CANDIDATES = [
    "/System/Library/Fonts/Helvetica.ttc",
    "/System/Library/Fonts/Supplemental/Arial.ttf",
    "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
    "/usr/share/fonts/TTF/DejaVuSans.ttf",
    "/usr/share/fonts/dejavu/DejaVuSans.ttf",
    "/usr/share/fonts/truetype/liberation/LiberationSans-Regular.ttf",
    "C:/Windows/Fonts/arial.ttf",
]
MANIFEST = ".tikzify-grid-files"


def run(cmd):
    return _run(cmd).stdout


def size_of(path):
    w, h = run(["magick", "identify", "-format", "%w %h", path + "[0]"]).split()
    return int(w), int(h)


def font():
    for f in FONT_CANDIDATES:
        if os.path.exists(f):
            return f
    return None


def paper_box(path, probe=320, tol=0.03):
    """Largest inner rectangle free of dark border bands (desk, shadow,
    rotation wedges): peel the darkest edge row/column until every edge is
    at most `tol` dark.  Returns (w, h, x, y) in pixels of `path`."""
    W, H = size_of(path)
    raw = subprocess.run(["magick", path, "-resize", f"{probe}x{probe}", "-colorspace",
                          "Gray", "-blur", "0x1.5", "-threshold", "88%", "-depth", "8", "gray:-"],
                         capture_output=True).stdout
    w, h = map(int, run(["magick", path, "-resize", f"{probe}x{probe}",
                         "-format", "%w %h", "info:"]).split())
    if len(raw) != w * h:
        return None
    dark = [[raw[r * w + c] < 128 for c in range(w)] for r in range(h)]
    t, b, l, rt = 0, h - 1, 0, w - 1
    while t < b and l < rt:
        edges = {
            "t": sum(dark[t][l:rt + 1]) / (rt - l + 1),
            "b": sum(dark[b][l:rt + 1]) / (rt - l + 1),
            "l": sum(dark[r][l] for r in range(t, b + 1)) / (b - t + 1),
            "r": sum(dark[r][rt] for r in range(t, b + 1)) / (b - t + 1),
        }
        k = max(edges, key=edges.get)
        if edges[k] <= tol:
            break
        if k == "t": t += 1
        elif k == "b": b -= 1
        elif k == "l": l += 1
        else: rt -= 1
    if (rt - l) * (b - t) < 0.25 * w * h:
        return None                       # peeled too much: not a page-on-desk photo
    sx, sy = W / w, H / h
    pad = 2                               # stay clear of the paper edge
    x0, y0 = round((l + pad) * sx), round((t + pad) * sy)
    x1, y1 = round((rt - pad + 1) * sx), round((b - pad + 1) * sy)
    return x1 - x0, y1 - y0, x0, y0


def fmt(v):
    s = f"{v:.2f}".rstrip("0").rstrip(".")
    return "0" if s in ("-0", "") else s


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0],
                                 formatter_class=argparse.RawDescriptionHelpFormatter,
                                 epilog=__doc__.split("Usage:", 1)[1])
    ap.add_argument("image")
    ap.add_argument("--width-cm", type=float)
    ap.add_argument("--dpi", type=float)
    ap.add_argument("--step", type=float, default=0.5)
    ap.add_argument("--clean", action="store_true")
    ap.add_argument("--zoom", help="x0,y0,x1,y1 in grid cm")
    ap.add_argument("--frame", help="X0,Y0,X1,Y1 in cm of a previous run's grid")
    ap.add_argument("--mask", action="append", default=[],
                    help="X0,Y0,X1,Y1 in cm of a previous run's grid: paint white "
                         "(captions or notes that share rows with the figure); repeatable")
    ap.add_argument("--crop", help="WxH+X+Y in source pixels, applied first "
                    "(cut away desk / page edges of a photo)")
    ap.add_argument("--no-autocrop", action="store_true",
                    help="with --clean, keep dark margins (desk) instead of cutting them")
    ap.add_argument("-o", "--out")
    a = ap.parse_args()

    need("magick")
    src = a.image
    if not os.path.isfile(src):
        sys.exit(f"error: {src} not found")
    check_path(src, "IMAGE")
    if a.out:
        check_path(a.out, "-o")
    positive(a.step, "--step")
    if a.width_cm is not None:
        positive(a.width_cm, "--width-cm")
    if a.dpi is not None:
        positive(a.dpi, "--dpi")
        if a.width_cm is not None:
            sys.exit("error: give either --width-cm or --dpi, not both")
    stem = os.path.splitext(os.path.basename(src))[0]
    outdir = os.path.dirname(a.out) if a.out else os.path.join(os.path.dirname(src), "work")
    if outdir:
        os.makedirs(outdir, exist_ok=True)
    base = os.path.join(outdir, stem)
    out = a.out or base + "-grid.png"

    # Files this script writes; refuse to clobber anything it did not create.
    man_path = os.path.join(outdir or ".", MANIFEST)
    made = set(read_text(man_path).split("\n")) if os.path.exists(man_path) else set()
    planned = [out] + [base + s for s in ("-src.png", "-clean.png", "-framed.png", "-up.png", "-zoomsrc.png")]
    src_real = os.path.realpath(src)
    for p in planned:
        if os.path.realpath(p) == src_real:
            sys.exit(f"error: refusing to overwrite the input image ({p}); pass another -o")
        if os.path.exists(p) and os.path.basename(p) not in made:
            sys.exit(f"error: refusing to overwrite {p} (not created by grid.py); pass another -o")
    write_text(man_path, "\n".join(sorted((made | {os.path.basename(p) for p in planned}) - {""})))

    # Rasterise PDFs / flatten alpha so everything below works on one PNG.
    work = base + "-src.png"
    pre = ["magick", "-density", "200", src + "[0]", "-auto-orient",
           "-background", "white", "-alpha", "remove", "-alpha", "off"]
    if a.crop:
        pre += ["-crop", a.crop, "+repage"]
    if a.clean:
        work = base + "-clean.png"
        # Background flattening: divide by a heavily blurred copy removes
        # uneven lighting / paper shadows, then stretch contrast.
        pre += ["-colorspace", "Gray",
                "(", "+clone", "-blur", "0x25", ")", "-compose", "Divide_Src",
                "-composite", "-normalize", "-level", "15%,90%",
                "-background", "white", "-deskew", "40%", "+repage"]
    run(pre + [work])
    if a.clean and not a.no_autocrop:
        box = paper_box(work)
        W0, H0 = size_of(work)
        if box and (box[0] < W0 * 0.98 or box[1] < H0 * 0.98):
            run(["magick", work, "-crop", "%dx%d+%d+%d" % box, "+repage", work])
            print("autocrop: cut dark margins, kept %dx%d+%d+%d of the cleaned image "
                  "(disable with --no-autocrop)" % box, file=sys.stderr)

    W, H = size_of(work)
    if a.width_cm is None:
        a.width_cm = round(W / a.dpi * 2.54, 4) if a.dpi else 12.0
    ppc = W / a.width_cm                     # pixels per cm
    height0 = H / ppc

    def region(spec, what):
        rx0, ry0, rx1, ry1 = floats(spec, 4, what)
        rx0, rx1 = sorted((rx0, rx1))
        ry0, ry1 = sorted((ry0, ry1))
        rx0, ry0 = max(0.0, rx0), max(0.0, ry0)
        rx1, ry1 = min(a.width_cm, rx1), min(height0, ry1)
        if rx1 - rx0 < 2 / ppc or ry1 - ry0 < 2 / ppc:
            sys.exit(f"error: {what} {spec} is empty or outside the image "
                     f"(0..{a.width_cm:.3f} x 0..{height0:.3f} cm)")
        return rx0, ry0, rx1, ry1

    masks = [region(m, "--mask") for m in a.mask]
    frame = region(a.frame, "--frame") if a.frame else None
    if a.frame or a.mask:
        # keep the unframed reference; framed/masked versions get their own name
        framed = base + "-framed.png"
        run(["magick", work, framed])
        work = framed
    for mx0, my0, mx1, my1 in masks:
        run(["magick", work, "-fill", "white", "-stroke", "none", "-draw",
             "rectangle %d,%d %d,%d" % (round(mx0 * ppc), round(H - my1 * ppc),
                                        round(mx1 * ppc), round(H - my0 * ppc)),
             work])
    if frame:
        fx0, fy0, fx1, fy1 = frame
        box = "%dx%d+%d+%d" % (round((fx1 - fx0) * ppc), round((fy1 - fy0) * ppc),
                               round(fx0 * ppc), round(H - fy1 * ppc))
        run(["magick", work, "-crop", box, "+repage", work])
        W, H = size_of(work)
        a.width_cm = round(W / ppc, 4)
        print("frame: kept x %s..%s, y %s..%s cm; the frame's lower-left is the new "
              "origin, scale unchanged (new width %s cm)"
              % (fmt(fx0), fmt(fx1), fmt(fy0), fmt(fy1), fmt(a.width_cm)), file=sys.stderr)
    height_cm = H / ppc

    x0, y0, x1, y1 = 0.0, 0.0, a.width_cm, height_cm
    img = work
    if a.zoom:
        height0 = height_cm
        x0, y0, x1, y1 = region(a.zoom, "--zoom")
        cx, cw = round(x0 * ppc), round((x1 - x0) * ppc)
        cy, ch = round(H - y1 * ppc), round((y1 - y0) * ppc)
        img = base + "-zoomsrc.png"
        run(["magick", work, "-crop", f"{cw}x{ch}+{cx}+{cy}", "+repage", img])
        W, H = size_of(img)
        ppc = W / (x1 - x0)

    # Upscale small crops / images so labels and lines stay legible.
    scale = max(1.0, 1400 / max(W, H))
    if scale > 1.0:
        tmp = base + "-up.png"
        run(["magick", img, "-resize", f"{scale * 100:.1f}%", tmp])
        img = tmp
        W, H = size_of(img)
        ppc *= scale

    margin = 46
    draws_minor, draws_major, labels = [], [], []

    def px(x):
        return margin + (x - x0) * ppc

    def py(y):
        return margin + (y1 - y) * ppc

    n0 = math.ceil(x0 / a.step - 1e-9)
    n1 = math.floor(x1 / a.step + 1e-9)
    for n in range(n0, n1 + 1):
        x = n * a.step
        major = abs(x - round(x)) < 1e-9
        line = f"line {px(x):.1f},{margin} {px(x):.1f},{margin + H}"
        (draws_major if major else draws_minor).append(line)
        if major or (x1 - x0) <= 3:
            labels.append((px(x) - 8, margin + H + 30, fmt(x)))
            labels.append((px(x) - 8, 30, fmt(x)))
    n0 = math.ceil(y0 / a.step - 1e-9)
    n1 = math.floor(y1 / a.step + 1e-9)
    for n in range(n0, n1 + 1):
        y = n * a.step
        major = abs(y - round(y)) < 1e-9
        line = f"line {margin},{py(y):.1f} {margin + W},{py(y):.1f}"
        (draws_major if major else draws_minor).append(line)
        if major or (y1 - y0) <= 3:
            labels.append((4, py(y) + 6, fmt(y)))
            labels.append((margin + W + 6, py(y) + 6, fmt(y)))

    cmd = ["magick", img, "-bordercolor", "white", "-border", str(margin),
           "-fill", "none", "-strokewidth", "1",
           "-stroke", "rgba(0,120,255,0.28)"]
    for d in draws_minor:
        cmd += ["-draw", d]
    cmd += ["-stroke", "rgba(230,0,60,0.55)"]
    for d in draws_major:
        cmd += ["-draw", d]
    f = font()
    cmd += ["-stroke", "none", "-fill", "rgb(200,0,40)", "-pointsize", "17"]
    if f:
        cmd += ["-font", f]
    for lx, ly, t in labels:
        cmd += ["-annotate", f"+{lx:.0f}+{ly:.0f}", t]
    cmd.append(out)
    run(cmd)

    info = {
        "grid_image": out,
        "reference_image": work,
        "width_cm": a.width_cm,
        "height_cm": round(height_cm, 3),
        "view_cm": [x0, y0, x1, y1],
        "step_cm": a.step,
        "px_per_cm_in_reference": round(size_of(work)[0] / a.width_cm, 3),
    }
    print(json.dumps(info, ensure_ascii=False, indent=2))
    print(f"\nnext: build.py FIG.tikz --ref {work} --ref-width-cm {a.width_cm}"
          + ("\n(the reference is the framed/masked image above, not *-src.png)" if (a.frame or a.mask) else ""))


if __name__ == "__main__":
    main()
