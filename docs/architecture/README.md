# Architecture

The transcription-demo system turns audio into summarized text: **audio** → **Amazon Transcribe** → **transcript JSON in S3** → **Lambda** (S3-triggered) → **Amazon Bedrock (Nova)** → **results** back to S3. Users run scripts (`run_full_pipeline.py`, `run_transcript_only.py`) to upload audio or sample transcripts and retrieve `results/<stem>-results.txt`.

Diagrams are defined in **Structurizr DSL** and follow the [C4 model](https://c4model.com/) (system context, container, component, deployment). You can export them to Mermaid, PlantUML, or Draw.io for rendering. The workspace uses **Structurizr’s AWS theme** and **AWS tags** on deployment nodes so that **Structurizr Lite** shows standard AWS icons. For standard AWS icons in Mermaid, PlantUML, or Draw.io, see **AWS-DEPLOYMENT-DIAGRAM-STANDARDS.md** in the architecture-diagram-guidance package.

---

## Diagram source

| File | Purpose |
|------|---------|
| **[workspace.dsl](workspace.dsl)** | Single source of truth for all architecture views. Edit this file to change diagrams. |

### Views in this workspace

| View | C4 level | Contents |
|------|----------|----------|
| **System context** | Level 1 | User, Transcription Demo (one box), Amazon Transcribe, Amazon Bedrock. |
| **Containers** | Level 2 | Transcript bucket (S3), Summarization Lambda; external systems. |
| **Components** | Level 3 | Inside Lambda: Handler, TranscriptReader, Summarizer, ResultWriter. |
| **Deployment** | Deployment | AWS (Cloud → Region → S3, Lambda). Single view; dev and prod share the same topology. |

---

## Generating diagrams

### Option 1: Project script (Docker, recommended)

From the **transcription-demo** repo root, use the script that uses the Structurizr CLI Docker image:

```bash
./scripts/render_structurizr.sh
```

This exports `docs/architecture/workspace.dsl` to **Mermaid** and **PlantUML** under `docs/architecture/output/`. Requires Docker; the script will pull `structurizr/cli:latest` if needed. See `./scripts/render_structurizr.sh --help` for options and install guidance (Docker + image).

**Visualize in browser (Structurizr Lite):** Run with `--lite` to start [Structurizr Lite](https://docs.structurizr.com/lite/) and open the workspace at http://localhost:8080. Edit the DSL and refresh to see changes. Stop with Ctrl+C.

```bash
./scripts/render_structurizr.sh --help              # Usage and install guidance
./scripts/render_structurizr.sh --lite              # Open workspace in browser (Structurizr Lite)
./scripts/render_structurizr.sh -o my/output        # Custom output dir (must be under repo)
./scripts/render_structurizr.sh --mermaid           # Only Mermaid
./scripts/render_structurizr.sh --plantuml          # Only PlantUML
./scripts/render_structurizr.sh --no-pull           # Use existing image only
```

Port for Lite can be overridden with `STRUCTURIZR_LITE_PORT` (default 8080).

### Option 2: Scripts from architecture-diagram-guidance

If you have the shared **architecture-diagram-guidance** package (e.g. sibling of this repo):

```bash
cd path/to/architecture-diagram-guidance/scripts
./export-mermaid.sh  /path/to/transcription-demo/docs/architecture/workspace.dsl  ../output/mermaid
./export-plantuml.sh /path/to/transcription-demo/docs/architecture/workspace.dsl  ../output/plantuml
./export-for-drawio.sh /path/to/transcription-demo/docs/architecture/workspace.dsl  ../output/drawio
```

When using Docker, workspace and output paths must be under the guidance directory. Copy `docs/architecture/workspace.dsl` into the guidance folder temporarily, or run the CLI locally (see below).

### Option 3: Structurizr CLI (local or Docker)

With [Structurizr CLI](https://docs.structurizr.com/cli/installation) on your PATH:

```bash
cd transcription-demo/docs/architecture
structurizr export -workspace workspace.dsl -format mermaid -output ../../output/mermaid
structurizr export -workspace workspace.dsl -format plantuml/c4plantuml -output ../../output/plantuml
```

With Docker (from repo root, so paths are valid inside the container):

```bash
docker run --rm -v "$(pwd):/w" -w /w structurizr/cli:latest \
  export -workspace docs/architecture/workspace.dsl -format mermaid -output output/mermaid
```

### Rendering

- **Mermaid:** Use `"securityLevel": "loose"` in your Mermaid config. Paste `.mmd` into GitHub/GitLab or [Mermaid Live](https://mermaid.live/).
- **PlantUML:** Use C4-PlantUML includes when rendering `.puml`; optionally add [AWS icons for PlantUML](https://github.com/awslabs/aws-icons-for-plantuml) for deployment diagrams.
- **Draw.io:** Insert → Advanced → PlantUML, then paste `.puml` content; add AWS shape libraries as needed.

---

## High-level flow (reference)

```
User (scripts) → upload audio / sample transcript
       ↓
S3 bucket (audio/, transcripts/*.json, results/*.txt)
       ↓
Amazon Transcribe (job output → transcripts/*-transcript.json)
       ↓
S3 event → Lambda (extract_transcript → Bedrock Nova → put results/<stem>-results.txt)
       ↓
User downloads results from S3
```

Infrastructure is defined and deployed by [transcription-demo-infra](../../transcription-demo-infra) (CloudFormation: Infra stack + Lambda stack, S3 trigger added by script).
