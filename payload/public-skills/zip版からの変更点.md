# zip 版からの変更点

2026-10-05。`claude-skill-writing-compact.zip`(規約 3 本と drafting-skill-with-template)を正として取り込んだあとに加えた変更の一覧。本文の文言の変更だけを挙げ、改行コードの変換(CRLF から LF)は省く。

## 規約の 3 本(`rules/skill-writing/`。zip では `rules/skill-writing-compact/`)

- フォルダの名前を `skill-writing-compact` から `skill-writing` に改めた(12 本版を削除したため)。
- 先頭の `paths` を、agent-home では `**/skills/*/SKILL.md`、`**/skills/*/references/**`、`**/skills-pool/*/SKILL.md`、`**/skills-pool/*/references/**` の 4 行にした。公開版では `.claude/skills/**/*` と `.claude/rules/skill-writing/**/*` の 2 行に書き換えて写す。
- 雛形 `skill-template.md`: 「省ける部分」の表に「やり直しがあるときだけ」「委任があるときだけ」の 2 行を足し、「形」に(やり直し)と(委任)の step の形を足した。
- 完成例 `skill-completed-example.md`: step 2-1 の手順の後半を、雛形の「ファイルを出さないスキルだけ」の固定の文と一致させた(zip では「表の行は常に 1 行ある。出していれば…」だった)。
- 規約 `skill-writing-rule.md`: 規則 39(元に戻せない操作の前のユーザー確認)に「規則 13 が求める一時フォルダの削除は除く」の 1 文を足した(規則 13 と 39 の矛盾の解消)。 規則 10(step の入力と出力)に「前の step へ戻る流れで戻ったときだけ使う受け渡し値は、出す step が使う step より後でもよい」の例外を足した(ユーザー確認の「直したい点」とやり直しの戻り先の入力が、機械的な判定で違反になっていたため)。

## drafting-skill-with-template(`skills/drafting-skill-with-template/`)

- step 1-1: 自分自身の `SKILL.md` を読む前に `realpath` で実体のパスに解決する手順と、解決できないときの中止を足した(`~/.claude/skills/` のリンク経由では規約が読み込まれないため)。
- 分岐の step(1-1、1-4、1-5)の「手順」の項目を外し、その動作を「条件」の行に移した(雛形の分岐の形に「手順」がないため)。
- step 3-2: step 3-3 から戻ったときの入力と、戻ったときの手順(直したファイルだけを照らさせる)を足した(規則 37)。
- step 3-2: 検証者の返す出力の形を、雛形の照合の表と規約の照合の表の 2 つにした。
- step 3-3: 直す対象を 2 つの表の件にし、判断の観点を雛形の行と規則の両方にした。
- `references/検証の指示文.md`: 照合を、雛形の形の機械的な照合(a〜h)と規約の照合(規則 1〜42、完成例を目盛りに使う)の 2 段に書き換えた。
- ピンクの象の除去: 全体像の「書き足さない」「パスやファイル名、規則の番号は持たない」、開始時の入力の「(このスキルはパスを持たない)」、step 1-1 の「省かない」の文と `realpath` の括弧の補足、step 2-1 の「上限は緩めない」、step 3-2 の「まだ使っていない」と「渡さず」、step 3-3 の「何も直さずに」を外した。
