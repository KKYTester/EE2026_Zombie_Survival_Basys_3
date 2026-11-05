"""Independent numerical reference for the fixed-step renderer simulations."""
import math
import random
from pathlib import Path

out = Path(__file__).resolve().parents[1] / "build/renderer_checks"
out.mkdir(parents=True, exist_ok=True)


def cast(x, y, angle):
    # Quantize the full-circle direction directly, independent of RTL folding.
    def nearest(value):
        return math.floor(value + 0.5) if value >= 0 else -math.floor(-value + 0.5)

    sx = nearest(128 * math.sin(angle * 2 * math.pi / 1024))
    sy = nearest(128 * math.cos(angle * 2 * math.pi / 1024))
    for distance in range(769):
        if not (0 <= x < 65536 and 0 <= y < 65536):
            return 1023, 0
        cell_x, cell_y = x // 4096, y // 4096
        if (cell_x in (0, 15) or cell_y in (0, 15)
                or (6 <= cell_x <= 10 and 10 <= cell_y <= 14)):
            return distance, 64 if distance <= 32 else 2048 // distance
        x += sx
        y += sy
    return 1023, 0


def project(distance, factor):
    if distance == 1023:
        return 1023, 0
    depth = (distance * min(factor, 4096) + 2048) // 4096
    return depth, 64 if depth <= 32 else 2048 // depth


def cosine(offset):
    return math.floor(4096 * math.cos(offset * 2 * math.pi / 1024) + 0.5)


vectors = [(34816, 34816, angle, 4096) for angle in range(1024)]
rng = random.Random(2026)
vectors += [(rng.randrange(4096, 61440), rng.randrange(4096, 61440), rng.randrange(1024), 4096)
            for _ in range(256)]
# Inside walls, negative coordinates, all four out-of-map directions, near walls.
vectors += [(x, y, angle, 4096) for x, y in [(0, 0), (-1, 34816), (65536, 34816),
            (34816, -4096), (34816, 65536), (4096, 4096), (61439, 61439)]
            for angle in (0, 256, 512, 768)]
# Every column factor at cardinal headings and near angle wraparound.
vectors += [(34816, 34816, (view + offset) % 1024, cosine(offset))
            for view in (0, 256, 512, 768, 1023)
            for offset in [(170 * col + 47) // 95 - 85 for col in range(96)]]
# Zero depth saturates, invalid factors clamp to unity, misses keep sentinel.
vectors += [(x, y, 256, factor) for x, y in [(34816, 34816), (0, 0), (-1, 34816)]
            for factor in (0, 3544, 4096, 8191)]
with (out / "ray_vectors.txt").open("w", encoding="ascii") as stream:
    for x, y, angle, factor in vectors:
        distance, _ = cast(x, y, angle)
        depth, height = project(distance, factor)
        stream.write(f"{x & 0x3ffff:05x} {y & 0x3ffff:05x} {angle:03x} {factor:04x} "
                     f"{distance:03x} {depth:03x} {height:02x}\n")
for name, x, y, angle in [("frame0", 34816, 34816, 128), ("frame1", 18432, 26624, 256),
                          ("frame2", 34816, 18432, 512)]:
    raw_distances, depths, heights = [], [], []
    with (out / f"{name}.mem").open("w", encoding="ascii") as stream:
        for col in range(96):
            offset = (170 * col + 47) // 95 - 85
            distance, _ = cast(x, y, (angle + offset) % 1024)
            depth, height = project(distance, cosine(offset))
            raw_distances.append(distance)
            depths.append(depth)
            heights.append(height)
            stream.write(f"{(depth << 7) | height:05x}\n")
    if name == "frame2":
        # A front-facing flat wall must not curve at the screen edges. Allow
        # one depth step from the raymarcher's existing direction quantization.
        assert raw_distances[0] > raw_distances[47]
        assert max(depths) - min(depths) <= 1
        assert set(heights) == {18}
assert cast(34816, 34816, 0) == (48, 42)
assert cast(34816, 34816, 256) == (208, 9)
assert cast(34816, 34816, 512) == (241, 8)
assert cast(34816, 34816, 768) == (241, 8)
print(f"Generated {len(vectors)} ray vectors and three cosine-corrected reference frames")
