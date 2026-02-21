# Lambda source (Bedrock summarization)

This folder contains **LambdaFunctionSummarize**, which uses **Amazon Nova** (Converse API) for summarization. Model: **`amazon.nova-lite-v1:0`**. To use a different Nova model (e.g. `amazon.nova-pro-v1:0`), change the `modelId` in `bedrock_summarisation()`.

## Deploy

```bash
cd transcription-demo/lambda-src
zip -r ../deploy.zip lambda_function.py prompt_template.txt
cd ..
aws lambda update-function-code \
  --function-name LambdaFunctionSummarize \
  --zip-file fileb://deploy.zip \
  --profile administrator
```

Then re-run the transcript demo; `results.txt` in S3 should update.
