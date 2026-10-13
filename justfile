# Cargo package/binary name (kept as upstream so the embedded i18n domain still
# resolves the xdg_desktop_portal_cosmic.ftl files).
name := 'xdg-desktop-portal-cosmic'
# Чтобы shell() работал и на Windows с Git Bash; на Linux игнорируется
set windows-shell := ["C:\\Program Files\\Git\\bin\\sh.exe", "-cu"]
# Installed binary name and D-Bus identity, rebranded so this coexists with the
# stock xdg-desktop-portal-cosmic package (distinct file names + bus name).
bin-name := 'xdg-desktop-portal-wmde'
appid := 'org.freedesktop.impl.portal.desktop.wmde'

rootdir := ''
prefix := '/usr'

base-dir := absolute_path(clean(rootdir / prefix))

# Path baked into the installed service files (without rootdir)
libexecdir := clean(prefix / 'libexec')

# Installation target paths
data-dir := base-dir / 'share'
lib-dir := base-dir / 'lib'
icons-dir := data-dir / 'icons' / 'hicolor'

cargo-target-dir := env('CARGO_TARGET_DIR', 'target')

# Set debug=1 to build with the debug profile instead of release
debug := '0'
target := if debug == '0' { 'release' } else { 'debug' }
profile-args := if debug == '0' { '--release' } else { '' }

# Set vendor=1 to build offline from the vendored tarball
vendor := '0'
vendor-args := if vendor == '0' { '' } else { '--frozen' }

bin-src := cargo-target-dir / target / name
bin-dst := absolute_path(clean(rootdir / libexecdir)) / bin-name

[private]
default: build

# Builds the application
build: vendor-check
    cargo build {{ profile-args }} {{ vendor-args }} --bin {{ name }}

# Removes the target directory
clean:
    rm -rf {{ cargo-target-dir }}

# Removes the target directory and vendored dependencies
distclean: clean
    rm -rf .cargo vendor vendor.tar

# Installs files
install:
    install -Dm0755 {{ bin-src }} {{ bin-dst }}
    sed 's|@libexecdir@|{{ libexecdir }}|' data/dbus-1/{{ appid }}.service.in \
        | install -Dm0644 /dev/stdin {{ data-dir }}/dbus-1/services/{{ appid }}.service
    sed 's|@libexecdir@|{{ libexecdir }}|' data/{{ appid }}.service.in \
        | install -Dm0644 /dev/stdin {{ lib-dir }}/systemd/user/{{ appid }}.service
    install -Dm0644 data/wmde.portal {{ data-dir }}/xdg-desktop-portal/portals/wmde.portal
    install -Dm0644 data/wmde-portals.conf {{ data-dir }}/xdg-desktop-portal/wmde-portals.conf
    @if [ -d 'data'/'icons' ]; then find 'data'/'icons' -type f -exec echo {} \; | rev | cut -d'/' -f-3 | rev | xargs -d '\n' -I {} install -Dm0644 'data'/'icons'/{} {{ icons-dir }}/{}; fi

# Vendors Cargo dependencies into a tarball
vendor:
    rm -rf .cargo
    mkdir -p .cargo
    cargo vendor | head -n -1 > .cargo/config.toml
    echo 'directory = "vendor"' >> .cargo/config.toml
    echo >> .cargo/config.toml
    echo '[env]' >> .cargo/config.toml
    if [ -n "${SOURCE_DATE_EPOCH}" ]; then \
        source_date="$(date -d "@${SOURCE_DATE_EPOCH}" "+%Y-%m-%d")"; \
        echo "VERGEN_GIT_COMMIT_DATE = \"${source_date}\"" >> .cargo/config.toml; \
    fi
    if [ -n "${SOURCE_GIT_HASH}" ]; then \
        echo "VERGEN_GIT_SHA = \"${SOURCE_GIT_HASH}\"" >> .cargo/config.toml; \
    fi
    tar pcf vendor.tar .cargo vendor
    rm -rf .cargo vendor

# Extracts the vendored dependencies when vendor=1
[private]
vendor-check:
    if [ '{{ vendor }}' != '0' ]; then \
        rm -rf vendor && tar xf vendor.tar; \
    fi

# Версия пакета как pkgver() в PKGBUILD: 1.10.0.<commits>.g<sha>.
# Теги epoch-* дают только счётчик через git describe, fallback — rev-list.
wmde-version := shell('desc=$(git describe --long --tags --abbrev=7 2>/dev/null || true); if [ -n "$desc" ]; then printf "1.10.0.%s.g%s" "$(printf "%s" "$desc" | sed -E "s/.*-([0-9]+)-g[0-9a-f]+$/\\1/")" "$(git rev-parse --short=7 HEAD)"; else printf "1.10.0.%s.g%s" "$(git rev-list --count HEAD)" "$(git rev-parse --short=7 HEAD)"; fi')
# CPU-baseline: пусто = чистый x86-64 (для deb/rpm по умолчанию), для v3: WMDE_CPU=x86-64-v3
wmde-cpu := env('WMDE_CPU', '')

# Раскладывает собранное в target/staging (тот же набор, что PKGBUILD кладёт в $pkgdir).
# ZSTD_SYS_USE_PKG_CONFIG=1 — как в PKGBUILD: системный libzstd, иначе
# vendored zstd-sys роняет символы под lld.
package-staging staging="target/staging":
    #!/usr/bin/env bash
    set -e
    rm -rf {{staging}}
    if [ -n "{{wmde-cpu}}" ]; then export RUSTFLAGS="${RUSTFLAGS:+$RUSTFLAGS }-C target-cpu={{wmde-cpu}}"; fi
    export ZSTD_SYS_USE_PKG_CONFIG=1
    just build
    just rootdir="{{staging}}" prefix=/usr install
    # makepkg на Arch стрипает бинарники сам, в deb/rpm это делаем руками
    strip --strip-unneeded "{{staging}}/usr/libexec/"* 2>/dev/null || true
    just package-doc "{{staging}}"

# doc для deb/rpm: копирайт + changelog.yaml (nFPM сам разложит changelog
# в changelog.Debian.gz для deb и в %changelog для rpm)
package-doc staging="target/staging":
    #!/usr/bin/env bash
    set -e
    mkdir -p "{{staging}}/usr/share/doc/wmde-portal"
    cp packaging/copyright "{{staging}}/usr/share/doc/wmde-portal/copyright"
    chmod 644 "{{staging}}/usr/share/doc/wmde-portal/copyright"
    printf -- '- semver: %s\n  date: %s\n  packager: WMDE <wmde@wmde.fun>\n  urgency: low\n  distribution: unstable\n  deb:\n    urgency: low\n    distributions:\n      - unstable\n  changes:\n    - note: Automated build via nFPM (see INSTALL.deb-rpm.md).\n' "{{wmde-version}}-1" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > target/changelog.yaml

# Стейджинг из вендора: сборка без сети к git-зависимостям.
# vendor.tar генерим один раз при наличии сети (`just vendor`), сам тарболл
# в git не коммитится (см. .gitignore), на офлайн-машину его привозим файлом.
package-staging-vendored staging="target/staging":
    #!/usr/bin/env bash
    set -e
    rm -rf {{staging}}
    if [ ! -f vendor.tar ]; then just vendor; fi
    if [ -n "{{wmde-cpu}}" ]; then export RUSTFLAGS="${RUSTFLAGS:+$RUSTFLAGS }-C target-cpu={{wmde-cpu}}"; fi
    export ZSTD_SYS_USE_PKG_CONFIG=1
    just vendor=1 build
    just rootdir="{{staging}}" prefix=/usr install
    strip --strip-unneeded "{{staging}}/usr/libexec/"* 2>/dev/null || true
    just package-doc "{{staging}}"
    rm -rf vendor .cargo

# Собирает .deb через nFPM (нужен nfpm в PATH)
deb:
    #!/usr/bin/env bash
    set -e
    just package-staging
    export WMDE_VERSION="{{wmde-version}}"
    nfpm package --config packaging/nfpm.yaml --packager deb --target target/

# Собирает .rpm через nFPM (нужен nfpm в PATH)
rpm:
    #!/usr/bin/env bash
    set -e
    just package-staging
    export WMDE_VERSION="{{wmde-version}}"
    nfpm package --config packaging/nfpm.yaml --packager rpm --target target/

# .deb из вендора (офлайн-сборка)
deb-vendored:
    #!/usr/bin/env bash
    set -e
    just package-staging-vendored
    export WMDE_VERSION="{{wmde-version}}"
    nfpm package --config packaging/nfpm.yaml --packager deb --target target/

# .rpm из вендора (офлайн-сборка)
rpm-vendored:
    #!/usr/bin/env bash
    set -e
    just package-staging-vendored
    export WMDE_VERSION="{{wmde-version}}"
    nfpm package --config packaging/nfpm.yaml --packager rpm --target target/
