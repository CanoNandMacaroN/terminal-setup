terminal_setup_pixi_entries_for_platform() {
    local manifest=$1 platform=$2
    awk -v wanted_platform="$platform" '
        function emit() {
            if (!in_tool) return
            if (environment == "" || package == "" || expose == "") exit 2
            if (platforms == "") platforms="linux,windows"
            if (index("," platforms ",", "," wanted_platform ",") > 0) {
                print environment "\t" package "\t" expose "\t" platforms
            }
        }
        $0 == "[[tool]]" {
            emit()
            in_tool=1
            environment=package=expose=platforms=""
            next
        }
        in_tool && /^environment = "/ {
            value=$0; sub(/^environment = "/, "", value); sub(/"$/, "", value); environment=value; next
        }
        in_tool && /^package = "/ {
            value=$0; sub(/^package = "/, "", value); sub(/"$/, "", value); package=value; next
        }
        in_tool && /^expose = "/ {
            value=$0; sub(/^expose = "/, "", value); sub(/"$/, "", value); expose=value; next
        }
        in_tool && /^platforms = "/ {
            value=$0; sub(/^platforms = "/, "", value); sub(/"$/, "", value); platforms=value; next
        }
        END { emit() }
    ' "$manifest"
}

terminal_setup_apt_command_available() {
    local command_name=$1 pixi_bin=$2 path_entry system_path="" command_path resolved_path
    command -v dpkg-query >/dev/null 2>&1 || return 1

    while IFS= read -r path_entry; do
        [[ -n "$path_entry" && "${path_entry%/}" != "${pixi_bin%/}" ]] || continue
        system_path="${system_path:+$system_path:}$path_entry"
    done < <(printf '%s' "$PATH" | tr ':' '\n')
    command_path="$(PATH="$system_path" command -v "$command_name" 2>/dev/null || true)"
    [[ -n "$command_path" && -x "$command_path" ]] || return 1
    dpkg-query -S "$command_path" >/dev/null 2>&1 && return 0

    resolved_path="$(readlink -f "$command_path" 2>/dev/null || true)"
    [[ -n "$resolved_path" && "$resolved_path" != "$command_path" ]] || return 1
    dpkg-query -S "$resolved_path" >/dev/null 2>&1
}
