"""年次の集計帳票を組み立てる。見本の入力データとして最小限の実装を持つ。"""

ROWS_PER_PAGE = 40


def build_annual_report(database, year, renderer):
    rows = database.query(
        "SELECT organization_id, amount FROM sales WHERE fiscal_year = ?"
        " ORDER BY organization_id",
        (year,),
    )
    if not rows:
        raise LookupError("該当する年度の売上が無い")

    totals = {}
    for row in rows:
        key = row["organization_id"]
        totals[key] = totals.get(key, 0) + row["amount"]

    page = 1
    printed = 0
    for key in sorted(totals):
        if printed and printed % ROWS_PER_PAGE == 0:
            page += 1
            renderer.break_page(page)
        renderer.write_line(key, totals[key])
        printed += 1

    renderer.write_total(sum(totals.values()))
    return renderer.finish()
