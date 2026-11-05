import pytest
from ytm_service.normalizer import normalize_text, parse_duration, compute_metadata_hash

def test_normalize_text_case_and_punctuation():
    assert normalize_text("AC/DC") == "ac dc"
    assert normalize_text("Metallica - Master of Puppets") == "metallica master of puppets"

def test_normalize_text_removes_tags():
    assert normalize_text("Battery (Remastered 2016)") == "battery"
    assert normalize_text("Nutshell [Live at the Majestic Theatre]") == "nutshell"
    assert normalize_text("Song Title (Deluxe Edition)") == "song title"
    assert normalize_text("Hit Track feat. Drake") == "hit track"

def test_parse_duration():
    assert parse_duration("3:45") == 225.0
    assert parse_duration("1:02:30") == 3750.0
    assert parse_duration(180) == 180.0
    assert parse_duration("invalid") is None

def test_compute_metadata_hash_consistency():
    h1 = compute_metadata_hash("Tool", "Lateralus", "Schism", 406.0)
    h2 = compute_metadata_hash("TOOL", "Lateralus [Deluxe]", "Schism (Radio Edit)", 406.2)
    assert h1 == h2

def test_normalize_text_caching_and_edge_cases():
    # Test edge cases: None, empty string, whitespace only
    assert normalize_text(None) == ""
    assert normalize_text("") == ""
    assert normalize_text("   ") == ""

    # Test cache hits work as expected
    normalize_text.cache_clear()
    info_before = normalize_text.cache_info()
    assert info_before.hits == 0

    res1 = normalize_text("Radiohead - Creep (Remastered)")
    info_after_miss = normalize_text.cache_info()
    assert info_after_miss.hits == 0
    assert info_after_miss.misses >= 1

    res2 = normalize_text("Radiohead - Creep (Remastered)")
    info_after_hit = normalize_text.cache_info()
    assert info_after_hit.hits >= 1
    assert res1 == res2 == "radiohead creep"
