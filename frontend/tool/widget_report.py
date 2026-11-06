"""Run the Flutter widget tests and write an HTML page for the report.

From the frontend folder:

    ..\\backend\\.venv\\Scripts\\python.exe tool\\widget_report.py

Opens nothing by itself. The page is reports/widget_tests.html.
"""

from __future__ import annotations

import html
import json
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
REPORTS = ROOT / "reports"

LABELS = {
    "empty login asks for the username": "تسجيل الدخول الفارغ يطلب اسم المستخدم",
    "wrong password shows the server message": "كلمة المرور الخاطئة تعرض رسالة الخادم",
    "forgot password explains that the manager resets it": "نسيت كلمة المرور توضح أن المدير يعيد التعيين",
    "manager shell shows the dashboard placeholder": "واجهة المدير تعرض لوحة التحكم",
    "manager shell uses drawer navigation on narrow screens": "الشاشة الضيقة تستخدم القائمة الجانبية",
    "operator shell does not show the manager sidebar": "واجهة الموظف لا تعرض قائمة المدير",
    "settings screen shows the three tabs": "الإعدادات تعرض التبويبات الثلاثة",
    "shift form rejects an empty name": "نموذج الوردية يرفض الاسم الفارغ",
    "assets board shows the pump gauge and a tank-link error": "لوحة الأصول تعرض المؤشر وخطأ الربط",
    "tank form rejects an empty name": "نموذج الخزان يرفض الاسم الفارغ",
    "attendance shows present, late, and absent, and exports the same rows": "الحضور يعرض حاضرًا ومتأخرًا وغائبًا ونفس صفوف التصدير",
    "closing meters preview a match, a shortage, and a surplus": "إغلاق العدادات: تطابق وعجز وفائض",
    "close submit validates on click when closing is below opening": "التحقق عند إدخال عداد إغلاق أقل من الافتتاح",
    "duty approval panel offers approve and reject for a pending duty": "اعتماد الوردية يتيح الموافقة أو الرفض",
    "supply form only offers tanks of the chosen product": "نموذج التوريد يعرض خزانات المنتج المختار فقط",
    "dashboard shows the day totals and a shortage in red": "لوحة اليوم تعرض الإجمالي والعجز باللون الأحمر",
    "dashboard hides the table when the day has no shifts and shows an alert": "يوم بلا ورديات يخفي الجدول ويعرض تنبيهًا",
    "dashboard shows the load error": "لوحة التحكم تعرض خطأ التحميل",
    "license banner appears only inside the renewal window": "شريط الرخصة يظهر داخل فترة التجديد فقط",
    "phone operator view offers a new shift": "هاتف الموظف يعرض بدء وردية جديدة",
    "saving a renamed user on a narrow screen does not crash": "حفظ اسم المستخدم على شاشة ضيقة لا يغلق التطبيق",
    "prefers server work hours label": "ساعات العمل تُعرض كما أرسلها الخادم",
    "formats from iso without fractional noise": "تنسيق الوقت من ISO بلا كسور زائدة",
    "4280 liters at 0.150 matches 642.00 and the five-dinar cases": "مطابقة اللترات مع السعر وحالات الخمسة دنانير",
    "validateCloseFields reports the first invalid field": "التحقق يبلغ عن أول حقل غير صالح",
    "accepts eastern arabic numerals in cash and meters": "قبول الأرقام العربية في النقد والعدادات",
    "mixed prices stay on their own lines": "الأسعار المختلفة تبقى كل منها في سطره",
}


def _flutter() -> str:
    candidates = [
        Path(r"D:\Flutter\flutter\bin\flutter.bat"),
        Path(shutil.which("flutter") or ""),
    ]
    for candidate in candidates:
        if candidate and candidate.is_file():
            return str(candidate)
    raise SystemExit("Flutter was not found. Install it or add it to PATH.")


def _run_tests() -> list[dict]:
    REPORTS.mkdir(parents=True, exist_ok=True)
    log_path = REPORTS / "widget_tests.jsonl"
    completed = subprocess.run(
        [_flutter(), "test", "--reporter", "json"],
        cwd=ROOT,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        encoding="utf-8",
        errors="replace",
    )
    log_path.write_text(completed.stdout, encoding="utf-8")
    events = []
    for line in completed.stdout.splitlines():
        line = line.strip()
        if not line.startswith("{"):
            continue
        try:
            events.append(json.loads(line))
        except json.JSONDecodeError:
            continue
    if not any(event.get("type") == "done" for event in events):
        raise SystemExit(completed.stdout[-2000:] or "Flutter test produced no result.")
    return events


def _load_log() -> list[dict]:
    events = []
    for line in (REPORTS / "widget_tests.jsonl").read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line.startswith("{"):
            continue
        try:
            events.append(json.loads(line))
        except json.JSONDecodeError:
            continue
    return events


def _rows(events: list[dict]) -> tuple[list[dict], int]:
    names: dict[int, str] = {}
    started: dict[int, int] = {}
    rows = []
    for event in events:
        if event.get("type") == "testStart":
            test = event.get("test") or {}
            test_id = test.get("id")
            names[test_id] = test.get("name") or ""
            started[test_id] = int(event.get("time") or 0)
        elif event.get("type") == "testDone":
            if event.get("hidden") or event.get("skipped"):
                continue
            test_id = event.get("testID")
            name = names.get(test_id, "")
            if name.startswith("loading "):
                continue
            short = next((key for key in LABELS if key in name), name.split(":")[-1].strip() or name)
            finished = int(event.get("time") or 0)
            rows.append(
                {
                    "name": short,
                    "label": LABELS.get(short, short),
                    "result": event.get("result") or "error",
                    "time_ms": max(0, finished - started.get(test_id, finished)),
                }
            )
    suite_ms = max((int(event.get("time") or 0) for event in events), default=0)
    return rows, suite_ms


def _seconds(ms: int) -> str:
    if ms >= 1000:
        return f"{ms / 1000:.1f} ث"
    return f"{ms} ms"


def _page(rows: list[dict], suite_ms: int) -> str:
    passed = sum(1 for row in rows if row["result"] == "success")
    failed = len(rows) - passed
    body = []
    for index, row in enumerate(rows, start=1):
        ok = row["result"] == "success"
        status = "ناجح" if ok else "فاشل"
        klass = "ok" if ok else "bad"
        body.append(
            "<tr>"
            f"<td>{index}</td>"
            f"<td>{html.escape(row['label'])}</td>"
            f"<td class='{klass}'>{status}</td>"
            f"<td>{_seconds(row['time_ms'])}</td>"
            "</tr>"
        )
    banner = "كل الاختبارات نجحت" if failed == 0 else f"فشل {failed} من {len(rows)}"
    midpoint = (len(body) + 1) // 2
    columns = ("".join(body[:midpoint]), "".join(body[midpoint:]))
    tables = []
    for column in columns:
        tables.append(
            "<table>"
            "<thead><tr><th>#</th><th>الحالة المختبرة</th><th>النتيجة</th><th>الزمن</th></tr></thead>"
            f"<tbody>{column}</tbody></table>"
        )
    return f"""<!DOCTYPE html>
<html lang="ar" dir="rtl">
<head>
  <meta charset="utf-8">
  <title>نتائج اختبار الواجهة</title>
  <style>
    * {{ box-sizing: border-box; }}
    html, body {{ margin: 0; background: #f4f6f8; }}
    body {{
      font-family: "Segoe UI", Tahoma, sans-serif;
      color: #1c2430;
      padding: 16px 18px 12px;
    }}
    header {{
      display: flex;
      align-items: center;
      justify-content: space-between;
      gap: 16px;
      margin-bottom: 10px;
    }}
    h1 {{ margin: 0; font-size: 22px; }}
    p {{ margin: 2px 0 0; color: #52606d; font-size: 13px; }}
    .cards {{ display: flex; gap: 8px; flex: none; }}
    .card {{
      background: white;
      border: 1px solid #d9e2ec;
      border-radius: 8px;
      padding: 6px 12px;
      min-width: 72px;
      text-align: center;
      font-size: 12px;
      color: #52606d;
    }}
    .card b {{ display: block; font-size: 18px; color: #102a43; }}
    .cols {{ display: grid; grid-template-columns: 1fr 1fr; gap: 10px; }}
    table {{ width: 100%; border-collapse: collapse; background: white; font-size: 13px; }}
    th, td {{ border-bottom: 1px solid #e4e7eb; padding: 4px 8px; text-align: right; line-height: 1.25; }}
    th {{ background: #102a43; color: white; font-weight: 600; }}
    td:first-child, th:first-child {{ width: 28px; }}
    td:nth-child(3), th:nth-child(3) {{ width: 52px; }}
    td:nth-child(4), th:nth-child(4) {{ width: 58px; white-space: nowrap; }}
    .ok {{ color: #0b7a3b; font-weight: 700; }}
    .bad {{ color: #b42318; font-weight: 700; }}
  </style>
</head>
<body>
  <header>
    <div>
      <h1>اختبار واجهة نظام إدارة محطة الوقود</h1>
      <p>{html.escape(banner)} — اختبارات ودجت Flutter بدون اتصال بالخادم.</p>
    </div>
    <div class="cards">
      <div class="card"><b>{len(rows)}</b>الاختبارات</div>
      <div class="card"><b>{passed}</b>ناجحة</div>
      <div class="card"><b>{failed}</b>فاشلة</div>
      <div class="card"><b>{_seconds(suite_ms)}</b>زمن التشغيل</div>
    </div>
  </header>
  <div class="cols">
    {tables[0]}
    {tables[1]}
  </div>
</body>
</html>
"""


def main() -> None:
    events = _load_log() if len(sys.argv) > 1 and sys.argv[1] == "--from-log" else _run_tests()
    rows, suite_ms = _rows(events)
    if not rows:
        raise SystemExit("No widget tests were reported.")
    page = REPORTS / "widget_tests.html"
    page.write_text(_page(rows, suite_ms), encoding="utf-8")
    failed = sum(1 for row in rows if row["result"] != "success")
    print(f"{len(rows) - failed} passed, {failed} failed")
    print(page)
    if failed:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
