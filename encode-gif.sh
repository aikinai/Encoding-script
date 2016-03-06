#!/usr/bin/env bash


PALETTE="/tmp/palette.png"

FILTERS="fps=30,scale=320:-1:flags=lanczos"

ffmpeg -v warning -i $1 -vf "$FILTERS,palettegen" -y $PALETTE
ffmpeg -v warning -i $1 -i $PALETTE -lavfi "$FILTERS [x]; [x][1:v] paletteuse" -y $2
