#!/usr/bin/env bash
#
# crossfade.sh
# Merges two videos with a one second crossfade.
# Usage: crossfade.sh video1 video2 timetofade
# Output is a lossless H.264 MKV with PCM audio
#

INPUT1=$1
INPUT2=$2
FADETIME=$3
FADEEND=$(($FADETIME+1))

ffmpeg -i ${INPUT1} -i ${INPUT2} -an \
-filter_complex \
"   [0:v]trim=start=0:end=${FADETIME},setpts=PTS-STARTPTS[firstclip];
    [1:v]trim=start=1,setpts=PTS-STARTPTS[secondclip];
    [0:v]trim=start=${FADETIME}:end=${FADEEND},setpts=PTS-STARTPTS[fadeoutsrc];
    [1:v]trim=start=0:end=1,setpts=PTS-STARTPTS[fadeinsrc];
    [fadeinsrc]format=pix_fmts=yuva420p,
                fade=t=in:st=0:d=1:alpha=1[fadein];
    [fadeoutsrc]format=pix_fmts=yuva420p,
                fade=t=out:st=0:d=1:alpha=1[fadeout];
    [fadein]fifo[fadeinfifo];
    [fadeout]fifo[fadeoutfifo];
    [fadeoutfifo][fadeinfifo]overlay[crossfade];
    [firstclip][crossfade][secondclip]concat=n=3[output];
    [0:a][1:a] acrossfade=d=1 [audio]
" \
-map "[output]" -map "[audio]" -y -c:a pcm_s16le -c:v libx264 -preset ultrafast -qp 0 crossfaded.mkv
