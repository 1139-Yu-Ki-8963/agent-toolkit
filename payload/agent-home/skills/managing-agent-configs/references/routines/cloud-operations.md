# クラウド Routine 操作リファレンス（cloud-operations）

Claude Code クラウド Routines（https://claude.ai/code/routines/）の登録・確認・変更・管理の操作手順。create / review / 単独確認のいずれからも参照される。

## 新規登録（/schedule コマンド）

Claude Code ターミナルで以下を入力する:

```
/schedule <自然言語での時刻指定>
```

Claude が対話的にプロンプト・リポジトリ等を聞いてくる。以下を回答する:

| 質問 | 回答 |
|---|---|
| プロンプト | `routines/_shared/cloud-prompt-template.md` のテンプレートに従い `<name>` と `<project>` を埋める |
| リポジトリ | **agent-home** と **プロジェクトリポジトリ** の **2 つ** を指定 |

プロンプトテンプレート:
```
routines/<name>/実行プロンプト.md を Read し、記載されている全 Phase を順番に実行してください。project は <project> です。
```

## Web UI 設定確認チェックリスト（7 項目）

https://claude.ai/code/routines/ を開き、該当ルーティンのカードをクリックして詳細画面で確認する。

| # | 項目 | 確認内容 | NG の場合 |
|---|---|---|---|
| 1 | プロンプト欄 | テンプレートの 1 行のみか。インライン手順が含まれていないか | 削除してテンプレートに置き換える |
| 2 | リポジトリ | agent-home + プロジェクトリポジトリの 2 つが指定されているか | 「Edit」で追加する |
| 3 | スケジュール | 設計書（profile.md の有効なルーティン表）の cron 式と一致するか | 修正する |
| 4 | 環境 | Cloud Environment が選択されているか | 変更する。ネットワークアクセスが必要なら Trusted 以上 |
| 5 | コネクタ | profile.md のコネクタ要件に記載されたコネクタが接続済みか | https://claude.ai/customize/connectors で追加 |
| 6 | パーミッション | PR 作成ルーティンの場合、「Allow unrestricted branch pushes」が有効か | 対象リポジトリで有効化する |
| 7 | モデル | 適切なモデルが選択されているか | 変更する |

## 既存ルーティンの確認手順

1. https://claude.ai/code/routines/ を開く
2. 一覧から該当ルーティンを探す
3. カードをクリックして設定を表示
4. 上記 7 項目チェックリストを順に確認する
5. 直近の実行結果: カード内の「Recent runs」から実行ログを開く
6. 実行セッションの詳細: セッション URL（`https://claude.ai/code/session_<ID>`）で確認

## 設定変更手順

### Web UI で変更する場合

1. https://claude.ai/code/routines/ を開く
2. 該当ルーティンのカードをクリック
3. 「Edit」ボタンで編集画面を開く
4. 変更を保存

### /schedule コマンドで変更する場合

```
/schedule update
```

Claude が登録済みルーティンを一覧表示する。変更対象を選択して設定を変更する。カスタム cron 式の指定もここで行う。

## /schedule 管理コマンド一覧

| コマンド | 用途 |
|---|---|
| `/schedule list` | 登録済みルーティンの一覧表示 |
| `/schedule update` | 既存ルーティンの設定変更 |
| `/schedule run` | 即時実行（テスト用。日次上限にカウントされない） |

## ローカル CronCreate の場合

```
CronCreate({
  cron: "<cron 式>",
  prompt: "routines/<name>/実行プロンプト.md を Read し、記載されている全 Phase を順番に実行してください。project は <project> です。",
  recurring: true
})
```

管理コマンド:
- `CronList` — 現セッションのジョブ一覧
- `CronDelete` — ジョブ ID で削除

## Gotchas

- `/schedule` は Claude Code 組込コマンド。Bash からは実行不可。ユーザーに操作を案内する
- `/schedule` は `claude.ai` サブスクリプションログインが必要。`ANTHROPIC_API_KEY` が環境変数にあると非表示になる
- `実行プロンプト.md` を git commit + push しないと、クラウドの fresh clone に含まれず動作しない
- `/schedule run` で即時実行した場合、日次上限にカウントされない（テスト用途）
- Web UI と `/schedule` の両方から同じルーティンを変更できる。どちらで変更しても同期される
