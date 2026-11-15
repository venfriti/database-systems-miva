# AI Use Declaration

**Student:** Tolu Sanusi · Miva Open University
**Course:** MIT 8103 Advanced Database Systems

This declaration covers all five portfolio activities and the final documentation, as required by section 11 of the assessment brief. I remain responsible for the accuracy, originality and understanding of everything submitted.

## 1. AI tool used

| Tool | Provider | How it was accessed |
|---|---|---|
| Claude | Anthropic | Claude Code (VS Code extension) |

## 2. What it was used for

- **Writing code:** some of the code in the repository (SQL, Python and JavaScript scripts) was written with AI assistance.
- **The final test run:** the AI tool ran every portfolio's scripts again in Docker, regenerated the outputs and screenshots, and updated the measured figures in the README files to match.

The case study, the database design and the design decisions are my own.

## 3. How the output was reviewed and verified

I reviewed all AI-assisted code before using it. Every script was then run on my own machine (PostgreSQL 16, MongoDB 7.0 and Redis 7 in Docker). The results in each `test-results/` folder come from those runs, not from text written by the AI tool. These checks confirm that the code does what it claims:

| Portfolio | Verification |
|---|---|
| 1 | `verify.sql` reconciles stock with its movement ledger and invoice totals with their order lines. `constraint-tests.sql` confirms that each constraint rejects invalid data (T1–T13) and accepts valid data (T14). |
| 2 | Each optimisation was measured with `EXPLAIN (ANALYZE, BUFFERS)` before and after (median of 5 runs). Each rewritten query was compared with the original using `EXCEPT` in both directions. The data generator's integrity checks all return 0. |
| 3 | `run_scenarios.py` runs every concurrency scenario on two real connections and records the actual result of each step. The outcomes were checked against PostgreSQL's documented isolation behaviour. |
| 4 | MongoDB query results were cross-checked against the same queries in PostgreSQL (D4–D7, and D5 to the cent on all 60 rows). Index use was confirmed with `explain()`. The validator and the transaction rollback were tested with deliberately invalid input. |
| 5 | Replication, failover and sharding were observed on a running 5-server cluster (`pg_stat_replication`, `pg_prepared_xacts`, partition-pruning plans), not just described from documentation. |

Re-running everything for the final test run exposed problems, which were investigated and fixed:
- The P2 database has to be built before P1's constraint tests run, because their failing inserts use up id values.
- The P5 failover demo could not reliably re-attach the old primary. `cluster.sh` now keeps enough WAL for `pg_rewind`, and the demo checkpoints the new primary before rewinding.
