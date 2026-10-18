#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
python3 scripts/audio.py
ffmpeg -y -v error -i public/audio/mix-raw.wav -af loudnorm=I=-14:TP=-2:LRA=8 -ar 48000 public/audio/mix.wav
ffmpeg -y -v error -i public/audio/music-raw.wav -af loudnorm=I=-14:TP=-2:LRA=8 -ar 48000 public/audio/music.wav
npx tsc --noEmit
mkdir -p out
shasum -a 256 src/*.tsx src/*.ts production/timing.json public/fonts/CleanSans.woff2 > out/render-source.sha256
npx remotion render CleanFilm out/clean-master.mp4 --concurrency=6 --crf=16
shasum -a 256 -c out/render-source.sha256
ffmpeg -y -v error -i out/clean-master.mp4 -t 30 -c:v copy -c:a aac -b:a 192k -ar 48000 -movflags +faststart ../docs/assets/clean-product-film.mp4
ffmpeg -y -v error -i public/audio/music.wav -t 30 -c:a aac -b:a 192k ../docs/assets/clean-music-only.m4a
ffmpeg -y -v error -i ../docs/assets/clean-product-film.mp4 -frames:v 1 -q:v 2 ../docs/assets/clean-film-poster.jpg
ffmpeg -y -v error -i ../docs/assets/clean-product-film.mp4 -vf 'fps=0.5,scale=480:270,tile=5x3' -frames:v 1 production/contact-sheet.jpg
ffmpeg -y -v error -i ../docs/assets/clean-product-film.mp4 -vf 'fps=2,scale=320:180,tile=10x6' -frames:v 1 production/silent-contact-sheet.jpg
