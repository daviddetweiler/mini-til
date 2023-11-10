import sys
import math

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


class AdaptiveMarkovModel:
    def __init__(self, n_symbols):
        self.context_models = [GlobalAdaptiveModel(n_symbols) for _ in range(n_symbols)]
        self.context = 0

    def pvalue(self, symbol):
        return self.context_models[self.context].pvalue(symbol)

    def update(self, symbol):
        self.context_models[self.context].update(symbol)
        self.context = symbol

    def range(self):
        return self.context_models[self.context].range()


MAGIC = 64 - 6
LBOUND = shl(1, MAGIC)
UBOUND = subtract(0, LBOUND)

# TODO: check precision guarantees (0x4cfffff..., 0x4d01000000...) seems to me the smallest possible interval width
# (2^48 + 1)


class HowardVitterModel:
    def __init__(self, n_symbols):
        assert n_symbols == 2  # For debugging atm
        self.p_for_1 = divide(1, n_symbols)
        self.f = subtract(0, divide(1, 32))

    def pvalue(self, symbol):
        return self.p_for_1 if symbol == 1 else subtract(0, self.p_for_1)

    def update(self, symbol):
        if symbol == 0:
            self.p_for_1 = multiply(self.p_for_1, self.f)
        else:
            self.p_for_1 = add(multiply(self.p_for_1, self.f), subtract(0, self.f))

        if self.p_for_1 < LBOUND:
            self.p_for_1 = LBOUND
        elif self.p_for_1 > UBOUND:
            self.p_for_1 = UBOUND

    def range(self):
        return 2


class HowardVitterTreeModel:
    def __init__(self, n_symbols):
        assert n_symbols == 256
        bit8_models = [(HowardVitterModel(2), (None, None)) for _ in range(128)]
        bit7_models = [
            (HowardVitterModel(2), (bit8_models[2 * i], bit8_models[2 * i + 1]))
            for i in range(64)
        ]
        bit6_models = [
            (HowardVitterModel(2), (bit7_models[2 * i], bit7_models[2 * i + 1]))
            for i in range(32)
        ]
        bit5_models = [
            (HowardVitterModel(2), (bit6_models[2 * i], bit6_models[2 * i + 1]))
            for i in range(16)
        ]
        bit4_models = [
            (HowardVitterModel(2), (bit5_models[2 * i], bit5_models[2 * i + 1]))
            for i in range(8)
        ]
        bit3_models = [
            (HowardVitterModel(2), (bit4_models[2 * i], bit4_models[2 * i + 1]))
            for i in range(4)
        ]
        bit2_models = [
            (HowardVitterModel(2), (bit3_models[2 * i], bit3_models[2 * i + 1]))
            for i in range(2)
        ]
        bit1_model = (HowardVitterModel(2), (bit2_models[0], bit2_models[1]))

        self.tree = bit1_model

    def pvalue(self, symbol):
        model = self.tree
        p = subtract(0, 1)  # Max probability
        for i in range(8):
            bit = (symbol >> (7 - i)) & 1
            predictor, branches = model
            p = multiply(p, predictor.pvalue(bit))
            model = branches[bit]

        return p

    def update(self, symbol):
        model = self.tree
        for i in range(8):
            bit = (symbol >> (7 - i)) & 1
            predictor, branches = model
            predictor.update(bit)
            model = branches[bit]

    def range(self):
        return 256


class Encoder:
    def __init__(self) -> None:
        self.a = 0
        self.b = (1 << 64) - 1
        self.encoded = b""
        self.pending = 0
        self.leader = 0

    def encode(self, model, data):
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


if __name__ == "__main__":
    if len(sys.argv) != 4 or sys.argv[1] not in ("pack", "unpack"):
        print("Usage: ac.py <pack|unpack> <input> <output>")
        sys.exit(1)

    with open(sys.argv[2], "rb") as f:
        data = f.read()

    if sys.argv[1] == "pack":
        e = entropy(data)
        print(f"{e:.2f}\tbits of entropy per symbol")
        print(f"{100 * e / 8 :.2f}%\toptimal compression ratio")
        min_size = math.ceil((e / 8) * len(data))

        encoder = Encoder()
        encoder.encode(GlobalAdaptiveModel(256), data)
        encoded = encoder.end_stream()

        decoder = Decoder(encoded)
        decoded = decoder.decode(GlobalAdaptiveModel(256), len(data))
        if decoded != list(data):
            print("Stream corruption detected!")
            sys.exit(1)

        print(len(encoded), "compressed size", sep="\t")
        print(f"{100 * len(encoded) / len(data):.2f}%\tcompression ratio")
        print(
            f"{100 * (len(encoded) - min_size) / min_size:.2f}%\tadaptive coding overhead"
        )
        with open(sys.argv[3], "wb") as f:
            f.write(encoded)
    elif sys.argv[1] == "unpack":
        decoder = Decoder(data)
        decoded = decoder.decode(GlobalAdaptiveModel(256), len(data))
        with open(sys.argv[3], "wb") as f:
            f.write(decoded)
