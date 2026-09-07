# Studio reliability contracts

This change implements the first reliability cycle from the September 2026
studio audit, on top of v0.52.0's synced Create workspaces. The larger creative
feature roadmap and platform/media architecture recommendations remain separate
work. The next media delivery cycle is documented in
[Media delivery reliability](media-delivery-reliability.md).

## Generation intent

Every deliberate Generate activation creates a new operation, even when its
prompt, references, seed and settings match an earlier or still-running job.
There is no prompt fingerprint, content-based deduplication, or waiting period
between accepted submissions. The in-flight activation guard covers the submission call, including preparation
and receipt bookkeeping; it releases when that call finishes so another take
can be requested while the previous film is still generating.

The operation captures its recipe and routing before hydration, account checks
or pricing requests. Editing the draft or switching tabs during preflight cannot
change the captured generation. ArtCraft's idempotency token derives from the
operation's unique local ID, never from the inputs.

Immediately before a chargeable provider POST, the gateways persist an uncertain
acceptance state. A lost response or interrupted process cannot honestly prove
that the provider rejected the request. Those jobs say **Submission unknown**,
retain a warning to check the provider console, and are not automatically
resubmitted or failed over. Confirmed rejecting responses remain errors; a saved
provider receipt remains recoverable after optional bookkeeping fails.

That uncertain state describes an *interrupted* submission, so only the process
still holding the request open may look past it: while a submission is in
flight, its gateway serves that record as **Submitting**, does not recover it as
interrupted, and the studio overlays the card onto every library read — a Drive
refresh, a preference write, the periodic cross-device pass — so an
optimistically inserted card can neither disappear from Recent work nor accuse a
live request of an unconfirmed charge. The durable bytes are unchanged, so any
other reader (a second device, the next launch) still sees the uncertain state.

## Library preservation

Every asynchronous library read the studio applies goes through the superseded
read merge, not a wholesale replacement of the in-memory library. A read notes
the snapshot revision before it starts; if any other code path has written the
library by the time it answers, the response is adopted record by record — the
store wins except where the in-memory copy carries more of the film or is
plainly newer — and records only this device knows about are carried across.
That covers the manual Drive refresh, the periodic cross-device pass, the
delivery paths, the preference write's returning snapshot, the foreground
reconcile, and the provider-catalog refresh. A film delivered while one of
those reads was open therefore stays on screen, and a stale copy of a record
cannot undo a published Drive swap the studio is already showing.

Drive writes carry the immutable snapshot on which their edits were based.
Vault reads and background refreshes cannot redefine an operation's deletions.
Deletion wins over a stale edit when the record existed in that base; durable
long-lived tombstones and field-by-field conflict resolution remain future work.

Local edits can persist through transient Drive read failures using the cached
remote view. This is not a new general offline queue for arbitrary cloud edits.
Malformed JSON roots invoke backup recovery; newer unsupported schemas are
refused rather than loaded or overwritten as an empty library.

Moving a library verifies copied metadata and uncached cloud media digests before
removing originals. Earlier Drive copies are kept when safe overwrite provenance
is unavailable. A changed local library or conflicting character assignment
stops the move and preserves originals. Draft-referenced local media remains
protected; a library move does not promise to relocate every draft attachment.

A permanent wipe removes the primary metadata and its owned recovery files.
Normal writes sanitize valid legacy credential/diagnostic backups while retaining
metadata. Undecodable recovery copies remain preserved for explicit recovery;
they are not guessed at or silently destroyed.

## Drafts, recovery and access

The last ten closed drafts can be reopened from the Create tab recovery menu.
Reopening uses a new tab ID so synced close tombstones remain respected. Active
and recoverable draft media participates in reference-aware cleanup.

Save failures stay visible with retry; a failed initial read cannot be overwritten
by an empty default workspace. Source-only drafts are real work and are preserved
when reusing a generation. Tab actions expose semantic labels, the screenplay
editor supports Escape followed by Tab to leave indentation mode, and notice
actions retain the operation that was actually displayed.

## Cost evidence and diagnostics

Account balance changes are account observations, not confirmed task charges.
Historical inferred amounts remain readable for audit, but are excluded from
settled totals and route calibration. Task-reported amounts override earlier
observations, including zero-cost refunds. Fixed published route prices and adapter quotes remain
estimates. Historical records labeled only `provider-reported` cannot always
distinguish an old adapter quote from a genuine task amount; those records are
retained rather than relabeled by guesswork. Quote variance summarizes per-film ratios from matched settled pairs.

Persisted diagnostics use a small allowlist and remove inline media, credential
fields, bearer strings and private URL details. Existing record serialization,
recovery-file writes and companion errors use the same boundary. Desktop Google
refresh tokens survive offline, rate-limit and server failures; a confirmed
`invalid_grant` response requires reconnecting.

## Verification

Regression coverage includes repeated identical takes, preflight edits, dropped
submission responses, interleaved Drive clients, corrupt uploads, concurrent
library moves, backup recovery, closed-draft assets, failed saves, keyboard and
semantic access, transient OAuth failures, synthetic secret payloads, and matched
cost accounting. All fixtures use temporary data and mocked provider transports.
Live provider billing, authenticated multi-device Drive behavior and hardware
lifecycle behavior require their own integration validation.
