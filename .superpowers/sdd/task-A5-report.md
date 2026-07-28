# Task A5 Report

- **Status:** DONE_WITH_CONCERNS
- Added five named cascade-checkbox regression tests covering recommended-only parent selection, parent-off propagation, mixed/on aggregation, and manual dangerous selection.
- **RED evidence:** Initial targeted run executed 5 tests with 1 expected failure in `testParentOff_AllChildrenOff`; the fixture exposed the `setState` same-state guard, so the parent was initialized `.on` before toggling `.off`.
- **GREEN evidence:** Targeted suite executed 5 tests with 0 failures; full suite executed 137 tests with 0 failures.
- **Concern:** Full-suite output contains pre-existing Core Data `FileEntry entity` duplicate-match error logs despite all tests passing.
