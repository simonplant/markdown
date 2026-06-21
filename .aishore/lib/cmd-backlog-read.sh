#!/usr/bin/env bash
# Module: cmd-backlog-read — backlog read/check commands (dispatcher, list, show, check, rm)
# Lazy-loaded by _load_module; all globals (BACKLOG_DIR, BACKLOG_FILES, ARCHIVE_DIR,
# PROJECT_ROOT, jq, log_*, parse_opts, validate_status, validate_priority,
# find_item, resolve_backlog_file, remove_item, check_readiness_gates,
# collect_done_ids, require_tool,
# JQ_PRIO_RANK, _load_module) come from the main script.
# Write commands (add, edit) in cmd-backlog-write.sh, populate in cmd-populate.sh.

cmd_backlog() {
    require_tool jq
    local subcmd="${1:-list}"
    shift || true
    case "$subcmd" in
        list|ls)    cmd_backlog_list "$@" ;;
        add|new)    _load_module cmd-backlog-write; cmd_backlog_add "$@" ;;
        show)       cmd_backlog_show "$@" ;;
        edit)       _load_module cmd-backlog-write; cmd_backlog_edit "$@" ;;
        rm|remove)  cmd_backlog_rm "$@" ;;
        check)      cmd_backlog_check "$@" ;;
        requeue)    cmd_backlog_requeue "$@" ;;
        move)       _load_module cmd-backlog-write; cmd_backlog_move "$@" ;;
        set-priority) _load_module cmd-backlog-write; cmd_backlog_set_priority "$@" ;;
        set-track)    _load_module cmd-backlog-write; cmd_backlog_set_track "$@" ;;
        populate)   _load_module cmd-populate; cmd_backlog_populate "$@" ;;
        stats)      cmd_backlog_stats "$@" ;;
        next)       cmd_backlog_next "$@" ;;
        *)
            log_error "Unknown backlog command: $subcmd"
            echo "Usage: backlog {list|add|show|edit|check|rm|move|set-priority|set-track|requeue|populate|stats|next}" >&2
            return 1
            ;;
    esac
}

cmd_backlog_check() {
    local quick=false
    local args=()
    for arg in "$@"; do
        case "$arg" in
            --quick) quick=true ;;
            *) args+=("$arg") ;;
        esac
    done
    set -- "${args[@]+"${args[@]}"}"

    # Handle --all flag
    if [[ "${1:-}" == "--all" ]]; then
        _backlog_check_all "$quick"
        return $?
    fi

    local id="${1:-}"
    [[ -z "$id" ]] && { log_error "Usage: backlog check <ID|--all> [--quick]"; return 1; }
    [[ $# -gt 1 ]] && { log_error "Unexpected argument: ${2}"; return 1; }

    # Verify item exists
    find_item "$id" >/dev/null || return 1

    local gates_warnings
    local exit_code=0
    if gates_warnings=$(check_readiness_gates "$id" "$quick"); then
        log_success "$id passes all readiness gates"
    else
        log_warning "$id has readiness warnings:"
        printf '%b\n' "$gates_warnings"
        exit_code=1
    fi

    return "$exit_code"
}

_backlog_check_all() {
    local quick="${1:-false}"
    local pass_count=0 fail_count=0 total=0
    local -a table_rows=()

    if [[ "$quick" == "true" ]]; then
        log_info "Quick mode: skipping verify command execution"
    fi

    for f in "${BACKLOG_FILES[@]}"; do
        [[ -f "$BACKLOG_DIR/$f" ]] || continue
        local ids
        ids=$(jq -r '.items[] | select((.status // "todo") != "done") | .id' "$BACKLOG_DIR/$f" 2>/dev/null) || continue
        [[ -z "$ids" ]] && continue

        while IFS= read -r item_id; do
            ((total++)) || true
            local gates_warnings result failures
            if gates_warnings=$(check_readiness_gates "$item_id" "$quick" 2>/dev/null); then
                result="PASS"
                failures="-"
                ((pass_count++)) || true
            else
                result="FAIL"
                # Extract failure reasons from warnings (strip leading "  - " prefix)
                failures=$(printf '%b' "$gates_warnings" | sed -n 's/^  - //p' | paste -sd ',' - )
                [[ -z "$failures" ]] && failures="unknown"
                ((fail_count++)) || true
            fi
            table_rows+=("$(printf '%s\t%s\t%s' "$item_id" "$result" "$failures")")
        done <<< "$ids"
    done

    if [[ "$total" -eq 0 ]]; then
        log_info "No non-done items found"
        return 0
    fi

    # Print table
    printf "%-10s %-6s %s\n" "ID" "GATE" "FAILURES"
    printf "%-10s %-6s %s\n" "──────────" "──────" "──────────────────────────────────────────"
    for row in "${table_rows[@]}"; do
        IFS=$'\t' read -r id result failures <<< "$row"
        printf "%-10s %-6s %s\n" "$id" "$result" "$failures"
    done
    echo ""
    printf '%s item(s): %s pass, %s fail\n' "$total" "$pass_count" "$fail_count"
    log_info "$pass_count/$total items ready for sprint"

    [[ "$fail_count" -gt 0 ]] && return 1
    return 0
}

cmd_backlog_list() {
    local filter_status="" filter_type="" filter_priority="" filter_track="" filter_ready=false filter_no_ready=false filter_failed=false filter_done=false filter_no_verify=false filter_json=false filter_by_priority=false filter_search=""
    parse_opts "val:filter_status:--status" "val:filter_type:--type" "val:filter_priority:--priority" "val:filter_track:--track" "bool:filter_ready:--ready" "bool:filter_no_ready:--no-ready" "bool:filter_failed:--failed" "bool:filter_done:--done" "bool:filter_no_verify:--no-verify" "bool:filter_json:--json" "bool:filter_by_priority:--by-priority" "val:filter_search:--search" -- "$@" || return 1

    if [[ "$filter_done" == "true" ]]; then
        _backlog_list_done
        return $?
    fi

    if [[ "$filter_by_priority" == "true" ]]; then
        _backlog_list_by_priority "$filter_status" "$filter_type" "$filter_track" "$filter_ready" "$filter_no_ready" "$filter_failed" "$filter_no_verify" "$filter_search"
        return $?
    fi

    # Validate --track value
    if [[ -n "$filter_track" ]]; then
        case "$filter_track" in
            core|feature) ;;
            *) log_error "Invalid track: $filter_track (must be: core, feature)"; return 1 ;;
        esac
    fi

    # Determine which files to scan
    local files=()
    case "$filter_type" in
        feat|feature) files=("backlog.json") ;;
        bug)          files=("bugs.json") ;;
        "")           files=("${BACKLOG_FILES[@]}") ;;
        *) log_error "Invalid type: $filter_type (must be: feat, bug)"; return 1 ;;
    esac

    # Build jq filter
    local jq_filter='.items[]'
    if [[ -n "$filter_status" ]]; then
        validate_status "$filter_status" || return 1
        jq_filter="$jq_filter | select((.status // \"todo\") == \"$filter_status\")"
    fi
    if [[ -n "$filter_priority" ]]; then
        validate_priority "$filter_priority" || return 1
        jq_filter="$jq_filter | select((.priority // \"should\") == \"$filter_priority\")"
    fi
    if [[ "$filter_ready" == "true" ]]; then
        jq_filter="$jq_filter | select(.readyForSprint == true)"
    elif [[ "$filter_no_ready" == "true" ]]; then
        jq_filter="$jq_filter | select(.readyForSprint != true)"
    fi
    if [[ -n "$filter_track" ]]; then
        jq_filter="$jq_filter | select((.track // \"feature\") == \"$filter_track\")"
    fi
    if [[ "$filter_failed" == "true" ]]; then
        jq_filter="$jq_filter | select((.failCount // 0) > 0)"
    fi
    if [[ "$filter_no_verify" == "true" ]]; then
        jq_filter="$jq_filter | select([.acceptanceCriteria // [] | .[] | select(type==\"object\" and .verify != null)] | length == 0)"
    fi
    if [[ -n "$filter_search" ]]; then
        jq_filter="$jq_filter | select((.title // \"\" | test(\$search; \"i\")) or (.intent // \"\" | test(\$search; \"i\")) or (.description // \"\" | test(\$search; \"i\")))"
    fi

    # JSON output mode: collect matching items and emit as JSON array
    if [[ "$filter_json" == "true" ]]; then
        local json_items="[]"
        for f in "${files[@]}"; do
            [[ -f "$BACKLOG_DIR/$f" ]] || continue
            local matched
            matched=$(jq -c --arg search "$filter_search" "[$jq_filter]" "$BACKLOG_DIR/$f" 2>/dev/null) || continue
            json_items=$(printf '%s\n%s\n' "$json_items" "$matched" | jq -s 'add // []')
        done
        printf '%s\n' "$json_items" | jq '.'
        return 0
    fi

    # Collect done IDs for dependency checking
    local done_ids
    done_ids=$(collect_done_ids)

    # Header
    printf "%-10s %-8s %-8s %-13s %-6s %-6s %-20s %s\n" "ID" "PRI" "TRACK" "STATUS" "READY" "FAILS" "BLOCKED" "TITLE"
    printf "%-10s %-8s %-8s %-13s %-6s %-6s %-20s %s\n" "──────────" "────────" "────────" "─────────────" "──────" "──────" "────────────────────" "─────────────────────────────"

    local count=0
    for f in "${files[@]}"; do
        [[ -f "$BACKLOG_DIR/$f" ]] || continue
        local items
        # shellcheck disable=SC1010
        items=$(jq -r --argjson done "$done_ids" --arg search "$filter_search" "${JQ_PRIO_RANK}[$jq_filter] | sort_by(.priority // \"should\" | prio_rank) | .[] | [.id, .priority // \"-\", .track // \"feature\", .status // \"todo\", (if .readyForSprint then \"yes\" else \"no\" end), ((.failCount // 0) | tostring), ((.dependsOn // []) | map(select(. as \$d | \$done | index(\$d) | not)) | if length == 0 then \"-\" else join(\",\") end), .title] | @tsv" "$BACKLOG_DIR/$f" 2>/dev/null) || continue
        if [[ -n "$items" ]]; then
            while IFS=$'\t' read -r id pri track status ready fails blocked title; do
                local blocked_display="" fails_display="-"
                if [[ "$blocked" != "-" ]]; then
                    blocked_display="[blocked: $blocked]"
                fi
                if [[ "$fails" -gt 0 ]] 2>/dev/null; then
                    fails_display="$fails"
                fi
                printf "%-10s %-8s %-8s %-13s %-6s %-6s %-20s %s\n" "$id" "$pri" "$track" "$status" "$ready" "$fails_display" "$blocked_display" "$title"
                ((count++)) || true
            done <<< "$items"
        fi
    done

    # Count ready items across listed files
    local ready_count=0
    for f in "${files[@]}"; do
        [[ -f "$BACKLOG_DIR/$f" ]] || continue
        ready_count=$((ready_count + $(count_ready_items "$BACKLOG_DIR/$f")))
    done

    echo ""
    printf '%s item(s), %s ready for sprint\n' "$count" "$ready_count"
}

_backlog_list_by_priority() {
    local filter_status="$1" filter_type="$2" filter_track="$3" filter_ready="$4" filter_no_ready="$5" filter_failed="$6" filter_no_verify="$7" filter_search="${8:-}"

    if [[ -n "$filter_track" ]]; then
        case "$filter_track" in
            core|feature) ;;
            *) log_error "Invalid track: $filter_track (must be: core, feature)"; return 1 ;;
        esac
    fi

    local files=()
    case "$filter_type" in
        feat|feature) files=("backlog.json") ;;
        bug)          files=("bugs.json") ;;
        "")           files=("${BACKLOG_FILES[@]}") ;;
        *) log_error "Invalid type: $filter_type (must be: feat, bug)"; return 1 ;;
    esac

    local jq_filter='.items[]'
    if [[ -n "$filter_status" ]]; then
        validate_status "$filter_status" || return 1
        jq_filter="$jq_filter | select((.status // \"todo\") == \"$filter_status\")"
    fi
    if [[ "$filter_ready" == "true" ]]; then
        jq_filter="$jq_filter | select(.readyForSprint == true)"
    elif [[ "$filter_no_ready" == "true" ]]; then
        jq_filter="$jq_filter | select(.readyForSprint != true)"
    fi
    if [[ -n "$filter_track" ]]; then
        jq_filter="$jq_filter | select((.track // \"feature\") == \"$filter_track\")"
    fi
    if [[ "$filter_failed" == "true" ]]; then
        jq_filter="$jq_filter | select((.failCount // 0) > 0)"
    fi
    if [[ "$filter_no_verify" == "true" ]]; then
        jq_filter="$jq_filter | select([.acceptanceCriteria // [] | .[] | select(type==\"object\" and .verify != null)] | length == 0)"
    fi
    if [[ -n "$filter_search" ]]; then
        jq_filter="$jq_filter | select((.title // \"\" | test(\$search; \"i\")) or (.intent // \"\" | test(\$search; \"i\")) or (.description // \"\" | test(\$search; \"i\")))"
    fi

    local done_ids
    done_ids=$(collect_done_ids)

    local count=0
    local priorities=("must" "should" "could" "future")
    for pri in "${priorities[@]}"; do
        local pri_filter="$jq_filter | select((.priority // \"should\") == \"$pri\")"
        local group_items=""

        for f in "${files[@]}"; do
            [[ -f "$BACKLOG_DIR/$f" ]] || continue
            local items
            # shellcheck disable=SC1010
            items=$(jq -r --argjson done "$done_ids" --arg search "$filter_search" "${JQ_PRIO_RANK}[$pri_filter] | sort_by(.priority // \"should\" | prio_rank) | .[] | [.id, .priority // \"-\", .track // \"feature\", .status // \"todo\", (if .readyForSprint then \"yes\" else \"no\" end), ((.failCount // 0) | tostring), ((.dependsOn // []) | map(select(. as \$d | \$done | index(\$d) | not)) | if length == 0 then \"-\" else join(\",\") end), .title] | @tsv" "$BACKLOG_DIR/$f" 2>/dev/null) || continue
            [[ -n "$items" ]] && group_items+="$items"$'\n'
        done

        [[ -z "${group_items%$'\n'}" ]] && continue

        printf '\n=== %s ===\n' "${pri^^}"
        printf "%-10s %-8s %-8s %-13s %-6s %-6s %-20s %s\n" "ID" "PRI" "TRACK" "STATUS" "READY" "FAILS" "BLOCKED" "TITLE"
        printf "%-10s %-8s %-8s %-13s %-6s %-6s %-20s %s\n" "──────────" "────────" "────────" "─────────────" "──────" "──────" "────────────────────" "─────────────────────────────"

        while IFS=$'\t' read -r id p track status ready fails blocked title; do
            [[ -z "$id" ]] && continue
            local blocked_display="" fails_display="-"
            if [[ "$blocked" != "-" ]]; then
                blocked_display="[blocked: $blocked]"
            fi
            if [[ "$fails" -gt 0 ]] 2>/dev/null; then
                fails_display="$fails"
            fi
            printf "%-10s %-8s %-8s %-13s %-6s %-6s %-20s %s\n" "$id" "$p" "$track" "$status" "$ready" "$fails_display" "$blocked_display" "$title"
            ((count++)) || true
        done <<< "$group_items"
    done

    local ready_count=0
    for f in "${files[@]}"; do
        [[ -f "$BACKLOG_DIR/$f" ]] || continue
        ready_count=$((ready_count + $(count_ready_items "$BACKLOG_DIR/$f")))
    done

    echo ""
    printf '%s item(s), %s ready for sprint\n' "$count" "$ready_count"
}

_backlog_list_done() {
    local sprints_file="$ARCHIVE_DIR/sprints.jsonl"

    if [[ ! -f "$sprints_file" ]] || [[ ! -s "$sprints_file" ]]; then
        log_info "No completed items in archive"
        return 0
    fi

    local rows
    rows=$(jq -rs '
        [.[] | select(.status == "complete")]
        | group_by(.itemId)
        | map(sort_by(.date) | last)
        | sort_by(.date)
        | reverse
        | .[] | [
            .itemId,
            .date,
            ((.attempts // 1) | tostring),
            ((.title // "-") | if length > 50 then .[:47] + "..." else . end)
        ] | @tsv
    ' "$sprints_file" 2>/dev/null)

    if [[ -z "$rows" ]]; then
        log_info "No completed items in archive"
        return 0
    fi

    printf "%-12s %-12s %-10s %s\n" "ID" "DATE" "ATTEMPTS" "TITLE"
    printf "%-12s %-12s %-10s %s\n" "────────────" "────────────" "──────────" "──────────────────────────────────────────────────"

    local count=0
    while IFS=$'\t' read -r id date attempts title; do
        printf "%-12s %-12s %-10s %s\n" "$id" "$date" "$attempts" "$title"
        ((count++)) || true
    done <<< "$rows"

    echo ""
    printf '%s completed item(s)\n' "$count"
}

cmd_backlog_show() {
    local id="${1:-}"
    [[ -z "$id" ]] && { log_error "Usage: backlog show <ID> [--json]"; return 1; }
    shift || true

    local json_mode=false
    parse_opts "bool:json_mode:--json" -- "$@" || return 1

    local item archived=false
    if ! item=$(find_item "$id" 2>/dev/null); then
        # Search archive files for done/cleaned items
        local archive_file
        for archive_file in "$ARCHIVE_DIR/backlog_done.json" "$ARCHIVE_DIR/bugs_done.json"; do
            [[ -f "$archive_file" ]] || continue
            if item=$(jq -e --arg id "$id" '.[] | select(.id == $id)' "$archive_file" 2>/dev/null); then
                archived=true
                break
            fi
        done
        if [[ "$archived" == "false" ]]; then
            log_error "Item not found: $id"
            return 1
        fi
    fi

    if [[ "$json_mode" == "true" ]]; then
        printf '%s\n' "$item" | jq '.'
        return 0
    fi

    # Collect done IDs for dependency status display
    local done_ids="[]"
    if printf '%s\n' "$item" | jq -e '.dependsOn // [] | length > 0' >/dev/null 2>&1; then
        done_ids=$(collect_done_ids)
    fi

    echo ""
    if [[ "$archived" == "true" ]]; then
        log_info "[archived]"
    fi
    printf '%s\n' "$item" | jq -r --argjson done_ids "$done_ids" '
        "ID:          \(.id)",
        "Title:       \(.title)",
        "Status:      \(.status // "todo")",
        "Priority:    \(.priority // "-")",
        "Track:       \(.track // "feature")",
        "Category:    \(.category // "-")",
        "Ready:       \(if .readyForSprint then "yes" else "no" end)",
        "Passes:      \(if .passes then "yes" else "no" end)",
        if (.failCount // 0) > 0 or .lastFailReason then
            "Fail count:   \(.failCount // 0)",
            if .lastFailReason then "Last failure: \(.lastFailReason)" else empty end,
            if .lastFailAt then "Last fail at: \(.lastFailAt)" else empty end
        else empty end,
        "",
        if .intent then "Intent:      \(.intent)\n" else empty end,
        "Description: \(.description // "-")",
        "",
        if (.steps // [] | length) > 0 then "Steps:" else empty end,
        (.steps // [] | to_entries[] | "  \(.key + 1). \(.value)"),
        if (.steps // [] | length) > 0 then "" else empty end,
        if (.acceptanceCriteria // [] | length) > 0 then "Acceptance Criteria:" else empty end,
        (.acceptanceCriteria // [] | .[] | if type == "object" then "  - \(.text)" + (if .verify then " (verify: \(.verify))" else "" end) else "  - \(.)" end),
        if (.scope // [] | length) > 0 then "\nScope:" else empty end,
        (.scope // [] | .[] | "  - \(.)"),
        if (.dependsOn // [] | length) > 0 then
            "\nDependencies:",
            (.dependsOn[] | . as $dep | if ($done_ids | index($dep) != null) then "  \($dep) [done]" else "  \($dep) [pending]" end)
        else empty end,
        if .groomedAt then "\nGroomed:      \(.groomedAt)" else empty end,
        if .groomingNotes then "Notes:        \(.groomingNotes)" else empty end,
        if .resolved_at then "Resolved:     \(.resolved_at)" else empty end,
        if .completedAt then "Completed:    \(.completedAt)" else empty end
    '

    # Sprint history from archive
    local sprints_file="$ARCHIVE_DIR/sprints.jsonl"
    if [[ -f "$sprints_file" ]]; then
        local history
        history=$(jq -s --arg id "$id" '
            [.[] | select(.itemId == $id)] | sort_by(.date) | .[-10:]
        ' "$sprints_file" 2>/dev/null) || history="[]"

        if [[ "$(printf '%s' "$history" | jq 'length')" -gt 0 ]]; then
            echo ""
            echo "Sprint history:"
            printf '%s' "$history" | jq -r '.[] |
                "  \(.date)  \(.status)  (attempts: \(.attempts // 1))"
            '
        fi
    fi
}

cmd_backlog_rm() {
    local id="${1:-}" force=false
    [[ -z "$id" ]] && { log_error "Usage: backlog rm <ID> [--force]"; return 1; }
    shift || true

    parse_opts "bool:force:--force" -- "$@" || return 1

    local title
    title=$(find_item "$id" | jq -r '.title') || return 1

    local file
    file=$(resolve_backlog_file "$id") || return 1

    if [[ "$force" == "false" ]]; then
        echo "Remove $id: $title?"
        read -r -p "Confirm (y/N): " confirm
        [[ "$confirm" != "y" && "$confirm" != "Y" ]] && { echo "Cancelled"; return 0; }
    fi

    if ! remove_item "$file" "$id"; then
        log_error "Failed to remove item"
        return 1
    fi

    # Clean stale dependsOn references to the removed item in all backlog files
    local bf
    for bf in "${BACKLOG_FILES[@]}"; do
        [[ -f "$BACKLOG_DIR/$bf" ]] || continue
        if jq -e --arg id "$id" '.items[] | select(.dependsOn[]? == $id)' "$BACKLOG_DIR/$bf" >/dev/null 2>&1; then
            local tmp
            tmp="$(ensure_tmpdir)/clean_deps.json"
            jq --arg id "$id" '.items |= map(.dependsOn |= (if . then map(select(. != $id)) else . end))' "$BACKLOG_DIR/$bf" > "$tmp" && mv "$tmp" "$BACKLOG_DIR/$bf"
        fi
    done

    log_success "Removed $id: $title"
}

cmd_backlog_requeue() {
    if [[ "${1:-}" == "--all" ]]; then
        _backlog_requeue_all
        return $?
    fi

    local id="${1:-}"
    [[ -z "$id" ]] && { log_error "Usage: backlog requeue <ID|--all>"; return 1; }
    [[ $# -gt 1 ]] && { log_error "Unexpected argument: ${2}"; return 1; }

    local item
    item=$(find_item "$id") || return 1

    local title status
    title=$(printf '%s\n' "$item" | jq -r '.title')
    status=$(printf '%s\n' "$item" | jq -r '.status // "todo"')

    if [[ "$status" == "todo" ]]; then
        local fail_count
        fail_count=$(printf '%s\n' "$item" | jq -r '.failCount // 0')
        if [[ "$fail_count" -eq 0 ]]; then
            log_info "$id is already todo with no failure history"
            return 0
        fi
    fi

    local file
    file=$(resolve_backlog_file "$id") || return 1

    if ! dal_update_item "$file" "$id" \
        '| .status = "todo" | .passes = false | del(.lastFailReason) | del(.lastFailAt) | del(.failCount)'; then
        log_error "Failed to requeue item $id"
        return 1
    fi

    log_success "Requeued $id: $title (status → todo, failure tracking cleared)"
}

_backlog_requeue_all() {
    local requeued=0
    local -a requeued_ids=()

    for f in "${BACKLOG_FILES[@]}"; do
        [[ -f "$BACKLOG_DIR/$f" ]] || continue

        local ids
        ids=$(jq -r '.items[] | select((.failCount // 0) > 0) | .id' "$BACKLOG_DIR/$f" 2>/dev/null) || continue
        [[ -z "$ids" ]] && continue

        while IFS= read -r id; do
            [[ -z "$id" ]] && continue
            if dal_update_item "$f" "$id" \
                '| .status = "todo" | .passes = false | del(.lastFailReason) | del(.lastFailAt) | del(.failCount)'; then
                requeued_ids+=("$id")
                requeued=$((requeued + 1))
            else
                log_error "Failed to requeue $id"
            fi
        done <<< "$ids"
    done

    if [[ "$requeued" -eq 0 ]]; then
        log_info "No failed items found"
        return 0
    fi

    log_success "Requeued $requeued item(s): ${requeued_ids[*]}"
    return 0
}

cmd_backlog_stats() {
    local sprints_file="$ARCHIVE_DIR/sprints.jsonl"

    if [[ ! -f "$sprints_file" ]] || [[ ! -s "$sprints_file" ]]; then
        log_info "No sprint archive found — run some sprints first"
        return 0
    fi

    local stats
    stats=$(jq -s '
        {
            total: length,
            complete: [.[] | select(.status == "complete")] | length,
            failed: [.[] | select(.status != "complete")] | length,
            durations: [.[] | select(.duration != null) | .duration],
            priorities: [.[] | select(.priority != null) | .priority],
            attempts: [.[] | .attempts // 1],
            dates: [.[] | .date] | sort,
            items: [.[] | .itemId] | unique | length
        } | . + {
            success_rate: (if .total > 0 then (100.0 * .complete / .total) else 0 end),
            dur_avg: (if (.durations | length) > 0 then (.durations | add / length) else null end),
            dur_min: (if (.durations | length) > 0 then (.durations | min) else null end),
            dur_max: (if (.durations | length) > 0 then (.durations | max) else null end),
            dur_count: (.durations | length),
            first_date: (.dates | first),
            last_date: (.dates | last),
            retried: ([.attempts[] | select(. > 1)] | length),
            pri_must: ([.priorities[] | select(. == "must")] | length),
            pri_should: ([.priorities[] | select(. == "should")] | length),
            pri_could: ([.priorities[] | select(. == "could")] | length),
            pri_future: ([.priorities[] | select(. == "future")] | length),
            pri_unset: (.total - ([.priorities[]] | length))
        }
    ' "$sprints_file" 2>/dev/null)

    if [[ -z "$stats" ]]; then
        log_error "Failed to parse sprint archive"
        return 1
    fi

    local total complete failed success_rate items
    total=$(printf '%s' "$stats" | jq -r '.total')
    complete=$(printf '%s' "$stats" | jq -r '.complete')
    failed=$(printf '%s' "$stats" | jq -r '.failed')
    success_rate=$(printf '%s' "$stats" | jq -r '.success_rate | . * 10 | round / 10')
    items=$(printf '%s' "$stats" | jq -r '.items')

    local dur_avg dur_min dur_max dur_count
    dur_count=$(printf '%s' "$stats" | jq -r '.dur_count')
    dur_avg=$(printf '%s' "$stats" | jq -r 'if .dur_avg then (.dur_avg | . * 10 | round / 10 | tostring + "s") else "-" end')
    dur_min=$(printf '%s' "$stats" | jq -r 'if .dur_min then (.dur_min | tostring + "s") else "-" end')
    dur_max=$(printf '%s' "$stats" | jq -r 'if .dur_max then (.dur_max | tostring + "s") else "-" end')

    local retried first_date last_date
    retried=$(printf '%s' "$stats" | jq -r '.retried')
    first_date=$(printf '%s' "$stats" | jq -r '.first_date // "-"')
    last_date=$(printf '%s' "$stats" | jq -r '.last_date // "-"')

    local pri_must pri_should pri_could pri_future pri_unset
    pri_must=$(printf '%s' "$stats" | jq -r '.pri_must')
    pri_should=$(printf '%s' "$stats" | jq -r '.pri_should')
    pri_could=$(printf '%s' "$stats" | jq -r '.pri_could')
    pri_future=$(printf '%s' "$stats" | jq -r '.pri_future')
    pri_unset=$(printf '%s' "$stats" | jq -r '.pri_unset')

    echo ""
    echo "Sprint Velocity & Success Metrics"
    echo "══════════════════════════════════"
    echo ""
    printf "  %-24s %s\n" "Total sprints:" "$total"
    printf "  %-24s %s\n" "Unique items:" "$items"
    printf "  %-24s %s\n" "Completed:" "$complete"
    printf "  %-24s %s\n" "Failed:" "$failed"
    printf "  %-24s %s\n" "Success rate:" "${success_rate}%"
    printf "  %-24s %s\n" "Sprints with retries:" "$retried"
    printf "  %-24s %s\n" "Date range:" "${first_date} → ${last_date}"
    echo ""
    echo "Duration (${dur_count} sprints with timing data)"
    echo "──────────────────────────────────"
    printf "  %-24s %s\n" "Average:" "$dur_avg"
    printf "  %-24s %s\n" "Min:" "$dur_min"
    printf "  %-24s %s\n" "Max:" "$dur_max"
    echo ""
    echo "Completed by Priority"
    echo "──────────────────────────────────"
    printf "  %-24s %s\n" "must:" "$pri_must"
    printf "  %-24s %s\n" "should:" "$pri_should"
    printf "  %-24s %s\n" "could:" "$pri_could"
    printf "  %-24s %s\n" "future:" "$pri_future"
    if [[ "$pri_unset" -gt 0 ]]; then
        printf "  %-24s %s\n" "(no priority):" "$pri_unset"
    fi
    echo ""
}

cmd_backlog_next() {
    local json_mode=false
    parse_opts "bool:json_mode:--json" -- "$@" || return 1

    local skip_json="[]"
    local done_ids_json
    done_ids_json=$(collect_done_ids)
    local core_healthy="${CORE_HEALTHY:-true}"

    local all_candidates="[]"
    _next_collect() {
        local backlog="$1"
        [[ -f "$BACKLOG_DIR/$backlog" ]] || return 0
        local candidates
        candidates=$(jq -r --argjson skip "$skip_json" --argjson done_ids "$done_ids_json" --arg core_healthy "$core_healthy" '
            '"$PICKABLE_ITEMS_FILTER"' |
            [.[] | '"$ITEM_PROJECTION"']
        ' "$BACKLOG_DIR/$backlog" 2>/dev/null || echo "[]")
        all_candidates=$(printf '%s\n%s\n' "$all_candidates" "$candidates" | jq -s 'add // []')
    }
    map_backlog_files _next_collect

    local best
    best=$(printf '%s\n' "$all_candidates" | jq -r "$JQ_PRIO_RANK"'
        sort_by([(if .category == "heal" then 0 else 1 end), (.priority // "should" | prio_rank)]) | first // empty
    ' 2>/dev/null)

    if [[ -z "$best" || "$best" == "null" ]]; then
        log_warning "No pickable items found"
        return 1
    fi

    if [[ "$json_mode" == "true" ]]; then
        printf '%s\n' "$best"
        return 0
    fi

    printf '%s\n' "$best" | jq -r '"\(.id)  \(.title)",
        "  Priority: \(.priority // "-")",
        "  Track:    \(.track // "feature")"'
}
