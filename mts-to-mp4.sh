#!/usr/bin/env bash
# 
# mts-to-mp4.sh
# Converts MTS files to MP4 without transcoding
# Copies all metadata
# Applies created and modified dates to the new file
# Will apply orientation metadata based on ROTATE variable
#   ROTATE=CW will rotate clockwise
#   ROTATE=CC will rotate counterclockwise
#

# Set rotate argument as appropriate
if [[ "$ROTATE" = "CW" ]]; then
  ROTATE_ARG="-metadata:s:v:0 rotate=90"
elif [[ "$ROTATE" = "CC" ]]; then
  ROTATE_ARG="-metadata:s:v:0 rotate=270"
else
  ROTATE_ARG=" "
fi

# Set start time and stop time if defined
if [ -n "$START" ]; then
  START_ARG="-ss ${START}"
else
  START_ARG=" "
fi
if [ -n "$STOP" ]; then
  STOP_ARG="-to ${STOP}"
else
  STOP_ARG=" "
fi

for INPUT in $@
do
  OUTPUT="${INPUT%.*}.mp4"

  # Copy video and audio to MP4
  TZ="UTC" \
  ffmpeg \
    ${START_ARG} \
    -i "$INPUT" \
    ${STOP_ARG} \
    -c:a copy -c:v copy \
    -flags +global_header \
    -map_metadata 0 \
    -map_metadata:s:v 0:s:v \
    -map_metadata:s:a 0:s:a \
    -metadata creation_time="$(TZ=UTC stat -c '%y' "$INPUT" | sed 's/\.00000.*//')" \
    ${ROTATE_ARG} \
    "$OUTPUT"

  # Copy created and modified dates from mts
  SetFile \
    -d "$(GetFileInfo -d "$INPUT")" \
    -m "$(GetFileInfo -m "$INPUT")" \
    "$OUTPUT"
done
