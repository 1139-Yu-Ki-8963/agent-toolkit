#!/usr/bin/env python3
"""Validate that a template-only HTML contains structure, never populated data."""
import argparse
import hashlib
import pathlib
import re
from html.parser import HTMLParser

SCHEMAS = {
    "batch-requirements.md": {
        "headings": ["バッチ要件"],
        "columns": ["バッチ", "目的", "起動条件", "入力", "出力", "根拠", "未確定事項"],
    },
    "business-overview.md": {
        "headings": ["ビジネス概要", "背景", "目的", "対象範囲", "関係者", "未確定事項"],
        "columns": [],
    },
    "external-requirements.md": {
        "headings": ["外部連携要件"],
        "columns": ["連携先", "目的", "方式", "入力", "出力", "根拠", "未確定事項"],
    },
    "feature-requirements.md": {
        "headings": ["機能要件一覧"],
        "columns": ["機能", "概要", "利用者", "根拠", "未確定事項"],
    },
    "report-requirements.md": {
        "headings": ["帳票要件"],
        "columns": ["帳票", "目的", "出力条件", "形式", "根拠", "未確定事項"],
    },
    "requirements-business-overview.html": {
        "headings": ["要件定義・ビジネス概要", "背景", "目的", "対象範囲", "関係者", "未確定事項"],
        "columns": [],
    },
    "review-checklist.html": {
        "headings": ["レビュー観点表"],
        "columns": ["観点", "確認内容", "根拠", "結果"],
    },
    "test-policy.html": {
        "headings": ["テスト方針書", "目的"],
        "columns": ["種別", "対象", "方法", "根拠"],
    },
}
STYLE_SHA256 = {
    "requirements-business-overview.html": "7d2038091a15ad50ed2c7a1f165fbef054bd7d8989b10571d4dd5f21727c7419",
    "review-checklist.html": "25b95b5979bb06f8e3e3242fb4481a7c45a10d984178bc83ee48667b3ef32873",
    "test-policy.html": "50e5c0580f060ab7abcb6fc159ff150fa00f8e194d973c144b26c372d731b393",
}
ALLOWED_ATTRIBUTES = {
    "html": {"lang": {"ja"}},
    "meta": {
        "charset": {"UTF-8", "utf-8"},
        "name": {"viewport"},
        "content": {"width=device-width, initial-scale=1"},
    },
    "div": {"class": {"template-page", "table-wrap"}},
    "table": {"id": {"test-case-list"}},
    "tbody": {"data-zero-case": {"true"}},
    "th": {"scope": {"col"}},
}
ALLOWED_PARENTS = {
    "html": {None},
    "head": {"html"},
    "body": {"html"},
    "meta": {"head"},
    "title": {"head"},
    "style": {"head"},
    "div": {"body", "main"},
    "header": {"div"},
    "main": {"div"},
    "h1": {"header"},
    "section": {"main"},
    "h2": {"section"},
    "table": {"div"},
    "caption": {"table"},
    "thead": {"table"},
    "tbody": {"table"},
    "tr": {"thead", "tbody"},
    "th": {"tr"},
    "td": {"tr"},
}
VOID_TAGS = {"meta"}
SAMPLE_OUTPUTS = {
    "レビュー観点表.html": "# レビュー観点表",
    "テスト方針書.html": "# テスト方針書",
}


class StructureParser(HTMLParser):
    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.invalid = False
        self.comments = 0
        self.scripts = 0
        self.styles = []
        self.titles = []
        self.stack = []

    def handle_starttag(self, tag, attrs):
        tag = tag.lower()
        parent = self.stack[-1] if self.stack else None
        if tag not in ALLOWED_PARENTS or parent not in ALLOWED_PARENTS[tag]:
            self.invalid = True
        if tag not in VOID_TAGS:
            self.stack.append(tag)
        if tag == "script":
            self.scripts += 1
            self.invalid = True
        seen = set()
        for name, value in attrs:
            name = name.lower()
            if name in seen or value is None:
                self.invalid = True
                continue
            seen.add(name)
            if value not in ALLOWED_ATTRIBUTES.get(tag, {}).get(name, set()):
                self.invalid = True

    def handle_startendtag(self, tag, attrs):
        depth = len(self.stack)
        self.handle_starttag(tag, attrs)
        if len(self.stack) > depth:
            self.stack.pop()

    def handle_endtag(self, tag):
        if self.stack and self.stack[-1] == tag.lower():
            self.stack.pop()
        else:
            self.invalid = True

    def handle_decl(self, decl):
        if decl.lower() != "doctype html":
            self.invalid = True

    def handle_comment(self, data):
        self.comments += 1
        self.invalid = True

    def handle_data(self, data):
        if not self.stack:
            if data.strip():
                self.invalid = True
            return
        if self.stack[-1] == "style":
            self.styles.append(data)
        elif self.stack[-1] == "title" and data.strip():
            self.titles.append(data.strip())
        elif self.stack[-1] in {"head", "html"} and data.strip():
            self.invalid = True


def clean(value: str) -> str:
    return re.sub(r"<[^>]+>", "", value).strip()


def validate_sample_output(path: pathlib.Path) -> int:
    heading = SAMPLE_OUTPUTS.get(path.name)
    if heading is None:
        return 1
    try:
        text = path.read_text()
    except OSError:
        return 1
    if re.search(
        r"サンプルプロジェクト|更新\s*:\s*\d{4}-\d{2}-\d{2}|"
        r"\b20\d{2}[-/]\d{1,2}[-/]\d{1,2}\b",
        text,
    ):
        return 1
    required = (
        '<span class="brand-title">プロジェクト</span>',
        '<span class="pm-updated">更新日</span>',
        heading,
    )
    return 0 if all(value in text for value in required) else 1


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("template")
    parser.add_argument("--sample-output", action="store_true")
    args = parser.parse_args()
    path = pathlib.Path(args.template)
    if not path.is_file():
        return 1
    if args.sample_output:
        return validate_sample_output(path)
    schema = SCHEMAS.get(path.name)
    if schema is None:
        return 1
    text = path.read_text()
    forbidden = re.compile(
        r"(サンプル|記入例|具体例|推奨|すべき|望ましい|架空|FAKE|"
        r"\b(?:ID|API|USR)-\d+\b)",
        re.IGNORECASE,
    )
    if forbidden.search(text):
        return 1
    if path.suffix == ".md":
        headings = [
            match.group(1).strip()
            for match in re.finditer(r"^#{1,2}\s+(.+?)\s*$", text, re.M)
        ]
        table_lines = [
            line for line in text.splitlines()
            if line.strip().startswith("|")
        ]
        table_rows = [
            [cell.strip() for cell in line.strip().strip("|").split("|")]
            for line in table_lines
        ]
        columns = table_rows[0] if table_rows else []
        if columns:
            if len(table_rows) < 2 or len(table_rows[1]) != len(columns):
                return 1
            if not all(
                re.fullmatch(r":?-{3,}:?", cell)
                for cell in table_rows[1]
            ):
                return 1
        data_rows = [
            row for row in table_rows[2:]
            if any(cell for cell in row)
        ]
        if data_rows:
            return 1
        structural_lines = re.compile(
            r"^(?:\s*|#{1,2}\s+.+|\|.+\|)\s*$"
        )
        if any(
            not structural_lines.fullmatch(line)
            for line in text.splitlines()
        ):
            return 1
    else:
        parser_state = StructureParser()
        try:
            parser_state.feed(text)
            parser_state.close()
        except Exception:
            return 1
        style = "".join(parser_state.styles)
        style_hash = hashlib.sha256(style.encode()).hexdigest()
        if (
            parser_state.invalid
            or parser_state.stack
            or parser_state.scripts
            or parser_state.comments
            or parser_state.titles != [schema["headings"][0]]
            or style_hash != STYLE_SHA256.get(path.name)
        ):
            return 1
        headings = [clean(value) for value in re.findall(
            r"<h[12]\b[^>]*>(.*?)</h[12]>", text, re.I | re.S)]
        columns = [clean(value) for value in re.findall(
            r"<th\b[^>]*>(.*?)</th>", text, re.I | re.S)]
        body_match = re.search(r"<body\b[^>]*>(.*?)</body>", text, re.I | re.S)
        if body_match is None:
            return 1
        if not re.fullmatch(
            r"\s*</html>\s*",
            text[body_match.end():],
            re.I | re.S,
        ):
            return 1
        body = body_match.group(1)
        body = re.sub(
            r"<(?:h[12]|th|caption)\b[^>]*>.*?</(?:h[12]|th|caption)>",
            "",
            body,
            flags=re.I | re.S,
        )
        body = re.sub(r"<td\b[^>]*>\s*</td>", "", body, flags=re.I | re.S)
        body = re.sub(
            r"</?(?:div|header|main|section|table|thead|tbody|tr)\b[^>]*>",
            "",
            body,
            flags=re.I,
        )
        if body.strip():
            return 1
    if headings != schema["headings"] or columns != schema["columns"]:
        return 1
    if path.suffix != ".md":
        for cell in re.findall(r"<td\b[^>]*>(.*?)</td>", text, re.I | re.S):
            if re.sub(r"<[^>]+>", "", cell).strip():
                return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
