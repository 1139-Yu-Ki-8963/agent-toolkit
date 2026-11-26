<!-- AUTO-GENERATED from system-functional.md.tmpl — do not edit directly -->
<!-- Regenerate: bun run gen:skill-docs -->
# Functional QA with repository-native tools

Use documented repository commands, CLI/API clients and job/queue tools, not a new
harness or browser substitution.

## Functional modes

For /qa and /qa-only, within the selected scope:
- **Full** (default): cover every applicable documented contract below.
- **Quick** (`--quick`): check success and the highest-risk changed edge; mark other
  contracts not run.
- **Regression** (`--regression <previous-report>`): before probes, read the supplied
  functional report and linked replay evidence. A missing, unreadable or wrong-target
  baseline blocks regression mode. A browser-only `baseline.json` is not a functional
  baseline. Re-establish owned setup; replay prior failed probes against the documented
  expectation, never recorded buggy output, then check changed adjacent behavior.
  Preserve the prior report; report fixed, still failing and new findings separately.
  Missing safe replay inputs block affected probes, never count as passes.

Mixed runs apply each surface's mode separately. /review and /gstack-ship retain their caller's
bounded smoke and explicit plan checks, not Full exploration.

## Contract map

Record each contract/source, isolated setup, exact probe, expectation and outcome:
pass/fail/blocked/not run/inconclusive/not applicable (reason).

| 契約 | 観察するもの |
|---|---|
| 成功する実行 | 期待した戻り値か出力と、業務の最後の効果。起動か受け付けだけではない |
| Invalid/missing input | One probe per documented input rule of each field (allowed characters, format, sign, range, arity) breaking only it: declared rejection, correct status and no forbidden state change |
| Authentication/authorization | Valid identity, missing/invalid identity, wrong owner/role and durable no-effect boundary |
| CLI process contract | Exact exit code, stdout and stderr separately; resulting file/state changes |
| 状態の遷移 | 最初、途中、完了か失敗の状態と、それらの間の許された遷移 |
| Timeout/cancellation | Deadline, partial state, termination of owned work and recovery |
| 再試行 | リポジトリが約束する試行の回数、間隔の延ばし方、最後の状態。限りのない再試行はない |
| Duplicates/idempotency | Repeated request/event and number of durable effects under the documented guarantee |
| 並行と順序 | 制御して競わせた操作を、関係する 2 つの完了の順の両方で行う。最後の不変条件 |
| 途中の失敗からの回復 | 効果のあとで中断し、再開か再実行をして、完了か dead-letter の状態と、重複を調べる |

Do not impose universal exactly-once delivery. Separate acceptance, enqueue, processing,
retry/dead-letter and final effect; 2xx is not completion. Expected rejection/injected
failure may pass; a missing service preventing execution blocks coverage.

## Execute and retain evidence

1. Apply the shared isolation/permission preflight. Verify cwd, command, environment
   NAMES and safe reset; use synthetic data/credentials.
2. Follow the shared exploratory loop's order and written checkpoints.
   プローブの 1 つごとに、最初と最後の残る状態を調べ、終了コードかステータスと、
   stdout と stderr を、失敗を隠さずに分けて残す。
3. On timeout, retain partial output/state and stop only owned work. Record setup errors
   and untested contracts; never patch product code to hide missing prerequisites.
4. Record exact command or method/path/headers/body, setup/reset, expected contract/source,
   observed output/state, revision/runtime, evidence paths and limits. Secrets are referenced
   only by environment name. 値を伏せたために再現できない限りは、そのことを伝える。
5. Use `templates/functional-report-template.md` relative to the installed QA SKILL.md.
   この実行が持つものを片付ける前に証拠を残し、残したものを伝える。探索の権限を
   広げずに、呼び出し元に戻る。
