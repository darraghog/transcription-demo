# Transcription-demo-infra – related todos

These align with [transcription-demo’s migration](../transcription-demo/docs/MIGRATION_TO_INFRA.md) to use this project’s infrastructure instead of the original, non-CDK infra.

1. **Fix CDK bootstrap/deploy** – Resolve bootstrap (AdministratorAccess, CDKToolkit cleanup) and credential/profile handling so `cdk deploy --all` succeeds. CDK deployment is not fully working yet (see README note).
2. **Document consumption by transcription-demo** – Clearly document the **BucketName** stack output and how to set `--bucket` or `TRANSCRIPTION_DEMO_BUCKET` so the demo scripts target this infra.
3. **Verify deployment** – After first successful deploy, run `scripts/verify_deployment.sh` and confirm the transcript-only demo runs against the new bucket.
4. **Stay aligned with migration** – When transcription-demo migrates (scripts pointed at this bucket, original infra retired), ensure this repo’s README and outputs remain the single source of truth for the demo.
