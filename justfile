[private]
default:
    @just --list

[doc("Build prismacat for the current host")]
[group("build")]
build:
    zig build

[doc("Build an optimized prismacat binary for the current host")]
[group("build")]
release-build:
    zig build -Doptimize=ReleaseFast -Dcpu=baseline

[doc("Run the Zig test suite")]
[group("test")]
test:
    zig build test --summary all

[doc("Run the local CI checks")]
[group("test")]
ci: test

[doc("Render the README demo image")]
[group("assets")]
demo-image:
    mkdir -p assets
    zig build
    freeze --execute 'bash -lc '\''printf "prismacat\n" | zig-out/bin/prismacat --theme "Catppuccin Mocha"; echo; fortune | cowsay -f dragon | zig-out/bin/prismacat --theme "TokyoNight Night"'\''' \
        --output assets/prismacat-demo.png \
        --window \
        --background '#11111b' \
        --border.radius 12 \
        --padding 24 \
        --margin 24 \
        --font.size 16
    oxipng -o max --strip safe assets/prismacat-demo.png

[doc("Check the GoReleaser config without publishing")]
[group("release")]
release-check:
    goreleaser check

[doc("Build release artifacts locally without publishing")]
[group("release")]
release-snapshot:
    goreleaser release --snapshot --clean --skip=publish
