default:
    @just --list --unsorted

config := absolute_path('config')
build := absolute_path('.build')
out := absolute_path('firmware')
draw := absolute_path('draw')
zmk_config := `if [ -f .west/config ]; then sed -n 's|^file[[:space:]]*=[[:space:]]*\([^/]*\)/.*|\1|p' .west/config; else echo zmk-config-roBa; fi`

# parse build.yaml and filter targets by expression
_parse_targets $expr:
    #!/usr/bin/env bash
    attrs="[.board, .shield, .snippet, .\"artifact-name\"]"
    filter="(($attrs | map(. // [.]) | combinations), ((.include // {})[] | $attrs)) | join(\",\")"
    echo "$(yq -r "$filter" "{{ config }}/{{ zmk_config }}/build.yaml" | grep -v "^," | grep -i "${expr/#all/.*}")"

# build firmware for single board & shield combination
_build_single $board $shield $snippet $artifact *west_args:
    #!/usr/bin/env bash
    set -euo pipefail
    artifact="${artifact:-${shield:+${shield// /+}-}${board}}"
    build_dir="{{ build / '$artifact' }}"
    zmk_config_path="{{ config }}/{{ zmk_config }}"

    echo "Building firmware for $artifact..."

    # Check if zephyr/module.yml exists to determine whether to include DZMK_EXTRA_MODULES
    if [[ -f "$zmk_config_path/zephyr/module.yml" ]]; then
        west build -s zmk/app -d "$build_dir" -b $board {{ west_args }} ${snippet:+-S "$snippet"} -- \
            -DZMK_CONFIG="$zmk_config_path/config" -DZMK_EXTRA_MODULES="$zmk_config_path" ${shield:+-DSHIELD="$shield"}
    else
        west build -s zmk/app -d "$build_dir" -b $board {{ west_args }} ${snippet:+-S "$snippet"} -- \
            -DZMK_CONFIG="$zmk_config_path/config" ${shield:+-DSHIELD="$shield"}
    fi

    if [[ -f "$build_dir/zephyr/zmk.uf2" ]]; then
        mkdir -p "{{ out }}" && cp "$build_dir/zephyr/zmk.uf2" "{{ out }}/$artifact.uf2"
    else
        mkdir -p "{{ out }}" && cp "$build_dir/zephyr/zmk.bin" "{{ out }}/$artifact.bin"
    fi

# build firmware for matching targets
build expr *west_args:
    #!/usr/bin/env bash
    set -euo pipefail
    targets=$(just _parse_targets {{ expr }})

    [[ -z $targets ]] && echo "No matching targets found. Aborting..." >&2 && exit 1
    echo "$targets" | while IFS=, read -r board shield snippet artifact; do
        just _build_single "$board" "$shield" "$snippet" "$artifact" {{ west_args }}
    done

# clear build cache and artifacts
clean:
    rm -rf {{ build }} {{ out }}

# clear all automatically generated files
clean-all: clean
    rm -rf .west zmk

# clear nix cache
clean-nix:
    nix-collect-garbage --delete-old

# parse & plot keymap
draw:
    #!/usr/bin/env bash
    set -euo pipefail
    keymap -c "{{ draw }}/config.yaml" parse -z "{{ config }}/base.keymap" --virtual-layers Combos >"{{ draw }}/base.yaml"
    yq -Yi '.combos.[].l = ["Combos"]' "{{ draw }}/base.yaml"
    keymap -c "{{ draw }}/config.yaml" draw "{{ draw }}/base.yaml" -k "ferris/sweep" >"{{ draw }}/base.svg"

# initialize west
init *config_name:
    #!/usr/bin/env bash
    set -euo pipefail

    # Get all zmk-config directories
    config_dirs=$(find "{{ config }}" -mindepth 1 -maxdepth 1 -type d -exec basename {} \; | sort)

    if [[ -z "$config_dirs" ]]; then
        echo "No zmk-config directories found in config/." >&2
        exit 1
    fi

    # If config name is provided as argument, use it; otherwise use fzf
    if [[ -n "{{ config_name }}" ]]; then
        selected="{{ config_name }}"
        # Validate that the provided config exists
        if [[ ! -d "{{ config }}/$selected" ]]; then
            echo "Config directory '{{ config }}/$selected' not found." >&2
            echo "Available configs:" >&2
            echo "$config_dirs" >&2
            exit 1
        fi
    else
        # Use fzf to select config
        selected=$(echo "$config_dirs" | fzf \
            --prompt="Select ZMK config: " \
            --header="Choose a configuration to initialize" \
            --preview="ls -1a {{ config }}/{}")

        if [[ -z "$selected" ]]; then
            echo "No config selected. Exiting..."
            exit 0
        fi
    fi

    echo "Initializing with config: $selected"
    rm -rf .west
    west init -l config --mf "$selected/config/west.yml"
    west update --fetch-opt=--filter=blob:none
    west zephyr-export

# list build targets
list:
    @just _parse_targets all | sed 's/,*$//' | sort | column

# update west
update:
    west update --fetch-opt=--filter=blob:none

# upgrade zephyr-sdk and python dependencies
upgrade-sdk:
    nix flake update --flake .

# flash firmware for matching targets
flash expr *args:
    #!/usr/bin/env bash
    set -euo pipefail

    # Check if -r option is provided
    rebuild=false
    build_args=()
    for arg in {{ args }}; do
        if [[ "$arg" == "-r" ]]; then
            rebuild=true
        else
            build_args+=("$arg")
        fi
    done

    # Rebuild if -r option was provided
    if [[ "$rebuild" == "true" ]]; then
        echo "Rebuilding before flashing..."
        just build "{{ expr }}" "${build_args[@]}"
    fi

    target=$(just _parse_targets {{ expr }} | head -n 1)

    if [[ -z "$target" ]]; then
        echo "No matching targets found for expression '{{ expr }}'. Aborting..." >&2
        exit 1
    fi

    IFS=, read -r board shield snippet artifact <<< "$target"
    # Use artifact-name if specified, otherwise construct from shield and board
    if [[ -n "$artifact" ]]; then
        artifact_name="$artifact"
    else
        artifact_name="${shield:+${shield// /+}-}${board}"
    fi
    uf2_file="$artifact_name.uf2"
    uf2_path="{{ out }}/$uf2_file"

    if [[ ! -f "$uf2_path" ]]; then
        echo "Firmware file '$uf2_path' not found. Please build it first with 'just build \"{{ expr }}\"'." >&2
        exit 1
    fi

    echo "Flashing '$uf2_path'..."
    win_build_dir=$(wslpath -w "{{ out }}")
    powershell.exe -ExecutionPolicy Bypass -File flash.ps1 -BuildDir "$win_build_dir" -Uf2File "$uf2_file"

[no-cd]
test $testpath *FLAGS:
    #!/usr/bin/env bash
    set -euo pipefail
    testcase=$(basename "$testpath")
    build_dir="{{ build / "tests" / '$testcase' }}"
    config_dir="{{ '$(pwd)' / '$testpath' }}"
    cd {{ justfile_directory() }}

    if [[ "{{ FLAGS }}" != *"--no-build"* ]]; then
        echo "Running $testcase..."
        rm -rf "$build_dir"
        west build -s zmk/app -d "$build_dir" -b native_posix_64 -- \
            -DCONFIG_ASSERT=y -DZMK_CONFIG="$config_dir" \
            ${ZMK_EXTRA_MODULES:+-DZMK_EXTRA_MODULES="$(realpath ${ZMK_EXTRA_MODULES})"}
    fi

    ${build_dir}/zephyr/zmk.exe | sed -e "s/.*> //" |
        tee ${build_dir}/keycode_events.full.log |
        sed -n -f ${config_dir}/events.patterns > ${build_dir}/keycode_events.log
    if [[ "{{ FLAGS }}" == *"--verbose"* ]]; then
        cat ${build_dir}/keycode_events.log
    fi

    if [[ "{{ FLAGS }}" == *"--auto-accept"* ]]; then
        cp ${build_dir}/keycode_events.log ${config_dir}/keycode_events.snapshot
    fi
    diff -auZ ${config_dir}/keycode_events.snapshot ${build_dir}/keycode_events.log
