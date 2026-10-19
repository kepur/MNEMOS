"""Catalogue prices and money helpers."""

PRICES = {
    "apple": 0.50,
    "bread": 2.75,
    "cheese": 6.40,
    "coffee": 11.90,
}

TAX_RATE = 0.08


def money(value):
    """Round a float to cents."""
    return round(value + 1e-9, 2)


def unit_price(sku):
    try:
        return PRICES[sku]
    except KeyError:
        raise KeyError(f"unknown sku: {sku}") from None


def line_total(sku, qty):
    if qty <= 0:
        raise ValueError("qty must be positive")
    return money(unit_price(sku) * qty)
