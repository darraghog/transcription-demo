# Lambda source (Bedrock summarization)

This folder is the **single source** for the summarization Lambda. **transcription-demo-infra** builds the deployment bundle from here (`scripts/bundle_lambda.sh`).

The Lambda uses **Amazon Nova** (Converse API) for summarization. Model: **`amazon.nova-lite-v1:0`**. To use a different Nova model (e.g. `amazon.nova-pro-v1:0`), change the `modelId` in `bedrock_summarisation()` in `lambda_function.py`.

## Deploy (original / manual)

For an existing Lambda that already has dependencies (e.g. jinja2) in the runtime or layer:

```bash
cd lambda-src
zip -r ../deploy.zip lambda_function.py prompt_template.txt
cd ..
aws lambda update-function-code \
  --function-name LambdaFunctionSummarize \
  --zip-file fileb://deploy.zip \
  --profile administrator
```

For a full bundle including dependencies, use **transcription-demo-infra**: run `./scripts/bundle_lambda.sh` from `transcription-demo-infra`, then `upload_lambda_zip.sh` and deploy the Lambda stack via CloudFormation (`deploy-cfn.sh`).

Then re-run the transcript demo; the results file in `results/<stem>-results.txt` in S3 should update.
