#!/usr/bin/env bash
# 
# rename-to-time.sh
# Renames files based on their creation date
# Date format is a slightly modified ISO 8601
#

for FILE in $@
do
  # Get the modification date and convert it to ISO 8601 (simple time) format
  DATETIME=$(date --date="$(GetFileInfo -d "${FILE}")" -Iseconds | sed 's/://g')
  # Get the extension
  EXTENSION="${FILE##*.}"
  # Convert the extension to lowercase
  EXTENSION="${EXTENSION,,}"
  # Rename file to the ISO 8601 date
  mv -iv "${FILE}" "${DATETIME}.${EXTENSION}"
done
