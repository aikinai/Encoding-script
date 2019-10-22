#!/usr/bin/env bash
# 
# rename-to-time.sh
# Renames video files based on their creation date
# Date format is a slightly modified ISO 8601
#

for FILE in "$@"
do
  DIRECTORY="$(dirname "${FILE}")"
  BASENAME="${FILE%.*}"
  EXTENSION="${FILE##*.}"
  EXTENSION="${EXTENSION,,}" # Convert to lowercase
  # MTS files have DateTimeOriginal, MP4 files have LastUpdate, and MOV files 
  # have CreateDate. This is just a casual observation, not something I 
  # determined from any particular spec.
  case "${EXTENSION}" in
    mp4|MP4)
      DATETIME="$(exiftool -api largefilesupport=1 -s -s -s -d "%Y-%m-%dT%H%M%S%z" -LastUpdate "${FILE}")"
      FILEDATE="$(exiftool -api largefilesupport=1 -s -s -s -d "%m/%d/%Y %H:%M:%S" -LastUpdate "${FILE}")"
      ;;
    mts|MTS)
      DATETIME="$(exiftool -api largefilesupport=1 -s -s -s -d "%Y-%m-%dT%H%M%S%z" -DateTimeOriginal "${FILE}")"
      FILEDATE="$(exiftool -api largefilesupport=1 -s -s -s -d "%m/%d/%Y %H:%M:%S" -DateTimeOriginal "${FILE}")"
      ;;
    mov|MOV)
      DATETIME="$(exiftool -api largefilesupport=1 -s -s -s -d "%Y-%m-%dT%H%M%S%z" -CreateDate "${FILE}")"
      FILEDATE="$(exiftool -api largefilesupport=1 -s -s -s -d "%m/%d/%Y %H:%M:%S" -CreateDate "${FILE}")"
      ;;
    xml|XML)
      break # XML files handled later to make sure the name matches perfectly
      ;;
  esac

  # Rename file to the ISO 8601 date
  NEWNAME="${DATETIME}.${EXTENSION}"
  DESTINATION="${DIRECTORY}"/"${NEWNAME}"
  echo -e "Rename ${FILE} → \x1B[00;33m${NEWNAME}\x1B[00m"
  mv -iv "${FILE}" "${DESTINATION}"

  # Rename matching XML file if it exists
  # The for loop is the best way to test if the file exists with globbing
  # XML files have names like `C0001M01.XML` to match `C0001.MP4` so I use the
  # globbing to be sure I get the matching XML file and rename with the exact
  # same time as the video.
  for XMLFILE in "${BASENAME}"*.XML; do
    if [ -e "$XMLFILE" ]; then
      echo -e "Rename ${XMLFILE} → \x1B[00;33m${DATETIME}.xml\x1B[00m"
      mv -iv "${XMLFILE}" "${DIRECTORY}"/"${DATETIME}".xml
    fi
    # Don't actually need the loop, so break if it finds one
    break
  done

  # Set creation and modification dates to the same time
  echo -e "Set date → \x1B[00;33m${FILEDATE}\x1B[00m"
  SetFile \
    -d "${FILEDATE}" \
    -m "${FILEDATE}" \
    "${DESTINATION}"

done
