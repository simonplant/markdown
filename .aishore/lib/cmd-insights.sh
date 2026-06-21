#!/usr/bin/env bash
# Module: cmd-insights — cross-session sprint insights from archive analysis
# Lazy-loaded by _load_module; all globals (ARCHIVE_DIR, BACKLOG_DIR, BACKLOG_FILES,
# BLUE, CYAN, GREEN, YELLOW, RED, NC, log_header, log_subheader, log_info, log_warning,
# log_success, require_tool, load_config, parse_opts) come from the main script.

cmd_insights() {
    require_tool jq
    load_config

    local sprints_file="$ARCHIVE_DIR/sprints.jsonl"
    local regression_file="$ARCHIVE_DIR/regression.jsonl"

    if [[ ! -f "$sprints_file" ]] || [[ ! -s "$sprints_file" ]]; then
        log_warning "No sprint archive found — run some sprints first"
        return 0
    fi

    log_header "Sprint Insights"

    _insights_overview "$sprints_file"
    _insights_failure_patterns "$sprints_file"
    _insights_fragile_files "$regression_file"
    _insights_velocity_trends "$sprints_file"
    _insights_recommendations "$sprints_file" "$regression_file"

    echo ""
}

# ---------------------------------------------------------------------------
# Overview: total sprints, success rate, date range
# ---------------------------------------------------------------------------
_insights_overview() {
    local sprints_file="$1"

    log_subheader "Overview"

    local total complete failed first_date last_date
    total=$(wc -l < "$sprints_file" | tr -d ' ')
    complete=$(jq -sr '[.[] | select(.status == "complete")] | length' "$sprints_file")
    failed=$(jq -sr '[.[] | select(.status == "failed")] | length' "$sprints_file")
    first_date=$(jq -sr '.[0].date // "unknown"' "$sprints_file")
    last_date=$(jq -sr '.[-1].date // "unknown"' "$sprints_file")

    echo "  Total sprints: $total"
    echo "  Completed:     $complete"
    echo "  Failed:        $failed"
    if [[ "$total" -gt 0 ]]; then
        local success_rate
        success_rate=$(( (complete * 100) / total ))
        echo "  Success rate:  ${success_rate}%"
    fi
    echo "  Date range:    $first_date → $last_date"
}

# ---------------------------------------------------------------------------
# Failure patterns: items with multiple attempts, retries, by priority
# ---------------------------------------------------------------------------
_insights_failure_patterns() {
    local sprints_file="$1"

    log_subheader "Failure Patterns"

    # Items that needed retries (attempts > 1)
    local retry_items
    retry_items=$(jq -sr '[.[] | select((.attempts // 1) > 1)] | .[] | "\(.itemId) (\(.attempts) attempts) — \(.title // .itemId)"' "$sprints_file" 2>/dev/null)

    if [[ -n "$retry_items" ]]; then
        echo "  Items that needed retries:"
        while IFS= read -r line; do
            echo "    - $line"
        done <<< "$retry_items"
    else
        echo "  No items required retries"
    fi

    # Failed sprints
    local failed_items
    failed_items=$(jq -sr '[.[] | select(.status == "failed")] | .[] | "\(.itemId) — \(.title // .itemId)"' "$sprints_file" 2>/dev/null)

    if [[ -n "$failed_items" ]]; then
        echo ""
        echo "  Failed sprints:"
        while IFS= read -r line; do
            echo "    - $line"
        done <<< "$failed_items"
    fi

    # Failure rate by priority
    echo ""
    echo "  Failure rate by priority:"
    local priority_stats
    priority_stats=$(jq -sr '
        [.[] | select(.priority != null)] |
        group_by(.priority) |
        map({
            priority: .[0].priority,
            total: length,
            failed: ([.[] | select(.status == "failed")] | length),
            retried: ([.[] | select((.attempts // 1) > 1)] | length)
        }) |
        sort_by(.priority) |
        .[] |
        "    \(.priority): \(.total) sprints, \(.failed) failed, \(.retried) retried"
    ' "$sprints_file" 2>/dev/null)

    if [[ -n "$priority_stats" ]]; then
        echo "$priority_stats"
    else
        echo "    (no priority data available — older sprints lack this field)"
    fi

    # Failure rate by item prefix (FEAT vs BUG)
    echo ""
    echo "  By item type:"
    jq -sr '
        group_by(.itemId | split("-")[0]) |
        map({
            type: .[0].itemId | split("-")[0],
            total: length,
            failed: ([.[] | select(.status == "failed")] | length),
            avg_attempts: (([.[] | .attempts // 1] | add) / length * 10 | round / 10)
        }) |
        .[] |
        "    \(.type): \(.total) sprints, \(.failed) failed, avg \(.avg_attempts) attempts"
    ' "$sprints_file" 2>/dev/null || echo "    (unable to compute)"
}

# ---------------------------------------------------------------------------
# Fragile files: files frequently mentioned in regression suite
# ---------------------------------------------------------------------------
_insights_fragile_files() {
    local regression_file="$1"

    log_subheader "Fragile File Detection"

    if [[ ! -f "$regression_file" ]] || [[ ! -s "$regression_file" ]]; then
        echo "  No regression data available yet"
        return 0
    fi

    local regression_count
    regression_count=$(grep -c '{' "$regression_file" 2>/dev/null || echo 0)
    echo "  Regression suite: $regression_count checks"

    # Extract file references from verify commands
    local file_refs
    file_refs=$(jq -r '.verify // empty' "$regression_file" 2>/dev/null | \
        grep -oE '[a-zA-Z0-9_./-]+\.(sh|json|js|ts|py|md|yaml|yml)' | \
        sort | uniq -c | sort -rn | head -10)

    if [[ -n "$file_refs" ]]; then
        echo ""
        echo "  Most referenced files in regression checks:"
        while IFS= read -r line; do
            local count file
            count=$(echo "$line" | awk '{print $1}')
            file=$(echo "$line" | awk '{print $2}')
            echo "    ${count}x  $file"
        done <<< "$file_refs"
    fi

    # Items contributing most regression checks
    echo ""
    echo "  Items with most regression checks:"
    jq -sr '
        group_by(.itemId) |
        map({itemId: .[0].itemId, count: length}) |
        sort_by(-.count) |
        .[:5] |
        .[] |
        "    \(.count) checks from \(.itemId)"
    ' "$regression_file" 2>/dev/null || echo "    (unable to compute)"
}

# ---------------------------------------------------------------------------
# Velocity & trends: sprints per day, duration trends, size trends
# ---------------------------------------------------------------------------
_insights_velocity_trends() {
    local sprints_file="$1"

    log_subheader "Sprint Velocity & Trends"

    # Sprints per day
    echo "  Sprints per session:"
    jq -sr '
        group_by(.date) |
        map({date: .[0].date, count: length}) |
        sort_by(.date) |
        .[-10:] |
        .[] |
        "    \(.date): \(.count) sprints"
    ' "$sprints_file" 2>/dev/null || echo "    (unable to compute)"

    # Duration trends (recent vs older, for items that have duration)
    local has_duration
    has_duration=$(jq -sr '[.[] | select(.duration != null)] | length' "$sprints_file" 2>/dev/null)

    if [[ "$has_duration" -gt 0 ]]; then
        echo ""
        echo "  Duration stats (completed sprints with timing data):"
        jq -sr '
            [.[] | select(.duration != null and .status == "complete")] |
            if length == 0 then "    (no duration data)"
            else
                {
                    count: length,
                    avg: (([.[].duration] | add) / length | round),
                    min: ([.[].duration] | min),
                    max: ([.[].duration] | max),
                    median: (sort_by(.duration) | .[length/2 | floor].duration)
                } |
                "    Avg: \(.avg)s  Min: \(.min)s  Max: \(.max)s  Median: \(.median)s  (n=\(.count))"
            end
        ' "$sprints_file" 2>/dev/null || echo "    (unable to compute)"
    fi

    # Code churn trends
    local has_lines
    has_lines=$(jq -sr '[.[] | select(.linesAdded != null)] | length' "$sprints_file" 2>/dev/null)

    if [[ "$has_lines" -gt 0 ]]; then
        echo ""
        echo "  Code churn (sprints with size data):"
        jq -sr '
            [.[] | select(.linesAdded != null and .status == "complete")] |
            if length == 0 then "    (no size data)"
            else
                {
                    count: length,
                    avg_added: (([.[].linesAdded] | add) / length | round),
                    avg_removed: (([.[].linesRemoved] | add) / length | round),
                    avg_files: (([.[].filesChanged] | add) / length * 10 | round / 10)
                } |
                "    Avg lines added: \(.avg_added)  Avg removed: \(.avg_removed)  Avg files: \(.avg_files)  (n=\(.count))"
            end
        ' "$sprints_file" 2>/dev/null || echo "    (unable to compute)"
    fi
}

# ---------------------------------------------------------------------------
# Actionable recommendations based on the data
# ---------------------------------------------------------------------------
_insights_recommendations() {
    local sprints_file="$1"
    local regression_file="$2"

    log_subheader "Recommendations"

    local has_recs=false

    # Check for high retry items
    local retry_count
    retry_count=$(jq -sr '[.[] | select((.attempts // 1) > 1)] | length' "$sprints_file" 2>/dev/null || echo 0)
    local total
    total=$(wc -l < "$sprints_file" | tr -d ' ')

    if [[ "$total" -gt 0 ]] && [[ "$retry_count" -gt 0 ]]; then
        local retry_pct=$(( (retry_count * 100) / total ))
        if [[ "$retry_pct" -gt 20 ]]; then
            echo "  - High retry rate (${retry_pct}%): consider improving AC specificity or grooming quality"
            has_recs=true
        fi
    fi

    # Check for failed sprints
    local failed_count
    failed_count=$(jq -sr '[.[] | select(.status == "failed")] | length' "$sprints_file" 2>/dev/null || echo 0)
    if [[ "$failed_count" -gt 0 ]]; then
        echo "  - ${failed_count} sprint(s) failed: review failed items for unclear intent or overly broad scope"
        has_recs=true
    fi

    # Check regression suite size
    if [[ -f "$regression_file" ]] && [[ -s "$regression_file" ]]; then
        local reg_count
        reg_count=$(grep -c '{' "$regression_file" 2>/dev/null || echo 0)
        if [[ "$reg_count" -gt 50 ]]; then
            echo "  - Large regression suite ($reg_count checks): consider 'clean --regression' to prune obsolete entries"
            has_recs=true
        fi
    fi

    # Check for items without duration data (old format)
    local no_duration
    no_duration=$(jq -sr '[.[] | select(.duration == null)] | length' "$sprints_file" 2>/dev/null || echo 0)
    if [[ "$no_duration" -gt 10 ]]; then
        echo "  - ${no_duration} sprints lack timing data (older format): trend analysis improves as new sprints accumulate"
        has_recs=true
    fi

    # Check velocity trend — are recent sessions faster?
    local recent_avg older_avg
    recent_avg=$(jq -sr '
        [.[] | select(.duration != null)] | sort_by(.date) |
        .[-20:] | if length > 0 then ([.[].duration] | add / length | round) else null end
    ' "$sprints_file" 2>/dev/null)
    older_avg=$(jq -sr '
        [.[] | select(.duration != null)] | sort_by(.date) |
        .[:20] | if length > 0 then ([.[].duration] | add / length | round) else null end
    ' "$sprints_file" 2>/dev/null)

    if [[ -n "$recent_avg" && "$recent_avg" != "null" && -n "$older_avg" && "$older_avg" != "null" ]]; then
        if [[ "$recent_avg" -lt "$older_avg" ]]; then
            echo "  - Sprint duration improving: recent avg ${recent_avg}s vs earlier ${older_avg}s"
            has_recs=true
        elif [[ "$recent_avg" -gt $(( older_avg + older_avg / 4 )) ]]; then
            echo "  - Sprint duration increasing: recent avg ${recent_avg}s vs earlier ${older_avg}s — items may be growing in complexity"
            has_recs=true
        fi
    fi

    if [[ "$has_recs" == "false" ]]; then
        log_success "No issues detected — sprint history looks healthy"
    fi
}
