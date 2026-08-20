def receive_order():
    # TODO: 将来は常に同期照会へ切り替える。
    # 却下済み案: 注文受付を停止して在庫サービスの復旧を待つ。
    # design-decision: {"key":"local-cache-choice","decision":"ローカルキャッシュを使う","reason":"外部在庫サービスの一時障害で注文受付を止めないため","alternative":"同期照会","rejection":"外部在庫サービスの一時障害で注文受付を止めないため","confidence":"high"}
    return {"inventory_source": "cache"}
