"""A tiny in-memory inventory."""
from dataclasses import dataclass


@dataclass
class Item:
    name: str
    qty: int
    price: float


class Inventory:
    def __init__(self):
        self._items = {}

    def add(self, name, qty, price=None):
        """Add ``qty`` units of ``name``.

        A new item needs a price. Adding to an existing item keeps its price
        unless a new price is given. ``qty`` must be a positive integer.
        """
        if not isinstance(qty, int) or qty <= 0:
            raise ValueError("qty must be a positive integer")
        item = self._items.get(name)
        if item is None:
            if price is None:
                raise ValueError("a new item needs a price")
            self._items[name] = Item(name, qty, float(price))
            return
        item.qty += qty
        if price is not None:
            item.price = float(price)

    def quantity(self, name):
        item = self._items.get(name)
        return item.qty if item else 0

    def names(self):
        return sorted(self._items)

    def remove(self, name, qty):
        """Remove ``qty`` units of ``name``.

        - Unknown item: raise ``KeyError``.
        - ``qty`` not a positive integer, or larger than the stock: raise
          ``ValueError`` and leave the stock unchanged.
        - When the stock reaches zero the item is deleted entirely, so it no
          longer appears in ``names()``.
        Returns the remaining quantity.
        """
        item = self._items[name]
        if not isinstance(qty, int) or isinstance(qty, bool) or qty <= 0 or qty > item.qty:
            raise ValueError("invalid quantity")
        item.qty -= qty
        if item.qty == 0:
            del self._items[name]
        return item.qty

    def low_stock(self, threshold):
        """Return the names of items whose quantity is strictly below
        ``threshold``, sorted by quantity ascending, then by name."""
        low = [i for i in self._items.values() if i.qty < threshold]
        return [i.name for i in sorted(low, key=lambda i: (i.qty, i.name))]

    def total_value(self):
        """Return the sum of ``qty * price`` over all items, rounded to two
        decimals. An empty inventory is worth ``0.0``."""
        return round(sum(i.qty * i.price for i in self._items.values()), 2)
