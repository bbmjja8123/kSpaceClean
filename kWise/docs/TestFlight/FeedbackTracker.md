# TestFlight Feedback Tracker — kSpaceClean v1.0 (Week 15)

## Daily Review (5 minutes)
- [ ] TestFlight feedback tab: any new comments?
- [ ] App Store Connect → kSpaceClean → TestFlight → Crashes: any new crashes?
- [ ] `~/Library/Application Support/kWise/metric-kit/` (on test machines you have access to): any new `.json` files?

## Crash Triage
For each crash:
1. Read the JSON payload (timestamp + stack + termination reason).
2. Look up the stack in `kWise/`.
3. File a GitHub issue in the form `crash(<symbol>): <one-line summary>` and assign.
4. If the crash blocks any of the 5 testers from completing a scan → fix in E1 buffer.

## Weekly Roll-up (Friday)
Summarize:
- Top 3 feedback themes (with tester counts)
- Top 3 crash signatures
- Open issues filed this week

Send roll-up to the team Discord and to the Apple Developer Relations contact if any crash is severe.

## Tester Acknowledgement
At end of week 15, send each tester a thank-you DM with a teaser for the v1.1 launch.
