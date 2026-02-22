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
                                ┌─────────────────────────┐            ┌────────────────┐
                                │ results/<stem>-results  │ ◄───────────│  Summary JSON  │
                                │ .txt (per transcript)    │            └────────────────┘
                                └─────────────────────────┘
```

## Prerequisites

- **[uv](https://docs.astral.sh/uv/)** (recommended for install and run):
  ```bash
  # Install uv (Windows PowerShell, or see https://docs.astral.sh/uv/getting-started/installation/)
  powershell -ExecutionPolicy ByPass -c "irm https://astral.sh/uv/install.ps1 | iex"
  # Or on macOS/Linux: curl -LsSf https://astral.sh/uv/install.sh | sh
  ```
- **AWS CLI** configured (e.g. `aws sso login`) with access to:
  - S3 transcript bucket (from [transcription-demo-infra](transcription-demo-infra) deployment; **BucketName** stack output)
  - Amazon Transcribe (start/get transcription job)
  - Lambda summarization function (triggered by S3)
  - Bedrock (used inside the Lambda)
- **Python 3.9+** (uv will use it automatically)
- An **audio file** in WAV, MP3, or another [format supported by Transcribe](https://docs.aws.amazon.com/transcribe/latest/dg/supported-formats.html) (for the full pipeline only)

**AWS profile:** Scripts use the **PowerUser** profile by default (`--profile PowerUser`). If a command fails with a permission error, use a profile with broader access (e.g. `--profile administrator`).

**Bucket required:** You must pass **`--bucket BUCKET_NAME`** or set **`TRANSCRIPTION_DEMO_BUCKET`**. Get **BucketName** from your **TranscriptionDemoLambda-&lt;instance&gt;** stack output (after deploying [transcription-demo-infra](transcription-demo-infra)).

## Quick Start

Install dependencies and run with **uv** (creates a venv and installs from `pyproject.toml` if needed):

```bash
cd transcription-demo
uv sync
```

### 1. Transcript-only test (no audio)

Uses a sample transcript JSON so you can see the Lambda + Bedrock flow without Transcribe. Pass the **BucketName** from your TranscriptionDemoLambda stack (e.g. `transcription-demo-dev-ACCOUNT_ID`):

```bash
uv run python scripts/run_transcript_only.py --bucket <BucketName> --profile PowerUser
# Or: export TRANSCRIPTION_DEMO_BUCKET=<BucketName>
#     uv run python scripts/run_transcript_only.py --profile PowerUser
```

This uploads `sample-data/sample-transcript.json` to the bucket, waits for the Lambda to run, then downloads and prints the results file (`results/sample-transcript-results.txt`).

### 2. Full pipeline (audio → Transcribe → Lambda → summary)

Record or obtain a `.wav` (or other supported format), then:

```bash
# Put your audio in sample-data/ (e.g. sample-data/my-call.wav)
uv run python scripts/run_full_pipeline.py sample-data/my-call.wav --bucket <BucketName> --profile PowerUser
```

The script will:

1. Upload the audio to `s3://<BucketName>/audio/`
2. Start an Amazon Transcribe job with speaker labels
3. Set the job output key to `transcripts/<name>-transcript.json` so S3 triggers the Lambda
4. Poll until the Transcribe job completes
5. Wait a short time for the Lambda to run and write `results/<job>-transcript-results.txt`
6. Download and print the summary from that file

## Build and deploy (Makefile)

From the repo root you can build and deploy changed code:

```bash
make help          # List targets
make test          # Unit tests only
make build         # Bundle Lambda (lambda-src -> infra .lambda_bundle)
make deploy        # Build, upload zip, deploy Lambda stack (infra must already exist)
make deploy-full   # Bootstrap from scratch (Infra + Lambda)
make clean         # Remove Lambda bundle artifacts
```

Override defaults: `make deploy REGION=us-east-1 INSTANCE=dev AWS_PROFILE=PowerUser`.  
If deploy fails with an IAM permission error (e.g. `iam:GetRole`), use a profile with IAM access: `make deploy AWS_PROFILE=administrator`.

## Running tests

Use **`scripts/run_tests.sh`** to run unit tests and optionally the full pipeline on new audio files:

```bash
chmod +x scripts/run_tests.sh
# Full (unit tests + new files from audio dir → sample-data, then run pipeline for each)
./scripts/run_tests.sh
./scripts/run_tests.sh prod

# Partial (unit tests only, no AWS required)
./scripts/run_tests.sh --unit-only
./scripts/run_tests.sh -u
```

- **Full:** runs `uv run pytest tests/ -v`, then checks **AUDIO_SOURCE_DIR** (default: `/mnt/c/Users/darra/OneDrive/Documents/Audacity`) for audio files (e.g. .wav, .mp3) that are not yet in **sample-data**. Copies only those new files into **sample-data**, then runs the full pipeline (upload → Transcribe → Lambda → results) for each. Requires AWS credentials and the environment to be deployed. Override: `AUDIO_SOURCE_DIR=/path/to/audio ./scripts/run_tests.sh`.
- **Partial (`--unit-only` / `-u`):** runs only unit tests; no AWS or environment needed.

## Project layout

```
transcription-demo/
├── Makefile                  # Build and deploy (make deploy, make test, etc.)
├── README.md                 # This file
├── pyproject.toml            # Project and deps (uv sync / uv run)
├── requirements.txt          # Optional; same deps for pip users
├── lambda-src/               # Lambda source (Nova summarization); infra bundles from here
│   ├── lambda_function.py
│   ├── prompt_template.txt
│   └── requirements.txt
├── sample-data/
│   └── sample-transcript.json   # Minimal Transcribe-style JSON for transcript-only test
├── scripts/
│   ├── run_tests.sh             # Run unit tests + full pipeline on new files from audio dir
│   ├── run_transcript_only.py   # Upload sample transcript, fetch results/<stem>-results.txt
│   └── run_full_pipeline.py     # Upload audio → Transcribe → wait → fetch results file
└── transcription-demo-infra/   # IaC (CloudFormation) and deploy scripts
```

## Configuration

- **Bucket:** Required. Pass **`--bucket`** or set **`TRANSCRIPTION_DEMO_BUCKET`** to the **BucketName** from your **TranscriptionDemoLambda-&lt;instance&gt;** stack (see [transcription-demo-infra](transcription-demo-infra)).
- **Region:** `us-east-1` (default); override with **`--region`** or env **`AWS_REGION`**.

## Sample transcript format

The Lambda expects Amazon Transcribe–style JSON: a `results.items` array where each item has at least `alternatives[0].content`, and optionally `speaker_label` and `type` (e.g. `"pronunciation"` or `"punctuation"`). See `sample-data/sample-transcript.json` for a minimal example.
