#!/bin/bash

URL="https://media.xiph.org/video/derf/y4m/big_buck_bunny_1080p24.y4m.xz"
OUTPUT_MP4="lossless_reference.mp4"

echo "========================================================="
echo ">>> Streaming, Decompressing, and Encoding Reference Video..."
echo ">>> This will take several minutes depending on your CPU/Network."
echo "========================================================="

# 1. 'curl -L' downloads the .xz file as a continuous stream
# 2. 'xz -d -c' decompresses the stream on the fly and pushes it to standard output
# 3. 'ffmpeg -i -' reads that standard output directly
# 4. '-c:v libx264 -crf 0' encodes it into H.264 at mathematical lossless quality

curl -L "$URL" | xz -d -c | ffmpeg -hide_banner -i - -c:v libx264 -preset fast -crf 0 -pix_fmt yuv420p "$OUTPUT_MP4"

echo "========================================================="
echo ">>> DONE! Lossless reference video saved as: $OUTPUT_MP4"
echo "========================================================="