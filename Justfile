default:
    @just --list --unsorted

build := absolute_path('.build')
zmk_config_root := absolute_path(`
  if [ -f .west/config ]; then
    path=$(awk -F ' *= *' '/^ *path/ {print $2}' .west/config)
    file=$(awk -F ' *= *' '/^ *file/ {print $2}' .west/config)
    west_yml_path="${path:-.}/${file}"
    echo "$(dirname $west_yml_path)/.."
  else
    echo "."
  fi
`)
firmware := absolute_path('firmware')
out := firmware / file_name(zmk_config_root)

# parse build.yaml and filter targets by expression
_parse_targets $expr:
    #!/usr/bin/env bash
    attrs="[.board, .shield, .snippet, .\"artifact-name\"]"
    filter="(($attrs | map(. // [.]) | combinations), ((.include // {})[] | $attrs)) | join(\",\")"
    echo "$(yq -r "$filter" "{{ zmk_config_root }}/build.yaml" | grep -v "^," | grep -i "${expr/#all/.*}")"

# build firmware for single board & shield combination
_build_single $board $shield $snippet $artifact *west_args:
    #!/usr/bin/env bash
    set -euo pipefail
    artifact="${artifact:-${shield:+${shield// /+}-}${board}}"

    # Board ids may contain '/' (e.g. xiao_ble//zmk). Slashes break cp paths and mkdir.
    artifact_fs="${artifact//\//-}"
    build_dir="{{ build / '$artifact_fs' }}"

    echo "Building firmware for $artifact..."

    # Check if zephyr/module.yml exists to determine whether to include DZMK_EXTRA_MODULES
    if [[ -f "{{ zmk_config_root }}/zephyr/module.yml" ]]; then
        west build -s zmk/app -d "$build_dir" -b $board {{ west_args }} ${snippet:+-S "$snippet"} -- \
            -DZMK_CONFIG=""{{ zmk_config_root }}/config"" -DZMK_EXTRA_MODULES="{{ zmk_config_root }}" ${shield:+-DSHIELD="$shield"}
    else
        west build -s zmk/app -d "$build_dir" -b $board {{ west_args }} ${snippet:+-S "$snippet"} -- \
            -DZMK_CONFIG=""{{ zmk_config_root }}/config"" ${shield:+-DSHIELD="$shield"}
    fi

    if [[ -f "$build_dir/zephyr/zmk.uf2" ]]; then
        mkdir -p "{{ out }}" && cp "$build_dir/zephyr/zmk.uf2" "{{ out }}/$artifact_fs.uf2"
    else
        mkdir -p "{{ out }}" && cp "$build_dir/zephyr/zmk.bin" "{{ out }}/$artifact_fs.bin"
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

# initialize west
init *config_path:
    #!/usr/bin/env bash
    set -euo pipefail

    config_path="{{ config_path }}"

    # If config_path is provided as argument, use fzf to select it
    if [[ -z "$config_path" ]]; then
        # Use fzf to select config from config/ and its subdirectories
        subdirs=$(find config -mindepth 1 -maxdepth 1 -type d -exec basename {} \; | sort)
        candidates=$(printf "config\n"; printf "%s\n" "$subdirs" | sed 's#^#config/#')

        config_path=$(echo "$candidates" | fzf \
            --prompt="Select ZMK config: " \
            --header="Choose a configuration to initialize" \
            --preview="ls -1a config/{}")

        if [[ -z "$config_path" ]]; then
            echo "No config selected. Exiting..."
            exit 0
        fi
    fi

    # Determine west.yml path
    if [[ -f "$config_path/west.yml" ]]; then
        west_yml_abs="$config_path/west.yml"
    else
        west_yml_abs="$config_path/config/west.yml"
    fi

    # Convert to path relative to config
    west_yml_rel=$(realpath --relative-to=config "$west_yml_abs")

    rm -rf .west
    west init -l config --mf "$west_yml_rel"
    west update --fetch-opt=--filter=blob:none
    west zephyr-export

# list build targets
list:
    @just _parse_targets all | sed 's/,*$//' | sort | column

# update west
update:
    west update --fetch-opt=--filter=blob:none

# draw keymap SVGs with keymap-drawer
draw-keymap *names:
    #!/usr/bin/env bash
    set -euo pipefail

    config_root="{{ zmk_config_root }}"
    keymap_dir="$config_root/keymap-drawer"
    keymap_config="$keymap_dir/config.yaml"
    mkdir -p "$keymap_dir"

    keymap_config_args=()
    if [[ -f "$keymap_config" ]]; then
        keymap_config_args=(-c "$keymap_config")
    fi

    requested=({{ names }})
    if [[ ${#requested[@]} -eq 0 ]]; then
        mapfile -t requested < <(find "$config_root/config" -maxdepth 1 -type f -name "*.keymap" -printf "%f\n" | sed "s/\.keymap$//" | sort)
    fi

    if [[ ${#requested[@]} -eq 0 ]]; then
        echo "No keymap files found in $config_root/config" >&2
        exit 1
    fi

    for name in "${requested[@]}"; do
        keymap_file="$config_root/config/$name.keymap"
        yaml_file="$keymap_dir/$name.yaml"
        svg_file="$keymap_dir/$name.svg"

        if [[ ! -f "$keymap_file" ]]; then
            echo "Keymap file not found: $keymap_file" >&2
            exit 1
        fi

        json_file=""
        if [[ -f "$config_root/config/$name.json" ]]; then
            json_file="$config_root/config/$name.json"
        fi

        board_search_dirs=()
        [[ -d "$config_root/boards" ]] && board_search_dirs+=("$config_root/boards")
        [[ -d "$config_root/config/boards" ]] && board_search_dirs+=("$config_root/config/boards")

        dtsi_file=""
        if [[ ${#board_search_dirs[@]} -gt 0 ]]; then
            dtsi_file=$(find "${board_search_dirs[@]}" -type f \( -name "$name.dts" -o -name "$name.dtsi" -o -name "$name.overlay" \) 2>/dev/null | sort | head -n 1)
            if [[ -z "$dtsi_file" ]]; then
                base_name="$name"
                for suffix in _left _right _central _peripheral; do
                    if [[ "$name" == *"$suffix" ]]; then
                        base_name="${name%$suffix}"
                        break
                    fi
                done
                if [[ "$base_name" != "$name" ]]; then
                    dtsi_file=$(find "${board_search_dirs[@]}" -type f \( -name "$base_name.dts" -o -name "$base_name.dtsi" -o -name "$base_name.overlay" -o -name "${base_name}-layouts.dtsi" \) 2>/dev/null | sort | head -n 1)
                fi
            fi
            if [[ -z "$dtsi_file" ]]; then
                mapfile -t board_matches < <(find "${board_search_dirs[@]}" -type f \( -name "*.dtsi" -o -name "*.overlay" \) 2>/dev/null | sort)
                if [[ ${#board_matches[@]} -eq 1 ]]; then
                    dtsi_file="${board_matches[0]}"
                elif [[ ${#board_matches[@]} -gt 1 ]]; then
                    echo "Physical layout source for '$name' is ambiguous; multiple candidates found in boards/:" >&2
                    printf '  %s\n' "${board_matches[@]}" >&2
                    exit 1
                fi
            fi
        fi

        if [[ -z "$dtsi_file" ]] && [[ -d "{{ justfile_directory() }}/modules" ]]; then
            if [[ -f "$config_root/west.yml" ]]; then
                west_yml="$config_root/west.yml"
            else
                west_yml="$config_root/config/west.yml"
            fi
            module_search_dirs=()
            if [[ -f "$west_yml" ]]; then
                while IFS= read -r mp; do
                    [[ "$mp" == modules/* ]] || continue
                    full_mp="{{ justfile_directory() }}/$mp"
                    [[ -d "$full_mp" ]] && module_search_dirs+=("$full_mp")
                done < <(yq -r '.manifest.projects[] | (.path // .name)' "$west_yml" 2>/dev/null)
            fi
            [[ ${#module_search_dirs[@]} -eq 0 ]] && module_search_dirs=("{{ justfile_directory() }}/modules")
            mapfile -t module_matches < <(find "${module_search_dirs[@]}" -type f \( -name "$name.dts" -o -name "$name.dtsi" -o -name "$name.overlay" \) 2>/dev/null | sort)
            if [[ ${#module_matches[@]} -gt 1 ]]; then
                echo "Multiple physical layout sources found for '$name' in modules; place the correct file in $config_root/boards/ or $config_root/config/boards/ to resolve ambiguity:" >&2
                printf '  %s\n' "${module_matches[@]}" >&2
                exit 1
            fi
            dtsi_file="${module_matches[0]:-}"
        fi

        if [[ -z "$dtsi_file" ]] && [[ -d "{{ justfile_directory() }}/zmk/app/boards" ]]; then
            mapfile -t zmk_matches < <(find "{{ justfile_directory() }}/zmk/app/boards" -type f \( -name "$name.dts" -o -name "$name.dtsi" -o -name "$name.overlay" \) 2>/dev/null | sort)
            if [[ ${#zmk_matches[@]} -gt 1 ]]; then
                echo "Multiple physical layout sources found for '$name' in zmk/app/boards; place the correct file in $config_root/boards/ to resolve ambiguity:" >&2
                printf '  %s\n' "${zmk_matches[@]}" >&2
                exit 1
            fi
            dtsi_file="${zmk_matches[0]:-}"
        fi

        if [[ -z "$json_file" && -z "$dtsi_file" ]]; then
            echo "Physical layout source not found for '$name'" >&2
            exit 1
        fi

        echo "Drawing keymap for $name..."
        keymap "${keymap_config_args[@]}" parse -z "$keymap_file" -o "$yaml_file"
        if [[ -n "$json_file" ]]; then
            keymap "${keymap_config_args[@]}" draw "$yaml_file" -j "$json_file" -o "$svg_file"
        else
            keymap "${keymap_config_args[@]}" draw "$yaml_file" -d "$dtsi_file" -o "$svg_file"
        fi
        echo "Wrote $svg_file"
    done

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
    artifact_fs="${artifact_name//\//-}"
    uf2_file="$artifact_fs.uf2"
    uf2_path="{{ out }}/$uf2_file"

    if [[ ! -f "$uf2_path" ]]; then
        echo "Firmware file '$uf2_path' not found. Please build it first with 'just build \"{{ expr }}\"'." >&2
        exit 1
    fi

    # macOS
    if [[ "$OSTYPE" == "darwin"* ]]; then
        echo "Flashing '$uf2_path'..."
        ./flash.sh "$uf2_path"
    # WSL
    elif grep -q -i "Microsoft" /proc/version; then
        echo "Flashing '$uf2_path'..."
        powershell.exe -ExecutionPolicy Bypass -File flash.ps1 -Uf2File "$(wslpath -w $uf2_path)"
    # Other: Not supported
    else
        echo "Flashing '$uf2_path' is not supported on this platform." >&2
        exit 1
    fi

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
