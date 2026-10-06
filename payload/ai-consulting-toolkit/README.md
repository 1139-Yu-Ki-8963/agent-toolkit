# AI推進コンサルタント道具箱

このリポジトリは、AI推進コンサルタントが顧客企業の現場業務をヒアリングし、AI化の提案・導入・運用管理までを一貫して進めるための道具箱である。対象読者はコンサルタント本人であり、案件ごとの進め方・判定基準・テンプレート・外部ツールの使い分けをここに集約する。

## 業務フローとドキュメント対応

| フェーズ | 目的 | 対応ドキュメント |
|---|---|---|
| 1. 課題の受付・事例照合 | 課題を受け付け、既知なら事例と導入スキルで即対応する | consult-intake スキル（.claude/skills/consult-intake/） + consult-level-draft スキル（レベル軌道下書きの生成） |
| 2. 現場ヒアリング | 誰が何に困っているかを特定する | consult-hearing スキル（.claude/skills/consult-hearing/） |
| 3. 業務の棚卸し | 作業を計測可能な単位に分解する | [docs/03_業務棚卸しテンプレート/業務棚卸しテンプレート.md](docs/03_業務棚卸しテンプレート/業務棚卸しテンプレート.md) |
| 4. AI化レベル判定 | タスクごとにどこまでAIに任せるかを判定する | [docs/02_AI化レベル基準/AI化レベル基準.md](docs/02_AI化レベル基準/AI化レベル基準.md) |
| 5. 施策設計・WBS化 | 判定レベル別の定番タスクをWBSに展開する（レベル合意後） | [docs/04_レベル別タスクテンプレート/レベル別タスクテンプレート.md](docs/04_レベル別タスクテンプレート/レベル別タスクテンプレート.md) + consult-wbs スキル + [docs/08_着手前提チェックリスト/着手前提チェックリスト.md](docs/08_着手前提チェックリスト/着手前提チェックリスト.md) + consult-level-agree スキル |
| 6. 実行・稼働管理 | 進捗と課題を管理する | [docs/07_道具マッピング/道具マッピング.md](docs/07_道具マッピング/道具マッピング.md) |
| 7. 効果測定・定着化 | 削減時間・品質を検証し定着させる | [docs/05_効果測定テンプレート/効果測定テンプレート.md](docs/05_効果測定テンプレート/効果測定テンプレート.md) + consult-measure スキル（効果測定と昇格判定） |

フェーズの詳細な定義（入力・出力・完了条件）は [docs/01_コンサル業務フロー/コンサル業務フロー.md](docs/01_コンサル業務フロー/コンサル業務フロー.md) を参照する。

## ドキュメント一覧

| ファイル | 内容 |
|---|---|
| [docs/01_コンサル業務フロー/コンサル業務フロー.md](docs/01_コンサル業務フロー/コンサル業務フロー.md) | 7フェーズの業務フロー定義。道具箱全体の入口 |
| [docs/02_AI化レベル基準/AI化レベル基準.md](docs/02_AI化レベル基準/AI化レベル基準.md) | レベル1〜5の定義と4判定軸。顧客説明用HTML（同フォルダ内 AI化レベル基準.html）あり |
| [docs/03_業務棚卸しテンプレート/業務棚卸しテンプレート.md](docs/03_業務棚卸しテンプレート/業務棚卸しテンプレート.md) | タスク一覧の記入表 |
| [docs/04_レベル別タスクテンプレート/レベル別タスクテンプレート.md](docs/04_レベル別タスクテンプレート/レベル別タスクテンプレート.md) | 判定レベル別のWBS展開用タスク集 |
| [docs/05_効果測定テンプレート/効果測定テンプレート.md](docs/05_効果測定テンプレート/効果測定テンプレート.md) | before/after測定表 |
| [docs/06_データ取り扱いチェック/データ取り扱いチェック.md](docs/06_データ取り扱いチェック/データ取り扱いチェック.md) | 顧客データをAIに渡す前の判定 |
| [docs/07_道具マッピング/道具マッピング.md](docs/07_道具マッピング/道具マッピング.md) | 外部WBSツール資産の使い分け |
| [docs/08_着手前提チェックリスト/着手前提チェックリスト.md](docs/08_着手前提チェックリスト/着手前提チェックリスト.md) | AI化タスク着手の前提5分類（アクセス権限・データの実物・現状手順・実行環境・体制と時間） |
| [docs/09_解決事例集/解決事例集.md](docs/09_解決事例集/解決事例集.md) | 汎用課題と解決事例の蓄積簿。事例は1課題=1フォルダで docs/09_解決事例集/ 配下に置く |
| [docs/10_解説スライド集/解説スライド集.md](docs/10_解説スライド集/解説スライド集.md) | 横1枚（16:9）の解説HTMLの蓄積簿。スライドは consult-slide スキルで生成し、1スライド=1フォルダで docs/10_解説スライド集/ 配下に置く |
| [docs/14_案件フォルダ設計/案件フォルダ設計.md](docs/14_案件フォルダ設計/案件フォルダ設計.md) | 案件フォルダの共通の構成と運用の決まり。新しい案件は templates/案件雛形/ を clients/<案件名>/ へ複製して始める |

## スキル

| スキル | 役割 | 起動のしかた |
|---|---|---|
| [.claude/skills/consult-hearing/](.claude/skills/consult-hearing/SKILL.md) | 現場ヒアリング。課題深掘り・4判定軸評価・AI化レベル判定を選択式対話で行い、判定レベル付き業務棚卸し表を出力する | このリポジトリで開いたセッションで「ヒアリングを開始」と依頼する |
| [.claude/skills/consult-wbs/](.claude/skills/consult-wbs/SKILL.md) | 棚卸し表からWBSを展開。顧客共有用Excelと内部管理用wbs.jsonを出力する | 棚卸し表がある状態で「WBSを作成」と依頼する |
| [.claude/skills/consult-case/](.claude/skills/consult-case/SKILL.md) | 解決事例の登録。検証済みの課題と解決策を説明HTMLと実物資材のセットで事例集に登録する | 「事例登録」「事例にして」と依頼する |
| [.claude/skills/consult-lint-setup/](.claude/skills/consult-lint-setup/SKILL.md) | 顧客プロジェクトへ文章品質の機械強制一式（textlint・置き換え辞書・文体規約・コミット検査hook）を導入する | 「文章品質を導入」「textlint導入」と依頼する |
| [.claude/skills/consult-repo-rules/](.claude/skills/consult-repo-rules/SKILL.md) | 顧客リポジトリの規約整備。暗黙の様式を規約として明文化し、レビュー・テストの仕組みを設置する | 「規約を整備」「コーディング規約を作って」と依頼する |
| [.claude/skills/consult-intake/](.claude/skills/consult-intake/SKILL.md) | 課題の受付と振り分け。自由文の課題を事例集と照合し、既知は事例+導入スキルで処方、未知はヒアリングへ | 案件の最初に「課題を受け付けて」と依頼する |
| [.claude/skills/consult-request-list/](.claude/skills/consult-request-list/SKILL.md) | 課題一覧から現場への確認依頼リストを生成。実物・事実・状況説明のみを依頼し、決定タスク・人的協力依頼は含めない | ヒアリング行き課題が出たら「確認リストを作って」と依頼する |
| [.claude/skills/consult-level-agree/](.claude/skills/consult-level-agree/SKILL.md) | 課題別にL1〜L5のレベル軌道を可視化し、顧客と現在地・今回の目標を合意するHTMLを生成する | レベル判定後に「レベルを合意」と依頼する |
| [.claude/skills/consult-level-draft/](.claude/skills/consult-level-draft/SKILL.md) | 受付直後の全課題にL1〜L5軌道の下書きを生成する（上限は保留） | 課題受付の直後に「レベル軌道を下書き」と依頼する |
| [.claude/skills/consult-analyze/](.claude/skills/consult-analyze/SKILL.md) | 顧客リポジトリの解析レポートHTMLを生成。技術構成・規約状況・テスト分布を可視化する | 「リポジトリを解析」と依頼する |
| [.claude/skills/consult-diagnose/](.claude/skills/consult-diagnose/SKILL.md) | Claude Code設定を診断。規約・スキル・hookの整備状況をHTMLレポートで報告する | 「設定を診断」と依頼する |
| [.claude/skills/consult-measure/](.claude/skills/consult-measure/SKILL.md) | 効果測定と昇格判定。実測と昇格条件を突合し棚卸し表の現在レベルを更新する | 実測値がそろったら「効果測定と昇格判定をして」と依頼する |
| [.claude/skills/consult-slide/](.claude/skills/consult-slide/SKILL.md) | 与えたトピックを図解入り横1枚（16:9）の解説HTMLにする | 「解説スライドを作って」と依頼する |

## 外部資産

| 場所 | 役割 | 使いどころ |
|---|---|---|
| 外部リポジトリ wbs-skills（環境ごとに clone） | Excel向けWBSスキル3種（wbs-hearing=選択式ヒアリング / wbs-generator=Excel WBS生成 / wbs-edit=共同編集WBSの編集・本番反映） | consult-wbs の Excel 生成エンジン（wbs-generator）・顧客共有WBSの共同編集（wbs-edit） |
| 外部リポジトリ single-file-wbs（環境ごとに clone） | 単一HTMLのWBSビューア。データはwbs.json 1枚で、AIがJSONを直接編集して保守する設計 | consult-wbs が出力する wbs.json の閲覧ビューア |

## 案件での使い方

案件を開始したら、`templates/案件雛形/` をリポジトリ直下の `clients/<案件名>/`（git管理外）へ複製する。フォルダの構成と運用の決まりは [docs/14_案件フォルダ設計/案件フォルダ設計.md](docs/14_案件フォルダ設計/案件フォルダ設計.md) を参照する。
docs/ のテンプレート（03_業務棚卸しテンプレート/業務棚卸しテンプレート.md・05_効果測定テンプレート/効果測定テンプレート.md・06_データ取り扱いチェック/データ取り扱いチェック.md）を `clients/<案件名>/` にコピーし、案件固有の内容を記入する。
テンプレート本体（docs/ 配下）は案件情報で汚さず、常に空欄の雛形として保つ。

## 注意

顧客データ・案件情報はこのリポジトリにコミットしない。`clients/` は `.gitignore` 済みであり、コピー先として使う。
