# リバース検証ループ

この仕組みは、リバース設計スキル群が壊れていないかを確かめる。対象はスキルと同梱のスクリプトであり、生成された成果物の業務的な正しさではない。空の状態から設計書とポータル一式を作り直し、その結果を毎回記録する。

## 何を確かめるか

| 観点 | 何が分かるか |
|---|---|
| 網羅 | 作るはずの成果物が、すべて実際に作られたか |
| 自立 | このリポジトリの中身だけで作り切れるか |
| 再現 | 同じ入力で 2 回作って、同じ結果になるか |
| 健全 | 出来上がった生成物に、壊れたリンクや空のページが無いか |

## どう回すか

1 回で回すなら、次を実行する。

```
bash generation-engine/scripts/verification/run-verification-loop.sh
```

版の取得から前回との比較までを、続けて実行する。使い捨ての出力先は最後に破棄する。

個別に段を回す場合は、次の手順を使う。

1. 第 1 層を実行する。自己テストと定義の整合を毎回確かめる（`generation-engine/scripts/verification/run-layer-machine-checks.sh`）
2. 疑似入力を用意する。既存の成果物は入力に使わない（`generation-engine/scripts/verification/prepare-verification-input.sh`）
3. 第 3 層を実行する。空の出力先から順に生成する（`generation-engine/scripts/verification/run-layer-full-pipeline.sh`）
4. 4 つの観点で判定する。道具は `generation-engine/scripts/verification/` 配下にある
   - 網羅の道具は `check-coverage.sh`、自立の道具は `check-self-contained.sh`
   - 再現の道具は `check-reproducible.sh`、健全の道具は `check-sound.sh`
5. 判定の結果を記録する（`docs/design/reverse-verification/実行記録.md`）
6. 実行できなかった項目があれば、退避の記録へ残す（`docs/design/reverse-verification/退避記録.md`）
7. 前回の記録と見比べ、直ったものと新たに壊れたものを洗い出す

## 退避の記録の書き方

「実行が要るから」だけでは、退避を記録できない。

`record-deferral.sh` は、試したコマンドと失敗の内容と再実行の条件を必須にする。どれか 1 つでも欠けると、終了コード 1 で拒否する。

```
bash generation-engine/scripts/verification/record-deferral.sh \
  --ledger docs/design/reverse-verification/退避記録.md \
  --item <退避した項目> \
  --version <対象のコミットハッシュ> \
  --tried <実行したコマンド> \
  --failed <失敗の内容> \
  --condition <再実行の条件>
```

版は 40 文字の 16 進でなければならない。

## 置き場

| 中身 | 場所 |
|---|---|
| この案内 | `docs/design/reverse-verification/README.md` |
| 設計 | `docs/design/reverse-verification/設計.md` |
| 実行の記録 | `docs/design/reverse-verification/実行記録.md` |
| 退避の記録 | `docs/design/reverse-verification/退避記録.md` |
| 実行の道具 | `generation-engine/scripts/verification/` |
| 運用の規約 | `.claude/rules/always/verification/reverse-verification/rule.md` |

## 関連

- [設計.md](./設計.md) — 検証の設計そのもの
- [実行記録.md](./実行記録.md) — 判定の結果の台帳
- [退避記録.md](./退避記録.md) — 退避の記録の台帳
