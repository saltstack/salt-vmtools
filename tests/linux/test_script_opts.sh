#!/usr/bin/env bash
#
# Lightweight, fixture-free test for linux/svtminion.sh's handling of script
# options set using key=value (source, minionversion, loglevel) in the
# VMTools guest variables, tools.conf and on the command line.
#
# The functions under test are extracted verbatim from the real script, with
# vmtoolsd mocked and tools.conf in a temporary directory. This does not
# perform an install. The same scenarios are tested for the Windows script in
# tests/windows/functional/test_script_options.ps1, keep them in step.
#
# Run directly: bash tests/linux/test_script_opts.sh

set -o pipefail

_test_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_repo_root="$(cd "${_test_dir}/../.." && pwd)"
_script="${_repo_root}/linux/svtminion.sh"

_work_dir="$(mktemp -d)"
_extracted="${_work_dir}/extracted.sh"
trap 'rm -rf "${_work_dir}"' EXIT

# Stub the logging functions. _error_log is like the real one, it only exits
# with 126 when errors are being logged, which is not the case when silent
_error_log() {
    echo "ERROR: $*" 1>&2
    if [[ ${LOG_LEVELS_ARY[error]} -le ${LOG_LEVEL} ]]; then exit 126; fi
}
_warning_log() { echo "WARNING: $*" 1>&2; }
_info_log() { :; }
_debug_log() { :; }

# Extract what is under test verbatim from the real script
for _fn in _is_script_opt_key _split_tokens _parse_kv_token \
    _update_minion_conf_ary _read_tools_conf_salt_minion_lines \
    _fetch_vmtools_salt_minion_conf_tools_conf \
    _fetch_vmtools_salt_minion_conf_guestvars \
    _fetch_vmtools_salt_minion_conf_cli_args _get_desired_state \
    _collect_script_opts _fetch_script_opts _validate_loglevel_param \
    _apply_script_opts _set_log_level _validate_source_param \
    _validate_minion_version_param _source_fn \
    _set_install_minion_version_fn _validation_failed; do
    if ! sed -n "/^${_fn} *() {/,/^}/p" "${_script}" >> "${_extracted}" \
        || ! grep -q "^${_fn} *() {" "${_extracted}"; then
        echo "FAILED: unable to extract ${_fn} from ${_script}"
        exit 1
    fi
done
# shellcheck disable=SC1090
source "${_extracted}"

# constants from the real script
eval "$(grep -E '^readonly (script_opt_keys|LOG_MODES_AVAILABLE)=' "${_script}")"
declare -A LOG_LEVELS_ARY STATUS_CODES_ARY
STATUS_CODES_ARY[scriptFailed]=126
LOG_LEVELS_ARY[silent]=0
LOG_LEVELS_ARY[error]=1
LOG_LEVELS_ARY[warning]=2
LOG_LEVELS_ARY[info]=3
LOG_LEVELS_ARY[debug]=4
vmtools_base_dir_etc="${_work_dir}/etc"
vmtools_conf_file="tools.conf"
vmtools_salt_minion_section_name="salt_minion"
guestvars_salt_args="guestinfo./vmware.components.salt_minion.args"
guestvars_salt_desiredstate="guestinfo./vmware.components.salt_minion.desiredstate"
default_salt_url_version="latest"
mkdir -p "${vmtools_base_dir_etc}"

# Mock `vmtoolsd --cmd "info-get <var>"`
vmtoolsd() {
    if [[ "$1" = "--cmd" && "$2" = "info-get ${guestvars_salt_args}" ]]; then
        echo "${_MOCK_ARGS}"
        return 0
    fi
    if [[ "$1" = "--cmd" && "$2" = "info-get ${guestvars_salt_desiredstate}" ]]
    then
        echo "${_MOCK_STATE}"
        return 0
    fi
    return 1
}

# Reset all the state the functions use
_new_env() {
    LOG_LEVEL=2
    LOG_ACTION="default"
    STATUS_CHK=0 DEPS_CHK=0 SOURCE_FLAG=0 MINION_VERSION_FLAG=0 UPGRADE_FLAG=0
    CLEAR_ID_KEYS_FLAG=0 UNINSTALL_FLAG=0 VERSION_FLAG=0 RECONFIG_FLAG=0
    STOP_FLAG=0 RESTART_FLAG=0 LOG_LEVEL_FLAG=0 INSTALL_FLAG=0
    INSTALL_PARAMS="" RECONFIG_PARAMS="" SOURCE_PARAMS=""
    base_url="" salt_url_version="latest"
    GVAR_ACTION_FETCHED=0 GVAR_ACTION=""
    m_cfg_keys=() m_cfg_values=()
    _MOCK_ARGS="" _MOCK_STATE=""
    rm -f "${vmtools_base_dir_etc}/${vmtools_conf_file}"
}

_tools_conf() {
    printf '[other]\nsource=https://wrong.example.com/onedir\n[salt_minion]\n%s\n[after]\nsource=https://wrong.example.com/onedir\n' \
        "$1" > "${vmtools_base_dir_etc}/${vmtools_conf_file}"
}

# Result of applying the script options
_applied() {
    echo "src=${base_url} ver=${salt_url_version} lvl=${LOG_LEVEL}" \
        "act=${LOG_ACTION} cli=${CLI_ACTION:-unset}"
}

# Result of reading minion configuration from all three sources
_minion_conf() {
    m_cfg_keys=() m_cfg_values=()
    _fetch_vmtools_salt_minion_conf_guestvars
    _fetch_vmtools_salt_minion_conf_tools_conf
    _fetch_vmtools_salt_minion_conf_cli_args "${INSTALL_PARAMS}"
    local i
    for ((i=0; i<${#m_cfg_keys[@]}; i++)); do
        echo -n "${m_cfg_keys[i]}=${m_cfg_values[i]};"
    done
}

_failed=0

# _check <name> <expected exit code> <expected output> <command...>
_check() {
    local name="$1" want_rc="$2" want_out="$3" out="" rc=0
    shift 3
    out=$( ("$@") 2>/dev/null ); rc=$?
    if [[ ${rc} -ne ${want_rc} || "${out}" != "${want_out}" ]]; then
        echo "FAILED: ${name}"
        echo "    expected rc=${want_rc} output '${want_out}'"
        echo "    actual   rc=${rc} output '${out}'"
        _failed=1
    else
        echo "OK: ${name}"
    fi
}

_t_gv_only() {
    _new_env; INSTALL_FLAG=1
    _MOCK_ARGS="master=m source=https://gv.example.com/onedir minionversion=3006.8 loglevel=debug"
    _apply_script_opts; _applied
}
_check "1. all options picked up from guest variables" 0 \
    "src=https://gv.example.com/onedir ver=3006.8 lvl=4 act=install cli=unset" _t_gv_only

_t_tc_over_gv() {
    _new_env; INSTALL_FLAG=1
    _MOCK_ARGS="source=https://gv.example.com/onedir loglevel=info"
    _tools_conf "source=https://tc.example.com/onedir"
    _apply_script_opts; _applied
}
_check "2a. tools.conf beats guest variables (only for keys it sets)" 0 \
    "src=https://tc.example.com/onedir ver=latest lvl=3 act=install cli=unset" _t_tc_over_gv

_t_cli_over_tc() {
    _new_env; INSTALL_FLAG=1
    _MOCK_ARGS="source=https://gv.example.com/onedir"
    _tools_conf "source=https://tc.example.com/onedir"
    INSTALL_PARAMS="source=https://cli.example.com/onedir"
    _apply_script_opts; _applied
}
_check "2b. command line key=value beats tools.conf" 0 \
    "src=https://cli.example.com/onedir ver=latest lvl=2 act=install cli=unset" _t_cli_over_tc

_t_switch_over_token() {
    _new_env; INSTALL_FLAG=1 SOURCE_FLAG=1 LOG_LEVEL_FLAG=1 MINION_VERSION_FLAG=1
    SOURCE_PARAMS="https://switch.example.com/onedir"
    INSTALL_PARAMS="source=https://cli.example.com/onedir minionversion=3007 loglevel=debug"
    _apply_script_opts; _applied
}
_check "2c. explicit switches are not overridden by key=value" 0 \
    "src= ver=latest lvl=2 act=default cli=unset" _t_switch_over_token

_t_minion_conf() {
    _new_env
    _MOCK_ARGS="master=m source=https://gv.example.com/onedir loglevel=debug"
    _tools_conf $'id=tcid\nMinionVersion=3006'
    INSTALL_PARAMS="log_level=trace Source=https://cli.example.com/onedir --loglevel debug"
    _minion_conf
}
_check "3. script options never reach the minion config" 0 \
    "master=m;id=tcid;log_level=trace;" _t_minion_conf

_t_cli_one_arg() {
    _new_env; INSTALL_FLAG=1
    INSTALL_PARAMS="master=m source=https://cli.example.com/onedir --loglevel debug"
    _apply_script_opts; _applied
}
_check "4a. command line tokens as one argument" 0 \
    "src=https://cli.example.com/onedir ver=latest lvl=2 act=install cli=unset" _t_cli_one_arg

_t_cli_several() {
    _new_env; INSTALL_FLAG=1
    # as _install_fn is given them, "$*" of several arguments
    set -- master=m source=https://cli.example.com/onedir minionversion=3007.1
    INSTALL_PARAMS="$*"
    _apply_script_opts; _applied
}
_check "4b. command line tokens as several arguments" 0 \
    "src=https://cli.example.com/onedir ver=3007.1 lvl=2 act=install cli=unset" _t_cli_several

_t_cli_after_switch() {
    _new_env; INSTALL_FLAG=1
    INSTALL_PARAMS="master=m --loglevel debug source=https://evil.example.com/onedir"
    _apply_script_opts; _applied
}
_check "4c. tokens after the next switch are not read" 0 \
    "src= ver=latest lvl=2 act=default cli=unset" _t_cli_after_switch

_t_invalid() {
    _new_env; INSTALL_FLAG=1; _MOCK_ARGS="$1"
    _apply_script_opts; _applied
}
_check "5a. invalid source scheme exits 126" 126 "" _t_invalid "source=ftp:/bad"
_check "5b. invalid source characters exits 126" 126 "" _t_invalid "source=http://x/a;id"
_check "5c. invalid minionversion exits 126" 126 "" _t_invalid "minionversion=abc"
_check "5d. invalid loglevel exits 126" 126 "" _t_invalid "loglevel=loud"

_t_equals() {
    _new_env; INSTALL_FLAG=1
    _MOCK_ARGS="master=a=b source=https://h.example.com/onedir?a=b"
    _apply_script_opts; _applied; _minion_conf
}
_check "6. value containing = is preserved" 0 \
    "src=https://h.example.com/onedir?a=b ver=latest lvl=2 act=install cli=unset
master=a=b;" _t_equals

_t_tokens() {
    _new_env
    mkdir -p "${_work_dir}/glob"; cd "${_work_dir}/glob" || return 1
    touch "master=foo" "idx"
    _MOCK_ARGS=$'master=* id=x empty= bad=a\x01b noequals'
    _minion_conf
}
_check "7. no globbing; control chars, empty values and non key=value ignored" 0 \
    "master=*;id=x;" _t_tokens

_t_case() {
    _new_env; INSTALL_FLAG=1
    _MOCK_ARGS="Source=https://gv.example.com/onedir MINIONVERSION=3006 LOGLEVEL=DEBUG"
    _apply_script_opts; _applied
}
_check "8. keys and loglevel are not case sensitive" 0 \
    "src=https://gv.example.com/onedir ver=3006 lvl=4 act=install cli=unset" _t_case

_t_status() {
    _new_env; STATUS_CHK=1
    _MOCK_ARGS="source=https://gv.example.com/onedir minionversion=3006 loglevel=debug"
    _apply_script_opts; _applied
}
_check "9. non install action ignores source and minionversion, honors loglevel" 0 \
    "src= ver=latest lvl=4 act=default cli=unset" _t_status

_t_old_vmtools() {
    _new_env; INSTALL_FLAG=1 SOURCE_FLAG=1 LOG_LEVEL_FLAG=1
    SOURCE_PARAMS="https://switch.example.com/onedir"
    INSTALL_PARAMS="master=m --loglevel debug --source https://switch.example.com/onedir"
    _apply_script_opts; _applied
}
_check "10. switches on the command line (current VMTools) still work" 0 \
    "src= ver=latest lvl=2 act=default cli=unset" _t_old_vmtools

_t_legacy() {
    _new_env; INSTALL_FLAG=1
    _MOCK_ARGS="--source https://legacy.example.com/onedir master=m"
    _apply_script_opts; _applied; _minion_conf
}
_check "11. legacy --source in guest variables is ignored" 0 \
    "src= ver=latest lvl=2 act=default cli=unset
master=m;" _t_legacy

_t_desired_present() {
    _new_env
    _MOCK_STATE="present"
    _MOCK_ARGS="source=https://gv.example.com/onedir"
    _apply_script_opts; _applied
}
_check "12a. desired state present: source applied, CLI_ACTION untouched" 0 \
    "src=https://gv.example.com/onedir ver=latest lvl=2 act=install cli=unset" _t_desired_present

_t_desired_absent() {
    _new_env
    _MOCK_STATE="absent"
    _MOCK_ARGS="source=https://gv.example.com/onedir"
    _apply_script_opts; _applied
}
_check "12b. desired state absent: source ignored" 0 \
    "src= ver=latest lvl=2 act=default cli=unset" _t_desired_absent

_t_tc_filtering() {
    _new_env
    _tools_conf $'master=m\nid=\nbad=a\x01b\nnoequals\n=novalue\nsource=https://tc.example.com/onedir'
    _minion_conf; _fetch_script_opts; echo "src=${SCRIPT_OPT_source}"
}
_check "13. tools.conf: control chars, empty values and non key=value ignored, sections respected" 0 \
    "master=m;src=https://tc.example.com/onedir" _t_tc_filtering

_t_tc_missing() {
    _new_env
    _fetch_script_opts; _read_tools_conf_salt_minion_lines
    echo "src=${SCRIPT_OPT_source} lines=${#TOOLS_CONF_LINES[@]} exists=$([[ -f ${vmtools_base_dir_etc}/${vmtools_conf_file} ]] && echo yes || echo no)"
}
_check "14. missing tools.conf is not an error and is not created when reading options" 0 \
    "src= lines=0 exists=no" _t_tc_missing

_t_parse_kv() {
    local tok rc
    for tok in "a=b" "a=b=c" "a=" "=b" "ab" $'a=b\x01' ""; do
        _parse_kv_token "${tok}" ""; rc=$?
        echo -n "${rc}:${KV_KEY}|${KV_VALUE};"
    done
}
_check "15. _parse_kv_token return codes and first = split" 0 \
    "0:a|b;0:a|b=c;1:|;1:|;1:|;1:|;1:|;" _t_parse_kv

_t_split_noglob() {
    local before after
    set +f; _split_tokens "a* b"; echo -n "off->$([[ $- == *f* ]] && echo on || echo off) ${#SPLIT_TOKENS[@]};"
    set -f; _split_tokens "a* b"; echo -n "on->$([[ $- == *f* ]] && echo on || echo off) ${#SPLIT_TOKENS[@]};"
    set +f
}
_check "16. _split_tokens keeps the caller's globbing setting" 0 \
    "off->off 2;on->on 2;" _t_split_noglob

_t_is_key() {
    local k
    for k in source Source MINIONVERSION loglevel log_level master sources ""; do
        _is_script_opt_key "${k}"; echo -n "${k}:$?;"
    done
}
_check "17. _is_script_opt_key matches only the three keys, any case" 0 \
    "source:0;Source:0;MINIONVERSION:0;loglevel:0;log_level:1;master:1;sources:1;:1;" _t_is_key

_t_gv_dup_last_wins() {
    _new_env; INSTALL_FLAG=1
    _MOCK_ARGS="source=https://first.example.com/onedir source=https://last.example.com/onedir"
    _apply_script_opts; _applied
}
_check "18. last duplicate key wins within a source" 0 \
    "src=https://last.example.com/onedir ver=latest lvl=2 act=install cli=unset" _t_gv_dup_last_wins

_t_reconfig_tokens() {
    _new_env; RECONFIG_FLAG=1
    RECONFIG_PARAMS="loglevel=debug source=https://cli.example.com/onedir"
    _apply_script_opts; _applied
}
_check "19. --reconfig: key=value read, loglevel applied, source ignored" 0 \
    "src= ver=latest lvl=4 act=default cli=unset" _t_reconfig_tokens

_t_upgrade() {
    _new_env; INSTALL_FLAG=1 UPGRADE_FLAG=1
    _MOCK_ARGS="source=https://gv.example.com/onedir minionversion=3007.1"
    _apply_script_opts; _applied
}
_check "20. --install --upgrade: source and minionversion applied" 0 \
    "src=https://gv.example.com/onedir ver=3007.1 lvl=2 act=install cli=unset" _t_upgrade

# --- An invalid value must be rejected whatever the log level, including silent
_t_silent_invalid() {
    _new_env; INSTALL_FLAG=1; _MOCK_ARGS="$1"
    _apply_script_opts; _applied
}
_check "21a. loglevel=silent does not let an invalid source through" 126 "" \
    _t_silent_invalid "loglevel=silent source=http://x/a;id"
_check "21b. loglevel=silent does not let an invalid source scheme through" 126 "" \
    _t_silent_invalid "loglevel=silent source=ftp:/bad"
_check "21c. loglevel=silent does not let an invalid minionversion through" 126 "" \
    _t_silent_invalid "loglevel=silent minionversion=abc"
_check "21d. loglevel=silent with valid values still works" 0 \
    "src=https://ok.example.com/onedir ver=3007.1 lvl=0 act=install cli=unset" \
    _t_silent_invalid "loglevel=silent source=https://ok.example.com/onedir minionversion=3007.1"

_t_silent_validators() {
    _new_env; LOG_LEVEL=0
    "$@"
    echo "returned"
}
_check "22a. _validate_source_param exits 126 when silent" 126 "" \
    _t_silent_validators _validate_source_param "http://x/a;id"
_check "22b. _validate_minion_version_param exits 126 when silent" 126 "" \
    _t_silent_validators _validate_minion_version_param "abc"
_check "22c. _validate_loglevel_param exits 126 when silent" 126 "" \
    _t_silent_validators _validate_loglevel_param "loud"
_check "22d. valid values return when silent" 0 "returned" \
    _t_silent_validators _validate_source_param "https://ok.example.com/onedir"

# --- tools.conf is read the same as the Windows script reads it
_t_tc_spaces() {
    _new_env; INSTALL_FLAG=1
    _tools_conf $'source = https://tc.example.com/onedir\n  loglevel =  error  \n\tmaster\t=\tm\r'
    _apply_script_opts; _applied; _minion_conf
}
_check "23. tools.conf: white space around the line, key and value is ignored" 0 \
    "src=https://tc.example.com/onedir ver=latest lvl=1 act=install cli=unset
master=m;" _t_tc_spaces

_t_tc_comments() {
    _new_env; INSTALL_FLAG=1
    _tools_conf $'# source=https://comment.example.com/onedir\n; minionversion=3007\n, loglevel=debug\nid=x'
    _apply_script_opts; _applied; _minion_conf
}
_check "24. tools.conf: comment lines are ignored" 0 \
    "src= ver=latest lvl=2 act=default cli=unset
id=x;" _t_tc_comments

_t_tc_crlf() {
    _new_env; INSTALL_FLAG=1
    printf '[salt_minion]\r\nsource=https://crlf.example.com/onedir\r\nmaster=m\r\n[other]\r\nsource=https://wrong.example.com/onedir\r\n' \
        > "${vmtools_base_dir_etc}/${vmtools_conf_file}"
    _apply_script_opts; _applied; _minion_conf
}
_check "25. tools.conf with CRLF line endings" 0 \
    "src=https://crlf.example.com/onedir ver=latest lvl=2 act=install cli=unset
master=m;" _t_tc_crlf

_t_tc_value_equals() {
    _new_env
    _tools_conf $'master = a=b'
    _minion_conf
}
_check "26. tools.conf: value with = after white space is kept" 0 \
    "master=a=b;" _t_tc_value_equals

if [[ "${_failed}" -ne 0 ]]; then
    echo "test_script_opts.sh: FAILED"
    exit 1
fi

echo "test_script_opts.sh: All tests passed"
exit 0
