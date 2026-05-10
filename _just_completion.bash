#!/bin/bash

_just_completion() {
    local cur prev invoked
    local -a just_cmd
    COMPREPLY=()
    cur="${COMP_WORDS[COMP_CWORD]}"
    prev="${COMP_WORDS[COMP_CWORD-1]}"
    invoked="${COMP_WORDS[0]}"

    if [[ "$(basename "$invoked")" == "just.sh" ]]; then
        just_cmd=("$invoked")
    elif command -v just >/dev/null 2>&1; then
        just_cmd=("just")
    elif [[ -x "./just.sh" ]]; then
        just_cmd=("./just.sh")
    else
        return 0
    fi

    if [[ $COMP_CWORD -eq 1 ]]; then
        local recipes=""
        if [[ "$(basename "$invoked")" == "just.sh" ]]; then
            local justfile_dir justfile
            justfile_dir="$(dirname -- "$invoked")"
            justfile="${justfile_dir}/Justfile"
            if command -v just >/dev/null 2>&1 && [[ -f "$justfile" ]]; then
                recipes=$(just --summary --justfile "$justfile" 2>/dev/null)
            elif [[ -f "$justfile" ]]; then
                recipes=$(grep -E '^[a-zA-Z][a-zA-Z0-9_-]*([[:space:]]|:)' "$justfile" 2>/dev/null \
                    | grep -v '^_' | grep ':' | grep -v ':=' \
                    | sed 's/[[:space:]].*$//' | sort -u | tr '\n' ' ')
            fi
        else
            recipes=$("${just_cmd[@]}" --summary 2>/dev/null)
        fi
        COMPREPLY=($(compgen -W "$recipes" -- "$cur"))
        return 0
    fi

    if [[ $COMP_CWORD -eq 1 ]]; then
        local recipes
        recipes=$(just --summary 2>/dev/null)
        [[ -n "$recipes" ]] && COMPREPLY=($(compgen -W "$recipes" -- "$cur"))
        return
    fi

    if [[ "${COMP_WORDS[1]}" == "init" ]]; then
        # Handle init command completion with config directories
        if [[ -d "config" ]]; then
            local dirs
            subdirs=$(find config -mindepth 1 -maxdepth 1 -type d -exec basename {} \; | sort)
            candidates=$(printf "config\n"; printf "%s\n" "$subdirs" | sed 's#^#config/#')

            if [[ -n "$candidates" ]]; then
                if command -v fzf >/dev/null 2>&1; then
                    local selected
                    selected=$(echo "$candidates" | fzf \
                        --prompt="Select ZMK config: " \
                        --header="Choose a configuration to initialize" \
                        --preview="ls -1a {}" \
                        --query="$cur")
                    [[ -n "$selected" ]] && COMPREPLY=("$selected")
                else
                    COMPREPLY=($(compgen -W "$candidates" -- "$cur"))
                fi
                return
            fi
        fi
    elif [[ "${COMP_WORDS[1]}" == "draw" ]]; then
        if [[ -d "config" ]]; then
            local keymaps selected
            keymaps=$(find config -maxdepth 2 -type f -name "*.keymap" -printf "%f\n" | sed 's/\.keymap$//' | sort -u)

            if [[ -n "$keymaps" ]]; then
                selected=$(echo "$keymaps" | fzf \
                    --prompt="Select keymap: " \
                    --header="Choose keymap to draw" \
                    --query="$cur")
                [[ -n "$selected" ]] && COMPREPLY=("$selected")
                return
            fi
        fi
    elif [[ "${COMP_WORDS[1]}" == "build" || "${COMP_WORDS[1]}" == "flash" ]]; then
        # Handle -S option completion (only for flash command with -r option)
        if [[ "$prev" == "-S" && ("${COMP_WORDS[1]}" == "build" || ("${COMP_WORDS[1]}" == "flash" && " ${COMP_WORDS[*]} " =~ " -r ")) ]]; then
            if command -v fzf >/dev/null 2>&1; then
                local selected
                selected=$(printf '%s\n' "zmk-usb-logging" "studio-rpc-usb-uart" | fzf \
                    --prompt="Select snippet: " \
                    --header="Choose a snippet (Both = separate -S options)" \
                    --query="$cur")
                [[ -n "$selected" ]] && COMPREPLY=("$selected")
            else
                COMPREPLY=($(compgen -W "zmk-usb-logging studio-rpc-usb-uart" -- "$cur"))
            fi
            return
        fi

        # Check if target is already specified (excluding current position)
        local target_specified=false
        for ((i=2; i<${#COMP_WORDS[@]}; i++)); do
            if [[ $i -ne $COMP_CWORD && "${COMP_WORDS[i]}" != -* && "${COMP_WORDS[i-1]}" != "-S" ]]; then
                target_specified=true
                break
            fi
        done

        # Handle west build options
        if [[ "$cur" == -* || "$target_specified" == true ]]; then
            local options
            if [[ "${COMP_WORDS[1]}" == "build" ]]; then
                options="-p
-S zmk-usb-logging
-S studio-rpc-usb-uart"
            elif [[ "${COMP_WORDS[1]}" == "flash" ]]; then
                if [[ " ${COMP_WORDS[*]} " =~ " -r " ]]; then
                    options="-p
-S zmk-usb-logging
-S studio-rpc-usb-uart"
                else
                    options="-r"
                fi
            fi

            if [[ -n "$options" ]]; then
                if command -v fzf >/dev/null 2>&1; then
                    local selected
                    selected=$(echo "$options" | fzf \
                        --prompt="Select option: " \
                        --header="Choose a west build option" \
                        --query="$cur")
                    [[ -n "$selected" ]] && COMPREPLY=("$selected")
                else
                    COMPREPLY=($(compgen -W "$options" -- "$cur"))
                fi
                return
            fi
        fi

        # Target completion for non-options (only if target not already specified)
        if [[ "$cur" != -* && "$prev" != "-S" && "$target_specified" == false ]]; then
            local targets
            targets=$("${just_cmd[@]}" _parse_targets all 2>/dev/null | sed 's/,*$//')

            if [[ -n "$targets" ]]; then
                local selected board shield search_expr target_candidates
                if command -v fzf >/dev/null 2>&1; then
                    selected=$(echo "$targets" | fzf \
                        --prompt="Select build target: " \
                        --header="Choose target to build (ESC to cancel)" \
                        --query="$cur" \
                        --preview="echo {} | awk -F',' '{print \"Board: \" \$1 \"\\nShield: \" \$2 \"\\nSnippet: \" \$3}'")

                    if [[ -n "$selected" ]]; then
                        IFS=',' read -r board shield _ <<< "$selected"

                        if [[ -n "$shield" && "$shield" != "null" ]]; then
                            if [[ "$shield" =~ [[:space:]] ]]; then
                                search_expr="${shield%% *}"
                            else
                                search_expr="$shield"
                            fi
                        else
                            search_expr="$board"
                        fi

                        COMPREPLY=("$search_expr")
                    fi
                else
                    target_candidates=$(echo "$targets" | while IFS=',' read -r board shield _; do
                        if [[ -n "$shield" && "$shield" != "null" ]]; then
                            printf '%s\n' "${shield%% *}"
                        else
                            printf '%s\n' "$board"
                        fi
                    done | sort -u)
                    COMPREPLY=($(compgen -W "$target_candidates" -- "$cur"))
                fi
            fi
        fi
    fi
}

complete -o bashdefault -o default -F _just_completion just
complete -o bashdefault -o default -F _just_completion just.sh
complete -o bashdefault -o default -F _just_completion ./just.sh
