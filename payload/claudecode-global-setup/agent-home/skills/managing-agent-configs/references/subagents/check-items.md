# サブエージェント機械検出式集（check-items）

reviewing.md の機械判定可能な観点の grep / bash 検出式。review モードの Phase 2 冒頭と、testing.md のテスト前段（機械 lint）から実行する。CI 等の外部自動実行ではなく、Claude 自身が実行する。

## 現行有効モデル ID リスト（A4 / A8 の照合先）

```
claude-fable-5
claude-opus-4-8
claude-sonnet-5
claude-haiku-4-5-20251001
```

モデル世代が更新されたらこのリストを更新する（保守: 人手）。

## A1: name / dir / file の一致

```bash
for d in ~/agent-home/agents/*/; do
  n=$(basename "$d"); f="$d$n.md"
  [ -f "$f" ] || { echo "FAIL A1: $n ($n.md 不在)"; continue; }
  grep -q "^name: $n$" "$f" || echo "FAIL A1: $n (name フィールド不一致)"
done
```

## A2: TRIGGER when + SKIP の存在

```bash
for f in ~/agent-home/agents/*/*.md; do
  grep -q "TRIGGER when" "$f" || echo "FAIL A2: $f (TRIGGER 欠落)"
  grep -q "SKIP:" "$f" || echo "FAIL A2: $f (SKIP 欠落)"
done
```

## A3: description 1 行目 50 字以内

```bash
for f in ~/agent-home/agents/*/*.md; do
  line=$(awk '/^description: \|/{getline; gsub(/^ +/,""); print; exit}' "$f")
  len=$(printf '%s' "$line" | wc -m | tr -d ' ')
  [ "${len:-0}" -gt 50 ] && echo "WARN A3: $f (${len} 字)"
done; true
```

awk の length() はバイト数を返す環境があるため、文字数は wc -m で数える（日本語 1 字 = 3 バイトの過大計上を防ぐ）。

## A4 / A8: model の明示 ID・現行有効性

```bash
valid="claude-fable-5|claude-opus-4-8|claude-sonnet-5|claude-haiku-4-5-20251001"
for f in ~/agent-home/agents/*/*.md; do
  m=$(grep "^model:" "$f" | awk '{print $2}')
  [ -z "$m" ] && { echo "FAIL A4: $f (model 未指定)"; continue; }
  echo "$m" | grep -qE "^(opus|sonnet|haiku|inherit)$" && echo "FAIL A4: $f (エイリアス: $m)"
  echo "$m" | grep -qE "^($valid)$" || echo "FAIL A8: $f (無効 ID: $m)"
done
```

## A6: 許可フィールド白リスト照合

```bash
allow="name|description|tools|model|disallowedTools|permissionMode|mcpServers|skills|memory|background|hooks|isolation"
for f in ~/agent-home/agents/*/*.md; do
  awk '/^---$/{c++; next} c==1 && /^[a-zA-Z]+:/{print $1}' "$f" | tr -d ':' | while read -r k; do
    echo "$k" | grep -qE "^($allow)$" || echo "FAIL A6: $f (白リスト外フィールド: $k)"
  done
done
```

## A7: tools の明示

```bash
for f in ~/agent-home/agents/*/*.md; do
  grep -q "^tools:" "$f" || echo "FAIL A7: $f (tools 省略 = 全ツール継承)"
done
```

## A9: tools と disallowedTools の併用禁止

```bash
for f in ~/agent-home/agents/*/*.md; do
  grep -q "^tools:" "$f" && grep -q "^disallowedTools:" "$f" && echo "FAIL A9: $f (併用)"
done; true
```

## B1: 本文 100 行以内

```bash
for f in ~/agent-home/agents/*/*.md; do
  n=$(awk '/^---$/{c++; next} c>=2{print}' "$f" | wc -l | tr -d ' ')
  [ "$n" -gt 100 ] && echo "WARN B1: $f (本文 ${n} 行)"
done; true
```

## B3: セクション数 2〜4

```bash
for f in ~/agent-home/agents/*/*.md; do
  n=$(grep -c "^## " "$f")
  { [ "$n" -lt 2 ] || [ "$n" -gt 4 ]; } && echo "INFO B3: $f (セクション ${n})"
done; true
```

## C5: SKIP 代替先の実在

SKIP 行に登場するエージェント名が実体として存在するかの機械確認（双方向性の意味確認は目視で補完する）。

```bash
names=$(ls ~/agent-home/agents/)
for f in ~/agent-home/agents/*/*.md; do
  grep -A3 "SKIP:" "$f" | grep -oE "[a-z][a-z-]+[a-z]" | sort -u | while read -r w; do
    case "$w" in *-reviewer|worker-*|investigator|researcher|brain|plan-comprehension-prober)
      echo "$names" | grep -qx "$w" || echo "FAIL C5: $f (SKIP 参照先が不在: $w)";;
    esac
  done
done
```

## C7: 正本 4 点突合

4 点（①conventions.md 役割体系 ②subagent-selection 規約 ③カタログ HTML ④実体）それぞれに全エージェント名が掲載されているかを突合する。

```bash
for n in $(ls ~/agent-home/agents/); do
  grep -q "$n" ~/agent-home/skills/managing-agent-configs/references/subagents/conventions.md || echo "FAIL C7: conventions.md に $n 不在"
  grep -q "$n" ~/agent-home/rules/always/agent/subagent-selection/rule.md || echo "FAIL C7: subagent-selection 規約に $n 不在"
  [ -f ~/agent-home/ai-management-portal/catalog/subagents.html ] && { grep -q "$n" ~/agent-home/ai-management-portal/catalog/subagents.html || echo "FAIL C7: カタログ HTML に $n 不在"; }
done
```

## D4: references 内 md の name frontmatter 禁止

```bash
find ~/agent-home/agents/*/references -name "*.md" 2>/dev/null | while read -r f; do
  head -5 "$f" | grep -q "^name:" && echo "WARN D4: $f (name frontmatter あり)"
done; true
```

## E5: 合否宣言と分類の整合

判定系（code-reviewer / document-reviewer / business-content-reviewer / report-reviewer）以外の本文に PASS / FAIL 宣言の記述が無いか。

```bash
for f in ~/agent-home/agents/*/*.md; do
  n=$(basename "$f" .md)
  case "$n" in code-reviewer|document-reviewer|business-content-reviewer|report-reviewer) continue;; esac
  awk '/^---$/{c++; next} c>=2{print}' "$f" | grep -qE "PASS / FAIL を宣言|合否を宣言する" && echo "WARN E5: $f (非判定系が合否宣言)"
done; true
```

注意: SKIP 行の「合否の宣言はしない」のような否定文は違反ではない。検出時は文脈を目視確認する。

## 修正前後例

| 観点 | 修正前 | 修正後 |
|---|---|---|
| A4 | `model: sonnet` | `model: claude-sonnet-5` |
| A6 | `mode: claude-sonnet-5`（typo） | `model: claude-sonnet-5` |
| A7 | `tools:` 行なし | `tools: Read, Grep, Glob` |
| A9 | `tools: Read` + `disallowedTools: Write` | `tools: Read`（許可リストのみ） |
| C7 | 規約 4 分類表に business-content-reviewer 不在 | 判定系の行に追加 |
