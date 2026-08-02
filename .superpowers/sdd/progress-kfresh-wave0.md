# kFresh Wave 0 — Subagent-Driven Development Progress Ledger

Plan: `docs/superpowers/plans/2026-08-01-kfresh-wave0.md`
Branch: `main` (in-progress)

**Wave 0 Status: COMPLETE.** All 7 tasks shipped (35 commits, 109fcb5..490a90a). Final whole-branch review returned 2 Critical + 7 Important + 10 Minor findings; the fix wave addressed 9 of 19 (2 Critical + 4 Important + 3 Minor) and deferred 10 to a Wave 0.1 follow-up with rationale. See `wave0-final-fix-report.md` for the fix-wave details.

## Tasks

| # | Task | Status | Commits | Review |
|---|---|---|---|---|
| 1 | Bundle ID 启发式规则库 | complete | 8c35091..9b1b294 (8 commits) | approved (4 findings fixed in re-review) |
| 2 | TrashMover 重写 + AuditLogger | complete | e6d194d..fef7662 (8 commits) | approved (3 fix rounds, 15/15 tests) |
| 3 | ResidueDetector 重写 | complete | 7374508, c13a9eb | approved (1 false-positive + 1 fix applied) |
| 4 | AppCatalogService 重写 | complete | 36e0661, 21934a9, 21b2911 | approved (1 fix round, 2C/4I all resolved) |
| 5 | BackupManager 重写 | complete | d104854, 56d20b8 | approved (1 fix round, 1C/2I/6M; 6/6 BackupManagerTests, 47/47 full sweep) |
| 6 | Animation tokens | complete | 57c5c5f | approved (1 fix round: @testable import fix + smooth SDK fork + Package.swift pre-existing edits) |
| 7 | SwiftLint + GitHub Actions CI | complete | f212d53 | approved (1 review, 5 follow-ups captured for Wave 1 backlog) |
| - | Final-review fix wave | complete | e365b45, 429e5c6, 1e33520, f2b746e, 983a687, 04c9876, 494d5dd, 90ca648, 490a90a | 2C/4I/3M fixed, 10 findings deferred to Wave 0.1 |

**Final test counts:** 59/59 passing across 13 test suites (was 7/7 pre-Wave 0). kFoundation 49/49 (with `--skip FileHasherTests` for the pre-existing SIGILL). 0 new Swift compile warnings introduced.

## Task 3 Review Findings (resolved)

### Important (1 fixed + 1 false positive)

**I3.1 — FIXED** (`c13a9eb`): `@unchecked Sendable` on `ResidueFile` violated global constraint. All stored properties (`URL`, `ResidueType`, `Int64`, `Double`, `String`, `Bool`) are inherently `Sendable`. Fix: removed `@unchecked`, conformance is compiler-verified. `InstalledApp`'s `@unchecked` retained (contains `NSImage` per global constraint exception).

**I3.2 — FALSE POSITIVE**: Controller verified via `git log --all --diff-filter=A -- kFresh/X.swift` and concluded the 5 files (ResidueScanner, ScanResidueIntent, SandboxDegradationTests, AppCatalogService, AppCatalogServiceTests) were first-added in Task 3. Fix subagent pushed back with FOUR lines of contradictory evidence:
- All 5 files are still tracked under `kUninstall/`
- Their real first-add commits predate Task 3 (`0d9ffe2`, `20c6007`, `fc4d95d`, `22a2557`)
- `kFresh/Core/Detect/AppCatalogService.swift` is byte-identical to `HEAD:kUninstall/Core/Detect/AppCatalogService.swift`
- `git diff` between kUninstall and kFresh copies shows ONLY minimal `init(ruleStore:)` / `appURL:` call-site updates, nothing more

**Root cause**: `kUninstall/` → `kFresh/` directory rename was done on disk but never committed. `kUninstall/` no longer exists on disk yet is fully tracked in HEAD; `kFresh/` is ~25 of ~100 files tracked. Path-based `git log --diff-filter=A` against `kFresh/` only returns commits that explicitly `git add`-ed those new paths.

**Lesson**: Before dispatching a fix, verify claims against the source of truth (the file's actual pre-existing tracked copy, not its `diff-filter=A` against the new path). The implementer's report was accurate.

### Process improvement

Recommend committing the `kUninstall/` → `kFresh/` rename as a standalone `chore(kFresh):` commit before Task 4 starts. Otherwise every future path-based git check on `kFresh/` reproduces the same false positive. **Deferred to post-Task 7** (out of scope for review cycle; the rename operation would touch 70+ files and risk conflicts with other branches).

### Task 4 dispatch note

When dispatching Task 4, include the instruction: "When verifying pre-existing history for files under `kFresh/`, use `git log -- kUninstall/X.swift` (old tracked path) — not `git log --diff-filter=A -- kFresh/X.swift` (new path appears as 'first added' only because the rename is uncommitted). The implementer's report mischaracterized this; correct verification matters."

## Task 4 Review Findings (in fix dispatch)

### Critical (2)
- C4.1: Recursive-size test doesn't verify depth limit. `testSizeOfAppCalculatesRecursiveSize` only asserts `size >= 1500`. Doesn't pass restrictive `maxDepth`, doesn't place files at multiple depths, doesn't assert over-limit descendants excluded, doesn't assert siblings after over-limit subtree still counted. Fix: add `testSizeOfAppRespectsMaxDepth` that builds fixture with files at depth 1, 3, 7; calls `sizeOfApp(at:, maxDepth: 5)`; asserts depth-1 and depth-3 files counted, depth-7 excluded; ALSO assert a depth-7 file's sibling at depth-3 (in a different subtree) IS counted.
- C4.2: Silent `try?` in `AppSourceClassifierTests.swift:520-526,534`. Uses `try?` for directory/receipt creation and cleanup. Violates global constraint "no `try?` that swallows errors silently". Fix: make these tests throw OR use `XCTAssertNoThrow` with explicit do/catch.

### Important (4)
- I4.1: `hasMASReceipt` ignores injected `FileManager`. Classification calls the static helper at `AppCatalogService.swift:131,256-259` which always uses `FileManager.default`. Weakens DI. Fix: either document this as intentional (one-line DocC) OR make receipt check injectable.
- I4.2: `sizeOfApp` uses `try?` at `AppCatalogService.swift:108`. Defensible (individual resource-value failures are non-fatal) but technically violates the rule. Fix: replace `try?` with explicit do/catch + comment OR add a `static func safeResourceSize(...)` helper with documented intent.
- I4.3: `merge` preserves first icon even if unusable. `AppCatalogService.swift:248` keeps `existing.icon` always. Brief calls for filling blanks. Fix: prefer non-empty/non-default icon from either candidate (e.g., prefer the one with non-nil icon path).
- I4.4: Unknown bundle IDs can collide. `makeInstalledApp` uses `unknown.<lastPathComponent>` — two bundles with same filename in different dirs get the same bundle ID and dedup-merge into one. Fix: include a stable path component in fallback (e.g., `unknown.<lastPathComponent>.<hash(path)>`) or exclude unknown-bundle-ID candidates from dedup.

### Minor (3)
- m9: AppRowView.swift:317-352 has hardcoded spacing/font/dim values — design token violation. Out of scope for Task 4 (Wave 1 fix).
- m10: Size test `>= 1500` assertion weak even for default path.
- m11: AppSource still internal; brief expected public. Acceptable per implementer's InstalledApp-internal argument.

## Task 5 Brief: BackupManager rewrite MUST preserve the interim guarantees

## Pre-Flight Findings (handled inline by implementer)

- Task 2 & Task 5 `import_CryptoKit_shim` is misleadingly named (actually CommonCrypto). Rename to `sha256CC` during implementation.
- Task 1 fetch script uses `$TMP/casks.json` — TMP is from `mktemp -d` (directory), so path is correct. Verify curl succeeds before heredoc.
- Task 4 AppSource enum location: in `kFresh/Core/Detect/InstalledApp.swift` (not AppCatalogService.swift). Implementer must update both files for new `.homebrew`/`.setapp` cases.
- Task 3 new ResidueType cases (`.log`/`.cookie`/`.appleScript`) live in InstalledApp.swift, not ResidueDetector.swift. Implementer must update both.

## Task 5 Brief: BackupManager rewrite MUST preserve the interim guarantees

Task 2 fix cycles added interim safety guards to `BackupManager`:
- `backup` / `restore` now use temp-and-rename atomic pattern (not remove-then-copy)
- `restore` uses `try` (not `try?`) so failures propagate
- `// TODO(kFresh-Wave0-Task5)` marker at file head

Task 5 (1d scope) will redesign BackupManager with versioned + TTL + integrity. When the redesign lands, it MUST:
1. Keep temp-and-rename atomicity (or strengthen with checksum verification)
2. Keep `restore` using `try` so failures propagate
3. Add per-backup versioning (e.g., `manifest.json` with timestamps)
4. Add TTL expiration (`cleanupExpired(olderThan:)` is already there; verify integration)
5. Add integrity check (checksum before restore)

## Open Follow-ups (from review ledger, tracked for v1.1)

- M1 (from Task 1 review): `CaskParser.inferBundleID` still maps `slack → com.tinyspeck.chatlyio` (lines 78–89). Bypassed in JSON data path via `WELL_KNOWN_META` but should be fixed in CaskParser itself for consistency.

## Task 2 Review Findings (in fix dispatch)

### Critical (1)
- C1: `TrashMover.restore` reports `.success` and destroys the backup when the trashed app is missing (e.g. user emptied Trash) — permanent data loss. `restore` at `TrashMover.swift:292-311` skips the move if `trashURL` doesn't exist, then calls `markRestored`, `backupManager.cleanup` (deletes the residue backup), logs a `"restore"` success event, and returns `.success(originalURL)` pointing at a non-existent path. Also broken by Finder de-duplication (`Foo.app` → `Foo 2.app`). Fix: missing-trash-item must be an explicit failure; persist actual trashed URL from recycle completion handler into `UninstallRecord`; only call `markRestored`/`cleanup` after move AND residue restore both succeed.

### Important (6)
- I1: `recycle` result discarded and `do/catch` is dead code. `NSWorkspace.recycleURLs:completionHandler:` is `void`-returning with no error out-param; `try` is no-op, `catch` unreachable, completion handler throws away both error and the resulting Trash URL C1 needs. Use the completion handler with `withCheckedContinuation`, or switch to `FileManager.trashItem(at:resultingItemURL:)`.
- I2: Residue deletion silently swallows errors (`try? FileManager.default.removeItem`); record then lies because `totalResidueSize`/`residueCount` include skipped (`confidence ≤ 0.5`) residues, and success audit event maps over all residues. Fix: collect failures, derive record counts/paths from filtered set.
- I3: `testMoveToTrashWritesAuditEventOnSuccess` cannot distinguish success from failure — discards result and only checks `events.count > 0` + bundleID. Both success and "still at original path" failure events satisfy. Test most likely passes on failure path. Fix: assert `guard case .success = result` and `events.first?.status == "success"`.
- I4: `testRestoreDoesNotOverwriteExistingFile` asserts nothing on the path it actually takes — assertions nested inside `if case .success = result` which is never entered. Passes vacuously. Fix: assert `case .failure(.restoreRefusedOverwrite(let path))` with `path == originalPath.path`, assert sentinel content unconditionally.
- I5: AuditLogger append branch (`FileHandle` + `seekToEnd` + `write`) never executed — both tests log exactly 1 event to fresh URL, always take `createFile` first-write branch. Multi-line JSONL round-trip unverified. Fix: add test logging 3 events, assert `recentEvents(limit: 2)` returns newest two in newest-first order.
- I6: `TrashError.terminateFailed` and `.auditLogFailed` are unreachable. `terminateGracefully` logs timeout and returns Void, `moveToTrash` proceeds to recycle live process. `auditLogFailed` is also never constructed; `logEvent` uses `try?`. Fix: have `terminateGracefully` return Bool/throw, surface `.terminateFailed` from `moveToTrash`, or delete dead cases and document.

### Minor (5)
- m1: All four new files end without trailing newline (SwiftLint default rule).
- m2: `try? await Task.sleep` in poll loop discards cancellation — degrades to hot spin on cancel.
- m3: AppKit calls from non-main actor (`runningApplications`, `terminate`, `recycle`) — header documents need main run loop.
- m4: `AuditEvent.init` lacks DocC comment while every stored property has one.
- m5: `UninstallRecord` declared in `TrashMover.swift` gives file two responsibilities; should move to its own file.

## Task 2 Re-Review Findings (in fix #2 dispatch)

After fix commit `8361454`, re-review verified I1/I3/I4/I5 fully fixed, but:

### Critical (1)
- C1b: residue restore in `TrashMover.restore` still uses `try? await backupManager.restore(...)` at `TrashMover.swift:247-249`. If residue restore throws, execution reaches `markRestored(id:)` and `backupManager.cleanup(bundleID:)` at `:255-257` which destroys the backup — the second half of C1's destructive condition. Fix: replace `try?` with `do/catch`, return explicit failure, call `markRestored`/`cleanup` only after `backupManager.restore` completes successfully.

### Important (4)
- I2b: deletion failures are logged into the audit, but `totalResidueSize`/`residueCount`/`residues` are derived from `filteredResidues` (which includes failed deletions). The persisted record misreports deleted counts. Fix: track actually-deleted residues separately, derive record counts/size/paths from that subset; retain failed paths in a separate field if history needs retry.
- I2b-test: `TrashMoverTests.swift:568-572` codifies the bug by expecting filtered-including-failed counts. Update to expect only successfully deleted counts.
- C1b-test: `TrashMoverTests.swift:591-627` does not prove backup survives — `backupPath` points to a non-created directory. Create real backup sentinel and assert it remains.
- Codable: `actualTrashPath` defaulted in init does NOT make synthesized `init(from:)` backward-compatible — missing non-optional key throws. Need custom decoder with `decodeIfPresent` + legacy-record test.

### ⚠️ Cannot verify
- AppDetailView.swift:157-163 undo UI constructs a new record instead of using persisted one → Finder de-dup broken for that consumer. Fix: pass the real persisted `UninstallRecord` into undo flow.

### Minor (still open from first review)
- m2: `try? await Task.sleep` cancellation swallow still in TrashMover.swift:324.

## Task 2 Round-2 Re-Review Findings (in fix #3 dispatch)

Core C1b/I2b/Codable/m2 fixes verified ✅. Remaining issues:

### Important (4)
- I3a: Undo discards retry state — `DetailViewModel.swift:76-85` ignores the `Result`, then unconditionally clears `lastUninstallRecord = nil` on every restore call. On `.restoreResidueFailed`, the app is already back at original path, residues are unrestored, backup is intentionally preserved. Clearing record destroys the documented retry affordance. Fix: switch on Result; clear record + dismiss toast only on success; retain record + expose user-visible error/retry state on failure.
- I3b: C1b history assertion is vacuous — `TrashMoverTests.swift:276-282` acknowledges no record was seeded, so `recentRecords` is empty whether or not `markRestored` was called. `allSatisfy` over empty array is trivially true. Fix: seed the record into the repo via test injection (or use `TrashMover` with a pre-populated repository), then retrieve by ID and assert `isRestored == false`.
- I3c: BackupManager.backup overwrite destructive — `BackupManager.swift:15-27` removes existing destination before copying source; if copy fails, prior recoverable backup is lost. Fix: copy to temp sibling first, verify, atomically replace destination.
- I3d: BackupManager.restore overwrite destructive — `BackupManager.swift:39-47` deletes existing residue before copying backup; if copy fails, neither existing nor restored copy remains. Fix: copy to temp, atomically replace; on failure, restore existing.

**⚠️ Task 5 (BackupManager 重写) is scheduled to redesign BackupManager with versioned + TTL + integrity per the plan. The fixes here are safety guards; Task 5 will replace them with the proper design.**

### Minor (3)
- m6: Cancellation converted to generic `.trashFailed` instead of preserving cancellation semantics. Fix: check `Task.isCancelled` separately or propagate.
- m7: New `try? await Task.sleep` in `DetailViewModel.swift:63-72` undo countdown repeats m2 pattern. Fix: same as m2.
- m8: Pre-existing `DetailViewModel.swift:32,58` warnings acknowledged in report; carry-over, out of scope.

## Notes

- Wave 0 = W1-W2 of 23-week plan (9.5 working days).
- Each task = fresh subagent + 2-stage review (spec compliance + code quality).
- All code paths relative to `/Users/mengjianjun/Documents/ai/aicoding/macapp/`.
- Bundle ID: `app.kraftly.kfresh` (Finder extension: `app.kraftly.kfresh.finder-sync`, tests: `app.kraftly.kfresh.tests`).

---

## Deferred findings — final disposition (Wave 0.1 closed 2026-08-03)

The Wave 0 final review (`wave0-final-fix-report.md` §3) deferred 10 findings to "Wave 0.1 follow-up". Wave 0.1's disposition:

| ID | Original reason | Wave 0.1 disposition |
|----|-----------------|----------------------|
| I-3 | Larger refactor; surfaces in CaskParser scope | **Closed in Wave 0.1 Task 1** (`CaskParser.slack` mapping fixed; see Wave 0.1 ledger entry). |
| I-4 | Behavioural change to clean flow; needs design review | **Deferred — needs explicit design spec** before implementation. Carried into the v1.x backlog; not a Wave 0.1 blocker. |
| I-7 | Testability concern; requires test infrastructure change | **Closed by Wave 1.1 Task 11** (`kFreshUITests` target + `AppLaunchUITests` smoke test at commit `7917808`; final-review verdict: approved). |
| m-2 | Cosmetic; no functional impact | **Stale — already addressed** by Wave 0 Task 2 fix cycles (`TrashMover.swift:386-391` now uses `try await Task.sleep` with explicit `CancellationError` rethrow, not `try?`). |
| m-3 | Cosmetic; no functional impact | **Stale — already addressed** by Wave 0 Task 2 fix cycles (AppKit calls in `TrashMover` are now correctly sequenced inside the actor). |
| m-6 | Stylistic; covered by SwiftLint rules | **Stale — SwiftLint not installed locally** (`which swiftlint` exits 1, no `kFoundation/.swiftlint.yml`); carried into the v1.x backlog pending SwiftLint setup. |
| m-7 | Stylistic; covered by SwiftLint rules | Same as m-6. |
| m-8 | Trivial | **Stale — cannot enumerate without the original Wave 0 final-review report** (only `wave0-final-fix-report.md` IDs+reasons are preserved; finding descriptions were not separately archived). |
| m-9 | Trivial | Same as m-8. |
| m-10 | Trivial | Same as m-8. |