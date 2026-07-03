# Phase 詳細（P3〜P6 の詳細手順・5 計測の算出式）

`SKILL.md` の P3・P4・P5・P6 で参照する詳細手順。SKILL.md 本体には要約のみを置き、具体的な算出方法・prompt 骨格・書式はここに集約する。

章の役割キー → 節キーワード対応表は本ファイルでは複製しない。正本は `~/agent-home/skills/rebuilding-code-from-docs/references/phase-details.md` の同名表であり、本スキルもそちらを参照する。

## スクリプト入力契約

### `scripts/measure-file-diff.sh <generated-file> <original-file>`

- **標準出力**（key=value を 1 行ずつ・機械可読）:
  ```
  import_diff_lines=<整数>
  style_diff_lines=<整数>
  total_diff_lines=<整数>
  substantive_diff_lines=<整数>
  verdict=PASS|FAIL
  ```
- **verdict の判定式**: `import_diff_lines == 0 && style_diff_lines == 0 && substantive_diff_lines <= 20` のとき `PASS`、それ以外 `FAIL`
- **対象外**: 「単体テスト仕様の検査」（禁止パターン・import・コンポーネント/API 利用）は本スクリプトの対象外。P5 でメインが別途実施する
- **引数不足・ファイル不在**: stderr にメッセージを出して `exit 1`。正常時は `exit 0`

### 4 計測の算出方法（heuristic）

| 計測 | 算出方法 |
|---|---|
| import diff | 両ファイルから `^\s*import ` 行を抽出→ソート→`diff` の差分行数（`^[<>]` 行の数） |
| style diff | `className` / `style=` 属性・`const .*Style` 系変数・16 進カラーコード（`#[0-9a-fA-F]{3,8}`）・`px`/`rem`/`em`/`vh`/`vw` を含む数値行を抽出→ソート→diff の差分行数 |
| 全体 diff | `diff <original> <generated>` の差分行数（参考値。合格判定には使わない） |
| 実質 diff | コメント行（`^\s*//`・`^\s*/\*`・`^\s*\*`）と空行を除外した上での diff 差分行数 |

### 非 JSX ファイル（hook / util 等）での縮退

対象ファイルが JSX を持たないロジックフック・ユーティリティ（`.ts` 等）の場合、style diff と P6 の差分 4 分類のうち JSX 分類は構造的に 0 に縮退しやすい。この場合は logic 分類（データフロー §6・API通信 §7）を主軸に解釈する。`style_diff_lines=0` は縮退による 0 であり、それだけで合格を意味するのではなく、実質 diff のうち logic に起因する差分を重視して判定する。

## P3: 単体テスト仕様作成の詳細

1. 単体テスト観点表の全行から、対象ファイル（対象の関数・フック・コンポーネント名）に対応する行を抽出する
2. 抽出した観点ごとに RED のテストケースを書く（1 行 = 1 つ以上のテスト）
3. 対象ファイルに対応する観点が 1 件も無い場合、意味キー規約（連番禁止・内容要約キー）に沿って観点表へ最低限の行を追記してから RED を書く
4. 本フェーズでは元コード（原本参照コミットの内容）を一切参照しない。観点表・設計書の該当章のみを根拠にする

## P4: サブエージェント委任の prompt 骨格

`worker-sonnet` へ 1 エージェント = 1 ファイルで委任する。prompt には次の要素のみを含める。

```
## 対象
<対象ファイルパス>（新規作成 or 白紙化済みファイルの再作成）

## 対象設計書の該当章（抜粋）
<画面構造 / データフロー / API通信 / イベント処理 / 領域別仕様 / 定数設定値 / エラーハンドリング
 等、対象ファイルに関係する章のみを抜粋。設計書全文は渡さない>

## 共通部品（該当する場合のみ）
<DESIGN.md の関連スタイル定義 / 共通設計書の関連コンポーネント仕様 / メッセージ定義書の関連文言>

## 単体テスト観点表（該当行）+ P3 で書いたテスト
<該当行の抜粋 + P3 で書いたテストコード全文>

## 禁止事項（厳守）
- 元コード（オリジナル環境・原本参照コミット）は一切 Read しない。パス・内容ともに提示されていない
- 上記の設計書抜粋・共通部品・テストのみを根拠に実装する
- import/export/Props 名は設計書の記載と完全一致させる（省略形・別名禁止）
```

**期待返却値**: 実装ファイル 1 件の内容・変更内容の要約・P3 テストのローカル実行可否

**新規サブエージェント起動の徹底**: ループの各周（P6→P2 再投入後の P4 再実行時）で、必ず新規に `worker-sonnet` を起動する。前周の会話・生成物の文脈を prompt に含めない（同一エージェントへの追加指示は禁止）。

## P5: 差分比較の詳細手順

1. `git show <原本参照コミット>:<対象ファイルパス> > $CLAUDE_JOB_DIR/tmp/<basename>.original`（`$CLAUDE_JOB_DIR` 未設定時は `${TMPDIR:-/tmp}/claude-job-<session>/` にフォールバック）で原本を一時ファイルへ抽出する
2. P3 のテストを P4 の生成物に対して実行する（禁止パターン検査・import 検査・コンポーネント/API 利用検査を含む）。全項目合格が必須
3. `scripts/measure-file-diff.sh <generated-file> <original-tmp-file>` を実行し、5 計測を省略なく取得する
4. verdict=FAIL の場合、差分の内容（import/style/substantive のどの行が差分か）を P6 の分類の根拠として記録する

## P6: 差分分類 → 設計書修正先マップ

| 差分種別 | 判定条件 | 修正先 |
|---|---|---|
| import | `import_diff_lines > 0` | 実装契約章の依存（既定 §15.3） |
| style | `style_diff_lines > 0` | `DESIGN.md`（画面構造章のスタイル適用パターン経由、既定 §3.6） |
| logic | `substantive_diff_lines` の内容がデータフロー・API 呼び出し条件に起因 | データフロー（既定 §6）・API通信（既定 §7） |
| JSX | `substantive_diff_lines` の内容が JSX 構造・領域仕様に起因 | 画面構造（既定 §3）・領域別仕様（既定 §9） |

logic と JSX の切り分けは目視判断による。1 件の実質 diff が複数分類にまたがる場合、両方の修正先に記載する。

### 修正順序

1. 単体テスト観点表に不足していた観点（境界値・異常系等）を追記する
2. 設計書の該当章に記載を追加する
3. verdict=FAIL が続く場合は P2（白紙化）へ再投入する（原本参照コミットは再取得不要）

## 修正指示書・検証記録の書式

配置先は `<画面ディレクトリ>/検証記録/単体-<対象ファイル basename>/<timestamp>/修正指示書.md`。書式は `~/agent-home/skills/rebuilding-code-from-docs/references/report-format.md` の修正指示書テンプレを踏襲し、以下の点を stage1 向けに読み替える。

- 「根拠となる証跡パス」には Phase 7（stage2 の答え合わせ）返却ブロックの代わりに、P5 の 5 計測出力全文（key=value）を参照パスとして記載する
- 判定は `syncing-reverse-env` の静的 3 分類 / 動的 L1〜L4 ではなく、単体テスト仕様の検査結果 + 5 計測の verdict で行う
- NG が 0 件（収束）の場合は「NG なし」と明記し、表は省略する
