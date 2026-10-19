"""Discount code rules.

- SAVE10: 10% off the subtotal.
- FLAT5: 5.00 off, only when the subtotal is at least 20.00; otherwise
  apply_code raises ValueError.
- Unknown codes raise ValueError. Codes are case-insensitive.
- Only one code per cart; applying a second code replaces the first.
- The discount is applied before tax; tax is charged on the discounted amount.
- Cart.discount() returns the discount amount (0.0 without a code).
- The CLI accepts --code CODE and prints an extra "discount X.XX" line between
  subtotal and total when a code is used.
"""
import io
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from shop import discounts  # noqa: E402
from shop.cart import Cart  # noqa: E402
from shop.cli import main  # noqa: E402


def cart_with(**items):
    cart = Cart()
    for sku, qty in items.items():
        cart.add(sku, qty)
    return cart


class DiscountTests(unittest.TestCase):
    def test_module_lists_codes(self):
        self.assertEqual(sorted(discounts.CODES), ["FLAT5", "SAVE10"])

    def test_percent(self):
        cart = cart_with(coffee=2)  # 23.80
        cart.apply_code("save10")
        self.assertEqual(cart.discount(), 2.38)
        self.assertEqual(cart.total(), 23.13)  # (23.80 - 2.38) * 1.08

    def test_flat_needs_minimum(self):
        with self.assertRaises(ValueError):
            cart_with(apple=2).apply_code("FLAT5")
        cart = cart_with(cheese=4)  # 25.60
        cart.apply_code("FLAT5")
        self.assertEqual(cart.discount(), 5.0)
        self.assertEqual(cart.total(), 22.25)  # 20.60 * 1.08

    def test_unknown_code(self):
        with self.assertRaises(ValueError):
            cart_with(apple=1).apply_code("FREE")

    def test_second_code_replaces(self):
        cart = cart_with(cheese=4)
        cart.apply_code("FLAT5")
        cart.apply_code("SAVE10")
        self.assertEqual(cart.discount(), 2.56)

    def test_no_code(self):
        self.assertEqual(cart_with(apple=1).discount(), 0.0)

    def test_cli_code(self):
        out = io.StringIO()
        self.assertEqual(main(["coffee:2", "--code", "SAVE10"], out=out), 0)
        self.assertEqual(out.getvalue().splitlines(),
                         ["subtotal 23.80", "discount 2.38", "total 23.13"])


if __name__ == "__main__":
    unittest.main()
