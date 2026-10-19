"""Date helpers shared by the ledger and the reports."""
from datetime import datetime

FORMATS = ("%Y-%m-%d", "%d/%m/%Y", "%Y%m%d")


def parse(text):
    """Parse a date written in one of FORMATS."""
    text = text.strip()
    for fmt in FORMATS:
        try:
            return datetime.strptime(text, fmt).date()
        except ValueError:
            continue
    raise ValueError(f"unrecognised date: {text!r}")


def week_key(day):
    """ISO-8601 week label such as '2026-W07'.

    Weeks start on Monday and the year is the ISO week-numbering year, so
    2025-12-29 belongs to '2026-W01'.
    """
    return day.strftime("%Y-W%U")


def month_key(day):
    return day.strftime("%Y-%m")
