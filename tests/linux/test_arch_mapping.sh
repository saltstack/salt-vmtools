#!/usr/bin/env bash
#
# Lightweight regression test for linux/svtminion.sh's mapping from uname -m
# to Salt onedir package arch tokens (_map_salt_onedir_arch).
#
# Run directly: bash tests/linux/test_arch_mapping.sh

set -o pipefail

_test_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_repo_root="$(cd "${_test_dir}/../.." && pwd)"
_script="${_repo_root}/linux/svtminion.sh"

_extracted="$(mktemp)"
trap 'rm -f "${_extracted}"' EXIT

if ! sed -n '/^_map_salt_onedir_arch() {/,/^}/p' "${_script}" > "${_extracted}" \
    || ! grep -q '^_map_salt_onedir_arch() {' "${_extracted}"; then
    echo "FAILED: unable to extract _map_salt_onedir_arch from ${_script}"
    exit 1
fi

# shellcheck disable=SC1090
source "${_extracted}"

_failed=0

_assert_maps_to() {
    local input="$1"
    local expected="$2"
    local label="$3"
    local got

    if ! got=$(_map_salt_onedir_arch "${input}"); then
        echo "FAILED: ${label} -- mapping '${input}' returned non-zero"
        _failed=1
        return
    fi
    if [[ "${got}" != "${expected}" ]]; then
        echo "FAILED: ${label} -- expected '${expected}', got '${got}'"
        _failed=1
        return
    fi
    echo "OK: ${label} -- '${input}' -> '${expected}'"
}

_assert_rejects() {
    local input="$1"
    local label="$2"

    if _map_salt_onedir_arch "${input}" >/dev/null 2>&1; then
        echo "FAILED: ${label} -- mapping '${input}' should fail"
        _failed=1
        return
    fi
    echo "OK: ${label} -- '${input}' rejected"
}

_assert_maps_to "x86_64" "x86_64" "x86_64 host"
_assert_maps_to "aarch64" "arm64" "aarch64 host"
_assert_maps_to "arm64" "arm64" "arm64 host"
_assert_rejects "i686" "unsupported i686"
_assert_rejects "ppc64le" "unsupported ppc64le"
_assert_rejects "" "empty arch"

if [[ "${_failed}" -ne 0 ]]; then
    echo "test_arch_mapping.sh: FAILED"
    exit 1
fi

echo "test_arch_mapping.sh: All tests passed"
exit 0
