#!/usr/bin/env bash
#
# Regenerate Quarry's app icon (Icon Composer format) and the vector mark.
#
# macOS 26+ masks and lights the icon itself, so the .icon bundle supplies a
# background fill plus the white square as a layer — it must NOT contain its own
# rounded square, or the system draws its tile around ours and you get a black
# square floating on Apple's white one.
#
# Usage: scripts/generate-icon.sh

set -euo pipefail
cd "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

ASSETS="quarry/Resources/Assets.xcassets"
ICON="quarry/Resources/AppIcon.icon"

mkdir -p "$ICON/Assets"

python3 - "$ICON" "$ASSETS/quarry_logo_mark.imageset/quarry_logo_mark.svg" <<'PY'
import json, pathlib, sys

# --- geometry, on the 1024 canvas the system masks -----------------------
CANVAS       = 1024
INNER_RATIO  = 0.44    # white square as a share of the tile
INNER_CORNER = 0.36    # corner run as a share of its side (0.5 = fully round)
INNER_DX     = -0.1038 # offset from center, as a share of the tile
INNER_DY     =  0.0983

# Continuous-corner profile read off the original mark: control points at
# these fractions of the corner run. Gives Apple's smooth squircle corner
# rather than the flat circular fillet an SVG `rx` would produce.
A, B, C, D, E, F = 0.6500, 0.4750, 0.3413, 0.2237, 0.1280, 0.0681


def squircle(x, y, size, corner):
    k = size * corner
    x0, y0, x1, y1 = x, y, x + size, y + size
    n = lambda v: f"{v:.4f}"
    return " ".join([
        f"M{n(x0 + k)} {n(y0)}", f"L{n(x1 - k)} {n(y0)}",
        f"C{n(x1 - A*k)} {n(y0)} {n(x1 - B*k)} {n(y0)} {n(x1 - C*k)} {n(y0 + F*k)}",
        f"C{n(x1 - D*k)} {n(y0 + E*k)} {n(x1 - E*k)} {n(y0 + D*k)} {n(x1 - F*k)} {n(y0 + C*k)}",
        f"C{n(x1)} {n(y0 + B*k)} {n(x1)} {n(y0 + A*k)} {n(x1)} {n(y0 + k)}",
        f"L{n(x1)} {n(y1 - k)}",
        f"C{n(x1)} {n(y1 - A*k)} {n(x1)} {n(y1 - B*k)} {n(x1 - F*k)} {n(y1 - C*k)}",
        f"C{n(x1 - E*k)} {n(y1 - D*k)} {n(x1 - D*k)} {n(y1 - E*k)} {n(x1 - C*k)} {n(y1 - F*k)}",
        f"C{n(x1 - B*k)} {n(y1)} {n(x1 - A*k)} {n(y1)} {n(x1 - k)} {n(y1)}",
        f"L{n(x0 + k)} {n(y1)}",
        f"C{n(x0 + A*k)} {n(y1)} {n(x0 + B*k)} {n(y1)} {n(x0 + C*k)} {n(y1 - F*k)}",
        f"C{n(x0 + D*k)} {n(y1 - E*k)} {n(x0 + E*k)} {n(y1 - D*k)} {n(x0 + F*k)} {n(y1 - C*k)}",
        f"C{n(x0)} {n(y1 - B*k)} {n(x0)} {n(y1 - A*k)} {n(x0)} {n(y1 - k)}",
        f"L{n(x0)} {n(y0 + k)}",
        f"C{n(x0)} {n(y0 + A*k)} {n(x0)} {n(y0 + B*k)} {n(x0 + F*k)} {n(y0 + C*k)}",
        f"C{n(x0 + E*k)} {n(y0 + D*k)} {n(x0 + D*k)} {n(y0 + E*k)} {n(x0 + C*k)} {n(y0 + F*k)}",
        f"C{n(x0 + B*k)} {n(y0)} {n(x0 + A*k)} {n(y0)} {n(x0 + k)} {n(y0)}",
        "Z",
    ])


icon_dir = pathlib.Path(sys.argv[1])
size = CANVAS * INNER_RATIO
x = CANVAS / 2 + INNER_DX * CANVAS - size / 2
y = CANVAS / 2 + INNER_DY * CANVAS - size / 2
d = squircle(x, y, size, INNER_CORNER)

(icon_dir / "Assets" / "quarry-mark.svg").write_text(
    f'<svg width="{CANVAS}px" height="{CANVAS}px" viewBox="0 0 {CANVAS} {CANVAS}" '
    f'version="1.1" xmlns="http://www.w3.org/2000/svg">\n'
    f'  <path d="{d}" fill="#FFFFFF"/>\n'
    f'</svg>\n'
)

(icon_dir / "icon.json").write_text(json.dumps({
    # The tile itself. The system masks this to the squircle and lights it.
    "fill": {"automatic-gradient": "srgb:0.00000,0.00000,0.00000,1.00000"},
    "groups": [{
        "blur-material": None,
        "hidden": False,
        "layers": [{
            "blend-mode": "normal",
            "fill": {"solid": "srgb:1.00000,1.00000,1.00000,1.00000"},
            "glass": False,
            "hidden": False,
            "image-name": "quarry-mark.svg",
            "name": "quarry-mark",
        }],
        "lighting": "individual",
        "shadow": {"kind": "neutral", "opacity": 0.35},
        "specular": True,
        "translucency": {"enabled": False, "value": 0},
    }],
    "supported-platforms": {"squares": ["macOS"]},
}, indent=2) + "\n")

# Flat vector mark for the premium card: black body, inner knocked out.
s = 294 / CANVAS
body = squircle(0, 0, 294, 0.3146)
inner = squircle(x * s, y * s, size * s, INNER_CORNER)
p = pathlib.Path(sys.argv[2])
p.parent.mkdir(parents=True, exist_ok=True)
p.write_text(
    '<svg width="294" height="294" viewBox="0 0 294 294" fill="none" '
    'xmlns="http://www.w3.org/2000/svg">\n'
    f'<path fill-rule="evenodd" d="{body} {inner}" fill="#D9D9D9"/>\n'
    '</svg>\n'
)
print(f"    tile 1024 black | mark {size:.0f} ({INNER_RATIO:.0%}) corner {INNER_CORNER}")
PY

# The .icon supersedes the legacy set; two assets named AppIcon collide.
rm -rf "$ASSETS/AppIcon.appiconset"
echo "    ok $ICON (legacy AppIcon.appiconset removed)"
