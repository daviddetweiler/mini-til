import sys
import ac

CONFIG = {
    "control": ac.AdaptiveMarkovModel,
    "literal": ac.GlobalAdaptiveModel,
    "offset": ac.GlobalAdaptiveModel,
    "length": ac.GlobalAdaptiveModel,
    "alt_offset": ac.GlobalAdaptiveModel,
    "alt_length": ac.GlobalAdaptiveModel,
}


def encode_15bit(n: int) -> bytes:
    assert 0 <= n < 2**15
    if n < 0x80:
        return n.to_bytes(1, "little")
    else:
        hi = n >> 8
        lo = n & 0xFF
        return (0x80 | hi).to_bytes(1, "little") + lo.to_bytes(1, "little")


def encode(data: bytes, allocation_size: int) -> bytes:
    encoder = ac.Encoder()
    command_model = CONFIG["control"](2)
    literal_model = CONFIG["literal"](256)
    offset_model = CONFIG["offset"](256)
    length_model = CONFIG["length"](256)
    alt_offset_model = CONFIG["alt_offset"](256)
    alt_length_model = CONFIG["alt_length"](256)

    expected_bytes = len(data)
    encoder.encode(literal_model, allocation_size.to_bytes(4, "little"))
    encoder.encode(literal_model, expected_bytes.to_bytes(4, "little"))

    window = 2**15 - 1
    i = 0
    while i < len(data):
        # At least 2 bytes are needed to encode a match, so we match only 3 bytes or more.
        j = 3
        longest_match = None
        while True:
            if i + j > len(data):
                break

            window_base = max(0, i - window)
            window_data = data[window_base : i + j - 1]
            m = window_data.rfind(data[i : i + j])
            if m == -1:
                break

            o, l = i - (window_base + m), j
            longest_match = o, l
            j += 1

        if longest_match is not None:
            offset, length = longest_match
            offset_code = encode_15bit(offset)
            length_code = encode_15bit(length)
            if len(offset_code) + len(length_code) < length:
                encoder.encode(command_model, [1])
                encoder.encode(offset_model, offset_code[:1])
                if len(offset_code) > 1:
                    encoder.encode(alt_offset_model, offset_code[1:])

                encoder.encode(length_model, length_code[:1])
                if len(length_code) > 1:
                    encoder.encode(alt_length_model, length_code[1:])

                i += length
            else:
                encoder.encode(command_model, [0])
                encoder.encode(literal_model, data[i : i + 1])
                i += 1
        else:
            encoder.encode(command_model, [0])
            encoder.encode(literal_model, data[i : i + 1])
            i += 1

    coded = encoder.end_stream()
    print(len(coded), "bytes compressed", sep="\t")

    return coded


def decode_15bit(data: bytes) -> int:
    leader = data[0]
    if leader < 0x80:
        return leader
    else:
        hi = leader & 0x7F
        lo = data[1]
        return (hi << 8) | lo


def decode(encoded: bytes) -> bytes:
    decoder = ac.Decoder(encoded)
    command_model = CONFIG["control"](2)
    literal_model = CONFIG["literal"](256)
    offset_model = CONFIG["offset"](256)
    length_model = CONFIG["length"](256)
    alt_offset_model = CONFIG["alt_offset"](256)
    alt_length_model = CONFIG["alt_length"](256)

    _ = int.from_bytes(bytes(decoder.decode(literal_model, 4)), "little")
    expected_bytes = int.from_bytes(bytes(decoder.decode(literal_model, 4)), "little")

    decompressed = b""
    while len(decompressed) < expected_bytes:
        bit = decoder.decode(command_model, 1)[0]
        if bit == 0:
            literal = bytes(decoder.decode(literal_model, 1))
            decompressed += literal
        else:
            offset = decoder.decode(offset_model, 1)
            if offset[0] & 0x80 != 0:
                offset += decoder.decode(alt_offset_model, 1)

            length = decoder.decode(length_model, 1)
            if length[0] & 0x80 != 0:
                length += decoder.decode(alt_length_model, 1)

            offset = decode_15bit(offset)
            length = decode_15bit(length)

            # This is necessary to do this even kind of efficiently in python, but the assembly language version can
            # just use byte-by-byte copies.
            if offset > length:
                decompressed += decompressed[-offset : -(offset - length)]
            else:
                while length > 0:
                    if offset <= length:
                        decompressed += decompressed[-offset:]
                    else:
                        decompressed += decompressed[-offset : -(offset - length)]

                    length -= offset

    return decompressed


def get_size(data: bytes) -> int:
    bss_size = 0
    bss_size = int.from_bytes(data[-8:], "little")
    print(bss_size, "extra bytes of BSS", sep="\t")
    return len(data) + bss_size


def info(data: bytes) -> None:
    decoder = ac.Decoder(data)
    command_model = CONFIG["control"](2)
    literal_model = CONFIG["literal"](256)
    offset_model = CONFIG["offset"](256)
    length_model = CONFIG["length"](256)
    alt_offset_model = CONFIG["alt_offset"](256)
    alt_length_model = CONFIG["alt_length"](256)

    allocation_size = int.from_bytes(bytes(decoder.decode(literal_model, 4)), "little")

    expected_bytes = int.from_bytes(bytes(decoder.decode(literal_model, 4)), "little")

    print(allocation_size, "bytes allocated", sep="\t")
    print(expected_bytes, "bytes expected", sep="\t")

    bytes_counted = 0
    control_bit_count = 0
    literal_byte_count = 0
    offset_byte_count = 0
    length_byte_count = 0
    pair_count = 0
    extended_offset_count = 0
    extended_length_count = 0
    while bytes_counted < expected_bytes:
        bit = decoder.decode(command_model, 1)[0]
        control_bit_count += 1
        if bit == 0:
            decoder.decode(literal_model, 1)
            literal_byte_count += 1
            bytes_counted += 1
        else:
            pair_count += 1
            b = decoder.decode(offset_model, 1)
            offset_byte_count += 1
            if b[0] & 0x80 != 0:
                decoder.decode(alt_offset_model, 1)
                offset_byte_count += 1
                extended_offset_count += 1

            b = decoder.decode(length_model, 1)
            length_byte_count += 1
            if b[0] & 0x80 != 0:
                b += decoder.decode(alt_length_model, 1)
                length_byte_count += 1
                extended_length_count += 1

            bytes_counted += decode_15bit(b)

    print(control_bit_count, "control bits", sep="\t")
    print(literal_byte_count, "literal bytes", sep="\t")
    print(offset_byte_count, "offset bytes", sep="\t")
    print(extended_offset_count, "extended offsets", sep="\t")
    print(length_byte_count, "length bytes", sep="\t")
    print(extended_length_count, "extended lengths", sep="\t")
    print(pair_count, "offset-length pairs", sep="\t")


if __name__ == "__main__":
    if sys.argv[1] not in ("pack", "unpack", "info"):
        print("Usage: bitweaver.py <pack|unpack|info> [...]")
        sys.exit(1)

    command = sys.argv[1]
    if command in ("pack", "unpack") and len(sys.argv) != 4:
        print("Usage: bitweaver.py <pack|unpack> <input> <output>")
        sys.exit(1)
    elif command == "info" and len(sys.argv) != 3:
        print("Usage: bitweaver.py info <input>")
        sys.exit(1)

    with open(sys.argv[2], "rb") as f:
        data = f.read()

    if command == "pack":
        full_size = get_size(data)
        encoded = encode(data, full_size)
        print(f"{100 * len(encoded) / len(data) :.2f}%\tcompression ratio")
        decoded = decode(encoded)
        if decoded != data:
            print("Stream corruption detected!")
            sys.exit(1)

        with open(sys.argv[3], "wb") as f:
            f.write(encoded)
    elif command == "unpack":
        decoded = decode(data)
        with open(sys.argv[3], "wb") as f:
            f.write(decoded)
    elif command == "info":
        info(data)
