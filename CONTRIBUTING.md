# Contributing to Markdown

This document owns the operational model for how Markdown gets built. `PRODUCT.md` summarizes the sustainability bet; the full model, the mechanics, and the metrics live here.

---

## 1. The Sustainability Model in Full

### The bet

Every standalone free markdown editor before us has died the same way: one human ran out of energy. MarkText, Remarkable, Haroopad, Abricotine — 100% mortality across the category. The pattern is volunteer maintainer burnout.

Markdown bets that AI coding agents break this pattern. Not because "agents write code," but because *agent-legibility* makes distributed contribution viable at a scale a single maintainer could never absorb.

The mechanics:

- The project publishes clear intent documents (`PRODUCT.md`, `ARCHITECTURE.md`), well-scoped issues with machine-verifiable acceptance criteria, real test suites, and architectural documents that fit in a context window.
- Contributors bring their own AI coding agent subscriptions (Claude Code, Cursor, or equivalent) and run them against open issues.
- The project provides architecture, intent, and review. Contributors provide compute.
- The "labor" is distributed across subscribers who are already paying for the tooling for their own reasons.

No donations (Wikipedia model). No corporate sponsorship (Linux Foundation model). No open-core bait-and-switch (Elastic model). No maintainer martyrdom (the default).

### Why contributors will actually show up

The load-bearing question is not "can agents write code against this project?" — that is a solved problem. The load-bearing question is **why would a developer spend their own agent subscription on this project rather than their own side project, their own day job, or nothing at all?**

The answer is a claim about subscription economics, not about altruism:

1. **Modern AI coding agent subscriptions are priced with usage headroom.** A Claude Code, Cursor, or equivalent plan is a fixed monthly cost that covers far more usage than most individual developers actually consume on their own projects. The marginal hour of agent time on any given day sits idle — not because the developer doesn't want to build things, but because thinking up, scoping, specifying, and shepherding a PR on their own codebase is cognitively expensive. The bottleneck is *human effort per unit of agent output*, not agent capacity.
2. **Markdown externalizes the expensive part.** The project provides the hard cognitive overhead that would otherwise eat a contributor's evening: a well-scoped issue, machine-verifiable acceptance criteria, explicit non-goals, a baseline the work is measured against, a reviewer who will give a real answer. The contributor brings the agent and twenty minutes.
3. **This trade is cheaper than any alternative.** Contributing a feature to a daily-driver tool costs a contributor less cognitive load and less calendar time than spinning up their own equivalent from scratch, fighting their own scope creep, and never shipping. The substitute is not "another OSS project to contribute to" — the substitute is "the thing I was going to build alone but didn't." We are competing against the inertia of the blank page, not against other projects.
4. **A daily-driver tool has tight enough feedback that contribution is satisfying.** Contributors use the product. When they ship a feature, they use it the next day. That feedback loop is the retention mechanism — not recognition, not a line on a resume, not a t-shirt.

This is the thesis the project is betting on. It is plausible and it is testable. If the first ten issues that carry `readyForSprint: true` sit unclaimed for months, the thesis is wrong, and the reduced-ambition fallback (D-SUST-2) is what ships. The operational metrics in §5 are the test.

### The cost structure

Most lines are zero, but naming them matters:

- **Architect / reviewer time**: valuable, finite, irreplaceable. This is the binding constraint on the whole model.
- **Contributors' agent subscription costs**: real but externalized. The project does not pay for them.
- **CI / hosting**: small, covered by free tiers (GitHub Actions, GitHub Pages) for the foreseeable future.
- **Agent-legibility maintenance**: ongoing, non-trivial, and easy to underinvest in. This is the most-likely-to-erode leg of the stool.

### Agent-legibility as infrastructure

The pattern that makes distributed agent contribution work is not "agents write code" — it's the project structure that makes agent contribution viable. That structure is:

- A product doc with decision IDs that agents can reference and cross-check
- An architecture doc that also has decision IDs and explicitly cites the product decisions each architectural choice implements
- The walking-skeleton discipline (every architectural claim has an end-to-end executable proof)
- Acceptance criteria that exercise real running code, not `grep`-able code existence
- Explicit non-goals so agents don't scope-creep
- Baseline metrics with regression gates so performance claims are enforced, not aspirational
- Architecture documents that fit in an agent's context window

Maintaining agent-legibility is ongoing work and is treated as such. It is not meta-work. It is the infrastructure that enables all other work.

### If the bet fails

If distributed agent contribution produces a 3x multiplier rather than 10x — still transformative, but not miraculous — the roadmap contracts to the reduced-ambition scope defined in `PRODUCT.md` D-SUST-2: native iOS + macOS, with the web build for cross-platform reach, no Android, no Mermaid/math/PDF, and the core loop (open, read, edit, format, doctor, save) done to craft quality.

That is still a product no one else ships. Failing honestly means shipping a smaller thing that's genuinely good, not shipping a bigger thing that's mediocre and unmaintained.

---

## 2. How to contribute

### Pick an issue

All work flows through the backlog. Issues that are ready for contribution are marked `readyForSprint: true` and carry:

- A **commander's intent** statement — what the change is trying to achieve, in language an agent can resolve ambiguity against without a human
- **Acceptance criteria** concrete enough for an agent to verify and for CI to enforce
- A **context-loading instruction** — which documents to read before starting, which code paths are in scope, which are out of scope
- A **decision-ID reference** — the product decision (`D-*`) and architecture decision (`A-*`) that the change implements

If an issue is missing any of these, it is not ready. Don't try to complete it; flag it for grooming instead.

### Run an agent against it

Bring your own agent subscription. We do not prescribe which agent. We do prescribe what its output must look like:

- The PR description states the issue, the commander's intent, and the acceptance criteria
- Every acceptance criterion has a verifiable command in the PR description, with its output
- No mocks. No stubs. No "will wire up later."
- Real tests exercise the running system end-to-end
- The PR runs the baseline measurement and reports the delta against the committed `docs/baseline.json`. Regressions >10% are named and either fixed or explicitly accepted.

### Submit the PR

PRs go through the same review process whether they were written by a human, an agent, or a human-directed agent. The reviewer does not care how the code was produced; they care that the intent is satisfied, the acceptance criteria pass, and the regression budget is respected.

### Review feedback

Review feedback is scoped and specific. A reviewer asking for changes is not a comment on the contributor's competence — it's the system working. Iterate, resubmit, merge. If you disagree with review feedback, the product and architecture docs are the arbiters: cite the relevant decision ID.

---

## 3. Keeping the project agent-legible

Agent-legibility is a maintained property, tracked like code quality.

**When adding a feature**:
- Does a `D-*` decision in `PRODUCT.md` justify it? If not, the decision has to be added first (and approved) before the feature can ship.
- Does the implementation approach correspond to an `A-*` decision in `ARCHITECTURE.md`? If not, add the decision or revise an existing one.
- Are the acceptance criteria verifiable by something other than a human reading them?

**When fixing a bug**:
- Is there a test that would have caught it? If not, add one as part of the fix.
- Does the fix change any baseline metric? If so, note the delta.

**When updating docs**:
- PRODUCT.md never names a framework, language, library, or engineering budget. If it does, the update is wrong.
- ARCHITECTURE.md never invents product requirements. Every architectural decision cites the product decision it implements.
- CONTRIBUTING.md (this document) owns the operational model, not the product or the architecture.

---

## 4. Review loop mechanics

Review is the binding constraint on the whole model. If review capacity is exhausted, the project stalls regardless of how many PRs are produced. The review loop is designed to keep human reviewer time rare, focused, and high-leverage.

### Gates before human review

A PR reaches a human reviewer only after:

1. All CI gates pass, including the baseline regression gate
2. Automated lint, format, and architecture-conformance checks pass
3. Agent-assisted first-pass review checks: does the PR description match the issue? Are the acceptance criteria genuinely exercised? Is the scope limited to what the issue asks for, or is there scope creep?

If any of these fail, the PR is returned to the contributor with specific remediation notes. No human reviewer time is spent on a PR that fails automated gates.

### What the human reviewer does

- Architectural judgment: is this the right approach, given the rest of the system?
- Intent alignment: does the PR satisfy the *intent* of the issue, or just the literal acceptance criteria?
- Risk: what could this break?
- Non-obvious correctness: things tests can't easily catch

Human reviewers do not re-run CI checks, re-verify acceptance criteria, or check lint. Those are delegated to the gates.

### Review throughput target

The system's throughput target is that `issue marked ready → PR merged` takes days, not weeks. If review queue depth grows monotonically over multiple weeks, the model is failing and intervention is required — whether that's more reviewers, stricter automated gates, or pausing new issue creation until the queue drains.

---

## 5. Operational metrics

These are tracked from first external contribution. They are distinct from the product success metrics in `PRODUCT.md §10`; those measure whether the product is winning. These measure whether the sustainability bet is working.

**Contributor pipeline**:
- Number of distinct contributors (human or agent-assisted) who have merged a PR
- Ratio of PRs that pass first-pass automated review vs. require human intervention before review

**Throughput**:
- Mean time from "issue marked ready" to "PR merged" — the throughput of the full loop
- Review queue depth over time — a leading indicator of reviewer burnout; if this grows monotonically, the model is failing

**Agent-legibility health**:
- **Agent-readiness rate**: percentage of open issues that have all of: a decision ID reference, at least one acceptance criterion with a verifiable command, and a context-loading instruction. Proxy for agent-legibility.
- **Agent first-attempt CI pass rate**: percentage of agent-submitted PRs that pass CI on first submission without human guidance during the attempt. Proxy for whether the codebase and issue descriptions are actually agent-legible in practice, not just on paper.

**Resilience**:
- **Architect-absence resilience**: issue-to-merge throughput does not degrade more than 50% during a 7-day architect absence. Measured when opportunities arise naturally, not engineered as a test.

If the agent-readiness rate drops below 80%, work pauses on new features until the backlog is groomed back up. Agent-legibility is infrastructure; infrastructure gets maintained.

---

## 6. Honest accounting

### Known risks

These mirror the risks listed in `PRODUCT.md §9`, stated here in operational terms:

- **The review bottleneck may be harder than the writing bottleneck.** If the human at the helm runs out of review energy, Markdown joins the MarkText graveyard — not because no one wrote the code, but because no one could review it fast enough. The metrics in §5 are early warning signs.
- **Vendor dependency.** Contributors depend on external AI providers we don't control. Price hikes, quality degradation, rate limit tightening, or a vendor pivoting away from coding agents can shrink the contributor pool overnight. We accept this as a known dependency rather than pretending it doesn't exist.
- **Privilege selection.** Agent subscriptions cost real money. We are honest that "community contributions" means "community members who can afford agent subscriptions." We do not subsidize this, and we do not pretend otherwise.

### What's not in scope for this document

- Governance decisions (who gets merge rights, how disputes are resolved, how direction changes get approved) — these belong in a separate GOVERNANCE.md when the project needs it.
- Code of conduct — standard Contributor Covenant.
- Security reporting — standard `SECURITY.md` (vulnerability disclosure).

---

## Appendix: Related documents

- `PRODUCT.md` — what the product is. All product decisions (`D-*`) live there.
- `ARCHITECTURE.md` — how the product is built. All architecture decisions (`A-*`) live there.
- `docs/baseline.json` — the committed performance baseline that every PR is measured against.
