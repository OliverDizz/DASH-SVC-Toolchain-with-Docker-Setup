#!/bin/bash

DATASET_URL="https://ftp.itec.aau.at/datasets/SVCDASHDataset2015/BBB/"

echo "========================================================="
echo ">>> Starting recursive download of the BBB Dataset..."
echo ">>> Source: $DATASET_URL"
echo "========================================================="

# -r: Recursive download
# -np: No parent (don't traverse up the server directory tree)
# -nH: No host directory (don't create an 'ftp.itec.aau.at' folder locally)
# --cut-dirs=2: Strip the '/datasets/SVCDASHDataset2015/' path prefix
# -R "index.html*": Ignore web server index files
# -e robots=off: Ignore robots.txt restrictions just in case

wget -r -np -nH --cut-dirs=2 -R "index.html*" -e robots=off "$DATASET_URL"

echo "========================================================="
echo ">>> Download Complete! Dataset saved to the ./BBB directory."
echo "========================================================="