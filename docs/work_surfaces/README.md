# Work Surfaces — feature tracker

In-repo working docs for the `feat/work_surfaces` branch. This directory is the authoritative workspace while the feature is under active development. When (and only when) the feature merges to `6.6.3_vr_main`, the `design-*.md` files here are synced forward to the external `kwin-vr.wiki` repo. The `impl-*.md` files stay in the code repo as implementation history.

## Merge rule

**This branch does not merge to `6.6.3_vr_main` without explicit user confirmation.** Push every commit to `origin/feat/work_surfaces` for backup, but never invoke `git merge` to main on your own. If you're a future agent picking this up with no context, treat that as a hard rule.

## Conventions

- **Thematic filenames.** `design-drag.md`, `impl-registry.md` — no numeric prefixes except for commit ordering in `impl-*` where sequence matters.
- **Two doc classes:**
  - `design-*.md` — intended behavior. Source of truth for "what are we building". These are the drafts that will become external wiki pages on merge.
  - `impl-*.md` — what has actually been built. Updated as commits land. Cross-references design docs.
- **Per-chunk template for `impl-*`:**
  ```
  # <chunk name>

  **Status:** done | wip | blocked
  **Commits:** <SHA short> — <subject>
  **Design refs:** [design-foo](design-foo.md)

  ## Goal
  ...
  ## What shipped
  ...
  ## Files touched
  ...
  ## Code refs
  file.qml:NN — <function> — <what it does>
  ## Open issues / follow-ups
  ...
  ```
- **Commit messages use `work_surfaces: <chunk>: <detail>`** so `git log --grep=work_surfaces` pulls the whole feature history.

## Progress index

| Chunk | Status | Commits | Impl doc | Design ref |
|-------|--------|---------|----------|------------|
| Scaffold types | done | `8b11b835a3` | [impl-scaffold](impl-scaffold.md) | [design-data-model](design-data-model.md) |
| Registry + snap join | wip — uncommitted | (pending) | [impl-registry](impl-registry.md) | [design-lifecycle](design-lifecycle.md) |
| Group-rigid drag | planned | — | — | [design-drag](design-drag.md) |
| Detach modifier + release-to-solo | planned | — | — | [design-drag](design-drag.md) |
| Bisection | planned | — | — | [design-bisection](design-bisection.md) |
| Curvature rendering + kcfg | planned | — | — | [design-curvature](design-curvature.md) |
| Alt+wheel nudge | planned | — | — | [design-curvature](design-curvature.md) |
| Control tab widget | planned | — | — | [design-control-tab](design-control-tab.md) |
| Group-tab on surface bbox | planned | — | — | [design-control-tab](design-control-tab.md) |
| KCM entries | planned | — | — | [design-curvature](design-curvature.md) |
| Autotests (bisection) | planned | — | — | [design-bisection](design-bisection.md) |

## Pointers

- **Feature overview + zero-context onboarding:** [overview](overview.md)
- **External design snapshot** (frozen, pre-implementation): [kwin-vr.wiki/Work-Surfaces](https://github.com/Bake-Ware/kwin-vr/wiki/Work-Surfaces). That page was the approved v1 design as of 2026-04-23; it will be replaced with the synced `design-*.md` set when we merge. Until then it does not track in-branch amendments.
- **Base commit this branch is off:** `107f6ef91b` on `6.6.3_vr_main` (Merge `feat/qol_scroll_world_depth`).

## For a zero-context agent picking this up

1. Read [overview](overview.md) for the feature's purpose and scope.
2. Read [README](README.md) (this file) for conventions + current status.
3. Walk `design-*.md` in any order — they cover intended behavior.
4. Walk `impl-*.md` in progress-index order to see what was actually built and why commits happened when they did.
5. Before writing code, check the Progress index above to know which chunk is next.
6. Never merge to main. Push commits for backup only.
