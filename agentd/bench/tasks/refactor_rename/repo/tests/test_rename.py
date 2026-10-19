import re
import sys
import unittest
import warnings
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

import billing  # noqa: E402
from billing import exports, invoice, quotes, refunds, reports, subscriptions, tax  # noqa: E402


class RenameTests(unittest.TestCase):
    def test_new_name_exported(self):
        self.assertIs(billing.compute_tax, tax.compute_tax)
        self.assertIn("compute_tax", billing.__all__)
        self.assertEqual(tax.compute_tax(100, "DE"), 19.0)

    def test_old_name_is_deprecated_alias(self):
        with warnings.catch_warnings(record=True) as caught:
            warnings.simplefilter("always")
            self.assertEqual(tax.calc_tax(100, "FR"), 20.0)
        self.assertTrue(any(issubclass(w.category, DeprecationWarning) for w in caught))

    def test_no_internal_use_of_old_name(self):
        offenders = []
        for path in sorted((ROOT / "billing").glob("*.py")):
            if path.name == "tax.py":
                continue
            if re.search(r"\bcalc_tax\b", path.read_text()):
                offenders.append(path.name)
        self.assertEqual(offenders, [])

    def test_no_warnings_on_normal_use(self):
        with warnings.catch_warnings():
            warnings.simplefilter("error")
            inv = invoice.Invoice("NL")
            inv.add("chair", 100)
            inv.add("manual", 20, "books")
            self.assertEqual(inv.total(), 141.0)
            self.assertEqual(refunds.refund(50, "SE"), (50, 12.5))
            self.assertEqual(reports.tax_by_region([("JP", 10, "general"), ("DE", 10, "books")]), {"DE": 0.0, "JP": 1.0})
            self.assertEqual(subscriptions.Subscription("pro", 10, "US-NY").yearly_cost(), 124.8)
            self.assertEqual(list(exports.invoice_rows(inv))[1], "chair,100.00,21.00")
            self.assertEqual(quotes.quote(10, "AU"), "10.00 + tax 1.00 = 11.00")


if __name__ == "__main__":
    unittest.main()
