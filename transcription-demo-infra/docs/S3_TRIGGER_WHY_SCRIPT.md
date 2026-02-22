# Why the S3→Lambda trigger is added by a script (not in the template)

When using **CloudFormation** (the YAML templates in `cloudformation/`), the S3 event notification that invokes the Lambda is **not** defined in the stack. You have to run `scripts/add_s3_trigger.sh` once after the Lambda stack is created. This is because of a **circular dependency** in the template.

## The circular dependency

1. **AWS::Lambda::Permission** (so S3 can invoke the Lambda) must reference the **bucket ARN** (`SourceArn`). So this resource depends on the bucket existing.

2. **S3 bucket notification** (the trigger) is configured on the bucket and must reference the **Lambda ARN**. When AWS applies that configuration, it checks that the Lambda already has a **resource-based policy** allowing S3 to invoke it—i.e. the `AWS::Lambda::Permission` must already exist.

So:

- The **Permission** cannot be created until the **Bucket** exists (Permission needs the bucket ARN).
- The **Bucket** cannot be given the notification until the **Permission** exists (S3’s API requires the permission before attaching the event).

In a single CloudFormation template you can’t satisfy both orderings: bucket-first and permission-first. So the notification cannot be part of the template; it has to be applied **after** the stack has created both the bucket and the permission, which is what `add_s3_trigger.sh` does.

## What the template does

The Lambda stack template already creates:

- The S3 bucket
- The Lambda function
- **BucketPermission** (Lambda resource policy so `s3.amazonaws.com` can call the function)

So after deploy, the bucket and the permission exist; only the bucket’s **event notification** (which objects trigger the Lambda) is missing. The script adds that one configuration.

## CDK

With **CDK** (`transcription_demo_infra/lambda_stack.py`), the trigger is defined in code (`bucket.add_event_notification(...)`). CDK resolves the dependency order and can create the permission and then set the bucket notification in the right sequence, so no separate script is needed for the CDK path.
