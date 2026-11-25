# Grand Bruxelles — PR Drift Dashboard

## Purpose

The PR Drift Dashboard attacks two recurring factory costs without changing production code:

- `main` advances while specialist lots are still open;
- long or overlapping specialist branches become unsafe to replay mechanically.

The dashboard is read-only. It measures the live `main` SHA and every open PR, then classifies whether a branch can be considered a clean rebuild candidate or needs owner coordination.

## States

- `CURRENT` — zero commits behind live `main` and no detected file overlap.
- `REBUILD_REQUIRED` — behind live `main`, complete changed-file inventory, and no overlap with another open PR. This is a candidate for a fresh-main rebuild, not an automatic force-push.
- `OWNERSHIP_CONFLICT` — one or more changed files overlap another open PR. Manual owner coordination is required.
- `OWNERSHIP_UNCERTAIN` — the changed-file inventory is incomplete. The dashboard refuses to call the branch safe for mechanical rebuild.

A separate `long_lived_risk=true` flag is raised at the versioned default thresholds of 20 commits or 72 hours. It is a risk signal, not proof that the branch is wrong.

## Safety rails

- `automatic_merge_allowed=false`;
- `automatic_force_push_allowed=false`;
- file overlap wins over stale/rebuild status;
- incomplete file inventory fails closed;
- all comparisons use the live `main` SHA read during the workflow run;
- no production, CityGen state or PR branch is modified by the dashboard.

## Workflow

Run **Actions → Grand Bruxelles PR Drift Dashboard**. The workflow collects live PR metadata through the GitHub API, computes `behind_by`, enumerates changed files, runs the deterministic planner, and uploads `snapshot.json` plus `pr_drift_plan.json`.

The intended later ONE CLICK integration is to consume this report before dispatching any rebuild work. A stale branch is only a mechanical rebuild candidate when the changed-file inventory is complete and no concurrent open PR owns any of the same files.
