#!/usr/bin/env bash
#
# Lightweight, fixture-free regression test for linux/svtminion.sh's minion
# config-parsing logic (_update_minion_conf_ary /
# _fetch_vmtools_salt_minion_conf_guestvars /
# _fetch_vmtools_salt_minion_conf_tools_conf).
#
# Reproduces https://github.com/saltstack/salt-vmtools/issues/70: when the
# guestVar `vmware.components.salt_minion.args` (or a `tools.conf`
# `[salt_minion]` section) is populated with a raw CLI-argument string
# instead of the documented space-delimited `key=value` pairs, every
# whitespace-separated token -- switches, versions, URLs alike -- was being
# written to the minion config as a bogus self-mapped `token: token` entry.
#
# Like test_version_resolution.sh, this does not perform a real install and
# is not currently wired into CI (.github/workflows/test-linux.yml) -- it's
# meant to be run manually.
#
# Run directly: bash tests/linux/test_minion_conf_parsing.sh

set -o nounset
set -o errexit
set -o pipefail

_test_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_repo_root="$(cd "${_test_dir}/../.." && pwd)"
_script="${_repo_root}/linux/svtminion.sh"

# Stub the logging functions the functions under test depend on so they can
# run standalone without the rest of svtminion.sh's global state.
_error_log() { echo "ERROR: $*" 1>&2; }
_warning_log() { echo "WARNING: $*" 1>&2; }
_info_log() { :; }
_debug_log() { :; }

# guestvars_salt_args is normally a readonly global set up earlier in the
# real script; the function under test only reads it, so stub it here.
guestvars_salt_args="guestinfo.vmware.components.salt_minion.args"

# Extract the functions under test verbatim from the real script, so this
# test always exercises the current implementation rather than a
# hand-copied duplicate that could drift out of sync.
_extracted="$(mktemp)"
_fixture_dir="$(mktemp -d)"
trap 'rm -f "${_extracted}"; rm -rf "${_fixture_dir}"' EXIT

sed -n '/^_update_minion_conf_ary() {/,/^}/p' "${_script}" > "${_extracted}"
sed -n '/^_fetch_vmtools_salt_minion_conf_guestvars() {/,/^}/p' "${_script}" >> "${_extracted}"

# shellcheck disable=SC1090
source "${_extracted}"

_failed=0

# Mock `vmtoolsd --cmd "info-get ${guestvars_salt_args}"` the same way the
# real function invokes it.
vmtoolsd() {
    if [[ "$1" = "--cmd" && "$2" = "info-get ${guestvars_salt_args}" ]]; then
        echo "${_MOCK_GVAR_ARGS}"
        return 0
    fi
    return 1
}

_reset_conf_ary() {
    m_cfg_keys=()
    m_cfg_values=()
}

# --- Case 1: CLI-style switches leaking into the guestVar must not produce
# --- any bogus config entries (the reported bug).
_reset_conf_ary
_MOCK_GVAR_ARGS="--minionversion 3007.1 --source http://example.com/artifactory/saltproject-generic/onedir --loglevel debug"
_fetch_vmtools_salt_minion_conf_guestvars

if [[ ${#m_cfg_keys[@]} -ne 0 ]]; then
    echo "FAILED: CLI-style guestVar args produced ${#m_cfg_keys[@]} bogus config" \
        "entries (expected 0): ${m_cfg_keys[*]}"
    _failed=1
else
    echo "OK: CLI-style guestVar args produced no bogus config entries"
fi

# --- Case 2: legitimate key=value guestVar args must still work.
_reset_conf_ary
_MOCK_GVAR_ARGS="master=gv_master id=gv_minion"
_fetch_vmtools_salt_minion_conf_guestvars

_found_master=0
_found_id=0
for ((_i=0; _i<${#m_cfg_keys[@]}; _i++)); do
    if [[ "${m_cfg_keys[${_i}]}" = "master" && "${m_cfg_values[${_i}]}" = "gv_master" ]]; then
        _found_master=1
    fi
    if [[ "${m_cfg_keys[${_i}]}" = "id" && "${m_cfg_values[${_i}]}" = "gv_minion" ]]; then
        _found_id=1
    fi
done

if [[ ${_found_master} -ne 1 || ${_found_id} -ne 1 ]]; then
    echo "FAILED: valid key=value guestVar args were not parsed correctly:" \
        "keys='${m_cfg_keys[*]:-}' values='${m_cfg_values[*]:-}'"
    _failed=1
else
    echo "OK: valid key=value guestVar args parsed correctly"
fi

if [[ "${_failed}" -ne 0 ]]; then
    echo "test_minion_conf_parsing.sh: FAILED"
    exit 1
fi

echo "test_minion_conf_parsing.sh: All tests passed"
exit 0
