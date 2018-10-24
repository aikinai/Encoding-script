#!/usr/bin/env bash
# 
# rename-to-time.sh
# Renames video files based on their creation date
# Date format is a slightly modified ISO 8601
#

for FILE in $@
do

  EXTENSION="${FILE##*.}"
  EXTENSION="${EXTENSION,,}" # Convert to lowercase
  # MTS files have DateTimeOriginal set and MP4 files have LastUpdate
  case "${EXTENSION}" in
    mp4|MP4)
      DATETIME="$(exiftool -s -s -s -d "%Y-%m-%dT%H%M%S%z" -LastUpdate ${FILE})"
      FILEDATE="$(exiftool -s -s -s -d "%m/%d/%Y %H:%M:%S" -LastUpdate ${FILE})"
      ;;
    mts|MTS)
      DATETIME="$(exiftool -s -s -s -d "%Y-%m-%dT%H%M%S%z" -DateTimeOriginal ${FILE})"
      FILEDATE="$(exiftool -s -s -s -d "%m/%d/%Y %H:%M:%S" -DateTimeOriginal ${FILE})"
      ;;
  esac

  # Rename file to the ISO 8601 date
  NEWNAME="${DATETIME}.${EXTENSION}"
  echo -e "Rename ${FILE} → \x1B[00;33m${NEWNAME}\x1B[00m"
  mv -iv "${FILE}" "${NEWNAME}"

  # Set creation and modification dates to the same time
  echo -e "Set date → \x1B[00;33m${FILEDATE}\x1B[00m"
  SetFile \
    -d "${FILEDATE}" \
    -m "${FILEDATE}" \
    "${NEWNAME}"

done
