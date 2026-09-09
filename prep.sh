#!/bin/bash
set -e
PLAYLIST="https://www.youtube.com/playlist?list=PLDLkA3FbT-pZJN_n1pjQuLh2I09mrp9lL"
OUT="assets"
mkdir -p "$OUT"

NAMES=("Ember Hollow" "Mossbank" "The Long Dusk" "Riverstone" "Slatewater"
       "Willowdrift" "Amberfall" "Cedar Smoke" "Ashgrove" "Fernbrook"
       "Hearthlight" "Alderbank" "Quiet Ridge")

echo "📋 Reading playlist..."
yt-dlp --flat-playlist --print "%(id)s" "$PLAYLIST" > "$OUT/ids.txt"

MANIFEST="$OUT/manifest.json"
echo "[" > "$MANIFEST"
i=0; FIRST=1

while read -r VID; do
  [ -z "$VID" ] && continue
  ID=$(printf "scene_%02d" $((i+1)))
  NAME="${NAMES[$i]:-Scene $((i+1))}"

  if [ ! -f "$OUT/$ID.mp4" ]; then
    echo "⬇️  $ID — $NAME"
    yt-dlp --download-sections "*00:20:00-00:25:00" \
      -f "bestvideo[ext=mp4][height<=1080]+bestaudio[ext=m4a]/best[ext=mp4]/best" \
      --merge-output-format mp4 -o "$OUT/$ID.mp4" \
      "https://www.youtube.com/watch?v=$VID" || { echo "⚠️  skipped"; continue; }
  else
    echo "✅ $ID exists"
  fi

  # Full-resolution stills: the hero banner renders these at ~2200px on Retina,
  # so anything smaller than the source visibly softens.
  [ -f "$OUT/$ID.jpg" ] || ffmpeg -loglevel error -y -ss 30 -i "$OUT/$ID.mp4" \
      -frames:v 1 -vf "scale=1920:-1:flags=lanczos" -q:v 2 "$OUT/$ID.jpg"

  [ $FIRST -eq 0 ] && echo "," >> "$MANIFEST"
  FIRST=0
  printf '  {"id":"%s","title":"%s","video":"%s.mp4","thumb":"%s.jpg"}' \
    "$ID" "$NAME" "$ID" "$ID" >> "$MANIFEST"
  i=$((i+1))
done < "$OUT/ids.txt"

echo "" >> "$MANIFEST"; echo "]" >> "$MANIFEST"; rm "$OUT/ids.txt"
echo "🌲 $i scenes ready. Open $OUT/*.jpg, then reorder the titles in $MANIFEST to match."
