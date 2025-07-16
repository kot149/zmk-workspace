#!/bin/bash

_just_build_completion() {
    local cur prev
    COMPREPLY=()
    cur="${COMP_WORDS[COMP_CWORD]}"
    prev="${COMP_WORDS[COMP_CWORD-1]}"

    if [[ "${COMP_WORDS[1]}" == "build" || "${COMP_WORDS[1]}" == "flash" ]]; then
        # Handle -S option completion (only for flash command with -r option)
        if [[ "$prev" == "-S" && ("${COMP_WORDS[1]}" == "build" || ("${COMP_WORDS[1]}" == "flash" && " ${COMP_WORDS[*]} " =~ " -r ")) ]]; then
            local selected
            selected=$(printf '%s\n' "zmk-usb-logging" "studio-rpc-usb-uart" | fzf \
                --prompt="Select snippet: " \
                --header="Choose a snippet (Both = separate -S options)" \
                --query="$cur")
            [[ -n "$selected" ]] && COMPREPLY=("$selected")
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
                local selected
                selected=$(echo "$options" | fzf \
                    --prompt="Select option: " \
                    --header="Choose a west build option" \
                    --query="$cur")
                [[ -n "$selected" ]] && COMPREPLY=("$selected")
                return
            fi
        fi

        # Target completion for non-options (only if target not already specified)
        if [[ "$cur" != -* && "$prev" != "-S" && "$target_specified" == false ]]; then
            local targets
            targets=$(just _parse_targets all 2>/dev/null | sed 's/,*$//')

            if [[ -n "$targets" ]]; then
                local selected
                selected=$(echo "$targets" | fzf \
                    --prompt="Select build target: " \
                    --header="Choose target to build (ESC to cancel)" \
                    --query="$cur" \
                    --preview="echo {} | awk -F',' '{print \"Board: \" \$1 \"\\nShield: \" \$2 \"\\nSnippet: \" \$3}'")

                if [[ -n "$selected" ]]; then
                    local board shield search_expr
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
            fi
        fi
    fi
}

complete -F _just_build_completion just
