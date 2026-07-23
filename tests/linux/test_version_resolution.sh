#!/usr/bin/env bash
#
# Lightweight, fixture-free regression test for linux/svtminion.sh's Salt
# version resolution logic (_salt_onedir_dir_is_ga / _get_desired_salt_version_fn).
#
# Unlike test-linux.sh, this does not perform a real install and needs no
# onedir tarball fixtures -- it extracts the two functions under test
# directly from the real script and exercises them against a directory of
# zero-byte stub files, so it only tests directory-name resolution logic
# (GA classification, latest/major-series selection, exact-name lookup),
# not extraction or installation.
#
# Run directly: bash tests/linux/test_version_resolution.sh

set -o nounset
set -o errexit
set -o pipefail

_test_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_repo_root="$(cd "${_test_dir}/../.." && pwd)"
_script="${_repo_root}/linux/svtminion.sh"

# Stub the logging functions _get_desired_salt_version_fn depends on so it
# can run standalone without the rest of svtminion.sh's global state.
_error_log() { echo "ERROR: $*" 1>&2; }
_info_log() { :; }
_debug_log() { :; }

# Extract the two functions under test verbatim from the real script, so
# this test always exercises the current implementation rather than a
# hand-copied duplicate that could drift out of sync.
_extracted="$(mktemp)"
trap 'rm -f "${_extracted}"' EXIT

sed -n '/^_salt_onedir_dir_is_ga() {/,/^}/p' "${_script}" > "${_extracted}"
sed -n '/^_get_desired_salt_version_fn() {/,/^}/p' "${_script}" >> "${_extracted}"

# shellcheck disable=SC1090
source "${_extracted}"

_fixture_dir="$(mktemp -d)"
trap 'rm -rf "${_fixture_dir}"; rm -f "${_extracted}"' EXIT

for v in "3008.0rc1" "3008.1" "3008.1-1" "3007.9"; do
    touch "${_fixture_dir}/${v}"
done

_failed=0

_assert_resolves_to() {
    local requested="$1"
    local expected="$2"
    local label="$3"

    salt_url_version="${requested}"
    _GENERIC_PKG_VERSION=""
    salt_specific_version=""

    if ! _get_desired_salt_version_fn "${_fixture_dir}"; then
        echo "FAILED: ${label} -- _get_desired_salt_version_fn returned non-zero for '${requested}'"
        _failed=1
        return
    fi

    if [ "${salt_specific_version}" != "${expected}" ]; then
        echo "FAILED: ${label} -- requested '${requested}', expected '${expected}', got '${salt_specific_version}'"
        _failed=1
    else
        echo "OK: ${label} -- '${requested}' resolved to '${expected}'"
    fi
}

# latest / major-series resolution must prefer the newest GA build,
# including a -N repackage of a version that also exists without the suffix.
_assert_resolves_to "latest" "3008.1-1" "latest picks -N repackage over bare version"
_assert_resolves_to "3008" "3008.1-1" "major-series picks -N repackage over bare version"

# Exact-name request for a prerelease still works (unchanged RC behavior).
_assert_resolves_to "3008.0rc1" "3008.0rc1" "exact RC request"

# Exact-name request for a -N build works.
_assert_resolves_to "3008.1-1" "3008.1-1" "exact -N request"

# Mere-presence check: requesting an unrelated version must not fail/crash
# just because -N and rc directories exist alongside it in the listing.
# This is the same failure mode that previously broke RC handling before
# GA classification distinguished "present" from "requested".
_assert_resolves_to "3007.9" "3007.9" "mere presence of -N/rc does not break unrelated exact request"

if [ "${_failed}" -ne 0 ]; then
    echo "test_version_resolution.sh: FAILED"
    exit 1
fi

echo "test_version_resolution.sh: All tests passed"
exit 0
