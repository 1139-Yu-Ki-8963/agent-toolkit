# gold-standard（正解セット）

既存コードから生成した設計書が「合格」かどうかを判定するための正解基準。

## 用途

1. **バックテスト**: facts抽出スキーマが正解設計書の全情報を復元できるか逆算検査する（`backtest-facts-against-gold.sh`）
2. **カバレッジ受入判定**: 生成設計書がgold設計書と同等の網羅度を持つか機械判定する（`check-doc-coverage-against-gold.sh`）
3. **著述見本**: 執筆スキルが記載粒度・表形式の参考にする（値・識別子の転写は禁止）

## ディレクトリ構成

| ディレクトリ | 内容 |
|---|---|
| original/ | 合成原本コード（React+TypeScript+MUI、3ファイル、10構文パターン網羅） |
| docs/ | 完全設計書一式（著述後に配置） |
| rebuild-evidence/ | 盲検再構築の成果物（検証後に配置） |

## 合成原本コードの設計

プロジェクト非依存の語彙のみを使用し、以下の10構文パターンを網羅する:
テーブル表示 / フォーム入力 / API呼出し / エラー処理 / インラインsx+ネストセレクタ / ローカル型定義 / enum引数 / useEffect / import type / 画面遷移

## 完成までの手順

1. original/ の合成コードを確定する（本コミットで完了）
2. extracting-unit-facts-from-code で facts.yml を抽出する
3. generating-reverse-detailed-design で完全設計書を著述する
4. 盲検再構築（原本非参照の新規ワーカーが設計書のみから再構築）を実施し、全計測PASSまで反復する
5. 実証記録を同梱する
