#!/usr/bin/env bash
# Module: cmd-init — init command and helpers
# Lazy-loaded by _load_module; all globals (PROJECT_ROOT, AISHORE_ROOT, STATUS_DIR,
# LOGS_DIR, ARCHIVE_DIR, AGENTS_DIR, CONFIG_FILE, BACKLOG_DIR, CYAN, NC,
# log_header, log_subheader, log_success, log_error, log_warning, log_info,
# parse_opts, count_items, find_claude_md, _find_prd, get_claudemd_snippet)
# come from the main script.

_init_check_prereqs() {
    log_subheader "Step 1/6 — Prerequisites"

    if git -C "$PROJECT_ROOT" rev-parse --is-inside-work-tree &>/dev/null; then
        log_success "Git repository detected"
    else
        log_error "Not a git repository"
        echo "  aishore tracks work via git commits. Please initialize git first:"
        echo "    git init && git add -A && git commit -m 'initial commit'"
        return 1
    fi

    if command -v claude &>/dev/null; then
        log_success "Claude CLI found ($(claude --version 2>/dev/null || echo 'installed'))"
    else
        log_error "Claude CLI not found"
        echo "  Install it: https://docs.anthropic.com/en/docs/claude-code"
        return 1
    fi

    if command -v jq &>/dev/null; then
        log_success "jq found"
    else
        log_warning "jq not found — some features may be limited"
        echo "  Recommended: install jq (https://jqlang.github.io/jq/)"
    fi

    echo ""
}

# Detect project name, validation command, and existing docs.
# Sets outer-scope locals: project_name, core_cmd, prd_found, arch_found, claude_md
_init_detect_project() {
    local auto_yes="${1:-false}"

    # ── Project info ──
    log_subheader "Step 2/6 — Project"

    local detected_name=""
    if [[ -f "$PROJECT_ROOT/package.json" ]] && command -v jq &>/dev/null; then
        detected_name=$(jq -r '.name // empty' "$PROJECT_ROOT/package.json" 2>/dev/null || true)
    fi
    if [[ -z "$detected_name" && -f "$PROJECT_ROOT/Cargo.toml" ]]; then
        detected_name=$(grep -m1 '^name' "$PROJECT_ROOT/Cargo.toml" 2>/dev/null | sed 's/.*= *"\(.*\)"/\1/' || true)
    fi
    [[ -z "$detected_name" ]] && detected_name=$(basename "$PROJECT_ROOT")

    if [[ "$auto_yes" == "true" ]]; then
        project_name="$detected_name"
        log_info "Project name: $project_name"
    else
        read -r -p "  Project name [$detected_name]: " project_name
        project_name="${project_name:-$detected_name}"
    fi

    echo ""

    # ── Core command ──
    log_subheader "Step 3/6 — Core Command"
    echo "  aishore verifies your project's core works — the product doing its primary thing."
    echo "  This gates the sprint queue: if the core breaks, only fix items are pickable."
    echo "  Examples: 'npm run build && node -e \"require(\\\"./dist\\\")\"', 'cargo build && ./target/debug/myapp --help'"
    echo "  Leave empty to configure later (the architect agent can propose one)."
    echo ""

    local detected_core=""
    if [[ -f "$PROJECT_ROOT/package.json" ]]; then
        if command -v jq &>/dev/null; then
            local npm_script
            npm_script=$(jq -r '.scripts // {} | if .check then "check" elif .build and .test then "build+test" elif .build then "build" elif .test then "test" else empty end' "$PROJECT_ROOT/package.json" 2>/dev/null || true)
            case "$npm_script" in
                check)      detected_core="npm run check" ;;
                build+test) detected_core="npm run build && npm test" ;;
                build)      detected_core="npm run build" ;;
                test)       detected_core="npm test" ;;
            esac
        fi
    elif [[ -f "$PROJECT_ROOT/Cargo.toml" ]]; then
        detected_core="cargo build"
    elif [[ -f "$PROJECT_ROOT/Makefile" ]]; then
        detected_core="make build"
    elif [[ -f "$PROJECT_ROOT/pyproject.toml" || -f "$PROJECT_ROOT/setup.py" ]]; then
        detected_core="python -m pytest"
    elif [[ -f "$PROJECT_ROOT/go.mod" ]]; then
        detected_core="go build ./..."
    fi

    if [[ "$auto_yes" == "true" ]]; then
        core_cmd="${detected_core:-}"
        if [[ -n "$core_cmd" ]]; then
            log_info "Core command: $core_cmd"
        else
            log_info "No core command detected — skipping (configure later or run scaffold)"
        fi
    elif [[ -n "$detected_core" ]]; then
        read -r -p "  Core command [$detected_core]: " core_cmd
        core_cmd="${core_cmd:-$detected_core}"
    else
        read -r -p "  Core command (or leave empty to skip): " core_cmd
    fi

    echo ""

    # ── Product requirements ──
    log_subheader "Step 4/6 — Product requirements"
    echo "  aishore works best when agents have context about what you're building."
    echo ""

    prd_found=$(_find_prd)

    arch_found=""
    for _p in "$PROJECT_ROOT/ARCHITECTURE.md" "$PROJECT_ROOT/docs/ARCHITECTURE.md"; do
        [[ -f "$_p" ]] && { arch_found="$_p"; break; }
    done

    claude_md=$(find_claude_md)

    if [[ -n "$claude_md" ]]; then
        log_success "Found $claude_md — agents will use this automatically"
    else
        log_info "No CLAUDE.md found — will create one during scaffolding"
    fi

    if [[ -n "$prd_found" ]]; then
        log_success "Found requirements doc: $prd_found"
    else
        log_info "No product requirements doc found (PRODUCT.md, PRD.md, etc.)"
        echo "  Tip: a PRODUCT.md helps the groomer agent prioritize features."
        echo "  Even a short description of what you're building is useful."
    fi

    echo ""
}

# Create directories, config, backlogs, templates, .gitignore, CLAUDE.md.
# Uses outer-scope locals: project_name, core_cmd, claude_md, reinit, prd_found, arch_found
# Sets outer-scope locals: product_path, arch_path
_init_scaffold_files() {
    log_subheader "Step 5/6 — Scaffolding"

    mkdir -p "$STATUS_DIR" "$LOGS_DIR" "$ARCHIVE_DIR" "$AGENTS_DIR"
    log_success "Created directory structure"

    # Write config.yaml
    # Escape sed metacharacters in user input (| is the delimiter, & and \ are special)
    _sed_escape() { sed 's:[&\\|]:\\&:g'; }
    local project_name_safe core_cmd_safe
    project_name_safe=$(printf '%s' "$project_name" | _sed_escape)
    core_cmd_safe=$(printf '%s' "$core_cmd" | _sed_escape)

    sed -e "s|\\\$PROJECT_NAME|$project_name_safe|g" \
        -e "s|\\\$CORE_CMD|$core_cmd_safe|g" \
        "$AISHORE_ROOT/templates/config.yaml.tmpl" > "$CONFIG_FILE"
    log_success "Wrote .aishore/config.yaml"

    # Create backlogs (never overwrite existing)
    if [[ ! -f "$BACKLOG_DIR/backlog.json" ]]; then
        cp "$AISHORE_ROOT/templates/backlog.json" "$BACKLOG_DIR/backlog.json"
        log_success "Created backlog/backlog.json"
    else
        log_info "Kept existing backlog/backlog.json ($(count_items "$BACKLOG_DIR/backlog.json") items)"
    fi

    if [[ ! -f "$BACKLOG_DIR/bugs.json" ]]; then
        cp "$AISHORE_ROOT/templates/bugs.json" "$BACKLOG_DIR/bugs.json"
        log_success "Created backlog/bugs.json"
    else
        log_info "Kept existing backlog/bugs.json"
    fi

    if [[ ! -f "$BACKLOG_DIR/sprint.json" ]]; then
        echo '{"sprintId": null, "status": "idle", "item": null}' > "$BACKLOG_DIR/sprint.json"
        log_success "Created backlog/sprint.json"
    else
        log_info "Kept existing backlog/sprint.json"
    fi

    if [[ ! -f "$BACKLOG_DIR/DEFINITIONS.md" ]]; then
        cp "$AISHORE_ROOT/templates/DEFINITIONS.md" "$BACKLOG_DIR/DEFINITIONS.md"
        log_success "Created backlog/DEFINITIONS.md"
    else
        log_info "Kept existing backlog/DEFINITIONS.md"
    fi

    touch "$ARCHIVE_DIR/sprints.jsonl"

    # Scaffold project docs if missing
    local docs_dir="$PROJECT_ROOT/docs"

    # Product doc — use prd_found from detect phase (skip README for scaffolding)
    local prd_base=""
    [[ -n "$prd_found" ]] && prd_base=$(basename "$prd_found")
    if [[ -n "$prd_found" && "$prd_base" != "README.md" ]]; then
        product_path="$prd_found"
        log_info "Found existing product doc: $prd_found"
    else
        mkdir -p "$docs_dir"
        sed "s|\\\$PROJECT_NAME|$project_name_safe|g" \
            "$AISHORE_ROOT/templates/PRODUCT.md.tmpl" > "$docs_dir/PRODUCT.md"
        log_success "Created docs/PRODUCT.md (fill in to help agents understand your product)"
        product_path="$docs_dir/PRODUCT.md"
    fi

    # Architecture doc — use arch_found from detect phase
    if [[ -n "$arch_found" ]]; then
        arch_path="$arch_found"
        log_info "Found existing architecture doc: $arch_found"
    else
        mkdir -p "$docs_dir"
        sed "s|\\\$PROJECT_NAME|$project_name_safe|g" \
            "$AISHORE_ROOT/templates/ARCHITECTURE.md.tmpl" > "$docs_dir/ARCHITECTURE.md"
        log_success "Created docs/ARCHITECTURE.md (fill in to guide agent implementation)"
        arch_path="$docs_dir/ARCHITECTURE.md"
    fi

    # Update .gitignore
    local gitignore="$PROJECT_ROOT/.gitignore"
    local entries_file="$AISHORE_ROOT/gitignore-entries.txt"
    local gitignore_content=""
    if [[ -f "$entries_file" ]]; then
        gitignore_content=$(grep -v '^#' "$entries_file" | grep -v '^$' || true)
    else
        gitignore_content=".aishore/data/logs/
.aishore/data/status/result.json
.aishore/data/status/.item_source
.aishore/data/status/.aishore.lock"
    fi
    if [[ -f "$gitignore" ]]; then
        if ! grep -q ".aishore/data/logs/" "$gitignore" 2>/dev/null; then
            printf '\n# aishore runtime files\n%s\n' "$gitignore_content" >> "$gitignore"
            log_success "Updated .gitignore"
        else
            log_info ".gitignore already configured"
        fi
    else
        printf '# aishore runtime files\n%s\n' "$gitignore_content" > "$gitignore"
        log_success "Created .gitignore"
    fi

    # Add aishore section to CLAUDE.md
    local snippet
    snippet=$(get_claudemd_snippet)
    if [[ -n "$claude_md" ]]; then
        if grep -q "## Sprint Orchestration (aishore)" "$claude_md" 2>/dev/null; then
            log_info "CLAUDE.md already contains aishore section"
        else
            printf '%s\n' "$snippet" >> "$claude_md"
            log_success "Appended aishore section to CLAUDE.md"
        fi
    else
        claude_md="$PROJECT_ROOT/CLAUDE.md"
        printf '# %s\n%s\n' "$project_name" "$snippet" > "$claude_md"
        log_success "Created CLAUDE.md with aishore section"
    fi

    echo ""
}

_init_demo() {
    local demo_dir="$PROJECT_ROOT/aishore-demo"

    log_header "aishore demo — experience the full sprint lifecycle"
    echo ""
    echo "  This creates a tiny demo project and runs sprints on it so you"
    echo "  can see aishore pick items, develop them, validate, and merge."
    echo ""

    # ── Guard: don't overwrite existing demo ──
    if [[ -d "$demo_dir" ]]; then
        log_warning "Demo directory already exists: $demo_dir"
        echo "  Remove it first if you want to start fresh:"
        echo "    rm -rf $demo_dir"
        return 1
    fi

    # ── 1. Create demo project ──
    log_subheader "Step 1/3 — Scaffolding demo project"

    mkdir -p "$demo_dir"
    (
        cd "$demo_dir" || exit 1
        git init -q

        # Create the starter script — just a shebang so the AI has something to build on
        cat > txtstat <<'SCRIPT'
#!/usr/bin/env bash
# txtstat — text statistics CLI (demo project for aishore)
set -euo pipefail

echo "txtstat: not yet implemented — run aishore to build this!"
SCRIPT
        chmod +x txtstat

        # Sample input file
        cat > sample.txt <<'SAMPLE'
The quick brown fox jumps over the lazy dog.
Pack my box with five dozen liquor jugs.
How vexingly quick daft zebras jump.
SAMPLE

        # PRODUCT.md
        mkdir -p docs
        cat > docs/PRODUCT.md <<'PRODUCT'
# txtstat — Text Statistics CLI

## Vision
txtstat is a tiny command-line tool that analyzes text and reports statistics.
It reads from files or stdin and prints word count, line count, and character count.

## Core
A user runs `./txtstat sample.txt` and sees accurate word, line, and character counts printed to stdout in a clear format.

## Features
- Word count
- Line count
- Character count
- Read from file arguments or stdin
- Show --help usage information
PRODUCT

        # CLAUDE.md
        cat > CLAUDE.md <<'CLAUDEMD'
# txtstat

A tiny text statistics CLI tool. Pure Bash, no dependencies.

## Code Style
- `set -euo pipefail` at the start
- Quote all variables
- `[[ ]]` for conditionals
CLAUDEMD

        # .gitignore
        cat > .gitignore <<'GITIGNORE'
.aishore/data/logs/
.aishore/data/status/result.json
.aishore/data/status/.aishore.lock
GITIGNORE

        # Copy the aishore tool
        cp -r "$AISHORE_ROOT" .aishore

        # Create config
        cat > .aishore/config.yaml <<'CONFIG'
# aishore configuration — demo project
project:
  name: "txtstat"

core:
  command: "./txtstat sample.txt 2>&1 | grep -qE 'words|lines|characters'"
  timeout: 30
CONFIG

        # Create backlog directory
        mkdir -p backlog/archive
        touch backlog/archive/sprints.jsonl
        touch backlog/archive/regression.jsonl

        # Sprint (idle)
        echo '{"sprintId": null, "status": "idle", "item": null}' > backlog/sprint.json

        # Bugs (empty)
        echo '{"description": "Bug backlog", "items": []}' > backlog/bugs.json

        # DEFINITIONS.md
        if [[ -f "$AISHORE_ROOT/templates/DEFINITIONS.md" ]]; then
            cp "$AISHORE_ROOT/templates/DEFINITIONS.md" backlog/DEFINITIONS.md
        fi

        # ── Pre-groomed backlog with 5 sprint-ready items ──
        cat > backlog/backlog.json <<'BACKLOG'
{
  "description": "Feature backlog",
  "items": [
    {
      "id": "FEAT-001",
      "title": "Add --help flag with usage information",
      "intent": "A user who runs ./txtstat --help must see clear usage instructions showing available options and what the tool does, so they know how to use it.",
      "steps": [
        "Parse --help and -h flags in txtstat",
        "Print usage text showing: usage line, description, and available options",
        "Exit 0 after printing help"
      ],
      "acceptanceCriteria": [
        {
          "text": "--help flag prints usage information",
          "verify": "./txtstat --help 2>&1 | grep -qi 'usage'"
        }
      ],
      "priority": "must",
      "size": "xs",
      "status": "todo",
      "track": "core",
      "readyForSprint": true
    },
    {
      "id": "FEAT-002",
      "title": "Count lines in input",
      "intent": "When a user passes a file or pipes stdin, txtstat must count and display the number of lines so they can quickly see how long the text is.",
      "steps": [
        "Read input from file argument or stdin",
        "Count newlines to determine line count",
        "Print the line count with a 'lines' label"
      ],
      "acceptanceCriteria": [
        {
          "text": "Line count is printed for file input",
          "verify": "./txtstat sample.txt 2>&1 | grep -qE '3.*lines|lines.*3'"
        }
      ],
      "priority": "must",
      "size": "xs",
      "status": "todo",
      "track": "core",
      "readyForSprint": true
    },
    {
      "id": "FEAT-003",
      "title": "Count words in input",
      "intent": "When a user passes a file or pipes stdin, txtstat must count and display the number of words so they can gauge the size of the text.",
      "steps": [
        "Read input from file argument or stdin",
        "Count words using whitespace splitting",
        "Print the word count with a 'words' label"
      ],
      "acceptanceCriteria": [
        {
          "text": "Word count is printed for file input",
          "verify": "./txtstat sample.txt 2>&1 | grep -qE '[0-9]+.*words|words.*[0-9]+'"
        }
      ],
      "priority": "must",
      "size": "xs",
      "status": "todo",
      "track": "core",
      "readyForSprint": true
    },
    {
      "id": "FEAT-004",
      "title": "Count characters in input",
      "intent": "When a user passes a file or pipes stdin, txtstat must count and display the number of characters so they can see the exact text size.",
      "steps": [
        "Read input from file argument or stdin",
        "Count total characters including whitespace and newlines",
        "Print the character count with a 'characters' label"
      ],
      "acceptanceCriteria": [
        {
          "text": "Character count is printed for file input",
          "verify": "./txtstat sample.txt 2>&1 | grep -qE '[0-9]+.*characters|characters.*[0-9]+|[0-9]+.*chars|chars.*[0-9]+'"
        }
      ],
      "priority": "should",
      "size": "xs",
      "status": "todo",
      "track": "feature",
      "readyForSprint": true
    },
    {
      "id": "FEAT-005",
      "title": "Support reading from stdin when no file given",
      "intent": "A user must be able to pipe text into txtstat (e.g., echo hello | ./txtstat) and get the same statistics output as file input, so the tool works in shell pipelines.",
      "steps": [
        "Detect when no file argument is given",
        "Read from stdin instead of a file",
        "Produce the same output format as file mode"
      ],
      "acceptanceCriteria": [
        {
          "text": "stdin input produces statistics output",
          "verify": "echo 'hello world' | ./txtstat 2>&1 | grep -qE 'words|lines|characters'"
        }
      ],
      "priority": "should",
      "size": "xs",
      "status": "todo",
      "track": "feature",
      "readyForSprint": true
    }
  ]
}
BACKLOG

        # Initial commit
        git add -A
        git commit -q -m "initial: txtstat demo project scaffolded by aishore"
    ) || {
        log_error "Failed to scaffold demo project"
        return 1
    }

    log_success "Created demo project at $demo_dir"
    log_success "5 sprint-ready items in backlog"
    echo ""

    # ── 2. Run sprints ──
    log_subheader "Step 2/3 — Running demo sprints"
    echo ""
    echo "  aishore will now pick items and develop them autonomously."
    echo "  Watch the full lifecycle: pick → branch → develop → validate → merge"
    echo ""

    local demo_aishore="$demo_dir/.aishore/aishore"
    local sprint_count=0

    # Run up to 2 sprints
    for _i in 1 2; do
        if "$demo_aishore" run 2>&1; then
            sprint_count=$((_i))
        else
            log_warning "Sprint $_i did not complete — that's OK for a demo"
            break
        fi
    done

    echo ""

    # ── 3. Summary ──
    log_subheader "Step 3/3 — What just happened"
    echo ""

    if [[ "$sprint_count" -gt 0 ]]; then
        log_success "Completed $sprint_count demo sprint(s)"
    else
        log_info "No sprints completed (the demo project is still set up for you)"
    fi

    echo ""
    echo "  aishore picked items from the backlog, created feature branches,"
    echo "  had an AI agent implement each one, validated the results against"
    echo "  acceptance criteria, and merged the changes."
    echo ""
    echo "  Explore the demo:"
    echo "    cd $demo_dir"
    echo "    git log --oneline          # see the commits aishore made"
    echo "    ./txtstat sample.txt       # try the tool it built"
    echo "    .aishore/aishore status    # see backlog progress"
    echo "    .aishore/aishore run       # run more sprints"
    echo ""
    echo -e "  ${CYAN}Ready to use aishore on your own project?${NC}"
    echo "    cd /path/to/your/project"
    echo "    .aishore/aishore init      # or copy .aishore/ from the demo"
    echo ""
}

cmd_init() {
    local auto_yes=false demo_mode=false

    parse_opts "bool:auto_yes:-y|--yes" "bool:demo_mode:--demo" -- "$@" || return 1

    if [[ "$demo_mode" == "true" ]]; then
        _init_demo
        return $?
    fi

    log_header "aishore setup wizard"
    echo ""
    if [[ "$auto_yes" == "true" ]]; then
        echo "  Running non-interactively — accepting all detected defaults."
    else
        echo "  This will walk you through setting up aishore for your project."
        echo "  Press Enter to accept defaults shown in [brackets]."
    fi
    echo ""

    # shellcheck disable=SC2034  # documented as outer-scope local for future use
    local reinit=false
    if [[ -f "$BACKLOG_DIR/backlog.json" ]]; then
        log_warning "aishore already initialized (backlog.json exists)"
        if [[ "$auto_yes" == "true" ]]; then
            # shellcheck disable=SC2034
            reinit=true
        else
            read -r -p "  Reinitialize? This preserves existing backlogs. [y/N] " c
            [[ $c != [yY] ]] && return 0
            # shellcheck disable=SC2034
            reinit=true
        fi
        echo ""
    fi

    # Shared state across init steps
    local project_name="" core_cmd="" prd_found="" claude_md=""
    local arch_found="" product_path="" arch_path=""

    _init_check_prereqs
    _init_detect_project "$auto_yes"
    _init_scaffold_files

    # ── Summary & next steps ──
    log_subheader "Step 6/6 — Ready"
    echo ""
    log_success "aishore initialized for $project_name"
    echo ""

    echo "  Project:       $project_name"
    echo "  Core command:  ${core_cmd:-<none>}"
    echo "  CLAUDE.md:     ${claude_md:-<not found>}"
    echo "  PRODUCT.md:    ${product_path:-<not found>}"
    echo "  ARCHITECTURE:  ${arch_path:-<not found>}"
    echo "  Definitions:   $BACKLOG_DIR/DEFINITIONS.md"
    echo ""

    echo -e "${CYAN}Next steps:${NC}"
    local step=1
    local prd_base=""
    [[ -n "$prd_found" ]] && prd_base=$(basename "$prd_found")

    if [[ -z "$prd_found" || "$prd_base" == "README.md" ]]; then
        echo "  $step. Fill in docs/PRODUCT.md with your product vision"
        step=$((step + 1))
    fi
    if [[ -z "$arch_found" ]]; then
        echo "  $step. Fill in docs/ARCHITECTURE.md with your tech stack and conventions"
        step=$((step + 1))
    fi

    local item_count=0
    if command -v jq &>/dev/null && [[ -f "$BACKLOG_DIR/backlog.json" ]]; then
        item_count=$(count_items "$BACKLOG_DIR/backlog.json")
    fi

    if [[ "$item_count" -eq 0 ]]; then
        echo "  $step. Add features: .aishore/aishore backlog add"
        step=$((step + 1))
        echo "  $step. Groom items for sprint readiness: .aishore/aishore groom"
        step=$((step + 1))
    fi

    echo "  $step. Run your first sprint: .aishore/aishore run"
    echo ""
}
