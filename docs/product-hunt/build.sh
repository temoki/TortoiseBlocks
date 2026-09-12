#!/bin/bash
# Product Hunt のギャラリー画像を gallery.html から作り直す。
#
#   ./docs/product-hunt/build.sh
#
# gallery.html の #s1 … #s5 を headless Chrome で 2x で撮り、1270x760
# （Product Hunt のギャラリー標準サイズ）に落として oxipng にかける。
# 2x で撮ってから縮めているのは、等倍で撮ると文字のアンチエイリアスが荒れるため。
#
# アルファチャンネルは落とす。Product Hunt は受け付けるが、このリポジトリの
# 画像は Tools/screenshots.rb 以来ずっと不透明で揃えてある。
#
# 必要なもの: Google Chrome, ImageMagick 7 (magick), oxipng。
set -euo pipefail

cd "$(dirname "$0")"

CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
[ -x "$CHROME" ] || { echo "Google Chrome が見つからない: $CHROME" >&2; exit 1; }

NAMES=(1-blocks-to-swift 2-calls-itself 3-watch-it-draw 4-on-the-table 5-nothing-collected)

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

for i in 1 2 3 4 5; do
  name=${NAMES[$((i - 1))]}
  "$CHROME" --headless=new --disable-gpu --hide-scrollbars \
    --force-device-scale-factor=2 --window-size=1270,760 \
    --virtual-time-budget=5000 \
    --screenshot="$TMP/$name.png" "file://$PWD/gallery.html#s$i" >/dev/null 2>&1
  [ -s "$TMP/$name.png" ] || { echo "撮影に失敗: $name" >&2; exit 1; }
  magick "$TMP/$name.png" -resize 1270x760 \
    -background white -alpha remove -alpha off -strip "$name.png"
  oxipng -o 4 -q "$name.png"
  echo "$name.png"
done

# 投稿フォームの Thumbnail 枠は 240x240。
magick ../../site/icon-256.png -resize 240x240 \
  -background white -alpha remove -alpha off -strip thumbnail-240.png
oxipng -o 4 -q thumbnail-240.png
echo "thumbnail-240.png"
