# generating-reverse-detailed-design 工程詳細

SKILL.md の Phase 2（封印検証と facts 読込）〜Phase 5（完全性ゲート）の詳細手順を集約する。9 分類の定義（キーの付け方・抽出粒度）は `shared/references/facts-schema.md` を正本とする（本ファイルでは重複定義しない）。転記先の判定規律・字面転記と要約の境界・実測委譲の書式は `references/writing-rules.md` を正本とする（同上）。

## Phase 2 詳細: 封印検証と facts 読込

1. `shared/scripts/seal-facts.sh verify <facts_ref>` を実行する。exit 0 なら Phase を継続する。exit 1（facts.yml が封印時から改変されている）なら著述を行わず `status=BLOCKED` とし、hint に「extracting-unit-facts-from-code で再封印せよ」と記す（このゲートはループ対象外の終端条件であり、Phase 4 への差し戻しは発生しない）。
2. `<facts_ref>/facts.yml` を読み込む。9 分類（`sections` 配下のキー: import・export_type・const・state・handler・jsx・style・api・measurement_pending）の定義・キー付け規則は `shared/references/facts-schema.md` を参照する。
3. `common_docs_root` 配下のプロジェクト共通文書を読み込む（DESIGN.md 等の既存共通トークン・章マップとの整合確認に使う）。
4. `bash shared/scripts/check-facts-sufficiency.sh <facts_ref>/facts.yml` を実行し exit 0 を確認する（著述前の充足検査）。12分類キーの存在・items空時のreason記載・value充足・evidence形式・孤児参照の5検査を行う。exit 0 でなければ著述に入らず `status=BLOCKED` としてfacts抽出工程へ差し戻す。差し戻し理由には検査出力のchapter-impact行を添える。
5. 対象リポジトリの原本コードは一切 Read しない。facts.yml に事実の欠落・矛盾を発見した場合も自ら原本で確認せず、extracting-unit-facts-from-code への差し戻し事由として hint に記録する。

完了条件: `seal-facts.sh verify` が exit 0、`check-facts-sufficiency.sh` が exit 0、かつ facts.yml と共通文書の読込完了

## Phase 4 詳細: facts.yml → 章の転記

facts.yml の各セクションを対応する章へ転記する判定規律（章マップ準拠の転記先決定・facts のキー→設計書章の対応規律・字面転記と要約の境界・実測委譲の書式）は `references/writing-rules.md` を正本とする。SKILL.md 本文の転記マップ表（facts.yml セクション → §番号）と矛盾する記述を本ファイルには残さない。

章の役割キー → §番号の解決は起動引数 chapter_map_path（`shared/references/chapter-map.md`）を正本とする。§番号は既定値であり、設計書の章マップ表で解決する。

## Phase 5 詳細: 完全性ゲート

1. `scripts/check-fact-coverage.sh <facts_ref>/facts.yml <画面詳細設計書.md> [<DESIGN.md>]` を実行し exit 0 を確認する。未転記が 1 件でもあれば exit 1（fail-closed）で、未転記キーが stderr に列挙される。`measurement_pending`（⑨）のキーは、設計書に「実測委譲」の表記があれば転記済み扱いとして除外される（表記が無い場合のみ個別キー一致を要求する）。該当キーを Phase 4 のマップに従って転記してから再実行する。
2. 起動引数 audit_script_path（`shared/scripts/audit-consistency.sh`）を通常モードで実行し、章の内部整合性の違反が 0 件であることを確認する。

§15.2 が facts.yml の export_type「型定義なし・リテラル推論型」に基づく根拠付き該当なし文の場合も、audit_script_path はそのまま exit 0 を返す（検査gの型名抽出は§15.2テーブルの型名列〔1列目〕を対象とし、テーブル行が無い＝無マッチを許容する実装）。型を捏造して検査を通すことは禁止事項1（facts に無い事実の創作）違反であり、絶対に行わない。exit 1 は常に実違反として扱い、出力された「違反:」行に従って設計書を修正して再実行する。
5. 3 の 3 条件すべてが真の場合、以後の合否判定・下流工程への申し送り・検証記録の `audit_exit` フィールドには **実効値 `0`** を記録する（Phase 5 完了条件は「違反 0 件」であり「生の終了コードが 0」ではないため）。audit_script_path 自身が返す生の終了コード `1` は、3 条件の充足内容と併せて既知の非致命的スクリプト欠陥の証跡として別枠で保存し、実効値の代わりに報告しない
