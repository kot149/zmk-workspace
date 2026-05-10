#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
image="${ZMK_WORKSPACE_CONTAINER_IMAGE:-zmk-workspace-dev:latest}"
workspace="/zmk-workspace"
ccache_dir="$repo_dir/.cache/ccache"
dockerfile="$repo_dir/.devcontainer/Dockerfile"

_abspath() {
    (CDPATH= cd -- "$1" && pwd -P)
}

_sha256sum() {
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$@"
    else
        shasum -a 256 "$@"
    fi
}

firmware_dir() {
    local west_config path file west_yml_path config_root config_name

    if [[ -f "$repo_dir/.west/config" ]]; then
        west_config="$repo_dir/.west/config"
    else
        printf '%s\n' "$repo_dir/firmware"
        return
    fi

    path="$(awk -F ' *= *' '/^ *path/ {print $2}' "$west_config")"
    file="$(awk -F ' *= *' '/^ *file/ {print $2}' "$west_config")"
    west_yml_path="${path:-.}/${file}"
    config_root="$(dirname "$west_yml_path")/.."
    config_name="$(basename "$(_abspath "$repo_dir/$config_root")")"
    printf '%s\n' "$repo_dir/firmware/$config_name"
}

if [[ "${1:-}" == "flash" ]]; then
    shift
    expr="${1:-}"
    if [[ -z "$expr" ]]; then
        echo "Usage: ./just.sh flash <target> [-r] [west build args...]" >&2
        exit 2
    fi
    shift

    rebuild=false
    build_args=()
    for arg in "$@"; do
        if [[ "$arg" == "-r" ]]; then
            rebuild=true
        else
            build_args+=("$arg")
        fi
    done

    if [[ "$rebuild" == "true" ]]; then
        echo "Rebuilding before flashing..."
        "$repo_dir/just.sh" build "$expr" "${build_args[@]}"
    fi

    target="$("$repo_dir/just.sh" _parse_targets "$expr" | head -n 1)"
    if [[ -z "$target" ]]; then
        echo "No matching targets found for expression '$expr'. Aborting..." >&2
        exit 1
    fi

    IFS=, read -r board shield snippet artifact <<< "$target"
    artifact_name="${artifact:-${shield:+${shield// /+}-}${board}}"
    artifact_fs="${artifact_name//\//-}"
    uf2_path="$(firmware_dir)/$artifact_fs.uf2"

    if [[ ! -f "$uf2_path" ]]; then
        echo "Firmware file '$uf2_path' not found. Please build it first with './just.sh build \"$expr\"'." >&2
        exit 1
    fi

    if [[ "$OSTYPE" == "darwin"* ]]; then
        echo "Flashing '$uf2_path'..."
        exec "$repo_dir/flash.sh" "$uf2_path"
    elif grep -q -i "Microsoft" /proc/version; then
        echo "Flashing '$uf2_path'..."
        exec powershell.exe -ExecutionPolicy Bypass -File "$repo_dir/flash.ps1" -Uf2File "$(wslpath -w "$uf2_path")"
    else
        echo "Flashing '$uf2_path' is not supported on this platform." >&2
        exit 1
    fi
fi

dockerfile_hash="$(_sha256sum "$dockerfile" | awk '{print $1}')"
image_hash="$(docker image inspect -f '{{ index .Config.Labels "zmk-workspace.dockerfile-sha" }}' "$image" 2>/dev/null || true)"
if [[ "$image_hash" != "$dockerfile_hash" ]]; then
    docker build \
        --label "zmk-workspace.dockerfile-sha=$dockerfile_hash" \
        -t "$image" \
        -f "$dockerfile" \
        "$repo_dir"
fi

mkdir -p "$ccache_dir"

docker_tty_args=()
if [[ -t 0 && -t 1 ]]; then
    docker_tty_args=(-it)
fi

exec docker run --rm \
    "${docker_tty_args[@]}" \
    --user "$(id -u):$(id -g)" \
    --env HOME=/tmp \
    --env IN_ZMK_CONTAINER=1 \
    --env TERM="${TERM:-xterm-256color}" \
    --env CCACHE_DIR="$workspace/.cache/ccache" \
    --env CCACHE_MAXSIZE="${ZMK_WORKSPACE_CCACHE_MAXSIZE:-5G}" \
    --env CCACHE_COMPILERCHECK=content \
    --env CCACHE_IGNOREOPTIONS="${ZMK_WORKSPACE_CCACHE_IGNOREOPTIONS:---specs=picolibc.specs}" \
    --env WORKSPACE_DIR="$workspace" \
    --env ZMK_BUILD_DIR="$workspace/.build" \
    --env ZMK_SRC_DIR="$workspace/zmk/app" \
    --env ZEPHYR_BASE="$workspace/zephyr" \
    --volume "$repo_dir:$workspace" \
    --workdir "$workspace" \
    "$image" \
    bash -lc 'exec "$@"' _ just "$@"
