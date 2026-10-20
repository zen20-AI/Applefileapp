#!/usr/bin/env python3
"""Lists the UI strings in Sources/Petal as Localizable.strings keys (SwiftUI literal → key).

Interpolations become format specifiers the way SwiftUI does it: numbers (counts) → %lld, the rest → %@.
Usage: scripts/extract-strings.py            # print keys
       scripts/extract-strings.py --check     # keys missing from Resources/th.lproj/Localizable.strings
"""
import re, sys, pathlib

ROOT = pathlib.Path(__file__).resolve().parent.parent
CALLS = r'(?:Text|Button|Label|Toggle|Section|Picker|TextField|SecureField|Stepper|LabeledContent|ContentUnavailableView|help|navigationTitle|confirmationDialog|String\(localized:|title:|tip|feature|description: Text|prompt:|Menu|EditorScaffold\(title:|ValueSlider\(title:)'
LIT = r'"((?:[^"\\]|\\.)*)"'
INT_HINT = re.compile(r'(count|number|Int\(|total|start|\.page|selection\.count|offset|groups\.count|chunk|files|pageCount)', re.I)

def key_for(literal):
    out, i = '', 0
    while i < len(literal):
        if literal.startswith('\\(', i):
            depth, j = 1, i + 2
            while depth:
                if j >= len(literal): return ''  # interpolation with its own quotes: skip
                depth += {'(': 1, ')': -1}.get(literal[j], 0); j += 1
            expr = literal[i + 2:j - 1]
            out += '%@' if ('String(' in expr or 'Component' in expr or 'label' in expr or 'displayString' in expr
                            or 'short' in expr or 'title' in expr or 'format' in expr) else ('%lld' if INT_HINT.search(expr) else '%@')
            i = j
        else:
            out += literal[i]; i += 1
    return out

keys = []
for path in sorted((ROOT / 'Sources/Petal').rglob('*.swift')):
    text = path.read_text()
    for m in re.finditer(CALLS + r'\s*\(?\s*' + LIT, text):
        k = key_for(m.group(1))
        if k.strip() and re.search(r'[A-Za-z]', k) and k not in keys:
            keys.append(k)
    # second literal of ternaries / tip(…, "title", "detail") helpers
    for m in re.finditer(r'(?:\?|:|,)\s*' + LIT + r'\s*(?:\)|:|,)', text):
        k = key_for(m.group(1))
        if ' ' in k and re.search(r'[A-Za-z]', k) and not k.startswith(('x-apple', 'petal:', '/', '%')) and k not in keys:
            keys.append(k)

if '--check' in sys.argv:
    strings = (ROOT / 'Resources/th.lproj/Localizable.strings').read_text()
    have = set(re.findall(r'^"((?:[^"\\]|\\.)*)"\s*=', strings, re.M))
    missing = [k for k in keys if k not in have]
    print('\n'.join(missing)); print(f'{len(missing)} missing of {len(keys)}', file=sys.stderr)
else:
    print('\n'.join(keys))
