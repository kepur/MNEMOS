"""Command line: python3 -m shop.cli apple:3 bread:1"""
import argparse
import sys

from .cart import Cart


def parse_item(text):
    sku, _, qty = text.partition(":")
    return sku, int(qty or 1)


def main(argv=None, out=sys.stdout):
    parser = argparse.ArgumentParser(prog="shop")
    parser.add_argument("items", nargs="+", help="sku[:qty]")
    args = parser.parse_args(argv)
    cart = Cart()
    for item in args.items:
        cart.add(*parse_item(item))
    print(f"subtotal {cart.subtotal():.2f}", file=out)
    print(f"total {cart.total():.2f}", file=out)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
