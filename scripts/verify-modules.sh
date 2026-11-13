#!/usr/bin/env bash
#
# Fails when a directory holding a pom.xml under apps/ or libs/ is not declared
# as a <module> of the root aggregator. Maven silently ignores undeclared
# directories, so the "one reactor, every module" guarantee needs its own check.
#
# Usage: scripts/verify-modules.sh
# Exit codes: 0 when every module directory is declared, 1 otherwise.

set -euo pipefail

# Resolve the repository root from this script's location so the check behaves
# the same no matter which directory Maven (or a human) launches it from.
repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"

# The Maven release inherits the plugin into every module, and exec runs with the
# module basedir as working directory. The execution passes that basedir as the
# first argument: only the aggregator runs the repository-wide check, the rest
# report the skip instead of repeating it.
module_basedir="${1:-}"
if [[ -n "${module_basedir}" ]]; then
  resolved_basedir="$(cd -- "${module_basedir}" && pwd)"
  if [[ "${resolved_basedir}" != "${repo_root}" ]]; then
    echo "verify-modules: skipped (aggregator-only check; module ${resolved_basedir})."
    exit 0
  fi
fi
root_pom="${repo_root}/pom.xml"

if [[ ! -f "${root_pom}" ]]; then
  echo "verify-modules: root pom not found at ${root_pom}" >&2
  exit 1
fi

# Declared modules: the <module> entries of the root aggregator. Only the
# <modules> block is read, so prose mentioning <module> in a comment is never
# mistaken for a declaration. Trailing slashes and ./ prefixes are normalised
# because Maven accepts both forms.
declared=()
while IFS= read -r module; do
  [[ -n "${module}" ]] || continue
  module="${module#./}"
  module="${module%/}"
  declared+=("${module}")
done < <(
  awk '
    /<modules[ >]/ { inside = 1 }
    inside { printf "%s ", $0 }
    /<\/modules>/ { inside = 0 }
  ' "${root_pom}" \
    | grep -o '<module>[^<]*</module>' \
    | sed -e 's:<module>::' -e 's:</module>::' -e 's/[[:space:]]//g' \
    | sort -u || true
)

# Candidate directories: any directory holding a pom.xml under the scanned
# roots, expressed relative to the repository root. apps/web-frontend has no
# pom.xml on purpose, so it never shows up here.
candidates=()
for scan_root in apps libs; do
  [[ -d "${repo_root}/${scan_root}" ]] || continue
  while IFS= read -r pom; do
    relative="${pom#"${repo_root}/"}"
    candidates+=("${relative%/pom.xml}")
  done < <(find "${repo_root}/${scan_root}" -type f -name pom.xml | sort)
done

# Compare both sets: a directory present on disk but missing from <modules> is
# a build lie, so it must be reported by name.
undeclared=()
for directory in "${candidates[@]:-}"; do
  [[ -n "${directory}" ]] || continue
  found=false
  for module in "${declared[@]:-}"; do
    [[ -n "${module}" ]] || continue
    if [[ "${module}" == "${directory}" ]]; then
      found=true
      break
    fi
  done
  if [[ "${found}" == false ]]; then
    undeclared+=("${directory}")
  fi
done

if (( ${#undeclared[@]} > 0 )); then
  echo "verify-modules: directories with a pom.xml but no <module> entry in pom.xml:" >&2
  printf '  - %s\n' "${undeclared[@]}" >&2
  echo "Declare each one in <modules> or move it out of apps/ and libs/." >&2
  exit 1
fi

echo "verify-modules: OK (${#candidates[@]} module directories found, ${#declared[@]} declared)."
