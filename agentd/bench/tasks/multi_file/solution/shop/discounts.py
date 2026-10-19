"""Discount codes."""
from .pricing import money

CODES = {
    "SAVE10": {"kind": "percent", "value": 10, "minimum": 0.0},
    "FLAT5": {"kind": "flat", "value": 5.0, "minimum": 20.0},
}


def lookup(code):
    rule = CODES.get(str(code).upper())
    if rule is None:
        raise ValueError(f"unknown code: {code}")
    return rule


def amount(code, subtotal):
    rule = lookup(code)
    if subtotal < rule["minimum"]:
        raise ValueError(f"{code} needs a subtotal of at least {rule['minimum']:.2f}")
    if rule["kind"] == "percent":
        return money(min(subtotal, subtotal * rule["value"] / 100))
    return money(min(subtotal, rule["value"]))
