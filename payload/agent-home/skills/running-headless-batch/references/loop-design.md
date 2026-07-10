# ループ雛形の正本

`running-headless-batch` の Phase 4 で使う無人バッチループの雛形。プレースホルダを実値に置換し、Bash ツール1コマンド（`nohup bash -c "$(cat <<'RHB_SCRIPT' ... RHB_SCRIPT)" >> ログ 2>&1 & disown` 構造）としてそのまま実行する。ヒアドキュメント区切り子を引用符付き（`'RHB_SCRIPT'`）にすることで、雛形内の `$VAR` 参照が展開されずに実行時までそのまま渡り、かつスクリプトをディスクへファイル保存せずに1回のコマンド呼び出しで完結する。

## 1. プレースホルダ定義表

| プレースホルダ | 説明 | 既定値 |
|---|---|---|
| `TARGETS_FILE` | Phase 2 で正規化済みの対象一覧（1行1対象）の絶対パス | なし（必須） |
| `MARKER` | 完了判定に使うマーカー文字列。対象への付与位置は Phase 1 で確定した仕様に従う（例: 対象ファイル内に追記、または対象専用の完了ログに記録） | なし（必須） |
| `CHECK_CMD` | 対象1件が完了しているかを判定するシェル条件式。`$TARGET` と `$MARKER` を参照できる（例: `grep -q -F -- "$MARKER" "$TARGET" 2>/dev/null`） | なし（必須） |
| `LOG` | 実行ログの出力先絶対パス | なし（必須） |
| `WAIT_SECONDS` | limit 検知時の待機秒数 | 3600（60分） |
| `FAIL_LIMIT_K` | 同一対象の連続失敗上限 | 3 |
| `MODEL` | `claude -p` に渡すモデル名 | 安価モデル（例: haiku 系） |
| `ALLOWED_TOOLS` | `--allowedTools` に渡すツール一覧（カンマ区切り） | Phase 1 で確定した編集許可範囲に対応するツール |
| `PER_ITEM_PROMPT` | 1件分プロンプトのテンプレート文字列。`$TARGET` を対象パスへの置換対象として含む | 本ファイル §4 参照 |
| `FAILED_LIST` | 連続失敗で K 回に達した対象の退避先絶対パス | `<LOG と同じディレクトリ>/failed.txt` |
| `FAIL_COUNTS` | 対象ごとの失敗回数を記録する TSV（タブ区切り値）ファイルの絶対パス | `<LOG と同じディレクトリ>/fail-counts.tsv` |

macOS 標準の `/bin/bash`（バージョン3.2系）は連想配列（`declare -A`）を持たない。`bash -c` で起動したプロセスがどの `bash` を解決するかは環境依存のため、失敗回数の管理は連想配列に頼らず、`awk` によるファイルベースのカウンタ（`FAIL_COUNTS`）で行う。`awk` は macOS 標準搭載でバージョン非依存に動く。

## 2. ワンライナー骨格

```bash
nohup bash -c "$(cat <<'RHB_SCRIPT'
TARGETS_FILE="__TARGETS_FILE__"
MARKER="__MARKER__"
LOG="__LOG__"
WAIT_SECONDS=__WAIT_SECONDS__
FAIL_LIMIT_K=__FAIL_LIMIT_K__
MODEL="__MODEL__"
ALLOWED_TOOLS="__ALLOWED_TOOLS__"
FAILED_LIST="__FAILED_LIST__"
FAIL_COUNTS="__FAIL_COUNTS__"

touch "$FAILED_LIST" "$FAIL_COUNTS"

check_done() {
  # $1 = TARGET。完了していれば真を返す。CHECK_CMD の中身をここに展開する。
  TARGET="$1"
  __CHECK_CMD__
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

# 周回ループには意図的に上限を設けていない。要件「残ゼロまで継続」を文字通り満たすため。
# 暴走防止は対象単位のFAIL_LIMIT_Kのみで担保する（全対象が成功またはfailedリスト行きで確定すればremaining=0になり自然終了する）。
lap=0
while :; do
  lap=$((lap + 1))
  remaining=0
  progressed=0
  echo "[LAP $lap] start $(date '+%Y-%m-%d %H:%M:%S')"

  while IFS= read -r TARGET; do
    [ -z "$TARGET" ] && continue
    grep -qxF -- "$TARGET" "$FAILED_LIST" && continue

    if check_done "$TARGET"; then
      continue
    fi
    remaining=$((remaining + 1))

    PROMPT="__PER_ITEM_PROMPT__"
    PROMPT="${PROMPT//\$TARGET/$TARGET}"

    OUTPUT=$(claude -p "$PROMPT" \
      --model "$MODEL" \
      --allowedTools "$ALLOWED_TOOLS" \
      --permission-mode dontAsk \
      --no-session-persistence \
      --output-format text 2>&1)

    if echo "$OUTPUT" | grep -qiE 'usage limit|rate limit|session limit|limit reached|limit will reset|You.ve reached'; then
      echo "[LAP $lap] limit検知 target=$TARGET -> ${WAIT_SECONDS}秒待機"
      sleep "$WAIT_SECONDS"
      continue
    fi

    if check_done "$TARGET"; then
      echo "[LAP $lap] 成功 target=$TARGET"
      progressed=$((progressed + 1))
    else
      fc=$(inc_fail_count "$TARGET")
      echo "[LAP $lap] 未完了 target=$TARGET fail_count=$fc"
      if [ "$fc" -ge "$FAIL_LIMIT_K" ]; then
        echo "$TARGET" >> "$FAILED_LIST"
        echo "[LAP $lap] failedリストへ退避 target=$TARGET"
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

1. `__TARGETS_FILE__` `__MARKER__` `__LOG__` `__WAIT_SECONDS__` `__FAIL_LIMIT_K__` `__MODEL__` `__ALLOWED_TOOLS__` `__FAILED_LIST__` `__FAIL_COUNTS__` を Phase 1 の確定値で置換する
2. `__CHECK_CMD__` を Phase 1 で確定した成否判定コマンド（`$TARGET` と `$MARKER` を参照するシェル条件式）で置換する
3. `__PER_ITEM_PROMPT__` を §4 のテンプレートを埋めた文字列で置換する。プロンプト内の `\$TARGET` は実行時に `check_done` と同じ `$TARGET` へ展開されるよう、スクリプト側の `PROMPT="${PROMPT//\$TARGET/$TARGET}"` 行で対応する
4. 置換済みの全文を1個の Bash ツール呼び出しとして実行する。事前にファイルへ保存しない

起動直後の生存確認:

```bash
sleep 10
kill -0 "$BG_PID" && echo "生存中" || echo "起動直後に終了した（要調査）"
```

## 3. limit検知の正規表現パターン集（正本）

```
grep -qiE 'usage limit|rate limit|session limit|limit reached|limit will reset|You.ve reached'
```

上記を基本形とする。claude CLI のバージョン更新でメッセージ文言が変わった場合は、実際に観測した新しい文言をこのパターンに `|` で追補する。追補時は本ファイルの当該行を更新し、既存のパターンを削除せず追加のみ行う（既存パターンとの後方互換を保つため）。

## 4. 1件分プロンプトのテンプレート（3要素契約入り）

```
あなたは1件の対象を処理するヘッドレスタスクです。

対象: $TARGET

契約（必ず守ること）:
1. 編集してよい範囲は「$TARGET 自身のみ」（Phase 1 で確定した編集許可範囲に置き換える）。それ以外のファイルには一切触れない。
2. 作業が完了したら、必ず次のマーカーを付与すること: __MARKER__
   付与位置: Phase 1 で確定した仕様（対象ファイル内への追記、または完了ログへの記録）に従う。
3. 対象に既に上記マーカーが付与されている場合、何もせず即座に終了すること。

作業内容: <ここに Phase 1 で確定した具体的な作業指示を記載する>
```
