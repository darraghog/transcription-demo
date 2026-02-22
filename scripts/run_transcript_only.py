#!/usr/bin/env python3
"""
Upload the sample transcript JSON to S3, wait for Lambda to run, then download and print the results file.
Results are written to results/<transcript-stem>-results.txt. No audio or Transcribe step.
"""
import argparse
import json
import sys
import time
from pathlib import Path

import os
import boto3

DEFAULT_BUCKET = os.environ.get("TRANSCRIPTION_DEMO_BUCKET", "")
REGION = "us-east-1"
# Key must contain "-transcript.json" for the Lambda to process it
TRANSCRIPT_KEY = "demo/sample-transcript.json"
# Lambda writes to results/<transcript-stem>-results.txt
RESULTS_KEY = "results/" + Path(TRANSCRIPT_KEY).stem + "-results.txt"
BUCKET_HELP = "S3 bucket name (transcript bucket from TranscriptionDemoLambda stack). Set TRANSCRIPTION_DEMO_BUCKET or pass --bucket."


def main() -> None:
    parser = argparse.ArgumentParser(description="Run transcript-only demo (no Transcribe)")
    parser.add_argument(
        "--transcript",
        type=Path,
        default=Path(__file__).resolve().parent.parent / "sample-data" / "sample-transcript.json",
        help="Path to transcript JSON file",
    )
    parser.add_argument(
        "--wait-seconds",
        type=int,
        default=30,
        help="Max seconds to wait for results file after upload (default 30)",
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
            "  uv run python scripts/run_transcript_only.py --bucket <BucketName>\n"
            "  or set TRANSCRIPTION_DEMO_BUCKET=<BucketName>",
            file=sys.stderr,
        )
        sys.exit(1)

    transcript_path = args.transcript
    if not transcript_path.exists():
        print("Error: transcript file not found:", transcript_path, file=sys.stderr)
        sys.exit(1)

    session = boto3.Session(profile_name=args.profile)
    s3 = session.client("s3", region_name=args.region)

    # Load and validate minimal structure
    with open(transcript_path, encoding="utf-8") as f:
        data = json.load(f)
    if "results" not in data or "items" not in data.get("results", {}):
        print("Error: transcript must have results.items (Transcribe-style JSON)", file=sys.stderr)
        sys.exit(1)

    print("Uploading", transcript_path.name, "to s3://%s/%s" % (bucket, TRANSCRIPT_KEY))
    s3.upload_file(str(transcript_path), bucket, TRANSCRIPT_KEY, ExtraArgs={"ContentType": "application/json"})

    # Lambda is triggered by S3; it reads the file and writes to results/<stem>-results.txt
    print("Waiting for Lambda to run and write %s (up to %s s)..." % (RESULTS_KEY, args.wait_seconds))
    start = time.time()
    while time.time() - start < args.wait_seconds:
        try:
            resp = s3.get_object(Bucket=bucket, Key=RESULTS_KEY)
            body = resp["Body"].read().decode("utf-8")
            elapsed = time.time() - start
            print("\n--- %s (after %.1f s) ---\n%s" % (RESULTS_KEY, elapsed, body))
            return
        except s3.exceptions.NoSuchKey:
            time.sleep(2)
            continue

    print("Timeout: %s not found after %s seconds. Check Lambda logs or S3." % (RESULTS_KEY, args.wait_seconds), file=sys.stderr)
    sys.exit(1)


if __name__ == "__main__":
    main()
