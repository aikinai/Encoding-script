#!/bin/bash
#
# EncodeAudio.sh
#
# Alan Rogers
# 2013/10/03
#
# Encodes audio files using Apple's encoder

mkdir M4A

# Audio parameters
     BITRATE="256"
    STRATEGY="VBRC"
STRATEGY_NUM="2"
    CHANNELS="2"

for INPUT in "$@"
do
      NAME="${INPUT%.*}"
    OUTPUT="M4A/${NAME}.m4a"

    pwd
    echo $INPUT
    echo $NAME
    echo $OUTPUT

    # Encode audio
    afconvert -v \
        -f m4af -q 127 \
        -d aac \
        -b ${BITRATE}'000' \
        -s $STRATEGY_NUM \
        "$INPUT" \
        "$OUTPUT"
done

exit 0
