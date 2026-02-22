# Transcription demo: build and deploy.
# Run from repo root. Override: make deploy REGION=us-east-1 INSTANCE=dev
# Deploy requires IAM (e.g. iam:GetRole for stack outputs). If deploy fails with 403, use: make deploy AWS_PROFILE=administrator
REGION    ?= us-east-1
INSTANCE  ?= dev
AWS_PROFILE ?= administrator

INFRA_DIR := transcription-demo-infra
LAMBDA_SRC := lambda-src

.PHONY: help install test build deploy deploy-full clean

help:
	@echo "Targets:"
	@echo "  install     - Install app dependencies (uv sync)"
	@echo "  test        - Run unit tests"
	@echo "  build       - Bundle Lambda (lambda-src -> .lambda_bundle in infra)"
	@echo "  deploy      - Build, upload Lambda zip, deploy Lambda stack (infra must already exist)"
	@echo "  deploy-full - Bootstrap from scratch (deploy infra, bundle, upload, deploy Lambda)"
	@echo "  clean       - Remove .lambda_bundle and .lambda_bundle.zip from infra"
	@echo ""
	@echo "Override: make deploy REGION=us-east-1 INSTANCE=dev AWS_PROFILE=PowerUser"
	@echo "If deploy fails with IAM permission errors (e.g. iam:GetRole), use: make deploy AWS_PROFILE=administrator"

install:
	uv sync

test: install
	uv run pytest tests/ -v

# Bundle Lambda from lambda-src into transcription-demo-infra/.lambda_bundle
build: install
	@cd $(INFRA_DIR) && \
		REGION=$(REGION) INSTANCE=$(INSTANCE) AWS_PROFILE=$(AWS_PROFILE) \
		bash scripts/bundle_lambda.sh

# Deploy changed Lambda code: build, upload zip to code bucket, deploy Lambda stack.
# Requires Infra stack deployed (so CODE_BUCKET exists). Gets CODE_BUCKET from stack if not set.
deploy: build
	@cd $(INFRA_DIR) && \
		export REGION=$(REGION) INSTANCE=$(INSTANCE) AWS_PROFILE=$(AWS_PROFILE) && \
		CODE_BUCKET=$$(aws cloudformation describe-stacks --stack-name "TranscriptionDemoInfra-$(INSTANCE)" --region "$(REGION)" --profile "$(AWS_PROFILE)" --query "Stacks[0].Outputs[?OutputKey=='CodeBucketName'].OutputValue" --output text 2>/dev/null) && \
		[ -n "$$CODE_BUCKET" ] || { echo "Error: Infra stack not found. Run 'make deploy-full' or bootstrap first." >&2; exit 1; } && \
		export CODE_BUCKET && \
		CODE_S3_KEY=$$(bash scripts/upload_lambda_zip.sh | tee /dev/stderr | sed -n 's/^CODE_S3_KEY=//p') && \
		export CODE_S3_KEY && \
		bash scripts/deploy-cfn.sh

# Full deploy from scratch: deploy Infra stack, bundle, upload, deploy Lambda stack.
deploy-full:
	@cd $(INFRA_DIR) && \
		REGION=$(REGION) INSTANCE=$(INSTANCE) AWS_PROFILE=$(AWS_PROFILE) \
		bash scripts/bootstrap.sh $(INSTANCE)

clean:
	rm -rf $(INFRA_DIR)/.lambda_bundle $(INFRA_DIR)/.lambda_bundle.zip
