# 観点別検出式（check-items）

`reviewing.md` の各観点に対応する具体的な検出コマンド。

## A. フォルダ構造

### A1: ルート直下 .md 残存

```bash
find ~/.claude/rules/ -maxdepth 1 -name "*.md" -type f
```

空出力なら PASS。

### A2: `-rules` suffix 残存 / rule.md 深さ不正

新形式では `-rules` suffix は廃止済み。`always/` `scoped/` 配下に suffix 付きディレクトリが残っていないか、rule.md が深さ 3（`<scope>/<topic>/<name>/rule.md`）以外に置かれていないかを検出する。

```bash
# -rules suffix が残存していないか（新形式では suffix 禁止）
find ~/.claude/rules/always ~/.claude/rules/scoped -mindepth 2 -maxdepth 2 -type d 2>/dev/null | while read d; do
  basename "$d" | grep -qE '\-rules$' && echo "FAIL: $d に -rules suffix が残存"
done

# rule.md が深さ 3 以外にないか（scoped/review-checklist/ 配下のみ深さ 4 が正。
# 統治規約: scoped/agent-config/review-checklist/rule.md）
find ~/.claude/rules/always ~/.claude/rules/scoped -name "rule.md" 2>/dev/null | while read f; do
  depth=$(echo "$f" | sed "s|$HOME/.claude/rules/||" | awk -F/ '{print NF-1}')
  case "$f" in
    */scoped/review-checklist/*)
      [ "$depth" -eq 4 ] || echo "FAIL: $f が深さ 4 以外にある (review-checklist 配下, depth=$depth)" ;;
    *)
      [ "$depth" -eq 3 ] || echo "FAIL: $f が深さ 3 以外にある (depth=$depth)" ;;
  esac
done
```

### A3: rule.md 欠落

```bash
for d in ~/.claude/rules/always/*/*/ ~/.claude/rules/scoped/*/*/; do
  [ -d "$d" ] || continue
  [ -f "$d/rule.md" ] || echo "FAIL: $d に rule.md がない"
done
```

### A4: hook script の分離検出

```bash
# settings.json から command path を抽出し、rule.md と同ディレクトリか確認
jq -r '.. | .command? // empty' ~/.claude/settings.json | grep '\.claude/rules/' | while read cmd; do
  script_dir=$(dirname "$cmd" | sed "s|\\\$HOME|$HOME|")
  [ -f "$script_dir/rule.md" ] || echo "WARN: $cmd の rule.md が同ディレクトリにない"
done
```

## B. scope 適合性

### B1: プロジェクト固有キーワード検出

```bash
# <project固有語彙をパイプ区切りで列挙>（例: 'internal-slot-id|owner-context|mock-fixture|internal-queue-name'）
PROJECT_SPECIFIC_KEYWORDS='internal-slot-id|owner-context|mock-fixture|internal-queue-name'

for d in ~/.claude/rules/always/*/*/ ~/.claude/rules/scoped/*/*/; do
  [ -f "$d/rule.md" ] || continue
  hits=$(grep -cE "$PROJECT_SPECIFIC_KEYWORDS" "$d/rule.md" 2>/dev/null || echo 0)
  [ "$hits" -gt 0 ] && echo "CRITICAL: $(basename $d) にプロジェクト固有キーワード $hits 件"
done
```

## C. hook 連携

### C1: additionalContext のプロンプト埋め込み検出

```bash
for sh in ~/.claude/rules/{always,scoped}/*/*/*.sh; do
  [ -f "$sh" ] || continue
  # ctx= 変数の長さを計測
  ctx_len=$(grep -A 20 'ctx=' "$sh" | head -20 | wc -c | tr -d ' ')
  [ "$ctx_len" -gt 300 ] && echo "CRITICAL: $(basename $sh) の ctx が $ctx_len 文字（300 字超）"
done
```

### C2: rule.md 参照の有無

```bash
for sh in ~/.claude/rules/{always,scoped}/*/*/*.sh; do
  [ -f "$sh" ] || continue
  grep -q 'rule\.md' "$sh" || echo "WARN: $(basename $sh) に rule.md への参照がない"
done
```

### C3: command path の実在確認

```bash
jq -r '.. | .command? // empty' ~/.claude/settings.json | while read cmd; do
  path=$(echo "$cmd" | sed 's/\$HOME/'"$HOME"'/g' | awk '{print $NF}' | sed 's/ .*//')
  [ -f "$path" ] || echo "CRITICAL: $path が存在しない"
done
```

### C5-C6: shebang と実行ビット

```bash
for sh in ~/.claude/rules/{always,scoped}/*/*/*.sh; do
  [ -f "$sh" ] || continue
  head -1 "$sh" | grep -q '^#!/' || echo "WARN: $(basename $sh) に shebang がない"
  [ -x "$sh" ] || echo "WARN: $(basename $sh) に実行ビットがない"
done
```

## E. ADR

### E1-E3: 設計判断セクション

```bash
for d in ~/.claude/rules/always/*/*/ ~/.claude/rules/scoped/*/*/; do
  [ -f "$d/rule.md" ] || continue
  name=$(basename "$d")
  grep -q '## 設計判断' "$d/rule.md" || { echo "CRITICAL: $name に設計判断セクションがない"; continue; }
  grep -q '必要性' "$d/rule.md" || echo "WARN: $name の ADR に「必要性」がない"
  grep -q '代替案' "$d/rule.md" || echo "WARN: $name の ADR に「代替案」がない"
  grep -q '保守責任者' "$d/rule.md" || echo "WARN: $name の ADR に「保守責任者」がない"
  grep -q '廃棄条件' "$d/rule.md" || echo "WARN: $name の ADR に「廃棄条件」がない"
done
```

## F. 注入タグの整合性

### F1-F2: タグ突合

```bash
for d in ~/.claude/rules/always/*/*/ ~/.claude/rules/scoped/*/*/; do
  [ -f "$d/rule.md" ] || continue
  name=$(basename "$d")
  # rule.md 内のタグ
  rule_tags=$(grep -oE '\[([A-Z][A-Z0-9-]+)\]' "$d/rule.md" | sort -u)
  # .sh 内のタグ
  sh_tags=""
  for sh in "$d"/*.sh; do
    [ -f "$sh" ] || continue
    sh_tags="$sh_tags $(grep -oE '\[([A-Z][A-Z0-9-]+)\]' "$sh" | sort -u)"
  done
  sh_tags=$(echo "$sh_tags" | tr ' ' '\n' | sort -u | grep -v '^$')
  # .sh にあるが rule.md にないタグ
  for tag in $sh_tags; do
    echo "$rule_tags" | grep -q "$tag" || echo "CRITICAL: $name — $tag が .sh にあるが rule.md にない"
  done
done
```

## C7-C8: 環境依存前提

既知 CLI × 既知の「暗黙解決を示す呼び出しパターン」× 既知の「上書き引数」の対応表で機械検出する。

```bash
# gh: {owner}/{repo} プレースホルダを使っている ⇒ --repo/-R を読んでいるか
# git: 単純呼び出し(diff/fetch/cat-file/log)で -C を使っていない ⇒ --git-dir/--work-tree/-C を読んでいるか
for sh in ~/.claude/rules/{always,scoped}/*/*/*.sh; do
  [ -f "$sh" ] || continue
  implicit=$(grep -cE '\{owner\}/\{repo\}' "$sh" 2>/dev/null || echo 0)
  [ "$implicit" -gt 0 ] || continue
  if grep -qE -- '--repo|-R[[:space:]]' "$sh"; then
    echo "WARN: $(basename $sh) — --repo/-R 抽出コードはあるが、抽出結果が全ての暗黙呼び出し箇所に反映されているかは要人手確認"
  else
    echo "CRITICAL: $(basename $sh) — {owner}/{repo} プレースホルダに依存しているが --repo/-R を抽出していない"
  fi
done
```

修正前後例（`check-approved-sha-on-merge.sh` が実例。(撤去済み hook の歴史事例)）:

修正前:
```bash
gh api "repos/{owner}/{repo}/pulls/$PR_NUMBER/reviews"
```

修正後:
```bash
REPO_ARG=$(printf '%s' "$COMMAND" | grep -oE '(--repo|-R)[[:space:]]+[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+' | ...)
if [ -n "$REPO_ARG" ]; then gh api "repos/$REPO_ARG/pulls/$PR_NUMBER/reviews"; else gh api "repos/{owner}/{repo}/pulls/$PR_NUMBER/reviews"; fi
```

### 機械化できる範囲 / 人間・サブエージェント判断が必要な範囲

| 範囲 | 判定手段 |
|---|---|
| 既知 CLI + 既知プレースホルダ + 抽出コード有無の突合 | 機械（grep のみ、CRITICAL/WARN 判定まで自動） |
| 抽出した変数が全ての暗黙呼び出し箇所に実際に伝播しているか（制御フロー） | 人間 or Phase 2.5 のロジックレビューへ委譲 |
| cwd 自体が対象と異なる worktree の場合の二次的失敗 | 人間 or Phase 2.5 へ委譲 |
| ホワイトリストにない CLI・未知のラップパターン | 機械検出不可。Phase 2.5 のロジックレビューでのみ発見できる |

## G. 内容品質

### G1: 行数

```bash
for d in ~/.claude/rules/always/*/*/ ~/.claude/rules/scoped/*/*/; do
  [ -f "$d/rule.md" ] || continue
  lines=$(wc -l < "$d/rule.md" | tr -d ' ')
  [ "$lines" -gt 200 ] && echo "INFO: $(basename $d)/rule.md が $lines 行（200 行超）"
done
```

## I. 参照実在

### I1: rule.md が言及するパスの実在

検出対象はバッククォートで囲まれた `~/` 始まりのパス。プレースホルダ（`<repo>`・`<name>` 等）・glob（`*`）・変数（`$`）を含むものは対象外。

```bash
for d in ~/.claude/rules/always/*/*/ ~/.claude/rules/scoped/*/*/; do
  [ -f "$d/rule.md" ] || continue
  grep -oE '`~/[^`]+`' "$d/rule.md" | tr -d '`' | grep -vE '[<>*$]' | sort -u | while IFS= read -r p; do
    ep="${p/#\~/$HOME}"
    [ -e "$ep" ] || echo "CRITICAL: ${d}rule.md が実在しないパスを参照: $p"
  done
done
```

修正前後例:

修正前（参照先が存在しない。例示のため `<repo>` プレースホルダ表記にしてある）:
```markdown
**まず `~/Projects/<repo>/docs_site/規約・基準/コードレビュー観点.md` を Read する。**
```

修正後（実在する正本へ差し替え、または正本を新設してから参照）:
```markdown
観点の正本は `~/.claude/rules/scoped/review-checklist/code/common/rule.md`。
```
