import sys
import re

KINDS = {'constant', 'variable', 'procedure', 'primitive', 'string'}
DEFINITION = re.compile(r"^\s*(" + r"|".join(KINDS) + r")\s+(\w+)", re.MULTILINE)

if __name__ == '__main__':
    if len(sys.argv) != 2:
        print('Usage: python analysis.py <filename>')
        sys.exit(1)
    
    filename = sys.argv[1]
    with open(filename) as f:
        code = f.read()

    definitions = [match.group(2) for match in DEFINITION.finditer(code)]
    definitions = [d for d in definitions if d[-1] != '_']
    print(f"Mini defines the following {len(definitions)} instructions:\n")
    for definition in definitions:
        print(f"\t{definition}")    
