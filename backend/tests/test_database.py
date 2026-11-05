import pytest
import pytest_asyncio
from pathlib import Path
from ytm_service.database import Database
from ytm_service.models import MatchType, UploadStatus

@pytest_asyncio.fixture
async def test_db(tmp_path: Path):
    db_file = tmp_path / "test.db"
    db_instance = Database(db_file)
    await db_instance.init_db()
    return db_instance

@pytest.mark.asyncio
async def test_upsert_and_get_music_file(test_db: Database):
    file_data = {
        "path": "/music/battery.flac",
        "filename": "battery.flac",
        "artist": "Metallica",
        "album": "Master of Puppets",
        "title": "Battery",
        "track_number": 1,
        "disc_number": 1,
        "duration": 312.0,
        "format": "FLAC",
        "file_size": 25000000,
        "modified_time": 1700000000.0,
        "file_hash": "dummyhash",
        "metadata_hash": "dummyhash2"
    }
    file_id = await test_db.upsert_music_file(file_data)
    assert file_id > 0

    files = await test_db.get_music_files()
    assert len(files) == 1
    assert files[0].title == "Battery"
    assert files[0].artist == "Metallica"
    assert files[0].upload_status == UploadStatus.NOT_UPLOADED

@pytest.mark.asyncio
async def test_sync_job_lifecycle(test_db: Database):
    file_data = {
        "path": "/music/schism.flac",
        "filename": "schism.flac",
        "artist": "Tool",
        "album": "Lateralus",
        "title": "Schism",
        "track_number": 5,
        "disc_number": 1,
        "duration": 406.0,
        "format": "FLAC",
        "file_size": 35000000,
        "modified_time": 1700000000.0
    }
    file_id = await test_db.upsert_music_file(file_data)
    job_id = await test_db.create_sync_job(file_id)
    assert job_id > 0

    job = await test_db.get_next_queued_job()
    assert job is not None
    assert job.id == job_id
    assert job.status == UploadStatus.QUEUED

    await test_db.update_sync_job(job_id, UploadStatus.VERIFIED)
    next_job = await test_db.get_next_queued_job()
    assert next_job is None

    history = await test_db.get_sync_history()
    assert len(history) == 1
    assert history[0].status == UploadStatus.VERIFIED


@pytest.mark.asyncio
async def test_sync_jobs_music_file_id_index(test_db: Database):
    """Verify that idx_sync_jobs_music_file_id exists and is used by query planner."""
    async with test_db.get_connection() as conn:
        # Check index exists in sqlite_master
        async with conn.execute(
            "SELECT name FROM sqlite_master WHERE type = 'index' AND name = 'idx_sync_jobs_music_file_id'"
        ) as cursor:
            row = await cursor.fetchone()
            assert row is not None, "idx_sync_jobs_music_file_id index should exist"

        # Check EXPLAIN QUERY PLAN uses index on correlated MAX subquery
        query = """
            EXPLAIN QUERY PLAN
            SELECT COUNT(*) FROM sync_jobs s1
            WHERE s1.status = 'failed'
            AND id = (SELECT MAX(id) FROM sync_jobs s2 WHERE s2.music_file_id = s1.music_file_id)
        """
        async with conn.execute(query) as cursor:
            rows = await cursor.fetchall()
            plan_str = " ".join(dict(r)["detail"] for r in rows)
            assert "idx_sync_jobs_music_file_id" in plan_str, (
                f"Query plan detail should use idx_sync_jobs_music_file_id, got: {plan_str}"
            )
