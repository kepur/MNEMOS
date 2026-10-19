"""Shopping cart."""
from .pricing import TAX_RATE, line_total, money


class Cart:
    def __init__(self):
        self.lines = {}

    def add(self, sku, qty=1):
        line_total(sku, qty)  # validates sku and qty
        self.lines[sku] = self.lines.get(sku, 0) + qty

    def subtotal(self):
        return money(sum(line_total(sku, qty) for sku, qty in self.lines.items()))

    def tax(self):
        return money(self.subtotal() * TAX_RATE)

    def total(self):
        return money(self.subtotal() + self.tax())
