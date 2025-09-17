default:
    @just --list --unsorted

build := absolute_path('.build')
out := absolute_path('firmware')
zmk_config_root := `
if [ -f .west/config ]; then
  root=$(awk -F= '
    BEGIN { p=""; f="" }
    /^[[:space:]]*path[[:space:]]*=/ {
      p=$2; gsub(/^[[:space:]]+|[[:space:]]+$/, "", p)
    }
    /^[[:space:]]*file[[:space:]]*=/ {
      f=$2; gsub(/^[[:space:]]+|[[:space:]]+$/, "", f)
    }
    END {
      if (p != "" && f != "") {
        pf = p "/" f
        if (f == "west.yml") {
          print "."
        } else {
          sub(/\/config\/west\.yml$/, "", pf)
          print pf
        }
      }
    }
  ' .west/config)
else
  root="."
fi

if [ "$root" = "." ]; then
  realpath .
else
  realpath "$root"
fi`

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
    build_dir="{{ build / '$artifact' }}"

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
