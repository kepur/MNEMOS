"""Tax rules per region."""

RATES = {
    'DE': 0.19,
    'FR': 0.2,
    'NL': 0.21,
    'SE': 0.25,
    'US-CA': 0.0725,
    'US-NY': 0.04,
    'US-TX': 0.0625,
    'JP': 0.1,
    'AU': 0.1,
    'CA-ON': 0.13,
}

EXEMPT_CATEGORIES = {"books", "medicine", "education"}


def rate_for(region):
    try:
        return RATES[region]
    except KeyError:
        raise KeyError(f"no tax rate for region {region!r}") from None


def calc_tax(amount, region, category="general"):
    """Tax due on ``amount`` (already net of discounts), rounded to cents."""
    if amount < 0:
        raise ValueError("amount must not be negative")
    if category in EXEMPT_CATEGORIES:
        return 0.0
    return round(amount * rate_for(region) + 1e-9, 2)
