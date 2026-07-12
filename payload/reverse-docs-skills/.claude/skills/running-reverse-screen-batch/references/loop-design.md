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
| `FAIL_LIMIT_K` | 同一画面の連続失敗上限 | 3 |
| `MODEL` | `claude -p` に渡すモデル名 | claude-sonnet-5 |
| `ALLOWED_TOOLS` | `--allowedTools` に渡すツール一覧（カンマ区切り） | Read,Write,Edit,Bash,Grep,Glob,Skill |
| `PER_ITEM_PROMPT_FIRST` | 前半（著述）のプロンプト文字列。`$TARGET` を画面IDへの置換対象として含む | 本ファイル §4 参照 |
| `PER_ITEM_PROMPT_SECOND` | 後半（ファイル単位盲検検証・往復検証）のプロンプト文字列。`$TARGET` を画面IDへの置換対象として含む | 本ファイル §4 参照 |
| `FAILED_LIST` | 連続失敗でK回に達した画面の退避先絶対パス | `<LOGと同ディレクトリ>/failed-screens.txt` |
| `FAIL_COUNTS` | 画面ごとの失敗回数を記録するTSVファイルの絶対パス | `<LOGと同ディレクトリ>/fail-counts.tsv` |
| `TARGET_REPO_PATH` | 対象プロジェクトのリポジトリルートパス | なし（必須） |
| `DOCS_ROOT` | 設計書の書き出し先ルートパス | なし（必須） |
| `TEMPLATE_ROOT` | テンプレートディレクトリパス | なし（必須） |
| `COMMON_DOCS_ROOT` | プロジェクト共通設計書パス | なし（必須） |
| `SURVEY_DOC_PATH` | アーキテクチャ調査書パス | なし（必須） |

macOS 標準の `/bin/bash`（バージョン3.2系）は連想配列を持たないため、失敗回数の管理は `awk` によるファイルベースのカウンタで行う。

## 2. ワンライナー骨格

```bash
nohup bash -c "$(cat <<'RHB_SCRIPT'
TARGETS_FILE="__TARGETS_FILE__"
MARKER_REGISTRY="__MARKER_REGISTRY__"
LOG="__LOG__"
WAIT_SECONDS=__WAIT_SECONDS__
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

touch "$FAILED_LIST" "$FAIL_COUNTS"

check_authored() {
  TARGET="$1"
  grep -A5 "screen_id: $TARGET" "$MARKER_REGISTRY" 2>/dev/null | grep -qE "status: (authored|baseline-established)"
}

check_baseline() {
  TARGET="$1"
  grep -A5 "screen_id: $TARGET" "$MARKER_REGISTRY" 2>/dev/null | grep -qE "status: baseline-established"
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
    remaining=$((remaining + 1))
    STAGE_OK=1

    if ! check_authored "$TARGET"; then
      PROMPT="__PER_ITEM_PROMPT_FIRST__"
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
        continue
      fi

      if ! check_authored "$TARGET"; then
        STAGE_OK=0
      fi
    fi

    if [ "$STAGE_OK" -eq 1 ]; then
      PROMPT="__PER_ITEM_PROMPT_SECOND__"
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
      fc=$(inc_fail_count "$TARGET")
      echo "[LAP $lap] 未完了 screen=$TARGET fail_count=$fc"
      if [ "$fc" -ge "$FAIL_LIMIT_K" ]; then
        echo "$TARGET" >> "$FAILED_LIST"
        echo "[LAP $lap] failedリストへ退避 screen=$TARGET"
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

1. `__TARGETS_FILE__` `__MARKER_REGISTRY__` `__LOG__` `__WAIT_SECONDS__` `__FAIL_LIMIT_K__` `__MODEL__` `__ALLOWED_TOOLS__` `__FAILED_LIST__` `__FAIL_COUNTS__` `__TARGET_REPO_PATH__` `__DOCS_ROOT__` `__TEMPLATE_ROOT__` `__COMMON_DOCS_ROOT__` `__SURVEY_DOC_PATH__` を起動引数の確定値で置換する
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

前半・後半は別々の `claude -p` 呼び出しに渡す独立したプロンプトであり、互いのセッション・コンテキストを共有しない（これにより盲検分離が成立する）。

### 4.1 前半テンプレート（著述）: `PER_ITEM_PROMPT_FIRST`

```
あなたは1画面のリバース設計著述を完遂するヘッドレスタスクです（前半: 原本コードを読む工程）。

対象画面: $TARGET
リポジトリ: $TARGET_REPO_PATH
設計書出力先: $DOCS_ROOT
テンプレート: $TEMPLATE_ROOT
共通設計書: $COMMON_DOCS_ROOT
アーキテクチャ調査書: $SURVEY_DOC_PATH

契約（必ず守ること）:
1. 対象画面の著述パイプラインを以下の順に全て実行する:
   - Skill(unlocking-reverse-target-screens) で画面開通
   - Skill(extracting-unit-facts-from-code) で事実封印
   - Skill(generating-reverse-basic-design) で基本設計著述
   - Skill(generating-reverse-detailed-design) で詳細設計著述
2. 全工程完了したら画面レジストリの当該エントリ status を `authored` に更新する（=中間マーカー付与）
3. 画面レジストリで当該画面の status が既に authored または baseline-established なら、何もせず即座に終了する

各 Skill の args は以下のリポジトリの SKILL.md に従い全量指定する:
- target_repo_path: $TARGET_REPO_PATH
- docs_root: $DOCS_ROOT
- screen_id: $TARGET
- template_root: $TEMPLATE_ROOT
- common_docs_root: $COMMON_DOCS_ROOT
- survey_doc_path: $SURVEY_DOC_PATH

工程途中で失敗した場合はそこで停止する（status は更新しない）。
```

### 4.2 後半テンプレート（ファイル単位盲検検証・往復検証）: `PER_ITEM_PROMPT_SECOND`

```
あなたは1画面のリバース設計検証を完遂するヘッドレスタスクです（後半: 設計書のみから判定する工程。原本コードは一切読まない）。

対象画面: $TARGET
リポジトリ: $TARGET_REPO_PATH
設計書出力先: $DOCS_ROOT
テンプレート: $TEMPLATE_ROOT
共通設計書: $COMMON_DOCS_ROOT

前提: 画面レジストリの当該エントリ status が authored であること（前半で著述済み）。この前提が満たされない場合は何もせず即座に終了する。

契約（必ず守ること）:
1. 対象リポジトリの原本コードを Read しない（盲検）。情報源は設計書と facts のみ
2. 検証パイプラインを以下の順に全て実行する:
   - Skill(rebuilding-screen-unit-from-docs) でファイル単位盲検検証（対象ファイルを白紙化し設計書のみから再現。無人モードでは必須工程）
   - Skill(syncing-reverse-env) mode=sync で基準確立
   - Skill(rebuilding-code-from-docs) mode=implement で比較要求を取得
   - Skill(syncing-reverse-env) mode=sync,dry-run で比較結果ブロックを取得
   - Skill(rebuilding-code-from-docs) mode=judge で比較結果ブロックを判定
3. status=PASS まで到達したら画面レジストリの当該エントリ status を `baseline-established` に更新する（=検証完了マーカー付与）
4. 検証完了後、Skill(syncing-reverse-env) mode=teardown（軽量: ポート・プロセスのみ解放し baseline_tag・成果物は保持）で環境スロットを解放する
5. 画面レジストリで当該画面の status が既に baseline-established なら、何もせず即座に終了する

各 Skill の args は以下のリポジトリの SKILL.md に従い全量指定する:
- target_repo_path: $TARGET_REPO_PATH
- docs_root: $DOCS_ROOT
- screen_id: $TARGET
- template_root: $TEMPLATE_ROOT
- common_docs_root: $COMMON_DOCS_ROOT

工程途中で失敗した場合はそこで停止する（status は baseline-established に更新しない）。
```
