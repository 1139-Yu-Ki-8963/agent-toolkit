#!/usr/bin/env python3
"""既存の用語データを移行の3状態へ分類する。

契約 delivery-payload/references/semantic-glossary-contract-v0.1.md は次を定める。

- 24行目: 確認できない移行データは `legacy_migrated` として再承認まで公開しない。
- 136行目: `publication_status` は `candidate|approved|legacy_migrated` のいずれか。

本スクリプトは既存の用語集を読み、各用語を次の基準で分類する。
自動で承認しない。判断の根拠を出力へ残す。

| 分類 | 基準 |
|---|---|
| approved | 承認の記録（decision_ref と change_ref）が揃い、出典が1件以上ある |
| candidate | 出典はあるが承認の記録が欠ける |
| legacy_migrated | 出典が無い、または読み取れない |

実装判断（依存）: PyYAML を使う。無ければ判定不能として終了コード2を返す
（.claude/rules/always/verification/indeterminate-result/rule.md）。
検証器（validate-semantic-glossary.py）と同じ依存であり、新たな依存は増やさない。
"""
from __future__ import annotations

import argparse
import json
import sys

try:
    import yaml
except ImportError:
    print("[UNKNOWN] PyYAML が無いため判定できません"
          "（用語の読み取りに必要です。requirements.txt の依存を入れてください）",
          file=sys.stderr)
    sys.exit(2)


def classify_term(term: dict) -> tuple[str, str]:
    """1件の用語を分類し、(状態, 理由) を返す。"""
    prov = term.get("provenance")
    if not isinstance(prov, dict):
        return "legacy_migrated", "出典の記録そのものが無い"

    sources = prov.get("sources")
    if not isinstance(sources, list) or not sources:
        return "legacy_migrated", "出典が1件も無い"

    decision = prov.get("decision_ref")
    change = prov.get("change_ref")
    if isinstance(decision, str) and decision and isinstance(change, str) and change:
        return "approved", "承認の記録（提案と変更）が揃っている"

    missing = []
    if not (isinstance(decision, str) and decision):
        missing.append("提案の参照")
    if not (isinstance(change, str) and change):
        missing.append("変更の参照")
    return "candidate", "出典はあるが%sが欠ける" % "と".join(missing)


def run(path: str) -> dict:
    with open(path, encoding="utf-8") as fh:
        doc = yaml.safe_load(fh)
    if not isinstance(doc, dict):
        raise ValueError("用語集の中身が辞書ではありません")

    terms = doc.get("terms")
    if not isinstance(terms, list):
        raise ValueError("terms が配列ではありません")

    result = {"approved": [], "candidate": [], "legacy_migrated": []}
    reasons = {}
    for term in terms:
        if not isinstance(term, dict):
            result["legacy_migrated"].append("(読み取れない項目)")
            continue
        key = term.get("key") or "(キーなし)"
        state, reason = classify_term(term)
        result[state].append(key)
        reasons[key] = reason

    return {
        "総数": len(terms),
        "分類": {k: len(v) for k, v in result.items()},
        "内訳": result,
        "理由": reasons,
    }


def main() -> int:
    parser = argparse.ArgumentParser(
        description="既存の用語を移行の3状態へ分類する（自動で承認しない）")
    parser.add_argument("--input", required=True, help="用語集のYAML")
    parser.add_argument("--output", help="分類の結果を書き出すJSON（省略時は標準出力）")
    args = parser.parse_args()

    try:
        report = run(args.input)
    except FileNotFoundError:
        print("[UNKNOWN] 入力が見つかりません: %s" % args.input, file=sys.stderr)
        return 2
    except Exception as exc:  # noqa: BLE001
        print("ERROR: %s" % exc, file=sys.stderr)
        return 1

    text = json.dumps(report, ensure_ascii=False, indent=2, sort_keys=True)
    if args.output:
        with open(args.output, "w", encoding="utf-8") as fh:
            fh.write(text + "\n")
    else:
        print(text)

    total = report["総数"]
    counted = sum(report["分類"].values())
    if total != counted:
        print("ERROR: 全行を分類できていません（総数 %d / 分類 %d）" % (total, counted),
              file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
