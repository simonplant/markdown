#!/usr/bin/env bash
# Module: cmd-status — backlog status overview command
# Lazy-loaded by _load_module; all globals (ARCHIVE_DIR, BACKLOG_DIR, BACKLOG_FILES,
# STATUS_DIR, CYAN, NC, colors, jq, count_items, list_ready_items, log_*, parse_opts)
# come from the main script.

_status_output() {
    local sprints_file="$ARCHIVE_DIR/sprints.jsonl"

    log_header "Backlog Status"
    echo ""

    # --- Item counts by status per declared file (single jq pass per file) ---
    local any_file=false
    local total=0 done_total=0
    local f
    for f in "${BACKLOG_FILES[@]}"; do
        local full_path="$BACKLOG_DIR/$f"
        [[ -f "$full_path" ]] || continue
        any_file=true
        local f_todo f_inprog f_done
        read -r f_todo f_inprog f_done < <(jq -r '[
            ([.items[] | select((.status // "todo") == "todo")] | length),
            ([.items[] | select(.status == "in-progress")] | length),
            ([.items[] | select(.status == "done")] | length)
        ] | @tsv' "$full_path" 2>/dev/null || echo "0 0 0")
        local label="${f%.json}"
        echo "${label}: ${f_todo:-0} todo, ${f_inprog:-0} in-progress, ${f_done:-0} done"
        total=$((total + $(count_items "$full_path")))
        done_total=$((done_total + ${f_done:-0}))
    done

    if [[ "$any_file" == "false" ]]; then
        log_warning "Backlog is empty"
    fi

    # --- Ready for sprint ---
    echo ""
    log_subheader "Ready for sprint"
    local has_ready=false

    for f in "${BACKLOG_FILES[@]}"; do
        [[ -f "$BACKLOG_DIR/$f" ]] || continue
        local ready
        ready=$(list_ready_items "$BACKLOG_DIR/$f")
        if [[ -n "$ready" ]]; then
            printf '%s\n' "$ready"
            has_ready=true
        fi
    done

    if [[ "$has_ready" == "false" ]]; then
        if [[ "$total" -eq 0 ]]; then
            log_warning "Backlog is empty — add items with 'backlog add' or 'backlog populate'"
        else
            log_warning "No items ready for sprint — run 'groom' (AI prepares steps, AC, and priority) or 'backlog check --all' to diagnose"
        fi
    fi

    # --- Ready count summary ---
    local ready_total=0
    for f in "${BACKLOG_FILES[@]}"; do
        [[ -f "$BACKLOG_DIR/$f" ]] || continue
        ready_total=$((ready_total + $(count_ready_items "$BACKLOG_DIR/$f")))
    done
    log_info "$ready_total/$total items ready for sprint"

    # --- Core/feature split for ready items ---
    if [[ -n "${CORE_CMD:-}" ]] && [[ "$ready_total" -gt 0 ]]; then
        local core_ready=0 feature_ready=0
        for f in "${BACKLOG_FILES[@]}"; do
            [[ -f "$BACKLOG_DIR/$f" ]] || continue
            local _cr _fr
            _cr=$(jq '[.items[] | select(.readyForSprint == true and (.status == "todo" or .status == null) and (.track // "feature") == "core")] | length' "$BACKLOG_DIR/$f" 2>/dev/null || echo 0)
            _fr=$(jq '[.items[] | select(.readyForSprint == true and (.status == "todo" or .status == null) and (.track // "feature") == "feature")] | length' "$BACKLOG_DIR/$f" 2>/dev/null || echo 0)
            core_ready=$((core_ready + _cr))
            feature_ready=$((feature_ready + _fr))
        done
        echo "  core: $core_ready ready, feature: $feature_ready ready"
    fi

    # --- Core health ---
    if [[ -n "$CORE_CMD" ]]; then
        echo ""
        log_subheader "Core health"
        local core_tmpfile
        core_tmpfile="$(ensure_tmpdir)/status_core_check.txt"
        if run_timed_command "$CORE_CMD" "$core_tmpfile"; then
            rm -f "$core_tmpfile"
            log_success "Core: healthy ($CORE_CMD)"
        else
            rm -f "$core_tmpfile"
            log_error "Core: FAILING ($CORE_CMD)"
            # Count core vs feature items
            local core_ready=0 feature_ready=0
            for f in "${BACKLOG_FILES[@]}"; do
                [[ -f "$BACKLOG_DIR/$f" ]] || continue
                local _cr _fr
                _cr=$(jq '[.items[] | select(.readyForSprint == true and (.status == "todo" or .status == null) and (.track // "feature") == "core")] | length' "$BACKLOG_DIR/$f" 2>/dev/null || echo 0)
                _fr=$(jq '[.items[] | select(.readyForSprint == true and (.status == "todo" or .status == null) and (.track // "feature") == "feature")] | length' "$BACKLOG_DIR/$f" 2>/dev/null || echo 0)
                core_ready=$((core_ready + _cr))
                feature_ready=$((feature_ready + _fr))
            done
            echo "  Core items:    $core_ready ready"
            echo "  Feature items: $feature_ready ready (blocked until core passes)"
        fi
    else
        echo ""
        log_warning "Core: not configured — run 'scaffold' to establish CORE_CMD"
    fi

    # --- Currently running ---
    local sprint_file="$BACKLOG_DIR/sprint.json"
    if [[ -f "$sprint_file" ]]; then
        local sprint_status sprint_item_id sprint_item_title
        sprint_status=$(jq -r '.status // "idle"' "$sprint_file" 2>/dev/null || echo "idle")
        if [[ "$sprint_status" == "in_progress" ]]; then
            sprint_item_id=$(jq -r '.item.id // empty' "$sprint_file" 2>/dev/null || true)
            sprint_item_title=$(jq -r '.item.title // empty' "$sprint_file" 2>/dev/null || true)
            if [[ -n "$sprint_item_id" ]]; then
                echo ""
                log_subheader "Currently running"
                echo "  ${sprint_item_id} — ${sprint_item_title}"
            fi
        fi
    fi

    # --- Recent sprints ---
    echo ""
    log_subheader "Recent sprints"
    if [[ -f "$sprints_file" ]] && [[ -s "$sprints_file" ]]; then
        tail -5 "$sprints_file" | jq -r '"\(.date) \(.itemId) \(.status) \((.title // "-") | if length > 40 then .[:40] + "…" else . end)"' 2>/dev/null | while IFS= read -r line; do
            echo "  $line"
        done
    else
        log_info "No sprints run yet"
    fi

    # --- Warnings ---
    local prd_path
    prd_path=$(_find_prd)
    if [[ -z "$prd_path" ]] || _is_template_prd "$prd_path"; then
        echo ""
        if [[ -z "$prd_path" ]]; then
            log_warning "No PRODUCT.md found — agents work better with product context"
            echo "  Create one: .aishore/aishore refine"
        else
            log_warning "PRODUCT.md is still a template — fill it in so agents understand what you're building"
            echo "  Edit: $prd_path"
            echo "  Or run: .aishore/aishore refine"
        fi
    fi

    if [[ "$total" -gt 0 && "$total" -eq "$done_total" ]]; then
        echo ""
        log_info "All items completed"
    fi

    # --- Quickstart hint for empty projects ---
    if [[ "$total" -eq 0 ]]; then
        echo ""
        echo "  Getting started:"
        echo "    1. .aishore/aishore refine              # describe what you're building"
        echo "    2. .aishore/aishore backlog populate     # create items from PRODUCT.md"
        echo "    3. .aishore/aishore groom                # prepare items for sprint"
        echo "    4. .aishore/aishore run                  # execute first sprint"
    fi
}

cmd_status() {
    require_tool jq
    load_config

    local json_mode=false
    parse_opts "bool:json_mode:--json" -- "$@" || return 1

    if [[ "$json_mode" == "true" ]]; then
        _status_json
        return 0
    fi

    _status_output
}

_status_json() {
    local total=0 todo=0 in_progress=0 done_count=0 ready=0 failed=0
    local f
    for f in "${BACKLOG_FILES[@]}"; do
        local full_path="$BACKLOG_DIR/$f"
        [[ -f "$full_path" ]] || continue
        local f_total f_todo f_inprog f_done f_ready f_failed
        read -r f_total f_todo f_inprog f_done f_ready f_failed < <(jq -r '[
            (.items | length),
            ([.items[] | select((.status // "todo") == "todo")] | length),
            ([.items[] | select(.status == "in-progress")] | length),
            ([.items[] | select(.status == "done")] | length),
            ([.items[] | select(.readyForSprint == true and ((.status // "todo") == "todo"))] | length),
            ([.items[] | select((.failCount // 0) > 0)] | length)
        ] | @tsv' "$full_path" 2>/dev/null || echo "0 0 0 0 0 0")
        total=$((total + ${f_total:-0}))
        todo=$((todo + ${f_todo:-0}))
        in_progress=$((in_progress + ${f_inprog:-0}))
        done_count=$((done_count + ${f_done:-0}))
        ready=$((ready + ${f_ready:-0}))
        failed=$((failed + ${f_failed:-0}))
    done
    jq -n --argjson total "$total" \
          --argjson todo "$todo" \
          --argjson in_progress "$in_progress" \
          --argjson done "$done_count" \
          --argjson ready "$ready" \
          --argjson failed "$failed" \
          '{total: $total, todo: $todo, in_progress: $in_progress, done: $done, ready: $ready, failed: $failed}'
}
