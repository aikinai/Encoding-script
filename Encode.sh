#!/bin/bash

# Video parameters
PRESET="slower"
PROFILE="high"
LEVEL="41"
RESOLUTION="720"
BITRATE="1024k"

# Audio parameters
FREQUENCY="48"
AUDIOBITRATE="64"
STRATEGY="VBRC"
STRATEGY_NUM="2"
CHANNELS="2"

for INPUT in $@
do
    NAME=${INPUT%.*}
    
    VIDEO="NoAudio/${NAME}.mp4"
    AUDIOSOURCE="NoAudio/${NAME}.wav"
    AUDIO="NoAudio/${NAME}.m4a"

    OUTPUT="MP4/${NAME}.mp4"
    OUTPUT_FASTSTART="MP4/${NAME}_faststart.mp4"

    # Encode video
    ffmpeg -i $INPUT -c:v libx264 \
        -vf scale=-1:$RESOLUTION \
        -preset $PRESET -profile:v $PROFILE -b:v $BITRATE -level:v $LEVEL \
        -refs 6 \
        -pix_fmt yuv420p \
        -an -pass 1 -threads 4 -y $VIDEO 

    ffmpeg -i $INPUT -c:v libx264 \
        -vf scale=-1:$RESOLUTION \
        -preset $PRESET -profile:v $PROFILE -b:v $BITRATE -level:v $LEVEL \
        -refs 6 \
        -pix_fmt yuv420p \
        -an \
        -pass 2 -threads 4 -y $VIDEO

    # Make audio source
    ffmpeg -i $INPUT \
        -c:a pcm_s16le -vn -y \
        -ac $CHANNELS
        $AUDIOSOURCE

    # Encode audio
    afconvert -v \
        -f m4af -q 127 \
        -d aac@${FREQUENCY}'000' \
        -b ${AUDIOBITRATE}'000' \
        -s $STRATEGY_NUM \
        $AUDIOSOURCE \
        $AUDIO

    # Mux audio and video
    ffmpeg \
        -i $VIDEO \
        -i $AUDIO \
        -map 0:0 -map 1:0 \
        -c:v copy -c:a copy \
        -y \
        $OUTPUT

    # Run faststart to put the ATOM at the beginning for streaming
    qt-faststart $OUTPUT $OUTPUT_FASTSTART
    mv $OUTPUT_FASTSTART $OUTPUT

done

rm ffmpeg2*

exit 0
