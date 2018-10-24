#!/usr/bin/env bash
#
# encode-hevc.sh
# Encodes videos to HEVC MOV using ffmpeg and x265
# Copies as much original metadata and applies specified new metadata
# Copies created and modified dates to the new file
#
# x265 encoder uses CRF=23 with medium preset
# Audio is encoded with FDK AAC using default settings
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

for INPUT in "$@"
do
  EXTENSION="${INPUT##*.}"
  # Use same filename .mov for output
  # Assuming I don't encode anything that starts as .mov
  OUTPUT="${INPUT%.*}.mov"
  # The MP4 spec calls for UTC time, so use that for the creation/encoding time
  TIME_UTC="$(TZ=UTC stat -c '%y' "$INPUT" | sed 's/\.00000.*//')"

  # Set rotate argument based on MacOS Finder tags
  if [[ "$(tag -lN "$INPUT")" = *"↻"* ]]; then
    ROTATE_ARG="-vf transpose=1"
  elif [[ "$(tag -lN "$INPUT")" = *"↺"* ]]; then
    ROTATE_ARG="-vf transpose=2"
  else
    ROTATE_ARG=" "
  fi

  # Encode to MOV with x265 and FDK AAC
  # Copy as much metadata as FFMPEG can handle
  # hvc1 tag is required for Quicktime playback
  TZ="UTC" \
  ffmpeg \
    -n \
    ${START_ARG} \
    -i "$INPUT" \
    ${STOP_ARG} \
    -c:a libfdk_aac \
    -c:v libx265 \
    -crf 23 \
    -tag:v hvc1 \
    -flags +global_header \
    -map_metadata 0 \
    -map_metadata:s:v 0:s:v \
    -map_metadata:s:a 0:s:a \
    -metadata creation_time="${TIME_UTC}" \
    -metadata creation_date="${TIME_UTC}" \
    -metadata make="Sony" \
    -metadata model="ILCE-6500" \
    ${ROTATE_ARG} \
    "$OUTPUT"

  # Use exiftool to copy more metadata that FFMPEG misses
  echo -e "\x1B[00;33mCopy all metadata from \x1B[01;35m${INPUT}\x1B[00m"
  # Try to copy everything first, but this will still miss some important tags
  exiftool -overwrite_original -extractEmbedded -TagsFromFile "$INPUT" "-all:all>all:all" "$OUTPUT"
  # Copy the important date/time tags that have time zone and seem to be respected by Apple
  case "${EXTENSION}" in
    mp4|MP4)
      echo -e "\x1B[00;33mSet CreationDate and DateTimeOriginal from \x1B[01;35m${INPUT}\x1B[00;33m CreationDateValue\x1B[00m"
      # MP4 dates have the same format but need to go from CreationDateValue to CreationDate
      exiftool -overwrite_original -tagsfromfile "${INPUT}" '-CreationDate<CreationDateValue' '-DateTimeOriginal<CreationDateValue' "${OUTPUT}"
      ;;
    mts|MTS)
      echo -e "\x1B[00;33mSet CreationDate and DateTimeOriginal from \x1B[01;35m${INPUT}\x1B[00;33m CreationDate\x1B[00m"
      # DateTimeOriginal in MTS files has "DST" and such at the end which can't be written to MOV files,
      # so strip that manually and then separately write to the MOV file instead of copying
      DATETIME="$(exiftool -s -s -s -DateTimeOriginal "${INPUT}" | sed -e 's/ [[:alpha:]]\+$//')"
      exiftool -overwrite_original -DateTimeOriginal="${DATETIME}" -CreationDate="${DATETIME}" "${OUTPUT}"
      ;;
  esac

  # Copy location from other file if specified
  if [ -n "$LOCATION" ]; then
    echo -e "\x1B[00;33mCopy location from \x1B[01;35m${LOCATION}\x1B[00m"
    exiftool -overwrite_original -TagsFromFile "$LOCATION" -Location:all "$OUTPUT"
  fi

  # Add description, rating, or keywords if they are set
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
    eval "$EXIF_CMD \"${OUTPUT}\""
  fi

  # Copy MacOS Finder tags from original file
  echo -e "\x1B[00;33mCopy MacOS Finder tags from \x1B[01;35m${INPUT}\x1B[00m"
  tag --add "$(tag --no-name --list "$INPUT")" "$OUTPUT"

  # Copy created and modified dates from original file
  echo -e "\x1B[00;33mCopy file created and modified date from \x1B[01;35m${INPUT}\x1B[00m"
  SetFile \
    -d "$(GetFileInfo -d "$INPUT")" \
    -m "$(GetFileInfo -m "$INPUT")" \
    "$OUTPUT"
done
