
## 2025-02-12 - Concurrent Music Folder Scanning
**Learning:** `MusicScanner.scan_folders` was bottlenecked by sequentially waiting on both the CPU/IO-bound `extract_metadata` thread and the database `upsert_music_file` insertion loop for each file found.
**Action:** Use an `asyncio.Semaphore` with `asyncio.gather` inside `os.walk` to concurrently execute extraction and insertion, significantly speeding up large folder scans.

## 2025-02-15 - Index Foreign Keys in SQLite Correlated Subqueries
**Learning:** Correlated subqueries finding the latest status per track (e.g., `(SELECT MAX(id) FROM sync_jobs s2 WHERE s2.music_file_id = s1.music_file_id)` in dashboard and file queries) cause full table scans if `music_file_id` is unindexed on `sync_jobs`, leading to quadratic query times as sync job history grows.
**Action:** Always maintain an index on `sync_jobs(music_file_id)` (and any foreign keys subjected to `GROUP BY` / correlated subqueries) to maintain O(log N) lookup speed.
