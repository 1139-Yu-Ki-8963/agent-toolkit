// データ正本。スキーマは docs/13_業務管理ポータル設計/02_データモデル設計.md 参照。更新は consult-portal-update スキル経由
// 出典: コンサル業務管理 プロトタイプ.dc.html の logic クラス（data() / extraIssues() / decData() / docsVals() / peopleVals() / meetingsVals() / accessVals() / projVals()）
window.PORTAL_DATA = {
  "projects": [
    {
      "key": "a",
      "ini": "A",
      "name": "A社 DX推進支援",
      "sub": "2026 Q3 · ルーティン 毎週金",
      "issues": 20,
      "alerts": 3
    },
    {
      "key": "b",
      "ini": "B",
      "name": "B社 新規事業戦略策定",
      "sub": "2026 Q3 · ルーティン 隔週火",
      "issues": 8,
      "alerts": 1
    },
    {
      "key": "c",
      "ini": "C",
      "name": "C社 コスト構造改革",
      "sub": "2026 Q3 · ルーティン 毎週月",
      "issues": 12,
      "alerts": 0
    },
    {
      "key": "d",
      "ini": "D",
      "name": "D社 営業改革PMO",
      "sub": "通年 · ルーティン 毎週水",
      "issues": 15,
      "alerts": 2
    },
    {
      "key": "e",
      "ini": "E",
      "name": "E社 基幹システム刷新構想",
      "sub": "2026 Q4 · ルーティン 毎週木",
      "issues": 9,
      "alerts": 1
    },
    {
      "key": "f",
      "ini": "F",
      "name": "F社 中期経営計画策定",
      "sub": "2026 Q3 · ルーティン 隔週金",
      "issues": 6,
      "alerts": 0
    },
    {
      "key": "g",
      "ini": "G",
      "name": "G社 組織再編・PMI支援",
      "sub": "2026 Q3-4 · ルーティン 毎週火",
      "issues": 11,
      "alerts": 4
    },
    {
      "key": "h",
      "ini": "H",
      "name": "H社 データ基盤構想",
      "sub": "2026 Q4 · ルーティン 隔週水",
      "issues": 7,
      "alerts": 0
    },
    {
      "key": "i",
      "ini": "I",
      "name": "I社 業務プロセス標準化",
      "sub": "通年 · ルーティン 毎週月",
      "issues": 14,
      "alerts": 2
    },
    {
      "key": "j",
      "ini": "J",
      "name": "J社 サプライチェーン診断",
      "sub": "2026 Q3 · ルーティン 隔週木",
      "issues": 10,
      "alerts": 1
    }
  ],
  "issues": [
    {
      "id": "ISS-04",
      "name": "データ品質",
      "title": "基幹システムのデータ品質が想定より低い",
      "prio": "高",
      "goal": "9月末までにクレンジング方針を合意し、10月の現状分析に使える状態へ",
      "crit": [
        "クレンジング方針がA社と合意済(決定事項に記録)",
        "品質基準書v1が両者承認済",
        "10月の分析に使うデータセットが検収済"
      ],
      "deliv": [
        {
          "type": "DOC",
          "n": "データ品質基準書 v1",
          "st": "作成中",
          "due": "9/12"
        },
        {
          "type": "XLS",
          "n": "クレンジング済データセット(検収版)",
          "st": "先方待ち",
          "due": "9/30"
        },
        {
          "type": "PPT",
          "n": "品質評価サマリー(ルーティン報告用)",
          "st": "未着手",
          "due": "9/12"
        }
      ],
      "ms": [
        {
          "name": "品質基準の合意",
          "due": "9/12"
        },
        {
          "name": "クレンジング完了・検収",
          "due": "9/30"
        }
      ],
      "tasks": [
        {
          "t": "欠損・重複の実態調査(サンプル1万行)",
          "done": true,
          "due": "8/25",
          "side": "us",
          "owner": "高橋",
          "ms": 0
        },
        {
          "t": "影響範囲をスコープ表に反映",
          "done": true,
          "due": "8/27",
          "side": "us",
          "owner": "田中",
          "ms": 0
        },
        {
          "t": "クレンジング分担案を作成",
          "done": true,
          "due": "8/29",
          "side": "us",
          "owner": "田中",
          "ms": 0
        },
        {
          "t": "分担案のレビュー依頼を送付",
          "done": false,
          "due": "9/3",
          "side": "us",
          "owner": "田中",
          "ms": 0
        },
        {
          "t": "分担案のレビュー回答",
          "done": false,
          "due": "9/8",
          "side": "cl",
          "owner": "山本部長",
          "ms": 0
        },
        {
          "t": "品質基準の最終合意(ルーティン)",
          "done": false,
          "due": "9/12",
          "side": "us",
          "owner": "田中",
          "ms": 0
        },
        {
          "t": "クレンジング一次対応",
          "done": false,
          "due": "9/30",
          "side": "cl",
          "owner": "小林氏",
          "ms": 1
        },
        {
          "t": "A社側作業の進捗確認(週次)",
          "done": false,
          "due": "毎週金",
          "side": "us",
          "owner": "田中",
          "ms": 1
        }
      ],
      "notes": [
        [
          "f",
          "売上データ34万行のうち12%に欠損・8%に重複",
          "8/25 実態調査"
        ],
        [
          "f",
          "欠損の発生源は旧システムからの移行データ",
          "8/26 小林氏ヒアリング"
        ],
        [
          "j",
          "当社で巻き取ると分析開始が約3週遅延。A社側一次対応+当社は基準策定・検収が妥当",
          "田中 8/27"
        ],
        [
          "r",
          "A社側の対応リソースが不足すると10月開始が後ろ倒しになる",
          "田中 8/29"
        ],
        [
          "q",
          "品質基準の閾値(欠損許容率)をどこに置くか",
          "9/12ルーティンで協議"
        ]
      ],
      "rels": [
        [
          "doc",
          "売上データ抽出_2024-2026.xlsx"
        ],
        [
          "doc",
          "システム構成一覧.pdf"
        ],
        [
          "ppl",
          "山本部長"
        ],
        [
          "ppl",
          "小林氏"
        ],
        [
          "dec",
          "DEC-06",
          "DEC-06 クレンジングはA社側で一次対応"
        ],
        [
          "mtg",
          "8/29 週次ルーティン(第8回)"
        ],
        [
          "mtg",
          "8/22 週次ルーティン(第7回)"
        ]
      ],
      "aiLabel": "✦ AI解読済 · 最終同期 8/29"
    },
    {
      "id": "ISS-07",
      "name": "ヒアリング日程",
      "title": "現場部門のヒアリング日程が確定しない",
      "prio": "高",
      "goal": "現場3部門のヒアリングを9月第2週までに完了させる",
      "crit": [
        "3部門すべてのヒアリングが実施済",
        "分析メモがA社と共有済"
      ],
      "deliv": [
        {
          "type": "DOC",
          "n": "ヒアリング議事メモ×3部門",
          "st": "1/3 完了",
          "due": "9/12"
        },
        {
          "type": "PPT",
          "n": "現状業務の課題サマリー",
          "st": "未着手",
          "due": "9/19"
        }
      ],
      "ms": [
        {
          "name": "全部門の日程確定",
          "due": "9/5"
        },
        {
          "name": "実施・分析メモ",
          "due": "9/12"
        }
      ],
      "tasks": [
        {
          "t": "営業部門の候補日 取得依頼",
          "done": false,
          "due": "9/2",
          "side": "us",
          "owner": "佐藤",
          "ms": 0
        },
        {
          "t": "営業部門の候補日 回答",
          "done": false,
          "due": "8/29",
          "side": "cl",
          "owner": "伊藤氏",
          "ms": 0
        },
        {
          "t": "情シス部門の日程確定",
          "done": false,
          "due": "9/5",
          "side": "cl",
          "owner": "山本部長",
          "ms": 0
        },
        {
          "t": "経理部ヒアリング実施",
          "done": true,
          "due": "8/18",
          "side": "us",
          "owner": "佐藤",
          "ms": 1
        },
        {
          "t": "ヒアリング実施・分析メモ作成",
          "done": false,
          "due": "9/12",
          "side": "us",
          "owner": "佐藤",
          "ms": 1
        }
      ],
      "notes": [
        [
          "f",
          "営業部門から候補日の回答なし(8/29時点)",
          "8/29 ルーティン会議の議事録"
        ],
        [
          "f",
          "経理部ヒアリングは8/18に実施済",
          "実施記録"
        ],
        [
          "j",
          "伊藤氏経由の調整が最短。直接依頼は現場の警戒感を高める",
          "佐藤 8/29"
        ],
        [
          "r",
          "9月第2週を逃すと現状分析の開始に影響",
          "佐藤 8/29"
        ]
      ],
      "rels": [
        [
          "ppl",
          "伊藤氏"
        ],
        [
          "ppl",
          "佐々木氏"
        ],
        [
          "ppl",
          "山本部長"
        ],
        [
          "dec",
          "DEC-05",
          "DEC-05 対象は3部門に限定"
        ],
        [
          "mtg",
          "8/18 現場ヒアリング(経理部)"
        ],
        [
          "mtg",
          "8/29 週次ルーティン(第8回)"
        ]
      ],
      "aiLabel": "✦ AI解読済 · 最終同期 8/29"
    },
    {
      "id": "ISS-09",
      "name": "組織図の鮮度",
      "title": "受領した組織図が最新版でない可能性",
      "prio": "中",
      "goal": "最新の組織体制を確定し、体制図・人物マップに反映する",
      "crit": [
        "7月改編を反映した組織図を受領・確認済",
        "体制図と登場人物マップが最新化済"
      ],
      "deliv": [
        {
          "type": "PDF",
          "n": "最新組織図(7月改編版)",
          "st": "先方待ち",
          "due": "9/12"
        },
        {
          "type": "PPT",
          "n": "プロジェクト体制図 v2",
          "st": "未着手",
          "due": "9/19"
        }
      ],
      "ms": [
        {
          "name": "最新版の入手",
          "due": "9/12"
        },
        {
          "name": "体制図・人物マップ反映",
          "due": "9/19"
        }
      ],
      "tasks": [
        {
          "t": "受領版(4月版)と公開情報の差分確認",
          "done": true,
          "due": "8/24",
          "side": "us",
          "owner": "高橋",
          "ms": 0
        },
        {
          "t": "7月改編版の有無を確認依頼",
          "done": false,
          "due": "9/4",
          "side": "us",
          "owner": "高橋",
          "ms": 0
        },
        {
          "t": "最新組織図の提供",
          "done": false,
          "due": "9/12",
          "side": "cl",
          "owner": "高木氏",
          "ms": 0
        },
        {
          "t": "登場人物マップへ反映",
          "done": false,
          "due": "9/19",
          "side": "us",
          "owner": "高橋",
          "ms": 1
        }
      ],
      "notes": [
        [
          "f",
          "受領版は2026年4月版。7月に組織改編があった旨の言及が8/22議事録にあり",
          "8/22 ルーティン会議の議事録"
        ],
        [
          "j",
          "現体制と乖離した分析は手戻りリスク大。最新版確認を優先すべき",
          "高橋 8/24"
        ],
        [
          "q",
          "改編が軽微なら4月版のまま進める選択肢もあるか",
          "高橋 8/24"
        ]
      ],
      "rels": [
        [
          "doc",
          "組織図_2026年4月版.pdf"
        ],
        [
          "ppl",
          "高木氏"
        ]
      ],
      "aiLabel": "✦ AI解読済 · 最終同期 8/24"
    },
    {
      "id": "ISS-11",
      "name": "KPI定義の合意",
      "title": "KPI定義の合意が部門間で取れていない",
      "prio": "中",
      "goal": "営業・経営企画間でKPI定義書v1に合意する",
      "crit": [
        "KPI定義書v1に営業・経営企画の両部門が合意",
        "KPIツリー現行版へ反映済"
      ],
      "deliv": [
        {
          "type": "XLS",
          "n": "KPI定義 差分比較表",
          "st": "作成中",
          "due": "9/10"
        },
        {
          "type": "DOC",
          "n": "KPI定義書 v1",
          "st": "未着手",
          "due": "9/26"
        }
      ],
      "ms": [
        {
          "name": "差分の見える化",
          "due": "9/10"
        },
        {
          "name": "KPI定義書v1の合意",
          "due": "9/26"
        }
      ],
      "tasks": [
        {
          "t": "両部門の現行定義をヒアリング",
          "done": true,
          "due": "8/20",
          "side": "us",
          "owner": "田中",
          "ms": 0
        },
        {
          "t": "業務フロー記述書から定義箇所を抽出",
          "done": true,
          "due": "8/26",
          "side": "us",
          "owner": "田中",
          "ms": 0
        },
        {
          "t": "定義差分の比較表を9/10ルーティンに提出",
          "done": false,
          "due": "9/10",
          "side": "us",
          "owner": "田中",
          "ms": 0
        },
        {
          "t": "比較表の両部門レビュー",
          "done": false,
          "due": "9/19",
          "side": "cl",
          "owner": "伊藤氏・原氏",
          "ms": 1
        },
        {
          "t": "KPI定義書v1の合意",
          "done": false,
          "due": "9/26",
          "side": "us",
          "owner": "田中",
          "ms": 1
        }
      ],
      "notes": [
        [
          "f",
          "「受注率」の定義が営業(引合ベース)と経営企画(商談ベース)で相違",
          "8/20 両部門ヒアリング"
        ],
        [
          "j",
          "定義統一はKPIツリー全体に波及。差分比較表の提示が合意への近道",
          "田中 8/26"
        ],
        [
          "r",
          "部門間の対立に発展すると9月中の合意が困難",
          "田中 8/26"
        ]
      ],
      "rels": [
        [
          "doc",
          "現行業務フロー記述書(営業).docx"
        ],
        [
          "ppl",
          "伊藤氏"
        ],
        [
          "ppl",
          "鈴木常務"
        ],
        [
          "dec",
          "DEC-02",
          "DEC-02 KPIは中計の重点3領域に対応"
        ]
      ],
      "aiLabel": "✦ AI解読済 · 最終同期 8/26"
    },
    {
      "id": "ISS-12",
      "name": "推進体制",
      "title": "10月以降のA社側推進体制が未確定",
      "prio": "低",
      "goal": "10月以降のA社側推進担当のアサインを確定する",
      "crit": [
        "A社側推進担当(専任1名+兼任2名)のアサインが確定",
        "体制図v2が経営会議で承認済"
      ],
      "deliv": [
        {
          "type": "PPT",
          "n": "実行フェーズ体制図 v2",
          "st": "未着手",
          "due": "10/3"
        }
      ],
      "ms": [
        {
          "name": "候補者の合意",
          "due": "9/26"
        },
        {
          "name": "体制図v2",
          "due": "10/3"
        }
      ],
      "tasks": [
        {
          "t": "鈴木常務との個別相談を設定",
          "done": false,
          "due": "9月中旬",
          "side": "us",
          "owner": "佐藤",
          "ms": 0
        },
        {
          "t": "候補者リストの提示",
          "done": false,
          "due": "9/26",
          "side": "cl",
          "owner": "鈴木常務",
          "ms": 0
        },
        {
          "t": "体制図v2の合意",
          "done": false,
          "due": "10/3",
          "side": "us",
          "owner": "佐藤",
          "ms": 1
        }
      ],
      "notes": [
        [
          "f",
          "キックオフ資料に実行フェーズ体制は「別途検討」と記載。以降の言及なし",
          "8/8 キックオフ資料"
        ],
        [
          "j",
          "アサインには鈴木常務の意向が強く働く見込み。個別相談が有効",
          "佐藤 8/25"
        ]
      ],
      "rels": [
        [
          "ppl",
          "鈴木常務"
        ],
        [
          "mtg",
          "8/8 プロジェクトキックオフ"
        ]
      ],
      "aiLabel": "✦ AI解読済 · 最終同期 8/8"
    },
    {
      "id": "ISS-13",
      "name": "セキュリティ審査の長期化",
      "title": "セキュリティ審査の長期化",
      "prio": "高",
      "goal": "A社セキュリティ審査を9月中に通過し、検証環境の利用を開始する",
      "crit": [],
      "deliv": [],
      "ms": [
        {
          "name": "初動対応",
          "due": "9/19"
        }
      ],
      "tasks": [
        {
          "t": "審査質問票の回答ドラフト提出",
          "done": false,
          "due": "9/5",
          "side": "us",
          "owner": "田中",
          "ms": 0
        }
      ],
      "notes": [
        [
          "f",
          "関連する事実をAIが議事録・受領資料から抽出済み。詳細は元資料を参照",
          "AI集約"
        ],
        [
          "j",
          "担当者の判断・仮説は未記載",
          "—"
        ]
      ],
      "rels": [],
      "aiLabel": "✦ AI解読済 · 8/29"
    },
    {
      "id": "ISS-14",
      "name": "予算超過リスク",
      "title": "予算超過リスク",
      "prio": "高",
      "goal": "追加スコープの予算影響を可視化し、10月の契約更新前に合意する",
      "crit": [],
      "deliv": [],
      "ms": [
        {
          "name": "初動対応",
          "due": "9/30"
        }
      ],
      "tasks": [
        {
          "t": "変更管理表を鈴木常務と確認",
          "done": false,
          "due": "9/17",
          "side": "us",
          "owner": "佐藤",
          "ms": 0
        }
      ],
      "notes": [
        [
          "f",
          "関連する事実をAIが議事録・受領資料から抽出済み。詳細は元資料を参照",
          "AI集約"
        ],
        [
          "j",
          "担当者の判断・仮説は未記載",
          "—"
        ]
      ],
      "rels": [],
      "aiLabel": "✦ AI解読済 · 8/29"
    },
    {
      "id": "ISS-15",
      "name": "個人情報の取扱範囲",
      "title": "個人情報の取扱範囲",
      "prio": "高",
      "goal": "個人情報を含むデータの取扱範囲をNDA別紙として確定する",
      "crit": [],
      "deliv": [],
      "ms": [
        {
          "name": "初動対応",
          "due": "9/12"
        }
      ],
      "tasks": [
        {
          "t": "法務レビュー結果の反映",
          "done": false,
          "due": "9/9",
          "side": "us",
          "owner": "高橋",
          "ms": 0
        }
      ],
      "notes": [
        [
          "f",
          "関連する事実をAIが議事録・受領資料から抽出済み。詳細は元資料を参照",
          "AI集約"
        ],
        [
          "j",
          "担当者の判断・仮説は未記載",
          "—"
        ]
      ],
      "rels": [],
      "aiLabel": "✦ AI解読済 · 8/29"
    },
    {
      "id": "ISS-16",
      "name": "経営会議の報告形式",
      "title": "経営会議の報告形式",
      "prio": "中",
      "goal": "月次の経営報告フォーマットを確定し、9月末報告から適用する",
      "crit": [],
      "deliv": [],
      "ms": [
        {
          "name": "初動対応",
          "due": "9/25"
        }
      ],
      "tasks": [
        {
          "t": "報告書ドラフトのレビュー",
          "done": false,
          "due": "9/18",
          "side": "us",
          "owner": "田中",
          "ms": 0
        }
      ],
      "notes": [
        [
          "f",
          "関連資料の解読待ち。取込後にAIが事実を抽出します",
          "AI"
        ]
      ],
      "rels": [],
      "aiLabel": "✦ AI解読中 · 関連資料待ち"
    },
    {
      "id": "ISS-17",
      "name": "データ辞書の不在",
      "title": "データ辞書の不在",
      "prio": "中",
      "goal": "主要テーブルのデータ辞書v1を整備する",
      "crit": [],
      "deliv": [],
      "ms": [
        {
          "name": "初動対応",
          "due": "10/10"
        }
      ],
      "tasks": [
        {
          "t": "対象テーブルの優先順位付け",
          "done": false,
          "due": "9/12",
          "side": "us",
          "owner": "佐藤",
          "ms": 0
        }
      ],
      "notes": [
        [
          "f",
          "関連する事実をAIが議事録・受領資料から抽出済み。詳細は元資料を参照",
          "AI集約"
        ],
        [
          "j",
          "担当者の判断・仮説は未記載",
          "—"
        ]
      ],
      "rels": [],
      "aiLabel": "✦ AI解読済 · 8/29"
    },
    {
      "id": "ISS-18",
      "name": "現場の協力度ばらつき",
      "title": "現場の協力度ばらつき",
      "prio": "中",
      "goal": "部門ごとの温度差を把握し、巻き込み策をルーティンで合意する",
      "crit": [],
      "deliv": [],
      "ms": [
        {
          "name": "初動対応",
          "due": "9/30"
        }
      ],
      "tasks": [
        {
          "t": "部門別ヒアリング所感の整理",
          "done": false,
          "due": "9/16",
          "side": "us",
          "owner": "高橋",
          "ms": 0
        }
      ],
      "notes": [
        [
          "f",
          "関連する事実をAIが議事録・受領資料から抽出済み。詳細は元資料を参照",
          "AI集約"
        ],
        [
          "j",
          "担当者の判断・仮説は未記載",
          "—"
        ]
      ],
      "rels": [],
      "aiLabel": "✦ AI解読済 · 8/29"
    },
    {
      "id": "ISS-19",
      "name": "ベンダー契約の更新時期",
      "title": "ベンダー契約の更新時期",
      "prio": "中",
      "goal": "既存ベンダー契約の更新条件を整理し、方針を提示する",
      "crit": [],
      "deliv": [],
      "ms": [
        {
          "name": "初動対応",
          "due": "10/17"
        }
      ],
      "tasks": [
        {
          "t": "契約一覧の受領依頼",
          "done": false,
          "due": "9/10",
          "side": "us",
          "owner": "田中",
          "ms": 0
        }
      ],
      "notes": [
        [
          "f",
          "関連する事実をAIが議事録・受領資料から抽出済み。詳細は元資料を参照",
          "AI集約"
        ],
        [
          "j",
          "担当者の判断・仮説は未記載",
          "—"
        ]
      ],
      "rels": [],
      "aiLabel": "✦ AI解読済 · 8/29"
    },
    {
      "id": "ISS-20",
      "name": "PoC環境の調達",
      "title": "PoC環境の調達",
      "prio": "中",
      "goal": "PoC用クラウド環境の調達ルートと予算を確定する",
      "crit": [],
      "deliv": [],
      "ms": [
        {
          "name": "初動対応",
          "due": "10/3"
        }
      ],
      "tasks": [
        {
          "t": "情シスへ構成案を提示",
          "done": false,
          "due": "9/19",
          "side": "us",
          "owner": "佐藤",
          "ms": 0
        }
      ],
      "notes": [
        [
          "f",
          "関連する事実をAIが議事録・受領資料から抽出済み。詳細は元資料を参照",
          "AI集約"
        ],
        [
          "j",
          "担当者の判断・仮説は未記載",
          "—"
        ]
      ],
      "rels": [],
      "aiLabel": "✦ AI解読済 · 8/29"
    },
    {
      "id": "ISS-21",
      "name": "用語定義の不統一",
      "title": "用語定義の不統一",
      "prio": "中",
      "goal": "部門間で異なる用語の対訳表を作成する",
      "crit": [],
      "deliv": [],
      "ms": [
        {
          "name": "初動対応",
          "due": "10/10"
        }
      ],
      "tasks": [
        {
          "t": "頻出用語の洗い出し",
          "done": false,
          "due": "9/24",
          "side": "us",
          "owner": "高橋",
          "ms": 0
        }
      ],
      "notes": [
        [
          "f",
          "関連資料の解読待ち。取込後にAIが事実を抽出します",
          "AI"
        ]
      ],
      "rels": [],
      "aiLabel": "✦ AI解読中 · 関連資料待ち"
    },
    {
      "id": "ISS-22",
      "name": "過去施策の失敗要因分析",
      "title": "過去施策の失敗要因分析",
      "prio": "中",
      "goal": "過去のDX施策の失敗要因を整理し、計画に反映する",
      "crit": [],
      "deliv": [],
      "ms": [
        {
          "name": "初動対応",
          "due": "10/24"
        }
      ],
      "tasks": [
        {
          "t": "関連資料の受領依頼",
          "done": false,
          "due": "9/26",
          "side": "us",
          "owner": "田中",
          "ms": 0
        }
      ],
      "notes": [
        [
          "f",
          "関連する事実をAIが議事録・受領資料から抽出済み。詳細は元資料を参照",
          "AI集約"
        ],
        [
          "j",
          "担当者の判断・仮説は未記載",
          "—"
        ]
      ],
      "rels": [],
      "aiLabel": "✦ AI解読済 · 8/29"
    },
    {
      "id": "ISS-23",
      "name": "レガシー帳票の棚卸し",
      "title": "レガシー帳票の棚卸し",
      "prio": "低",
      "goal": "紙・Excel帳票の棚卸しリストを作成する",
      "crit": [],
      "deliv": [],
      "ms": [
        {
          "name": "初動対応",
          "due": "10/31"
        }
      ],
      "tasks": [
        {
          "t": "対象部門の確定",
          "done": false,
          "due": "10/2",
          "side": "us",
          "owner": "佐藤",
          "ms": 0
        }
      ],
      "notes": [
        [
          "f",
          "関連する事実をAIが議事録・受領資料から抽出済み。詳細は元資料を参照",
          "AI集約"
        ],
        [
          "j",
          "担当者の判断・仮説は未記載",
          "—"
        ]
      ],
      "rels": [],
      "aiLabel": "✦ AI解読済 · 8/29"
    },
    {
      "id": "ISS-24",
      "name": "会議体の重複",
      "title": "会議体の重複",
      "prio": "低",
      "goal": "重複する会議体を整理し、統合案を提示する",
      "crit": [],
      "deliv": [],
      "ms": [
        {
          "name": "初動対応",
          "due": "10/17"
        }
      ],
      "tasks": [
        {
          "t": "会議体一覧の作成",
          "done": false,
          "due": "9/30",
          "side": "us",
          "owner": "高橋",
          "ms": 0
        }
      ],
      "notes": [
        [
          "f",
          "関連資料の解読待ち。取込後にAIが事実を抽出します",
          "AI"
        ]
      ],
      "rels": [],
      "aiLabel": "✦ AI解読中 · 関連資料待ち"
    },
    {
      "id": "ISS-25",
      "name": "海外拠点の巻き込み",
      "title": "海外拠点の巻き込み",
      "prio": "低",
      "goal": "海外2拠点への展開前提を整理する",
      "crit": [],
      "deliv": [],
      "ms": [
        {
          "name": "初動対応",
          "due": "11/13"
        }
      ],
      "tasks": [
        {
          "t": "拠点責任者の特定",
          "done": false,
          "due": "10/9",
          "side": "us",
          "owner": "田中",
          "ms": 0
        }
      ],
      "notes": [
        [
          "f",
          "関連する事実をAIが議事録・受領資料から抽出済み。詳細は元資料を参照",
          "AI集約"
        ],
        [
          "j",
          "担当者の判断・仮説は未記載",
          "—"
        ]
      ],
      "rels": [],
      "aiLabel": "✦ AI解読済 · 8/29"
    },
    {
      "id": "ISS-26",
      "name": "教育計画の未着手",
      "title": "教育計画の未着手",
      "prio": "低",
      "goal": "実行フェーズ向け教育計画の骨子を作成する",
      "crit": [],
      "deliv": [],
      "ms": [
        {
          "name": "初動対応",
          "due": "11/27"
        }
      ],
      "tasks": [
        {
          "t": "研修ベンダー候補の整理",
          "done": false,
          "due": "10/16",
          "side": "us",
          "owner": "佐藤",
          "ms": 0
        }
      ],
      "notes": [
        [
          "f",
          "関連資料の解読待ち。取込後にAIが事実を抽出します",
          "AI"
        ]
      ],
      "rels": [],
      "aiLabel": "✦ AI解読中 · 関連資料待ち"
    },
    {
      "id": "ISS-27",
      "name": "ツール標準の不在",
      "title": "ツール標準の不在",
      "prio": "低",
      "goal": "部門で乱立するツールの標準化方針を策定する",
      "crit": [],
      "deliv": [],
      "ms": [
        {
          "name": "初動対応",
          "due": "11/13"
        }
      ],
      "tasks": [
        {
          "t": "利用ツールの棚卸し",
          "done": false,
          "due": "10/7",
          "side": "us",
          "owner": "高橋",
          "ms": 0
        }
      ],
      "notes": [
        [
          "f",
          "関連する事実をAIが議事録・受領資料から抽出済み。詳細は元資料を参照",
          "AI集約"
        ],
        [
          "j",
          "担当者の判断・仮説は未記載",
          "—"
        ]
      ],
      "rels": [],
      "aiLabel": "✦ AI解読済 · 8/29"
    }
  ],
  "docs": [
    {
      "group": "今週の受領(8/25〜)",
      "name": "売上データ抽出_2024-2026.xlsx",
      "ext": "XLS",
      "date": "8/28",
      "from": "小林氏(情シス)",
      "relIssue": "ISS-04",
      "status": "未確認",
      "ai": "解読中"
    },
    {
      "group": "今週の受領(8/25〜)",
      "name": "顧客マスタ抽出.xlsx",
      "ext": "XLS",
      "date": "8/28",
      "from": "小林氏(情シス)",
      "relIssue": "ISS-04",
      "status": "未確認",
      "ai": "解読中"
    },
    {
      "group": "今週の受領(8/25〜)",
      "name": "システム構成一覧.pdf",
      "ext": "PDF",
      "date": "8/26",
      "from": "山本部長(情シス)",
      "relIssue": "ISS-04",
      "status": "確認済",
      "ai": "解読済"
    },
    {
      "group": "今週の受領(8/25〜)",
      "name": "議事録_0822ルーティン.docx",
      "ext": "DOC",
      "date": "8/26",
      "from": "当社作成",
      "relIssue": null,
      "status": "確認済",
      "ai": "解読済"
    },
    {
      "group": "今週の受領(8/25〜)",
      "name": "中期経営計画(社内向け抜粋).pptx",
      "ext": "PPT",
      "date": "8/25",
      "from": "鈴木常務(経営企画)",
      "relIssue": null,
      "status": "確認済",
      "ai": "解読済"
    },
    {
      "group": "今週の受領(8/25〜)",
      "name": "IT予算実績_FY25.xlsx",
      "ext": "XLS",
      "date": "8/25",
      "from": "経理部 佐々木氏",
      "relIssue": "ISS-14",
      "status": "確認済",
      "ai": "解読済"
    },
    {
      "group": "8月中旬",
      "name": "組織図_2026年4月版.pdf",
      "ext": "PDF",
      "date": "8/21",
      "from": "人事部 高木氏",
      "relIssue": "ISS-09",
      "status": "差戻し",
      "ai": "旧版"
    },
    {
      "group": "8月中旬",
      "name": "部門別コスト実績_FY25.xlsx",
      "ext": "XLS",
      "date": "8/19",
      "from": "経理部 佐々木氏",
      "relIssue": null,
      "status": "確認済",
      "ai": "解読済"
    },
    {
      "group": "8月中旬",
      "name": "販売チャネル別実績.xlsx",
      "ext": "XLS",
      "date": "8/19",
      "from": "営業企画 伊藤氏",
      "relIssue": "ISS-11",
      "status": "差戻し",
      "ai": "解読済"
    },
    {
      "group": "8月中旬",
      "name": "ヒアリングメモ_経理部.docx",
      "ext": "DOC",
      "date": "8/18",
      "from": "当社作成",
      "relIssue": null,
      "status": "確認済",
      "ai": "解読済"
    },
    {
      "group": "8月中旬",
      "name": "業務システム利用状況調査.xlsx",
      "ext": "XLS",
      "date": "8/17",
      "from": "情シス 森氏",
      "relIssue": null,
      "status": "確認済",
      "ai": "解読済"
    },
    {
      "group": "8月中旬",
      "name": "現行業務フロー記述書(営業).docx",
      "ext": "DOC",
      "date": "8/15",
      "from": "営業企画 伊藤氏",
      "relIssue": "ISS-11",
      "status": "確認済",
      "ai": "解読済"
    },
    {
      "group": "8月中旬",
      "name": "現行業務フロー記述書(経理).docx",
      "ext": "DOC",
      "date": "8/15",
      "from": "経理部 佐々木氏",
      "relIssue": null,
      "status": "確認済",
      "ai": "解読済"
    },
    {
      "group": "8月中旬",
      "name": "過年度監査指摘事項.pdf",
      "ext": "PDF",
      "date": "8/14",
      "from": "総務部 青木氏",
      "relIssue": "ISS-13",
      "status": "確認済",
      "ai": "解読済"
    },
    {
      "group": "8月中旬",
      "name": "セキュリティチェックリスト.xlsx",
      "ext": "XLS",
      "date": "8/13",
      "from": "情シス 森氏",
      "relIssue": "ISS-13",
      "status": "未確認",
      "ai": "解読中"
    },
    {
      "group": "8月中旬",
      "name": "情報セキュリティ規程 v3.2.pdf",
      "ext": "PDF",
      "date": "8/12",
      "from": "総務部 青木氏",
      "relIssue": "ISS-13",
      "status": "確認済",
      "ai": "解読済"
    },
    {
      "group": "8月上旬",
      "name": "DX推進 キックオフ資料.pptx",
      "ext": "PPT",
      "date": "8/8",
      "from": "鈴木常務(経営企画)",
      "relIssue": null,
      "status": "確認済",
      "ai": "解読済"
    },
    {
      "group": "8月上旬",
      "name": "全社KPIツリー現行版.pptx",
      "ext": "PPT",
      "date": "8/7",
      "from": "経営企画 原氏",
      "relIssue": "ISS-11",
      "status": "確認済",
      "ai": "解読済"
    },
    {
      "group": "8月上旬",
      "name": "経営会議資料_7月度.pdf",
      "ext": "PDF",
      "date": "8/6",
      "from": "経営企画 原氏",
      "relIssue": null,
      "status": "確認済",
      "ai": "解読済"
    },
    {
      "group": "8月上旬",
      "name": "人員一覧_部門別.xlsx",
      "ext": "XLS",
      "date": "8/5",
      "from": "人事部 高木氏",
      "relIssue": "ISS-09",
      "status": "差戻し",
      "ai": "旧版"
    },
    {
      "group": "8月上旬",
      "name": "NDA締結書面.pdf",
      "ext": "PDF",
      "date": "8/5",
      "from": "総務部 青木氏",
      "relIssue": null,
      "status": "確認済",
      "ai": "解読済"
    },
    {
      "group": "8月上旬",
      "name": "ベンダー契約一覧.xlsx",
      "ext": "XLS",
      "date": "8/4",
      "from": "情シス 森氏",
      "relIssue": "ISS-14",
      "status": "未確認",
      "ai": "解読中"
    },
    {
      "group": "8月上旬",
      "name": "グループ会社一覧.pdf",
      "ext": "PDF",
      "date": "8/4",
      "from": "経営企画 原氏",
      "relIssue": null,
      "status": "確認済",
      "ai": "解読済"
    },
    {
      "group": "8月上旬",
      "name": "IT中期ロードマップ2024版.pptx",
      "ext": "PPT",
      "date": "8/1",
      "from": "情シス 山本部長",
      "relIssue": null,
      "status": "確認済",
      "ai": "解読済"
    },
    {
      "group": "7月以前",
      "name": "提案依頼書(RFP).pdf",
      "ext": "PDF",
      "date": "7/28",
      "from": "経営企画 原氏",
      "relIssue": null,
      "status": "確認済",
      "ai": "解読済"
    },
    {
      "group": "7月以前",
      "name": "過去DX施策振り返り資料.pptx",
      "ext": "PPT",
      "date": "7/24",
      "from": "経営企画 原氏",
      "relIssue": null,
      "status": "確認済",
      "ai": "解読済"
    },
    {
      "group": "7月以前",
      "name": "旧システム刷新PJ報告書.pdf",
      "ext": "PDF",
      "date": "7/22",
      "from": "情シス 山本部長",
      "relIssue": null,
      "status": "確認済",
      "ai": "解読済"
    },
    {
      "group": "7月以前",
      "name": "財務諸表_直近3期.pdf",
      "ext": "PDF",
      "date": "7/18",
      "from": "経理部 佐々木氏",
      "relIssue": null,
      "status": "確認済",
      "ai": "解読済"
    },
    {
      "group": "7月以前",
      "name": "中期経営計画(公開版).pdf",
      "ext": "PDF",
      "date": "7/15",
      "from": "経営企画 原氏",
      "relIssue": null,
      "status": "確認済",
      "ai": "解読済"
    },
    {
      "group": "7月以前",
      "name": "会社案内・組織概要.pdf",
      "ext": "PDF",
      "date": "7/15",
      "from": "総務部 青木氏",
      "relIssue": null,
      "status": "確認済",
      "ai": "解読済"
    },
    {
      "group": "7月以前",
      "name": "業界動向レポート(社内共有版).pdf",
      "ext": "PDF",
      "date": "7/10",
      "from": "経営企画 原氏",
      "relIssue": null,
      "status": "確認済",
      "ai": "解読済"
    },
    {
      "group": "7月以前",
      "name": "前回コンサル最終報告書.pptx",
      "ext": "PPT",
      "date": "7/8",
      "from": "経営企画 原氏",
      "relIssue": null,
      "status": "確認済",
      "ai": "解読済"
    },
    {
      "group": "7月以前",
      "name": "契約書・SOW.pdf",
      "ext": "PDF",
      "date": "7/5",
      "from": "当社法務",
      "relIssue": null,
      "status": "確認済",
      "ai": "解読済"
    },
    {
      "group": "7月以前",
      "name": "キックオフ準備メモ.docx",
      "ext": "DOC",
      "date": "7/3",
      "from": "当社作成",
      "relIssue": null,
      "status": "確認済",
      "ai": "解読済"
    }
  ],
  "people": [
    {
      "group": "経営・経営企画",
      "ini": "鈴",
      "name": "鈴木常務",
      "role": "経営企画 · スポンサー",
      "stance": "協力的",
      "isKey": true,
      "note": "本PJの発案者。経営会議への報告ラインを握る。",
      "links": "資料3 · 会議12 · 決定4",
      "lastContact": "8/29 ルーティン",
      "color": "#e4dcd8",
      "org": "cl"
    },
    {
      "group": "経営・経営企画",
      "ini": "木",
      "name": "木村社長",
      "role": "代表取締役 · 最終決裁者",
      "stance": "中立",
      "isKey": false,
      "note": "月次経営会議でのみ関与。ROIへの関心が強い。",
      "links": "会議1",
      "lastContact": "7/8 プレゼン",
      "color": "#dde0e4",
      "org": "cl"
    },
    {
      "group": "経営・経営企画",
      "ini": "原",
      "name": "原氏",
      "role": "経営企画 · PMO窓口",
      "stance": "協力的",
      "isKey": false,
      "note": "日程調整・資料集約のハブ。レスポンスが早い。",
      "links": "資料8 · 会議9",
      "lastContact": "8/29 ルーティン",
      "color": "#dce4e0",
      "org": "cl"
    },
    {
      "group": "情報システム部",
      "ini": "山",
      "name": "山本部長",
      "role": "情報システム部 · 意思決定者",
      "stance": "協力的",
      "isKey": true,
      "note": "データ提供の承認権限。段取りの事前共有を好む。",
      "links": "課題2 · 資料5 · 会議8",
      "lastContact": "8/29 ルーティン",
      "color": "#dde4d8",
      "org": "cl"
    },
    {
      "group": "情報システム部",
      "ini": "小",
      "name": "小林氏",
      "role": "情報システム部 · データ管理担当",
      "stance": "多忙",
      "isKey": true,
      "note": "データ抽出の実務担当。依頼はまとめて出すのが有効。",
      "links": "課題1 · 資料7",
      "lastContact": "8/28 資料受領",
      "color": "#d8dde4",
      "org": "cl"
    },
    {
      "group": "情報システム部",
      "ini": "森",
      "name": "森氏",
      "role": "情報システム部 · インフラ担当",
      "stance": "中立",
      "isKey": false,
      "note": "検証環境・アカウント発行の実務担当。",
      "links": "資料3 · 会議2",
      "lastContact": "8/27 申請対応",
      "color": "#e0e4dd",
      "org": "cl"
    },
    {
      "group": "営業・現場部門",
      "ini": "伊",
      "name": "伊藤氏",
      "role": "営業企画 · 現場キーパーソン",
      "stance": "慎重",
      "isKey": true,
      "note": "現場の信頼が厚い。ヒアリング調整の要。変化への警戒感あり。",
      "links": "課題2 · 資料2 · 会議4",
      "lastContact": "8/22 ルーティン",
      "color": "#e4e0d4",
      "org": "cl"
    },
    {
      "group": "営業・現場部門",
      "ini": "渡",
      "name": "渡辺部長",
      "role": "営業部 · 部門長",
      "stance": "慎重",
      "isKey": true,
      "note": "ヒアリング日程の承認者。現場負荷を懸念。",
      "links": "課題1 · 会議1",
      "lastContact": "8/22 ルーティン",
      "color": "#e4d8d8",
      "org": "cl"
    },
    {
      "group": "営業・現場部門",
      "ini": "加",
      "name": "加藤氏",
      "role": "店舗運営 · 現場代表",
      "stance": "中立",
      "isKey": false,
      "note": "店舗側の業務実態に詳しい。ヒアリング候補。",
      "links": "会議1",
      "lastContact": "8/18 ヒアリング",
      "color": "#d8e4e0",
      "org": "cl"
    },
    {
      "group": "管理部門",
      "ini": "高",
      "name": "高木氏",
      "role": "人事部 · 資料提供窓口",
      "stance": "中立",
      "isKey": false,
      "note": "組織図・人員データの窓口。回答に時間がかかる傾向。",
      "links": "課題1 · 資料2",
      "lastContact": "8/21 資料受領",
      "color": "#dce4e0",
      "org": "cl"
    },
    {
      "group": "管理部門",
      "ini": "佐",
      "name": "佐々木氏",
      "role": "経理部 · コストデータ担当",
      "stance": "協力的",
      "isKey": false,
      "note": "コスト実績の提供元。粒度の相談がしやすい。",
      "links": "資料4 · 会議2",
      "lastContact": "8/19 資料受領",
      "color": "#e0dce4",
      "org": "cl"
    },
    {
      "group": "管理部門",
      "ini": "青",
      "name": "青木氏",
      "role": "総務部 · セキュリティ・契約窓口",
      "stance": "中立",
      "isKey": false,
      "note": "NDA・入館・規程類の窓口。審査プロセスを主管。",
      "links": "資料4 · 会議2",
      "lastContact": "8/13 審査KO",
      "color": "#d8e0e4",
      "org": "cl"
    },
    {
      "group": "当社チーム",
      "ini": "田",
      "name": "田中",
      "role": "当社 · PM",
      "stance": "当社",
      "isKey": false,
      "note": "全体統括。データ品質・KPI定義の課題を担当。",
      "links": "課題2 · タスク8",
      "lastContact": "8/29 ルーティン",
      "color": "#dde0e4",
      "org": "us"
    },
    {
      "group": "当社チーム",
      "ini": "佐",
      "name": "佐藤",
      "role": "当社 · コンサルタント",
      "stance": "当社",
      "isKey": false,
      "note": "ヒアリング・体制まわりを担当。",
      "links": "課題2 · タスク6",
      "lastContact": "8/29 ルーティン",
      "color": "#e0dde4",
      "org": "us"
    },
    {
      "group": "当社チーム",
      "ini": "高",
      "name": "高橋",
      "role": "当社 · アナリスト",
      "stance": "当社",
      "isKey": false,
      "note": "データ分析・組織図まわりを担当。",
      "links": "課題1 · タスク4",
      "lastContact": "8/28 分析作業",
      "color": "#dde4e0",
      "org": "us"
    }
  ],
  "meetings": [
    {
      "group": "8月下旬",
      "title": "8/29 週次ルーティン(第8回)",
      "type": "r",
      "attendees": "山本部長, 小林氏, 田中, 佐藤",
      "summary": "クレンジング分担案を提示、A社側は概ね同意。営業ヒアリングは伊藤氏経由で再調整へ。",
      "aiImpact": "課題2 · タスク1 · 完了3",
      "ingested": true
    },
    {
      "group": "8月下旬",
      "title": "8/28 データ抽出 依頼打合せ",
      "type": "i",
      "attendees": "小林氏, 田中",
      "summary": "追加抽出2件を依頼。顧客マスタは8/28受領、売上データと合わせ解読中。",
      "aiImpact": "資料2",
      "ingested": false
    },
    {
      "group": "8月下旬",
      "title": "8/26 データ品質 個別打合せ",
      "type": "i",
      "attendees": "小林氏, 田中",
      "summary": "欠損の発生源は旧システムからの移行データと判明。システム構成一覧を受領。",
      "aiImpact": "資料1 · 課題1",
      "ingested": true
    },
    {
      "group": "8月下旬",
      "title": "8/25 経営報告 準備会",
      "type": "e",
      "attendees": "鈴木常務, 原氏, 田中",
      "summary": "9月経営会議の報告骨子を確認。データ品質課題の扱いを事前共有。",
      "aiImpact": "タスク1",
      "ingested": true
    },
    {
      "group": "8月下旬",
      "title": "8/22 週次ルーティン(第7回)",
      "type": "r",
      "attendees": "鈴木常務, 山本部長, 田中, 佐藤",
      "summary": "データクレンジングのスコープを協議し、A社側一次対応で合意(DEC-06)。",
      "aiImpact": "決定1 · 課題1",
      "ingested": true
    },
    {
      "group": "8月中旬",
      "title": "8/20 KPI定義ヒアリング(経営企画)",
      "type": "i",
      "attendees": "原氏, 田中",
      "summary": "「受注率」は商談ベースで運用。KPIツリーの整合を確認。",
      "aiImpact": "課題1",
      "ingested": true
    },
    {
      "group": "8月中旬",
      "title": "8/20 KPI定義ヒアリング(営業)",
      "type": "i",
      "attendees": "伊藤氏, 田中",
      "summary": "「受注率」は引合ベースで運用。経営企画と定義が相違。",
      "aiImpact": "課題1起票",
      "ingested": true
    },
    {
      "group": "8月中旬",
      "title": "8/18 現場ヒアリング(経理部)",
      "type": "i",
      "attendees": "佐々木氏, 佐藤",
      "summary": "月次締めプロセスの手作業ポイントを確認。コスト実績データの提供を依頼。",
      "aiImpact": "人物1 · 資料依頼1",
      "ingested": true
    },
    {
      "group": "8月中旬",
      "title": "8/15 週次ルーティン(第6回)",
      "type": "r",
      "attendees": "山本部長, 原氏, 田中, 佐藤",
      "summary": "現状分析の進め方を確認。業務フロー記述書2件を受領。",
      "aiImpact": "資料2 · タスク2",
      "ingested": true
    },
    {
      "group": "8月中旬",
      "title": "8/13 セキュリティ審査 キックオフ",
      "type": "i",
      "attendees": "青木氏, 田中",
      "summary": "審査プロセスと質問票を受領。回答期限は9/5。",
      "aiImpact": "課題1起票 · 資料2",
      "ingested": true
    },
    {
      "group": "8月中旬",
      "title": "8/12 検証環境 要件確認",
      "type": "i",
      "attendees": "森氏, 高橋",
      "summary": "検証環境のスペック・アクセス経路を確認。VPN申請を開始。",
      "aiImpact": "タスク2",
      "ingested": true
    },
    {
      "group": "8月上旬",
      "title": "8/8 プロジェクトキックオフ",
      "type": "e",
      "attendees": "木村社長, 鈴木常務, 山本部長 ほか",
      "summary": "体制・スコープ・ルーティン運営を合意。対象3部門を確定(DEC-04, 05)。",
      "aiImpact": "決定2 · 課題1起票",
      "ingested": true
    },
    {
      "group": "8月上旬",
      "title": "8/7 PMOルーティン(原氏)",
      "type": "i",
      "attendees": "原氏, 田中",
      "summary": "資料授受のルールと窓口を確認。共有フォルダを開設。",
      "aiImpact": "タスク1",
      "ingested": true
    },
    {
      "group": "8月上旬",
      "title": "8/5 契約・NDA確認会",
      "type": "i",
      "attendees": "青木氏, 当社法務",
      "summary": "NDA別紙の個人情報範囲に論点。法務レビューへ。",
      "aiImpact": "課題1起票",
      "ingested": true
    },
    {
      "group": "8月上旬",
      "title": "8/1 週次ルーティン(第4回)",
      "type": "r",
      "attendees": "山本部長, 田中, 佐藤",
      "summary": "準備フェーズの残タスクを確認。データ抽出依頼リストを確定。",
      "aiImpact": "タスク3",
      "ingested": true
    },
    {
      "group": "7月",
      "title": "7/25 週次ルーティン(第3回)",
      "type": "r",
      "attendees": "山本部長, 原氏, 田中",
      "summary": "ヒアリング対象部門の候補を協議。",
      "aiImpact": "タスク1",
      "ingested": true
    },
    {
      "group": "7月",
      "title": "7/18 週次ルーティン(第2回)",
      "type": "r",
      "attendees": "山本部長, 原氏, 田中",
      "summary": "受領資料の初期リストを確認。不足分を依頼。",
      "aiImpact": "資料依頼4",
      "ingested": true
    },
    {
      "group": "7月",
      "title": "7/15 スコープ協議",
      "type": "i",
      "attendees": "鈴木常務, 原氏, 田中",
      "summary": "分析対象範囲と成果物の粒度を協議。",
      "aiImpact": "決定1",
      "ingested": true
    },
    {
      "group": "7月",
      "title": "7/11 週次ルーティン(第1回)",
      "type": "r",
      "attendees": "山本部長, 原氏, 田中, 佐藤",
      "summary": "ルーティンの運営方法・議事録フォーマットを確認。",
      "aiImpact": "決定1",
      "ingested": true
    },
    {
      "group": "7月",
      "title": "7/8 提案最終プレゼン",
      "type": "e",
      "attendees": "木村社長, 鈴木常務 ほか",
      "summary": "提案内容の最終確認。10月実行フェーズ開始の前提を共有。",
      "aiImpact": "人物2",
      "ingested": true
    },
    {
      "group": "7月",
      "title": "7/3 キックオフ準備会",
      "type": "i",
      "attendees": "原氏, 田中",
      "summary": "キックオフの進行・出席者を確認。",
      "aiImpact": "タスク2",
      "ingested": true
    }
  ],
  "decisions": [
    {
      "id": "DEC-09",
      "text": "クレンジングの検収は当社が実施し、9/30までに完了させる",
      "date": "8/29",
      "venue": "週次ルーティン(第8回)",
      "agreedBy": "山本部長",
      "relIssueKey": "ISS-04",
      "relLabel": "データ品質",
      "group": "8月の決定"
    },
    {
      "id": "DEC-08",
      "text": "9月経営会議はデータ品質課題の状況を含めて報告する",
      "date": "8/25",
      "venue": "経営報告 準備会",
      "agreedBy": "鈴木常務",
      "relIssueKey": "ISS-04",
      "relLabel": "データ品質",
      "group": "8月の決定"
    },
    {
      "id": "DEC-07",
      "text": "営業部門のヒアリング調整は伊藤氏経由で行う",
      "date": "8/22",
      "venue": "週次ルーティン(第7回)",
      "agreedBy": "渡辺部長",
      "relIssueKey": "ISS-07",
      "relLabel": "ヒアリング日程",
      "group": "8月の決定"
    },
    {
      "id": "DEC-06",
      "text": "データクレンジングはA社側で一次対応、当社は基準策定と検収を担当",
      "date": "8/22",
      "venue": "週次ルーティン(第7回)",
      "agreedBy": "鈴木常務, 山本部長",
      "relIssueKey": "ISS-04",
      "relLabel": "データ品質",
      "group": "8月の決定"
    },
    {
      "id": "DEC-05",
      "text": "現状分析の対象部門は営業・経理・情シスの3部門に限定する",
      "date": "8/8",
      "venue": "キックオフ",
      "agreedBy": "鈴木常務",
      "relIssueKey": "ISS-07",
      "relLabel": "ヒアリング日程",
      "group": "8月の決定"
    },
    {
      "id": "DEC-04",
      "text": "週次ルーティンは毎週金曜15時、議事録は当社作成・A社翌営業日確認",
      "date": "8/8",
      "venue": "キックオフ",
      "agreedBy": "山本部長",
      "relIssueKey": null,
      "relLabel": null,
      "group": "8月の決定"
    },
    {
      "id": "DEC-03",
      "text": "機密データはA社環境内でのみ分析し、持ち出しは統計値に限る",
      "date": "8/5",
      "venue": "契約時合意",
      "agreedBy": "総務部, 当社PM",
      "relIssueKey": null,
      "relLabel": null,
      "group": "8月の決定"
    },
    {
      "id": "DEC-02",
      "text": "KPIは中期経営計画の重点3領域に対応させる",
      "date": "7/15",
      "venue": "スコープ協議",
      "agreedBy": "鈴木常務",
      "relIssueKey": "ISS-11",
      "relLabel": "KPI定義の合意",
      "group": "7月の決定"
    },
    {
      "id": "DEC-01",
      "text": "実行フェーズは10月開始を前提とする",
      "date": "7/8",
      "venue": "提案最終プレゼン",
      "agreedBy": "木村社長",
      "relIssueKey": null,
      "relLabel": null,
      "group": "7月の決定"
    }
  ],
  "access": [
    {
      "member": "田中",
      "ini": "田",
      "role": "当社 · PM",
      "items": {
        "A社ゲストアカウント": {
          "category": "アカウント",
          "status": "d"
        },
        "ADグループ追加": {
          "category": "アカウント",
          "status": "d"
        },
        "メール配布リスト": {
          "category": "アカウント",
          "status": "d"
        },
        "Teamsゲスト招待": {
          "category": "アカウント",
          "status": "d"
        },
        "VPN接続": {
          "category": "ネットワーク",
          "status": "d"
        },
        "入館証発行": {
          "category": "ネットワーク",
          "status": "d"
        },
        "社内Wi-Fi申請": {
          "category": "ネットワーク",
          "status": "d"
        },
        "リポジトリ招待(GitLab)": {
          "category": "開発環境",
          "status": "d"
        },
        "CI実行権限": {
          "category": "開発環境",
          "status": "d"
        },
        "検証環境SSH": {
          "category": "開発環境",
          "status": "d"
        },
        "シークレット共有": {
          "category": "開発環境",
          "status": "d"
        },
        "共有フォルダ権限": {
          "category": "データ/BI",
          "status": "d"
        },
        "BIツール閲覧": {
          "category": "データ/BI",
          "status": "d"
        },
        "DWH読取ロール": {
          "category": "データ/BI",
          "status": "d"
        },
        "データ抽出申請": {
          "category": "データ/BI",
          "status": "d"
        },
        "セキュリティ研修": {
          "category": "手続き・研修",
          "status": "d"
        },
        "NDA締結": {
          "category": "手続き・研修",
          "status": "d"
        },
        "PJ規約同意": {
          "category": "手続き・研修",
          "status": "d"
        },
        "勤怠・経費システム": {
          "category": "手続き・研修",
          "status": "d"
        },
        "緊急連絡網登録": {
          "category": "手続き・研修",
          "status": "d"
        }
      }
    },
    {
      "member": "佐藤",
      "ini": "佐",
      "role": "当社 · コンサルタント",
      "items": {
        "A社ゲストアカウント": {
          "category": "アカウント",
          "status": "d"
        },
        "ADグループ追加": {
          "category": "アカウント",
          "status": "d"
        },
        "メール配布リスト": {
          "category": "アカウント",
          "status": "d"
        },
        "Teamsゲスト招待": {
          "category": "アカウント",
          "status": "d"
        },
        "VPN接続": {
          "category": "ネットワーク",
          "status": "d"
        },
        "入館証発行": {
          "category": "ネットワーク",
          "status": "d"
        },
        "社内Wi-Fi申請": {
          "category": "ネットワーク",
          "status": "d"
        },
        "リポジトリ招待(GitLab)": {
          "category": "開発環境",
          "status": "x"
        },
        "CI実行権限": {
          "category": "開発環境",
          "status": "x"
        },
        "検証環境SSH": {
          "category": "開発環境",
          "status": "x"
        },
        "シークレット共有": {
          "category": "開発環境",
          "status": "x"
        },
        "共有フォルダ権限": {
          "category": "データ/BI",
          "status": "d"
        },
        "BIツール閲覧": {
          "category": "データ/BI",
          "status": "d"
        },
        "DWH読取ロール": {
          "category": "データ/BI",
          "status": "d"
        },
        "データ抽出申請": {
          "category": "データ/BI",
          "status": "d"
        },
        "セキュリティ研修": {
          "category": "手続き・研修",
          "status": "d"
        },
        "NDA締結": {
          "category": "手続き・研修",
          "status": "d"
        },
        "PJ規約同意": {
          "category": "手続き・研修",
          "status": "d"
        },
        "勤怠・経費システム": {
          "category": "手続き・研修",
          "status": "d"
        },
        "緊急連絡網登録": {
          "category": "手続き・研修",
          "status": "d"
        }
      }
    },
    {
      "member": "高橋",
      "ini": "高",
      "role": "当社 · アナリスト",
      "items": {
        "A社ゲストアカウント": {
          "category": "アカウント",
          "status": "d"
        },
        "ADグループ追加": {
          "category": "アカウント",
          "status": "d"
        },
        "メール配布リスト": {
          "category": "アカウント",
          "status": "d"
        },
        "Teamsゲスト招待": {
          "category": "アカウント",
          "status": "d"
        },
        "VPN接続": {
          "category": "ネットワーク",
          "status": "p"
        },
        "入館証発行": {
          "category": "ネットワーク",
          "status": "d"
        },
        "社内Wi-Fi申請": {
          "category": "ネットワーク",
          "status": "d"
        },
        "リポジトリ招待(GitLab)": {
          "category": "開発環境",
          "status": "p"
        },
        "CI実行権限": {
          "category": "開発環境",
          "status": "d"
        },
        "検証環境SSH": {
          "category": "開発環境",
          "status": "d"
        },
        "シークレット共有": {
          "category": "開発環境",
          "status": "d"
        },
        "共有フォルダ権限": {
          "category": "データ/BI",
          "status": "d"
        },
        "BIツール閲覧": {
          "category": "データ/BI",
          "status": "d"
        },
        "DWH読取ロール": {
          "category": "データ/BI",
          "status": "p"
        },
        "データ抽出申請": {
          "category": "データ/BI",
          "status": "d"
        },
        "セキュリティ研修": {
          "category": "手続き・研修",
          "status": "d"
        },
        "NDA締結": {
          "category": "手続き・研修",
          "status": "d"
        },
        "PJ規約同意": {
          "category": "手続き・研修",
          "status": "d"
        },
        "勤怠・経費システム": {
          "category": "手続き・研修",
          "status": "d"
        },
        "緊急連絡網登録": {
          "category": "手続き・研修",
          "status": "d"
        }
      }
    },
    {
      "member": "中村",
      "ini": "中",
      "role": "当社 · 9/8参画予定",
      "items": {
        "A社ゲストアカウント": {
          "category": "アカウント",
          "status": "a"
        },
        "ADグループ追加": {
          "category": "アカウント",
          "status": "n"
        },
        "メール配布リスト": {
          "category": "アカウント",
          "status": "n"
        },
        "Teamsゲスト招待": {
          "category": "アカウント",
          "status": "n"
        },
        "VPN接続": {
          "category": "ネットワーク",
          "status": "n"
        },
        "入館証発行": {
          "category": "ネットワーク",
          "status": "n"
        },
        "社内Wi-Fi申請": {
          "category": "ネットワーク",
          "status": "n"
        },
        "リポジトリ招待(GitLab)": {
          "category": "開発環境",
          "status": "p"
        },
        "CI実行権限": {
          "category": "開発環境",
          "status": "n"
        },
        "検証環境SSH": {
          "category": "開発環境",
          "status": "n"
        },
        "シークレット共有": {
          "category": "開発環境",
          "status": "n"
        },
        "共有フォルダ権限": {
          "category": "データ/BI",
          "status": "n"
        },
        "BIツール閲覧": {
          "category": "データ/BI",
          "status": "n"
        },
        "DWH読取ロール": {
          "category": "データ/BI",
          "status": "n"
        },
        "データ抽出申請": {
          "category": "データ/BI",
          "status": "n"
        },
        "セキュリティ研修": {
          "category": "手続き・研修",
          "status": "p"
        },
        "NDA締結": {
          "category": "手続き・研修",
          "status": "p"
        },
        "PJ規約同意": {
          "category": "手続き・研修",
          "status": "n"
        },
        "勤怠・経費システム": {
          "category": "手続き・研修",
          "status": "n"
        },
        "緊急連絡網登録": {
          "category": "手続き・研修",
          "status": "n"
        }
      }
    },
    {
      "member": "林(A社)",
      "ini": "林",
      "role": "クライアント · 情シス連携",
      "items": {
        "A社ゲストアカウント": {
          "category": "アカウント",
          "status": "x"
        },
        "ADグループ追加": {
          "category": "アカウント",
          "status": "x"
        },
        "メール配布リスト": {
          "category": "アカウント",
          "status": "x"
        },
        "Teamsゲスト招待": {
          "category": "アカウント",
          "status": "x"
        },
        "VPN接続": {
          "category": "ネットワーク",
          "status": "x"
        },
        "入館証発行": {
          "category": "ネットワーク",
          "status": "x"
        },
        "社内Wi-Fi申請": {
          "category": "ネットワーク",
          "status": "x"
        },
        "リポジトリ招待(GitLab)": {
          "category": "開発環境",
          "status": "d"
        },
        "CI実行権限": {
          "category": "開発環境",
          "status": "x"
        },
        "検証環境SSH": {
          "category": "開発環境",
          "status": "x"
        },
        "シークレット共有": {
          "category": "開発環境",
          "status": "x"
        },
        "共有フォルダ権限": {
          "category": "データ/BI",
          "status": "d"
        },
        "BIツール閲覧": {
          "category": "データ/BI",
          "status": "a"
        },
        "DWH読取ロール": {
          "category": "データ/BI",
          "status": "x"
        },
        "データ抽出申請": {
          "category": "データ/BI",
          "status": "x"
        },
        "セキュリティ研修": {
          "category": "手続き・研修",
          "status": "x"
        },
        "NDA締結": {
          "category": "手続き・研修",
          "status": "x"
        },
        "PJ規約同意": {
          "category": "手続き・研修",
          "status": "x"
        },
        "勤怠・経費システム": {
          "category": "手続き・研修",
          "status": "x"
        },
        "緊急連絡網登録": {
          "category": "手続き・研修",
          "status": "x"
        }
      }
    }
  ]
};
