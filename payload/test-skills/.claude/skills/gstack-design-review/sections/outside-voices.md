<!-- AUTO-GENERATED from outside-voices.md.tmpl — do not edit directly -->
<!-- Regenerate: bun run gen:skill-docs -->
## Design Outside Voices (independent)

**同意:** Codex が使え、`codex_reviews` が送ることを許すとき(設定がないときは既定の enabled であり、最初の送信は 1 回だけの知らせを表示する)、外の声は、質問なしに走る。`codex_reviews=disabled` のときは、内の声だけが走る。

**Check Codex availability:**
```bash

if ! _OUTSIDE_CFG=$("$HOME/.claude/skills/gstack/bin/gstack-config" get --stored codex_reviews) || [ "$_OUTSIDE_CFG" = disabled ]; then
  echo 'CODEX_MODE: disabled'
elif ( # GSTACK_ACTIVE_HOST names the harness, never the model.
if { [ -n "${CODEX_THREAD_ID:-}" ] || [ -n "${CODEX_SANDBOX:-}" ] || [ "${GSTACK_ACTIVE_HOST:-}" = codex ]; }; then
  echo 'Codex outside review unavailable: harness mismatch; no outside process started. Missing coverage.' >&2
  if { [ -n "${CLAUDECODE:-}" ] || [ "${GSTACK_ACTIVE_HOST:-}" = claude ]; } && { [ -n "${CODEX_THREAD_ID:-}" ] || [ -n "${CODEX_SANDBOX:-}" ] || [ "${GSTACK_ACTIVE_HOST:-}" = codex ]; }; then
    echo 'Inherited harness markers conflict. Run setup --host <actual-harness> (claude or codex); do not guess a replacement provider.' >&2
  else
    echo 'Repair installed skills: run setup --host codex from your gstack checkout.' >&2
  fi
  exit 78
fi
); then
  if command -v codex >/dev/null 2>&1; then echo 'CODEX_MODE: ready'; else echo 'CODEX_MODE: not_installed'; fi
else
  echo 'CODEX_MODE: under_current_harness'
fi
```

The historical `CODEX_MODE` variable describes **Codex** availability here. `CODEX_MODE: disabled` or a send's `consent_missing` line: `codex_reviews` is off or unreadable; do not ask; record `outside_status: disabled`. Authentication and configured model validity are checked by the actual invocation, without overriding either. Missing/broken CLI: install or repair Codex; authentication failure: run `codex login`. Otherwise honor this caller’s opt-in/skip choice. Any non-ready outcome is missing outside coverage; follow the caller’s existing fallback. Never substitute another external provider.

断られたとき: 両方の声を飛ばす。`CODEX_MODE: disabled` のとき: 内の声だけを走らせ、`outside_status: disabled` を記録する。準備ができていないとき: 直し方の知らせを残し、use only the native voice, and record `outside_status: unavailable` even if it succeeds. 呼び出しは、起動の前に、実行の環境を確かめ直す。

**準備ができたら**、AI は、両方の声を走らせ、await both before synthesis. 使えるなら、呼び出しを重ねて走らせる。内の声の呼び出しは、終わるまで待つ形のままにする。

1. **Codex design voice** (via Bash):
依頼(ファイルのパスだけでなく、実際の計画、プロダクト、フロントエンドのソースの文脈を入れる):

"このリポジトリのフロントエンドのソースコードをレビューする。次のデザインの厳しい規則で評価する:
- 余白: 決まりに沿っているか(デザイントークンか CSS 変数)、根拠のない数か。
- 文字組み: 表現と目的のある書体か、既定の書体の並びか。
- 色: 決まった仕組みを持つ CSS 変数か、直に書いた 16 進の色が散らばっているか。
- 画面幅への対応: 区切りの幅は決まっているか。ヒーローに calc(100svh - header) を使うか。スマホで確かめたか。
- アクセシビリティ: ARIA のランドマーク、代替テキスト、コントラスト比、44px の押せる大きさはあるか。
- 動き: 見せ場の 1 つ(見えている既定の状態から ease-out する、登場かスクロールに連動した表示)と、情報を運ぶ所だけの状態の切り替えがあるか、ゼロか、飾りだけか。
- カード: カードそのものが操作であるときだけ使っているか。飾りのカードのグリッドはないか。

まず、MARKETING/LANDING PAGE か APP UI か HYBRID かに分け、次に、当たる規則を当てる。

LITMUS CHECKS — YES か NO で答える:
1. Brand/product unmistakable in first screen?
2. One strong visual anchor present?
3. Page understandable by scanning headlines only?
4. Each section has one job?
5. Are cards actually necessary?
6. Does motion improve hierarchy or atmosphere?
7. Would design feel premium with all decorative shadows removed?

HARD REJECTION — 1 つでも当たれば印を付ける:
1. Generic SaaS card grid as first impression
2. Beautiful image with weak brand
3. Strong headline with no clear action
4. Busy imagery behind text
5. Sections repeating same mood statement
6. Carousel with no narrative purpose
7. App UI made of stacked cards instead of layout

具体的に書く。すべての問題に file:line を示す。"

Write the **complete prompt and context**, including actual plan/spec/source, to a private file. Substitute its shell-quoted path for `<prepared-prompt-file>`; never interpolate user text into shell source. Request severity (Critical, High, Medium or Low) per finding, a Recommendation: <action> because <reason> line, and `VERDICT: CLEAN` or `VERDICT: FINDINGS` as the last line.

```bash
# GSTACK_ACTIVE_HOST names the harness, never the model.
if { [ -n "${CODEX_THREAD_ID:-}" ] || [ -n "${CODEX_SANDBOX:-}" ] || [ "${GSTACK_ACTIVE_HOST:-}" = codex ]; }; then
  echo 'Codex outside review unavailable: harness mismatch; no outside process started. Missing coverage.' >&2
  if { [ -n "${CLAUDECODE:-}" ] || [ "${GSTACK_ACTIVE_HOST:-}" = claude ]; } && { [ -n "${CODEX_THREAD_ID:-}" ] || [ -n "${CODEX_SANDBOX:-}" ] || [ "${GSTACK_ACTIVE_HOST:-}" = codex ]; }; then
    echo 'Inherited harness markers conflict. Run setup --host <actual-harness> (claude or codex); do not guess a replacement provider.' >&2
  else
    echo 'Repair installed skills: run setup --host codex from your gstack checkout.' >&2
  fi
  exit 78
fi

_REPO_ROOT=$(git rev-parse --show-toplevel) || { echo 'ERROR: not in a git repo' >&2; exit 1; }
_OUTSIDE_TMP=$(mktemp -d "${TMPDIR:-/tmp}/gstack-outside.XXXXXXXX") || exit 1
trap 'rm -r "$_OUTSIDE_TMP"' EXIT
_OUTSIDE_INPUT="$_OUTSIDE_TMP/prompt"
cat -- '<prepared-prompt-file>' >"$_OUTSIDE_INPUT" || exit 1
_CODEX_PROBE="$HOME/.claude/skills/gstack/bin/gstack-codex-probe"
_CODEX_OUT=$("$_CODEX_PROBE" select-model exec) || exit 1
_CODEX_SEL=$(echo "$_CODEX_OUT" | sed -n 's/^CODEX_SEL: //p')
_CODEX_SANDBOX_MODE=$(echo "$_CODEX_OUT" | sed -n 's/^CODEX_SANDBOX: //p')
"$_CODEX_PROBE" check-sandbox || exit 1
"$_CODEX_PROBE" show-first-use-notice
_OUTSIDE_EXIT=0
"$_CODEX_PROBE" run-with-timeout --effort high 300 codex exec - -C "$_REPO_ROOT" -s "${_CODEX_SANDBOX_MODE:?}" -c "model=\"${_CODEX_SEL:?}\"" -c skills.include_instructions=false -c 'web_search="cached"' --json -o "$_OUTSIDE_TMP/text" <"$_OUTSIDE_INPUT" >"$_OUTSIDE_TMP/events" 2>"$_OUTSIDE_TMP/stderr" || _OUTSIDE_EXIT=$?
cat "$_OUTSIDE_TMP/text" 2>/dev/null || tail -n 20 "$_OUTSIDE_TMP/events"

cat "$_OUTSIDE_TMP/stderr" >&2 || { [ "$_OUTSIDE_EXIT" -ne 0 ] || _OUTSIDE_EXIT=1; }
_OUTSIDE_RC=0
bun --no-env-file --config=/dev/null "$HOME/.claude/skills/gstack/lib/outside-review-result.ts" --label 'Codex outside review' --exit "$_OUTSIDE_EXIT" --stderr "$_OUTSIDE_TMP/stderr" --events "$_OUTSIDE_TMP/events" review "$_OUTSIDE_TMP/text" || _OUTSIDE_RC=$?
case "$_OUTSIDE_RC" in
  0|3) ;;
  4) echo 'OUTSIDE_STATUS: unverified provider=codex host=claude'; exit 4 ;;
  *) [ "$_OUTSIDE_EXIT" -ne 0 ] && exit "$_OUTSIDE_EXIT"; exit 1 ;;
esac
echo 'OUTSIDE_STATUS: completed provider=codex host=claude'
```

Use Bash `timeout: 360000`; show the full response in a `tool-output` fence. Require successful execution and valid markers. Refusal, empty/malformed output, missing score/severity/completion markers, timeout or CLI failure means `outside_status: unavailable`. P0/P1 findings block like native ones; `OUTSIDE_STATUS: unverified` is missing coverage. Use the caller's fallback; missing coverage is never clean/PASS. After either outcome, delete only your private prompt; scratch cleanup is automatic.

2. **Claude design subagent** (Agent tool, `run_in_background: false` when available。その結果を待つ。A launch receipt means it went background: await its completion notice.):
"このリポジトリのフロントエンドのソースコードをレビューする。あなたは、ソースコードでデザインの監査を行う、独立した上級のプロダクトデザイナーである。1 つずつの違反より、ファイルをまたぐ一貫性の型に目を向ける:
- 余白の値は、コード全体で決まりに沿っているか。
- 色の仕組みは 1 つか、やり方が散らばっているか。
- 画面幅の区切りは、一貫した組に従っているか。
- アクセシビリティのやり方は、一貫しているか、まだらか。

問題の 1 件ずつに: 何がまずいか、重大度(critical/high/medium)、file:line。"

**エラーの扱い(どれも止めない):**
- **Auth failure:** If stderr contains "auth", "login", "unauthorized", or "API key": "Codex authentication failed. Run `codex login` to authenticate."
- **Timeout:** "Codex timed out after 5 minutes."
- **Empty response:** "Codex returned no response."
- Codex がエラーになったときは、どのエラーでも: Claude のサブエージェントの出力だけで進める。`[single-model]` の印を付ける。
- Claude のサブエージェントも失敗したとき: "Outside voices unavailable — continuing with primary review."

出力の見出し: `CODEX SAYS (design source audit):` and `CLAUDE SUBAGENT (design consistency):`.

**Synthesis — Litmus scorecard:**

AI は、/plan-design-review と同じ採点表の形(上に示したもの)を使い、両方の出力から埋める。
AI は、問題を、`[codex]` / `[subagent]` / `[cross-model]` の印を付けて、仕分けに混ぜる。

**結果を記録する:**
```bash
~/.claude/skills/gstack/bin/gstack-review-log '{"skill":"design-outside-voices","timestamp":"'"$(date -u +%Y-%m-%dT%H:%M:%SZ)"'","status":"STATUS","source":"SOURCE","host":"claude","outside_provider":"codex","outside_status":"OUTSIDE_STATUS","phase":"design","commit":"'"$(git rev-parse --short HEAD)"'"}'
```
STATUS="clean" は、問題のない、終わったレビューを要する。問題があれば "issues_found"、どちらも終わらなければ "unavailable" を使う。SOURCE は、終わった提供元か in-host とする。

Retain the historical review-log skill ID; add `"host":"claude","outside_provider":"codex","outside_status":"completed|unavailable|disabled|skipped","phase":"design"`. Record differing attempt outcomes separately. `source:"codex"` requires completed CLI output; native uses `source:"in-host"` (historical `source:"claude"`: native Claude). Availability/native fallback is not outside completion. Preserve all reported modelUsage; unknown model identity stays unknown. Under `GSTACK_CODEX_NO_SANDBOX=1` add `"codex_sandbox":"danger-full-access"`.
