# 規約とスキルと hook の一覧

この文書は、skill-factory の `.claude/` の下にある規約 6 フォルダ、スキル 13 本、hook 3 本ごとに、何であるかと、検査を通ったかを持つ 3 つの表を持つ文書です。README の「フォルダの中身」の表が名前だけを持つのに対して、この文書は、各ファイルが受けた検査を持ちます。この文書では、作った人がスキルの実体を管理する git リポジトリを「作業用リポジトリ」と呼びます。「最後に変えたコミット」の列は、作業用リポジトリのコミットのうち、今の時点でその行のファイルを最後に変えたコミットの短い hash です。丸の hash と「最後に変えたコミット」が同じなら、検査のあとに更新はありません。

## 規約の表

| 規約 | パス | 読み込まれる条件 | 最後に変えたコミット | rule-writing-rule | text-writing-rule | ピンクの象の除去 |
|---|---|---|---|---|---|---|
| text-writing-rule | `.claude/rules/text-writing/text-writing-rule.md` | 常に | 63c6b6d1 |  |  |  |
| thinking-rule | `.claude/rules/thinking/thinking-rule.md` | 常に | f9ad5725 |  |  |  |
| skill-or-rule | `.claude/rules/skill-or-rule/skill-or-rule.md` | 常に | 555a7924 |  |  |  |
| skill-making-flow-rule | `.claude/rules/skill-making-flow/skill-making-flow-rule.md` | 常に | 555a7924 |  |  |  |
| skill-writing-rule | `.claude/rules/skill-writing/skill-writing-rule/skill-writing-rule.md` | `skills/*/SKILL.md`、`skills/*/references/`、`skills/*/scripts/` の下を読んだとき | b7f24c33 |  |  |  |
| skill-template | `.claude/rules/skill-writing/skill-template/skill-template.md` | `skills/*/SKILL.md`、`skills/*/references/` の下を読んだとき | 2dfa58e0 | 対象外 |  |  |
| skill-completed-example | `.claude/rules/skill-writing/skill-template-completed-example/skill-completed-example.md` | `skills/*/SKILL.md`、`skills/*/references/` の下を読んだとき | 7dbc4836 | 対象外 |  |  |
| skill-test-design-rule | `.claude/rules/skill-testing/skill-test-design-rule.md` | `skills/tests/` の下か、段階 6 から 8 のスキルと fixing-skill のフォルダの下を読んだとき | 3ef9f52a |  |  |  |

## スキルの表

「段階」は、規約 skill-making-flow の規則「段階と、段階が使うスキルと、段階の入力と最終出力」の表の番号です。「補助」は、hook と fixing-skill が呼ぶスキルです。

| スキル | 段階 | 最後に変えたコミット | skill-writing-rule | text-writing-rule | ピンクの象の除去 | シナリオテスト |
|---|---|---|---|---|---|---|
| defining-skill-requirements | 1 | 0984deba |  |  |  | ○ 2026-10-25 0984deba |
| designing-skill-structure | 2 | 143d08c8 |  |  |  | ○ 2026-10-25 143d08c8 |
| designing-skill-phases | 3 | 143d08c8 |  |  |  | ○ 2026-10-25 143d08c8 |
| drafting-skill-with-template | 4 | 0984deba |  |  |  | ○ 2026-10-25 0984deba |
| checking-skill-with-template | 5 | a5c6c55b |  |  |  | ○ 2026-10-25 a5c6c55b |
| fixing-skill | 5 | 143d08c8 | ○ 2026-10-25 143d08c8 |  |  | ○ 2026-10-25 143d08c8 |
| designing-skill-test-cases | 6 | 143d08c8 | ○ 2026-10-25 143d08c8 |  |  | ○ 2026-10-25 143d08c8 |
| designing-skill-test-scenarios | 7 | 2dfa58e0 |  |  |  | ○ 2026-10-25 2dfa58e0 |
| testing-skill-with-template | 8 | 143d08c8 |  |  |  | ○ 2026-10-25 143d08c8 |
| fixing-test-plan | 8 | 2dfa58e0 |  |  |  | ○ 2026-10-25 2dfa58e0 |
| checking-markdown-document-with-rules | 補助 | 2dfa58e0 |  |  |  |  |
| fixing-markdown-document | 補助 | 2dfa58e0 |  |  |  |  |
| rewrite-pink-elephants | 補助 | 305fed4b | 対象外 |  |  | 対象外 |

## hook の表

「検査の名前」と「テスト」の中身は、`.claude/hooks/<hook の名前>/README.md` の「検査」の表にあります。「テストの合格」の丸は、README の「確かめ方」のコマンドのすべてのテストが合格した日付と hash です。

| hook | 発火点 | matcher | 検査の名前 | 最後に変えたコミット | テストの合格 |
|---|---|---|---|---|---|
| pre-tool-use-write-file | PreToolUse | `Edit\|Write\|NotebookEdit` | blockUnguidedSkillWrite | 2666a0d4 |  |
| post-tool-use-write-file | PostToolUse | `Edit\|Write` | remindPinkElephants、checkLinks、checkHookRequires、checkHookTests、requestRuleCheck | 2666a0d4 |  |
| post-tool-use-any-tool | PostToolUse | `*` | detectUnguidedSkillChange | 2666a0d4 |  |

## 列ごとの規約とスキル

検査の列は、左から、作った人が検査を通す順に並びます。規約の表とスキルの表の検査の列の名前は、規約との照合の列では突き合わせる規約の名前とし、ピンクの象の除去とシナリオテストの列では検査の名前とします。

### スキルの表の列

| 列 | 丸が示すこと | 突き合わせる規約 | 突き合わせるスキル | 直すスキル |
|---|---|---|---|---|
| skill-writing-rule | スキルが、雛形 skill-template との照合と、規約 skill-writing-rule の機械的な規則との照合(完成例 skill-completed-example を目盛りにする)の両方を通った | skill-writing-rule、雛形 skill-template、完成例 skill-completed-example | checking-skill-with-template | fixing-skill |
| text-writing-rule | スキルの `SKILL.md` と `references/` が、規約 text-writing-rule の機械的な規則との照合を通った | text-writing-rule | checking-markdown-document-with-rules | fixing-skill |
| ピンクの象の除去 | スキルの `SKILL.md` と `references/` に、rewrite-pink-elephants を流した | rewrite-pink-elephants の判定の基準 | rewrite-pink-elephants | なし |
| シナリオテスト | スキルが、testing-skill-with-template の最新の判定の記録で、実施したすべてのケースに合格した | skill-test-design-rule | designing-skill-test-cases(テストケース)、designing-skill-test-scenarios(シナリオ)、testing-skill-with-template(実施と判定) | fixing-skill(スキル)、fixing-test-plan(テスト計画書) |

### 規約の表の列

| 列 | 丸が示すこと | 突き合わせる規約 | 突き合わせるスキル | 直すスキル |
|---|---|---|---|---|
| rule-writing-rule | 規約が、規約 rule-writing-rule の機械的な規則との照合を通った | rule-writing-rule | checking-markdown-document-with-rules | fixing-markdown-document |
| text-writing-rule | 規約のファイルが、規約 text-writing-rule の機械的な規則との照合を通った | text-writing-rule | checking-markdown-document-with-rules | fixing-markdown-document |
| ピンクの象の除去 | 規約のファイルに、rewrite-pink-elephants を流した | rewrite-pink-elephants の判定の基準 | rewrite-pink-elephants | なし |

## 値の書き方

- 丸の値は、`○ <検査した日付> <作業用リポジトリのコミットのうち、検査した時点でその行のファイルを最後に変えたコミットの短い hash>`、`対象外`、空の 3 つのどれかです。
- 「最後に変えたコミット」の値は、スキルの行では `git log -1 --format=%h -- skills/<スキルの名前>`、規約の行では `git log -1 --format=%h -- <規約のファイルのパス>`、hook の行では `git log -1 --format=%h -- hooks` を作業用リポジトリで実行した出力です。作った人は、検査の丸を書くときに、この値を書き換えます。

## 丸を付ける条件

この章のすべての列で、判定の仕方が「AI の推論」の規則の指摘と、判定の仕方が「AI の推論」のケースの「不合格」と「判定できない」と、rewrite-pink-elephants の書き直しの箇所は、警告とし、丸の条件に含めません。

### スキルの表

| 列 | ○ にする条件 | 対象外にする条件 |
|---|---|---|
| skill-writing-rule | checking-skill-with-template の指摘の一覧で、雛形の照合の違反と、判定の仕方が「機械的」の規則の違反が、ともに 0 件 | 雛形「スキルの雛形(phase と step)」で作ったスキルでない |
| text-writing-rule | サブエージェントが `SKILL.md` と `references/` の全文を規約 text-writing-rule の全規則と突き合わせ、判定の仕方が「機械的」の規則の違反が 0 件 | なし |
| ピンクの象の除去 | rewrite-pink-elephants が `SKILL.md` と `references/` の各ファイルを読み、書き直しの案を出した | なし |
| シナリオテスト | testing-skill-with-template の判定の記録で、判定の仕方が「機械的」のケースがすべて合格。警告は「警告の記録」の章に書く。同じスキルの判定の記録が 2 件以上あるときは、実行日時が最新の 1 件で判定する。前の判定の記録で合格したケースが、同じ依頼を流しても実行ごとに出力が変わること(実行者の揺れ)で不合格になったときは、そのケースを合格として数え、「警告の記録」の章に書く | 雛形「スキルの雛形(phase と step)」で作ったスキルでない |

### 規約の表

| 列 | ○ にする条件 | 対象外にする条件 |
|---|---|---|
| rule-writing-rule | サブエージェントが規約の全文を規約 rule-writing-rule の全規則と突き合わせ、判定の仕方が「機械的」の規則の違反が 0 件 | 雛形と完成例 |
| text-writing-rule | サブエージェントがそのファイルの全文を規約 text-writing-rule の全規則と突き合わせ、判定の仕方が「機械的」の規則の違反が 0 件 | なし |
| ピンクの象の除去 | rewrite-pink-elephants がそのファイルを読み、書き直しの案を出した | なし |

### hook の表

| 列 | ○ にする条件 |
|---|---|
| テストの合格 | README の「確かめ方」の `node --test` のコマンドで、すべてのテストが合格 |

## 警告の記録

この章は、丸を付けたときに残っていた警告を、スキルと列ごとに持ちます。

| スキル | 列 | 警告の出どころ | 警告のケースの番号 | 警告の中身 |
|---|---|---|---|---|
| fixing-test-plan | シナリオテスト | `tests/fixing-test-plan/2026-10-25-1936/判定の記録.md` | 19 | 3 回目(2026-10-25-1640)と 4 回目で、「直せない項目: 判定の仕方」を一覧に出すかが変わった実行者の揺れ。作った人は、3 回目で合格した状態と見なした |
| fixing-skill | skill-writing-rule | checking-skill-with-template の 2 回目の指摘の一覧 | なし | 判定の仕方が「AI の推論」の規則の指摘が回ごとに入れ替わる。2 回目の 3 件は直した |
| designing-skill-test-cases | skill-writing-rule | checking-skill-with-template の 2 回目の指摘の一覧 | なし | 2 回目の指摘 1 件(phase 3 の中止の step の並び)は直した |

## 丸を消す条件

作った人は、丸の hash より後にその行のファイル(スキルの行は `skills/<スキルの名前>/`、規約の行は規約のファイル、hook の行は `hooks/`)を変えたコミットがあるかを列ごとに確かめ、あればその丸を空にし、「最後に変えたコミット」を今の値に書き換えます。
