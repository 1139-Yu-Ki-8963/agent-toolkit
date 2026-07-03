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

# rule.md が深さ 3 以外にないか
find ~/.claude/rules/always ~/.claude/rules/scoped -name "rule.md" 2>/dev/null | while read f; do
  depth=$(echo "$f" | sed "s|$HOME/.claude/rules/||" | awk -F/ '{print NF-1}')
  [ "$depth" -eq 3 ] || echo "FAIL: $f が深さ 3 以外にある (depth=$depth)"
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
ORADORA_KEYWORDS='slot/wt|owner.cwd|portal|mock_awaiting|spawn-child|ledger|\.slot-pool|worktrees/owner|EnterWorktree|ai-management-portal.*8780'

for d in ~/.claude/rules/always/*/*/ ~/.claude/rules/scoped/*/*/; do
  [ -f "$d/rule.md" ] || continue
  hits=$(grep -cE "$ORADORA_KEYWORDS" "$d/rule.md" 2>/dev/null || echo 0)
  [ "$hits" -gt 0 ] && echo "CRITICAL: $(basename $d) に oradora 固有キーワード $hits 件"
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

## G. 内容品質

### G1: 行数

```bash
for d in ~/.claude/rules/always/*/*/ ~/.claude/rules/scoped/*/*/; do
  [ -f "$d/rule.md" ] || continue
  lines=$(wc -l < "$d/rule.md" | tr -d ' ')
  [ "$lines" -gt 200 ] && echo "INFO: $(basename $d)/rule.md が $lines 行（200 行超）"
done
```
