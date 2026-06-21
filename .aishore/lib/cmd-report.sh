# shellcheck shell=bash
# cmd-report.sh — Sprint report generation
# Generates a shareable markdown sprint report after batch runs.
# Loaded via _load_module from print_sprint_summary().

# Generate a markdown sprint report for the current batch.
# Uses outer-scope locals from cmd_run: sprint_items, COMPLETED_IDS, FAILED_IDS,
#   ITEM_ATTEMPTS, batch_start, passed, failed, queued_ids, session_successes,
#   session_failures, auto_mode, auto_scope
# Uses globals: ARCHIVE_DIR, CORE_CMD, CORE_HEALTHY, REGRESSION_TOTAL,
#   REGRESSION_PASSED, REGRESSION_FAILED, AISHORE_VERSION, PROJECT_ROOT
# Writes report to .aishore/data/reports/sprint-<date>.md
# Prints compact summary to stdout.
# shellcheck disable=SC2154 # sprint_items, COMPLETED_IDS, FAILED_IDS, ITEM_ATTEMPTS,
# batch_start, passed, failed, queued_ids, session_failures, auto_mode, auto_scope
# are outer-scope locals from cmd_run in the main script
generate_sprint_report() {
    local reports_dir="$DATA_DIR/reports"
    mkdir -p "$reports_dir"

    local batch_end
    batch_end=$(date +%s)
    local elapsed_sec=$(( batch_end - batch_start ))
    local elapsed_min=$(( elapsed_sec / 60 ))
    local elapsed_rem=$(( elapsed_sec % 60 ))
    local report_date
    report_date=$(date +%Y-%m-%d)
    local report_time
    report_time=$(date +%H:%M)
    local skipped=$(( ${#queued_ids[@]} - passed - failed ))
    [[ "$skipped" -lt 0 ]] && skipped=0

    # Build item table rows from archive data for this batch's items
    local item_table=""
    local total_lines_added=0 total_lines_removed=0 total_files_changed=0
    local archive_file="$ARCHIVE_DIR/sprints.jsonl"

    for sid in "${sprint_items[@]}"; do
        local _status _duration_str _lines _attempts _title
        _attempts="${ITEM_ATTEMPTS[$sid]:-1}"

        if [[ -n "${COMPLETED_IDS[$sid]+_}" ]]; then
            _status="Pass"
        elif [[ -n "${FAILED_IDS[$sid]+_}" ]]; then
            _status="Fail"
        else
            _status="Unknown"
        fi

        # Try to get enriched data from archive (grep may return 1 on no match)
        local _archive_rec=""
        if [[ -f "$archive_file" ]]; then
            _archive_rec=$(grep "\"itemId\":\"${sid}\"" "$archive_file" | tail -1 || true)
        fi

        local _dur=0 _files=0 _added=0 _removed=0
        _title="$sid"
        if [[ -n "$_archive_rec" ]]; then
            _dur=$(printf '%s' "$_archive_rec" | jq -r '.duration // 0' 2>/dev/null || echo 0)
            _files=$(printf '%s' "$_archive_rec" | jq -r '.filesChanged // 0' 2>/dev/null || echo 0)
            _added=$(printf '%s' "$_archive_rec" | jq -r '.linesAdded // 0' 2>/dev/null || echo 0)
            _removed=$(printf '%s' "$_archive_rec" | jq -r '.linesRemoved // 0' 2>/dev/null || echo 0)
            local _arc_title
            _arc_title=$(printf '%s' "$_archive_rec" | jq -r '.title // ""' 2>/dev/null || echo "")
            [[ -n "$_arc_title" && "$_arc_title" != "null" ]] && _title="$_arc_title"
        fi

        # Format duration
        if [[ "$_dur" -ge 60 ]]; then
            _duration_str="$((_dur / 60))m $((_dur % 60))s"
        else
            _duration_str="${_dur}s"
        fi

        # Format lines changed
        _lines="+${_added}/-${_removed}"

        total_lines_added=$(( total_lines_added + _added ))
        total_lines_removed=$(( total_lines_removed + _removed ))
        total_files_changed=$(( total_files_changed + _files ))

        item_table="${item_table}| ${sid} | ${_title} | ${_status} | ${_duration_str} | ${_lines} | ${_attempts} |
"
    done

    # Core health status
    local core_status
    if [[ -z "$CORE_CMD" ]]; then
        core_status="Not configured"
    elif [[ "$CORE_HEALTHY" == "true" ]]; then
        core_status="Healthy"
    else
        core_status="Broken"
    fi

    # Regression suite stats
    local regression_status
    if [[ "$REGRESSION_TOTAL" -gt 0 ]]; then
        regression_status="${REGRESSION_PASSED}/${REGRESSION_TOTAL} passed"
        [[ "$REGRESSION_FAILED" -gt 0 ]] && regression_status="${regression_status} (${REGRESSION_FAILED} failed)"
    else
        regression_status="No regression checks"
    fi

    # Scope label for report header
    local scope_display=""
    if [[ "$auto_mode" == "true" ]]; then
        case "${auto_scope:-}" in
            p0)   scope_display="P0 (must)" ;;
            p1)   scope_display="P0+P1 (must + should)" ;;
            p2)   scope_display="P0-P2 (all priorities)" ;;
            done) scope_display="All items" ;;
            *)    scope_display="Batch" ;;
        esac
    else
        scope_display="Sprint"
    fi

    # Build the markdown report
    local report_path="${reports_dir}/sprint-${report_date}.md"
    # If a report for today already exists, append a sequence number
    if [[ -f "$report_path" ]]; then
        local seq=2
        while [[ -f "${reports_dir}/sprint-${report_date}-${seq}.md" ]]; do
            seq=$((seq + 1))
        done
        report_path="${reports_dir}/sprint-${report_date}-${seq}.md"
    fi

    cat > "$report_path" <<REPORT_EOF
# Sprint Report — ${report_date}

> Generated by [aishore](https://github.com/simonplant/aishore) v${AISHORE_VERSION} at ${report_time}

## Summary

| Metric | Value |
|--------|-------|
| Items passed | **${passed}** |
| Items failed | **${failed}** |
| Items skipped | **${skipped}** |
| Total duration | **${elapsed_min}m ${elapsed_rem}s** |
| Files changed | **${total_files_changed}** |
| Lines changed | **+${total_lines_added}/-${total_lines_removed}** |

## Items

| ID | Title | Status | Duration | Lines | Attempts |
|----|-------|--------|----------|-------|----------|
${item_table}
## Regression Suite

${regression_status}

## Core Health

${core_status}

## Session Details

- **Scope:** ${scope_display}
- **Project:** \`$(basename "$PROJECT_ROOT")\`
- **Started:** $(date -d "@${batch_start}" +"%Y-%m-%d %H:%M" 2>/dev/null || date -r "$batch_start" +"%Y-%m-%d %H:%M" 2>/dev/null || echo "unknown")
REPORT_EOF

    # Append failure details if any
    if [[ ${#session_failures[@]} -gt 0 ]]; then
        {
            echo ""
            echo "## Failures"
            echo ""
            for sf in "${session_failures[@]}"; do
                echo "- ${sf}"
            done
        } >> "$report_path"
    fi

    log_info "Sprint report: ${report_path}"

    # Print compact summary to stdout
    _print_compact_report "$passed" "$failed" "$skipped" "$elapsed_min" "$elapsed_rem" \
        "$total_lines_added" "$total_lines_removed" "$total_files_changed" \
        "$regression_status" "$core_status"
}

# Print a compact one-screen summary to stdout.
_print_compact_report() {
    local passed="$1" failed="$2" skipped="$3" mins="$4" secs="$5"
    local added="$6" removed="$7" files="$8"
    local regression="$9" core="${10}"

    echo ""
    echo -e "${CYAN}┌─────────────────────────────────────┐${NC}"
    echo -e "${CYAN}│${NC}       ${BLUE}Sprint Report${NC}                ${CYAN}│${NC}"
    echo -e "${CYAN}├─────────────────────────────────────┤${NC}"
    printf  "${CYAN}│${NC} Items:    ${GREEN}%d passed${NC}  ${RED}%d failed${NC}  %d skip ${CYAN}│${NC}\n" "$passed" "$failed" "$skipped"
    printf  "${CYAN}│${NC} Duration: %-26s ${CYAN}│${NC}\n" "${mins}m ${secs}s"
    printf  "${CYAN}│${NC} Changed:  %-4d files  ${GREEN}+%d${NC}/${RED}-%d${NC} lines  ${CYAN}│${NC}\n" "$files" "$added" "$removed"
    printf  "${CYAN}│${NC} Regress:  %-26s ${CYAN}│${NC}\n" "$regression"
    printf  "${CYAN}│${NC} Core:     %-26s ${CYAN}│${NC}\n" "$core"
    echo -e "${CYAN}└─────────────────────────────────────┘${NC}"
}
