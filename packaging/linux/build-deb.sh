#!/usr/bin/env bash
set -euo pipefail
version="$(awk '/^version: / {print $2}' pubspec.yaml)"
version="${version%+*}"
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]
bundle=build/linux/x64/release/bundle
stage=build/debian/zaskia
rm -rf "$stage"
install -d "$stage/DEBIAN" "$stage/usr/lib/zaskia" "$stage/usr/bin" \
  "$stage/usr/share/applications" "$stage/usr/share/icons/hicolor/scalable/apps" \
  "$stage/usr/share/doc/zaskia"
cp -a "$bundle/." "$stage/usr/lib/zaskia/"
cp -a build/llama/bin/*.so* "$stage/usr/lib/zaskia/"
install -m755 build/llama/bin/llama-server "$stage/usr/lib/zaskia/llama-server"
cc -O2 -Wall -Wextra -Werror packaging/linux/engine.c -o "$stage/usr/lib/zaskia/zaskia-engine"
cc -O2 -Wall -Wextra -Werror packaging/linux/managed-engine.c -o "$stage/usr/lib/zaskia/zaskia-managed-engine"
ln -s ../lib/zaskia/zaskia "$stage/usr/bin/zaskia"
install -m644 packaging/linux/zaskia.desktop "$stage/usr/share/applications/"
install -m644 packaging/linux/zaskia.svg "$stage/usr/share/icons/hicolor/scalable/apps/"
install -m644 vendor/llama.cpp/LICENSE "$stage/usr/share/doc/zaskia/llama.cpp-copyright"
cp -a vendor/llama.cpp/licenses "$stage/usr/share/doc/zaskia/third-party-licenses"
install -m644 vendor/llama.cpp/vendor/cpp-httplib/LICENSE "$stage/usr/share/doc/zaskia/third-party-licenses/cpp-httplib-LICENSE"
install -m644 packaging/linux/README.md "$stage/usr/share/doc/zaskia/README"
# Derive shared-library requirements from the actual binaries, on Debian 12.
mkdir -p debian
cat > debian/control <<CONTROL
Source: zaskia
Section: utils
Priority: optional
Maintainer: Zaskar Startup <zaskarstartup@users.noreply.github.com>

Package: zaskia
Architecture: amd64
Description: Ejecutor local de modelos de inteligencia artificial
CONTROL
mapfile -t binaries < <(find "$stage/usr/lib/zaskia" -type f -exec sh -c 'file -b "$1" | grep -q "ELF.*dynamically linked"' sh {} \; -print)
args=()
for binary in "${binaries[@]}"; do args+=("-e$binary"); done
deps="$(dpkg-shlibdeps -O --ignore-missing-info -l"$stage/usr/lib/zaskia/lib" -l"$stage/usr/lib/zaskia" "${args[@]}" | sed -n 's/^shlibs:Depends=//p')"
test -n "$deps"
cat > "$stage/DEBIAN/control" <<CONTROL
Package: zaskia
Version: $version
Section: utils
Priority: optional
Architecture: amd64
Maintainer: Zaskar Startup <zaskarstartup@users.noreply.github.com>
Depends: $deps
Recommends: fonts-noto-cjk, git, python3-venv, zstd
Installed-Size: $(du -sk "$stage/usr" | cut -f1)
Homepage: https://github.com/arcanokuro-art/ZASKIA
Description: ZASKIA - ejecutor local de modelos de IA
 Chat, biblioteca GGUF, descargas desde Hugging Face y conexión Ollama.
 Incluye un motor llama.cpp de texto por CPU. Los modelos se descargan aparte.
CONTROL
find "$stage" -type d -exec chmod 755 {} +
chmod 644 "$stage/DEBIAN/control"
dpkg-deb --root-owner-group --build "$stage" "ZASKIA-${version}-linux-amd64.deb"
dpkg-deb --info "ZASKIA-${version}-linux-amd64.deb"
sha256sum "ZASKIA-${version}-linux-amd64.deb" > "ZASKIA-${version}-linux-amd64.deb.sha256"
