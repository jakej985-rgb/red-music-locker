
## 2025-02-12 - Concurrent Music Folder Scanning
**Learning:** `MusicScanner.scan_folders` was bottlenecked by sequentially waiting on both the CPU/IO-bound `extract_metadata` thread and the database `upsert_music_file` insertion loop for each file found.
**Action:** Use an `asyncio.Semaphore` with `asyncio.gather` inside `os.walk` to concurrently execute extraction and insertion, significantly speeding up large folder scans.

## 2025-02-15 - Index Foreign Keys in SQLite Correlated Subqueries
**Learning:** Correlated subqueries finding the latest status per track (e.g., `(SELECT MAX(id) FROM sync_jobs s2 WHERE s2.music_file_id = s1.music_file_id)` in dashboard and file queries) cause full table scans if `music_file_id` is unindexed on `sync_jobs`, leading to quadratic query times as sync job history grows.
**Action:** Always maintain an index on `sync_jobs(music_file_id)` (and any foreign keys subjected to `GROUP BY` / correlated subqueries) to maintain O(log N) lookup speed.

## 2026-11-05 - Avoid Table-Wide GROUP BY Materialization in Point Queries
**Learning:** In queries targeting a single row (like `get_music_file_by_id`), joining against a global subquery that groups the entire table (`GROUP BY music_file_id`) forces SQLite to scan and materialize the entire history table before filtering to the single requested ID.
**Action:** For point queries, use a direct indexed lookup (`LEFT JOIN table t ON t.id = (SELECT MAX(id) FROM table WHERE fk = row.id)`) to keep query cost strictly O(log N) instead of O(N_table).
