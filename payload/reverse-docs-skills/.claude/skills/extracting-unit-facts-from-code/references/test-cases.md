# extracting-unit-facts-from-code テストケース

観点キーは連番禁止。内容を要約した意味語で付ける（番号からは情報を得られないため）。

| 観点キー | 前提 | 操作 | 期待結果 | 機械検証 |
|---|---|---|---|---|
| profile制約-未対応は中断 | profileがscreen・python以外 | Phase 1を実行する | 抽出せずstatus=中断を返す | 手動 |
| Python版本要件-3.7以下はfail-fast | profile=pythonでPython3.7以下の環境 | 抽出器を起動する | 実行前にexit2でfail-fastする | 手動 |
| 独立再計数-封印前の突合 | facts.ymlを作成済み | recount-facts.shを実行する | facts.ymlを読まず原本から独立算出してから突合する | 手動 |
| 再現性検証-現在時刻を書かない | 同一argsで2回抽出する | seal-facts.sh normalizeで比較する | run_idのみ異なるfacts.ymlはnormalize後に一致する | seal-facts.shのself-testケース「補助: run_idのみ異なるfacts.ymlはnormalize後に一致する」 |
| 盲点回避-検知漏れをreasonへ逃さない | recount-facts.shが実在パターンを構造的に検知できない | Phase 3の乖離判定を行う | itemsをreasonへ逃がさずパターンを拡張してから収束させる | 手動 |
| 孤児参照-完全一致判定 | evidenceのファイル部分がtarget_file_pathsの一部と一致する | 孤児参照検査を行う | サブパス一致では判定せず完全一致のみ判定する | 手動 |
| 封印-版不一致はexit3で区別 | facts.lockのNORMALIZE_VERSIONが現行と異なる | seal-facts.sh verifyを実行する | 改竄検知のexit1と区別しexit3で報告する | seal-facts.shのself-testケース「1-154b: 版が異なる封印は改竄ではなく規則変更として exit 3 で報告される」 |
| 封印-版一致下の改変は改竄検知 | 版は一致するがfacts.ymlの内容が変わる | seal-facts.sh verifyを実行する | 従来どおり改竄としてexit1で検知する | seal-facts.shのself-testケース「1-154c: 版が一致していても内容改変は従来どおり改竄としてexit 1で検知される」 |
| diff比較-一時ファイル経由に固定 | Phase 5で正規化出力を比較する | diffを実行する | プロセス置換を使わず一時ファイル経由で比較する | 手動 |
| 対象ファイル列挙-共有分は除外 | 子コンポーネントが他画面とも共有される | target_file_pathsを確定する | 画面専有コンポーネントのみを再帰列挙する | 手動 |
| ルーティング定義-対象外扱い | 複数画面の遷移を持つルーティング定義ファイルがある | target_file_pathsを確定する | 対象に含めずプロジェクト共通文書側で扱う | 手動 |
| 共通文書帰着-解釈分岐の差し戻し | 再現性検証の差分が共通文書未記載の解釈に起因する | Phase 5の診断分類を行う | status=共通文書帰着とし不足する観点をhintに記す | 手動 |

## 機械検証との対応

- 機械検証が「手動」の行は、guide.html の検証状況へ手動確認を記録する
- self-test に対応ケースを追加したら、この表の機械検証列を同じコミットで更新する
