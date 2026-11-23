#!/usr/bin/env bash
# Guards the architecture rules from AGENTS.md that do not need a Dart SDK:
#  1. domain/ must not import data/, features/, providers/ or Flutter material;
#  2. data/ and providers/ must not import features/;
#  3. no feature may import another feature's presentation layer directly
#     (public controllers are allowed);
#  4. no hardcoded colours outside the theme directory;
#  5. services/ stays UI-free and independent of features/ (AGENTS.md §3.1).
set -uo pipefail

cd "$(dirname "$0")/.."
fail=0

report() { echo "✗ $1"; fail=1; }

# 1. domain purity
if grep -rnE "import 'package:(mellow/(data|features|providers)|flutter/material)" lib/domain; then
  report "domain/ imports an outer layer"
fi

# 2. data & providers must not depend on features
if grep -rn "import 'package:mellow/features/" lib/data lib/providers; then
  report "data/ or providers/ imports features/"
fi

# 3. features may share application/ but never presentation/ of another feature
while IFS= read -r line; do
  file="${line%%:*}"
  target="${line#*import \'}"; target="${target%%\'*}"
  owner=$(echo "$file" | cut -d/ -f3)
  dep=$(echo "$target" | cut -d/ -f3)
  case "$target" in
    */presentation/*)
      if [ "$owner" != "$dep" ]; then
        echo "✗ $file imports the presentation layer of $dep"
        fail=1
      fi
      ;;
  esac
done < <(grep -rn "import 'package:mellow/features/" lib/features || true)

# 4. colour literals outside core/theme
if grep -rnE "Color\(0x" lib --include="*.dart" | grep -v "lib/core/theme/"; then
  report "hardcoded Color(0x...) outside core/theme"
fi

# 5. services/ must stay runnable outside the widget tree
if grep -rnE "import 'package:(mellow/features|flutter/(material|cupertino|widgets))" lib/services; then
  report "services/ imports Flutter UI or a feature"
fi

if [ "$fail" -eq 0 ]; then
  echo "✓ architecture rules hold"
fi
exit "$fail"
