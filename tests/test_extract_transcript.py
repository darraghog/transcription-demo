"""Unit tests for Lambda transcript extraction (Transcribe-style JSON → speaker text)."""
import json
import sys
from pathlib import Path
from unittest.mock import MagicMock

import pytest

# Mock boto3 before importing Lambda (Lambda creates S3/Bedrock clients at import time)
_original_boto3 = sys.modules.get("boto3")
sys.modules["boto3"] = MagicMock()
LAMBDA_SRC = Path(__file__).resolve().parent.parent / "lambda-src"
sys.path.insert(0, str(LAMBDA_SRC))
import lambda_function as lambda_module
sys.path.pop(0)
if _original_boto3 is not None:
    sys.modules["boto3"] = _original_boto3
else:
    sys.modules.pop("boto3", None)

extract = lambda_module.extract_transcript


def test_empty_items_returns_empty_string():
    payload = {"results": {"items": []}}
    assert extract(json.dumps(payload)) == ""


def test_single_word_no_speaker():
    payload = {
        "results": {
            "items": [
                {"type": "pronunciation", "alternatives": [{"content": "Hello"}], "speaker_label": None}
            ]
        }
    }
    assert extract(json.dumps(payload)) == "Hello "


def test_speaker_labels_and_punctuation():
    payload = {
        "results": {
            "items": [
                {"type": "pronunciation", "alternatives": [{"content": "Hello"}], "speaker_label": "SPEAKER_00"},
                {"type": "pronunciation", "alternatives": [{"content": "thanks"}], "speaker_label": "SPEAKER_00"},
                {"type": "punctuation", "alternatives": [{"content": "."}]},
                {"type": "pronunciation", "alternatives": [{"content": "How"}], "speaker_label": "SPEAKER_01"},
                {"type": "pronunciation", "alternatives": [{"content": "can"}], "speaker_label": "SPEAKER_01"},
                {"type": "punctuation", "alternatives": [{"content": "?"}]},
            ]
        }
    }
    out = extract(json.dumps(payload))
    assert "SPEAKER_00: Hello thanks." in out or "SPEAKER_00: Hello thanks ." in out
    assert "SPEAKER_01: How can?" in out or "SPEAKER_01: How can ?" in out


def test_punctuation_strips_trailing_space():
    payload = {
        "results": {
            "items": [
                {"type": "pronunciation", "alternatives": [{"content": "Hi"}], "speaker_label": "SPEAKER_00"},
                {"type": "punctuation", "alternatives": [{"content": "."}]},
            ]
        }
    }
    out = extract(json.dumps(payload))
    # Punctuation is appended without extra space before it (trailing space before . is stripped)
    assert "Hi." in out
    assert out.strip().endswith(".")


def test_missing_speaker_label_uses_content_only():
    payload = {
        "results": {
            "items": [
                {"type": "pronunciation", "alternatives": [{"content": "Word"}], "speaker_label": None},
            ]
        }
    }
    assert "Word " in extract(json.dumps(payload))
