# Firestore → BigQuery export instances

One instance of `firebase/firestore-bigquery-export` per collection we want in
the warehouse. Every instance shares the same dataset (`playsphere_analytics`,
`asia-south1` — the same region as Firestore and every Cloud Function, so no
query crosses a region) and differs only in `COLLECTION_PATH` / `TABLE_ID`.

Each instance creates two BigQuery objects:

- `<TABLE_ID>_raw_changelog` — append-only history of every write
- `<TABLE_ID>_raw_latest` — a view of the current state of each document

`docs/ANALYTICS.md` explains what is built on top of them and why the split
between "warehouse" and "rollups the app reads" exists at all.

## Costs, honestly

`bq-fixtures` is the expensive one. A fixture document is rewritten on every
scoring action, so the changelog grows with ball-by-ball volume rather than
with the number of matches. That is also exactly why it is worth having — it
is the only place a per-delivery history survives — but it is the instance to
watch, and `TABLE_PARTITIONING=DAY` is there so a query over last week does
not scan all of it.
