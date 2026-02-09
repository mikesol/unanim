# Unanim

Nim-based compile-time framework that eliminates the backend by generating client applications, server-side proxy configurations, and state sync protocols from a single source.

See `VISION.md` for full architecture. See `docs/plans/` for design documents.

## How to find work

```
gh issue list --milestone "<current phase>" --label "ready" --assignee ""
```

Pick an issue. Read it fully — especially **"Not in scope"**. Then:

1. Assign yourself: `gh issue edit <N> --add-assignee @me --remove-label ready --add-label in-progress`
2. Create a worktree: `git worktree add ../unanim-<N> -b issue-<N>`
3. Work in that worktree
4. PR back to main: `gh pr create` referencing `Closes #<N>`

## How to submit work

PR body must include:

- `Closes #<N>`
- **What this does**: 2-3 sentences
- **Spec compliance**: For each VISION.md section referenced in the issue, confirm how the implementation matches. Any deviation must reference an approved `spec-change` issue.
- **Validation performed**: What you tested against real Cloudflare/browser. Evidence, not claims.

## Standing rules

- **Ejectability by design**: Generated artifacts must be independently runnable without the framework. Always.
- **SCAFFOLD code**: If you encounter code marked `SCAFFOLD`, don't modify/extend/build on it beyond its stated purpose. When you create scaffold code, add a `SCAFFOLD(phase, #issue)` comment and create a `scaffold-cleanup` issue.
- **Spec seems wrong?** STOP. Open a GitHub Issue labeled `spec-change` with: the problem (with evidence), affected VISION.md sections, proposed change, downstream impact. Don't build on a wrong assumption.
- **Real infrastructure only**: Validate against real Cloudflare (`wrangler`) and real browser. Not mocks.
- **Use .venv** when running poetry, pytest, python, or formatters.

## Current phase

Phase 1: Foundation (Milestone: "Phase 1: Foundation")
