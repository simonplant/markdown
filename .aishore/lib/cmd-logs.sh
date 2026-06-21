#!/usr/bin/env bash
# Module: cmd-logs — show recent agent run history
# Lazy-loaded by _load_module; all globals (LOGS_DIR, log_header, log_warning,
# CYAN, NC) come from the main script.

cmd_logs() {
    local last=20

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --last)
                if [[ -z "${2:-}" || ! "$2" =~ ^[0-9]+$ ]]; then
                    log_error "--last requires a numeric argument"
                    return 1
                fi
                last="$2"
                shift 2
                ;;
            *)
                log_error "Unknown option: $1"
                return 1
                ;;
        esac
    done

    local log_file="$LOGS_DIR/agent-runs.log"

    if [[ ! -f "$log_file" ]] || [[ ! -s "$log_file" ]]; then
        echo "No agent runs recorded yet."
        echo "Run a sprint with 'aishore run' to generate log entries."
        return 0
    fi

    log_header "Recent Agent Runs (last $last)"
    echo ""

    # Header
    printf "%-25s  %-12s  %-10s  %-10s  %s\n" "TIMESTAMP" "AGENT" "COMMAND" "DURATION" "MODEL"
    printf "%-25s  %-12s  %-10s  %-10s  %s\n" "─────────────────────────" "────────────" "──────────" "──────────" "─────────────────"

    # Read last N lines and format
    tail -n "$last" "$log_file" | while IFS='|' read -r timestamp agent command duration model; do
        printf "%-25s  %-12s  %-10s  %-10s  %s\n" \
            "$timestamp" "$agent" "$command" "$duration" "$model"
    done
}
