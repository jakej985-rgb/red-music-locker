
## 2025-02-12 - Concurrent Music Folder Scanning
**Learning:** `MusicScanner.scan_folders` was bottlenecked by sequentially waiting on both the CPU/IO-bound `extract_metadata` thread and the database `upsert_music_file` insertion loop for each file found.
**Action:** Use an `asyncio.Semaphore` with `asyncio.gather` inside `os.walk` to concurrently execute extraction and insertion, significantly speeding up large folder scans.
