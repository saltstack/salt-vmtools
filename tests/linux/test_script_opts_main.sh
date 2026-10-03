#!/usr/bin/env bash
#
# Test the MAIN section of linux/svtminion.sh with script options set using
# key=value (source, minionversion, loglevel), see test_script_opts.sh for the
# unit tests of the functions.
#
# A copy of the real script is built where the action functions (install,
# remove, status, ...) just report what they were given. vmtoolsd is the stand-in
# executable in tests/linux/fake_bin, found through PATH like the real one, so
# the script runs it and reads its output and exit code the way it does for real.
# The log directory and tools.conf directory are moved to a temporary directory.
# Everything else, including the argument parsing and MAIN flow that decides
# which action runs, is the real code. This does not perform an install.
#
# Run directly: bash tests/linux/test_script_opts_main.sh

set -o pipefail

_test_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_repo_root="$(cd "${_test_dir}/../.." && pwd)"
_script="${_repo_root}/linux/svtminion.sh"

_work_dir="$(mktemp -d)"
trap 'rm -rf "${_work_dir}"' EXIT
mkdir -p "${_work_dir}/etc"

_built="${_work_dir}/svtminion_test.sh"
_marker='^################################### MAIN'

# Stubs for everything that would change the system
cat > "${_work_dir}/stubs.sh" <<'EOF'
_report() {
    echo "ACTION:$1 src=${base_url} ver=${salt_url_version}" \
        "lvl=${LOG_LEVEL} act=${LOG_ACTION}"
    return 0
}
_install_fn() { _report install; }
_uninstall_fn() { _report remove; }
_status_fn() { _report status; }
_deps_chk_fn() { _report depend; }
_reconfig_fn() { _report reconfig; }
_clean_up_log_files() { :; }
EOF

_line=$(grep -n "${_marker}" "${_script}" | cut -d: -f1)
if [[ -z "${_line}" ]]; then
    echo "FAILED: unable to find the MAIN section in ${_script}"
    exit 1
fi
{
    head -n $((_line - 1)) "${_script}" \
        | sed -e "s#^readonly log_dir=.*#log_dir=\"${_work_dir}/log\"#" \
              -e "s#^readonly vmtools_base_dir_etc=.*#vmtools_base_dir_etc=\"${_work_dir}/etc\"#"
    cat "${_work_dir}/stubs.sh"
    tail -n +"${_line}" "${_script}"
} > "${_built}"
if ! grep -q "^log_dir=\"${_work_dir}" "${_built}" \
    || ! grep -q "^vmtools_base_dir_etc=\"${_work_dir}" "${_built}"; then
    echo "FAILED: unable to move the log and tools.conf directories"
    exit 1
fi

_failed=0

# _run <args mock> <desired state mock> <expected rc> <expected output> <args...>
# The stand-in vmtoolsd, found through PATH like the real one
_fake_bin="${_test_dir}/fake_bin"
chmod +x "${_fake_bin}/vmtoolsd"

# _run <args guest variable> <desired state guest variable> <expected rc>
#      <expected output> <script args...>
# A guest variable of <unset> is not set, so reading it fails like it does on a
# host that did not set it. "" is set to an empty value.
_run() {
    local mock_args="$1" mock_state="$2" want_rc="$3" want_out="$4" out="" rc=0
    local -a gv_env=()
    shift 4
    if [[ "${mock_args}" != "<unset>" ]]; then gv_env+=( "FAKE_GV_ARGS=${mock_args}" ); fi
    if [[ "${mock_state}" != "<unset>" ]]; then gv_env+=( "FAKE_GV_STATE=${mock_state}" ); fi
    out=$(env -u FAKE_GV_ARGS -u FAKE_GV_STATE "${gv_env[@]}" \
        PATH="${_fake_bin}:${PATH}" bash "${_built}" "$@" 2>/dev/null); rc=$?
    if [[ ${rc} -ne ${want_rc} || "${out}" != "${want_out}" ]]; then
        echo "FAILED: $*  (guestVars args '${mock_args}', state '${mock_state}')"
        echo "    expected rc=${want_rc} output '${want_out}'"
        echo "    actual   rc=${rc} output '${out}'"
        _failed=1
    else
        echo "OK: $* (guestVars args '${mock_args}', state '${mock_state}')"
    fi
}

_tools_conf() {
    printf '[salt_minion]\n%s\n' "$1" > "${_work_dir}/etc/tools.conf"
}

rm -f "${_work_dir}/etc/tools.conf"

# --- command line key=value
_run "" "" 0 \
    "ACTION:install src=https://cli.example.com/onedir ver=3007.1 lvl=1 act=install" \
    --install source=https://cli.example.com/onedir minionversion=3007.1 loglevel=error

# --- the way VMware Tools runs it today: key=value, then --loglevel
_run "" "" 0 \
    "ACTION:install src=https://cli.example.com/onedir ver=latest lvl=4 act=install" \
    --install master=m source=https://cli.example.com/onedir --loglevel debug

# --- guest variables only
_run "source=https://gv.example.com/onedir minionversion=3006.8 loglevel=info" "" 0 \
    "ACTION:install src=https://gv.example.com/onedir ver=3006.8 lvl=3 act=install" \
    --install

# --- no action on the command line, the action is the desired state. This must
# --- still run the install (script options must not set CLI_ACTION)
_run "source=https://gv.example.com/onedir" "present" 0 \
    "ACTION:install src=https://gv.example.com/onedir ver=latest lvl=2 act=install"

# --- desired state absent ignores source
_run "source=https://gv.example.com/onedir loglevel=error" "absent" 0 \
    "ACTION:remove src= ver=latest lvl=1 act=remove"

# --- non install actions ignore source and minionversion, honor loglevel
_run "source=https://gv.example.com/onedir minionversion=3006 loglevel=error" "" 0 \
    "ACTION:status src= ver=latest lvl=1 act=status" \
    --status

# --- switches beat key=value
_run "source=https://gv.example.com/onedir" "" 0 \
    "ACTION:install src=https://switch.example.com/onedir ver=latest lvl=2 act=install" \
    --source https://switch.example.com/onedir --install source=https://cli.example.com/onedir

_run "loglevel=error" "" 0 \
    "ACTION:install src= ver=latest lvl=4 act=install" \
    --install --loglevel debug loglevel=error

# --- tools.conf beats guest variables
_tools_conf "source=https://tc.example.com/onedir"
_run "source=https://gv.example.com/onedir" "" 0 \
    "ACTION:install src=https://tc.example.com/onedir ver=latest lvl=2 act=install" \
    --install

# --- command line key=value beats tools.conf
_run "" "" 0 \
    "ACTION:install src=https://cli.example.com/onedir ver=latest lvl=2 act=install" \
    --install source=https://cli.example.com/onedir
rm -f "${_work_dir}/etc/tools.conf"

# --- invalid values stop the script with 126 before the action runs
_run "source=ftp:/bad" "" 126 "" --install
_run "source=http://x/a;id" "present" 126 ""
_run "minionversion=abc" "" 126 "" --install
_run "loglevel=loud" "" 126 "" --status
_run "" "" 126 "" --install source=notascheme://bad

# --- loglevel=silent must not let an invalid value through (the validators
# --- used to only exit when errors were being logged)
_run "loglevel=silent source=http://x/a;id" "" 126 "" --install
_run "loglevel=silent minionversion=abc" "present" 126 ""
_run "" "" 126 "" --install loglevel=silent source=ftp:/bad
_run "" "" 126 "" --loglevel silent --source "http://x/a;id" --install
_run "" "" 126 "" --loglevel silent --minionversion abc --install
_run "loglevel=silent source=https://ok.example.com/onedir" "" 0 \
    "ACTION:install src=https://ok.example.com/onedir ver=latest lvl=0 act=install" \
    --install

# --- tools.conf is read the same as on Windows: white space around the key
# --- and value is ignored, and comment lines are skipped
printf '# source=https://comment.example.com/onedir\n[salt_minion]\n  source = https://tc.example.com/onedir\n; loglevel=debug\n' \
    > "${_work_dir}/etc/tools.conf"
_run "source=https://gv.example.com/onedir" "" 0 \
    "ACTION:install src=https://tc.example.com/onedir ver=latest lvl=2 act=install" \
    --install
rm -f "${_work_dir}/etc/tools.conf"

# --- --version only prints the version, bad guest variables can not stop it
_run "loglevel=loud source=http://x/a;id" "present" 0 "SCRIPT_VERSION_REPLACE" --version
_run "loglevel=silent minionversion=abc" "" 0 "SCRIPT_VERSION_REPLACE" --version --loglevel debug
# --- guest variables that are not set make vmtoolsd fail, like on a host that
# --- did not set them. The script has to carry on with what it does have
_run "<unset>" "<unset>" 0 \
    "ACTION:install src=https://cli.example.com/onedir ver=latest lvl=2 act=install" \
    --install source=https://cli.example.com/onedir
_run "<unset>" "<unset>" 0 ""
_run "<unset>" "present" 0 \
    "ACTION:install src= ver=latest lvl=2 act=install"
_run "source=https://gv.example.com/onedir" "<unset>" 0 ""
# set, but empty
_run "" "" 0 ""

# --- what the script asks vmtoolsd for. The stand-in logs every call
# _calls <name> <expected log> <script args...>
_calls() {
    local name="$1" want="$2" got="" log
    shift 2
    log="${_work_dir}/vmtoolsd_calls.log"
    rm -f "${log}"
    env -u FAKE_GV_ARGS -u FAKE_GV_STATE FAKE_GV_ARGS="master=m" \
        FAKE_GV_STATE="present" FAKE_GV_LOG="${log}" \
        PATH="${_fake_bin}:${PATH}" bash "${_built}" "$@" > /dev/null 2>&1
    if [[ -f "${log}" ]]; then got=$(cat "${log}"); fi
    if [[ "${got}" != "${want}" ]]; then
        echo "FAILED: ${name}"
        echo "    expected calls: '${want}'"
        echo "    actual calls:   '${got}'"
        _failed=1
    else
        echo "OK: ${name}"
    fi
}
_args_call="--cmd info-get guestinfo./vmware.components.salt_minion.args"
_state_call="--cmd info-get guestinfo./vmware.components.salt_minion.desiredstate"
_calls "no action: reads the args and the desired state, once each" \
    "${_args_call}"$'\n'"${_state_call}"
_calls "--install: reads the args, not the desired state" "${_args_call}" --install
_calls "--status: reads the args, not the desired state" "${_args_call}" --status
_calls "--version: does not ask vmtoolsd for anything" "" --version
_calls "--version --loglevel debug: does not ask vmtoolsd for anything" "" --version --loglevel debug
_calls "--help: does not ask vmtoolsd for anything" "" --help

# but --version with an action still reads the options for that action
_run "minionversion=abc" "" 126 "" --version --install

# --- a legacy switch in guest variables is not honored
_run "--source https://legacy.example.com/onedir" "" 0 \
    "ACTION:install src= ver=latest lvl=2 act=install" \
    --install

if [[ "${_failed}" -ne 0 ]]; then
    echo "test_script_opts_main.sh: FAILED"
    exit 1
fi

echo "test_script_opts_main.sh: All tests passed"
exit 0
