<!-- AUTO-GENERATED from build-loop.md.tmpl — do not edit directly -->
<!-- Regenerate: bun run gen:skill-docs -->
## Build loop: /design-review --build

この節は、作っている途中の UI のための、選んだときだけ走る手順である。AI は、ローカルのプレビューで状態ごとに lint とスクリーンショットを取り、直し、最後に受領の 1 行で終える。この手順は、監査の Phase に代わって走る。この手順は、commit、stash、checkout、reset を一切行わず(この作業の変更は残る)、人がいない実行では never asks(代わりに NEEDS INPUT を記録する)。
結果を決めるのは `gstack-design-build` であり、この節は、その証拠を集める。

**7 つの項目**(AI は、スクリーンショットの 1 枚ずつで確かめる):

| # | 項目 | 規則 |
|---|------|------|
| 1 | Row padding holds with one line and with two | `row-crowding` (edge) |
| 2 | Adjacent rows have breathing room | `row-crowding` (next row) |
| 3 | 説明の文が、上に余白を持ち、隣の節と同じ控えめな見せ方をしている | `copy-flush-under-list` |
| 4 | Status notes sit on their own line with a warning treatment | `note-in-row-weight` |
| 5 | 見出し、名前、補足が、隣の節と同じ順に上から並んでいる | 目で見るだけ |
| 6 | Comfortable hit areas | `small-hit-area` |
| 7 | Nothing overflows at 375 | `section-overflow` |

項目 3 と 5 では、リポジトリの流儀が優先する。AI は、隣の節と比べて判断する。

### 1. 状態の一覧

```bash
SLUG=$(~/.claude/skills/gstack/bin/gstack-slug --get SLUG 2>/dev/null)
GSTACK_STATE_ROOT=$(~/.claude/skills/gstack/bin/gstack-paths --get GSTACK_STATE_ROOT); : "${GSTACK_STATE_ROOT:?gstack-paths failed; reinstall with ./setup or /gstack-upgrade}"
RUN="$GSTACK_STATE_ROOT/projects/$SLUG/designs/design-build-run-$(date -u +%Y%m%dT%H%M%SZ)"
mkdir -p "$RUN" && chmod 700 "$RUN" && echo "RUN: $RUN"
```

ブロックは、毎回新しいシェルで走る。`<run-dir>` は、表示された `RUN:` のパスである。AI は、仕様と差分から `<run-dir>/inventory.json` を書く。中身は、変更が見せうる、シナリオ × 重ねて出るもの × busy、success、error、empty のすべてである。

```json
{"version":1,"within":"<section selector>","fixtures":"<repo-relative fixture dir>","touched":["<untracked files you create>"],
 "states":[{"name":"owner","url":"http://127.0.0.1:5300/settings?as=owner","expect":"<selector only this state renders>"},
           {"name":"remove-confirm","mode":"screenshot","steps":"click Remove on the second row"}]}
```

URL の状態は、`?as=<scenario>` と、その状態がデータ付きで描かれたことを示す `expect` のセレクタを持つ。クリックが要る状態は `"mode":"screenshot"` とし、lint 済みとは数えない。プレビューとフィクスチャ:
`docs/howto-preview-a-frontend.md`。

### 2. 事前の確かめ(どのラウンドよりも前)

```bash
~/.claude/skills/gstack/bin/gstack-design-build preflight --inventory "<run-dir>/inventory.json"
```

確かめる順は、ブラウザ、対象(loopback だけ。ほかのホストには、本人が書いた `--grant-remote <host>` が要る。AI が自分で足すことは決してない)、届くかどうかである。ここで出た `DESIGN_BUILD:` の行は、この実行の最後の行である。AI は止まる。
`code=NO_PREVIEW` のときは、AI は、プレビューを起動し、事前の確かめを 1 回だけ走らせ直す。`mutations=unknown`(どのプレビューも答えなかった)のときは、AI は、変更した操作を決して動かさない。動かすと、本番のバックエンドに届くことがある。

### 3. Rounds (three at most)

```bash
~/.claude/skills/gstack/bin/gstack-design-build plan --inventory "<run-dir>/inventory.json" --run-dir "<run-dir>/round-N"
```

1. Run the printed `LINT_CMD:` line exactly. AI は、`<run-dir>/round-N/lint.json` の
   `app.verdict`、`app.codes`、`app.states[]` と、問題の一覧を読む。Never
   read the lint's exit status as the result.
2. AI は、`SHOT:` の行の 1 つずつで、その viewport のスクリーンショットを取る(スクリーンショットだけの状態は、その steps で取る)。Aside: `gstack-aside-repl --out` the
   `SHOT:` path's folder (rule 8); $B: /tmp, then cp it to the `SHOT:` path.
3. AI は、すべてのスクリーンショットで、7 つの項目を確かめる。
4. AI は、変更した操作の 1 つずつを、busy、success、error、立ち直りまで動かし、キーボードで閉じて、きっかけの要素に戻ることを確かめる。
5. AI は、ソースとフィクスチャで直す。変更は commit しないまま残す。

終わっていない状態(`app.states[]` にコードがあるもの)は、仕掛けの問題であり、ラウンドとは数えない。AI は、名前の出た原因を直し、その状態を走らせ直す。プレビューの 501 は、実行を終わらせる。AI は、その route を足し、プレビューを起動し直し、事前の確かめから走らせ直す。Stop
editing after round 3, or earlier once a round is clean.

### 4. 最後の確かめ(読むだけ)と受領

AI は、許された最後の変更のあとに、何も変えない 1 回の確かめを行う(問題を免除するときは、`plan` と `receipt` に `--waivers <file>` を足す):

```bash
~/.claude/skills/gstack/bin/gstack-design-build plan --inventory "<run-dir>/inventory.json" --run-dir "<run-dir>/final"
~/.claude/skills/gstack/bin/gstack-design-build verify-start --inventory "<run-dir>/inventory.json" --run-dir "<run-dir>/final"
```

AI は、その `LINT_CMD:` の行と、すべての `SHOT:` の行を走らせ、次を走らせる(`N`: 変更を入れたラウンドの数。プレビューがその状態を出したときは、`--preview <state dir>` を足す):

```bash
N=
~/.claude/skills/gstack/bin/gstack-design-build receipt --inventory "<run-dir>/inventory.json" --run-dir "<run-dir>/final" --rounds "${N:?}"
```

その `DESIGN_BUILD:` の行を、変えずにそのまま、この実行の最後で唯一の行とする。There is no
fourth editing round without a written grant.

### 5. 結果

| 結果 | 意味 | 次 |
|---------|-------|------|
| `clean` / `waived` | すべての URL の状態を、すべての viewport で lint し、すべての状態を撮り、開いた問題がない | そのまま報告する |
| `open` | 範囲はすべて覆ったが、開いた問題がある | 1 件ずつに、理由付きの免除か、PR の本文の 1 行を付ける |
| `incomplete` | どこかで lint していない状態、撮っていない状態、プレビューの 501、古い証拠のどれかがある | その直しの行を示し、残りは PR の本文に、確かめていないものとして並べる |
| `unrendered` | インストール、ブラウザ、プレビューのどれかがない | その直しの行を示す |
| `stale` | 受領のあとに作業フォルダが変わった | 最後の確かめを走らせ直す |

READY がそれを引く前に、`~/.claude/skills/gstack/bin/gstack-design-build check --inventory "<run-dir>/inventory.json" --receipt <file>`
が、それを表示し直さなければならない。`incomplete` は、決して、レーンのカードの推奨を満たさない。
