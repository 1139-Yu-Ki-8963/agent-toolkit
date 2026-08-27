"""監査の記録を参照する窓口。見本の入力データとして最小限の実装を持つ。"""

MAX_PAGE_SIZE = 200
DEFAULT_PAGE_SIZE = 50


def list_audit_logs(database, page, page_size):
    if page_size > MAX_PAGE_SIZE:
        page_size = MAX_PAGE_SIZE
    offset = (page - 1) * page_size
    rows = database.query(
        "SELECT * FROM audit_logs ORDER BY created_at DESC LIMIT ? OFFSET ?",
        (page_size, offset),
    )
    return {"items": rows, "page": page, "pageSize": page_size}


def export_audit_logs(database, writer):
    for row in database.stream("SELECT * FROM audit_logs ORDER BY created_at"):
        writer.write(row)
    return writer.finish()


def get_user_audit(database, user_id):
    rows = database.query(
        "SELECT * FROM audit_logs WHERE user_id = ?", (user_id,)
    )
    if not rows:
        raise LookupError("該当する利用者の記録が無い")
    return {"userId": user_id, "items": rows}


def list_alerts(database, severity):
    if severity is None:
        return database.query("SELECT * FROM audit_alerts")
    return database.query(
        "SELECT * FROM audit_alerts WHERE severity = ?", (severity,)
    )


def get_retention_policy(config):
    return {
        "retentionDays": config.get("audit_retention_days", 365),
        "archiveEnabled": config.get("audit_archive_enabled", True),
    }
