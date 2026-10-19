import io
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from shop.cart import Cart  # noqa: E402
from shop.cli import main  # noqa: E402


class CartTests(unittest.TestCase):
    def test_totals(self):
        cart = Cart()
        cart.add("apple", 4)
        cart.add("bread")
        self.assertEqual(cart.subtotal(), 4.75)
        self.assertEqual(cart.total(), 5.13)

    def test_unknown_sku(self):
        with self.assertRaises(KeyError):
            Cart().add("caviar")

    def test_cli(self):
        out = io.StringIO()
        self.assertEqual(main(["apple:4", "bread"], out=out), 0)
        self.assertEqual(out.getvalue().splitlines(), ["subtotal 4.75", "total 5.13"])


if __name__ == "__main__":
    unittest.main()
