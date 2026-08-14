#!/usr/bin/env python3
"""Bake a usable potato albedo map from a Blender UV paint layout."""

from __future__ import annotations

from collections import deque
from pathlib import Path

from PIL import Image, ImageFilter

ROOT = Path(__file__).resolve().parents[1]
UV_LAYOUT = Path(
	"/home/headadmin/.cursor/projects/home-headadmin-Documents-projects-john/assets/"
	"Untitled.001-beb088ba-f203-4ce2-9864-5b41ebead8fc.png"
)
POTATO_PHOTO = ROOT / "assets/models/potatos.png"
OUTPUT = ROOT / "assets/models/potato_albedo.png"


def clamp(v: int) -> int:
	return max(0, min(255, v))


def is_orange(r: int, g: int, b: int, a: int) -> bool:
	if a < 200:
		return False
	# Painted UV islands (orange brush strokes).
	if r > 165 and g < 155 and b < 85 and r > g + 25:
		return True
	return False


def build_mask(layout: Image.Image) -> Image.Image:
	w, h = layout.size
	mask = Image.new("L", (w, h), 0)
	layout_px = layout.load()
	mask_px = mask.load()
	for y in range(h):
		for x in range(w):
			if is_orange(*layout_px[x, y]):
				mask_px[x, y] = 255
	return mask


def label_islands(mask: Image.Image) -> list[dict]:
	w, h = mask.size
	mask_px = mask.load()
	labels = [[0] * w for _ in range(h)]
	islands: list[dict] = []
	label_id = 0

	for y in range(h):
		for x in range(w):
			if mask_px[x, y] < 128 or labels[y][x] != 0:
				continue
			label_id += 1
			queue: deque[tuple[int, int]] = deque([(x, y)])
			labels[y][x] = label_id
			min_x = max_x = x
			min_y = max_y = y
			pixels: list[tuple[int, int]] = []

			while queue:
				cx, cy = queue.popleft()
				pixels.append((cx, cy))
				min_x = min(min_x, cx)
				max_x = max(max_x, cx)
				min_y = min(min_y, cy)
				max_y = max(max_y, cy)
				for nx, ny in ((cx + 1, cy), (cx - 1, cy), (cx, cy + 1), (cx, cy - 1)):
					if 0 <= nx < w and 0 <= ny < h and labels[ny][nx] == 0 and mask_px[nx, ny] > 128:
						labels[ny][nx] = label_id
						queue.append((nx, ny))

			islands.append(
				{
					"id": label_id,
					"pixels": pixels,
					"bbox": (min_x, min_y, max_x, max_y),
				}
			)
	return islands


def bake(layout: Image.Image, potato: Image.Image, mask: Image.Image) -> Image.Image:
	w, h = layout.size
	potato = potato.convert("RGB")
	# Higher-res tile source for detail.
	tile = potato.resize((768, 768), Image.Resampling.LANCZOS)
	tile_px = tile.load()
	tw, th = tile.size

	out = layout.copy()
	out_px = out.load()
	layout_px = layout.load()
	islands = label_islands(mask)

	for island in islands:
		min_x, min_y, max_x, max_y = island["bbox"]
		bw = max(max_x - min_x, 1)
		bh = max(max_y - min_y, 1)
		for x, y in island["pixels"]:
			u = (x - min_x) / bw
			v = (y - min_y) / bh
			# Slight island rotation so copies don't look identical.
			rot = (island["id"] * 0.71) % 1.0
			uu = u * 0.92 + v * 0.08 + rot * 0.15
			vv = v * 0.92 - u * 0.05 + rot * 0.12
			sx = int(uu * (tw - 1)) % tw
			sy = int(vv * (th - 1)) % th
			pr, pg, pb = tile_px[sx, sy]
			# Organic variation + subtle darker specks (potato eyes).
			n = ((x * 17 + y * 31 + island["id"] * 13) % 17) - 8
			if ((x * 7 + y * 11 + island["id"] * 5) % 97) == 0:
				n -= 28
			out_px[x, y] = (clamp(pr + n), clamp(pg + n - 2), clamp(pb + n - 4), 255)

	# Keep original yellow UV gutter visible in Blender.
	for y in range(h):
		for x in range(w):
			if not is_orange(*layout_px[x, y]):
				out_px[x, y] = layout_px[x, y]

	return out


def main() -> None:
	layout = Image.open(UV_LAYOUT).convert("RGBA")
	potato = Image.open(POTATO_PHOTO)
	mask = build_mask(layout)
	# Slightly soften island edges so sampling doesn't look too harsh.
	mask = mask.filter(ImageFilter.GaussianBlur(radius=0.6))
	result = bake(layout, potato, mask)
	OUTPUT.parent.mkdir(parents=True, exist_ok=True)
	result.save(OUTPUT)
	print(f"Wrote {OUTPUT} ({result.size[0]}x{result.size[1]})")


if __name__ == "__main__":
	main()
