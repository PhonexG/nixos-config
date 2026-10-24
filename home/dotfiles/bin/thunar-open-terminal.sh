#!/usr/bin/env bash
set -e

target="${1:-}"

if [[ -z "$target" ]]; then
    target="$PWD"
elif [[ -f "$target" ]]; then
    target="$(dirname "$target")"
fi

if [[ ! -d "$target" ]]; then
    target="$HOME"
fi

exec kitty --directory "$target"
