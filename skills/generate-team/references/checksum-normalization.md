# Checksum Normalization — the design↔build hash contract

This document defines the **exact** normalization applied to a `design.md`
before its sha256 is computed, and **why each step exists**. It is the written
form of the contract implemented by
[`scripts/checksum.sh`](../scripts/checksum.sh).

> **Single source of truth.** Both sides of the gate MUST obtain the digest by
> running `checksum.sh` — the producer (`scripts/approve`, which *freezes* the
> checksum at approval) and the consumer (the `build` command, which *verifies*
> it). **Never hand-roll hashing** in approve or build. If both sides call the
> same script, a *false* mismatch (the two sides disagreeing on a spec that
> nobody actually changed) is structurally impossible — that zero is the whole
> point (spec Constraints "체크섬 정규화", D3, R3.2, R4.3).

## Usage

```sh
digest=$(skills/generate-team/scripts/checksum.sh path/to/design.md)
```

- **stdout:** the lowercase sha256 hex digest, and nothing else (so it is safe
  to capture into a variable).
- **errors:** a message on stderr and a non-zero exit code; stdout stays empty.
  - exit `2` — wrong number of arguments (usage error)
  - exit `1` — file not found / not a regular file / not readable / no sha256
    tool available

## The normalization steps

The digest is computed over the file **after** the following transformation, in
order:

### 1. Read the file

The raw bytes of `design.md`.

### 2. Remove `checksum:` and `status:` from the frontmatter

Inside the leading YAML frontmatter block (the first `---` … `---`), the
`checksum:` line and the `status:` line are deleted **entirely** before
hashing.

**Why:** `approve` is the moment that *mutates* `status` (→ `approved`) and
*writes* `checksum` (the frozen digest). If those two lines were part of the
hashed input, the hash would depend on values that approve is changing at the
very instant it computes the hash — a self-referential definition. The digest
could never match itself on the next read, producing a guaranteed false
mismatch. Excluding them makes the hash a function of *only* the design content
the human actually reviewed.

**Scope matters:** the removal is applied **only within the frontmatter block**.
A body line that happens to begin with `status:` or `checksum:` (e.g. prose or
a code sample) is preserved and hashed normally. The script tracks the
frontmatter delimiters to enforce this.

### 3. Keep everything else

The rest of the frontmatter (e.g. `team:`, `model:`, any other fields) **and**
the entire body are retained. The gate must detect any change a human could
make to the design they are approving — only the two self-referential meta
fields are excluded.

### 4. Normalize line endings to LF + strip trailing whitespace

Every line has any trailing carriage return (`\r`) and any other trailing
whitespace removed, and lines are joined with `\n` (LF).

**Why:** editors, OSes, and git autocrlf settings silently flip CRLF↔LF and add
or remove trailing spaces. Without this step, opening `design.md` on a
different machine — or letting an editor "clean up" whitespace on save — between
approve and build would flip the digest even though the *meaning* is identical.
That is exactly the false mismatch the invariant forbids. Normalizing the
"cosmetic" bytes makes the digest depend on content, not on file-system
incidentals.

The script also re-appends a single trailing newline to the normalized text
before hashing, so the digest is stable regardless of whether the source file
happened to end with a newline.

### 5. Compute sha256

The sha256 hex digest of the resulting normalized bytes is printed.

## Portability

`checksum.sh` prefers `shasum -a 256` (present by default on macOS / darwin) and
falls back to `sha256sum` (typical on Linux). Both produce byte-identical
digests for identical input, so the script is safe across the platforms approve
and build may run on. If neither tool is present, the script errors with a clear
message and a non-zero exit.

## Why this is the *only* place the rules live

If approve and build each re-described "exclude status/checksum, normalize
LF/whitespace, sha256," the two descriptions would inevitably drift — a stray
`tr` here, a different `sed` there — and reintroduce the false-mismatch risk the
gate is meant to eliminate. Centralizing the contract in one executable means
the producer and consumer are, by construction, computing the same function.
