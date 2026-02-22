# Transcription-demo-infra – related todos

These align with [transcription-demo's migration](../docs/MIGRATION_TO_INFRA.md) to use this project's infrastructure instead of the original, non–CloudFormation infra.

1. **Document consumption by transcription-demo** – Clearly document the **BucketName** stack output and how to set `--bucket` or `TRANSCRIPTION_DEMO_BUCKET` so the demo scripts target this infra.
2. **Verify deployment** – After first successful deploy, run `scripts/verify_deployment.sh` and confirm the transcript-only demo runs against the new bucket.
3. **Stay aligned with migration** – When transcription-demo migrates (scripts pointed at this bucket, original infra retired), ensure this repo's README and outputs remain the single source of truth for the demo.
