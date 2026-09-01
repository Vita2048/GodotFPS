"""Bullet-hole stamps: damage IN the existing materials, not copies of the tiling.

Albedo rule: keep hue/micro-grain from *_diff, strip large repeating motifs
(diamond plate, brick layout, plank seams) so a Godot Decal cannot look like
a rotated cookie of the wall.
"""
from __future__ import annotations

from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parent
FX = ROOT / "assets" / "fx"
TEX = ROOT / "assets" / "textures"
OUT = ROOT / "decals"
SIZE = 225
CX = CY = (SIZE - 1) * 0.5


def load_rgb(p: Path) -> np.ndarray:
    return np.asarray(Image.open(p).convert("RGB"), dtype=np.float32)


def load_gray(p: Path) -> np.ndarray:
    return np.asarray(Image.open(p).convert("L"), dtype=np.float32)


def save_rgb(arr: np.ndarray, p: Path) -> None:
    p.parent.mkdir(parents=True, exist_ok=True)
    Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8), "RGB").save(p, "PNG")


def save_gray(arr: np.ndarray, p: Path) -> None:
    p.parent.mkdir(parents=True, exist_ok=True)
    Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8), "L").save(p, "PNG")


def blur(arr: np.ndarray, radius: float) -> np.ndarray:
    mode = "RGB" if arr.ndim == 3 else "L"
    img = Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8), mode)
    return np.asarray(img.filter(ImageFilter.GaussianBlur(radius=radius)), dtype=np.float32)


def sample_crop(tex: np.ndarray, cx: float, cy: float, scale: float) -> np.ndarray:
    h, w = tex.shape[:2]
    yy, xx = np.mgrid[0:SIZE, 0:SIZE].astype(np.float32)
    half = (SIZE * 0.5) * scale
    u = np.mod(cx + (xx / (SIZE - 1) - 0.5) * 2.0 * half, w)
    v = np.mod(cy + (yy / (SIZE - 1) - 0.5) * 2.0 * half, h)
    x0 = np.floor(u).astype(np.int32)
    y0 = np.floor(v).astype(np.int32)
    x1 = (x0 + 1) % w
    y1 = (y0 + 1) % h
    fx = (u - x0)[..., None]
    fy = (v - y0)[..., None]
    return (
        tex[y0, x0] * (1 - fx) * (1 - fy)
        + tex[y0, x1] * fx * (1 - fy)
        + tex[y1, x0] * (1 - fx) * fy
        + tex[y1, x1] * fx * fy
    )


def highpass_grain(crop: np.ndarray, large: float, amount: float) -> np.ndarray:
    """Keep micro-grain, kill repeating motifs (diamonds, bricks, planks)."""
    mean = crop.mean(axis=(0, 1), keepdims=True)
    detail = crop - blur(crop, large)
    return np.clip(mean + detail * amount, 0, 255)


def palette(tex: np.ndarray, n: int, seed: int) -> np.ndarray:
    rng = np.random.RandomState(seed)
    h, w = tex.shape[:2]
    ys = rng.randint(0, h, size=400)
    xs = rng.randint(0, w, size=400)
    samples = tex[ys, xs]
    # simple k-means-ish by brightness quantiles
    lum = samples.mean(axis=1)
    cols = []
    for q in np.linspace(0.15, 0.85, n):
        t = np.quantile(lum, q)
        pick = samples[np.argmin(np.abs(lum - t))]
        cols.append(pick)
    return np.stack(cols, 0)


def radial() -> np.ndarray:
    yy, xx = np.mgrid[0:SIZE, 0:SIZE].astype(np.float32)
    return np.sqrt((xx - CX) ** 2 + (yy - CY) ** 2)


def make_masks(kind: str, hole_op: np.ndarray) -> tuple[np.ndarray, np.ndarray, np.ndarray]:
    """opacity, puncture (center cavity), chips (rim debris)."""
    rng = np.random.RandomState({"wood": 11, "brick": 22, "concrete": 33, "metal": 44}[kind])
    dist = radial()

    core = Image.fromarray(np.clip(hole_op, 0, 255).astype(np.uint8), "L")
    chips_img = Image.new("L", (SIZE, SIZE), 0)
    chips_img.paste(core, (0, 0))
    d = ImageDraw.Draw(chips_img)

    if kind == "wood":
        for _ in range(22):
            x = CX + rng.uniform(-30, 30)
            y = CY + rng.uniform(-48, 48)
            w = rng.uniform(1.5, 5)
            h = rng.uniform(12, 34)
            d.ellipse([x - w, y - h, x + w, y + h], fill=255)
        for _ in range(8):
            x = CX + rng.uniform(-20, 20)
            d.line(
                [(x, CY - rng.uniform(20, 42)), (x + rng.uniform(-4, 4), CY + rng.uniform(20, 42))],
                fill=230,
                width=int(rng.uniform(1, 3)),
            )
    elif kind == "brick":
        for _ in range(16):
            ox, oy = CX + rng.uniform(-34, 34), CY + rng.uniform(-34, 34)
            pts = [(ox + rng.uniform(-12, 12), oy + rng.uniform(-10, 10)) for __ in range(rng.randint(5, 8))]
            d.polygon(pts, fill=255)
        for _ in range(18):
            x, y, r = CX + rng.uniform(-36, 36), CY + rng.uniform(-36, 36), rng.uniform(1.2, 4)
            d.ellipse([x - r, y - r, x + r, y + r], fill=210)
    elif kind == "metal":
        # irregular dent, not a disc; paint flakes, no motif
        for _ in range(7):
            x, y = CX + rng.uniform(-16, 16), CY + rng.uniform(-16, 16)
            rx, ry = rng.uniform(10, 20), rng.uniform(8, 16)
            d.ellipse([x - rx, y - ry, x + rx, y + ry], fill=255)
        for _ in range(14):
            ox, oy = CX + rng.uniform(-28, 28), CY + rng.uniform(-28, 28)
            pts = [(ox + rng.uniform(-7, 7), oy + rng.uniform(-6, 6)) for __ in range(5)]
            d.polygon(pts, fill=200)
    else:
        for _ in range(10):
            x, y, r = CX + rng.uniform(-20, 20), CY + rng.uniform(-20, 20), rng.uniform(7, 16)
            d.ellipse([x - r, y - r, x + r, y + r], fill=245)
        for _ in range(20):
            x, y, r = CX + rng.uniform(-30, 30), CY + rng.uniform(-30, 30), rng.uniform(1, 3.5)
            d.ellipse([x - r, y - r, x + r, y + r], fill=190)

    chips = np.asarray(chips_img, dtype=np.float32)
    chips = np.maximum(chips, hole_op)
    limit = {"wood": 72, "brick": 70, "metal": 58, "concrete": 62}[kind]
    fade = np.clip(1.0 - (dist - limit) / 16.0, 0, 1)
    chips *= fade
    chips[dist > limit + 16] = 0
    chips = blur(chips, 0.55)

    puncture = np.clip(1.0 - (dist / {"wood": 16, "brick": 15, "metal": 13, "concrete": 14}[kind]) ** 1.35, 0, 1)
    puncture *= (hole_op / 255.0)
    puncture = np.clip(puncture, 0, 1)
    opacity = np.clip(np.maximum(chips, puncture * 255.0), 0, 255)
    opacity[dist > 82] = 0
    return opacity, puncture, chips / 255.0


def build(name: str, crop_xy, crop_scale, hp_large, hp_amt, puncture_rgb_scale, n_mat, n_crater):
    hole_alb = load_rgb(FX / "hole_albedo.png")
    hole_op = load_gray(FX / "hole_opacity.png")
    hole_rg = load_gray(FX / "hole_rough.png")
    hole_nr = load_rgb(FX / "hole_nor.png")

    diff = load_rgb(TEX / f"{name}_diff.jpg")
    nor = load_rgb(TEX / f"{name}_nor.jpg")
    rough = load_gray(TEX / f"{name}_rough.jpg")

    crop_d = sample_crop(diff, crop_xy[0], crop_xy[1], crop_scale)
    crop_n = sample_crop(nor, crop_xy[0], crop_xy[1], crop_scale)
    crop_r = sample_crop(rough[..., None].repeat(3, 2), crop_xy[0], crop_xy[1], crop_scale)[..., 0]

    grain = highpass_grain(crop_d, hp_large, hp_amt)
    pal = palette(diff, 4, hash(name) % 99991)

    opacity, puncture, chips = make_masks(name, hole_op)
    vis = opacity / 255.0
    dist = radial()

    # Base fill: material color + micro grain (no tiling motif)
    dark = pal[0]  # darkest quantile = cavity / scorched
    mid = pal[1]
    light = pal[2]
    bright = pal[3]

    if name == "metal":
        # olive paint (mid/light) and rust-dark (dark). Never diamonds.
        paint = mid * 0.45 + light * 0.55
        rust = dark * 0.7 + np.array([90.0, 45.0, 22.0]) * 0.3
        bare = mid * 0.25 + dark * 0.75  # exposed metal in hole
        albedo = grain * 0.15 + paint * 0.85
        albedo = albedo * (1.0 - puncture[..., None]) + bare * puncture_rgb_scale * puncture[..., None]
        # paint flakes on rim
        flake = np.clip(chips - puncture, 0, 1)
        albedo = albedo * (1.0 - flake[..., None] * 0.35) + rust * flake[..., None] * 0.35
        albedo = albedo * (1.0 - puncture[..., None] * 0.55) + bare * 0.35 * puncture[..., None]
    elif name == "wood":
        # stained surface vs paler torn inner fiber
        inner = np.clip(light * 1.15 + np.array([30.0, 18.0, 6.0]), 0, 255)
        stain = mid * 0.6 + dark * 0.4
        albedo = grain * 0.55 + stain * 0.45
        albedo = albedo * (1.0 - puncture[..., None]) + dark * puncture_rgb_scale * puncture[..., None]
        splinter = np.clip(chips - puncture * 0.5, 0, 1)
        albedo = albedo * (1.0 - splinter[..., None] * 0.65) + inner * splinter[..., None] * 0.65
    elif name == "brick":
        brick_col = pal[2]  # terracotta
        mortar = np.clip(pal[3] * 0.5 + np.array([160.0, 150.0, 125.0]) * 0.5, 0, 255)
        albedo = grain * 0.4 + brick_col * 0.6
        albedo = albedo * (1.0 - puncture[..., None]) + dark * puncture_rgb_scale * puncture[..., None]
        chip = np.clip(chips - puncture, 0, 1)
        albedo = albedo * (1.0 - chip[..., None] * 0.7) + brick_col * chip[..., None] * 0.7
        # mortar dust as irregular blobs, not a stripe
        rng_b = np.random.RandomState(7)
        mortar_zone = np.zeros((SIZE, SIZE), dtype=np.float32)
        yy, xx = np.mgrid[0:SIZE, 0:SIZE].astype(np.float32)
        for _ in range(9):
            mx = CX + rng_b.uniform(-28, 28)
            my = CY + rng_b.uniform(-28, 28)
            mr = rng_b.uniform(4, 10)
            mortar_zone = np.maximum(mortar_zone, np.clip(1.0 - np.sqrt((xx - mx) ** 2 + (yy - my) ** 2) / mr, 0, 1))
        mortar_zone *= chip
        albedo = albedo * (1.0 - mortar_zone[..., None] * 0.55) + mortar * mortar_zone[..., None] * 0.55
    else:
        # concrete: dusty chip of the actual gray, stay close to original crater
        albedo = grain * 0.5 + mid * 0.5
        orig = hole_alb
        albedo = albedo * (1.0 - 0.45) + (orig * 2.5 + grain * 0.4) * 0.45
        albedo = albedo * (1.0 - puncture[..., None] * 0.75) + dark * puncture_rgb_scale * puncture[..., None]
        dust = np.clip(chips - puncture, 0, 1)
        albedo = albedo * (1.0 - dust[..., None] * 0.35) + light * dust[..., None] * 0.35

    # original crater as extra occlusion in the very center
    albedo = albedo * vis[..., None]
    albedo = np.clip(albedo, 0, 255)
    sharp = albedo + (albedo - blur(albedo, 0.9)) * 0.9
    albedo = np.clip(sharp * vis[..., None], 0, 255)

    # roughness: hole_rough remapped toward material
    mat_mean = float(crop_r[vis > 0.35].mean()) if (vis > 0.35).any() else float(crop_r.mean())
    hole_mean = float(hole_rg[hole_op > 80].mean()) if (hole_op > 80).any() else 160.0
    remapped = hole_rg * (mat_mean / max(hole_mean, 1.0)) * 0.45 + crop_r * 0.55
    remapped = remapped + puncture * 45.0
    remapped = np.clip(remapped, 0, 255) * vis

    # normals: crater from original + material micro-bump (not the tiling)
    hn = (hole_nr / 255.0) * 2.0 - 1.0
    mn = (crop_n / 255.0) * 2.0 - 1.0
    mn_hp = mn - (blur((mn * 0.5 + 0.5) * 255.0, hp_large) / 255.0 * 2.0 - 1.0)
    n = hn.copy()
    n[..., 0] = hn[..., 0] * n_crater + mn_hp[..., 0] * n_mat * vis
    n[..., 1] = hn[..., 1] * n_crater + mn_hp[..., 1] * n_mat * vis
    dx = (np.mgrid[0:SIZE, 0:SIZE][1] - CX) / 20.0
    dy = (np.mgrid[0:SIZE, 0:SIZE][0] - CY) / 20.0
    fall = np.exp(-(dx * dx + dy * dy) * 0.9) * vis
    n[..., 0] -= dx * fall * 0.55
    n[..., 1] -= dy * fall * 0.55
    if name == "wood":
        n[..., 0] += 0.12 * vis * np.sin(np.mgrid[0:SIZE, 0:SIZE][1] * 0.85)
        n[..., 1] += 0.04 * vis * np.sin(np.mgrid[0:SIZE, 0:SIZE][0] * 0.4)
    length = np.sqrt((n ** 2).sum(axis=2, keepdims=True) + 1e-8)
    n = n / length
    n_rgb = (n * 0.5 + 0.5) * 255.0
    flat = np.array([128.0, 128.0, 255.0])
    n_rgb = n_rgb * vis[..., None] + flat * (1.0 - vis[..., None])
    n_rgb[..., 2] = np.clip(n_rgb[..., 2], 200, 255)

    dest = OUT / name
    save_rgb(albedo, dest / "hole_albedo.png")
    save_gray(opacity, dest / "hole_opacity.png")
    save_gray(remapped, dest / "hole_rough.png")
    save_rgb(n_rgb, dest / "hole_nor.png")
    print(f"{name}: vis px={(opacity>12).sum()} alb_mean={float(albedo[vis>0.3].mean()) if (vis>0.3).any() else 0:.0f}")


def main():
    wood = load_rgb(TEX / "wood_diff.jpg")
    brick = load_rgb(TEX / "brick_diff.jpg")
    conc = load_rgb(TEX / "concrete_diff.jpg")
    metal = load_rgb(TEX / "metal_diff.jpg")
    build("wood", (wood.shape[1] * 0.4, wood.shape[0] * 0.48), 0.22, 9.0, 0.85, 0.18, 0.45, 0.9)
    build("brick", (brick.shape[1] * 0.36, brick.shape[0] * 0.42), 0.20, 11.0, 0.55, 0.16, 0.5, 0.88)
    build("concrete", (conc.shape[1] * 0.5, conc.shape[0] * 0.5), 0.16, 6.0, 0.7, 0.12, 0.22, 1.0)
    # large high-pass so diamond plate is fully removed
    build("metal", (metal.shape[1] * 0.47, metal.shape[0] * 0.51), 0.18, 14.0, 0.25, 0.12, 0.2, 1.05)


if __name__ == "__main__":
    main()
