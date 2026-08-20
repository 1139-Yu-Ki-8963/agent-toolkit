# CLAUDE.md ドメイン個別チェック項目（claude-md-checks）

`managing-agent-configs` に CLAUDE.md 専用の reviewing.md 正本が存在しないため、**本ファイルが CLAUDE.md ドメインの唯一の基準定義**である。他ドメイン（rules/skills/hooks/subagents/hygiene）のように外部正本へのポインタでは済ませられない。

## 前提: 7 層配置決定木

判定の土台は `~/.claude/rules/scoped/agent-config/placement/rule.md` の 7 層配置決定木（CLAUDE.md / Rules / Skills / Subagents / Hooks / Output styles / --append-system-prompt）である。本ドメインの診断エージェントは診断開始前に同ファイルを Read し、決定木の Q1〜Q8 を判定基準として保持する。

## 観点表

| 観点キー | チェック内容 | 検出方法 | 重み |
|---|---|---|---|
| 配置決定木-手順未分離 | 30 行超の手順・フロー・チェックリストが CLAUDE.md に直書きされ、Skills に分離されていないか（決定木 Q4 に該当するのに未分離） | 見出し配下の行数を数え、手順的記述（番号付き手順・「〜する→〜する」の連続）を検出 | CRITICAL |
| 配置決定木-hook未移行 | 「毎回 X したら必ず Y せよ」「絶対に〜するな」等、機械強制可能な断定的禁止事項が Hook（決定木 Q1）に移行されず CLAUDE.md に残っていないか | `grep -nE '絶対に|必ず.*せよ|禁止する'` で該当文を抽出し、対応する hook の有無を settings.json 側と突合 | CRITICAL |
| 本体行数-200行上限 | CLAUDE.md 本体が 200 行を超えていないか | `wc -l CLAUDE.md` | WARN |
| dead-code-重複記載 | hooks/skills/rules が既に機械強制している行動規約（禁止事項・手順）を CLAUDE.md にも重複記載していないか | CLAUDE.md 内の禁止事項文言を抽出し、対象プロジェクトの `.claude/settings.json` の hooks コマンド・`.claude/rules/*/rule.md` の同一趣旨記述と突合 | WARN |
| 参照パス-実在確認 | CLAUDE.md が言及する rules/skills/hooks への参照パスが実在するファイルを指しているか | 言及されたパスを `[ -f <path> ]` / `[ -d <path> ]` で確認 | CRITICAL |
| 陳腐化記述-廃止参照 | 廃止済みの hook 名・skill 名・rule 名への言及が残っていないか | 言及されたファイル・ディレクトリ名が実在しない場合、リネーム痕跡（git log）と照合し廃止判定 | WARN |

## 検出コマンド例

観点キーごとの Bash 検出例（investigator が実際に叩く想定のコマンド）。

```bash
# 配置決定木-手順未分離: 番号付き手順が 30 行以上連続する見出しブロックを抽出
awk '/^## /{h=$0} /^[0-9]+\. /{c[h]++} END{for (k in c) if (c[k tmp]>=6) print k}' CLAUDE.md

# 配置決定木-hook未移行: 断定的禁止・強制表現を抽出
grep -nE '絶対に|必ず.*せよ|禁止する' CLAUDE.md

# 本体行数-200行上限
wc -l CLAUDE.md

# dead-code-重複記載: CLAUDE.md の禁止事項文言が settings.json の hook コマンドと重複していないか
grep -nE '禁止|してはならない' CLAUDE.md
jq -r '.hooks[][] .hooks[].command' .claude/settings.json 2>/dev/null

# 参照パス-実在確認: CLAUDE.md 内で言及されたパスの実在確認
grep -oE '~/[A-Za-z0-9_./-]+' CLAUDE.md | while read -r p; do
  expanded="${p/#\~/$HOME}"
  [ -e "$expanded" ] && echo "OK: $p" || echo "MISSING: $p"
done

# 陳腐化記述-廃止参照: 言及されたファイル名が git 上で削除・リネーム済みか
git log --diff-filter=DR --summary -- '<言及されたファイル名>'
```

## 判定への反映

- CRITICAL 1 件以上検出時点で claude-md ドメインは C 以下（`references/grading-rules.md` §1・§4 に従う）
- CRITICAL 0 かつ WARN 0 かつ充足率 90% 以上（6 観点中 6 満たす）で S
- 充足率の分母は本表の 6 観点固定。CLAUDE.md が存在しないプロジェクトは `present: false` で D 確定とし、本表は評価しない

## 対象外（誤検知防止）

- 一般名詞としての「hook」「rule」「skill」への言及（固有ファイル名を指さない文脈）は参照パス-実在確認の対象に含めない
- CLAUDE.md 内のプレースホルダー（記入例・テンプレ由来の残骸）は陳腐化記述と別観点であり、本表では扱わない。プレースホルダー残存は本スキルの対象外（`~/.claude/CLAUDE.md` の Maintenance Notes に委ねる運用上の注意点であり、機械判定の対象としない）

## 参照資料

- `~/.claude/rules/scoped/agent-config/placement/rule.md` — 7 層配置決定木（本ファイルの判定土台）
- `references/grading-rules.md` — グレード判定式・findings JSON スキーマの正本
- `references/domain-briefs.md` — 他 5 ドメインの診断委任定義（共通禁止ブロックを共有）
