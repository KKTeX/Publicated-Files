"""Shared helpers for the tikzify scripts (stdlib only)."""
import os
import re
import shutil
import subprocess
import sys

HINTS = {
    "magick": "install ImageMagick 7 (the `magick` command; ImageMagick 6 `convert` is not supported)",
    "pdftoppm": "install poppler (pdftoppm, pdftocairo, pdftotext, pdfinfo)",
    "pdftocairo": "install poppler (pdftoppm, pdftocairo, pdftotext, pdfinfo)",
    "pdftotext": "install poppler (pdftoppm, pdftocairo, pdftotext, pdfinfo)",
    "pdfinfo": "install poppler (pdftoppm, pdftocairo, pdftotext, pdfinfo)",
    "gs": "install Ghostscript (needed for EPS/PS input)",
    "lualatex": "install a TeX distribution (TeX Live / MacTeX / MiKTeX)",
    "pdflatex": "install a TeX distribution (TeX Live / MacTeX / MiKTeX)",
    "xelatex": "install a TeX distribution (TeX Live / MacTeX / MiKTeX)",
}


def need(*tools):
    for t in tools:
        if shutil.which(t) is None:
            sys.exit(f"error: `{t}` not found -- {HINTS.get(t, 'install it and put it on PATH')}")


def run(cmd, cwd=None, check=True, binary=False):
    """Run an argument list (never a shell string). On failure exit with the
    tool's own message instead of a traceback."""
    need(cmd[0])
    r = subprocess.run(cmd, cwd=cwd, capture_output=True,
                       **({} if binary else {"text": True, "errors": "replace"}))
    if check and r.returncode != 0:
        err = r.stderr if not binary else r.stderr.decode("utf-8", "replace")
        out = r.stdout if not binary else b""
        sys.exit(f"error: {' '.join(map(str, cmd[:3]))} ... failed (exit {r.returncode})\n"
                 f"{str(out)[-1500:]}\n{err[-1500:]}")
    return r


def read_text(path):
    with open(path, encoding="utf-8", errors="replace", newline="") as f:
        return f.read()


def write_text(path, text):
    d = os.path.dirname(os.path.abspath(path))
    os.makedirs(d, exist_ok=True)
    with open(path, "w", encoding="utf-8", newline="") as f:
        f.write(text)


SAFE_NAME = re.compile(r"^[A-Za-z0-9._ -]+$")


def check_name(name, what="figure name"):
    """Names end up in \\input{...} and ImageMagick arguments: keep them plain."""
    if not SAFE_NAME.match(name):
        sys.exit(f"error: {what} {name!r} may only contain letters, digits, '.', '_', '-' "
                 "and spaces (TeX and ImageMagick misread %, ~, #, {, } ...)")


def check_path(path, what="path"):
    if "%" in os.path.basename(path):
        sys.exit(f"error: {what} {path!r} contains '%' (ImageMagick reads it as a frame pattern)")


def posix_rel(path, start):
    """Relative path with forward slashes, as \\input and Markdown need."""
    return os.path.relpath(path, start).replace(os.sep, "/")


_TEX = {"\\": r"\textbackslash{}", "{": r"\{", "}": r"\}", "$": r"\$", "&": r"\&",
        "#": r"\#", "%": r"\%", "_": r"\_", "^": r"\textasciicircum{}",
        "~": r"\textasciitilde{}"}


def tex_escape(s):
    """Escape every TeX special character in one pass.  Text extracted from
    untrusted PDFs/SVGs goes through this, so ^^-notation or \\commands can
    never reach TeX as code."""
    s = "".join(_TEX.get(ch, ch) for ch in s)
    # control characters would be read as ^^-escapes or invalid input
    return "".join(ch for ch in s if ch >= " " or ch == "\t")


def strip_comments(s):
    """Remove TeX comments: a % not preceded by an odd number of backslashes."""
    return re.sub(r"(?<!\\)((?:\\\\)*)%.*", r"\1", s)


def floats(spec, n, what):
    try:
        v = [float(x) for x in spec.split(",")]
    except ValueError:
        v = []
    if len(v) != n:
        sys.exit(f"error: {what} needs {n} comma-separated numbers, got {spec!r}"
                 " (for negative values write --opt=-1,2,...)")
    return v


def positive(x, what):
    if not x or x <= 0:
        sys.exit(f"error: {what} must be > 0")
    return x
