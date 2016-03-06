#!/bin/bash

# Video parameters
PRESET="slower"
PROFILE="high"
LEVEL="42"
RESOLUTION="1080"
BITRATE="8192k"
PIXELFORMAT="yuvj420p"

# Audio parameters
FREQUENCY="48"
AUDIOBITRATE="128"
STRATEGY="VBRC"
STRATEGY_NUM="2"
CHANNELS="2"

case $CHANNELS in
  1)
    LAYOUT="Mono" ;;
  2)
    LAYOUT="Stereo" ;;
  4)
    LAYOUT="Quadraphonic" ;;
  *)
    echo -e "\x1B[00;31mError: Strange number of channels.\x1B[00m"
    exit 1
esac

function cleanup()
{
  echo ""
  echo -e "\x1B[00;32mRemoving temporary files.\x1B[00m"
  # Remove temporary directory
  [ -d tmp ] && rm -rf tmp
  # Remove FFMPEG temporary files
  ls ffmpeg2* &> /dev/null && rm -rf ffmpeg2*
}

# Always remove temporary files on exit
trap cleanup EXIT

# Create temporary and output directories
[ -d tmp ] || mkdir tmp
[ -d MP4 ] || mkdir MP4

for INPUT in $@
do
  NAME=${INPUT%.*}

  VIDEO="tmp/${NAME}.mp4"
  AUDIOSOURCE="tmp/${NAME}.wav"
  AUDIO="tmp/${NAME}.m4a"

  OUTPUT="MP4/${NAME}.mp4"
  OUTPUT_FASTSTART="MP4/${NAME}_faststart.mp4"

  echo -e ""
  echo -e "\x1B[00;32mEncoding ${INPUT}\x1B[00m" >&2


  # Encode video
  ffmpeg -i $INPUT -c:v libx264 \
    -preset $PRESET -profile:v $PROFILE -b:v $BITRATE -level:v $LEVEL \
    -refs 6 \
    -pix_fmt $PIXELFORMAT \
    -an \
    -pass 1 -threads 4 -y $VIDEO 
  
  if [ $? -ne 0 ]; then
    echo -e "\x1B[00;31mError: Failed to encode video.\x1B[00m" >&2
    exit 1
  fi

  ffmpeg -i $INPUT -c:v libx264 \
    -preset $PRESET -profile:v $PROFILE -b:v $BITRATE -level:v $LEVEL \
    -refs 6 \
    -pix_fmt $PIXELFORMAT \
    -an \
    -pass 2 -threads 4 -y $VIDEO

  if [ $? -ne 0 ]; then
    echo -e "\x1B[00;31mError: Failed to encode video.\x1B[00m" >&2
    exit 1
  fi

  # Make audio source
  ffmpeg -i $INPUT \
    -c:a pcm_s16le -vn -y \
    -ac $CHANNELS \
    $AUDIOSOURCE

  if [ $? -ne 0 ]; then
    echo -e "\x1B[00;31mError: Failed to convert audio to lossless source.\x1B[00m" >&2
    exit 1
  fi

  # Encode audio
  afconvert -v \
    -f m4af -q 127 \
    -d aac@${FREQUENCY}'000' \
    -b ${AUDIOBITRATE}'000' \
    -s $STRATEGY_NUM \
    -c $CHANNELS \
    -l $LAYOUT \
    $AUDIOSOURCE \
    $AUDIO

  if [ $? -ne 0 ]; then
    echo -e "\x1B[00;31mError: Failed to encode audio.\x1B[00m" >&2
    exit 1
  fi

  # Mux audio and video
  ffmpeg \
    -i $VIDEO \
    -i $AUDIO \
    -map 0:0 -map 1:0 \
    -c:v copy -c:a copy \
    -y \
    $OUTPUT

  if [ $? -ne 0 ]; then
    echo -e "\x1B[00;31mError: Failed to multiplex audio and video.\x1B[00m" >&2
    exit 1
  fi

  # Run faststart to put the ATOM at the beginning for streaming
  qt-faststart $OUTPUT $OUTPUT_FASTSTART

  if [ $? -ne 0 ]; then
    echo -e "\x1B[00;31mError: Failed to move ATOM to beginning of file.\x1B[00m" >&2
    exit 1
  fi

  mv $OUTPUT_FASTSTART $OUTPUT || exit 1

done

exit 0
