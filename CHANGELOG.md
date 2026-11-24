# Changelog

Bounty Ledger 1.0.0 to 1.1.6 and NCPD Uplink 1.0.0 were built on game version 2.31; 1.1.7 on 2.5. Only 1.0.0 has a written in-game test.

## Bounty Ledger 1.1.7 - 2026-11-23
### Fixed
- A warrant target killed by someone else (a gang, a police officer, a car) is no longer journalled as the player's kill; the NCPD Uplink shows it as "died (not by V)".

In use in the author's game and working; no written test record.

## Bounty Ledger 1.1.6 - 2026-11-07
### Fixed
- Review fixes; a claim voided because Trauma Team extracted the target is journalled as such.

## Bounty Ledger 1.1.5 - 2026-11-07
### Added
- A public method other mods can call to void the claim on one target.

## Bounty Ledger 1.1.4 - 2026-11-06
### Added
- Claim details, a saved event journal and lifetime totals for the NCPD Uplink window.

## NCPD Uplink 1.0.0 - 2026-11-06
- First version of the window: open batch with countdown, claims on file, warrants, journal, lifetime totals; pinned panel and "Ask Regina" hotkeys.

## Bounty Ledger 1.1.3 - 2026-11-06
### Changed
- Open claims are kept in the save, so the death downgrade and withdrawals survive a load.
- Lawful arrest no longer sets a saved flag on the target; the assault report is skipped for flagged targets in the current session instead.

## Bounty Ledger 1.1.2 - 2026-11-06
### Fixed
- Killing a warrant target is reported again; the scan list is reset on load.

## Bounty Ledger 1.1.1 - 2026-11-06
### Added
- A target tagged for I Want Them Alive's pickup is withdrawn from the NCPD batch (one payer per target).

## Bounty Ledger 1.1.0 - 2026-11-06
### Added
- Deep Scan warrants: scanned civilians with an active warrant become bail jobs.
- Payouts are tagged for Cashflow.

## Bounty Ledger 1.0.1 - 2026-11-06
### Changed
- NCPD processing time default 10 game minutes (was 60).

## Bounty Ledger 1.0.0 - 2026-11-06
- First version: prices by wanted stars, alive and dead rates, scan rule, delayed batch payout.

Tested in game: prices, alive claim, death downgrade, scan rule and batching seen; the payout was not reached in that test.
