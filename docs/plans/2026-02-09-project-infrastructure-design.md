# Project Infrastructure Design

*How parallel agents build Unanim from VISION.md to working framework across hundreds of sessions.*

Validated: 2026-02-09

---

## 1. Task System

**GitHub Issues + Milestones** as the single source of truth for project state.

- **Milestones** = Phases (7 total)
- **Issues** = Tasks (scoped to ~1 agent session, ~1 PR)
- **2-level hierarchy only** — no epics, no sub-tasks. Agents need one `gh` command to find work.

### Finding work

```
gh issue list --milestone "Phase 1: Foundation" --label "ready" --assignee ""
```

Returns unclaimed, unblocked tasks. Agent picks one, claims it, works it.

### Issue structure

Every issue follows this template:

- **Spec reference**: Which VISION.md sections this implements (e.g., "Section 3: `secret(name)`, Section 4.6")
- **Acceptance criteria**: Concrete, testable outcomes
- **Validation**: How to prove it works against real infrastructure (per VISION.md Section 13)
- **Dependencies**: `blocked by #X` if applicable
- **Not in scope**: Explicit boundaries — what this task deliberately omits or defers

### Labels

| Label | Meaning |
|---|---|
| `ready` | Unblocked, can be picked up |
| `in-progress` | An agent has claimed it |
| `blocked` | Waiting on another issue |
| `spec-change` | Proposes a VISION.md modification |
| `scaffold-cleanup` | Tracks temporary code to be removed later |

When an agent finishes blocking work, it removes `blocked` and adds `ready` to downstream issues.

---

## 2. Agent Startup Protocol

Every Claude Code session begins by reading `CLAUDE.md` in the repo root. Then:

1. `gh issue list --milestone "<current phase>" --label "ready" --assignee ""`
2. Pick an issue, read it fully (especially "Not in scope")
3. Assign yourself: `gh issue edit <N> --add-assignee @me --remove-label ready --add-label in-progress`
4. Create a worktree: `git worktree add ../unanim-<N> -b issue-<N>`
5. Work in that worktree
6. PR back to main: `gh pr create` referencing `Closes #<N>`

Cold start to productive: one `gh` command.

---

## 3. PR Process and Spec Compliance

### PR body requirements

- `Closes #<N>` (links to the issue)
- **What this does**: 2-3 sentences
- **Spec compliance**: For each VISION.md section referenced in the issue, confirm how the implementation matches. Any deviation must reference an approved spec-change issue.
- **Validation performed**: What was tested against real Cloudflare/browser — evidence, not claims.

### Merge rule

PRs merge to `main`. No direct commits to `main`.

---

## 4. Spec Evolution

VISION.md is versioned with a changelog (following the existing 0.0.0 -> 0.1.0 pattern).

### When the spec needs to change

An agent discovers something won't work as written. The agent:

1. **Stops** building on the assumption
2. Opens a GitHub Issue labeled `spec-change` with:
   - **Problem**: What doesn't work and why (with evidence)
   - **Affected spec sections**: Which parts of VISION.md are impacted
   - **Proposed change**: What the spec should say instead
   - **Downstream impact**: What other issues/work this affects
3. Continues working on unaffected tasks (if any), or waits

The project maintainer reviews, approves/modifies, and VISION.md gets a versioned update (e.g., 0.1.0 -> 0.1.1) with a changelog entry. Only then do agents build on the new assumption.

---

## 5. Scaffold Management

Every phase produces temporary code that isn't final. Left untracked, this becomes landmines for future agents.

### Convention

When an agent creates scaffold code, it adds a comment at the top of the file:

```
# SCAFFOLD(phase-1, #12): Raw HTML test client
# Replaced by: Islands DSL in Phase 6
# Cleanup issue: #25
```

### Tracking

For every scaffold created, the agent also creates a GitHub Issue labeled `scaffold-cleanup` with:
- What the scaffold is
- Why it exists
- What replaces it (and in which phase)
- `blocked by #X` (the issue that builds the replacement)

When the replacement is built, the cleanup issue becomes unblocked and an agent picks it up.

### Standing rule

If you encounter SCAFFOLD-marked code, do not modify it, extend it, or build on it beyond its stated purpose. It will be replaced.

---

## 6. Git Strategy

**Worktrees per task.** Each agent works in its own worktree on a feature branch. PRs merge to main. Total isolation — no stepping on each other.

```
unanim/          # main worktree (main branch)
unanim-12/       # worktree for issue #12 (branch: issue-12)
unanim-13/       # worktree for issue #13 (branch: issue-13)
```

---

## 7. Phase Breakdown

### Phase 1: Foundation — "Does the pipeline work?"

Nim macros detect `proxyFetch` + `secret()` and generate a Cloudflare Worker. Deploy to real Cloudflare, verify credential injection and round-trip.

- **Exit condition**: A Nim file compiles to a working Worker + client. Deployed, tested, real API call succeeds.
- **Scaffold produced**: Raw HTML client (no islands), hardcoded Worker URL, no state/events
- **Parallelism**: 2 agents max

### Phase 2: State — "Can we store and verify events?"

Event format, hash chain, append-only log, IndexedDB on client, SQLite in DO. Basic `migration()` + compile-time schema validation.

- **Exit condition**: Events survive browser refresh. Events replicated to DO. Hash chain verified. Merkle tree divergence detection works.
- **Scaffold produced**: Manual event creation (no UI), simplified event format, DO with state but no sync
- **Parallelism**: 2-3 agents

### Phase 3: Sync — "Can client and server exchange reliably?"

Event piggybacking on proxyFetch, lease mechanism, offline -> reconnect -> merge, fencing tokens.

- **Exit condition**: Airplane mode test passes. Server processes webhook while offline. Client reconnects, receives server events, state matches.
- **Scaffold produced**: Lease detection without WebSocket auto-response (added later), heartbeat sync without secondary channels
- **Parallelism**: 2 agents

### Phase 4: Primitives — "Do the building blocks work?"

`guard()`, `webhook()`, `cron()`, `shared()`, `auth()`, compile-time delegation, `safe{}` blocks, portability check. Schema evolution (three-tier strategy).

- **Exit condition**: OrgShoots example compiles and runs. All 7 stress tests from VISION.md Section 10 pass.
- **Parallelism**: 3-4 agents (primitives are largely independent)

### Phase 5: Battle Testing — "Do real apps actually work?"

Port real existing applications to Unanim. Discover missing primitives, DX gaps, performance issues.

- **OrgShoots full implementation** (Appendix D, running for real)
- **Port 1**: Small real app — LLM ports it unsupervised, measure time/correctness/speed/cost
- **Port 2**: Larger real app — surfaces missing primitives and composition issues
- **Success criteria**: LLM completes port autonomously in ~60min. Result is correct, faster (client-first), cheaper (Cloudflare), inspectable.
- **Output**: Backlog of issues feeding Phase 6

### Phase 6: Developer Experience — "Is it good?"

Informed by Phase 5 findings. LLM-optimized compiler errors, migration/ejection tooling (`unanim export`, `unanim detach`, `unanim inspect`), islands UI DSL, CLI, reactive queries.

- **Exit condition**: `npm create unanim` -> deployed app in under 5 minutes. LLM generates a correct app from natural language on first try.
- **Parallelism**: 3-4 agents

### Phase 7: Launch — "Ship it"

README, docs, example apps, CI/CD, npm package.

- **Exit condition**: Public repo, first GitHub star from a stranger.

### Cross-cutting constraints

- **Ejectability by design**: All generated artifacts are independently runnable, from Phase 1 onward. This is not a feature added later — it's a constraint on how we generate code.
- **Real infrastructure validation**: Every implementation step validated against real Cloudflare (`wrangler`) and real browser, per VISION.md Section 13.

---

## 8. Phase 1 Tasks

```
#1  Repo scaffolding + CLAUDE.md
 |
 +--> #2  secret() macro detection     (parallel)    #3  proxyFetch macro detection
 |         |                                                |
 +--> #4  Cloudflare Worker codegen    (parallel)    #5  Client JS codegen
 |                        |                    |
 +--> #6  End-to-end validation (real Cloudflare + real browser)
```

See GitHub Issues for full details on each task.
