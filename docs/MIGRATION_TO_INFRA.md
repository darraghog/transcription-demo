# Migration: Use infrastructure from transcription-demo-infra

Transcription-demo can run against **original infrastructure** (legacy bucket/Lambda) or against infrastructure defined and deployed by [transcription-demo-infra](../transcription-demo-infra) (CloudFormation: S3 bucket, Lambda, S3 trigger). This doc tracks migrating to the infra project.

## Stack names

- **TranscriptionDemoInfra-<instance>** (e.g. `TranscriptionDemoInfra-dev`) – Code bucket for Lambda zip, IAM role for Lambda.
- **TranscriptionDemoLambda-<instance>** (e.g. `TranscriptionDemoLambda-dev`) – Transcript S3 bucket, Lambda function, S3→Lambda trigger. Output **BucketName** is the transcript bucket used by the demo scripts.

## Todos

1. **Deploy transcription-demo-infra** – From repo root: `make deploy-full` (or from `transcription-demo-infra`: run [bootstrap.sh](../transcription-demo-infra/scripts/bootstrap.sh)). Requires a profile with sufficient IAM (e.g. AdministratorAccess). See [transcription-demo-infra README](../transcription-demo-infra/README.md).
2. **Point transcription-demo scripts to new infra** – Get **BucketName** from the **TranscriptionDemoLambda-<instance>** stack output. Set `--bucket <BucketName>` or `TRANSCRIPTION_DEMO_BUCKET=<BucketName>` when running scripts.
3. **Document or remove references to original infra** – Update README, defaults, and any docs that assume the old bucket/roles.
4. **Verify** – Run `transcription-demo-infra/scripts/verify_deployment.sh` and `uv run python scripts/run_transcript_only.py --bucket <BucketName>`. Optionally: `make test` and `./scripts/run_tests.sh` (full) or `./scripts/run_tests.sh --unit-only` (unit only).
5. **Retire original infrastructure** – After verification, decommission the original bucket/Lambda/roles if they are no longer needed.

## After migration

- All infrastructure is created and updated via **transcription-demo-infra** (CloudFormation).
- Demo scripts use the **BucketName** from **TranscriptionDemoLambda-<instance>**.
- Build/deploy from repo root: `make build`, `make deploy`, or `make deploy-full`.
