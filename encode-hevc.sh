#!/usr/bin/env bash
#
# encode-hevc.sh
# Encodes videos to HEVC/H.265 MOV/MP4 using ffmpeg + x265.
#
# Primary Apple HDR target:
#   QuickTime MOV, HEVC Main10, hvc1, Rec.2020 primaries, Rec.2100 HLG
#   transfer (ARIB STD-B67), BT.2020 non-constant matrix, limited/video range.
#
# Metadata:
#   - Copies as much source metadata as ffmpeg/exiftool can handle.
#   - Preserves important date/location/Finder metadata for Apple Photos.
#   - Copies created/modified filesystem dates when macOS developer tools are present.
#
# Finder rotation tags:
#   ↻  rotate clockwise
#   ↺  rotate counterclockwise
#   ⇅  rotate 180 degrees
#
# Environment options:
#   CRF           x265 CRF. Default: 20 for 10-bit HDR, 21 for SDR.
#   PRESET        x265 preset, e.g. slow, medium, fast. Default: medium.
#   TUNE          x265 tune, optional.
#   START         Input start time, passed as -ss.
#   STOP          Output stop time, passed as -to.
#   OUTPUT        Output file path. Only honored when encoding one input.
#   VIDEO         Optional separate video input. Audio is taken from the main input.
#   FILTER        Custom ffmpeg video filter chain.
#   SCALE         Output height. Width is computed with -2 for 4:2:0 compatibility.
#   NOAUDIO       If set, output has no audio.
#   AUDIO_CODEC   Audio codec. Default: libfdk_aac.
#   BILINGUAL     Hard-coded NHK Curious George stream mapping.
#   SUBTITLES     External subtitle file to add as soft subtitles.
#   SUB_LANG      Subtitle language. Default: eng.
#   METADATA_SOURCE  File to copy metadata from. Default: current input.
#   LOCATION      File to copy location metadata from.
#   DESCRIPTION   Description/caption.
#   RATING        Star rating, integer 1-5.
#   KEYWORDS      Comma-delimited keywords.
#   NOTCAMERA     If set, do not write Sony camera make/model metadata.
#   COLOR_MODE    Override color detection: auto, hlg, pq, sdr. Default: auto.
#   ALLOW_PQ_BT2020_FALLBACK
#                 If set, BT.2020 with unspecified transfer is treated as PQ.
#                 Default behavior treats that case as HLG because this script is
#                 optimized for Resolve Rec.2100 HLG ProRes intermediates.

set -euo pipefail
IFS=$'\n\t'

require_command() {
  local command_name="$1"
  if ! command -v "$command_name" >/dev/null 2>&1; then
    printf 'Error: required command not found: %s\n' "$command_name" >&2
    exit 127
  fi
}

warn_missing_command() {
  local command_name="$1"
  if ! command -v "$command_name" >/dev/null 2>&1; then
    printf 'Warning: optional command not found, skipping related step: %s\n' "$command_name" >&2
    return 1
  fi
  return 0
}

log_info() {
  printf '\033[00;33m%s\033[00m\n' "$*"
}

log_value() {
  printf '\033[00;33m%s \033[01;35m%s\033[00m\n' "$1" "$2"
}

ffprobe_stream_field() {
  local input_file="$1"
  local field_name="$2"

  ffprobe -v error -select_streams v:0 \
    -show_entries "stream=${field_name}" \
    -of default=nw=1:nk=1 \
    "$input_file" 2>/dev/null | head -n 1 || true
}

mediainfo_field() {
  local inform_string="$1"
  local input_file="$2"

  if command -v mediainfo >/dev/null 2>&1; then
    mediainfo --Inform="$inform_string" "$input_file" 2>/dev/null || true
  fi
}

get_file_mtime_utc() {
  local input_file="$1"

  if stat -c '%y' "$input_file" >/dev/null 2>&1; then
    TZ=UTC stat -c '%y' "$input_file" \
      | sed -n 's/\([[:digit:]]\{4\}-[[:digit:]]\{2\}-[[:digit:]]\{2\} [[:digit:]]\{2\}:[[:digit:]]\{2\}:[[:digit:]]\{2\}\).*/\1/p'
  else
    TZ=UTC stat -f '%Sm' -t '%Y-%m-%d %H:%M:%S' "$input_file"
  fi
}

escape_filter_path() {
  local path="$1"
  path="${path//\\/\\\\}"
  path="${path//:/\\:}"
  path="${path//\'/\\\'}"
  printf '%s' "$path"
}

join_by_comma() {
  local IFS=,
  printf '%s' "$*"
}

set_color_args() {
  local input_file="$1"
  local color_mode="${COLOR_MODE:-auto}"
  local primaries transfer matrix

  primaries="$(ffprobe_stream_field "$input_file" color_primaries)"
  transfer="$(ffprobe_stream_field "$input_file" color_transfer)"
  matrix="$(ffprobe_stream_field "$input_file" color_space)"

  # ffprobe may report unknown for ProRes files that still have QuickTime color
  # metadata readable by MediaInfo. Use MediaInfo as a fallback signal only.
  if [[ -z "$primaries" || "$primaries" == "unknown" || "$primaries" == "unspecified" ]]; then
    case "$(mediainfo_field 'Video;%colour_primaries%' "$input_file")" in
      BT.2020) primaries="bt2020" ;;
      BT.709) primaries="bt709" ;;
    esac
  fi

  if [[ -z "$transfer" || "$transfer" == "unknown" || "$transfer" == "unspecified" ]]; then
    case "$(mediainfo_field 'Video;%transfer_characteristics%' "$input_file")" in
      HLG|ARIB*|*B67*) transfer="arib-std-b67" ;;
      PQ|SMPTE*2084*|ST*2084*) transfer="smpte2084" ;;
      BT.709) transfer="bt709" ;;
    esac
  fi

  if [[ -z "$matrix" || "$matrix" == "unknown" || "$matrix" == "unspecified" ]]; then
    case "$(mediainfo_field 'Video;%matrix_coefficients%' "$input_file")" in
      "BT.2020 non-constant"|BT.2020*) matrix="bt2020nc" ;;
      BT.709) matrix="bt709" ;;
    esac
  fi

  color_mode="$(printf '%s' "$color_mode" | tr '[:upper:]' '[:lower:]')"

  if [[ "$color_mode" == "auto" ]]; then
    if [[ "$transfer" == "arib-std-b67" ]]; then
      color_mode="hlg"
    elif [[ "$transfer" == "smpte2084" ]]; then
      color_mode="pq"
    elif [[ "$primaries" == "bt2020" ]]; then
      # Resolve Rec.2100 HLG ProRes intermediates are the main HDR use case for
      # this script. If the transfer is missing but primaries are BT.2020, HLG is
      # the safer default for Apple Photos than incorrectly forcing PQ/ST 2084.
      if [[ -n "${ALLOW_PQ_BT2020_FALLBACK:-}" ]]; then
        color_mode="pq"
      else
        color_mode="hlg"
      fi
    else
      color_mode="sdr"
    fi
  fi

  case "$color_mode" in
    hlg)
      COLOR_ARG=(
        -color_primaries bt2020
        -color_trc arib-std-b67
        -colorspace bt2020nc
        -color_range tv
      )
      PIXFMT_ARG=(-pix_fmt yuv420p10le)
      X265_PARAMS_ARG=(-x265-params 'colorprim=bt2020:transfer=arib-std-b67:colormatrix=bt2020nc:range=limited:repeat-headers=1')
      DEFAULT_CRF=20
      COLOR_DESCRIPTION="Rec.2100 HLG / BT.2020 / Main10"
      ;;
    pq)
      COLOR_ARG=(
        -color_primaries bt2020
        -color_trc smpte2084
        -colorspace bt2020nc
        -color_range tv
      )
      PIXFMT_ARG=(-pix_fmt yuv420p10le)
      X265_PARAMS_ARG=(-x265-params 'colorprim=bt2020:transfer=smpte2084:colormatrix=bt2020nc:range=limited:repeat-headers=1')
      DEFAULT_CRF=20
      COLOR_DESCRIPTION="PQ/HDR10-style BT.2020 / Main10"
      ;;
    sdr|bt709|rec709)
      COLOR_ARG=(
        -color_primaries bt709
        -color_trc bt709
        -colorspace bt709
        -color_range tv
      )
      PIXFMT_ARG=(-pix_fmt yuv420p)
      X265_PARAMS_ARG=(-x265-params 'colorprim=bt709:transfer=bt709:colormatrix=bt709:range=limited:repeat-headers=1')
      DEFAULT_CRF=21
      COLOR_DESCRIPTION="Rec.709 SDR"
      ;;
    *)
      printf 'Error: invalid COLOR_MODE=%s. Use auto, hlg, pq, or sdr.\n' "$color_mode" >&2
      exit 2
      ;;
  esac

  if [[ -n "${CRF:-}" ]]; then
    CRF_ARG=(-crf "$CRF")
  else
    CRF_ARG=(-crf "$DEFAULT_CRF")
  fi

  log_value "Color mode:" "$COLOR_DESCRIPTION"
  log_value "Detected source color:" "primaries=${primaries:-unknown}, transfer=${transfer:-unknown}, matrix=${matrix:-unknown}"
}

set_creation_time_utc() {
  local metadata_file="$1"
  local extension="$2"

  case "$extension" in
    m2ts|M2TS)
      local duration_start
      duration_start="$(mediainfo_field 'General;%Duration_Start%' "$metadata_file" | sed -e 's/UTC //')"
      if [[ -n "$duration_start" ]] && date -d "$duration_start+09:00" >/dev/null 2>&1; then
        TZ=UTC date -d "$duration_start+09:00" +'%Y-%m-%d %H:%M:00'
      else
        get_file_mtime_utc "$metadata_file"
      fi
      ;;
    *)
      get_file_mtime_utc "$metadata_file"
      ;;
  esac
}

copy_specific_dates() {
  local metadata_file="$1"
  local output_file="$2"
  local extension="$3"

  if ! warn_missing_command exiftool; then
    return
  fi

  case "$extension" in
    mp4|MP4)
      log_value "Set CreationDate and DateTimeOriginal from" "$metadata_file CreationDateValue"
      exiftool -api largefilesupport=1 -overwrite_original \
        -tagsfromfile "$metadata_file" \
        '-CreationDate<CreationDateValue' \
        '-DateTimeOriginal<CreationDateValue' \
        "$output_file"
      ;;
    mts|MTS)
      log_value "Set CreationDate and DateTimeOriginal from" "$metadata_file CreationDate"
      local datetime
      datetime="$(exiftool -api largefilesupport=1 -s -s -s -DateTimeOriginal "$metadata_file" | sed -e 's/ [[:alpha:]]\+$//')"
      if [[ -n "$datetime" ]]; then
        exiftool -api largefilesupport=1 -overwrite_original \
          -DateTimeOriginal="$datetime" \
          -CreationDate="$datetime" \
          "$output_file"
      fi
      ;;
    m2ts|M2TS)
      log_value "Set CreationDate and DateTimeOriginal from" "$metadata_file Duration_Start"
      local duration_start datetime
      duration_start="$(mediainfo_field 'General;%Duration_Start%' "$metadata_file" | sed -e 's/UTC //')"
      if [[ -n "$duration_start" ]] && date -d "$duration_start" >/dev/null 2>&1; then
        datetime="$(date -d "$duration_start" +'%Y:%m:%d %H:%M:00%:z')"
        exiftool -api largefilesupport=1 -overwrite_original \
          -DateTimeOriginal="$datetime" \
          -CreationDate="$datetime" \
          "$output_file"
      fi
      ;;
  esac
}

copy_finder_dates() {
  local metadata_file="$1"
  local output_file="$2"

  if command -v SetFile >/dev/null 2>&1 && command -v GetFileInfo >/dev/null 2>&1; then
    log_value "Copy file created and modified date from" "$metadata_file"
    SetFile \
      -d "$(GetFileInfo -d "$metadata_file")" \
      -m "$(GetFileInfo -m "$metadata_file")" \
      "$output_file"
  else
    log_info "SetFile/GetFileInfo not found; preserving modified date only with touch."
    touch -r "$metadata_file" "$output_file" || true
  fi
}

copy_finder_tags() {
  local metadata_file="$1"
  local output_file="$2"

  if command -v tag >/dev/null 2>&1; then
    local tags
    tags="$(tag --no-name --list "$metadata_file" || true)"
    if [[ -n "$tags" ]]; then
      log_value "Copy macOS Finder tags from" "$metadata_file"
      tag --add "$tags" "$output_file"
    fi
  fi
}

set_finder_comment() {
  local output_file="$1"
  local description="$2"

  if command -v osascript >/dev/null 2>&1; then
    /usr/bin/osascript - "$output_file" "$description" <<'APPLESCRIPT' || true
on run argv
  set filepath to POSIX file (item 1 of argv)
  set theFile to filepath as alias
  tell application "Finder" to set the comment of theFile to (item 2 of argv)
end run
APPLESCRIPT
  fi
}

if (( $# == 0 )); then
  printf 'Usage: %s input1 [input2 ...]\n' "$(basename "$0")" >&2
  exit 64
fi

require_command ffmpeg
require_command ffprobe
require_command realpath

if [[ -n "${OUTPUT:-}" && $# -gt 1 ]]; then
  printf 'Error: OUTPUT may only be used when encoding a single input.\n' >&2
  exit 64
fi

for INPUT in "$@"; do
  if [[ ! -f "$INPUT" ]]; then
    printf 'Error: input file not found: %s\n' "$INPUT" >&2
    exit 66
  fi

  DIRECTORY="$(dirname "$INPUT")"
  FULLPATH="$(realpath "$DIRECTORY")"
  BASENAME="$(basename "${INPUT%.*}")"
  EXTENSION="${INPUT##*.}"

  if [[ -n "${OUTPUT:-}" ]]; then
    OUTPUT_PATH="$OUTPUT"
  else
    OUTPUT_PATH="${FULLPATH}/${BASENAME}.mov"
    if [[ -f "$OUTPUT_PATH" ]]; then
      OUTPUT_PATH="${FULLPATH}/${BASENAME}-hevc.mov"
    fi
  fi

  if [[ -n "${METADATA_SOURCE:-}" ]]; then
    METADATA="$METADATA_SOURCE"
  else
    METADATA="$INPUT"
  fi

  if [[ ! -f "$METADATA" ]]; then
    printf 'Error: metadata source not found: %s\n' "$METADATA" >&2
    exit 66
  fi

  log_value "Input:" "$INPUT"
  log_value "Output:" "$OUTPUT_PATH"

  START_ARG=()
  if [[ -n "${START:-}" ]]; then
    START_ARG=(-ss "$START")
  fi

  STOP_ARG=()
  if [[ -n "${STOP:-}" ]]; then
    STOP_ARG=(-to "$STOP")
  fi

  PRESET_ARG=(-preset "${PRESET:-medium}")

  TUNE_ARG=()
  if [[ -n "${TUNE:-}" ]]; then
    TUNE_ARG=(-tune "$TUNE")
  fi

  VIDEO_ARG=()
  if [[ -n "${VIDEO:-}" ]]; then
    VIDEO_ARG=(
      -i "$VIDEO"
      -map 1:v:0
      -map 0:a:0
    )
  fi

  if [[ -n "${NOAUDIO:-}" ]]; then
    AUDIO_ARG=(-an)
  else
    AUDIO_ARG=(-c:a "${AUDIO_CODEC:-libfdk_aac}")
  fi

  BILINGUAL_ARG=()
  if [[ -n "${BILINGUAL:-}" ]]; then
    BILINGUAL_ARG=(
      -map 0:0 -map 0:1 -map 0:11
      -metadata:s:v:0 language=jpn
      -metadata:s:a:0 language=jpn
      -metadata:s:a:1 language=eng
    )
  fi

  SUBTITLE_INPUT_ARG=()
  SUBTITLE_CODEC_ARG=()
  if [[ -n "${SUBTITLES:-}" ]]; then
    SUBTITLE_INPUT_ARG=(-i "$SUBTITLES")
    SUBTITLE_CODEC_ARG=(
      -c:s mov_text
      -metadata:s:s:0 language="${SUB_LANG:-eng}"
    )
  elif [[ -n "$(mediainfo_field 'Text;%ID%' "$INPUT")" ]]; then
    SUBTITLE_CODEC_ARG=(
      -c:s mov_text
      -metadata:s:s:0 language="${SUB_LANG:-eng}"
    )
  fi

  FORMAT_ARG=()
  if [[ "$OUTPUT_PATH" == *.m4v ]]; then
    FORMAT_ARG=(-f mp4)
  fi

  TIME_UTC="$(set_creation_time_utc "$METADATA" "$EXTENSION")"

  CAMERA_ARG=()
  if [[ -z "${NOTCAMERA:-}" ]]; then
    CAMERA_ARG=(
      -metadata make=Sony
      -metadata model=ILCE-7CM2
    )
  fi

  VIDEO_FILTERS=()

  if command -v tag >/dev/null 2>&1; then
    FINDER_TAGS="$(tag -lN "$INPUT" 2>/dev/null || true)"
    if [[ "$FINDER_TAGS" == *"↻"* ]]; then
      VIDEO_FILTERS+=(transpose=1)
    elif [[ "$FINDER_TAGS" == *"↺"* ]]; then
      VIDEO_FILTERS+=(transpose=2)
    elif [[ "$FINDER_TAGS" == *"⇅"* ]]; then
      VIDEO_FILTERS+=(transpose=2 transpose=2)
    fi
  fi

  if [[ -n "${FILTER:-}" ]]; then
    VIDEO_FILTERS+=("$FILTER")
  fi

  if [[ -n "${SCALE:-}" ]]; then
    VIDEO_FILTERS+=("scale=-2:${SCALE}")
  fi

  if [[ -f "${DIRECTORY}/${BASENAME}.srt" ]]; then
    SRT_FILTER_PATH="$(escape_filter_path "${DIRECTORY}/${BASENAME}.srt")"
    VIDEO_FILTERS+=("subtitles='${SRT_FILTER_PATH}':force_style='FontName=Myriad Pro,Fontsize=24,OutlineColour=&H30333333,Bold=600'")
  fi

  FILTER_ARG=()
  if (( ${#VIDEO_FILTERS[@]} > 0 )); then
    FILTER_ARG=(-vf "$(join_by_comma "${VIDEO_FILTERS[@]}")")
  fi

  set_color_args "$INPUT"

  FFMPEG_ARGS=(
    -n
    -fflags +genpts
    "${START_ARG[@]}"
    -i "$INPUT"
    "${VIDEO_ARG[@]}"
    "${SUBTITLE_INPUT_ARG[@]}"
    "${STOP_ARG[@]}"
    -c:v libx265
    "${AUDIO_ARG[@]}"
    "${SUBTITLE_CODEC_ARG[@]}"
    "${PIXFMT_ARG[@]}"
    "${PRESET_ARG[@]}"
    "${TUNE_ARG[@]}"
    "${CRF_ARG[@]}"
    "${X265_PARAMS_ARG[@]}"
    "${FILTER_ARG[@]}"
    "${BILINGUAL_ARG[@]}"
    -tag:v hvc1
    -flags +global_header
    -movflags +faststart
    -map_metadata 0
    -map_metadata:s:v 0:s:v
    -map_metadata:s:a 0:s:a
    -metadata creation_time="$TIME_UTC"
    -metadata creation_date="$TIME_UTC"
    -write_tmcd 0
    "${CAMERA_ARG[@]}"
    "${COLOR_ARG[@]}"
    "${FORMAT_ARG[@]}"
    "$OUTPUT_PATH"
  )

  log_value "Encode CRF:" "${CRF_ARG[1]}"
  log_value "Encode preset:" "${PRESET_ARG[1]}"
  if (( ${#FILTER_ARG[@]} > 0 )); then
    log_value "Video filters:" "${FILTER_ARG[1]}"
  fi

  TZ=UTC ffmpeg "${FFMPEG_ARGS[@]}"

  if command -v exiftool >/dev/null 2>&1; then
    log_value "Copy all metadata from" "$METADATA"
    exiftool -api largefilesupport=1 -overwrite_original -extractEmbedded \
      -TagsFromFile "$METADATA" \
      '-all:all>all:all' \
      "$OUTPUT_PATH"

    copy_specific_dates "$METADATA" "$OUTPUT_PATH" "$EXTENSION"
  else
    log_info "exiftool not found; skipping extended metadata copy."
  fi

  if [[ -n "${LOCATION:-}" ]]; then
    if command -v exiftool >/dev/null 2>&1; then
      log_value "Copy location from" "$LOCATION"
      exiftool -api largefilesupport=1 -overwrite_original \
        -TagsFromFile "$LOCATION" \
        -Location:all \
        "$OUTPUT_PATH"
    else
      log_info "exiftool not found; cannot copy location metadata."
    fi
  fi

  THIS_DESCRIPTION="${DESCRIPTION:-}"
  THIS_RATING="${RATING:-}"
  THIS_KEYWORDS="${KEYWORDS:-}"

  if [[ -z "$THIS_DESCRIPTION" ]] && command -v mdls >/dev/null 2>&1; then
    COMMENT="$(mdls -raw -name kMDItemFinderComment "$METADATA" 2>/dev/null || true)"
    if [[ -n "$COMMENT" && "$COMMENT" != "(null)" ]]; then
      THIS_DESCRIPTION="$COMMENT"
    fi
  fi

  if command -v exiftool >/dev/null 2>&1 \
    && { [[ -n "$THIS_DESCRIPTION" ]] || [[ -n "$THIS_RATING" ]] || [[ -n "$THIS_KEYWORDS" ]]; }; then

    EXIF_ARGS=(-api largefilesupport=1 -overwrite_original)

    if [[ -n "$THIS_DESCRIPTION" ]]; then
      log_value "Set description to" "$THIS_DESCRIPTION"
      EXIF_ARGS+=(-description="$THIS_DESCRIPTION")
      set_finder_comment "$OUTPUT_PATH" "$THIS_DESCRIPTION"
    fi

    if [[ -n "$THIS_RATING" ]]; then
      log_value "Set rating to" "$THIS_RATING"
      EXIF_ARGS+=(-rating="$THIS_RATING")
    fi

    if [[ -n "$THIS_KEYWORDS" ]]; then
      log_value "Set keywords to" "$THIS_KEYWORDS"
      EXIF_ARGS+=(-sep ', ' -keywords="$THIS_KEYWORDS")
    fi

    exiftool "${EXIF_ARGS[@]}" "$OUTPUT_PATH"
  fi

  copy_finder_tags "$METADATA" "$OUTPUT_PATH"
  copy_finder_dates "$METADATA" "$OUTPUT_PATH"

  log_info "ffprobe color check:"
  ffprobe -hide_banner -select_streams v:0 \
    -show_entries stream=codec_name,profile,pix_fmt,color_range,color_space,color_transfer,color_primaries,codec_tag_string \
    -of default=nw=1 \
    "$OUTPUT_PATH" || true

done
