#!/usr/bin/env python3
"""Generate the Android E2E fixtures using Python's standard library and FFmpeg."""

import argparse
from pathlib import Path
import shutil
import subprocess
import tempfile


def write_pattern(path, width, height, checkerboard=False):
    colors = tuple(bytes(color) for color in ((255, 0, 0), (0, 255, 0), (0, 0, 255), (255, 255, 0)))
    with path.open("wb") as output:
        output.write(f"P6\n{width} {height}\n255\n".encode("ascii"))
        for y in range(height):
            if checkerboard:
                row = b"".join(
                    bytes((255, 255, 255)) if (x // 80 + y // 80) % 2 == 0 else bytes(3)
                    for x in range(width)
                )
            else:
                offset = 0 if y < height // 2 else 2
                row = colors[offset] * (width // 2) + colors[offset + 1] * (width - width // 2)
            output.write(row)


def generate(output_directory):
    ffmpeg = shutil.which("ffmpeg")
    if ffmpeg is None:
        raise RuntimeError("FFmpeg is required to generate Android fixtures. Install ffmpeg and add it to PATH.")

    def encode(*arguments):
        subprocess.run([ffmpeg, "-v", "error", "-nostdin", "-y", *map(str, arguments)], check=True)

    output_directory.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="camrelay-android-fixtures-") as temporary:
        temporary = Path(temporary)
        for name, width, height, checkerboard in (
            ("checkerboard", 480, 640, True),
            ("orientation", 360, 640, False),
        ):
            source = temporary / f"{name}.ppm"
            write_pattern(source, width, height, checkerboard)
            encode("-i", source, "-frames:v", "1", "-update", "1", output_directory / f"{name}.png")

        encode(
            "-f", "lavfi", "-i", "color=c=0xFF0000:s=320x240:r=15:d=1",
            "-f", "lavfi", "-i", "color=c=0x00FF00:s=320x240:r=15:d=1",
            "-f", "lavfi", "-i", "color=c=0x0000FF:s=320x240:r=15:d=1",
            "-filter_complex", "[0:v][1:v][2:v]concat=n=3:v=1:a=0[v]", "-map", "[v]",
            "-c:v", "libx264", "-pix_fmt", "yuv420p", "-t", "3", output_directory / "colors.mp4",
        )
        orientation = temporary / "orientation-video.ppm"
        write_pattern(orientation, 640, 360)
        video = temporary / "orientation-video.mp4"
        encode("-loop", "1", "-framerate", "12", "-i", orientation, "-t", "3",
               "-c:v", "libx264", "-pix_fmt", "yuv420p", video)
        encode("-display_rotation", "-90", "-i", video, "-c", "copy",
               output_directory / "orientation-rotate90.mp4")
    print(f"Android fixtures: {output_directory}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--output", type=Path, default=Path(__file__).resolve().parents[1] / ".build/fixtures"
    )
    generate(parser.parse_args().output)
