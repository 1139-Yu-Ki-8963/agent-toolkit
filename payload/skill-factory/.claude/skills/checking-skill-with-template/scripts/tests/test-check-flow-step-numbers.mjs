#!/usr/bin/env node
import { mkdtempSync, writeFileSync, rmSync } from "node:fs";
import { spawnSync } from "node:child_process";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";
const S = join(dirname(fileURLToPath(import.meta.url)), "..", "check-flow-step-numbers.mjs");
const D = mkdtempSync(join(process.env.TMPDIR || "/tmp", "test-check-flow-step-numbers-"));
process.on("exit", () => rmSync(D, { recursive: true, force: true }));
let f = 0;
const t = (code, args, want, name) => { const r = spawnSync(process.execPath, [S, ...args], { encoding: "utf8" }); const out = r.stdout + r.stderr; if (r.status !== code || (want && !out.includes(want))) { console.log(`失敗: ${name}(終了コード ${r.status})`); f = 1; } else console.log(`成功: ${name}`); };
const w = (name, body) => { const p = join(D, name); writeFileSync(p, body); return p; };
const ok = `---
name: trying-fixture
description: 試しの SKILL.md。
---

# 試しの確認

## 全体像

- 目的: スクリプトを試す。

### 開始時の入力

| 項目 | 入力の種類 | 必須か任意か | 受け取り方 | 読み取れないときの動作 |
|---|---|---|---|---|
| パス | ユーザーのチャット入力 | 必須 | 依頼の文面 | 中止する(step 2-1) |

### 受け渡す値

| 名前 | 出す step | 使う step |
|---|---|---|
| 読んだパス | 2-1 | 2-2、3-1 |
| 直したい点 | 2-2 | 2-1(step 2-2 から戻ったときだけ) |

### 中間成果物

なし

### 最終出力

| 名前 | 出力の種類 | 見分け方 | 0 件でもよいか |
|---|---|---|---|
| ユーザーへの完了の報告 | チャットへの表示(ユーザーへの完了の報告) | 完了の 1 行 | いいえ |

### 流れ

| phase | 名前 | step |
|---|---|---|
| 1 | 全スキル共通の決まりの読み込み | 1-1 |
| 2 | 入力の確定 | 2-1 から 2-2 |
| 3 | 最終出力の確認とユーザーへの完了の報告 | 3-1 |

## 前提ツール

なし

## 使用するスクリプト

なし

## 使用するリファレンス

なし

## phase 1 全スキル共通の決まりの読み込み

### step 1-1 全スキル共通の決まりを読む

#### 手順

\`\`\`\`markdown
\`\`\`text
### step 9-9 コードブロックの中の見出し
\`\`\`
\`\`\`\`

#### ── step 1-1 の情報 ──

- 入力: なし
- 出力: なし

## phase 2 入力の確定

### step 2-1 依頼を読み取る

#### 手順

パスを読み取る。

#### ── step 2-1 の情報 ──

- 入力: 開始時の入力のパスを受け取る。step 2-2 から戻ったときだけ、step 2-2 で受け取った直したい点も受け取る
- 出力: 読んだパスを step 2-2 と 3-1 へ渡す

### step 2-2 パスを確かめる [ユーザー確認]

#### ユーザーに見せる文面

確かめる。

#### 手順

確かめる。

#### ── step 2-2 の情報 ──

- 入力: 読んだパスを step 2-1 から受け取る
- 出力: 直したい点を step 2-1 へ渡す

## phase 3 最終出力の確認とユーザーへの完了の報告

### step 3-1 ユーザーに完了を報告する

#### 手順

報告する。

#### ── step 3-1 の情報 ──

- 入力: step 2-1 で作った読んだパスを受け取る
- 出力: ユーザーへの完了の報告をチャットに表示する
`;
t(0, [w("ok.md", ok)], "", "正しい SKILL.md は指摘なし");
t(1, [w("gap.md", ok.replace(/^### step 2-2 /m, "### step 2-3 "))], "並びでは step 2-2 の位置", "step の番号の空き");
t(1, [w("phase.md", ok.replace(/^## phase 3 /m, "## phase 4 "))], "phase 4 の前の phase が 2", "phase の番号の空き");
t(1, [w("range.md", ok.replace("| 2 | 入力の確定 | 2-1 から 2-2 |", "| 2 | 入力の確定 | 2-1 から 2-3 |"))], "流れの表の step は 2-1 から 2-3、見出しの step は 2-1 から 2-2", "流れの表の範囲と見出しの違い");
t(2, [join(D, "none.md")], "使い方", "ないファイルは呼び出しの誤り");
t(2, [], "使い方", "引数なしは呼び出しの誤り");
process.exit(f);
