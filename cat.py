import sys

if __name__ == '__main__':
    try:
        files = sys.argv[1:]
        for file in files:
            if file == '-':
                for line in sys.stdin:
                    sys.stdout.write(line)
                    sys.stdout.flush()
            else:
                with open(file, "rb") as f:
                    data = f.read()
                    sys.stdout.write(data.decode('utf-8'))
                    sys.stdout.flush()
    except OSError:
        print("[program stopped accepting input]", file=sys.stderr)
        try:
            sys.stdout.close()
        except:
            pass
