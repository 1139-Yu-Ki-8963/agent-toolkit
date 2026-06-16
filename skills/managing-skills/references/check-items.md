# 観点チェック詳細

各 ID の検出方法（grep / python 式）と修正前後サンプル。`SKILL.md` から参照される詳細リファレンス。`<F>` は対象 SKILL.md のパス、`<NAME>` はスキル名を指す。

---

## A. frontmatter / メタデータ

### A1 — name の規約（CRITICAL）

`name` が kebab-case・64 字以内・（invocation 設定時）name==invocation か。

```bash
python3 - "$F" <<'PY'
import sys, re, yaml
fm = re.match(r'^---\n(.*?)\n---', open(sys.argv[1]).read(), re.S).group(1)
m = yaml.safe_load(fm)
name = m.get('name', '')
print('kebab-case:', bool(re.fullmatch(r'[a-z0-9]+(-[a-z0-9]+)*', name)), '/ len:', len(name))
if 'invocation' in m:
    print('name==invocation:', name == m['invocation'])
PY
```

```diff
-name: Reviewing_Skills
+name: reviewing-skills
```

### A2 — gerund 形（WARN）

`name` が「動詞 ing + 名詞」か。汎用語（do / handle / run）に置換しても意味が通るなら不十分（置き換えテスト）。

> **⚠️ 公式スキルは対象外**: プロバイダーが提供するスキル（`render-*` / `supabase-*` / `frontend-design` 等）は名前がプロバイダー側で固定されており変更不可。これらに A2 WARN を発行しない。カスタムスキル（`~/.claude/skills/` に自分で追加したスキル）のみを対象とする。

| 不十分 | 改善 |
|---|---|
| `skill-review` | `reviewing-skills` |
| `commit-helper` | `grouping-commits` |

判定は機械化しづらいため、先頭語が `-ing` で終わるかを一次フィルタにして目視確認する。公式スキルと判断できる場合はスキップする。

```bash
grep -m1 '^name:' "$F" | sed 's/name:[[:space:]]*//'
```

### A3 — TRIGGER when / SKIP の両在（CRITICAL）

```bash
grep -q 'TRIGGER when:' "$F" && grep -q 'SKIP:' "$F" \
  && echo OK || echo "MISSING: TRIGGER/SKIP"
```

```diff
 description: |
   PR 差分をセキュリティ観点でレビューする。
+  TRIGGER when: 「セキュリティレビュー」「脆弱性チェック」と言われた時。
+  SKIP: 差分を伴わない設計相談（→ managing-skills）。
```

### A4 — 説明文 50 字以内（CRITICAL）

50 字制限は **説明文（TRIGGER when 行より前）** にのみ適用する。`TRIGGER when:` / `SKIP:` の本文は計上しない（これらを含めると全スキルが超過となり誤検出するため）。

```bash
python3 - "$F" <<'PY'
import sys, re
t = open(sys.argv[1]).read()
# description: の直後から TRIGGER when 行の手前までを説明文とみなす
m = re.search(r'^description:\s*\|?\s*\n(.*?)(?=^\s*TRIGGER when:|^[a-z][\w-]*:|\n---)',
              t, re.M | re.S)
body = re.sub(r'\s+', '', m.group(1)) if m else ''
print(f'説明文 {len(body)} 字 / 上限 50（TRIGGER/SKIP は除外）')
PY
```

### A5 — 全スキル合計 2000 字（WARN・グローバル）

`conventions.md` の python ワンライナーを流用し、全 `~/.claude/skills/*/SKILL.md` の description 合計を測る。超過時は最長の description から圧縮する。

### A6 — invocation フィールド（CRITICAL）

`invocation` フィールドが存在し、`name` と同値か。

```bash
python3 - "$F" <<'PY'
import sys, re, yaml
fm = re.match(r'^---\n(.*?)\n---', open(sys.argv[1]).read(), re.S).group(1)
m = yaml.safe_load(fm)
inv = m.get('invocation')
name = m.get('name', '')
if inv is None:
    print('MISSING: invocation フィールドなし')
elif inv != name:
    print(f'MISMATCH: invocation={inv!r} != name={name!r}')
else:
    print('OK: invocation == name')
PY
```

```diff
+invocation: reviewing-skills
```

### A7 — allowed-tools の最小セット（WARN）

`allowed-tools` が未記載、または型の最小セットを下回る場合に検出する。型は `> Type:` 宣言（C5）から読み取る。

| 型 | 最小セット |
|---|---|
| 条件付き知識型 | Read, Grep, Glob |
| 手順型 | Bash, Read, Write, Edit |
| 強制型 | Agent, Read, Grep, Bash |

```bash
grep -E '^allowed-tools:' "$F" || echo "MISSING: allowed-tools"
```

```diff
+allowed-tools: Bash, Read, Write, Edit
```

---

## B. description 品質（発火条件）

### B1 — 具体キーワードの有無（WARN）

「コードレビュー用」のような抽象短文を検出する。TRIGGER when 行に「」で囲んだ反応語が 2 つ以上あるかを目安にする。

```bash
grep -A2 'TRIGGER when:' "$F" | grep -o '「[^」]*」' | wc -l
```

```diff
-description: コードレビュー用
+description: |
+  PR 差分の認証・入力検証・秘密情報を重点レビューし重大度付きで返す。
+  TRIGGER when: 「セキュリティレビュー」「脆弱性チェック」と言われた時。
```

### B2 — 発火範囲が広すぎる（WARN）

TRIGGER when に「実装」「修正」「対応」など汎用語のみが並ぶと誤発火する。固有の対象語で絞り、SKIP を補強する。

### B3 — SKIP の境界誘導（INFO）

SKIP が「〜の時」だけで止まり、代わりに使うべきスキル（→ xxx）を示していない。

```diff
-  SKIP: 新規作成の時。
+  SKIP: スキルライフサイクル全般（→ managing-skills）、命名のみ（→ naming-conventions）。
```

---

## C. 本体サイズ・段階的開示

### C1 / C2 — 行数（CRITICAL / WARN）

```bash
wc -l "$F"   # >500 で C1 CRITICAL, >200 で C2 WARN
```

200 行超は「目次＋最小手順」を本体に残し、詳細を `references/*.md` へ移す。

### C3 — 公式ドキュメントのコピー（WARN）

公式ドキュメント由来の長い仕様文を本文に貼っていないか。`/docs/` への参照リンクへ置換する。

### C4 — references の固有性（INFO）

`references/` が他スキルと重複する汎用情報になっていないか。そのスキル固有のパターン集・例に限定する。

### C5 — Category / Type 宣言（WARN）

frontmatter に `type:` が宣言されているか。`managing-skills` の review モードが型別最小セット検査（A7）に使うため必須。旧形式の本文 H1 直下 `> Category:` / `> Type:` blockquote は frontmatter `type:` に統合済み（残存していたら C5 で削除指示）。

```bash
grep -E '^> (Category|Type):' "$F"
```

9カテゴリ: ライブラリ参照 / 検証 / データ取得 / 業務自動化 / 雛形 / 品質・レビュー / CI-CD / Runbook / インフラ運用

3型: 手順型 / 条件付き知識型 / 強制型

```diff
 # my-skill
+> Category: 業務自動化
+> Type: 手順型
```

### C6 — Gotchas セクション（WARN）

`## Gotchas` セクションが存在するか。直感に反する罠・隠れた制約・読者が驚く挙動を 1 行でも記載する。

```bash
grep -q '^## Gotchas' "$F" && echo OK || echo "MISSING: ## Gotchas"
```

```diff
+## Gotchas
+- <罠の名前>: <実際の挙動> → <だからこうする>
```

---

## D. 単一責務

### D1 — 多責務の検出（WARN）

`## ` 見出しが無関係な責務（例: テスト実行 + 通知設定 + ドキュメント更新）を並列に持つ。責務ごとにスキルを分割する。

```bash
grep '^## ' "$F"
```

### D2 — 共通手順のコピペ（INFO）

複数スキルに同一手順（テストコマンド等）がコピペされていないか。参照元スキル 1 箇所へ一本化する。

---

## E. 副作用安全性

### E1 — オート発火可能な副作用コマンド（CRITICAL）

```bash
grep -nE 'git push|gh pr merge|gh release create|vercel deploy|supabase db push|rm -rf' "$F"
```

検出時は、SKILL.md 冒頭で「外部に影響を与える／ユーザー承認必須」を明記し、`AskUserQuestion` 承認または手動発火（invocation での明示呼び出し）に限定する。

### E2 — スクリプト直書き（WARN）

10 行を超える bash / python ブロックを本体に直書きしていないか。`scripts/` へ分離する（本環境では新規 `.sh` 作成禁止のため、既存スクリプト参照か手順記述に留める）。

### E3 — `!` 構文（WARN）

```bash
grep -nE '^\s*!|`!' "$F"   # Cursor 非互換の ! 構文
```

---

## F. Claude ツール活用（フロー系限定）

> 適用対象は SKILL.md 本体の「フロー系スキルの判定基準」を満たすスキルのみ。

### F1 — Phase 段階化（WARN）

```bash
# H2(##) / H3(###) のどちらの Phase 見出しも数える（実在スキルは ## Phase が主）
grep -cE '^#{2,3} Phase' "$F"   # 複数ステップなのに 0〜1 なら WARN
```

### F2 — サブエージェント委譲（WARN）

重い調査・並列分析・複数対象処理を、メインコンテキストで全部抱えず `Agent`（subagent_type 指定）へ委譲しているか。

```bash
grep -nE 'Agent\(|subagent_type|サブエージェント' "$F"
```

```diff
-各 PR を順番に読んでレビューする。
+各 PR について Agent ツールで reviewing-prs サブエージェントを並列起動し、
+結果を集約する（メインコンテキストを汚さない）。
```

### F3 — タスク管理（INFO）

多段・長時間フローで `TaskCreate` / `TaskUpdate` による進捗可視化を使っているか。

```bash
grep -nE 'TaskCreate|TaskUpdate|TaskList' "$F"
```

### F4 — プラン承認（WARN）

非自明な実装を伴うフローで `ExitPlanMode`（またはプラン提示→承認）をユーザーに取らせているか。取り消し困難な変更前の合意形成に有効。

```bash
grep -nE 'ExitPlanMode|プラン承認|計画モード' "$F"
```

### F5 — ユーザー確認（WARN）

取り消し困難な操作・分岐選択で `AskUserQuestion` を使っているか。

```bash
grep -nE 'AskUserQuestion' "$F"
```

### F6 — Skill ツール明示（INFO）

他スキルを呼ぶ箇所が「xxx スキルを使う」という手順記述だけで、`Skill` ツール起動として明示されていない。

```diff
-PR 本文は formatting-pr の手順に従って作る。
+Skill ツールで formatting-pr を起動し PR 本文を整形する。
```

### F7 — 仕組み化（WARN）

「Claude が適切に判断する」式の AI 挙動依存でなく、ツール呼び出し・条件分岐で仕組み化されているか（`anti-patterns.md` ⑧）。

---

## G. 登録・整合性

### G1 — 配置と絶対パス（CRITICAL）

SKILL.md が `~/.claude/skills/<NAME>/SKILL.md` にあるか。本文にユーザー名を含む絶対パス（`/Users/.../`）を直書きしていないか（`~/` または相対参照にする）。

```bash
grep -nE '/Users/[^/]+/' "$F"
```

### G2 — README 登録（WARN）

```bash
grep -q "<code>$NAME</code>" ~/.claude/skills/README.md \
  && echo registered || echo "MISSING in README"
```

### G3 — 見出しの日本語統一（INFO）

`## ` / `### ` 見出しに英語と日本語が混在していないか。

```bash
grep -E '^#{2,3} ' "$F"
```
