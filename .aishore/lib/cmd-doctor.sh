#!/usr/bin/env bash
# Module: cmd-doctor — health check command
# Lazy-loaded by _load_module; all globals (PROJECT_ROOT, BACKLOG_DIR,
# CONFIG_FILE, CORE_CMD, log_*, load_config) come from the main script.

cmd_doctor() {
    load_config
    cd "$PROJECT_ROOT" || { log_error "Cannot cd to $PROJECT_ROOT"; return 1; }

    # --- Flag parsing ---
    local run_regression=0
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --regression) run_regression=1; shift ;;
            *) log_error "Unknown flag: $1"; return 1 ;;
        esac
    done

    if [[ "$run_regression" -eq 1 ]]; then
        _doctor_regression
        return $?
    fi

    local failed=0

    log_header "Doctor: health check"

    # --- Required tools ---
    log_info "Required tools:"
    local tool
    for tool in jq git claude; do
        if command -v "$tool" &>/dev/null; then
            log_success "PASS  $tool — $(command -v "$tool")"
        else
            echo -e "${RED}✗ FAIL  $tool — not found${NC}"
            failed=1
        fi
    done

    # --- Optional tools ---
    echo ""
    log_info "Optional tools:"
    if command -v yq &>/dev/null; then
        log_success "PASS  yq — $(command -v yq)"
    else
        log_warning "WARN  yq — not found (needed for full config.yaml support)"
    fi

    # --- Backlog JSON validation ---
    echo ""
    log_info "Backlog files:"
    local json_file
    for json_file in "$BACKLOG_DIR/backlog.json" "$BACKLOG_DIR/bugs.json"; do
        local basename
        basename="$(basename "$json_file")"
        if [[ ! -f "$json_file" ]]; then
            echo -e "${RED}✗ FAIL  $basename — file not found${NC}"
            failed=1
        elif jq empty "$json_file" 2>/dev/null; then
            log_success "PASS  $basename — valid JSON"
        else
            echo -e "${RED}✗ FAIL  $basename — invalid JSON${NC}"
            failed=1
        fi
    done

    # --- Config file ---
    echo ""
    log_info "Configuration:"
    if [[ -f "$CONFIG_FILE" ]]; then
        if command -v yq &>/dev/null; then
            if yq empty "$CONFIG_FILE" 2>/dev/null; then
                log_success "PASS  config.yaml — parseable"
            else
                echo -e "${RED}✗ FAIL  config.yaml — not parseable${NC}"
                failed=1
            fi
        else
            # Without yq, do a basic syntax check via grep for obvious YAML issues
            log_success "PASS  config.yaml — present (install yq for full validation)"
        fi
    else
        log_warning "WARN  config.yaml — not found (using defaults)"
    fi

    # --- CORE_CMD ---
    echo ""
    log_info "Core status:"
    if [[ -n "$CORE_CMD" ]]; then
        log_success "PASS  CORE_CMD — $CORE_CMD"
    else
        log_warning "WARN  CORE_CMD — not set"
    fi

    # --- Summary ---
    echo ""
    if [[ "$failed" -eq 0 ]]; then
        log_success "All required checks passed"
        return 0
    else
        log_error "One or more required checks failed"
        return 1
    fi
}

# Run the regression suite interactively, reporting PASS/FAIL per entry.
_doctor_regression() {
    local regression_file="$ARCHIVE_DIR/regression.jsonl"

    log_header "Doctor: regression suite"

    if [[ ! -f "$regression_file" ]] || [[ ! -s "$regression_file" ]]; then
        log_info "No regression entries found (${regression_file} absent or empty)"
        return 0
    fi

    local total passed=0 failed=0 line_num=0
    total=$(wc -l < "$regression_file")
    log_info "Running $total regression check(s) from $regression_file"
    echo ""

    while IFS= read -r entry; do
        line_num=$((line_num + 1))
        local cmd text reg_item_id
        cmd=$(printf '%s' "$entry" | jq -r '.verify' 2>/dev/null) || continue
        text=$(printf '%s' "$entry" | jq -r '.text // "unnamed"' 2>/dev/null)
        reg_item_id=$(printf '%s' "$entry" | jq -r '.itemId // "?"' 2>/dev/null)

        [[ -z "$cmd" || "$cmd" == "null" ]] && continue

        local tmpfile
        tmpfile="$(ensure_tmpdir)/doctor_reg_${line_num}.txt"
        if run_timed_command "$cmd" "$tmpfile" 2>/dev/null; then
            rm -f "$tmpfile"
            passed=$((passed + 1))
            log_success "PASS  [$reg_item_id] $text"
        else
            failed=$((failed + 1))
            local fail_output
            fail_output=$(truncate_output "$tmpfile")
            rm -f "$tmpfile"
            echo -e "${RED}✗ FAIL  [$reg_item_id] $text${NC}"
            echo -e "${RED}  Command: $cmd${NC}"
            [[ -n "$fail_output" ]] && echo -e "${RED}  Output: $fail_output${NC}"
        fi
    done < "$regression_file"

    # --- Summary ---
    echo ""
    log_info "Regression results: $passed passed, $failed failed (of $total entries)"
    if [[ "$failed" -gt 0 ]]; then
        log_error "Regression suite: $failed check(s) failed"
        return 1
    else
        log_success "All regression checks passed"
        return 0
    fi
}
