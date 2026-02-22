# Why results.txt Was Not Updating

**Status:** Fix applied. The Lambda uses Amazon Nova via the Converse API (`amazon.nova-lite-v1:0`). This doc is kept as a runbook for the same class of issue (e.g. model end-of-life).

## Investigation summary (Feb 2026)

- **S3:** `results.txt` last modified **2024-12-15** (confirmed via `head-object`).
- **Lambda:** Is being **invoked** when new `*-transcript.json` objects are created (S3 event + Lambda policy are correct). Recent invocations appear in CloudWatch.
- **CloudWatch logs:** Every recent run fails **before** writing to S3 with:

  ```
  Error occurred: An error occurred (ResourceNotFoundException) when calling the InvokeModel operation: 
  This model version has reached the end of its life. Please refer to the AWS documentation for more details.
  ```

## Root cause

The Lambda was calling **Amazon Bedrock** with a **deprecated model** (e.g. legacy Titan or an end-of-life model). That call failed, the Lambda hit the `except` block, and **never** ran `s3_client.put_object()` for `results.txt`, so the object in S3 was never updated (it stayed at the Dec 2024 content from when the model still worked).

## Fix

Update the Lambda to use a **current** Bedrock model.

### 1. Model: Amazon Nova (Converse API)

The Lambda uses **Amazon Nova** via the **Converse API** (`bedrock_runtime.converse()` with `modelId="amazon.nova-lite-v1:0"`). Request/response use the Converse shape: `messages` / `content[].text` and `response["output"]["message"]["content"][0]["text"]`. To use another Nova model (e.g. `amazon.nova-pro-v1:0`), change the `modelId` in `bedrock_summarisation()` in `lambda_function.py` (in `lambda-src/`).

### 2. Redeploy the Lambda

- **Console:** Open the summarization function (e.g. `transcription-demo-dev-Summarize` or legacy `LambdaFunctionSummarize`) → Code → ensure model ID is current → Deploy.
- **CLI (original/legacy infra):** Zip `lambda_function.py` and `prompt_template.txt` from `lambda-src/`, then:

  ```bash
  aws lambda update-function-code --function-name LambdaFunctionSummarize --zip-file fileb://deploy.zip --profile administrator
  ```

- **transcription-demo-infra (recommended):** From repo root run `make deploy`, or from `transcription-demo-infra`: `./scripts/bundle_lambda.sh`, then `./scripts/upload_lambda_zip.sh`, then `./scripts/deploy-cfn.sh`. The bundle is built from `lambda-src/`.

After redeploying, new transcript uploads will invoke the Lambda, Bedrock will succeed, and the Lambda will write an updated **results.txt** (or `results/<stem>-results.txt`) to S3.
