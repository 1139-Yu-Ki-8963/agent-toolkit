#!/usr/bin/env python3
"""Generate pairwise (all-pairs) combinations as a Markdown table.

Input JSON:
  {"parameters": {"<name>": ["<value>", ...], ...}}

Usage:
  python3 pairwise.py --input '<json>'
  python3 pairwise.py --input-file params.json
  cat params.json | python3 pairwise.py

Exit codes:
  0  table printed, and every 2-way pair is covered
  1  allpairspy is not installed, or some 2-way pairs are not covered
  2  invalid input (no input, bad JSON, or the same value twice in one parameter)
"""

import argparse
import json
import sys


class NoInputError(Exception):
    pass


def load_allpairs():
    try:
        from allpairspy import AllPairs
    except ImportError:
        sys.stderr.write(
            "allpairspy が入っていません。次のコマンドで入れてから、もう一度実行してください。\n"
            f"  {sys.executable} -m pip install allpairspy\n"
        )
        sys.exit(1)
    return AllPairs


def read_input(args):
    if args.input is not None:
        text = args.input
    elif args.input_file is not None:
        with open(args.input_file, encoding="utf-8") as f:
            text = f.read()
    else:
        if sys.stdin is None or sys.stdin.isatty():
            raise NoInputError("入力がありません。")
        text = sys.stdin.read()
        if not text.strip():
            raise NoInputError("標準入力が空です。")
    return json.loads(text)


def validate(data):
    if not isinstance(data, dict) or not isinstance(data.get("parameters"), dict):
        raise ValueError('入力は {"parameters": {"名前": ["値", ...]}} の形の JSON にしてください。')
    params = data["parameters"]
    if len(params) < 2:
        raise ValueError("パラメータは 2 つ以上にしてください。")
    for name, values in params.items():
        if not isinstance(values, list) or len(values) == 0:
            raise ValueError(f"パラメータ「{name}」の値は、1 つ以上の値を持つ配列にしてください。")
        for i, v in enumerate(values):
            if v in values[:i]:
                raise ValueError(
                    f"パラメータ「{name}」に、同じ値 {json.dumps(v, ensure_ascii=False)} が 2 つ以上あります。"
                    "値は、パラメータの中で 1 回ずつにしてください。"
                )
    return params


def cell(value):
    return str(value).replace("|", "\\|").replace("\n", " ")


def uncovered_pairs(names, values_list, rows):
    """Return the set of 2-way pairs that no row covers (empty when all are covered)."""
    needed = set()
    for i in range(len(names)):
        for j in range(i + 1, len(names)):
            for a in range(len(values_list[i])):
                for b in range(len(values_list[j])):
                    needed.add((i, a, j, b))
    for row in rows:
        idx = [values_list[k].index(row[k]) for k in range(len(names))]
        for i in range(len(names)):
            for j in range(i + 1, len(names)):
                needed.discard((i, idx[i], j, idx[j]))
    return needed


def main():
    parser = argparse.ArgumentParser(description="Pairwise combinations as a Markdown table.")
    group = parser.add_mutually_exclusive_group()
    group.add_argument("--input", help="parameters JSON string")
    group.add_argument("--input-file", help="path to a parameters JSON file")
    args = parser.parse_args()

    try:
        params = validate(read_input(args))
    except NoInputError as e:
        sys.stderr.write(f"入力の誤り: {e}\n")
        parser.print_usage(sys.stderr)
        sys.stderr.write("--input か --input-file でパラメータの JSON を渡すか、標準入力に JSON を流してください。\n")
        sys.exit(2)
    except (ValueError, json.JSONDecodeError, OSError) as e:
        sys.stderr.write(f"入力の誤り: {e}\n")
        sys.exit(2)

    AllPairs = load_allpairs()

    names = list(params.keys())
    values_list = [list(v) for v in params.values()]
    rows = [list(r) for r in AllPairs(values_list)]

    missing = uncovered_pairs(names, values_list, rows)

    print("| No. | " + " | ".join(cell(n) for n in names) + " |")
    print("|---|" + "---|" * len(names))
    for no, row in enumerate(rows, start=1):
        print(f"| {no} | " + " | ".join(cell(v) for v in row) + " |")

    full = 1
    for v in values_list:
        full *= len(v)
    print()
    print(f"組み合わせ: {len(rows)} 件(すべての組み合わせは {full} 件)")
    if missing:
        print(f"覆えていない 2 つの組: {len(missing)} 件")
        sys.exit(1)
    print("すべての 2 つの組を、少なくとも 1 回覆っています。")


if __name__ == "__main__":
    main()
