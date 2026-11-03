# Evidence-only helpers; no work is added inside timed decoder processes.
import hashlib
from pathlib import Path
import re

def import_snapshot(products):
    products = Path(products)
    paths = [p for p in (products / 'SwiftJLI.swiftmodule').rglob('*') if p.is_file()]
    modulemap = products.parent.parent / 'Intermediates.noindex/GeneratedModuleMaps/SwiftJLIEntropyC.modulemap'
    if modulemap.is_file():
        paths.append(modulemap)
        for header in re.findall(r'header "([^"\n]+)"', modulemap.read_text()):
            item = Path(header)
            paths.append(item if item.is_absolute() else modulemap.parent / item)
    return {str(path): hashlib.sha256(path.read_bytes()).hexdigest() for path in sorted(set(paths))}

def unchanged(snapshot):
    return all(Path(path).is_file() and hashlib.sha256(Path(path).read_bytes()).hexdigest() == value
               for path, value in snapshot.items())
