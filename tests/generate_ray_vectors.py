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
        if x // 4096 in (0, 15) or y // 4096 in (0, 15):
            return distance, 64 if distance <= 32 else 2048 // distance
        x += sx
        y += sy
    return 1023, 0


vectors = [(34816, 34816, angle) for angle in range(1024)]
rng = random.Random(2026)
vectors += [(rng.randrange(4096, 61440), rng.randrange(4096, 61440), rng.randrange(1024))
            for _ in range(256)]
# Inside walls, negative coordinates, all four out-of-map directions, near walls.
vectors += [(x, y, angle) for x, y in [(0, 0), (-1, 34816), (65536, 34816),
            (34816, -4096), (34816, 65536), (4096, 4096), (61439, 61439)]
            for angle in (0, 256, 512, 768)]
with (out / "ray_vectors.txt").open("w", encoding="ascii") as stream:
    for x, y, angle in vectors:
        distance, height = cast(x, y, angle)
        stream.write(f"{x & 0x3ffff:05x} {y & 0x3ffff:05x} {angle:03x} {distance:03x} {height:02x}\n")
for name, x, y, angle in [("frame0", 34816, 34816, 0), ("frame1", 18432, 26624, 256)]:
    with (out / f"{name}.mem").open("w", encoding="ascii") as stream:
        for col in range(96):
            offset = (170 * col + 47) // 95 - 85
            distance, height = cast(x, y, (angle + offset) % 1024)
            stream.write(f"{(distance << 7) | height:05x}\n")
assert cast(34816, 34816, 0) == (208, 9)
assert cast(34816, 34816, 256) == (208, 9)
assert cast(34816, 34816, 512) == (241, 8)
assert cast(34816, 34816, 768) == (241, 8)
print(f"Generated {len(vectors)} ray vectors and two reference frames")
