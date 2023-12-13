#!/usr/bin/env bash
#
# encode-hevc.sh
# Encodes videos to HEVC MOV using ffmpeg and x265
# Copies as much original metadata and applies specified new metadata
# Copies created and modified dates to the new file
#
# x265 encoder uses CRF=23 with medium preset unless overridden
# Audio is encoded with FDK AAC using default settings
#
# Videos with ↻ or ↺ in their MacOS Finder tags will be rotated in the 
# appropriate direction
#
# Options and metadata
#   CRF
#     x265 CRF parameter
#   PRESET
#     x265 preset parameter
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
  START_ARG=(
  -ss
  "${START}"
  )
else
  START_ARG=()
fi
if [ -n "$STOP" ]; then
  STOP_ARG=(
  -to
  "${STOP}"
  )
else
  STOP_ARG=()
fi

# Set x265 CRF if defined; use 23 if not
if [ -n "$CRF" ]; then
  CRF_ARG=(
  "-crf"
  "${CRF}"
  )
else
  CRF_ARG=(
  "-crf"
  "28"
  )
fi

# Set x265 preset if defined
if [ -n "$PRESET" ]; then
  PRESET_ARG=(
  -preset
  "${PRESET}"
  )
else
  PRESET_ARG=()
fi

# Set x265 tuning if defined
if [ -n "$TUNE" ]; then
  TUNE_ARG=(
  -tune
  "${TUNE}"
  )
else
  TUNE_ARG=()
fi

# Set filter if defined
if [ -n "$FILTER" ]; then
  FILTER_ARG=(
  -vf
  "${FILTER}"
  )
else
  FILTER_ARG=()
fi

# Set resolution if defined
if [ -n "$SCALE" ]; then
  SCALE_ARG=(
  -vf scale=-1:"${SCALE}"
  )
else
  SCALE_ARG=()
fi

# Encode both audio streams if bilingual parameter is set
# For now, arguments hard-coded to match NHK's Curious George stream
# with video in 0, Japanese in 1, and English in 11
if [ -n "$BILINGUAL" ]; then
  BILINGUAL_ARG=(
  -map 0:0 -map 0:1 -map 0:11
  -metadata:s:v:0 language=jpn
  -metadata:s:a:0 language=jpn
  -metadata:s:a:1 language=eng
  )
else
  BILINGUAL_ARG=()
fi

# Set separate video source
if [ -n "$VIDEO" ]; then
  VIDEO_ARG=(
    -i "${VIDEO}"
    -map 1:v:0
    -map 0:a:0
    )
else
  VIDEO_ARG=()
fi


# Encode without audio if NOAUDIO is set.
# Otherwise use FDK AAC
if [ -n "$NOAUDIO" ]; then
  AUDIO_ARG=(
  -an
  )
else
  AUDIO_ARG=(
  -c:a libfdk_aac
    )
fi

for INPUT in "$@"
do
  DIRECTORY="$(dirname "${INPUT}")"
  FULLPATH="$(realpath "${DIRECTORY}")"
  BASENAME="$(basename "${INPUT%.*}")"
  EXTENSION="${INPUT##*.}"
  # Use same FILENAME.mov for output, unless defined in OUTPUT
  # Append -hevc if it already exists
  if [ -z "$OUTPUT" ]; then
    OUTPUT="${FULLPATH}/${BASENAME}.mov"
    if [ -f "${OUTPUT}" ]; then
      OUTPUT="${FULLPATH}/${BASENAME}-hevc.mov"
    fi
  fi
  # If separate file for metadata source is not set, default to input video
  if [ -z "$METADATA" ]; then
    METADATA="${INPUT}"
  fi
  # M4V extension doesn't default to mp4 format by default,
  # so force it if an M4V output is explicitly specified
  if [[ ${OUTPUT} == *.m4v ]]; then
    FORMAT_ARG=(
      -f mp4
    )
  else
    FORMAT_ARG=()
  fi
  # The MP4 spec calls for UTC time, so use that for the creation/encoding time
  case "${EXTENSION}" in
    m2ts|M2TS)
      TIME_UTC="$(TZ=UTC date -d "$(mediainfo --Inform="General;%Duration_Start%" "${METADATA}" | sed -e "s/UTC //")+09:00" +"%Y-%m-%d %H:%M:00")"
      ;;
    *)
  TIME_UTC="$(TZ=UTC stat -c '%y' "$METADATA" | sed -n 's/\([[:digit:]]\{4\}-[[:digit:]]\{2\}-[[:digit:]]\{2\} [[:digit:]]\{2\}:[[:digit:]]\{2\}:[[:digit:]]\{2\}\).*/\1/p')"
  esac

  # Set camera metadata
  if [ "$(exiftool -DeviceModelName "${INPUT}" | grep -q "ILCE-7CM2")" ]; then
    CAMERA_ARG=(
      -metadata make='Sony'
      -metadata model='ILCE-7CM2'
    )
  else
    CAMERA_ARG=()
  fi

  # Set rotate argument based on MacOS Finder tags
  if [[ "$(tag -lN "$INPUT")" = *"↻"* ]]; then
    ROTATE_ARG=(
    -vf
    "transpose=1"
    )
  elif [[ "$(tag -lN "$INPUT")" = *"↺"* ]]; then
    ROTATE_ARG=(
    -vf
    "transpose=2"
    )
  elif [[ "$(tag -lN "$INPUT")" = *"⇅"* ]]; then
    ROTATE_ARG=(
    -vf
    "transpose=2,transpose=2"
    )
  else
    ROTATE_ARG=()
  fi

  # Insert subtitles if SRT file exists in the same directory
  # This has a quick'n'dirty merger with the freeform FILTER parameter above
  # I should clean it up sometime
  SUBTITLE_ARG=()
  if [ -f "${DIRECTORY}"/"${BASENAME}".srt ]; then
    # Append subtitles to existing filter if already defined
    if [ -n "$FILTER" ]; then
      FILTER_ARG=(
        -vf
        "${FILTER}, subtitles="${DIRECTORY}"/"${BASENAME}".srt:force_style='FontName=Myriad Pro,Fontsize=24,OutlineColour=&H30333333,Bold=600'"
      )
    else # Otherwise set subtitles in their own filter
    SUBTITLE_ARG=(
    -vf
    "subtitles="${DIRECTORY}"/"${BASENAME}".srt:force_style='FontName=Myriad Pro,Fontsize=24,OutlineColour=&H30333333,Bold=600'"
    )
    fi
  fi

  # Set color parameters and pixel format for SDR or HDR
  COLOR_PRIMARIES=$(mediainfo --Inform="Video;%colour_primaries%" "${INPUT}")
  if [ "$COLOR_PRIMARIES" = "BT.2020" ]; then
    COLOR_ARG=(
      -color_primaries bt2020
      -color_trc smpte2084
      -colorspace bt2020nc
      )
    PIXFMT_ARG=(
      -pix_fmt yuv420p10
    )
  else
    COLOR_ARG=(
      -colorspace bt709
      -color_primaries bt709
      -color_trc bt709
      -color_range tv)
    PIXFMT_ARG=(
      -pix_fmt yuv420p
    )
  fi

  # Set up ffmpeg arguments as an array since this is more robust and doesn't 
  # break on the quotes in the subtitles option
  FFMPEG_ARGS=(
  -n
  -fflags +genpts
  -async 1
  -i "${INPUT}"
  "${VIDEO_ARG[@]}"
  "${START_ARG[@]}"
  "${STOP_ARG[@]}"
  -c:v libx265
  -c:a libfdk_aac
  "${PIXFMT_ARG[@]}"
  "${PRESET_ARG[@]}"
  "${TUNE_ARG[@]}"
  "${CRF_ARG[@]}"
  "${SCALE_ARG[@]}"
  "${FILTER_ARG[@]}"
  "${BILINGUAL_ARG[@]}"
  -tag:v hvc1
  -flags +global_header
  -movflags +faststart
  -map_metadata 0
  -map_metadata:s:v 0:s:v
  -map_metadata:s:a 0:s:a
  -metadata creation_time'='"${TIME_UTC}"
  -metadata creation_date'='"${TIME_UTC}"
  -write_tmcd 0
  "${CAMERA_ARG[@]}"
  "${COLOR_ARG[@]}"
  "${SUBTITLE_ARG[@]}"
  "${ROTATE_ARG[@]}"
  "${FORMAT_ARG[@]}"
  "$OUTPUT"
  )

  # Encode to MOV with x265 and FDK AAC
  # Copy as much metadata as FFMPEG can handle
  # hvc1 tag is required for Quicktime playback
  TZ="UTC" \
    ffmpeg "${FFMPEG_ARGS[@]}"

  # Use exiftool to copy more metadata that FFMPEG misses
  echo -e "\x1B[00;33mCopy all metadata from \x1B[01;35m${METADATA}\x1B[00m"
  # Try to copy everything first, but this will still miss some important tags
  exiftool -api largefilesupport=1 -overwrite_original -extractEmbedded -TagsFromFile "$METADATA" "-all:all>all:all" "$OUTPUT"
  # Copy the important date/time tags that have time zone and seem to be respected by Apple
  case "${EXTENSION}" in
    mp4|MP4)
      echo -e "\x1B[00;33mSet CreationDate and DateTimeOriginal from \x1B[01;35m${METADATA}\x1B[00;33m CreationDateValue\x1B[00m"
      # MP4 dates have the same format but need to go from CreationDateValue to CreationDate
      exiftool -api largefilesupport=1 -overwrite_original -tagsfromfile "${METADATA}" '-CreationDate<CreationDateValue' '-DateTimeOriginal<CreationDateValue' "${OUTPUT}"
      ;;
    mts|MTS)
      echo -e "\x1B[00;33mSet CreationDate and DateTimeOriginal from \x1B[01;35m${METADATA}\x1B[00;33m CreationDate\x1B[00m"
      # DateTimeOriginal in MTS files has "DST" and such at the end which can't be written to MOV files,
      # so strip that manually and then separately write to the MOV file instead of copying
      DATETIME="$(exiftool -api largefilesupport=1 -s -s -s -DateTimeOriginal "${METADATA}" | sed -e 's/ [[:alpha:]]\+$//')"
      exiftool -api largefilesupport=1 -overwrite_original -DateTimeOriginal="${DATETIME}" -CreationDate="${DATETIME}" "${OUTPUT}"
      ;;
    m2ts|M2TS)
      echo -e "\x1B[00;33mSet CreationDate and DateTimeOriginal from \x1B[01;35m${METADATA}\x1B[00;33m Duration_Start\x1B[00m"
      # DateTimeOriginal in MTS files has "DST" and such at the end which can't be written to MOV files,
      # so strip that manually and then separately write to the MOV file instead of copying
      DATETIME="$(date -d "$(mediainfo --Inform="General;%Duration_Start%" ${METADATA} | sed -e "s/UTC //")" +"%Y:%m:%d %H:%M:00%:z")"
      exiftool -api largefilesupport=1 -overwrite_original -DateTimeOriginal="${DATETIME}" -CreationDate="${DATETIME}" "${OUTPUT}"
      ;;
  esac

  # Copy location from other file if specified
  if [ -n "$LOCATION" ]; then
    echo -e "\x1B[00;33mCopy location from \x1B[01;35m${LOCATION}\x1B[00m"
    exiftool -api largefilesupport=1 -overwrite_original -TagsFromFile "$LOCATION" -Location:all "$OUTPUT"
  fi

  # Use Finder/Spotlight comment as description if not set in environment
  if [ -z "$DESCRIPTION" ]; then
    COMMENT="$(mdls -raw -name kMDItemFinderComment "${METADATA}")"
    if [ -n "$COMMENT" ] && [ "$COMMENT" != "(null)" ]; then
      DESCRIPTION="$COMMENT"
    fi
  fi

  # Add description, rating, or keywords if they are set
  if [ -n "$DESCRIPTION" ] || [ -n "$RATING" ] || [ -n "$KEYWORDS" ]; then
    EXIF_CMD="exiftool -api largefilesupport=1 -overwrite_original"
    if [ -n "$DESCRIPTION" ]; then
      echo -e "\x1B[00;33mSet description to \x1B[01;35m${DESCRIPTION}\x1B[00m"
      EXIF_CMD="${EXIF_CMD} -description=\"${DESCRIPTION}\""
      /usr/bin/osascript -e "set filepath to POSIX file \"${OUTPUT}\"" \
        -e "set theFile to filepath as alias" \
        -e "tell application \"Finder\" to set the comment of theFile to \"$DESCRIPTION\""
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
    # Clear these to avoid leaking to the next video if this is a loop
    unset DESCRIPTION RATING KEYWORDS
  fi

  # Copy MacOS Finder tags from original file
  echo -e "\x1B[00;33mCopy MacOS Finder tags from \x1B[01;35m${METADATA}\x1B[00m"
  tag --add "$(tag --no-name --list "$METADATA")" "$OUTPUT"

  # Copy created and modified dates from original file
  echo -e "\x1B[00;33mCopy file created and modified date from \x1B[01;35m${METADATA}\x1B[00m"
  SetFile \
    -d "$(GetFileInfo -d "$METADATA")" \
    -m "$(GetFileInfo -m "$METADATA")" \
    "$OUTPUT"
  unset OUTPUT
done
