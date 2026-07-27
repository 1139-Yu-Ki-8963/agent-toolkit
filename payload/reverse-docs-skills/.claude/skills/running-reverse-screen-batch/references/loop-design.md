# ループ雛形の正本

`running-reverse-screen-batch` の Phase 3 で使う無人バッチループの雛形。プレースホルダを実値に置換し、Bash ツール1コマンド（`nohup bash -c "$(cat <<'RHB_SCRIPT' ... RHB_SCRIPT)" >> ログ 2>&1 & disown` 構造）としてそのまま実行する。

盲検分離（正本は `orchestrating-reverse-docs-flow` の `references/contract.md` の「無人モード仕様」の「盲検分離の必須要件」）を満たすため、1画面につき `claude -p` を前半・後半の2回に分けて呼び出す。前半完了でレジストリ `status` が `authored` に、後半完了で `baseline-established` になる。

## 1. プレースホルダ定義表

| プレースホルダ | 説明 | 既定値 |
|---|---|---|
| `TARGETS_FILE` | Phase 1 で生成した画面ID一覧（1行1画面ID）の絶対パス | なし（必須） |
| `MARKER_REGISTRY` | 画面レジストリYAMLの絶対パス（マーカー判定に使用） | なし（必須） |
| `LOG` | 実行ログの出力先絶対パス | なし（必須） |
| `WAIT_SECONDS` | limit 検知時の待機秒数 | 3600 |
| `VERIFICATION_MODE` | 検証モード。`docs-only` / `single-pass` / `iterative` | single-pass |
| `FAIL_LIMIT_K` | `iterative` でだけ使う同一画面の連続失敗上限 | 3 |
| `MODEL` | `claude -p` に渡すモデル名 | claude-sonnet-5 |
| `ALLOWED_TOOLS` | `--allowedTools` に渡すツール一覧（カンマ区切り） | Read,Write,Edit,Bash,Grep,Glob,Skill |
| `PER_ITEM_PROMPT_FIRST` | 前半（静的著述）のプロンプト文字列。`$TARGET` を画面IDへの置換対象として含む。`docs-only` はこれだけを実行する | 本ファイル §4 参照 |
| `PER_ITEM_PROMPT_SECOND` | 後半（ファイル単位盲検検証・往復検証）のプロンプト文字列。`single-pass` / `iterative` のみで使い、`$TARGET` を画面IDへの置換対象として含む | 本ファイル §4 参照 |
| `FAILED_LIST` | `single-pass` の初回未完了、または `iterative` の連続失敗K回到達画面の退避先絶対パス | `<LOGと同ディレクトリ>/failed-screens.txt` |
| `FAIL_COUNTS` | 画面ごとの失敗回数を記録するTSVファイルの絶対パス | `<LOGと同ディレクトリ>/fail-counts.tsv` |
| `TARGET_REPO_PATH` | 対象プロジェクトのリポジトリルートパス | なし（必須） |
| `DOCS_ROOT` | 設計書の書き出し先ルートパス | なし（必須） |
| `TEMPLATE_ROOT` | テンプレートディレクトリパス | なし（必須） |
| `COMMON_DOCS_ROOT` | プロジェクト共通設計書パス | なし（必須） |
| `SURVEY_DOC_PATH` | アーキテクチャ調査書パス | なし（必須） |
| `DEADLINE` | 時限（ISO 8601日時）。未指定なら空文字（チェックスキップ） | 空（無制限） |

macOS 標準の `/bin/bash`（バージョン3.2系）は連想配列を持たないため、失敗回数の管理は `awk` によるファイルベースのカウンタで行う。

## 2. ワンライナー骨格

```bash
nohup bash -c "$(cat <<'RHB_SCRIPT'
TARGETS_FILE="__TARGETS_FILE__"
MARKER_REGISTRY="__MARKER_REGISTRY__"
LOG="__LOG__"
WAIT_SECONDS=__WAIT_SECONDS__
VERIFICATION_MODE="__VERIFICATION_MODE__"
FAIL_LIMIT_K=__FAIL_LIMIT_K__
MODEL="__MODEL__"
ALLOWED_TOOLS="__ALLOWED_TOOLS__"
FAILED_LIST="__FAILED_LIST__"
FAIL_COUNTS="__FAIL_COUNTS__"
TARGET_REPO_PATH="__TARGET_REPO_PATH__"
DOCS_ROOT="__DOCS_ROOT__"
TEMPLATE_ROOT="__TEMPLATE_ROOT__"
COMMON_DOCS_ROOT="__COMMON_DOCS_ROOT__"
SURVEY_DOC_PATH="__SURVEY_DOC_PATH__"
DEADLINE="__DEADLINE__"

touch "$FAILED_LIST" "$FAIL_COUNTS"

# レジストリのマップキーは `<system>-<screen_id>:`（正本: orchestrating-reverse-docs-flow の
# references/contract.md 「画面レジストリ」節）。system は本スクリプトが既に持つ
# TARGET_REPO_PATH のディレクトリ名から導出する（manifest.yml の system キーがリポジトリ
# ディレクトリ名と一致する運用を前提とする既知の制約。一致しないプロジェクトでは要調整）。
SYSTEM="$(basename "$TARGET_REPO_PATH")"

registry_block() {
  local target="$1"
  awk -v key="  ${SYSTEM}-${target}:" '
    $0 == key { infield=1; next }
    infield && /^  [^ ]/ { exit }
    infield { print }
  ' "$MARKER_REGISTRY" 2>/dev/null
}

check_authored() {
  TARGET="$1"
  registry_block "$TARGET" | grep -qE "status: (authored|unlocked|baseline-established)"
}

check_dynamic_ready() {
  TARGET="$1"
  registry_block "$TARGET" | grep -qE "status: (unlocked|baseline-established)"
}

check_baseline() {
  TARGET="$1"
  registry_block "$TARGET" | grep -qE "status: baseline-established"
}

get_fail_count() {
  awk -F'\t' -v t="$1" '$1==t{print $2; found=1} END{if(!found) print 0}' "$FAIL_COUNTS"
}

inc_fail_count() {
  local target="$1" cur
  cur=$(get_fail_count "$target")
  cur=$((cur + 1))
  awk -F'\t' -v t="$target" -v c="$cur" 'BEGIN{OFS="\t"} $1==t{$2=c; found=1; print; next} {print} END{if(!found) print t, c}' "$FAIL_COUNTS" > "$FAIL_COUNTS.tmp" && mv "$FAIL_COUNTS.tmp" "$FAIL_COUNTS"
  echo "$cur"
}

lap=0
while :; do
  # deadline チェック（指定時のみ）
  if [ -n "$DEADLINE" ]; then
    now=$(date -u +%s)
    dl=$(date -u -j -f "%Y-%m-%dT%H:%M:%S" "$DEADLINE" +%s 2>/dev/null || date -u -d "$DEADLINE" +%s 2>/dev/null)
    if [ "$now" -ge "$dl" ]; then
      echo "[DEADLINE] 時限到達 $(date '+%Y-%m-%d %H:%M:%S') -> 新規着手停止"
      break
    fi
  fi
  lap=$((lap + 1))
  remaining=0
  progressed=0
  echo "[LAP $lap] start $(date '+%Y-%m-%d %H:%M:%S')"

  while IFS= read -r TARGET; do
    [ -z "$TARGET" ] && continue
    grep -qxF -- "$TARGET" "$FAILED_LIST" && continue

    if check_baseline "$TARGET"; then
      continue
    fi
    if [ "$VERIFICATION_MODE" = "docs-only" ] && check_authored "$TARGET"; then
      continue
    fi
    remaining=$((remaining + 1))
    STAGE_OK=0

    if [ "$VERIFICATION_MODE" = "docs-only" ]; then
      if check_authored "$TARGET"; then
        STAGE_OK=1
      fi
    elif check_dynamic_ready "$TARGET"; then
      STAGE_OK=1
    fi

    if [ "$STAGE_OK" -eq 0 ]; then
      PROMPT="__PER_ITEM_PROMPT_FIRST__"
      PROMPT="${PROMPT//__VERIFICATION_MODE__/$VERIFICATION_MODE}"
      PROMPT="${PROMPT//\$TARGET/$TARGET}"
      PROMPT="${PROMPT//\$TARGET_REPO_PATH/$TARGET_REPO_PATH}"
      PROMPT="${PROMPT//\$DOCS_ROOT/$DOCS_ROOT}"
      PROMPT="${PROMPT//\$TEMPLATE_ROOT/$TEMPLATE_ROOT}"
      PROMPT="${PROMPT//\$COMMON_DOCS_ROOT/$COMMON_DOCS_ROOT}"
      PROMPT="${PROMPT//\$SURVEY_DOC_PATH/$SURVEY_DOC_PATH}"

      OUTPUT=$(claude -p "$PROMPT" \
        --model "$MODEL" \
        --allowedTools "$ALLOWED_TOOLS" \
        --permission-mode acceptEdits \
        --no-session-persistence \
        --output-format text 2>&1)

      if echo "$OUTPUT" | grep -qiE 'usage limit|rate limit|session limit|limit reached|limit will reset|You.ve reached'; then
        echo "[LAP $lap] limit検知(前半) screen=$TARGET -> ${WAIT_SECONDS}秒待機"
        sleep "$WAIT_SECONDS"
        # deadline チェック（指定時のみ）
        if [ -n "$DEADLINE" ]; then
          now=$(date -u +%s)
          dl=$(date -u -j -f "%Y-%m-%dT%H:%M:%S" "$DEADLINE" +%s 2>/dev/null || date -u -d "$DEADLINE" +%s 2>/dev/null)
          if [ "$now" -ge "$dl" ]; then
            echo "[DEADLINE] 時限到達 $(date '+%Y-%m-%d %H:%M:%S') -> 新規着手停止"
            break
          fi
        fi
        continue
      fi

      STAGE_OK=0
      if [ "$VERIFICATION_MODE" = "docs-only" ]; then
        if check_authored "$TARGET"; then
          STAGE_OK=1
        fi
      elif check_dynamic_ready "$TARGET"; then
        STAGE_OK=1
      fi
    fi

    if [ "$VERIFICATION_MODE" = "docs-only" ] && [ "$STAGE_OK" -eq 1 ] && check_authored "$TARGET"; then
      echo "[LAP $lap] STATIC_COMPLETE screen=$TARGET"
      progressed=$((progressed + 1))
      continue
    fi

    if [ "$VERIFICATION_MODE" != "docs-only" ] && [ "$STAGE_OK" -eq 1 ]; then
      PROMPT="__PER_ITEM_PROMPT_SECOND__"
      PROMPT="${PROMPT//__VERIFICATION_MODE__/$VERIFICATION_MODE}"
      PROMPT="${PROMPT//\$TARGET/$TARGET}"
      PROMPT="${PROMPT//\$TARGET_REPO_PATH/$TARGET_REPO_PATH}"
      PROMPT="${PROMPT//\$DOCS_ROOT/$DOCS_ROOT}"
      PROMPT="${PROMPT//\$TEMPLATE_ROOT/$TEMPLATE_ROOT}"
      PROMPT="${PROMPT//\$COMMON_DOCS_ROOT/$COMMON_DOCS_ROOT}"
      PROMPT="${PROMPT//\$SURVEY_DOC_PATH/$SURVEY_DOC_PATH}"

      OUTPUT=$(claude -p "$PROMPT" \
        --model "$MODEL" \
        --allowedTools "$ALLOWED_TOOLS" \
        --permission-mode acceptEdits \
        --no-session-persistence \
        --output-format text 2>&1)

      if echo "$OUTPUT" | grep -qiE 'usage limit|rate limit|session limit|limit reached|limit will reset|You.ve reached'; then
        echo "[LAP $lap] limit検知(後半) screen=$TARGET -> ${WAIT_SECONDS}秒待機"
        sleep "$WAIT_SECONDS"
        # deadline チェック（指定時のみ）
        if [ -n "$DEADLINE" ]; then
          now=$(date -u +%s)
          dl=$(date -u -j -f "%Y-%m-%dT%H:%M:%S" "$DEADLINE" +%s 2>/dev/null || date -u -d "$DEADLINE" +%s 2>/dev/null)
          if [ "$now" -ge "$dl" ]; then
            echo "[DEADLINE] 時限到達 $(date '+%Y-%m-%d %H:%M:%S') -> 新規着手停止"
            break
          fi
        fi
        continue
      fi

      if ! check_baseline "$TARGET"; then
        STAGE_OK=0
      fi
    fi

    if [ "$STAGE_OK" -eq 1 ] && check_baseline "$TARGET"; then
      echo "[LAP $lap] 検証完了 screen=$TARGET"
      progressed=$((progressed + 1))
    else
      if [ "$VERIFICATION_MODE" = "docs-only" ] || [ "$VERIFICATION_MODE" = "single-pass" ]; then
        echo "$TARGET" >> "$FAILED_LIST"
        echo "[LAP $lap] $VERIFICATION_MODE 未完了のため再試行せずfailedリストへ退避 screen=$TARGET"
      else
        fc=$(inc_fail_count "$TARGET")
        echo "[LAP $lap] 未完了 screen=$TARGET fail_count=$fc"
        if [ "$fc" -ge "$FAIL_LIMIT_K" ]; then
          echo "$TARGET" >> "$FAILED_LIST"
          echo "[LAP $lap] failedリストへ退避 screen=$TARGET"
        fi
      fi
    fi
  done < "$TARGETS_FILE"

  echo "[LAP $lap] summary remaining_at_start=$remaining progressed=$progressed"

  if [ "$remaining" -eq 0 ]; then
    echo "[DONE] 残ゼロで終了 $(date '+%Y-%m-%d %H:%M:%S')"
    break
  fi
done
echo "[END] 周回終了 lap=$lap $(date '+%Y-%m-%d %H:%M:%S')"
RHB_SCRIPT
)" >> "__LOG__" 2>&1 &
disown
BG_PID=$!
echo "$BG_PID"
```

置換手順:

1. `__TARGETS_FILE__` `__MARKER_REGISTRY__` `__LOG__` `__WAIT_SECONDS__` `__VERIFICATION_MODE__` `__FAIL_LIMIT_K__` `__MODEL__` `__ALLOWED_TOOLS__` `__FAILED_LIST__` `__FAIL_COUNTS__` `__TARGET_REPO_PATH__` `__DOCS_ROOT__` `__TEMPLATE_ROOT__` `__COMMON_DOCS_ROOT__` `__SURVEY_DOC_PATH__` `__DEADLINE__` を起動引数の確定値で置換する
2. `__PER_ITEM_PROMPT_FIRST__` を §4 の前半テンプレートを埋めた文字列で置換する
3. `__PER_ITEM_PROMPT_SECOND__` を §4 の後半テンプレートを埋めた文字列で置換する
4. 置換済みの全文を1個の Bash ツール呼び出し（dangerouslyDisableSandbox: true）として実行する

起動直後の生存確認:

```bash
sleep 10
kill -0 "$BG_PID" && echo "生存中" || echo "起動直後に終了した（要調査）"
```

## 3. limit検知の正規表現パターン集（正本）

```
grep -qiE 'usage limit|rate limit|session limit|limit reached|limit will reset|You.ve reached'
```

## 4. 1画面分プロンプトのテンプレート（per-item prompt）

`docs-only` は前半プロンプトだけを実行し、`STATIC_COMPLETE` で終端する。`single-pass` / `iterative` では前半・後半を別々の `claude -p` 呼び出しに渡し、互いのセッション・コンテキストを共有しない（これにより盲検分離が成立する）。

### 4.1 前半テンプレート（著述）: `PER_ITEM_PROMPT_FIRST`

```
あなたは1画面のリバース設計著述を完遂するヘッドレスタスクです（前半: 原本コードを読む工程）。

対象画面: $TARGET
検証モード: __VERIFICATION_MODE__
リポジトリ: $TARGET_REPO_PATH
設計書出力先: $DOCS_ROOT
テンプレート: $TEMPLATE_ROOT
共通設計書: $COMMON_DOCS_ROOT
アーキテクチャ調査書: $SURVEY_DOC_PATH

契約（必ず守ること）:
1. 対象画面の著述パイプラインを以下の順に全て実行する:
   - Skill(extracting-unit-facts-from-code) で事実封印
   - 対象ファイルの合計行数・ファイル数を実測し、orchestrating-reverse-docs-flow の契約どおり authoring_mode を判定する
   - standard: Skill(generating-reverse-basic-design, authoring_pass=standard) と Skill(generating-reverse-detailed-design, authoring_pass=full) を順次実行する
   - large-two-pass パス1: Skill(generating-reverse-detailed-design, authoring_pass=detail-only) を実行して DETAIL_AUTHORED・detail_design_path・pass1_receipt_path を検収する
   - large-two-pass パス2: 固定証跡の検収後に detail_design_path・pass1_receipt_path を渡し、Skill(generating-reverse-basic-design, authoring_pass=large-pass2) と Skill(generating-reverse-detailed-design, authoring_pass=companion-docs) を順次実行する
2. standard は基本設計著述完了+AUTHORED、large-two-pass はDETAIL_AUTHORED+基本設計著述完了+COMPANION_AUTHOREDを検収したら、管理プロセスとして画面レジストリの当該エントリを作成または更新し `status=authored` にする
3. `docs-only` の場合はここで `STATIC_COMPLETE` を返して終了する。unlocking/dynamic-only、ファイル単位検証、基準確立、implement、sync dry-run、judge、teardown を一切起動しない
4. `single-pass` / `iterative` の場合だけ Skill(unlocking-reverse-target-screens) を `invocation_mode=dynamic-only` で起動し、動的検証に使う画面を開通して設計書 frontmatter の実測項目を補完する
5. 画面レジストリで当該画面の status が既に authored、unlocked、baseline-established のいずれかなら、完了済み工程を再実行しない
6. 画面開通に失敗しても facts・基本設計・詳細設計と `authored` を保持し、`静的リバース完了・動的検証保留` として停止する
7. `single-pass` では再抽出・再著述・再比較を行わない。精度向上の反復は `iterative` の場合だけ許可する

各 Skill の args は以下のリポジトリの SKILL.md に従い全量指定する:
- target_repo_path: $TARGET_REPO_PATH
- output_dir: $DOCS_ROOT
- screen_id: $TARGET
- template_root: $TEMPLATE_ROOT
- common_docs_root: $COMMON_DOCS_ROOT
- survey_doc_path: $SURVEY_DOC_PATH

工程途中で失敗した場合はそこで停止する（status は更新しない）。
```

### 4.2 後半テンプレート（ファイル単位盲検検証・往復検証）: `PER_ITEM_PROMPT_SECOND`

`docs-only` ではこのテンプレートを使わない。

```
あなたは1画面のリバース設計検証を完遂するヘッドレスタスクです（後半: 設計書のみから判定する工程。原本コードは一切読まない）。

対象画面: $TARGET
検証モード: __VERIFICATION_MODE__
リポジトリ: $TARGET_REPO_PATH
設計書出力先: $DOCS_ROOT
テンプレート: $TEMPLATE_ROOT
共通設計書: $COMMON_DOCS_ROOT

前提: 画面レジストリの当該エントリ status が unlocked であること（静的著述・動的開通・frontmatter 完全性ゲート済み）。authored のままなら動的準備未完了なので何もせず即座に終了する。

契約（必ず守ること）:
1. 対象リポジトリの原本コードを Read しない（盲検）。情報源は設計書と facts のみ
2. 検証パイプラインを以下の順に全て実行する:
   - Skill(rebuilding-screen-unit-from-docs) に verification_mode を渡してファイル単位盲検検証（対象ファイルを白紙化し設計書のみから再現。無人モードでは必須工程）
   - Skill(syncing-reverse-env) mode=sync で基準確立
   - Skill(rebuilding-code-from-docs) mode=implement で比較要求を取得
   - Skill(syncing-reverse-env) mode=sync,dry-run で比較結果ブロックを取得
   - Skill(rebuilding-code-from-docs) mode=judge で比較結果ブロックを判定
3. status=PASS まで到達したら画面レジストリの当該エントリ status を `baseline-established` に更新する（=検証完了マーカー付与）
4. 検証完了後、Skill(syncing-reverse-env) mode=teardown（軽量: ポート・プロセスのみ解放し baseline_tag・成果物は保持）で環境スロットを解放する
5. 画面レジストリで当該画面の status が既に baseline-established なら、何もせず即座に終了する
6. `single-pass` は各検証を1回だけ実行し、FAIL・差し戻し・未完了を改善候補として返して停止する。再生成・再比較による精度向上は `iterative` の場合だけ行う

各 Skill の args は以下のリポジトリの SKILL.md に従い全量指定する:
- target_repo_path: $TARGET_REPO_PATH
- output_dir: $DOCS_ROOT
- screen_id: $TARGET
- template_root: $TEMPLATE_ROOT
- common_docs_root: $COMMON_DOCS_ROOT

工程途中で失敗した場合はそこで停止する（status は baseline-established に更新しない）。
```
