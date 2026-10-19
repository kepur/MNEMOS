import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from inventory import Inventory  # noqa: E402


def stocked():
    inv = Inventory()
    inv.add("bolt", 10, 0.25)
    inv.add("nut", 3, 0.10)
    inv.add("washer", 3, 0.05)
    inv.add("gear", 1, 12.5)
    return inv


class RemoveTests(unittest.TestCase):
    def test_remove_returns_remaining(self):
        inv = stocked()
        self.assertEqual(inv.remove("bolt", 4), 6)
        self.assertEqual(inv.quantity("bolt"), 6)

    def test_remove_to_zero_deletes(self):
        inv = stocked()
        self.assertEqual(inv.remove("gear", 1), 0)
        self.assertNotIn("gear", inv.names())

    def test_unknown_item(self):
        with self.assertRaises(KeyError):
            stocked().remove("spring", 1)

    def test_invalid_qty_keeps_stock(self):
        inv = stocked()
        for bad in (0, -1, 2.5, 11):
            with self.assertRaises(ValueError):
                inv.remove("bolt", bad)
        self.assertEqual(inv.quantity("bolt"), 10)


class ReportTests(unittest.TestCase):
    def test_low_stock_order(self):
        self.assertEqual(stocked().low_stock(4), ["gear", "nut", "washer"])

    def test_low_stock_strict(self):
        self.assertEqual(stocked().low_stock(1), [])

    def test_total_value(self):
        self.assertEqual(stocked().total_value(), 15.45)

    def test_empty_value(self):
        self.assertEqual(Inventory().total_value(), 0.0)


if __name__ == "__main__":
    unittest.main()
