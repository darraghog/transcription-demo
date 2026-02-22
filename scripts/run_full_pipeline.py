#!/usr/bin/env python3
"""
Full pipeline: upload audio to S3 → start Transcribe job (output to *-transcript.json)
→ S3 triggers Lambda → Lambda writes results/<stem>-results.txt. We wait and download that file.
"""
import argparse
import os
import sys
import time
from datetime import datetime
from pathlib import Path

import boto3

DEFAULT_BUCKET = os.environ.get("TRANSCRIPTION_DEMO_BUCKET", "")
AUDIO_PREFIX = "audio"
BUCKET_HELP = "S3 bucket name (transcript bucket from TranscriptionDemoLambda stack). Set TRANSCRIPTION_DEMO_BUCKET or pass --bucket."
TRANSCRIPT_PREFIX = "transcripts"
RESULTS_PREFIX = "results/"
REGION = "us-east-1"
# Transcribe supported formats: wav, mp3, mp4, wb-amr, flac, ogg, amr, webm, m4a, etc.
SUPPORTED_EXTENSIONS = {".wav", ".mp3", ".mp4", ".m4a", ".flac", ".ogg", ".webm", ".amr", ".wma"}


def main() -> None:
    parser = argparse.ArgumentParser(description="Run full pipeline: audio → Transcribe → Lambda → results")
    parser.add_argument(
        "audio_path",
        type=Path,
        help="Path to audio file (e.g. .wav, .mp3)",
    )
    parser.add_argument(
        "--job-name",
        type=str,
        default=None,
        help="Transcribe job name (default: demo-<stem>-<timestamp> to avoid conflicts)",
    )
    parser.add_argument(
        "--wait-results-seconds",
        type=int,
        default=90,
        help="Max seconds to wait for results file after Transcribe completes (default 90)",
    )
    parser.add_argument(
        "--region",
        default=REGION,
        help="AWS region (default %s)" % REGION,
    )
    parser.add_argument(
        "--profile",
        default="PowerUser",
        help="AWS profile name (default: PowerUser). Use administrator if you hit permission errors.",
    )
    parser.add_argument(
        "--bucket",
        default=DEFAULT_BUCKET,
        help=BUCKET_HELP,
    )
    args = parser.parse_args()

    bucket = (args.bucket or "").strip()
    if not bucket:
        print(
            "Error: bucket is required. Get BucketName from your TranscriptionDemoLambda stack output, then run:\n"
            "  uv run python scripts/run_full_pipeline.py <audio.wav> --bucket <BucketName>\n"
            "  or set TRANSCRIPTION_DEMO_BUCKET=<BucketName>",
            file=sys.stderr,
        )
        sys.exit(1)

    audio_path = args.audio_path
    if not audio_path.exists():
        print("Error: audio file not found:", audio_path, file=sys.stderr)
        sys.exit(1)

    suffix = audio_path.suffix.lower()
    if suffix not in SUPPORTED_EXTENSIONS:
        print("Warning: extension %s may not be supported by Transcribe. Common: .wav, .mp3, .m4a" % suffix, file=sys.stderr)

    # Default job name includes timestamp to avoid "job name already exists" on re-runs
    base = audio_path.stem.replace(" ", "-")[:40]
    job_name = args.job_name or ("demo-%s-%s" % (base, datetime.utcnow().strftime("%Y%m%d%H%M%S")))
    # Output key must contain "-transcript.json" so the Lambda processes it
    output_key = "%s/%s-transcript.json" % (TRANSCRIPT_PREFIX, job_name)
    s3_audio_key = "%s/%s%s" % (AUDIO_PREFIX, job_name, suffix)

    session = boto3.Session(profile_name=args.profile)
    s3 = session.client("s3", region_name=args.region)
    transcribe = session.client("transcribe", region_name=args.region)

    print("Uploading audio to s3://%s/%s" % (bucket, s3_audio_key))
    s3.upload_file(str(audio_path), bucket, s3_audio_key)
    media_uri = "s3://%s/%s" % (bucket, s3_audio_key)

    print("Starting Transcribe job: %s (output: s3://%s/%s)" % (job_name, bucket, output_key))
    transcribe.start_transcription_job(
        TranscriptionJobName=job_name,
        LanguageCode="en-US",
        MediaFormat=suffix.lstrip(".") if suffix != ".wb-amr" else "amr",
        Media={"MediaFileUri": media_uri},
        Settings={"ShowSpeakerLabels": True, "MaxSpeakerLabels": 10},
        OutputBucketName=bucket,
        OutputKey=output_key,
    )

    print("Waiting for Transcribe job to complete...")
    while True:
        job = transcribe.get_transcription_job(TranscriptionJobName=job_name)
        status = job["TranscriptionJob"]["TranscriptionJobStatus"]
        if status == "COMPLETED":
            print("Transcribe job completed. Lambda will be triggered by new object.")
            break
        if status == "FAILED":
            reason = job["TranscriptionJob"].get("FailureReason", "Unknown")
            print("Transcribe job failed:", reason, file=sys.stderr)
            sys.exit(1)
        time.sleep(5)

    # Lambda writes to results/<transcript-stem>-results.txt
    results_key = "%s%s-transcript-results.txt" % (RESULTS_PREFIX, job_name)
    print("Waiting for Lambda to run and write %s (up to %s s)..." % (results_key, args.wait_results_seconds))
    start = time.time()
    while time.time() - start < args.wait_results_seconds:
        try:
            resp = s3.get_object(Bucket=bucket, Key=results_key)
            body = resp["Body"].read().decode("utf-8")
            elapsed = time.time() - start
            print("\n--- %s (after %.1f s) ---\n%s" % (results_key, elapsed, body))
            return
        except s3.exceptions.NoSuchKey:
            time.sleep(3)
            continue

    print("Timeout: %s not found after %s seconds. Check Lambda logs or S3." % (results_key, args.wait_results_seconds), file=sys.stderr)
    sys.exit(1)


if __name__ == "__main__":
    main()
