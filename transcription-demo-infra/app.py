#!/usr/bin/env python3
"""CDK app for transcription-demo: infra and Lambda stacks. Supports multiple instances via -c instance=NAME."""
import sys

import aws_cdk as cdk
from transcription_demo_infra.infra_stack import InfraStack
from transcription_demo_infra.lambda_stack import LambdaStack

app = cdk.App()

# Instance name: deploy multiple copies in the same region (e.g. dev, prod, customer-a). Default: "default"
instance = app.node.try_get_context("instance") or "default"
instance_suffix = "" if instance == "default" else f"-{instance}"
ctx_account = app.node.try_get_context("account")
ctx_region = app.node.try_get_context("region")

env = cdk.Environment(
    account=ctx_account or None,
    region=ctx_region or "us-east-1",
)
if ctx_account is None:
    print(
        "Warning: account not set. For reliable deploy pass: -c account=ACCOUNT_ID [-c region=REGION] or set AWS_PROFILE.",
        file=sys.stderr,
    )

infra = InfraStack(
    app,
    f"TranscriptionDemoInfra{instance_suffix}",
    instance=instance,
    env=env,
)
lambda_stack = LambdaStack(
    app,
    f"TranscriptionDemoLambda{instance_suffix}",
    infra=infra,
    instance=instance,
    env=env,
)

app.synth()
