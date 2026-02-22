# Migration: Use infrastructure from transcription-demo-infra

Transcription-demo currently runs against **original infrastructure** (not created by the [transcription-demo-infra](../transcription-demo-infra) project). This doc tracks migrating to infra defined and deployed by transcription-demo-infra (CloudFormation: S3 bucket, Lambda, S3 trigger).

## Todos

1. **Deploy transcription-demo-infra** – Bootstrap (with AdministratorAccess), then deploy Infra + Lambda stacks. See transcription-demo-infra README.
2. **Point transcription-demo scripts to new infra** – Use bucket name from CloudFormation stack output (`TranscriptionDemoLambda` → BucketName). Set `--bucket` or `TRANSCRIPTION_DEMO_BUCKET` in scripts/env.
3. **Document or remove references to original infra** – Update README, defaults, and any docs that assume the old bucket/roles.
4. **Verify** – Run `transcription-demo-infra/scripts/verify_deployment.sh` and `run_transcript_only.py` against the new bucket.
5. **Retire original infrastructure** – After verification, decommission the original bucket/Lambda/roles if they are no longer needed.

## After migration

- All infrastructure will be created and updated via `transcription-demo-infra` (CloudFormation).
- Demo scripts will target the bucket (and region) produced by that project’s deployment.
