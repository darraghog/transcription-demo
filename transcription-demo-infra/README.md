# Transcription Demo – DevOps / IaC

Manages the **full DevOps lifecycle** for the [transcription-demo](..) app: S3 bucket, Lambda (Nova summarization), IAM, and S3→Lambda trigger. Deployment uses **CloudFormation** only (AWS CLI + YAML templates). **Infrastructure** and **Lambda code** can be deployed **independently**.

## Prerequisites

- **Bash** (scripts use `#!/usr/bin/env bash`)
- **AWS CLI** installed and configured (e.g. `aws sso login --profile PowerUser`)
- **Python 3** with **pip** or **uv** (for bundling Lambda dependencies in `bundle_lambda.sh`)
- **zip** or **Python 3** (for creating the Lambda zip; script falls back to Python `zipfile` if `zip` is not installed)
- **Enable** Amazon Nova (e.g. `amazon.nova-lite-v1:0`) in Bedrock → Model access in your account/region

## Deploy with CloudFormation

### 1. Deploy Infra stack (creates code bucket + IAM role)

Deploy the Infra stack first so the **code bucket** exists (name: `code-bucket-<instance>-<account-id>`):

```bash
cd transcription-demo-infra
aws cloudformation deploy \
  --template-file cloudformation/infra-stack.yaml \
  --stack-name TranscriptionDemoInfra-dev \
  --parameter-overrides "Instance=dev" \
  --capabilities CAPABILITY_NAMED_IAM \
  --region us-east-1
```

### 2. Bundle and upload Lambda code

```bash
./scripts/bundle_lambda.sh
# CODE_BUCKET is optional if Infra stack is deployed (script gets it from stack output)
./scripts/upload_lambda_zip.sh
# Or set explicitly: CODE_BUCKET=code-bucket-dev-ACCOUNT_ID ./scripts/upload_lambda_zip.sh
```

Set **CODE_S3_KEY** from the script output (or use the printed key).

### 3. Deploy Lambda stack

```bash
export CODE_S3_KEY=lambda/transcription-demo-summarize-YYYYMMDDHHMMSS.zip   # from upload step
# CODE_BUCKET optional if Infra stack is deployed (script gets it from stack output)
chmod +x scripts/deploy-cfn.sh && ./scripts/deploy-cfn.sh
```

**deploy-cfn.sh** deploys the infra stack (IAM role), then the Lambda stack (bucket, Lambda, permissions), then runs **add_s3_trigger.sh** to attach the S3→Lambda event (CloudFormation cannot do this in-template due to a [circular dependency](docs/S3_TRIGGER_WHY_SCRIPT.md)).

### 4. Use the bucket with the demo app

After deploy, **TranscriptionDemoLambda-&lt;instance&gt;** (e.g. TranscriptionDemoLambda-dev) outputs **BucketName**. Use it with the [transcription-demo](..) scripts:

```bash
# Option 1: pass bucket explicitly
uv run python scripts/run_transcript_only.py --bucket <BucketName>

# Option 2: set default via env (e.g. for one instance)
export TRANSCRIPTION_DEMO_BUCKET=<BucketName>
uv run python scripts/run_transcript_only.py
```

## Bootstrap an environment (one command)

One-command setup: deploy Infra stack (creates **code bucket** + IAM role), bundle Lambda, upload zip to the code bucket, deploy Lambda stack, add S3→Lambda trigger. Run from any directory (script changes to transcription-demo-infra).

**Required:** Set **REGION** (or **AWS_DEFAULT_REGION**). **INSTANCE** is optional (default: `dev`). The **code bucket** is defined in the Infra stack (CloudFormation) as **`code-bucket-<INSTANCE>-<account-id>`**; bootstrap deploys the Infra stack first so the bucket exists before upload.

```bash
cd transcription-demo-infra
chmod +x scripts/bootstrap.sh
# Default instance=dev: deploys Infra (code bucket + role), then bundle + upload + Lambda stack
REGION=us-east-1 ./scripts/bootstrap.sh
# Different instance: REGION=us-east-1 ./scripts/bootstrap.sh prod
```

## Multiple instances (same region)

Deploy several independent instances in one region (e.g. `dev`, `prod`, `customer-a`) by setting **INSTANCE** (default is `dev`). Each instance gets its own stack pair and S3 bucket.

```bash
# Default instance=dev
./scripts/deploy-cfn.sh

# Other instance
INSTANCE=prod ./scripts/deploy-cfn.sh
```

Stack names are **TranscriptionDemoInfra-&lt;instance&gt;** and **TranscriptionDemoLambda-&lt;instance&gt;** (e.g. TranscriptionDemoLambda-dev). The **BucketName** output is on the Lambda stack.

## What’s in this repo

| Stack | Contents | Deploy when |
|-------|----------|-------------|
| **TranscriptionDemoInfra** | Code bucket (Lambda zip) + IAM role for Lambda (Bedrock + basic execution) | Permissions or code-bucket change |
| **TranscriptionDemoLambda** | Transcript S3 bucket, Lambda function (code + deps), Lambda permission for S3 | Transcript bucket, Lambda code change |

The **S3→Lambda trigger** (which object keys invoke the Lambda) is added by **add_s3_trigger.sh** after the Lambda stack is created; **deploy-cfn.sh** and **bootstrap.sh** run it automatically.

## Teardown (remove all resources for an environment)

To remove all resources for an instance (Lambda stack, then Infra stack):

```bash
cd transcription-demo-infra
chmod +x scripts/teardown.sh
# Default instance=dev
REGION=us-east-1 ./scripts/teardown.sh
# Another instance
REGION=us-east-1 INSTANCE=prod ./scripts/teardown.sh prod
```

The Infra stack's **code bucket** has `DeletionPolicy: Retain`, so it is left behind after the stack is deleted. To also empty and delete the code bucket, set **DELETE_CODE_BUCKET=1**:

```bash
DELETE_CODE_BUCKET=1 REGION=us-east-1 ./scripts/teardown.sh
```

## Deploy infrastructure only (code bucket + IAM role)

When you change **IAM permissions** or the **code bucket**:

```bash
aws cloudformation deploy \
  --template-file cloudformation/infra-stack.yaml \
  --stack-name TranscriptionDemoInfra-dev \
  --parameter-overrides "Instance=dev" \
  --capabilities CAPABILITY_NAMED_IAM \
  --region us-east-1
```

For another instance: `--stack-name TranscriptionDemoInfra-prod` and `"Instance=prod"`.

## Deploy Lambda only (bucket, code)

When you change **Lambda code** or **bucket**:

1. Re-bundle and upload:
   ```bash
   ./scripts/bundle_lambda.sh
   CODE_BUCKET=your-code-bucket ./scripts/upload_lambda_zip.sh
   ```
2. Deploy the Lambda stack with the new **CODE_S3_KEY**:
   ```bash
   export CODE_BUCKET=your-code-bucket
   export CODE_S3_KEY=lambda/transcription-demo-summarize-YYYYMMDDHHMMSS.zip
   ./scripts/deploy-cfn.sh
   ```
   Or deploy only the Lambda stack (if infra stack is already deployed) by running the Lambda `aws cloudformation deploy` section from **deploy-cfn.sh** with the same parameters.

Optional: use an explicit bucket name by passing **BucketName** to the Lambda stack template (see `cloudformation/lambda-stack.yaml` parameters).

## Troubleshooting CloudFormation

If a stack update fails with **AWS::EarlyValidation::PropertyValidation**, get the exact error:

```bash
aws cloudformation describe-events --stack-name <StackName> --filters FailedEvents=true --output json
```

Or use `--change-set-name <ChangeSetArn>` if you have the failed change set ARN. The response shows `ValidationPath` and `ValidationStatusReason`.

## Demo runner role

The Lambda stack creates a **DemoRunner** IAM role with permissions to run the demo (S3 access to the transcript bucket and Amazon Transcribe for the full pipeline). Users do not need PowerUser or Administrator; they can assume this role instead.

**Stack output:** **DemoRunnerRoleArn** (e.g. `arn:aws:iam::ACCOUNT:role/transcription-demo-DemoRunner`).

**1. Allow a user or group to assume the role**

Attach an IAM policy that allows assuming the role:

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
eval $(aws sts assume-role --role-arn <DemoRunnerRoleArn> --role-session-name demo --query 'Credentials.[AccessKeyId,SecretAccessKey,SessionToken]' --output text | awk '{print "export AWS_ACCESS_KEY_ID="$1"\nexport AWS_SECRET_ACCESS_KEY="$2"\nexport AWS_SESSION_TOKEN="$3}')
uv run python scripts/run_transcript_only.py --bucket <BucketName>
```

Alternatively, add a profile to `~/.aws/config` with `role_arn` and `source_profile` so the CLI assumes the role automatically.

## Verify deployment

1. **Unit tests** (no AWS, from repo root):
   ```bash
   cd .. && uv run pytest tests/ -v
   ```

2. **Live verification** (after deploy; uses stack output and runs transcript-only demo):
   ```bash
   chmod +x scripts/verify_deployment.sh
   AWS_PROFILE=administrator ./scripts/verify_deployment.sh
   ```
   For another instance: `INSTANCE=prod AWS_PROFILE=administrator ./scripts/verify_deployment.sh`

## Project layout

```
transcription-demo-infra/
├── cloudformation/
│   ├── infra-stack.yaml       # IAM role for Lambda
│   └── lambda-stack.yaml      # S3 bucket, Lambda, permission (trigger added by script)
├── .lambda_bundle/            # Created by bundle_lambda.sh from ../lambda-src
├── scripts/
│   ├── bootstrap.sh           # Bundle, upload, deploy CF stacks, add S3 trigger (any env)
│   ├── bundle_lambda.sh      # Builds .lambda_bundle for Lambda deploy
│   ├── upload_lambda_zip.sh   # Zip and upload for CloudFormation deploy
│   ├── deploy-cfn.sh          # Deploy infra + Lambda via CloudFormation
│   ├── add_s3_trigger.sh      # Add S3→Lambda trigger after CF deploy
│   ├── teardown.sh            # Remove all resources for an environment (Lambda + Infra stacks)
│   └── verify_deployment.sh   # Get bucket from stack, run transcript-only demo
├── docs/
│   ├── S3_TRIGGER_WHY_SCRIPT.md
│   └── TODOS.md
├── pyproject.toml / requirements.txt
└── README.md
```

## Summary

- **Default environment:** `dev` (stack names: TranscriptionDemoInfra-dev, TranscriptionDemoLambda-dev).
- **Bootstrap** → `REGION=us-east-1 ./scripts/bootstrap.sh` (deploys Infra, bundle + upload, Lambda stack, trigger).
- **Teardown** → `REGION=us-east-1 ./scripts/teardown.sh` (deletes Lambda stack, then Infra stack; use `DELETE_CODE_BUCKET=1` to also remove the code bucket).
- **Infra changes** → deploy **TranscriptionDemoInfra-&lt;instance&gt;** with `cloudformation/infra-stack.yaml`
- **Lambda/code changes** → `./scripts/bundle_lambda.sh` → upload zip → deploy **TranscriptionDemoLambda** (and run **add_s3_trigger.sh** if needed)
- **Both** → `./scripts/deploy-cfn.sh` (after setting CODE_S3_KEY; CODE_BUCKET from stack if Infra deployed) or **./scripts/bootstrap.sh**
