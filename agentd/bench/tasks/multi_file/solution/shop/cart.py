"""Shopping cart."""
from . import discounts
from .pricing import TAX_RATE, line_total, money


class Cart:
    def __init__(self):
        self.lines = {}
        self.code = None

    def add(self, sku, qty=1):
        line_total(sku, qty)  # validates sku and qty
        self.lines[sku] = self.lines.get(sku, 0) + qty

    def subtotal(self):
        return money(sum(line_total(sku, qty) for sku, qty in self.lines.items()))

    def apply_code(self, code):
        discounts.amount(code, self.subtotal())
        self.code = str(code).upper()

    def discount(self):
        return discounts.amount(self.code, self.subtotal()) if self.code else 0.0

    def tax(self):
        return money((self.subtotal() - self.discount()) * TAX_RATE)

    def total(self):
        return money(self.subtotal() - self.discount() + self.tax())
