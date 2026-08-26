def audit_archive(database, queue):
    database.execute("INSERT INTO audit_logs_archive SELECT * FROM audit_logs")
    queue.enqueue("cleanup_audit_logs")


if __name__ == "__main__":
    audit_archive(database, queue)
