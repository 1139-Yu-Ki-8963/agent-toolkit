---
paths:
  - "**/.investigation-checklist.md"
  - "**/investigation-checklist.md"
---

# 調査報告共通観点（REPORT-COMMON-STANDARDS）

調査報告（investigator 等の調査系エージェントが返す報告文）の合格基準。調査チェックリストの作成時・調査の実行時に守るべき規約であると同時に、レビュー時の照合観点表そのものである。レビューでは report-reviewer が本ファイルを Read して照合する（フォルダ `review-checklist/report/` 配下 = report-reviewer 担当）。

他ドメイン（code / document）と異なり、照合対象の報告文はディスク上のファイルではなく委任プロンプト・会話内のテキストであることが多い。そのため paths はチェックリストファイル（`.investigation-checklist.md`）に合わせてあり、チェックリスト作成時点で本観点が注入される。report-reviewer への委任は resolve スクリプトを経由しない直接委任が主経路のため、report-reviewer は担当フォルダ配下の本ファイルを自ら Read する。

## チェックリスト完了性

- チェックリストの全項目が実行されている
- 未実行の項目が「未確認」と明記されている
- スキップされた項目に理由が添えられている

## 証拠の存在

- 各 finding にコマンド出力または公式ドキュメント引用が添付されている
- 「N 件」「N 個」等の数量主張に裏取りコマンドの出力がある
- 「〜の仕様上必須」等の外部仕様主張に公式ソース（URL・引用）がある

## 事実と推測の分離

- 推測が事実として断言されていない
- 「可能性がある」「と考えられる」が省略されて断定になっていない
- 言及されたファイルパスの実在が確認されている

## 再現可能性

- 報告内のコマンドを再実行して同じ結果が得られる（重要 finding はサンプリングで実照合する）
- ユーザーの判断に影響する finding は、別コマンドでも裏取りできる

## 合否基準

- **PASS**: 全 finding が証拠付きで事実確認済みであり、未確認項目が「未確認」として分離されている
- **FAIL**: 証拠なしの断言・チェックリスト項目の未実行（未確認の明記なし）・裏取り NG のいずれかが 1 件でもある

## 作成側の規律

本観点は検証だけでなく作成の規約でもある。調査系エージェント（investigator 等）は報告を書く時点で上記 4 観点を満たす（各 finding に証拠添付・数量は裏取り出力添付・推測は「未確認」と明記・実行していないコマンドを実行済みと書かない）。investigator の定義にある「調査の規律」は本観点の作成側表現であり、定義元は本ファイルである。

## 機械強制

現時点では hook による機械強制なし。report-reviewer の照合（`~/.claude/rules/always/agent/subagent-selection/rule.md` の調査チェックリストパイプライン Step 3）が防衛線となる。

## 違反検知時の手順

report-reviewer が FAIL を返した場合:

1. 委任元が FAIL 詳細（不足項目・誤り項目）を調査エージェントへ指示して再調査させる
2. 再調査後に report-reviewer へ再委任する。最大 2 回まで
3. 2 回 FAIL した場合は、検証済みの事実と未確認項目を分離した形でユーザーに報告して中断する

## 設計判断

設計判断・経緯の記録は同ディレクトリの `design-notes.txt` を参照（非注入サイドカー）。

## プロジェクト上書き

- 上書き可否: 委譲可（値のみ・追加のみ）
- 受け口: `<repo>/.claude/rules/scoped/review-checklist/report/common/rule.md`
- 優先順位: 受け口が存在すれば、レビュー時に本ファイルと受け口の基準を合成して照合する。プロジェクト固有の調査観点（対象システム固有の裏取り手順等）は受け口に置く。グローバル基準の無効化・緩和は不可

## 関連

- `~/.claude/agents/report-reviewer/report-reviewer.md` — 本観点を照合する判定系専門家
- `~/.claude/agents/investigator/investigator.md` — 作成側（調査の規律は本観点の作成側表現）
- `~/.claude/rules/scoped/agent-config/review-checklist/rule.md` — レビュー観点フォルダの統治規約
- `~/agent-home/skills/subagent-investigation-checklist/SKILL.md` — チェックリスト作成手順（paths の注入対象ファイルを生成する側）
