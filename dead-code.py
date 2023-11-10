import sys
import re

KINDS = {'constant', 'variable', 'procedure', 'primitive', 'string'}
DEFINITION = re.compile(r"^\s*(" + r"|".join(KINDS) + r")\s+(\w+)", re.MULTILINE)

if __name__ == '__main__':
    if len(sys.argv) != 2:
        print('Usage: python dead-code.py <filename>')
        sys.exit(1)
    
    filename = sys.argv[1]
    with open(filename) as f:
        code = f.read()

    definitions = [match.group(2) for match in DEFINITION.finditer(code)]
    occurrences = {definition: len(list(re.finditer(definition, code))) for definition in definitions}
    print("Unreachable:")
    for definition, count in occurrences.items():
        assert count > 0
        if count == 1:
            print(f"\t{definition}")
