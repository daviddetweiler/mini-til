import sys

if __name__ == "__main__":
    if len(sys.argv) != 3:
        print("Usage: python huffman.py <filename> <destination>")
        sys.exit(1)

    filename = sys.argv[1]
    with open(filename, "rb") as file:
        data = file.read()

    with open(sys.argv[2], "w") as file:
        i = 0
        for byte in data:
            if i % 16 == 0:
                print("db `", end="", file=file)

            print("\\x{:02x}".format(byte), end="", file=file)

            if i % 16 == 15:
                print("`", file=file)

            i += 1

        if i % 16 != 0:
            print("`", file=file)
