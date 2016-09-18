#!/usr/bin/env bash
#
# mts-to-mp4.sh
# Converts MTS files to MP4 without transcoding
# Copies as much original metadata and applies specified new metadata
# Copies created and modified dates to the new file
#
# Optional new metadata:
#   ROTATE
#     CW will rotate clockwise
#     CC will rotate counterclockwise
#   START
#     Time to start video copy
#   STOP
#     Time to stop video copy
#   LOCATION
#     A file to copy location from
#   DESCRIPTION
#     Description (caption)
#   RATING
#     Star rating (integer 1–5)
#   KEYWORDS
#     Comma-delimited list of keywords
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
  # Use same filename for output
  OUTPUT="${INPUT%.*}.mp4"
  # The MP4 spec calls for UTC time, so use that for the creation/encoding time
  TIME_UTC="$(TZ=UTC stat -c '%y' "$INPUT" | sed 's/\.00000.*//')"
  # Lightroom doesn't respect the UTC time spec, so use local time for Date/Time Original
  TIME_LOCAL="$(stat -c '%y' "$INPUT" | sed 's/\.00000.*//')"

  # Copy video and audio to MP4
  # with as much metadata as FFMPEG will copy
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
    -metadata creation_time="${TIME_UTC}" \
    ${ROTATE_ARG} \
    "$OUTPUT"

  # Use exiftool to copy more metadata that FFMPEG misses
  echo -e "\x1B[00;33mCopy all metadata from \x1B[01;35m${INPUT}\x1B[00m"
  exiftool -overwrite_original -TagsFromFile "$INPUT" "$OUTPUT"
  # Set Date/Time Original to local time for Lightroom
  echo -e "\x1B[00;33mSet Date/Time Original to (local time) \x1B[01;35m${TIME_LOCAL}\x1B[00m"
  exiftool -overwrite_original -DateTimeOriginal="${TIME_LOCAL}" "$OUTPUT"

  if [ -n "$LOCATION" ]; then
    echo -e "\x1B[00;33mCopy location from \x1B[01;35m${LOCATION}\x1B[00m"
    exiftool -overwrite_original -TagsFromFile "$LOCATION" -Location:all "$OUTPUT"
  fi

  if [ -n "$DESCRIPTION" -o -n "$RATING" -o -n "$KEYWORDS" ]; then
    EXIF_CMD="exiftool -overwrite_original"
    if [ -n "$DESCRIPTION" ]; then
      echo -e "\x1B[00;33mSet description to \x1B[01;35m${DESCRIPTION}\x1B[00m"
      EXIF_CMD="${EXIF_CMD} -description=\"${DESCRIPTION}\""
    fi
    if [ -n "$RATING" ]; then
      echo -e "\x1B[00;33mSet rating to \x1B[01;35m${RATING}\x1B[00m"
      EXIF_CMD="${EXIF_CMD} -rating=${RATING}"
    fi
    if [ -n "$KEYWORDS" ]; then
      echo -e "\x1B[00;33mSet keywords to \x1B[01;35m${KEYWORDS}\x1B[00m"
      EXIF_CMD="${EXIF_CMD} -sep \", \" -keywords=\"${KEYWORDS}\""
    fi
    eval "$EXIF_CMD ${OUTPUT}"
  fi

  # Copy created and modified dates from original MTS
  echo -e "\x1B[00;33mCopy file created and modified date from \x1B[01;35m${INPUT}\x1B[00m"
  SetFile \
    -d "$(GetFileInfo -d "$INPUT")" \
    -m "$(GetFileInfo -m "$INPUT")" \
    "$OUTPUT"
done
