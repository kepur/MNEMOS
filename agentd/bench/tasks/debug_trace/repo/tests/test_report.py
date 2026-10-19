import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from app import ledger, report  # noqa: E402

LINES = """
# date, amount, category
2025-12-28, 12.50, Groceries
29/12/2025, 40.00, train
2026-01-04, 7.25, supermarket
20260105, 100.00, power
2026-01-11, 3.00, Bus
2026-01-12, 9.99, books
""".strip().splitlines()


class ReportTests(unittest.TestCase):
    def setUp(self):
        self.entries = ledger.load(LINES)

    def test_weekly_summary(self):
        self.assertEqual(report.weekly_summary(self.entries), {
            "2025-W52": 12.5,
            "2026-W01": 47.25,
            "2026-W02": 103.0,
            "2026-W03": 9.99,
        })

    def test_weekly_keys_chronological(self):
        keys = list(report.weekly_summary(self.entries))
        self.assertEqual(keys, sorted(keys))
        self.assertEqual(len(keys), 4)

    def test_monthly_summary(self):
        self.assertEqual(report.monthly_summary(self.entries),
                         {"2025-12": 52.5, "2026-01": 120.24})

    def test_by_category(self):
        self.assertEqual(report.by_category(self.entries)[:2],
                         [("utilities", 100.0), ("transport", 43.0)])

    def test_bad_line_reports_number(self):
        with self.assertRaisesRegex(ValueError, "line 2"):
            ledger.load(["2026-01-01, 1, x", "nonsense"])


if __name__ == "__main__":
    unittest.main()
