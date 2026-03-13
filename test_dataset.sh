#!/bin/bash

# =========================================================================
# SVC Dataset Evaluation Script (Segmented)
# =========================================================================

if [ "$#" -lt 3 ]; then
    echo "Usage: $0 <SEG_DIR> <REF_VIDEO> <OUTPUT_DIR> [MAX_LAYER] [REF_W] [REF_H] [FPS]"
    echo ""
    echo "Examples:"
    echo "  With MP4 Reference: $0 recreate/BBB-III reference.mp4 ./logs 3"
    echo "  With YUV Reference: $0 recreate/BBB-III reference.yuv ./logs 3 1920 1080 24"
    echo ""
    echo "Note: REF_W, REF_H, and FPS are REQUIRED if REF_VIDEO is a .yuv file."
    exit 1
fi

SEG_DIR=${1%/}
REF_VIDEO=$2
LOG_DIR=${3%/}
MAX_TEST_LAYER=${4:-3}

JSVM_DECODER="./jsvm/bin/H264AVCDecoderLibTestStatic"
SEG_DURATION="2.0" # Standard 2.0 second segments

# =========================================================================
# 1. Auto-Detect Prefix from Directory
# =========================================================================
FIRST_SEG=$(find "$SEG_DIR" -maxdepth 1 -name "*.seg*-L0.svc" | head -n 1)

if [ -z "$FIRST_SEG" ]; then
    echo "Error: No valid .svc segment files found in '$SEG_DIR'."
    exit 1
fi

PREFIX=$(basename "$FIRST_SEG" | sed 's/\.seg.*//')
echo "--> Auto-detected Prefix: $PREFIX"

mkdir -p "$LOG_DIR"
RESULTS_CSV="$LOG_DIR/experiment_results_${PREFIX}.csv"

# =========================================================================
# 2. Extract or Assign Reference Metadata
# =========================================================================
if [[ "${REF_VIDEO,,}" == *.yuv ]]; then
    if [ "$#" -lt 7 ]; then
        echo "Error: Reference video is .yuv. You must provide REF_W, REF_H, and FPS."
        exit 1
    fi
    REF_W=$5
    REF_H=$6
    FPS=$7
    REF_INPUT_OPTS="-f rawvideo -vcodec rawvideo -s ${REF_W}x${REF_H} -pix_fmt yuv420p -r $FPS"
    echo "--> YUV Reference Configured: ${REF_W}x${REF_H} @ ${FPS}fps"
else
    # tr to strip invisible carriage returns that break FFmpeg
    FPS=$(ffprobe -v error -select_streams v:0 -show_entries stream=r_frame_rate -of default=noprint_wrappers=1:nokey=1 "$REF_VIDEO" | tr -d '[:space:]')
    REF_W=$(ffprobe -v error -select_streams v:0 -show_entries stream=width -of default=noprint_wrappers=1:nokey=1 "$REF_VIDEO" | tr -d '[:space:]')
    REF_H=$(ffprobe -v error -select_streams v:0 -show_entries stream=height -of default=noprint_wrappers=1:nokey=1 "$REF_VIDEO" | tr -d '[:space:]')
    REF_INPUT_OPTS="-hwaccel auto"
    echo "--> MP4 Reference Auto-detected: ${REF_W}x${REF_H} @ ${FPS}fps"
fi

# =========================================================================
# LOOKUP TABLE: Auto-Detect Resolution from Prefix
# =========================================================================
get_native_resolution() {
    local pref=$1
    local layer=$2
    local w=1920; local h=1080

    case "$pref" in
        *"-I-360p")  w=640; h=360 ;;
        *"-I-720p")  w=1280; h=720 ;;
        *"-I-1080p") w=1920; h=1080 ;;
        *"-II-360p") w=480; h=360 ;;
        *"-III"|*"-IV")
            if [ "$layer" -eq 0 ]; then w=640; h=360
            elif [ "$layer" -eq 1 ]; then w=1280; h=720
            else w=1920; h=1080; fi
            ;;
        *) w=1920; h=1080 ;;
    esac
    echo "${w}x${h}"
}

# =========================================================================
# 3. Execution Loop
# =========================================================================
echo "Variant,Layer_Config,Bitrate_kbps,PSNR_Avg_dB,SSIM_Avg" > "$RESULTS_CSV"

for MAX_L in $(seq 0 $MAX_TEST_LAYER); do
    
    RESOLUTION=$(get_native_resolution "$PREFIX" "$MAX_L")
    NATIVE_W=$(echo $RESOLUTION | cut -d'x' -f1)
    NATIVE_H=$(echo $RESOLUTION | cut -d'x' -f2)

    echo "========================================================="
    echo ">>> TESTING CONFIGURATION: $PREFIX (Up to Layer L${MAX_L})"
    echo ">>> Native Size: ${NATIVE_W}x${NATIVE_H} -> Upscaling to ${REF_W}x${REF_H}"
    echo "========================================================="
    
    SEG_NUMS=$(find "$SEG_DIR" -maxdepth 1 -name "${PREFIX}.seg*-L0.svc" -exec basename {} \; 2>/dev/null | sed -n "s/.*\.seg\([0-9]*\)-L0\.svc/\1/p" | sort -n)
    TOTAL_SEGS=$(echo $SEG_NUMS | wc -w)
    
    TOTAL_SIZE=0; SUM_PSNR=0; SUM_SSIM=0; VALID_SEGS=0
    
    SEG_LOG="$LOG_DIR/${PREFIX}_segment_details_L${MAX_L}.csv"
    echo "Segment,Size_Bytes,PSNR,SSIM" > "$SEG_LOG"

    for SEG in $SEG_NUMS; do
        echo -ne "\r    [Layer $MAX_L] Processing Segment $SEG / $TOTAL_SEGS... " >&2
        
        LAYERS=""
        for L in $(seq 0 $MAX_L); do
            LAYER_FILE="${SEG_DIR}/${PREFIX}.seg${SEG}-L${L}.svc"
            [ -f "$LAYER_FILE" ] && LAYERS="$LAYERS $LAYER_FILE"
        done
        
        TEMP_264="temp_${SEG}.264"
        TEMP_YUV="temp_${SEG}.yuv"

        python decode/svc_merge.py "$TEMP_264" "${SEG_DIR}/${PREFIX}.init.svc" $LAYERS > /dev/null 2>&1
        
        if [ $? -eq 0 ] && [ -s "$TEMP_264" ]; then
            SEG_SIZE=$(stat -c%s "$TEMP_264")
            TOTAL_SIZE=$((TOTAL_SIZE + SEG_SIZE))
            
            $JSVM_DECODER "$TEMP_264" "$TEMP_YUV" > /dev/null 2>&1
            
            if [ -s "$TEMP_YUV" ]; then
                START_TIME=$(awk -v s="$SEG" -v d="$SEG_DURATION" 'BEGIN {printf "%.3f", s * d}')
                
		# split=2[ref1][ref2] to give both PSNR and SSIM their own copy of the reference
                COMP_LOG=$(ffmpeg -hide_banner -threads 8 \
                    -f rawvideo -vcodec rawvideo -s ${NATIVE_W}x${NATIVE_H} -pix_fmt yuv420p -r $FPS -i "$TEMP_YUV" \
                    -ss "$START_TIME" -t "$SEG_DURATION" $REF_INPUT_OPTS -i "$REF_VIDEO" \
                    -filter_complex "[0:v]setpts=PTS-STARTPTS,scale=${REF_W}:${REF_H}:flags=bicubic,split=2[up1][up2]; [1:v]setpts=PTS-STARTPTS,split=2[ref1][ref2]; [up1][ref1]psnr; [up2][ref2]ssim" \
                    -f null - 2>&1)                    

                SEG_PSNR=$(echo "$COMP_LOG" | grep -oP "average:\K[0-9.]+")
                SEG_SSIM=$(echo "$COMP_LOG" | grep -oP "All:\K[0-9.]+")
                
                if [ ! -z "$SEG_PSNR" ] && [ ! -z "$SEG_SSIM" ]; then
                    SUM_PSNR=$(awk -v sum="$SUM_PSNR" -v val="$SEG_PSNR" 'BEGIN {print sum + val}')
                    SUM_SSIM=$(awk -v sum="$SUM_SSIM" -v val="$SEG_SSIM" 'BEGIN {print sum + val}')
                    VALID_SEGS=$((VALID_SEGS + 1))
                    echo "$SEG,$SEG_SIZE,$SEG_PSNR,$SEG_SSIM" >> "$SEG_LOG"
                else
                    echo -e "\n    [!] Error: FFmpeg failed on Segment $SEG. See logs/ffmpeg_error.log" >&2
                    echo "$COMP_LOG" > "$LOG_DIR/ffmpeg_error.log"
                fi
            else
                echo -e "\n    [!] Error: JSVM failed to decode Segment $SEG" >&2
            fi
        else
            echo -e "\n    [!] Error: python merge failed or missing Segment $SEG" >&2
        fi
        rm -f "$TEMP_264" "$TEMP_YUV"
    done
    
    echo "" >&2 
    
    if [ "$VALID_SEGS" -gt 0 ]; then
        TOTAL_DURATION=$(awk -v s="$VALID_SEGS" -v d="$SEG_DURATION" 'BEGIN {print s * d}')
        AVG_BITRATE=$(awk -v sz="$TOTAL_SIZE" -v dur="$TOTAL_DURATION" 'BEGIN { printf "%.2f", (sz * 8) / (dur * 1000) }')
        AVG_PSNR=$(awk -v sum="$SUM_PSNR" -v n="$VALID_SEGS" 'BEGIN { printf "%.6f", sum / n }')
        AVG_SSIM=$(awk -v sum="$SUM_SSIM" -v n="$VALID_SEGS" 'BEGIN { printf "%.6f", sum / n }')
        
        echo "$PREFIX,L0-L${MAX_L},$AVG_BITRATE,$AVG_PSNR,$AVG_SSIM" >> "$RESULTS_CSV"
        echo "---------------------------------------------------------"
        echo ">>> LAYER L${MAX_L} RESULT: ${AVG_BITRATE} kbps | PSNR: ${AVG_PSNR} dB | SSIM: ${AVG_SSIM}"
        echo "---------------------------------------------------------"
    else
        echo "---------------------------------------------------------"
        echo ">>> ERROR: Layer L${MAX_L} completed but 0 valid segments were processed."
        echo "---------------------------------------------------------"
    fi
done