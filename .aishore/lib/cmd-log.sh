#!/usr/bin/env bash
# Module: cmd-log — show recent sprint history from archive
# Lazy-loaded by _load_module; globals (ARCHIVE_DIR, GREEN, RED, NC,
# log_header, log_error) come from the main script.

cmd_log() {
    local limit=20
    local json_output=false

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --json)
                json_output=true
                shift
                ;;
            --limit)
                if [[ -z "${2:-}" || ! "$2" =~ ^[0-9]+$ ]]; then
                    log_error "--limit requires a numeric argument"
                    return 1
                fi
                limit="$2"
                shift 2
                ;;
            *)
                log_error "Unknown option: $1"
                return 1
                ;;
        esac
    done

    local archive="$ARCHIVE_DIR/sprints.jsonl"

    if [[ ! -f "$archive" ]] || [[ ! -s "$archive" ]]; then
        if [[ "$json_output" == "true" ]]; then
            echo "[]"
            return 0
        fi
        echo "No sprint history yet."
        echo "Run a sprint with 'aishore run' to generate history."
        return 0
    fi

    if [[ "$json_output" == "true" ]]; then
        tail -n "$limit" "$archive" | jq -s '.'
        return 0
    fi

    log_header "Sprint History (last $limit)"
    echo ""

    printf "%-12s  %-10s  %-42s  %-10s  %-10s  %s\n" \
        "DATE" "ID" "TITLE" "STATUS" "DURATION" "ATTEMPTS"
    printf "%-12s  %-10s  %-42s  %-10s  %-10s  %s\n" \
        "────────────" "──────────" "──────────────────────────────────────────" "──────────" "──────────" "────────"

    tail -n "$limit" "$archive" | while IFS= read -r line; do
        local date item_id title status duration attempts
        date=$(echo "$line" | jq -r '.date // "—"')
        item_id=$(echo "$line" | jq -r '.itemId // "—"')
        title=$(echo "$line" | jq -r '.title // "—"')
        status=$(echo "$line" | jq -r '.status // "—"')
        duration=$(echo "$line" | jq -r '.duration // "—"')
        attempts=$(echo "$line" | jq -r '.attempts // "—"')

        if [[ ${#title} -gt 40 ]]; then
            title="${title:0:39}…"
        fi

        if [[ "$duration" != "—" ]]; then
            duration="${duration}s"
        fi

        local color="$NC"
        if [[ "$status" == "complete" ]]; then
            color="$GREEN"
        elif [[ "$status" == "failed" ]]; then
            color="$RED"
        fi

        printf "%-12s  %-10s  %-42s  ${color}%-10s${NC}  %-10s  %s\n" \
            "$date" "$item_id" "$title" "$status" "$duration" "$attempts"
    done
}
