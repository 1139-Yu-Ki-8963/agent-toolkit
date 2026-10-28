# 段階のスキルの表示と state.json の値の対応表

## 段階のスキルの表示と state.json の値の対応表

この章は、対応表である。実行者は、step 2-1 で、開始時の入力の「段階のスキルの最後の表示の文」から state.json の値を作るときに、この章を読む。この章の「表示の行の形」は、skill-factory の段階のスキル 10 本(規約 skill-making-flow の規則「スキルだけで動く 8 段階の流れ」の表のスキル)の `SKILL.md` の「ユーザーに見せる文面」と、`references/全スキル共通の決まり.md` の「チャットへの表示の書式」から写した行の形である。

### 段階のスキルと段階の番号

実行者は、表示の文の「- 目的:」の行の文と、「**<題名> が完了しました**」の行の題名を、次の表で段階の番号に対応させる。

| スキル | 段階の番号 | 題名 | 目的の 1 文目 |
|---|---|---|---|
| defining-skill-requirements | 1 | 要件定義書の作成 | スキルにしたい作業の依頼から、足りない情報をユーザーにまとめて聞いて埋め、何を作るかをユーザーと合意した要件定義書を書く。 |
| designing-skill-structure | 2 | スキルの分割の設計 | 要件定義書の作業の流れをスキルの単位に切り、作業ごとに受け持つスキルと、新しく作るスキルの作る順と項目を決めた分割設計書を書く。 |
| designing-skill-phases | 3 | 構成の案の設計 | 分割設計書の新しく作るスキル 1 本分を、雛形の形の phase と step に切り、phase ごとの入力と出力と合格の条件、step ごとの種別と流れのパターンを決めた構成の案を書く。 |
| drafting-skill-with-template | 4 | スキルの作成 | 依頼された作業を、規約と雛形に合ったスキルとして新しく書く。 |
| checking-skill-with-template | 5 | スキルの規約チェック | 対象のスキルが規約と雛形に合っているかを、何も知らないサブエージェント 3 体に確かめさせ、2 体以上が指した違反を一覧にして示す。 |
| fixing-skill | 5 | スキルの修正 | 出どころの文書(checking-skill-with-template か checking-markdown-document-with-rules が出した照合の指摘の一覧か、testing-skill-with-template が書いた判定の記録か、ユーザーの依頼の一覧)の指摘を仕分け、承認を得て、既にあるスキルのファイルの文を直し、直した箇所の意味が元と同じかを別の判定で確かめ、同じでない箇所を戻す。 |
| designing-skill-test-cases | 6 | スキルのテストケースの設計 | このスキルは、雛形で作ったスキルの SKILL.md とリファレンスから、シナリオテストのテストケースをすべて持つテスト計画書を作る。 |
| designing-skill-test-scenarios | 7 | スキルのテストシナリオの設計 | テスト計画書の動的なテストケースを、前提の状態、依頼の文、回答、実行の回数が同じものごとに 1 つのシナリオにまとめ、シナリオごとに通す phase と終わり方と仕様の行を付け、流す順を決め、ユーザーが選んだ実施する範囲で実施するシナリオを決めた章「シナリオテストの表」をテスト計画書に足す。 |
| testing-skill-with-template | 8 | シナリオテストの実行 | テスト計画書の静的なテストを流してから、実施するとしたシナリオを、スキルを初めて読むサブエージェント(実行役)に流し、テストケースごとの合否を判定の記録に残す。 |

### 表示の行の形と state.json の値の作り方

実行者は、表示の文の行を上から順に見て、次の表の「表示の行の形」と同じ形の行ごとに、「state.json のキー」の値を「値の作り方」のとおりに作る。表のどの形にも当たらない行は、読み飛ばす。表の山かっこは、表示の中の実行のたびに変わる値である。「いまの段階の要素」は、`artifacts` の `stage` が `stage` の値と同じ要素である。表示の文が `stage` の値を作らないときの `stage` は、依頼の文面のいまの段階の番号である。表示の文が `questions` の行を 1 行も持たないときの `questions` は、依頼の文面の質問の一覧(ないときは `null`)である。

| 表示の行の形 | 出すスキル | state.json のキー | 値の作り方 |
|---|---|---|---|
| `**次の内容で始めます**` と、その下の「- 目的: <目的の 1 文目>」(作業の開始をユーザーに伝える宣言) | すべての段階のスキル | `stage`、`artifacts[].status`、`currentSkill`、`decision`、`questions` | `stage` は、「段階のスキルと段階の番号」の表で目的の 1 文目が同じ行の段階の番号。いまの段階の要素の `status` は「下書き」。`currentSkill` は、`stage` が 1 か 2 なら `null`、3 以上なら依頼の文面の値。`decision` は `null`。`questions` は `null` |
| `**<題名> が完了しました**`(ユーザーへの完了の報告) | すべての段階のスキル | `stage`、`artifacts[].status`、`decision`、`questions` | `stage` は、「段階のスキルと段階の番号」の表で題名が同じ行の段階の番号。いまの段階の要素の `status` は「済み」。`decision` は `null`。`questions` は `null` |
| `**step <番号> で中止しました**` と、その下の「- ユーザーが次にすること: <ユーザーが次にすること>」(中止の表示) | すべての段階のスキル | `decision`、`questions` | `decision` の `question` は「- ユーザーが次にすること:」の行の値、`choices` は空の配列、`replies` は空の配列。`questions` は `null` |
| 質問の文の 1 行と、その下の選択肢の「表示する名前」(選択肢を提示するツールの質問。ユーザー確認) | すべての段階のスキル | `decision`、`artifacts[].status` | `decision` の `question` は質問の文、`choices` は表示する名前を表示の順に並べた配列(「(推奨)」を含めて表示のまま)、`replies` は空の配列。質問の文が「この要件定義書で、次の外部設計(designing-skill-structure)へ進んでよいですか。」「この分割設計書で、次の内部設計(designing-skill-phases)へ進んでよいですか。」「この構成の案で、次の下書き(drafting-skill-with-template)へ進んでよいですか。」「この構成で <出力先のフォルダ> にスキルを書いてよいですか。」のどれか(承認の質問)のときは、いまの段階の要素の `status` は「承認待ち」 |
| 「次の点を教えてください。」と、その下の「(<番号>) <項目の名前>」と、「候補 1(推奨): <候補>。理由: <理由>。」と「候補 <番号>: <候補>。」(候補を実行のたびに作るユーザーへの聞き取り) | defining-skill-requirements、drafting-skill-with-template | `decision` | `decision` の `question` は「次の点を教えてください。」の行と「(<番号>) <項目の名前>」の行を改行で連ねた文、`choices` は空の配列、`replies` は「候補 <番号>(推奨): <候補>。」と「候補 <番号>: <候補>。」の <候補> を表示の順に並べた配列(4 件まで) |
| 「<項目>を教えてください。」と、その下の「候補 1(推奨): <候補>。理由: <理由>。」(決まった文面のユーザーへの聞き取り) | すべての段階のスキル | `decision` | `decision` の `question` は「<項目>を教えてください。」の行(2 行以上なら改行で連ねた文)、`choices` は空の配列、`replies` は「候補 <番号>(推奨): <候補>。」の <候補> を並べた配列(候補の行がなければ空の配列) |
| 「前の答えで、質問が <増えた数> 問増え、<減った数> 問減りました。」 | defining-skill-requirements、designing-skill-structure、designing-skill-phases | `questions.added`、`questions.removed` | `added` は <増えた数>、`removed` は <減った数>。この行がなく、`questions` の行がほかにあるときは、どちらも 0 |
| 「質問 全 <全体の問数> 問(回答済み <回答済みの問数> 問、残り <残りの問数> 問)」 | defining-skill-requirements | `questions.title` | `title` は、この行の全文 |
| 「質問 <質問の番号>: <質問の文>」 | defining-skill-requirements | `questions.items[].number`、`questions.items[].text`、`questions.items[].answer` | `items` に、`number` が <質問の番号>、`text` が <質問の文>、`choices` が空の配列、`answer` が `null` の要素を 1 件足す |
| 「候補 1(推奨): <候補>。理由: <理由>。」(直前の「質問 <質問の番号>: <質問の文>」の行の下) | defining-skill-requirements | `questions.items[].choices` | 直前の「質問 <質問の番号>:」の行で足した要素の `choices` の 1 件目は <候補> |
| 「候補 <候補の番号>: <候補>。」(直前の「質問 <質問の番号>: <質問の文>」の行の下) | defining-skill-requirements | `questions.items[].choices` | 直前の「質問 <質問の番号>:」の行で足した要素の `choices` の <候補の番号> 件目は <候補> |
| 「答えるときは、1 行に 1 問ずつ「質問の番号: 答え」の形で書いてください。答えた問いの分だけを送れます。」 | defining-skill-requirements | `decision` | `decision` の `question` は、この行の全文、`choices` は空の配列、`replies` は空の配列 |
| 「質問 <質問の番号> / 全 <全体の問数> 問(回答済み <回答済みの問数> 問、残り <残りの問数> 問)」と、その次の行「<質問の文>」 | designing-skill-structure、designing-skill-phases | `questions.title`、`questions.items[].number`、`questions.items[].text`、`questions.items[].choices`、`questions.items[].answer`、`decision` | `title` は「質問 全 <全体の問数> 問(回答済み <回答済みの問数> 問、残り <残りの問数> 問)」。`items` に、`number` が <質問の番号>、`text` が <質問の文>、`choices` が空の配列、`answer` が `null` の要素を 1 件足す。`decision` の `question` は <質問の文>、`choices` は空の配列、`replies` は空の配列 |
| `**指摘の一覧**` と、その下の「雛形の違反: <雛形の違反の件数> 件」「規約の違反: <規約の違反の件数> 件」 | checking-skill-with-template | `stage`、`artifacts[].status` | `stage` は 5。いまの段階の要素の `status` は、2 つの件数がどちらも 0 なら「済み」、それ以外なら「下書き」 |
| `**<テスト対象のスキルの名前> のシナリオテストを実行しました**` と、その下の「- 結果: <実施した件数> 件中、合格 <合格の数> 件、不合格 <不合格の数> 件、判定できない <判定できないの数> 件」 | testing-skill-with-template | `stage`、`artifacts[].status` | `stage` は 8。いまの段階の要素の `status` は、不合格の数と判定できないの数がどちらも 0 なら「済み」、それ以外なら「下書き」 |

依頼の文面に成果物の状態がないときの `artifacts` は、`stage` より小さい `stage` の要素の `status` を「済み」、大きい要素の `status` を「未着手」、いまの段階の要素の `status` を表の「値の作り方」の値とした 8 件とする。
