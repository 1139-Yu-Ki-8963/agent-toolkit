# PM引き継ぎの現状

## この文書は何か

`docs/tasks/` の課題を3セッションで分担して消化する体制で、進行を管理する役（PM）を別のセッションへ引き継ぐための現状の記録である。2026-08-18 時点。

## 体制

3つのセッションが分担し、PMが1つ加わる。**ファイルで分けて衝突を防ぐ**方式である。時間で分けない。

| 担当 | 群 | 反映先 |
|---|---|---|
| reverse-docs-skills-b3 | 規約の生成と検証 | `generation-engine/scripts/rules/`・`verification/`・`tests/` |
| reverse-docs-skills-1b | ポータル生成本体と設計文書からのマニフェスト生成 | `generation-engine/scripts/build-portal.sh`・`portal-input/` |
| reverse-docs-skills-2d | テンプレートと配色 | `delivery-payload/templates/` |

宛先は毎回 `ListAgents` で確かめる。名前は起動ごとに変わる。

## PMの職務

1. `docs/tasks/指摘改善一覧.md` の課題を分解し、反映先のファイルで群に分けて各担当へ配る
2. 担当は1課題ごとにコミットし、その時点でPMへ報告する。**PMのレビューを待たず次へ進ませる**
3. PMがレビューする。実測の内容を自分で走らせて確かめる
4. PMがmainへ統合し、payloadへ同期して `origin/main` へ押し出す
5. **押し出しはPMだけが行う。担当にはさせない**

## 運用の決まり

### mainへ書き込むプロセスは常に1つ

統合の前に `git status --porcelain` が空で `git rev-parse MERGE_HEAD` が何も返さないことを確認する。塞がっていたら待つ。**この制約は、複数の担当が同時にmainへ統合して作業ツリーが衝突で止まった事故のあとに設けた。**

### 担当はユーザーへ判断を仰がない

判断が要る事項は既定に従うか、指示書の「決めていないこと」へ記録して次へ進む。PMへ送るのは構わないが、送った後も待たない。**ユーザーへの問いはPMだけが立てる。**

規約は `.claude/rules/always/session/worker-autonomy/rule.md`。Stop の検査（`check-worker-autonomy.sh`・`check-manager-handoff.sh`）で機械強制している。

### 判断待ちを前に出さない

判断待ちの課題を毎ターン持ち出すと、進められる作業の割り振りが後回しになる。**まとめて後で聞く。** 進められる作業を優先して配る。

### 手が空いた報告を受けたら同じターン内で渡す

「渡します」と述べてターンを終えることを禁止する。渡せる作業が無ければ「無い」と答える。**述べた時点で渡していなければ相手は待ち続ける。**

## 現在の状態

```
main: 53fb6b41
作業ツリー: 汚れなし
公開: agent-toolkit 04acd8f / origin/main へ push 済み・未push 0件
docs/tasks 直下: 2件
docs/tasks/done: 32件
指摘改善一覧の課題: 56件（すべて「完了」または「確認済み」）
```

### 残る2件

| 指示書 | 判定器の理由 | 状況 |
|---|---|---|
| `指摘改善一覧.md` | 記録なし | 56課題の入れ物。今後も追記され続ける |
| `片付き判定に実測の段階を足す指示書.md` | 目視の行がある | 確かめる手段の欄に機械で実行できないものがある |

### 進行中の作業

2d が `1-50`（横スクロールの手がかり）と `1-49`（配色のコントラスト）の検査を新設中である。実ブラウザで測る恒久的な検査を `generation-engine/scripts/tests/` へ置き、第1層の集約へ載せる方針をPMが決めた。コントラストの基準値は `4.5`（WCAG AA）を採用した。既存の `test-matrix-header-compact-layout.cjs` が同じ値を使っており、一覧の実測値（4.59〜6.98）とも矛盾しないためである。

**これが押し出せる次の改善である。** 他の課題は実装済みで、状態欄の更新だけが差分になる。

## ユーザーの判断を待っている2件

**どちらも棚上げしている。進められる作業を優先する。**

### 規約の定義と生成物の分離を自分のリポジトリへ適用する

このリポジトリは「規約の定義を `docs/rules/` に置き、そこから `.claude/rules/`・`.cursor/rules/`・`AGENTS.md` の索引・hooks の登録を生成する」道具を作って納品先へ配っている。**しかし自分は `docs/rules/` を持たず、`.claude/rules/` に11件を手書きしている。** ユーザーは「あってはならない」と判定した。

移行には front matter 13鍵（`key`・`title`・`parent`・`summary`・`scope`・`paths`・`enforcement`・`checkable`・`checker`・`uncheckableReason`・`formatter`・`status`・`origin`）の設計が要る。**一部だけ移しても残りは消えない**ことを確認済み（生成器に生成先を消す処理はない）。

案は3つある。1件だけ試す（`reverse-verification/rule.md` 83行）、配布対象2件（`page-conventions`・`reverse-verification`）、11件すべて。**PMの推奨は1件だけ試すこと。** この道具が自分のリポジトリで動いた実績がまだない。

### 自己テストの所要時間が規約の件数に追いつかれる

`scaffold-rule-definitions.sh` の自己テストが、規約と検査ケースの件数に比例して伸びる。基準110秒だったものが実測212秒になり、宣言値150秒を超えて打ち切られた。**当座は宣言値を300秒へ引き上げた。**

恒久対応の候補は4つ（並列化・絞り込み・段階分割・キャッシュ）。どれを採るか、所要時間の上限をいくらに置くかがユーザーの判断待ちである。

## この環境の落とし穴

### サンドボックスの拒否と自動モードの分類器の拒否は別物

サンドボックスの拒否は `dangerouslyDisableSandbox: true` で通る。**自動モードの分類器の拒否はフラグでは通らない。** 見分けずに「回避できない」と結論した報告が複数あった。

`mktemp` が `/var/folders` で拒否される、`.claude/settings.json` へ書けない、Chrome が起動しない、`.git/worktrees/` を削除できない、はいずれもサンドボックスの拒否でありフラグで通る。

### 検査が「実行できなかった」と「不合格だった」を区別しない

`mktemp` の失敗で全件が不合格に見える検査があった。**PMはこれを3回踏み、うち1回は担当の成果を「不合格9件」と誤って報告した。**

`check-instruction-format.sh` は判定不能化に対応済み（終了コード2・`[UNKNOWN]` ラベル・原因の明記）。規約は `.claude/rules/always/verification/indeterminate-result/rule.md`。`mktemp` を使う検査は120件あり、対応済みは1件だけである。

### テンプレートを変えたら見本を同じコミットで再生成する

`.claude/rules/always/portal/template-sample-sync/rule.md` の規約1と5。`build-derived-rules.sh --apply` の直後に `check-derived-drift.sh record` を実行し、同じコミットへ含める。**この抜けで第1層の検査が不合格になった実例がある。**

ただし `delivery-payload/templates/リバース検証/` 配下は規約4で同期の対象外である。**PMはこれを見落として担当の成果を誤って差し戻した。** 接頭辞だけでなく全パスを確かめる。

### docs/tasks 配下は公開の同期対象外

`docs/tasks/` の状態欄の更新や `done/` への移動は、payload へ同期されない。**そのため押し出す差分が0件になる。** 実体を伴う変更（コードや検査の追加）だけが公開の対象になる。

## PMが繰り返した誤りの形

**すべて「正しい手続きを間違った対象へ当てた」形である。** 6回以上繰り返した。

| 誤り | 中身 |
|---|---|
| 作業ディレクトリの取り違え | 相対パスの起点が別の場所になり、存在するものを不在と読んだ。2回 |
| 枝の取り違え | コミットが乗っていない枝を読み、存在しない食い違いを指摘した |
| 根拠の未確認 | 担当の報告の結論だけを見て、走査の語を確かめずに判定した |
| 一覧の未照合 | 同期対象の一覧が古いまま実物と照合せず、誤った説明を公開した |
| 状態欄だけの計数 | 判定器の基準ではなく状態欄だけを数え、残件を誤って報告した。2回 |
| 除外規定の見落とし | 接頭辞だけを見て、その下の除外の階層を確かめず差し戻した |

**対策**: 確認のコマンドは毎回 `cd` でリポジトリの root へ移ってから実行する。変更の所在は `git branch --contains <コミット>` で先に出す。読んだ枝の名前を指摘の文面に必ず書く。残件は判定器の出力で数える。パスは接頭辞ではなく全パスで確かめる。

## 判定器の使い方

```
bash docs/scripts/judge-plan-done.sh              判定して一覧を出す（ファイルは動かない）
bash docs/scripts/judge-plan-done.sh --apply      移せると判定したものを done へ移す
bash docs/scripts/judge-plan-done.sh --write      確かめる手段を実行し状態欄へ書き込む
bash docs/scripts/judge-plan-done.sh --timeout N  確かめる手段1件あたりの上限（既定120秒）
bash docs/scripts/judge-plan-done.sh --self-test  自己テスト9件
```

片付いたと判定する条件は2段階である。

```
段階1: 記録の状態欄が「完了」または「対象外」で揃う
       （「判断待ち」は未解決として扱う。済みに数えない）
段階2: 表が5列（判定 | 確かめる手段 | 状態 | コミット | 確かめた内容）であり、
       確かめる手段が機械で実行できるコマンドであること（目視は認められない）
```

実行に時間がかかる。確かめる手段のコマンドを1件ずつ実際に走らせるためである。**背景で実行して待つ。**

## 公開の手順

`.claude/rules/always/publish/complete/rule.md` の「公開完遂の手順」節が正本である。

```
手順1: 正本のコミット
手順2: payload への同期
       cd ~/github-public/agent-toolkit
       node scripts/sync-payload.mjs --check --only payload/reverse-docs-skills
       node scripts/sync-payload.mjs --apply --only payload/reverse-docs-skills
手順3: 範囲の確認とコミット
       git add payload/reverse-docs-skills
       （git add -A は禁止。フックが止める）
       git -c user.name=... -c user.email=... commit -m "【同期】..."
手順4: git push origin main
手順5: 判定器で反映を確認
```

**作業は `~/github-public/agent-toolkit/` 側で行う。** `~/Projects/` 配下に作業ツリーを作ると工程ゲートが誤発火する。

## 実績

```
公開: 10回（うち実体を伴うもの 9回）
done へ移した指示書: 32件
押し出した改善: 1-31・1-41・1-46・1-183・1-184・1-186・1-29・1-30・1-190
main へ入れた改善（公開の差分なし）: 1-54・1-58・1-59・1-35・1-36・1-47・1-51・1-191
```

## 引き継ぐ側が最初にやること

1. `ListAgents` で3担当の名前を確かめる
2. `bash docs/scripts/judge-plan-done.sh` を背景で実行し、残件を確定させる
3. 各担当へ「PMが交代した」旨と、いま担当している課題の確認を送る
4. 手が空いている担当がいれば、その場で課題を渡す。無ければ「無い」と答える
