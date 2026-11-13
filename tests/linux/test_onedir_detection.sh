#!/usr/bin/env bash
#
# Lightweight, fixture-free regression test for linux/svtminion.sh's detection
# of an installed onedir salt-minion (_check_onedir_minion_install) and its
# lookup of the running salt-minion process (_find_salt_pid).
#
# The functions under test are extracted verbatim from the real script. The
# onedir location is redirected to a temporary directory and pgrep is mocked,
# so this does not need root, a Salt installation or a running minion.
#
# Run directly: bash tests/linux/test_onedir_detection.sh

set -o pipefail

_test_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_repo_root="$(cd "${_test_dir}/../.." && pwd)"
_script="${_repo_root}/linux/svtminion.sh"

_work_dir="$(mktemp -d)"
_extracted="${_work_dir}/extracted.sh"
trap 'rm -rf "${_work_dir}"' EXIT

_error_log() { echo "ERROR: $*" 1>&2; }
_info_log() { :; }
_debug_log() { :; }

# Extract what is under test verbatim from the real script
for _fn in _check_onedir_minion_install _find_salt_pid; do
    if ! sed -n "/^${_fn} *() {/,/^}/p" "${_script}" >> "${_extracted}" \
        || ! grep -q "^${_fn} *() {" "${_extracted}"; then
        echo "FAILED: unable to extract ${_fn} from ${_script}"
        exit 1
    fi
done
# shellcheck disable=SC1090
source "${_extracted}"

# Constants from the real script, with the install location redirected to a
# temporary directory
_fake_base="${_work_dir}/opt/saltstack"
eval "$(grep -E '^(readonly (salt_name|base_salt_location|salt_dir|onedir_[a-z0-9_]+_location)=|declare -a list_of_onedir_locations_check|list_of_onedir_locations_check\[[0-9]+\]=)' \
    "${_script}" | sed "s|\"/opt/saltstack\"|\"${_fake_base}\"|; s|^readonly ||")"

_failed=0

_assert_eq() {
    local name="$1" expected="$2" actual="$3"
    if [[ "${actual}" == "${expected}" ]]; then
        echo "PASS: ${name}"
    else
        echo "FAIL: ${name}: expected '${expected}', got '${actual}'"
        _failed=1
    fi
}

_reset_install() { rm -rf "${_fake_base}"; mkdir -p "${salt_dir}"; }

# --- _check_onedir_minion_install ---

_reset_install
_assert_eq "no onedir installed returns 0" "0" \
    "$(_check_onedir_minion_install)"

_reset_install
touch "${salt_dir}/salt-minion"
_assert_eq "salt/salt-minion (3006 and later layout) returns 2" "2" \
    "$(_check_onedir_minion_install)"

_reset_install
mkdir -p "${salt_dir}/run"
touch "${salt_dir}/run/run"
_assert_eq "salt/run/run (pre-3006 layout) is still detected, returns 1" "1" \
    "$(_check_onedir_minion_install)"

_reset_install
mkdir -p "${salt_dir}/run"
touch "${salt_dir}/run/run" "${salt_dir}/salt-minion"
_assert_eq "both layouts present, run/run takes precedence" "1" \
    "$(_check_onedir_minion_install)"

# --- _find_salt_pid ---

# mock pgrep: record the pattern searched for, and report a pid
pgrep() {
    echo "${2}" > "${_work_dir}/pgrep_pattern"
    echo "4242"
}

_assert_eq "minion pid found" "4242" "$(_find_salt_pid)"
_assert_eq "pid lookup matches /usr/bin/salt-minion" "1" \
    "$(grep -c -F '\/usr\/bin\/salt-minion' "${_work_dir}/pgrep_pattern")"
_assert_eq "pid lookup matches salt/run/run minion (pre-3006)" "1" \
    "$(grep -c -F 'salt\/run\/run minion' "${_work_dir}/pgrep_pattern")"

# no process running
pgrep() { return 1; }
_assert_eq "no minion process returns empty" "" "$(_find_salt_pid)"

if [[ ${_failed} -ne 0 ]]; then
    echo "FAILED"
    exit 1
fi
echo "ALL PASSED"
