# Character profile: what is left

The profile sections that are implemented are specified in
`docs/DATA_CONTRACT.md` and `schema/ScryDB.schema.json`. This file tracks what
is **not** done and what is **not yet confirmed in game**. Delete entries as
they are resolved; put confirmed client facts into `AGENTS.md`.

## Implemented, awaiting in-game confirmation

Everything else was confirmed in a real session on 2026-11-23 (13/13 selftests,
schema valid, data inspected with `./dev sv`).

| Section | Assumption to confirm |
|---|---|
| `bank` | Bank is tab-based (`C_Bank.FetchPurchasedBankTabIDs(Character)`) and tab contents are readable through `C_Container` while the bank is open. Needs a bank visit. |
| `spells.pet` | Pet spells are listed through `C_SpellBook.HasPetSpells`. Needs a character with a pet. |
| `skills`, `reputations` | Entries under collapsed headers are still listed. |

## Not built yet

| Section | Content | Why it waits |
|---|---|---|
| `account` (top level) | Account-wide bank, account-wide Legacy data | Need to see in game whether an account bank exists on Forever and which Legacy data is shared. |
| `statistics` | Kill counts, deaths, ... | `GetStatistic` / `GetStatisticsCategoryList` are undocumented here and the statistic IDs are unknown: needs a logging build first. |
| `mail` | Gold and items in the mailbox (snapshot at the mailbox) | `GetInboxHeaderInfo` is undocumented here. |
| `auctions` | Own auctions (snapshot at the auction house) | Unknown whether Forever uses the modern auction house API (`C_AuctionHouse.GetOwnedAuctions`). |
| `legacy.challenges` progress | Criteria progress of unfinished challenges | Only completed ones are stored now. |
| Item detail | Per-stack item links instead of `itemID -> count` | Decided 2026-11-22: counts are enough for now. |
