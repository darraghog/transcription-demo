# Transcription Demo – DevOps / IaC

Manages the **full DevOps lifecycle** for the [transcription-demo](../transcription-demo) app: S3 bucket, Lambda (Nova summarization), IAM, and S3→Lambda trigger. **Infrastructure** and **Lambda code** can be deployed **independently**.

> **Note:** CDK deployment is not fully working and requires further testing (e.g. bootstrap with AdministratorAccess, credential/profile handling, cleanup of failed CDKToolkit stacks). Use the instructions below as a starting point and validate in your environment.

## Deploy with CloudFormation (reliable alternative)

If CDK is unreliable in your environment (credentials, bootstrap, or toolchain issues), use the **CloudFormation** templates under `cloudformation/`. No CDK bootstrap or Node/Python CDK app is required; only the AWS CLI and a profile with sufficient IAM permissions.

1. **Bundle and upload Lambda code**
   - Create an S3 bucket (or use any existing bucket) to hold the Lambda zip.
   - From the repo root:
   ```bash
   ./scripts/bundle_lambda.sh
   CODE_BUCKET=your-code-bucket ./scripts/upload_lambda_zip.sh
   ```
   - Set `CODE_S3_KEY` from the script output (or use the printed key).

2. **Deploy both stacks**
   ```bash
   export CODE_BUCKET=your-code-bucket
   export CODE_S3_KEY=lambda/transcription-demo-summarize-YYYYMMDDHHMMSS.zip   # from upload step
   # Optional: INSTANCE=dev REGION=us-east-1 AWS_PROFILE=your-profile
   chmod +x scripts/deploy-cfn.sh && ./scripts/deploy-cfn.sh
   ```

3. **S3→Lambda trigger**  
   CloudFormation cannot add the notification in-template ([why: circular dependency](docs/S3_TRIGGER_WHY_SCRIPT.md)). **`deploy-cfn.sh` adds it automatically** after the Lambda stack is created. If you deploy the stack some other way, run once:
   ```bash
   BUCKET_NAME=<BucketName> LAMBDA_ARN=<Lambda ARN> REGION=us-east-1 ./scripts/add_s3_trigger.sh
   ```

After that, use the **BucketName** output with the [transcription-demo](../transcription-demo) scripts as in “Syncing with the transcription-demo app” below.

## Bootstrap an environment

One-command setup (CloudFormation path): bundle Lambda, upload to S3, deploy both stacks, add S3→Lambda trigger. Pass the **environment (instance) name** as the first argument; default is **dev**. Run from any directory (script changes to repo root).

**Prerequisites (clean environment):**

- **Bash** (scripts use `#!/usr/bin/env bash`)
- **AWS CLI** installed and configured (credentials or `AWS_PROFILE`)
- **Python 3** with **pip** or **uv** (for bundling Lambda dependencies)
- **zip** or **Python 3** (for creating the Lambda zip; script falls back to Python `zipfile` if `zip` is not installed)

Default **CODE_BUCKET** is `genai-training-bucket`; that bucket must exist in your target account, or set `CODE_BUCKET` to an existing S3 bucket before running.

```bash
cd transcription-demo-infra
chmod +x scripts/bootstrap.sh
# Bootstrap default environment (dev)
AWS_PROFILE=administrator ./scripts/bootstrap.sh
# Or specify environment: prod, staging, etc.
AWS_PROFILE=administrator ./scripts/bootstrap.sh prod
```

The bootstrap script adds the S3→Lambda trigger automatically after deploy; no separate step needed.

**Troubleshooting CloudFormation validation:** If a stack changeset fails with `AWS::EarlyValidation::PropertyValidation`, get the exact property error with:
```bash
aws cloudformation describe-events --stack-name <StackName> --filters FailedEvents=true --output json
```
Or use `--change-set-name <ChangeSetArn>` if you have the failed change set ARN. The response shows `ValidationPath` and `ValidationStatusReason` (e.g. unsupported property names).

**CDK path (if bootstrap works in your account):** Run once per account/region, then deploy dev:

```bash
cdk bootstrap aws://YOUR_ACCOUNT_ID/us-east-1 --profile administrator
./scripts/bundle_lambda.sh
cdk deploy --all -c instance=dev -c account=YOUR_ACCOUNT_ID -c region=us-east-1 --require-approval never
```

## Multiple instances (same region)

You can deploy several independent instances in one region (e.g. `dev`, `prod`, `customer-a`) by passing an **instance** name. Each instance gets its own stack pair and S3 bucket.

```bash
# Deploy instance "dev" (bucket name will be transcription-demo-dev-ACCOUNT_ID)
cdk deploy --all -c instance=dev --require-approval never

# Deploy instance "prod" with an explicit bucket name
cdk deploy --all -c instance=prod -c bucket_name=my-transcription-prod --require-approval never
```

Stack names become `TranscriptionDemoInfra-dev`, `TranscriptionDemoLambda-dev`, etc. The **BucketName** output is on the Lambda stack; use it with the demo scripts: `--bucket <value>`.

## What’s in this repo

| Stack | Contents | Deploy when |
|-------|----------|-------------|
| **TranscriptionDemoInfra** | IAM role (S3 + Bedrock); no dependency on Lambda stack | Permissions change |
| **TranscriptionDemoLambda** | S3 bucket, Lambda function (code + deps), S3 event notification | Bucket, Lambda code, or trigger change |

## Prerequisites

- **Python 3.9+** and **uv** (or pip)
- **AWS CDK CLI** (e.g. `npm install -g aws-cdk` or use `npx aws-cdk`)
- **AWS CLI** configured (e.g. `aws sso login --profile PowerUser`)
- **Enable** Amazon Nova (e.g. `amazon.nova-lite-v1:0`) in Bedrock → Model access in your account/region

## One-time setup

**CDK bootstrap** (once per account/region): run before the first deploy so CDK can stage assets (e.g. Lambda code). **Requires IAM permissions** (create/delete roles); the PowerUser permission set does *not* allow this—use a profile with AdministratorAccess (e.g. `administrator`) for bootstrap:

```bash
aws sso login --profile administrator
cdk bootstrap aws://YOUR_ACCOUNT_ID/us-east-1 --profile administrator
```
After bootstrap, you can deploy app stacks with PowerUser if your stacks don't need to create IAM roles; otherwise use the same admin profile for deploy.

Then install deps and bundle the Lambda:

```bash
cd transcription-demo-infra
uv sync
# Bundle Lambda (code + jinja2) for CDK asset
chmod +x scripts/bundle_lambda.sh && ./scripts/bundle_lambda.sh
```

## Deploy infrastructure only (IAM role)

Use when you change **IAM permissions** only. The bucket lives in the Lambda stack. For a non-default instance, add `-c instance=NAME`:

```bash
cdk deploy TranscriptionDemoInfra --require-approval never
# Or for instance "dev":
cdk deploy TranscriptionDemoInfra-dev --require-approval never
```

Optional: use an explicit bucket name when deploying the Lambda stack (e.g. to match transcription-demo scripts):

```bash
cdk deploy TranscriptionDemoLambda -c bucket_name=genai-training-bucket --require-approval never
```

## Deploy Lambda only (bucket, code, trigger)

Use when you change **bucket**, **Lambda code**, or **S3 trigger**:

```bash
./scripts/bundle_lambda.sh   # required after any lambda/ or lambda/requirements.txt change
cdk deploy TranscriptionDemoLambda --require-approval never
```

CDK will only update the Lambda asset and related resources; the infra stack is unchanged.

## Deploy everything

First time or after changing both infra and Lambda:

```bash
./scripts/bundle_lambda.sh
cdk deploy --all --require-approval never
```

**If CDK reports "Unable to resolve AWS account" or "no credentials have been configured":** Use the deploy wrapper so only your profile is used (it unsets credential env vars and sets `AWS_PROFILE`):

```bash
# Deploy with administrator profile (no account/region needed if profile works)
AWS_PROFILE=administrator ./scripts/cdk-deploy.sh --all --require-approval never

# If that still fails, pass account so CDK doesn't need to resolve it
CDK_ACCOUNT=YOUR_ACCOUNT_ID AWS_PROFILE=administrator ./scripts/cdk-deploy.sh --all --require-approval never
```
Replace `YOUR_ACCOUNT_ID` with your 12-digit account ID (e.g. from `aws sts get-caller-identity --profile administrator --query Account --output text`).

## Syncing with the transcription-demo app

After deploy, **TranscriptionDemoLambda** outputs **BucketName**. Use it when running the [transcription-demo](../transcription-demo) scripts:

```bash
# Option 1: pass bucket explicitly
uv run python scripts/run_transcript_only.py --bucket <BucketName>

# Option 2: set default via env (e.g. for one instance)
export TRANSCRIPTION_DEMO_BUCKET=<BucketName>
uv run python scripts/run_transcript_only.py
```

For multiple instances, pass `--bucket` per run or set `TRANSCRIPTION_DEMO_BUCKET` to the instance’s bucket.

## Demo runner role

The Lambda stack creates a **DemoRunner** IAM role with permissions to run the demo (S3 access to the transcript bucket and Amazon Transcribe for the full pipeline). Users do not need PowerUser or Administrator; they can assume this role instead.

**Stack output:** `DemoRunnerRoleArn` (e.g. `arn:aws:iam::ACCOUNT:role/transcription-demo-DemoRunner`).

**1. Allow a user or group to assume the role**

Attach an IAM policy to the user (or their group) that allows assuming the role:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": "sts:AssumeRole",
      "Resource": "<DemoRunnerRoleArn from stack output>"
    }
  ]
}
```

**2. Run the demo using the role**

Assume the role, then run the demo with the temporary credentials (or use a profile that assumes the role):

```bash
# Assume role and get temporary credentials (Linux/macOS)
eval $(aws sts assume-role --role-arn <DemoRunnerRoleArn> --role-session-name demo --query 'Credentials.[AccessKeyId,SecretAccessKey,SessionToken]' --output text | awk '{print "export AWS_ACCESS_KEY_ID="$1"\nexport AWS_SECRET_ACCESS_KEY="$2"\nexport AWS_SESSION_TOKEN="$3}')
uv run python scripts/run_transcript_only.py --bucket <BucketName>
```

Alternatively, add a profile to `~/.aws/config` that uses `role_arn` and `source_profile` so the CLI assumes the role automatically when you use that profile.

## Verify deployment

1. **Unit tests** (no AWS, from `transcription-demo`):
   ```bash
   cd ../transcription-demo && uv run pytest tests/ -v
   ```

2. **Live verification** (after deploy; uses stack output and runs transcript-only demo):
   ```bash
   chmod +x scripts/verify_deployment.sh
   AWS_PROFILE=administrator ./scripts/verify_deployment.sh
   ```
   For a non-default instance: `INSTANCE=dev AWS_PROFILE=administrator ./scripts/verify_deployment.sh`

## Project layout

```
transcription-demo-infra/
├── app.py                          # CDK app entry
├── cdk.json
├── pyproject.toml / requirements.txt
├── cloudformation/                 # CloudFormation (alternative to CDK)
│   ├── infra-stack.yaml
│   └── lambda-stack.yaml
├── lambda/                         # Lambda source (keep in sync with transcription-demo/lambda-src if desired)
│   ├── lambda_function.py
│   ├── prompt_template.txt
│   └── requirements.txt
├── scripts/
│   ├── bootstrap.sh               # Bundle, upload, deploy CF stacks, add S3 trigger (any env)
│   ├── bundle_lambda.sh           # Builds .lambda_bundle for CDK asset
│   ├── upload_lambda_zip.sh       # Zip and upload for CloudFormation deploy
│   ├── deploy-cfn.sh              # Deploy infra + Lambda via CloudFormation
│   └── add_s3_trigger.sh           # Add S3→Lambda trigger after CF deploy
├── transcription_demo_infra/
│   ├── infra_stack.py             # IAM role
│   └── lambda_stack.py            # Bucket + Lambda + S3 trigger
└── README.md
```

## Summary

- **Infra changes** → `cdk deploy TranscriptionDemoInfra`
- **Lambda/code changes** → `./scripts/bundle_lambda.sh` then `cdk deploy TranscriptionDemoLambda`
- **Both** → `./scripts/bundle_lambda.sh` then `cdk deploy --all`
