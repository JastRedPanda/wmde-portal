# Maintainer: WMDE <https://wmde.fun>
# Contributor: System76 <jeremy@system76.com> (original xdg-desktop-portal-cosmic)
# Builds our fork Lin-WMDE/wmde-portal (branch wmde; master mirrors pop-os upstream).
# WMDE-branded XDG desktop portal: serves org.freedesktop.impl.portal.Settings
# (color-scheme + accent) from the fun.wmde config so libcosmic apps switch theme/
# accent live. Built against ../libcosmic (fun.wmde config ids). Coexists with the
# stock xdg-desktop-portal-cosmic: distinct D-Bus name + distinct installed file names.
pkgname=wmde-portal
pkgver=1.5.0
pkgrel=2
pkgdesc="WMDE XDG desktop portal (fork of xdg-desktop-portal-cosmic; fun.wmde Settings backend)"
arch=('x86_64')
url="https://wmde.fun"
license=('GPL-3.0-or-later')
# !lto: makepkg's lto adds -flto to CFLAGS, so pipewire/libspa's wrap-static-fns C shim
# (static_fns.c, the *_libspa_rs symbols) compiles to GCC LTO bitcode that the Rust
# link's lld cannot read -> "undefined reference to *_libspa_rs" (breaks ScreenCast).
# Keeping it off makes the shim a normal object. !debug: skip the split-debug package for
# this large statically-linked libcosmic binary. Cargo's own release LTO still applies.
options=('!lto' '!debug')
# depends: libcosmic runtime set (same as wmde-files) + pipewire (ScreenCast) and the
# xdg-desktop-portal frontend this backend plugs into. Verify with namcap if in doubt.
depends=('glibc' 'gcc-libs' 'glib2' 'libxkbcommon' 'wayland' 'mesa' 'fontconfig'
         'freetype2' 'pipewire' 'xdg-desktop-portal')
# makedepends: toolchain/libs that build the fork in Docker + pipewire headers for
# the pipewire-sys/spa-sys bindgen build.
makedepends=('rust' 'cargo' 'git' 'clang' 'lld' 'pkgconf' 'glib2' 'mesa' 'wayland'
             'libxkbcommon' 'fontconfig' 'freetype2' 'expat' 'zstd' 'pipewire')
source=("$pkgname::git+https://github.com/Lin-WMDE/wmde-portal.git#branch=wmde")
sha256sums=('SKIP')

pkgver() {
  cd "$srcdir/$pkgname"
  # WMDE unified version: 1.5 (libcosmic base) . <commits since nearest tag> . g<short>.
  local desc
  desc=$(git describe --long --tags --abbrev=7 2>/dev/null || true)
  if [ -n "$desc" ]; then
    printf '1.6.%s.g%s' "$(printf '%s' "$desc" | sed -E 's/.*-([0-9]+)-g[0-9a-f]+$/\1/')" "$(git rev-parse --short=7 HEAD)"
  else
    printf '1.6.%s.g%s' "$(git rev-list --count HEAD)" "$(git rev-parse --short=7 HEAD)"
  fi
}

build() {
  cd "$srcdir/$pkgname"
  # x86-64-v3 (AVX2/BMI2) baseline for the WMDE repo; runs on Haswell+ (and the VM).
  export RUSTFLAGS="${RUSTFLAGS:+$RUSTFLAGS }-C target-cpu=x86-64-v3"
  # link the system libzstd; the vendored zstd-sys build drops symbols under lld
  export ZSTD_SYS_USE_PKG_CONFIG=1

  # NOTE: the *_libspa_rs undefined-symbol link failure that pipewire/libspa's
  # wrap-static-fns C shim otherwise causes here is avoided by options=('!lto') above
  # (which keeps -flto out of CFLAGS so the shim is a normal object lld can read).
  cargo build --release --bin xdg-desktop-portal-cosmic
}

package() {
  cd "$srcdir/$pkgname"
  # The Cargo package/binary name stays upstream (xdg-desktop-portal-cosmic) so the
  # embedded i18n domain resolves; install it under a distinct name to coexist with
  # the stock package's /usr/libexec/xdg-desktop-portal-cosmic.
  install -Dm755 "${CARGO_TARGET_DIR:-target}/release/xdg-desktop-portal-cosmic" \
    "$pkgdir/usr/libexec/xdg-desktop-portal-wmde"

  # Portal backend descriptor (Settings/Access/FileChooser/Screenshot/ScreenCast).
  install -Dm644 data/wmde.portal \
    "$pkgdir/usr/share/xdg-desktop-portal/portals/wmde.portal"

  # Routes the WMDE desktop's portal requests to the wmde backend.
  install -Dm644 data/wmde-portals.conf \
    "$pkgdir/usr/share/xdg-desktop-portal/wmde-portals.conf"

  # D-Bus activation + systemd user service (bake the libexec path of our binary).
  sed 's|@libexecdir@|/usr/libexec|' \
    data/dbus-1/org.freedesktop.impl.portal.desktop.wmde.service.in \
    | install -Dm644 /dev/stdin \
      "$pkgdir/usr/share/dbus-1/services/org.freedesktop.impl.portal.desktop.wmde.service"
  sed 's|@libexecdir@|/usr/libexec|' \
    data/org.freedesktop.impl.portal.desktop.wmde.service.in \
    | install -Dm644 /dev/stdin \
      "$pkgdir/usr/lib/systemd/user/org.freedesktop.impl.portal.desktop.wmde.service"

  # App-bundled screenshot-mode icons (the Screenshot UI looks them up by name).
  find data/icons -type f | while read -r f; do
    install -Dm644 "$f" "$pkgdir/usr/share/icons/hicolor/${f#data/icons/}"
  done

  install -Dm644 LICENSE "$pkgdir/usr/share/licenses/$pkgname/LICENSE"
}
