# Unit tests for transcription-demo Python

## How to run

From the **transcription-demo** repo root:

```bash
uv run pytest tests/ -v
# or
make test
```

For unit tests only (no AWS or deployed environment):

```bash
./scripts/run_tests.sh --unit-only
# or
./scripts/run_tests.sh -u
```

See [README – Running tests](../README.md#running-tests) for the full test script (unit tests + optional pipeline runs on new audio).

## What we test

| Component | Testable behavior | Strategy |
|-----------|-------------------|----------|
| **Lambda: `extract_transcript`** | JSON → speaker-labeled text | Pure function: no mocks. Feed Transcribe-style JSON, assert output string. |
| **Lambda: `lambda_handler`** | Key filter, S3 read, Bedrock call, S3 write, error handling | Mock `s3_client` and `bedrock_runtime`; assert calls and return values. |
| **Lambda: `bedrock_summarisation`** | Prompt build, response parsing | Mock `bedrock_runtime.converse`; optionally assert prompt contains transcript/topics. |
| **Script: `run_transcript_only`** | Transcript validation (results.items), bucket/key used | Mock boto3 S3; assert upload key, content-type; validate rejects bad JSON. |
| **Script: `run_full_pipeline`** | Job name derivation, bucket/key construction | Unit test job name and key logic with fixed time or args; mock Transcribe/S3 for integration. |

## Test files

| File | Coverage |
|------|----------|
| **`tests/test_extract_transcript.py`** | `extract_transcript`: empty items, with/without speaker labels, punctuation handling. |
| **`tests/test_lambda_handler.py`** | `lambda_handler`: skip non-transcript key; success path (mocked S3 + Bedrock); S3 error → 500. |
| **`tests/test_run_transcript_only.py`** | Script validation: rejects JSON without `results` or without `results.items`. |
