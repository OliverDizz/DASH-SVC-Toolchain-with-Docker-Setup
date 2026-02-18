#!/bin/bash
set -e  # Exit immediately if any command fails 

# Ensure memory limits are increased for JSVM
ulimit -s unlimited || true 

# Enter the Toolchain root (one level up from build_scripts)
cd /DASH-SVC-Toolchain 

echo "--- Building LibDash ---"
chmod +x ./build_scripts/buildLibDash.sh 
./build_scripts/buildLibDash.sh 

echo "--- Building JSVM ---"
cd jsvm/JSVM/H264Extension/build/linux 
make clean 
# Build with specific legacy CXXFLAGS
make -j$(nproc) CXXFLAGS="-O2 -fno-strict-aliasing -fno-aggressive-loop-optimizations -m64 -std=c++98" 

# Verify JSVM tools exist
cd ../../../../bin/ 
echo "Found binaries in $(pwd):" 
ls BitStreamExtractorStatic H264AVCDecoderLibTestStatic 

# Go back to the Toolchain root to run tests
cd /DASH-SVC-Toolchain 

# Setup Path to JSVM binaries for testing
JSVMPATH=$(pwd)/jsvm/bin 
export PATH=$PATH:$JSVMPATH 

echo "Starting JSVM Verification Tests..." 

# 1. Download the test video
echo "Downloading test video..." 
wget -q http://concert.itec.aau.at/SVCDataset/svcseqs/II/bluesky-II-360p.264 

if [ ! -f "bluesky-II-360p.264" ]; then 
    echo "FAILED: Could not download test video." 
    exit -1 
fi 

# 2. Test BitStreamExtractor
echo "Testing BitStreamExtractor..." 
BitStreamExtractorStatic bluesky-II-360p.264 > bluesky_test.txt 
diff bluesky_test.txt tests/bluesky_II_360p.txt 

if [ $? -ne 0 ] ; then 
    echo "TESTING JSVM (TEST 1: Extraction) FAILED!" 
    exit -2 
fi 
echo "Extraction test passed." 

# 3. Test Decoder
echo "Testing Decoder..." 
H264AVCDecoderLibTestStatic bluesky-II-360p.264 bluesky-II-360p.yuv > bluesky_decode_test.txt || true 
DEC_RESULT=$? 

# Accept 0 (success) or 248 (EOF) as passing results
if [ $DEC_RESULT -ne 0 ] && [ $DEC_RESULT -ne 248 ]; then 
    echo "TESTING JSVM (TEST 2: Decoding) CRASHED with code $DEC_RESULT!" 
    exit -2 
fi 

# Compare the log output
diff bluesky_decode_test.txt tests/decode_bluesky_II_360p.txt 
if [ $? -ne 0 ] ; then 
    echo "TESTING JSVM (TEST 2: Decoding) FAILED: Output logs do not match!" 
    exit -2 
fi 
echo "Decoding test passed." 

# 4. Clean up
echo "Cleaning up..." 
rm bluesky_test.txt 
rm bluesky_decode_test.txt 
rm bluesky-II-360p.264 
rm bluesky-II-360p.yuv 

echo "---------------------------------" 
echo "ALL TESTS DONE AND PASSED!!!" 
echo "---------------------------------"