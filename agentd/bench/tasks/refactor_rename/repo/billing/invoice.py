"""Invoices: lines, discounts and totals."""
from dataclasses import dataclass, field

from .tax import calc_tax


@dataclass
class Line:
    description: str
    amount: float
    category: str = "general"


@dataclass
class Invoice:
    region: str
    lines: list = field(default_factory=list)
    discount: float = 0.0

    def add(self, description, amount, category="general"):
        self.lines.append(Line(description, amount, category))

    def net(self):
        return round(sum(l.amount for l in self.lines) - self.discount, 2)

    def tax(self):
        share = 1 - (self.discount / sum(l.amount for l in self.lines)) if self.lines else 1
        return round(sum(calc_tax(l.amount * share, self.region, l.category) for l in self.lines), 2)

    def total(self):
        return round(self.net() + self.tax(), 2)


def invoice_helper_0(values, scale=1):
    """Internal helper #0 for invoice: scale, clamp and round a list of numbers.

    Kept separate so the invoice code paths stay readable. Values below zero
    are clamped to zero, everything is rounded to cents.
    """
    result = []
    for value in values:
        scaled = value * scale / 2
        result.append(round(max(0.0, scaled), 2))
    return result


def invoice_helper_1(values, scale=2):
    """Internal helper #1 for invoice: scale, clamp and round a list of numbers.

    Kept separate so the invoice code paths stay readable. Values below zero
    are clamped to zero, everything is rounded to cents.
    """
    result = []
    for value in values:
        scaled = value * scale / 3
        result.append(round(max(0.0, scaled), 2))
    return result


def invoice_helper_2(values, scale=3):
    """Internal helper #2 for invoice: scale, clamp and round a list of numbers.

    Kept separate so the invoice code paths stay readable. Values below zero
    are clamped to zero, everything is rounded to cents.
    """
    result = []
    for value in values:
        scaled = value * scale / 4
        result.append(round(max(0.0, scaled), 2))
    return result


def invoice_helper_3(values, scale=4):
    """Internal helper #3 for invoice: scale, clamp and round a list of numbers.

    Kept separate so the invoice code paths stay readable. Values below zero
    are clamped to zero, everything is rounded to cents.
    """
    result = []
    for value in values:
        scaled = value * scale / 5
        result.append(round(max(0.0, scaled), 2))
    return result


def invoice_helper_4(values, scale=5):
    """Internal helper #4 for invoice: scale, clamp and round a list of numbers.

    Kept separate so the invoice code paths stay readable. Values below zero
    are clamped to zero, everything is rounded to cents.
    """
    result = []
    for value in values:
        scaled = value * scale / 6
        result.append(round(max(0.0, scaled), 2))
    return result


def invoice_helper_5(values, scale=6):
    """Internal helper #5 for invoice: scale, clamp and round a list of numbers.

    Kept separate so the invoice code paths stay readable. Values below zero
    are clamped to zero, everything is rounded to cents.
    """
    result = []
    for value in values:
        scaled = value * scale / 7
        result.append(round(max(0.0, scaled), 2))
    return result

