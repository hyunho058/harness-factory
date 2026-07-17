# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- Shared `validate.sh` helper (`skills/generate-team/scripts/`) that structurally
  checks a `design.md` — invoked by `approve` before freezing and by `build` after
  the checksum gate, mirroring how both sides already share `checksum.sh`.
- Shared `section-checksum.sh` helper (`skills/generate-team/scripts/`) that hashes
  **one** `design.md` section (`agent:<name>` / `skill:<name>` / `orchestrator`) by
  reusing the literal `checksum.sh` normalization. `build` stamps each generated
  artifact with a provenance marker `<!-- generated-from: <selector> @ sha256:… -->`
  and, on a re-build, recomputes it to decide **preserve vs. regenerate
  deterministically** — replacing the old LLM re-render comparison that
  mis-classified untouched agents as changed (spec §D6/§R5.3/§R5.5). The marker
  lives in the artifact, never in `design.md`, so the checksum gate (§R5.4) is
  unaffected. Section-provenance regression tests added to `tests/gate_test.sh`.
- Gate regression tests under `tests/` plus a CI workflow under `.github/workflows/`,
  making the "reject on missing / draft / tampered spec" completion criterion
  automated instead of a manual repro.
- `CHANGELOG.md` (this file).
- A `specs/` `.gitignore` exception (`!specs/gated-team-generation/`) so the
  canonical design ledger `specs/gated-team-generation/spec.md` ships with the
  plugin — installed users can now resolve the "spec D3 / R3.x" citations in the
  scripts and references.

### Changed
- `approve` now validates the design spec (via shared `validate.sh`) **before**
  freezing `status: approved` and the checksum, so malformed specs fail at
  approval time rather than surfacing later at build time.
- De-duplicated the design↔build contract so a section rename can no longer make
  `approve`'s counters silently read `0`.
- README "Repository structure" tree refreshed to the real layout (the gated
  `design`/`build`/`generate-team` commands, the `team-design`/`team-build`/
  `generate-team` skills, `scripts/`, `assets/`, `references/`, `.claude-plugin/`,
  and the `plugins/harness-factory` symlink), with a Windows symlink caveat and a
  corrected description of the no-flag Phase -1 routing.

### Fixed
- `approve` no longer reports a false "Approved / frozen" success when run on a
  `design.md` that has no frontmatter (previously it computed a digest, discarded
  it because there was no frontmatter to write, and still exited 0 with an
  "approved" message).

## [0.2.0]

Baseline: the gated **design → approve → build** flow.

### Added
- Gated two-step generation split at the seam between *decisions* (Phase 0–2) and
  *materialization* (Phase 3–6):
  - `team-design` (producer) runs the interview and writes a reviewable
    `specs/<team>/design.md` with `status: draft`, writing no `.claude/*` files.
  - `team-build` (consumer) hard-gates the spec (exists → `status: approved` →
    checksum matches) and materializes `.claude/agents/`, `.claude/skills/`, and
    `CLAUDE.md` from the spec only, with no re-interview.
- Checksum anti-tamper gate: `scripts/approve` freezes the canonical sha256 of the
  spec body and `build` recomputes it via the same `scripts/checksum.sh`, so an
  edited-after-approval spec is rejected as tampered.
- `--skip-design` one-shot escape hatch preserving the legacy single-run Phase 0–6
  flow with no design spec and no approval gate.
- In-chat approval option for the design phase: on finishing, `design` offers
  Approve now / Revise / Review-the-file-myself, so the approval step can be a
  single in-chat choice without opening a terminal.
