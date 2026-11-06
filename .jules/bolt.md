
## 2025-02-12 - Concurrent Music Folder Scanning
**Learning:** `MusicScanner.scan_folders` was bottlenecked by sequentially waiting on both the CPU/IO-bound `extract_metadata` thread and the database `upsert_music_file` insertion loop for each file found.
**Action:** Use an `asyncio.Semaphore` with `asyncio.gather` inside `os.walk` to concurrently execute extraction and insertion, significantly speeding up large folder scans.

## 2025-02-15 - Index Foreign Keys in SQLite Correlated Subqueries
**Learning:** Correlated subqueries finding the latest status per track (e.g., `(SELECT MAX(id) FROM sync_jobs s2 WHERE s2.music_file_id = s1.music_file_id)` in dashboard and file queries) cause full table scans if `music_file_id` is unindexed on `sync_jobs`, leading to quadratic query times as sync job history grows.
**Action:** Always maintain an index on `sync_jobs(music_file_id)` (and any foreign keys subjected to `GROUP BY` / correlated subqueries) to maintain O(log N) lookup speed.

## 2026-11-05 - Avoid Table-Wide GROUP BY Materialization in Point Queries
**Learning:** In queries targeting a single row (like `get_music_file_by_id`), joining against a global subquery that groups the entire table (`GROUP BY music_file_id`) forces SQLite to scan and materialize the entire history table before filtering to the single requested ID.
**Action:** For point queries, use a direct indexed lookup (`LEFT JOIN table t ON t.id = (SELECT MAX(id) FROM table WHERE fk = row.id)`) to keep query cost strictly O(log N) instead of O(N_table).

## 2026-11-06 - Avoid Derived Table Materialization in Paginated Multi-Row Queries
**Learning:** In multi-row queries (such as `get_music_files` and `get_dashboard_counts`), joining against a derived table (`LEFT JOIN (SELECT s1.* FROM sync_jobs s1 JOIN (SELECT music_file_id, MAX(id)... GROUP BY music_file_id)...)`) causes SQLite to materialize all historical jobs across every track and build an automatic covering index, even when returning only a single page of 200 items.
**Action:** Replace the global derived table join with a direct index-backed join `LEFT JOIN sync_jobs sj ON sj.id = (SELECT MAX(id) FROM sync_jobs WHERE music_file_id = mf.id)`. Because `idx_sync_jobs_music_file_id` is an existing covering index, SQLite computes `MAX(id)` per row in `O(log N)` without materializing the full table or creating temp btrees, yielding a 2.8x - 6.2x speedup.

## 2026-11-07 - Use B-tree Prefix Range Scans Instead of LIKE for Indexed Path Filtering
**Learning:** In SQLite, `LIKE 'folder/%'` cannot use standard B-tree indexes unless compiled with case-sensitive LIKE PRAGMA or matching COLLATE NOCASE, forcing a full `SCAN` of the entire table on queries like folder stats aggregation. Furthermore, calculating total and unmapped song counts with two separate queries doubles table scans and database round-trips.
**Action:** Use an index-range scan `(path >= lower_bound AND path < upper_bound) OR path = exact_path` with single-pass conditional aggregation (`COUNT(*)` and `COUNT(CASE WHEN m.id IS NULL THEN 1 END)`). This enables `SEARCH USING COVERING INDEX idx_music_files_path` and delivers a ~5.9x query speedup with zero full-table scans.
