# End-to-End Transcription Demo

Demonstrates the full pipeline for **LambdaFunctionSummarize**: audio → Amazon Transcribe → transcript JSON → Lambda (S3-triggered) → Bedrock summarization → results.

## Architecture

```
┌─────────────┐     upload      ┌─────────────┐    Transcribe job     ┌──────────────────┐
│  Your .wav  │ ──────────────► │     S3      │ ───────────────────► │ *-transcript.json│
└─────────────┘                 │  (bucket)   │                      └────────┬─────────┘
                                └──────┬──────┘                               │
                                       │                                      │ S3 trigger
                                       │                                      ▼
                                       │                             ┌────────────────┐
                                       │                             │    Lambda      │
                                       │                             │ (Summarize +   │
                                       │                             │  Bedrock)      │
                                       │                             └────────┬───────┘
                                       │                                      │
                                       │ put_object                            │
                                       ▼                                      ▼
                                ┌─────────────┐                      ┌────────────────┐
                                │ results.txt │ ◄─────────────────────│  Summary JSON  │
                                └─────────────┘                      └────────────────┘
```

## Prerequisites

- **[uv](https://docs.astral.sh/uv/)** (recommended for install and run):
  ```bash
  # Install uv (Windows PowerShell, or see https://docs.astral.sh/uv/getting-started/installation/)
  powershell -ExecutionPolicy ByPass -c "irm https://astral.sh/uv/install.ps1 | iex"
  # Or on macOS/Linux: curl -LsSf https://astral.sh/uv/install.sh | sh
  ```
- **AWS CLI** configured (e.g. `aws sso login`) with access to:
  - S3 bucket: `genai-training-bucket`
  - Amazon Transcribe (start/get transcription job)
  - Lambda **LambdaFunctionSummarize** (triggered by S3)
  - Bedrock (used inside the Lambda)
- **Python 3.9+** (uv will use it automatically)
- An **audio file** in WAV, MP3, or another [format supported by Transcribe](https://docs.aws.amazon.com/transcribe/latest/dg/supported-formats.html) (for the full pipeline only)

**AWS profile:** Scripts use the **PowerUser** profile by default (`--profile PowerUser`). If a command fails with a permission error, use a profile with broader access (e.g. `--profile administrator`).

## Quick Start

Install dependencies and run with **uv** (creates a venv and installs from `pyproject.toml` if needed):

```bash
cd transcription-demo
uv sync
```

### 1. Transcript-only test (no audio)

Uses a sample transcript JSON so you can see the Lambda + Bedrock flow without Transcribe:

```bash
uv run python scripts/run_transcript_only.py --profile PowerUser
```

This uploads `sample-data/sample-transcript.json` to S3, waits for the Lambda to run, then downloads and prints `results.txt`.

### 2. Full pipeline (audio → Transcribe → Lambda → summary)

Record or obtain a `.wav` (or other supported format), then:

```bash
# Put your audio in sample-data/ (e.g. sample-data/my-call.wav)
uv run python scripts/run_full_pipeline.py sample-data/my-call.wav --profile PowerUser
```

The script will:

1. Upload the audio to `s3://genai-training-bucket/audio/`
2. Start an Amazon Transcribe job with speaker labels
3. Set the job output key to `transcripts/<name>-transcript.json` so S3 triggers the Lambda
4. Poll until the Transcribe job completes
5. Wait a short time for the Lambda to run and write `results.txt`
6. Download and print the summary from `results.txt`

## Project layout

```
transcription-demo/
├── README.md                 # This file
├── pyproject.toml             # Project and deps (uv sync / uv run)
├── requirements.txt          # Optional; same deps for pip users
├── sample-data/
│   └── sample-transcript.json   # Minimal Transcribe-style JSON for transcript-only test
└── scripts/
    ├── run_transcript_only.py   # Upload sample transcript, fetch results.txt
    └── run_full_pipeline.py    # Upload audio → Transcribe → wait → fetch results.txt
```

## Configuration

Scripts use:

- **Bucket:** `genai-training-bucket` (hardcoded to match the Lambda’s S3 trigger).
- **Region:** `us-east-1` (default in scripts; override with env `AWS_REGION` or CLI config).

To use another bucket, you’d need to add an S3 trigger for **LambdaFunctionSummarize** on that bucket and update the bucket name in the scripts.

## Sample transcript format

The Lambda expects Amazon Transcribe–style JSON: a `results.items` array where each item has at least `alternatives[0].content`, and optionally `speaker_label` and `type` (e.g. `"pronunciation"` or `"punctuation"`). See `sample-data/sample-transcript.json` for a minimal example.
