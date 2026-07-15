# 設計判断

`SKILL.md` 本体の「設計判断」から分離した、補助スクリプトの必要性・代替案・保守責任の詳細。

## update-flow-status

**必要性**: statusline.py が Phase/Step 進捗バーを表示するために `flow-status.json` を読むが、このファイルを書き込む処理がどこにもなかった。15 本の Phase ファイルの各 Step で同一の JSON 書き込みロジック（marker_path 解決 + JSON 生成）を Bash 直叩きすると 55 箇所にロジックが重複しトークン浪費かつ保守不能になる。スクリプトに集約することで各 Step は 1 行の呼び出しで済む。

**代替案を採用しなかった理由**:
- Bash ツール直叩き: marker_path ヘルパーの source・session_id 取得・JSON heredoc 生成を 55 箇所に重複展開するのは保守不能
- Phase ファイルへのインライン展開: marker_path の source 行を含む 5〜6 行のブロックが全 Step に入るとファイルの可読性が著しく低下する

**保守責任者**: 人手（ユーザー）。statusline.py の JSON スキーマ変更時に更新する。

**廃棄条件**: ステータスライン機能が廃止された時、または Claude Code 本体が Phase/Step 進捗を自動記録するようになった時。

## validate-design-md

**必要性**: DESIGN.md の構造検証（必須フィールド存在・primary 色定義・Token Reference 解決可能性・セクション順序）をプリフライトチェック・scaffold 後の自動検証・スキル生成後の確認の 3 箇所から呼ぶ必要がある。Google design.md CLI の `lint` は npm fetch + JSON 出力パースが必要で重い。YAML フロントマターの構造検証に特化した軽量スクリプトを用意することで、ネットワーク不要かつ即座に実行できる。3 箇所で同一検証ロジックを Bash 直叩きすると保守不能になる。

**代替案を採用しなかった理由**:
- Bash ツール直叩き: 3 箇所（preflight / scaffold / page-design）で同一の 110 行ロジックを毎回展開するとトークン浪費かつ検証ロジックの不整合リスクがある
- `npx @google/design.md lint` のみ: ネットワーク依存・exit code 0 固定の罠・JSON パースが必要で、構造チェックとしては過剰

**保守責任者**: 人手（ユーザー）。DESIGN.md フォーマットの必須フィールド変更時に更新する。

**廃棄条件**: Google design.md CLI がオフライン実行・構造検証特化モードを提供した時、または DESIGN.md フォーマット自体を廃止した時。
