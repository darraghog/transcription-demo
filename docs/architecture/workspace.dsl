/*
 * Transcription Demo – architecture as Structurizr DSL (C4 model).
 * Single source of truth for system context, container, component, and deployment diagrams.
 * Export to Mermaid / PlantUML / Draw.io via Structurizr CLI (see docs/architecture/README.md).
 */
workspace "Transcription Demo" "Audio → Transcribe → transcript JSON → Lambda (S3-triggered) → Bedrock Nova → results in S3." {

    model {
        /* ---------- People ---------- */
        user = person "User" "Uploads audio or sample transcripts via run_full_pipeline.py / run_transcript_only.py; retrieves results from S3."

        /* ---------- Software system ---------- */
        sys = softwareSystem "Transcription Demo" "Orchestrates audio upload, Transcribe jobs, and Lambda summarization; stores audio, transcripts, and results in S3." {
            s3 = container "Transcript bucket" "S3 bucket for audio/, transcripts/*-transcript.json, and results/<stem>-results.txt. Receives Transcribe output; triggers Lambda on new *-transcript.json." "Amazon S3"
            lambda = container "Summarization Lambda" "Triggered by S3 on new *-transcript.json. Reads transcript, calls Bedrock (Nova), writes results/<stem>-results.txt." "AWS Lambda" {
                handler = component "Handler" "Parses S3 event, delegates to extract and summarize, writes result to S3."
                transcriptReader = component "TranscriptReader" "extract_transcript(): loads JSON from S3, returns speaker-labeled text."
                summarizer = component "Summarizer" "bedrock_summarisation(): builds prompt from template, calls Bedrock Converse API (amazon.nova-lite-v1:0), returns summary text."
                resultWriter = component "ResultWriter" "Writes summary to S3 at results/<stem>-results.txt (text/plain)."
            }
        }

        /* ---------- External systems ---------- */
        /* Tag with AWS theme names so Structurizr Lite shows correct icons in system context and container views. */
        transcribe = softwareSystem "Amazon Transcribe" "Speech-to-text. Job output (transcripts/*-transcript.json) is written to the demo S3 bucket." {
            tags "Amazon Web Services - Transcribe"
        }
        bedrock = softwareSystem "Amazon Bedrock" "Nova Converse API used by Lambda for summarization." {
            /* Theme 2023.01.31 has no "Bedrock" tag; use ML category icon until a newer theme adds it. */
            tags "Amazon Web Services - Category Machine Learning"
        }

        /* ---------- Context relationships ---------- */
        user -> sys "Uploads audio, retrieves results"
        sys -> transcribe "Starts transcription job; job writes transcript JSON to S3"
        sys -> bedrock "Lambda invokes model for summarization"

        /* ---------- Container relationships ---------- */
        s3 -> lambda "S3 event on *-transcript.json"
        lambda -> s3 "Reads transcript, writes results/<stem>-results.txt"
        lambda -> bedrock "Converse API (Nova)"

        /* ---------- Component relationships ---------- */
        handler -> transcriptReader "Delegates load"
        transcriptReader -> summarizer "Passes transcript text"
        summarizer -> resultWriter "Passes summary"
        resultWriter -> s3 "put_object"

        /* ---------- Deployment ---------- */
        /* Single environment: dev and prod share the same topology (one region, S3 + Lambda). Tags match Structurizr AWS theme 2023.01.31 for icons in Lite/Cloud. */
        /* Hierarchy: Cloud (root) → Region (child) so theme applies correct icons; S3 tag must match theme exactly (see theme.json – "S3" is "Simple Storage Service S3 Standard"). */
        live = deploymentEnvironment "Live" {
            deploymentNode "Amazon Web Services" {
                tags "Amazon Web Services - Cloud"
                deploymentNode "US-East-1" "us-east-1" {
                    tags "Amazon Web Services - Region"
                    deploymentNode "S3" "Transcript bucket" "S3" {
                        tags "Amazon Web Services - Simple Storage Service S3 Standard"
                        containerInstance s3
                    }
                    deploymentNode "Lambda" "Summarization function" "AWS Lambda" {
                        tags "Amazon Web Services - Lambda"
                        containerInstance lambda
                    }
                    /* External AWS services used by the system (not deployed by us; shown as infrastructure for deployment context). */
                    transcribeInfra = infrastructureNode "Amazon Transcribe" "Speech-to-text; job output to S3" {
                        tags "Amazon Web Services - Transcribe"
                    }
                    bedrockInfra = infrastructureNode "Amazon Bedrock" "Nova Converse API for summarization" {
                        tags "Amazon Web Services - Category Machine Learning"
                    }
                    lambda -> transcribeInfra "Job output to S3"
                    lambda -> bedrockInfra "Converse API (Nova)"
                }
            }
        }
    }

    views {
        systemContext sys "SystemContext" "Transcription Demo in context." {
            include *
            autoLayout tb
        }

        container sys "Containers" "Containers: S3 bucket and Lambda." {
            include *
            autoLayout tb
        }

        component lambda "Components" "Inside the Summarization Lambda." {
            include *
            autoLayout lr
        }

        /* One deployment view: includes deployed components (S3, Lambda) and external AWS services (Transcribe, Bedrock) as infrastructure nodes. */
        deployment sys live "Deployment" "Deployment on AWS (transcription-demo-infra) and external services used (Transcribe, Bedrock)." {
            include *
            autoLayout lr
        }

        /* AWS theme: standard icons in Structurizr Lite/Cloud. Exports (Mermaid/PlantUML) do not apply theme. */
        theme https://static.structurizr.com/themes/amazon-web-services-2023.01.31/theme.json
    }
}
