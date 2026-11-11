import pytest
from ytm_service.matcher import evaluate_match
from ytm_service.models import MatchType

def test_evaluate_match_exact():
    m_type, score = evaluate_match(
        local_artist="Metallica",
        local_album="Master of Puppets",
        local_title="Battery",
        local_duration=312.4,
        ytm_artist="Metallica",
        ytm_album="Master of Puppets",
        ytm_title="Battery",
        ytm_duration=312.0
    )
    assert m_type == MatchType.EXACT
    assert score == 1.0

def test_evaluate_match_case_differences():
    m_type, score = evaluate_match(
        local_artist="ac/dc",
        local_album="BACK IN BLACK",
        local_title="HELLS BELLS",
        local_duration=312.0,
        ytm_artist="AC/DC",
        ytm_album="Back in Black",
        ytm_title="Hells Bells",
        ytm_duration=312.0
    )
    assert m_type == MatchType.EXACT
    assert score == 1.0

def test_evaluate_match_remasters():
    m_type, score = evaluate_match(
        local_artist="Nirvana",
        local_album="Nevermind [20th Anniversary Edition]",
        local_title="Smells Like Teen Spirit (Remastered 2011)",
        local_duration=301.0,
        ytm_artist="Nirvana",
        ytm_album="Nevermind",
        ytm_title="Smells Like Teen Spirit",
        ytm_duration=301.2
    )
    assert m_type == MatchType.EXACT
    assert score == 1.0

def test_evaluate_match_strong_different_album():
    m_type, score = evaluate_match(
        local_artist="Tool",
        local_album="Lateralus",
        local_title="Schism",
        local_duration=406.0,
        ytm_artist="Tool",
        ytm_album="Greatest Hits",
        ytm_title="Schism",
        ytm_duration=406.5
    )
    assert m_type == MatchType.STRONG
    assert score == 0.85

def test_evaluate_match_different_durations_live_version():
    # Live or extended version with major duration mismatch should not match studio track
    m_type, score = evaluate_match(
        local_artist="Pink Floyd",
        local_album="Pulse (Live)",
        local_title="Comfortably Numb",
        local_duration=575.0, # 9:35
        ytm_artist="Pink Floyd",
        ytm_album="The Wall",
        ytm_title="Comfortably Numb",
        ytm_duration=382.0  # 6:22
    )
    assert m_type != MatchType.EXACT
    assert score < 0.85

def test_evaluate_match_weak_similar():
    m_type, score = evaluate_match(
        local_artist="Alice in Chains",
        local_album="Jar of Flies",
        local_title="Nutshell",
        local_duration=259.0,
        ytm_artist="Alice in Chains (Tribute)",
        ytm_album="Tribute Album",
        ytm_title="Nutshell Acoustic",
        ytm_duration=250.0
    )
    assert m_type in (MatchType.WEAK, MatchType.NONE)

def test_evaluate_match_no_match():
    m_type, score = evaluate_match(
        local_artist="Pantera",
        local_album="Vulgar Display of Power",
        local_title="Walk",
        local_duration=314.0,
        ytm_artist="Slayer",
        ytm_album="Reign in Blood",
        ytm_title="Raining Blood",
        ytm_duration=254.0
    )
    assert m_type == MatchType.NONE
    assert score < 0.5

def test_evaluate_match_edge_cases_and_length_pruning():
    # Length pruning where (2 * min) / sum < 0.6
    m_type, score = evaluate_match(
        local_artist="Extremely Long Artist Name For Testing Length Ratio Pruning",
        local_album="Album",
        local_title="Song Title",
        local_duration=180.0,
        ytm_artist="Short",
        ytm_album="Album",
        ytm_title="Song Title",
        ytm_duration=180.0
    )
    assert m_type == MatchType.NONE
    assert score == 0.0

    # None / empty strings
    m_type_none, score_none = evaluate_match(None, None, "Track", 200.0, None, None, "Track", 200.0)
    assert m_type_none == MatchType.EXACT
    assert score_none == 1.0

    m_type_empty, score_empty = evaluate_match("", "", "Track", 200.0, "", "", "Track", 200.0)
    assert m_type_empty == MatchType.EXACT
    assert score_empty == 1.0

def test_evaluate_match_negative_pairs_skip_title_similarity():
    from unittest.mock import patch
    import ytm_service.matcher as matcher_mod

    pairs = [
        (("The Beatles", "Abbey Road", "Come Together", 259.0), ("Queen", "A Night at the Opera", "Bohemian Rhapsody", 354.0)),
        (("Led Zeppelin", "Led Zeppelin IV", "Stairway to Heaven", 482.0), ("Pink Floyd", "The Wall", "Comfortably Numb", 382.0)),
        (("Michael Jackson", "Thriller", "Billie Jean", 294.0), ("Prince", "Purple Rain", "Purple Rain", 520.0)),
        (("Radiohead", "OK Computer", "Karma Police", 261.0), ("Nirvana", "Nevermind", "Smells Like Teen Spirit", 301.0)),
    ]

    real_sim = matcher_mod.string_similarity
    for local_args, ytm_args in pairs:
        with patch.object(matcher_mod, "string_similarity", side_effect=real_sim) as spy:
            m_type, score = evaluate_match(*local_args, *ytm_args)
        assert m_type == MatchType.NONE
        assert score == 0.0
        # At most the artist comparison runs; title similarity must be skipped
        assert spy.call_count <= 1, f"{local_args[0]} vs {ytm_args[0]}: {spy.call_args_list}"
