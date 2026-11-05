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


@pytest.mark.asyncio
async def test_music_files_latest_sync_job_optimization(test_db: Database):
    """Verify get_music_files and get_dashboard_counts accurately resolve the latest sync job."""
    # Insert two tracks
    f1 = await test_db.upsert_music_file({
        "path": "/music/song1.mp3",
        "filename": "song1.mp3",
        "artist": "Artist A",
        "album": "Album 1",
        "title": "Song 1",
        "format": "mp3",
        "file_size": 1000,
        "modified_time": 1000.0,
    })
    f2 = await test_db.upsert_music_file({
        "path": "/music/song2.mp3",
        "filename": "song2.mp3",
        "artist": "Artist B",
        "album": "Album 2",
        "title": "Song 2",
        "format": "mp3",
        "file_size": 1000,
        "modified_time": 1000.0,
    })

    # For f1, create 3 sync jobs in sequence: failed -> queued -> verified
    j1 = await test_db.create_sync_job(f1)
    await test_db.update_sync_job(j1, UploadStatus.FAILED)
    j2 = await test_db.create_sync_job(f1)
    await test_db.update_sync_job(j2, UploadStatus.QUEUED)
    j3 = await test_db.create_sync_job(f1)
    await test_db.update_sync_job(j3, UploadStatus.VERIFIED)

    # For f2, create 2 sync jobs: queued -> failed
    j4 = await test_db.create_sync_job(f2)
    await test_db.update_sync_job(j4, UploadStatus.QUEUED)
    j5 = await test_db.create_sync_job(f2)
    await test_db.update_sync_job(j5, UploadStatus.FAILED)

    files = await test_db.get_music_files()
    assert len(files) == 2
    f1_res = next(f for f in files if f.id == f1)
    f2_res = next(f for f in files if f.id == f2)
    assert f1_res.upload_status == UploadStatus.VERIFIED
    assert f2_res.upload_status == UploadStatus.FAILED

    # Test filtering by status
    uploaded_files = await test_db.get_music_files(filter_status="uploaded")
    assert len(uploaded_files) == 1
    assert uploaded_files[0].id == f1

    failed_files = await test_db.get_music_files(filter_status="failed")
    assert len(failed_files) == 1
    assert failed_files[0].id == f2

    # Check dashboard counts
    counts = await test_db.get_dashboard_counts()
    assert counts["local_songs_count"] == 2
    assert counts["failed_count"] == 1
    assert counts["missing_count"] == 1  # f2 failed, so still missing
