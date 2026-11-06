#!/bin/sh
# Installs AniVerse for the current user: copies this bundle out of the build or
# download folder and adds it to the app menu, so docks and launchers can use it.
# Run it again from a newer build to update. Your watch history isn't touched.
set -eu

src=$(dirname "$(readlink -f "$0")")
data=${XDG_DATA_HOME:-$HOME/.local/share}
dest=$data/aniverse
id=com.animeapp.anime_watcher

if [ "$src" != "$dest" ]; then
  # Stage first, so a failed copy can't leave the installed app half-replaced.
  rm -rf "$dest.new"
  mkdir -p "$data"
  cp -r "$src" "$dest.new"
  rm -rf "$dest"
  mv "$dest.new" "$dest"
fi

for size in 48 64 128 256; do
  dir=$data/icons/hicolor/${size}x${size}/apps
  mkdir -p "$dir"
  cp "$dest/data/icons/aniverse-$size.png" "$dir/aniverse.png"
done

mkdir -p "$data/applications"
cat > "$data/applications/$id.desktop" <<DESKTOP
[Desktop Entry]
Type=Application
Name=AniVerse
Comment=Watch anime
Exec="$dest/anime_watcher"
Icon=aniverse
Terminal=false
Categories=AudioVideo;Video;Player;
StartupWMClass=$id
DESKTOP

command -v update-desktop-database >/dev/null 2>&1 &&
  update-desktop-database "$data/applications" || true
command -v gtk-update-icon-cache >/dev/null 2>&1 &&
  gtk-update-icon-cache -q -t "$data/icons/hicolor" || true

echo "Installed AniVerse to $dest"
