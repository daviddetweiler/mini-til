import sys
import math
from collections import defaultdict
from typing import *

UPPER8 = ((1 << 8) - 1) << (64 - 8)
TAIL8 = UPPER8 >> 8
BITS64 = (1 << 64) - 1


def divide(a, b):
    a <<= 64
    a //= b
    return a & BITS64


def multiply(a, b):
    a *= b
    a >>= 64
    return a & BITS64


def add(a, b):
    return (a + b) & BITS64


def subtract(a, b):
    return (a - b) & BITS64


def shl(a, n):
    return (a << n) & BITS64


def shr(a, n):
    return (a >> n) & BITS64


def nlog2(n):
    return 64 - math.log2(n)


def entropy(symbols):
    histogram = {}
    for symbol in symbols:
        histogram[symbol] = histogram.get(symbol, 0) + 1

    total = sum(histogram.values())
    p_values = [count / total for count in histogram.values()]

    return sum(-p * math.log2(p) for p in p_values)


class GlobalAdaptiveModel:
    def __init__(self, n_symbols):
        assert (
            n_symbols > 0 and n_symbols <= 256
        )  # 64 bits of p-value per symbol makes larger models impractical
        self.total = n_symbols
        self.histogram = [1] * n_symbols

    def pvalue(self, symbol):
        return divide(self.histogram[symbol], self.total)

    def update(self, symbol):
        self.histogram[symbol] += 1
        self.total += 1

    def range(self):
        return len(self.histogram)


class MarkovNode:
    def __init__(self):
        self.model = GlobalAdaptiveModel(2)
        self.children = [None, None]
        self.tag = None
        self.mispredictions = 0
        self.processed = 0


class MarkovChainModel:
    def __init__(self, node: MarkovNode):
        self.node = node
        self.named_parent = node
        self.already_missed = False

    def pvalue(self, symbol):
        return self.node.model.pvalue(symbol)

    def update(self, symbol):
        predicted = 0 if self.node.model.pvalue(0) > self.node.model.pvalue(1) else 1
        if self.node.tag is not None:
            self.node.processed += 1

        if predicted != symbol and not self.already_missed:
            self.named_parent.mispredictions += 1
            self.already_missed = True

        self.node.model.update(symbol)
        self.node = self.node.children[symbol]
        if self.node.tag is not None:
            self.named_parent = self.node
            self.already_missed = False

    def range(self):
        return 2


def compute_miss_recursively(
    node: MarkovNode,
    buckets: Dict[str, Tuple[int, int]],
    visited: Set[MarkovNode] = set(),
) -> None:
    if node in visited:
        return

    a, b = node.children
    if a is not None and a.tag != "root":
        compute_miss_recursively(a, buckets)
    if b is not None and b.tag != "root":
        compute_miss_recursively(b, buckets)

    if node.tag is not None:
        buckets[node.tag] = node.mispredictions, node.processed

    visited.add(node)


def compute_miss_rate(node: MarkovNode) -> Dict[str, float]:
    buckets: Dict[str, Tuple[int, int]] = defaultdict(lambda: (0, 0))
    compute_miss_recursively(node, buckets)
    return {k: n / t for k, (n, t) in buckets.items() if t > 0}


def build_markov_bitstring(end: MarkovNode, n: int) -> MarkovNode:
    if n == 0:
        return end
    else:
        node = MarkovNode()
        node.children[0] = build_markov_bitstring(end, n - 1)
        node.children[1] = build_markov_bitstring(end, n - 1)
        return node


def markov_join(node: MarkovNode, other: MarkovNode):
    joined = MarkovNode()
    joined.children[0] = node
    joined.children[1] = other
    return joined


def build_markov_chain() -> MarkovNode:
    root = MarkovNode()
    root.tag = "root"
    short_length_model = build_markov_bitstring(root, 7)
    short_length_model.tag = "short_length"
    ext_length_model = build_markov_bitstring(short_length_model, 8)
    ext_length_model.tag = "ext_length"
    length_model = markov_join(short_length_model, ext_length_model)
    length_model.tag = "length"

    short_offset_model = build_markov_bitstring(length_model, 7)
    short_offset_model.tag = "short_offset"
    ext_offset_model = build_markov_bitstring(short_offset_model, 8)
    ext_offset_model.tag = "ext_offset"
    offset_model = markov_join(short_offset_model, ext_offset_model)
    offset_model.tag = "offset"

    literal_model = build_markov_bitstring(root, 8)
    literal_model.tag = "literal"
    root.children[0] = literal_model
    root.children[1] = offset_model

    return root


def build_markov_loop(n: int) -> MarkovNode:
    root = MarkovNode()
    root.tag = "root"
    root.children[0] = build_markov_bitstring(root, n - 1)
    root.children[1] = build_markov_bitstring(root, n - 1)
    return root


class Encoder:
    def __init__(self) -> None:
        self.a = 0
        self.b = (1 << 64) - 1
        self.encoded = b""
        self.pending = 0
        self.leader = 0
        self.input_count = 0

    def encode(self, model, data):
        assert model.range() == 2
        self.input_count += len(data)

        for byte in data:
            interval_width = subtract(self.b, self.a)
            for i in range(model.range()):
                p = model.pvalue(i)
                subinterval_width = multiply(interval_width, p)
                if subinterval_width == 0:
                    print("Zero-width interval")

                new_a = add(self.a, subinterval_width)
                if byte == i:
                    if new_a > self.b:
                        print("Invariant broken")
                        sys.exit(1)

                    self.b = new_a
                    break
                else:
                    self.a = new_a

            while (self.a ^ self.b) & UPPER8 == 0:
                # 8 bits have been locked in
                flush_pending = self.pending > 0
                to_code = shr(self.a, 64 - 8)
                self.encoded += to_code.to_bytes(1, "little")
                self.a = shl(self.a, 8)
                self.b = shl(self.b, 8)
                self.b |= (1 << 8) - 1
                if flush_pending:
                    filler = 0xFF if to_code == self.leader else 0x00
                    self.encoded += filler.to_bytes(1, "little") * self.pending
                    self.pending = 0

            model.update(byte)

            a_top = shr(self.a, 64 - 8)
            b_top = shr(self.b, 64 - 8)
            if b_top - a_top == 1:
                while True:
                    a_tail = shr(self.a & TAIL8, 48)
                    b_tail = shr(self.b & TAIL8, 48)
                    if a_tail == 0xFF and b_tail == 0x00:
                        self.leader = a_top
                        # How to understand this check:
                        # Think of the interval (0.799..., 0.8000...) in decimal.
                        # The interval may still shrink arbitrarily without ever actually locking in any digits
                        self.a = shl(self.a, 8)
                        self.b = shl(self.b, 8)
                        self.b |= (1 << 8) - 1
                        self.pending += 1
                        self.a &= ~UPPER8
                        self.b &= ~UPPER8
                        self.a |= shl(a_top, 64 - 8)
                        self.b |= shl(b_top, 64 - 8)
                    else:
                        break

    def end_stream(self):
        flush_pending = self.pending > 0
        self.a = add(self.a, 1 << (64 - 8))  # The decoder semantics use open intervals
        to_code = shr(self.a, (64 - 8))
        self.encoded += to_code.to_bytes(1, "little")
        if flush_pending:
            filler = 0xFF if to_code == self.leader else 0x00
            self.encoded += filler.to_bytes(1, "little") * self.pending
            self.pending = 0

        return self.encoded


class Decoder:
    def __init__(self, encoded):
        self.bitgroups = [byte for byte in encoded]
        self.a = 0
        self.b = (1 << 64) - 1
        self.window = 0
        self.i = 0

    def decode(self, model, expected_length):
        decoded = []
        while self.i < 8:
            self.window = shl(self.window, 8) | (
                self.bitgroups[self.i] if self.i < len(self.bitgroups) else 0
            )

            self.i += 1

        while len(decoded) < expected_length:
            interval_width = subtract(self.b, self.a)
            byte = None
            for j in range(model.range()):
                subinterval_width = multiply(interval_width, model.pvalue(j))
                next_a = add(self.a, subinterval_width)
                if next_a > self.window:
                    self.b = next_a
                    byte = j
                    break

                self.a = next_a

            while (self.a ^ self.b) & UPPER8 == 0:
                # 8 bits have been locked in
                self.a = shl(self.a, 8)
                self.b = shl(self.b, 8)
                self.b |= (1 << 8) - 1
                self.shift_window()

            decoded += [byte]
            model.update(byte)

            a_top = shr(self.a, 64 - 8)
            b_top = shr(self.b, 64 - 8)
            if b_top - a_top == 1:
                while True:
                    a_tail = shr(self.a & TAIL8, 48)
                    b_tail = shr(self.b & TAIL8, 48)
                    if a_tail == 0xFF and b_tail == 0x00:
                        # How to understand this check:
                        # Think of the interval (0.799..., 0.8000...) in decimal.
                        # The interval may still shrink arbitrarily without ever actually locking in any digits
                        self.a = shl(self.a, 8)
                        self.a &= ~UPPER8
                        self.a |= shl(a_top, 64 - 8)

                        self.b = shl(self.b, 8)
                        self.b &= ~UPPER8
                        self.b |= shl(b_top, 64 - 8)

                        self.b |= (1 << 8) - 1

                        window_top = shr(self.window, 64 - 8)
                        self.shift_window()
                        self.window &= ~UPPER8
                        self.window |= shl(window_top, 64 - 8)
                    else:
                        break

        return decoded

    def shift_window(self):
        self.window = shl(self.window, 8) | (
            self.bitgroups[self.i] if self.i < len(self.bitgroups) else 0
        )

        self.i += 1
