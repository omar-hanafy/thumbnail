#!/usr/bin/env bash
# Generates the committed test fixture videos in example/assets/fixtures.
# Requires ffmpeg. Run from the package root:
#   bash tool/generate_fixtures.sh
set -euo pipefail

out="example/assets/fixtures"
mkdir -p "$out"

# 1s, 640x360, 30fps, colorful gradient so frames are visually distinct,
# keyframe every 10 frames, faststart for cheap network extraction.
ffmpeg -y -f lavfi -i "testsrc2=size=640x360:rate=30:duration=1" \
  -c:v libx264 -pix_fmt yuv420p -g 10 -movflags +faststart \
  "$out/landscape.mp4"

# Same content stored 640x360 but tagged with a 90-degree display rotation
# (display-matrix side data): players (and correct extractors) must render
# it 360x640 portrait.
ffmpeg -y -f lavfi -i "testsrc2=size=640x360:rate=30:duration=1" \
  -c:v libx264 -pix_fmt yuv420p -g 10 -movflags +faststart \
  "$out/_tmp_landscape.mp4"
ffmpeg -y -display_rotation 90 -i "$out/_tmp_landscape.mp4" -c copy \
  "$out/portrait_rot90.mp4"
rm "$out/_tmp_landscape.mp4"

ls -la "$out"
