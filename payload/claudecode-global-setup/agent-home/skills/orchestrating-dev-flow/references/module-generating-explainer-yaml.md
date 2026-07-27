# generating-explainer-yaml（orchestrating-dev-flow 内部モジュール）

Turn an understanding target — a pasted document, repository summary, PR/diff summary,
README, design note, or spec — into the **two intermediate YAML files** that the explainer
pipeline runs on:

1. `core.yaml` — the **semantic structure** of the target (meaning, not UI): concepts,
   relations, importance, difficulty, confidence, questions, risks, source refs.
2. `view.yaml` — **how to present it to this particular reader**: audience, preferred and
   avoided forms, density, tone, emphasis, generation policy.

This module is the **first half** of the pipeline. It does not produce HTML. Once the YAML
pair exists, the **`module-generating-explainer-html.md`** module reads it (by absolute path) and builds
a switchable, light/dark HTML view bundle.

```
Input (document / repo summary / PR diff / README / design doc / any technical text)
  ↓ analyze (this module)
core.yaml   (concepts, relations, importance, difficulty, evidence, source refs)
view.yaml   (audience, preferred/avoided forms, density, emphasis)
  ↓ design + generate (module-generating-explainer-html.md)
HTML bundle (index.html + switchable iframe views)
```

## What this module does

- **Generate** `core.yaml` + `view.yaml` from a fresh input.
- **Refine / reshape** an existing `core.yaml` / `view.yaml` (add a concept, fix a relation,
  re-target `view.yaml` at a different audience, adjust emphasis, tidy the structure).

## Where to write the YAML

Write the files to a **stable directory** whose path will persist — most naturally the
bundle directory the HTML module will build into (e.g. `./explainer-bundle/core.yaml` and
`./explainer-bundle/view.yaml`), or a project folder the user keeps. The HTML module copies
them into the bundle and embeds their **absolute path** into the regeneration prompts, so a
local-file-reading AI can re-read them later. Do **not** use a throwaway temp path.

## Steps

1. **Read the input.** Take whatever the user pasted or pointed at. Identify the target
   type (document / repository / pull_request / design_note / spec).

2. **Author `core.yaml`.** Capture the *meaning*: concepts (with importance, difficulty,
   confidence), relations, questions, risks, and `source_refs`. Keep it compact — compress
   to what matters; do not transcribe the source. Lower `confidence` and add a `question`
   when unsure; do not invent facts. Schema: `generating-explainer-yaml-core-yaml-schema.md`. Example:
   `generating-explainer-yaml-sample-core.yaml`.

3. **Author `view.yaml`.** Decide how to present it to *this* reader: audience
   role/familiarity, preferred and avoided forms, density, tone, what to emphasize, and the
   `html_generation_policy`. If the user did not say, infer a sensible strategy and **state
   the assumption**. Schema: `generating-explainer-yaml-view-yaml-schema.md`. Example:
   `generating-explainer-yaml-sample-view.yaml`.

4. **Write both files** to the stable directory and tell the user their **absolute paths**,
   so they can hand those paths to the `module-generating-explainer-html.md` module.

5. **(Refine mode)** When editing existing YAML, read the current file first, make the
   smallest change that satisfies the request, keep `id` values stable (relations,
   questions, and risks point at concept ids), and preserve the schema version.

## Hand-off to the HTML module

After writing the YAML, the next step is the **`module-generating-explainer-html.md`** module:

```
generating-explainer-html を使って、
  --core /abs/path/core.yaml --view /abs/path/view.yaml
からビュー付きの HTML バンドルを作ってください。
```

## Notes

- **core.yaml is reader-independent; view.yaml is reader-dependent.** Keeping meaning
  separate from presentation is what lets the same `core.yaml` be re-targeted at a new
  audience just by changing `view.yaml`.
- **Offline safety carries downstream.** The final HTML is offline and self-contained and a
  validator flags any `http://` / `https://` string. Treat any `url` in a `source_ref` as a
  *label*, not a live link — prefer `path` / `title` / `excerpt`, and drop the scheme if you
  must record a URL. See the "URLs" note in `generating-explainer-yaml-core-yaml-schema.md`.

## Reference material

- `generating-explainer-yaml-core-yaml-schema.md` — meaning structure schema (`core/v1`)
- `generating-explainer-yaml-view-yaml-schema.md` — presentation strategy schema (`view/v1`)
- `generating-explainer-yaml-sample-core.yaml` — worked `core.yaml` (a PR)
- `generating-explainer-yaml-sample-view.yaml` — worked `view.yaml` (engineer reviewing the PR)
- `generating-explainer-yaml-examples.md` — three worked intents (engineer / PdM / beginner)
- `generating-explainer-yaml-agents-openai.yaml` — portable description of this module for non-Claude agents
