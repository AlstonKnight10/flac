#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

INPUT_DIR="$PROJECT_ROOT/cluster_build/inputs"
OUTPUT_DIR="$PROJECT_ROOT/cluster_build/outputs"
TEMP_DIR=$(mktemp -d)

FLAC_URL="https://link.storjshare.io/raw/jx4ail3mgdene32efmvv4nzrjffq/bulk-data/Jellyfin%20Media%2FMusic%2FMEGAREX%2FSPD%20GAR%2FDisc%202/01%20Special%20DJ%20Mix.flac"
SRC_FLAC="$INPUT_DIR/01 Special DJ Mix.flac"
SRC_WAV="$INPUT_DIR/01 Special DJ Mix.wav"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

cleanup() {
    rm -rf "$TEMP_DIR"
}
trap cleanup EXIT

mkdir -p "$INPUT_DIR"
mkdir -p "$OUTPUT_DIR"

check_dependencies() {
    command -v flac >/dev/null || { echo -e "${RED}flac not found${NC}"; exit 1; }
    command -v wget >/dev/null || { echo -e "${RED}wget not found${NC}"; exit 1; }
    command -v awk >/dev/null || { echo -e "${RED}awk not found${NC}"; exit 1; }
    command -v stat >/dev/null || { echo -e "${RED}stat not found${NC}"; exit 1; }
}

prepare_input_file() {
    echo -e "${BLUE}Checking input files...${NC}"

    if [ ! -f "$SRC_FLAC" ]; then
        echo -e "${YELLOW}FLAC file not found, downloading...${NC}"
        wget --progress=bar:force -O "$SRC_FLAC" "$FLAC_URL" || {
            echo "Download failed"
            exit 1
        }
    else
        echo -e "${GREEN}Found FLAC: $SRC_FLAC${NC}"
    fi

    if [ ! -f "$SRC_WAV" ]; then
        echo -e "${YELLOW}WAV file not found, decoding...${NC}"
        flac -d "$SRC_FLAC" -o "$SRC_WAV" >/dev/null 2>&1 || {
            echo -e "${RED}Failed to decode FLAC file.${NC}"
            exit 1
        }
    else
        echo -e "${GREEN}Found WAV: $SRC_WAV${NC}"
    fi
}

run_benchmark() {
    local thread_count=$1
    local out_flac="$TEMP_DIR/test_${thread_count}.flac"
    local out_wav="$TEMP_DIR/test_${thread_count}.wav"

    local wav_size
    local out_size
    local enc_time
    local dec_time
    local ratio
    local enc_tput
    local dec_tput

    wav_size=$(stat -c%s "$SRC_WAV" 2>/dev/null || stat -f%z "$SRC_WAV")

    echo -e "${YELLOW}Testing with $thread_count thread(s)...${NC}"

    enc_time=$(/usr/bin/time -f "%e" sh -c 'flac -j'"$thread_count"' "$1" -o "$2" >/dev/null 2>/dev/null' _ "$SRC_WAV" "$out_flac" 2>&1)
    if [ ! -f "$out_flac" ]; then
        echo -e "${RED}Encode failed for thread count $thread_count${NC}"
        return
    fi

    dec_time=$(/usr/bin/time -f "%e" sh -c 'flac -d "$1" -o "$2" >/dev/null 2>/dev/null' _ "$out_flac" "$out_wav" 2>&1)
    if [ ! -f "$out_wav" ]; then
        echo -e "${RED}Decode failed for thread count $thread_count${NC}"
        return
    fi

    out_size=$(stat -c%s "$out_flac" 2>/dev/null || stat -f%z "$out_flac")
    ratio=$(awk -v input_bytes="$wav_size" -v output_bytes="$out_size" 'BEGIN { printf "%.2f", (output_bytes * 100) / input_bytes }')
    enc_tput=$(awk -v bytes="$wav_size" -v secs="$enc_time" 'BEGIN { if (secs > 0) printf "%.2f", (bytes / 1048576) / secs; else print "NA" }')
    dec_tput=$(awk -v bytes="$wav_size" -v secs="$dec_time" 'BEGIN { if (secs > 0) printf "%.2f", (bytes / 1048576) / secs; else print "NA" }')

    echo "$thread_count|$enc_time|$dec_time|$enc_tput|$dec_tput|$ratio|1" >> "${TEMP_DIR}/results.txt"

    echo -e "${GREEN}OK${NC} (Enc: ${enc_time}s | Dec: ${dec_time}s | Ratio: ${ratio}%)"
}

main() {
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}FLAC Preliminary Benchmark${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo ""

    check_dependencies
    prepare_input_file
    echo ""

    > "${TEMP_DIR}/results.txt"

    for threads in 1 2 4 8 16 32; do
        run_benchmark "$threads"
    done

    if [ -s "${TEMP_DIR}/results.txt" ]; then
        echo ""
        echo -e "${BLUE}========================================${NC}"
        echo -e "${BLUE}Benchmark Results Summary${NC}"
        echo -e "${BLUE}========================================${NC}"
        printf "%-8s | %-14s | %-14s | %-14s | %-14s | %-12s | %-8s\n" \
               "Threads" "Avg Enc(ms)" "Avg Dec(ms)" "Enc(MB/s)" "Dec(MB/s)" "Compress(%)" "Files"
        echo -e "${BLUE}---------|-------------|-------------|-------------|-------------|------------|--------${NC}"

        while IFS='|' read -r threads enc_time dec_time enc_tput dec_tput compress file_count; do
            printf "%-8s | %-14s | %-14s | %-14s | %-14s | %-12s | %-8s\n" \
                   "$threads" "$enc_time" "$dec_time" "$enc_tput" "$dec_tput" "$compress" "$file_count"
        done < "${TEMP_DIR}/results.txt"

        echo -e "${BLUE}========================================${NC}"
        echo ""
        echo -e "${GREEN}Benchmark complete!${NC}"
    else
        echo -e "${RED}No benchmark results were generated.${NC}"
        exit 1
    fi
}

main "$@"
