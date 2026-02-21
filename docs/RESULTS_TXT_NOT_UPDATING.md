# Why results.txt Was Not Updating

## Investigation summary (Feb 2026)

- **S3:** `results.txt` last modified **2024-12-15** (confirmed via `head-object`).
- **Lambda:** Is being **invoked** when new `*-transcript.json` objects are created (S3 event + Lambda policy are correct). Recent invocations appear in CloudWatch.
- **CloudWatch logs:** Every recent run fails **before** writing to S3 with:

  ```
  Error occurred: An error occurred (ResourceNotFoundException) when calling the InvokeModel operation: 
  This model version has reached the end of its life. Please refer to the AWS documentation for more details.
  ```

## Root cause

The Lambda calls **Amazon Bedrock** with model ID **`amazon.titan-text-express-v1`**. That model version has been **deprecated / end-of-life**. The `InvokeModel` call fails, the Lambda hits the `except` block, and **never** runs `s3_client.put_object()` for `results.txt`, so the object in S3 is never updated (it stays at the Dec 2024 content from when the model still worked).

## Fix

Update the Lambda to use a **current** Bedrock text model ID.

### 1. Model: Amazon Nova (Converse API)

The Lambda uses **Amazon Nova** via the **Converse API** (not the legacy Titan InvokeModel API). Default model: **`amazon.nova-lite-v1:0`**. To use another Nova model (e.g. `amazon.nova-pro-v1:0`), change the `modelId` in `bedrock_summarisation()` in `lambda_function.py`.

The existing request body (`inputText`, `textGenerationConfig`) and response parsing (`results[0].outputText`) work with these Titan Text models.

### 2. Redeploy the Lambda

- **Console:** Lambda → LambdaFunctionSummarize → Code → edit the line above → Deploy.
- **CLI:** Update the deployment package (zip `lambda_function.py` + `prompt_template.txt`) and run:

  ```bash
  aws lambda update-function-code --function-name LambdaFunctionSummarize --zip-file fileb://deploy.zip --profile administrator
  ```

After redeploying, new transcript uploads will invoke the Lambda, Bedrock will succeed, and the Lambda will write an updated **results.txt** to S3.
