default:
    @just --list --unsorted

config := absolute_path('config')
build := absolute_path('.build')
out := absolute_path('firmware')
draw := absolute_path('draw')
zmk_config := env_var_or_default('ZMK_CONFIG', 'zmk-config-roBa')

# parse combos.dtsi and adjust settings to not run out of slots
_parse_combos:
    #!/usr/bin/env bash
    set -euo pipefail
    cconf="{{ config / 'combos.dtsi' }}"
    if [[ -f $cconf ]]; then
        # set MAX_COMBOS_PER_KEY to the most frequent combos count
        count=$(
            tail -n +10 $cconf |
                grep -Eo '[LR][TMBH][0-9]' |
                sort | uniq -c | sort -nr |
                awk 'NR==1{print $1}'
        )
        sed -Ei "/CONFIG_ZMK_COMBO_MAX_COMBOS_PER_KEY/s/=.+/=$count/" "{{ config }}"/*.conf
        echo "Setting MAX_COMBOS_PER_KEY to $count"

        # set MAX_KEYS_PER_COMBO to the most frequent key count
        count=$(
            tail -n +10 $cconf |
                grep -o -n '[LR][TMBH][0-9]' |
                cut -d : -f 1 | uniq -c | sort -nr |
                awk 'NR==1{print $1}'
        )
        sed -Ei "/CONFIG_ZMK_COMBO_MAX_KEYS_PER_COMBO/s/=.+/=$count/" "{{ config }}"/*.conf
        echo "Setting MAX_KEYS_PER_COMBO to $count"
    fi

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
build *args: _parse_combos
    #!/usr/bin/env bash
    set -euo pipefail

    # Convert just args to bash array
    args_array=({{ args }})

    # Parse arguments to separate expression from west args
    expr=""
    west_args=()

    # Check if first argument doesn't start with '-' (is an expression)
    if [[ ${#args_array[@]} -gt 0 && "${args_array[0]:0:1}" != "-" ]]; then
        expr="${args_array[0]}"
        west_args=("${args_array[@]:1}")
    else
        west_args=("${args_array[@]}")
    fi

    # If no expression provided, use fzf to select targets
    if [[ -z "$expr" ]]; then
        targets=$(just _parse_targets all)

        if [[ -z "$targets" ]]; then
            echo "No targets found. Aborting..." >&2
            exit 1
        fi

        # Use fzf to select target(s)
        selected=$(echo "$targets" | sed 's/,*$//' | fzf \
            --multi \
            --prompt="Select build target(s): " \
            --header="Choose target(s) to build (use Tab for multi-select)" \
            --preview="echo {} | awk -F',' '{print \"Board: \" \$1 \"\\nShield: \" \$2 \"\\nSnippet: \" \$3}'")

        if [[ -z "$selected" ]]; then
            echo "No targets selected. Exiting..."
            exit 0
        fi

        targets="$selected"
    else
        targets=$(just _parse_targets "$expr")
        [[ -z $targets ]] && echo "No matching targets found. Aborting..." >&2 && exit 1
    fi

    echo "$targets" | while IFS=, read -r board shield snippet artifact; do
        just _build_single "$board" "$shield" "$snippet" "$artifact" "${west_args[@]}"
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
init:
    rm -rf .west
    west init -l config --mf {{ zmk_config }}/config/west.yml
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
flash *args:
    #!/usr/bin/env bash
    set -euo pipefail

    # Convert just args to bash array
    args_array=({{ args }})

    # Parse arguments to separate expression from options
    expr=""
    rebuild=false
    build_args=()

    # Check if first argument doesn't start with '-' (is an expression)
    if [[ ${#args_array[@]} -gt 0 && "${args_array[0]:0:1}" != "-" ]]; then
        expr="${args_array[0]}"
        remaining_args=("${args_array[@]:1}")
    else
        remaining_args=("${args_array[@]}")
    fi

    # Parse remaining arguments for options
    for arg in "${remaining_args[@]}"; do
        if [[ "$arg" == "-r" ]]; then
            rebuild=true
        else
            build_args+=("$arg")
        fi
    done

    # If no expression provided, use fzf to select target
    if [[ -z "$expr" ]]; then
        targets=$(just _parse_targets all)

        if [[ -z "$targets" ]]; then
            echo "No targets found. Aborting..." >&2
            exit 1
        fi

        # Use fzf to select target (single selection for flash)
        selected=$(echo "$targets" | sed 's/,*$//' | fzf \
            --prompt="Select target to flash: " \
            --header="Choose a target to flash" \
            --preview="echo {} | awk -F',' '{print \"Board: \" \$1 \"\\nShield: \" \$2 \"\\nSnippet: \" \$3}'")

        if [[ -z "$selected" ]]; then
            echo "No target selected. Exiting..."
            exit 0
        fi

        target="$selected"
    else
        target=$(just _parse_targets "$expr" | head -n 1)

        if [[ -z "$target" ]]; then
            echo "No matching targets found for expression '$expr'. Aborting..." >&2
            exit 1
        fi
    fi

    IFS=, read -r board shield snippet artifact <<< "$target"

    # Use provided artifact name or generate default
    if [[ -z "$artifact" ]]; then
        artifact="${shield:+${shield// /+}-}${board}"
    fi

    # Rebuild if -r option was provided
    if [[ "$rebuild" == "true" ]]; then
        echo "Rebuilding before flashing..."
        just _build_single "$board" "$shield" "$snippet" "$artifact" "${build_args[@]}"
    fi

    uf2_file="$artifact.uf2"
    uf2_path="{{ out }}/$uf2_file"

    if [[ ! -f "$uf2_path" ]]; then
        echo "Firmware file '$uf2_path' not found. Please build it first." >&2
        exit 1
    fi

    echo "Flashing '$uf2_path'..."
    win_build_dir=$(wslpath -w "{{ out }}")
    pwsh.exe -ExecutionPolicy Bypass -File flash.ps1 -BuildDir "$win_build_dir" -Uf2File "$uf2_file"

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

# export ZMK_CONFIG environment variable using fzf for config selection. Use with eval $(just config-export)
config-export:
    #!/usr/bin/env bash
    set -euo pipefail

    # Get all zmk-config directories
    config_dirs=$(find "{{ config }}" -maxdepth 1 -type d -name "zmk-config-*" -exec basename {} \; | sort)

    if [[ -z "$config_dirs" ]]; then
        echo "No zmk-config directories found in config/." >&2
        exit 1
    fi

    # Use fzf to select config
    selected=$(echo "$config_dirs" | fzf \
        --prompt="Select ZMK config: " \
        --header="Choose a configuration to export" \
        --preview="ls -1a {{ config }}/{}")

    if [[ -z "$selected" ]]; then
        echo "No config selected. Exiting..."
        exit 0
    fi

    echo "export ZMK_CONFIG=$selected"
