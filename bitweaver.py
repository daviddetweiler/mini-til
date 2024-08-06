import sys
import ac
import math


def encode_15bit(n: int) -> bytes:
    assert 0 <= n < 2**15
    if n < 0x80:
        return n.to_bytes(1, "big")
    else:
        return (0x8000 | n).to_bytes(2, "big")


def encode_bytes(encoder: ac.Encoder, bit_model, data: bytes):
    for byte in data:
        bitstring = [0] * 8
        for i in range(8):
            hibit = (byte & 0x80) >> 7
            byte <<= 1
            bitstring[i] = hibit

        encoder.encode(bit_model, bitstring)


def decode_byte(decoder: ac.Decoder, bit_model) -> bytes:
    return decode_bytes(decoder, bit_model, 1)


def decode_bytes(decoder: ac.Decoder, bit_model, count: int) -> bytes:
    data = [0] * count
    for n in range(count):
        byte = 0
        for i in range(8):
            bit = decoder.decode(bit_model, 1)[0]
            byte = (byte << 1) | bit

        data[n] = byte

    return bytes(data)


def encode(data: bytes, allocation_size: int) -> bytes:
    encoder = ac.Encoder()
    big_chain = ac.build_markov_chain()
    bid_model = ac.MarkovChainModel(big_chain)
    dummy_model = ac.MarkovChainModel(ac.build_markov_loop(1))

    expected_bytes = len(data)
    encode_bytes(encoder, dummy_model, allocation_size.to_bytes(4, "big"))
    assert dummy_model.node.tag == "root"
    encode_bytes(encoder, dummy_model, expected_bytes.to_bytes(4, "big"))

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

        assert bid_model.node.tag == "root"
        if longest_match is not None:
            offset, length = longest_match
            offset_code = encode_15bit(offset)
            length_code = encode_15bit(length)
            if len(offset_code) + len(length_code) < length:
                encoder.encode(bid_model, [1])
                assert bid_model.node.tag == "offset"
                encode_bytes(encoder, bid_model, offset_code[:1])
                if len(offset_code) > 1:
                    encode_bytes(encoder, bid_model, offset_code[1:])

                assert bid_model.node.tag == "length"
                encode_bytes(encoder, bid_model, length_code[:1])
                if len(length_code) > 1:
                    encode_bytes(encoder, bid_model, length_code[1:])

                i += length
            else:
                encoder.encode(bid_model, [0])
                assert bid_model.node.tag == "literal"
                encode_bytes(encoder, bid_model, data[i : i + 1])
                i += 1
        else:
            encoder.encode(bid_model, [0])
            assert bid_model.node.tag == "literal"
            encode_bytes(encoder, bid_model, data[i : i + 1])
            i += 1

    coded = encoder.end_stream()
    print(len(coded), "bytes compressed", sep="\t")

    return coded


def decode_15bit(data: bytes) -> int:
    leader = data[0]
    if leader < 0x80:
        return leader
    else:
        return int.from_bytes(data, "big") & 0x7FFF


assert decode_15bit(encode_15bit(0)) == 0
assert decode_15bit(encode_15bit(1234)) == 1234, decode_15bit(encode_15bit(1234))


def decode(encoded: bytes) -> bytes:
    decoder = ac.Decoder(encoded)
    big_chain = ac.build_markov_chain()
    bid_model = ac.MarkovChainModel(big_chain)
    dummy_model = ac.MarkovChainModel(ac.build_markov_loop(1))
    _ = int.from_bytes(decode_bytes(decoder, dummy_model, 4), "big")
    expected_bytes = int.from_bytes(decode_bytes(decoder, dummy_model, 4), "big")

    decompressed = b""
    while len(decompressed) < expected_bytes:
        bit = decoder.decode(bid_model, 1)[0]
        if bit == 0:
            literal = decode_byte(decoder, bid_model)
            decompressed += literal
        else:
            offset_bytes = decode_byte(decoder, bid_model)
            if offset_bytes[0] & 0x80 != 0:
                offset_bytes += decode_byte(decoder, bid_model)

            length_bytes = decode_byte(decoder, bid_model)
            if length_bytes[0] & 0x80 != 0:
                length_bytes += decode_byte(decoder, bid_model)

            offset = decode_15bit(offset_bytes)
            length = decode_15bit(length_bytes)

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
    bss_size = int.from_bytes(data[0:8], "little")
    if bss_size > 2**32:  # We're probably dealing with a non-image
        bss_size = 0

    print(bss_size, "extra bytes of BSS", sep="\t")

    return len(data) + bss_size


def info(data: bytes) -> None:
    decoder = ac.Decoder(data)
    big_chain = ac.build_markov_chain()
    bid_model = ac.MarkovChainModel(big_chain)
    dummy_model = ac.MarkovChainModel(ac.build_markov_loop(1))

    allocation_size = int.from_bytes(decode_bytes(decoder, dummy_model, 4), "big")
    expected_bytes = int.from_bytes(decode_bytes(decoder, dummy_model, 4), "big")

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
        bit = decoder.decode(bid_model, 1)[0]
        control_bit_count += 1
        if bit == 0:
            decode_byte(decoder, bid_model)
            literal_byte_count += 1
            bytes_counted += 1
        else:
            pair_count += 1
            b = decode_byte(decoder, bid_model)
            offset_byte_count += 1
            if b[0] & 0x80 != 0:
                decode_byte(decoder, bid_model)
                offset_byte_count += 1
                extended_offset_count += 1

            b = decode_byte(decoder, bid_model)
            length_byte_count += 1
            if b[0] & 0x80 != 0:
                b += decode_byte(decoder, bid_model)
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

    uncoded_length = (
        math.ceil(control_bit_count / 8)
        + literal_byte_count
        + offset_byte_count
        + length_byte_count
        + extended_offset_count
        + extended_length_count
    )

    print(uncoded_length, "bytes uncoded", sep="\t")
    print(f"{100 * len(data) / uncoded_length :.2f}%\tcoding ratio")
    print(f"{100 * uncoded_length / expected_bytes :.2f}%\tuncoded compression ratio")
    print(f"{100 * len(data) / expected_bytes :.2f}%\ttotal compression ratio")


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

    with open(sys.argv[2], "rb") as rf:
        data = rf.read()

    if command == "pack":
        full_size = get_size(data)
        encoded = encode(data, full_size)
        print(f"{100 * len(encoded) / len(data) :.2f}%\tcompression ratio")
        decoded = decode(encoded)
        if decoded != data:
            print("Stream corruption detected!")
            sys.exit(1)

        with open(sys.argv[3], "wb") as wf:
            wf.write(encoded)
    elif command == "unpack":
        decoded = decode(data)
        with open(sys.argv[3], "wb") as wf:
            wf.write(decoded)
    elif command == "info":
        info(data)
