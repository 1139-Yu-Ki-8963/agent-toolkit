# NOTICE

このリポジトリの規約と skill は、pstack をもとに作っています。

- 元の作品: pstack(https://github.com/cursor/plugins/tree/main/pstack)
- 参照したバージョン: 0.15.36(cursor/plugins のコミット 3dbd22ff12742fb28c9700b9760baa29ed41dc13、2026年11月13日)
- 元の作者: Lauren Tan
- 元のライセンス: MIT License(下に全文を掲載)

## pstack から派生したファイル

すべて、英語の原文を日本語に訳し、要約、再構成したものです。原文をそのまま収録したファイルはありません。

| このリポジトリのファイル | もとにした pstack のファイル |
|---|---|
| `rules/veteran-engineer.md` | `skills/principle-*/SKILL.md` のうち、設計判断と検証に関わる12本 |
| `rules/agent-behavior.md` | `skills/principle-*/SKILL.md` のうち4本(guard-the-context-window、never-block-on-the-human、build-the-lever、encode-lessons-in-structure)と、`skills/poteto-mode/SKILL.md` の Non-negotiables、Autonomy、Subagents、Writing the reply の各章 |
| `skills/investigate/SKILL.md` | `skills/poteto-mode/playbooks/investigation.md`、`skills/how/SKILL.md`、`skills/why/SKILL.md` |
| `skills/prototype/SKILL.md` | `skills/poteto-mode/playbooks/prototype.md` |
| `skills/plan/SKILL.md` | `skills/poteto-mode/playbooks/multi-phase-plan.md` |
| `skills/feature/SKILL.md` | `skills/poteto-mode/playbooks/feature.md`、`skills/architect/SKILL.md`、`skills/interrogate/SKILL.md` |
| `skills/bug-fix/SKILL.md` | `skills/poteto-mode/playbooks/bug-fix.md`、`skills/tdd/SKILL.md` |
| `skills/refactor/SKILL.md` | `skills/poteto-mode/playbooks/refactoring.md` |
| `skills/performance/SKILL.md` | `skills/poteto-mode/playbooks/perf-issue.md`、`skills/benchmark-checklist/SKILL.md` |
| `skills/open-pr/SKILL.md` | `skills/poteto-mode/playbooks/opening-a-pr.md` |
| `skills/pr-followup/SKILL.md` | `skills/poteto-mode/playbooks/babysit.md` |

## 元のライセンス

```
MIT License

Copyright (c) 2026 Lauren Tan

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```
