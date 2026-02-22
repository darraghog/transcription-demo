"""Unit tests for Lambda handler: key filter, S3/Bedrock mocks, error handling."""
import json
import sys
from pathlib import Path
from unittest.mock import MagicMock, patch

import pytest

# Mock boto3 before importing Lambda
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


def _s3_event(bucket: str, key: str):
    return {
        "Records": [
            {
                "s3": {
                    "bucket": {"name": bucket},
                    "object": {"key": key},
                }
            }
        ]
    }


def test_handler_skips_key_without_transcript_suffix():
    event = _s3_event("my-bucket", "results.txt")
    out = lambda_module.lambda_handler(event, None)
    assert out is None


def test_handler_success_returns_200_and_writes_results_txt():
    bucket, key = "my-bucket", "demo/sample-transcript.json"
    event = _s3_event(bucket, key)
    sample_transcript = json.dumps({
        "results": {"items": [
            {"type": "pronunciation", "alternatives": [{"content": "Hi"}], "speaker_label": "SPEAKER_00"},
            {"type": "punctuation", "alternatives": [{"content": "."}]},
        ]}
    })
    fake_summary = "Summary: greeting only."

    with patch.object(lambda_module, "s3_client") as s3_mock:
        with patch.object(lambda_module, "bedrock_summarisation", return_value=fake_summary):
            s3_mock.get_object.return_value = {"Body": MagicMock(read=MagicMock(return_value=sample_transcript.encode("utf-8")))}
            result = lambda_module.lambda_handler(event, None)

    assert result["statusCode"] == 200
    s3_mock.put_object.assert_called_once()
    call_kw = s3_mock.put_object.call_args.kwargs
    assert call_kw["Bucket"] == bucket
    assert call_kw["Key"] == "results/sample-transcript-results.txt"
    assert call_kw["Body"] == fake_summary
    assert call_kw["ContentType"] == "text/plain"


def test_handler_s3_get_error_returns_500():
    event = _s3_event("my-bucket", "demo/foo-transcript.json")
    with patch.object(lambda_module, "s3_client") as s3_mock:
        s3_mock.get_object.side_effect = Exception("NoSuchKey")
        result = lambda_module.lambda_handler(event, None)

    assert result["statusCode"] == 500
    assert "Error occurred" in result["body"]
