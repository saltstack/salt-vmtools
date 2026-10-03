#!/bin/bash

# Copyright (c) 2021-2026 Broadcom Inc. All Rights Reserved.
# SPDX-License-Identifier: Apache-2

## Salt VMware Tools Integration script
##  integration with Component Manager and GuestStore Helper

# latest shellcheck 0.9.0-1 is showing false negatives
# which 0.8.0-2 does not, disabling since using 0.9.0-1
# shellcheck disable=SC2317,SC2004,SC2320,SC2086

## set -u
## set -xT
set -o functrace
set -o pipefail
## set -o errexit

# using bash for now
# run this script as root, as needed to run Salt

readonly SCRIPT_VERSION="SCRIPT_VERSION_REPLACE"

# definitions

## Repository locations and naming
readonly default_salt_url_version="latest"
salt_url_version="${default_salt_url_version}"
salt_specific_version=""

readonly salt_name="salt"
base_url=""

# Broadcom infrastructure
bd_3006_base_url="https://packages.broadcom.com/artifactory/saltproject-generic/onedir"
bd_3006_chksum_base_url="https://packages.broadcom.com/artifactory/api/storage/saltproject-generic/onedir"


# Salt file and directory locations
readonly base_salt_location="/opt/saltstack"
readonly salt_dir="${base_salt_location}/${salt_name}"
readonly salt_conf_dir="/etc/salt"
readonly salt_minion_conf_name="minion"
readonly salt_minion_conf_file="${salt_conf_dir}/${salt_minion_conf_name}"
readonly salt_master_sign_dir="${salt_conf_dir}/pki/${salt_minion_conf_name}"

readonly log_dir="/var/log"

readonly list_files_systemd_to_remove="/lib/systemd/system/salt-minion.service
/usr/lib/systemd/system/salt-minion.service
/usr/local/lib/systemd/system/salt-minion.service
/etc/systemd/system/salt-minion.service
"

readonly list_file_dirs_to_remove="${base_salt_location}
/etc/salt
/var/run/salt
/var/cache/salt
/var/log/salt
/usr/bin/salt-*
${list_files_systemd_to_remove}
"
## /var/log/vmware-${SCRIPTNAME}-*

# some docker containers don't include 'find' - RHEL 8 equivalents
readonly salt_dep_file_list="systemctl
curl
sha256sum
vmtoolsd
grep
awk
sed
cut
wget
find
"

readonly allowed_log_file_action_names="status
depend
install
clear
remove
reconfig
default
"

readonly salt_wrapper_file_list="minion
call
"

readonly salt_minion_service_wrapper=\
"# Copyright (c) 2021-2026 Broadcom Inc. All Rights Reserved.
# SPDX-License-Identifier: Apache-2

[Unit]
Description=The Salt Minion
Documentation=man:salt-minion(1) file:///usr/share/doc/salt/html/contents.html https://docs.saltproject.io/en/latest/contents.html
After=network.target
# After=ConnMgr.service ProcMgr.service sockets.target

[Service]
KillMode=process
Type=notify
NotifyAccess=all
LimitNOFILE=8192
MemoryLimit=250M
Nice=19
ExecStart=/usr/bin/salt-minion

[Install]
WantedBy=multi-user.target
"

# Onedir detection locations
readonly onedir_post_3005_location="${salt_dir}/salt-minion"
readonly onedir_pre_3006_location="${salt_dir}/run/run"

declare -a list_of_onedir_locations_check
list_of_onedir_locations_check[0]="${onedir_pre_3006_location}"
list_of_onedir_locations_check[1]="${onedir_post_3005_location}"

## VMware file and directory locations
readonly vmtools_base_dir_etc="/etc/vmware-tools"
readonly vmtools_conf_file="tools.conf"
readonly vmtools_salt_minion_section_name="salt_minion"

## VMware guestVars file and directory locations
readonly guestvars_base_dir="guestinfo./vmware.components"
readonly \
guestvars_salt_dir="${guestvars_base_dir}.${vmtools_salt_minion_section_name}"
readonly guestvars_salt_args="${guestvars_salt_dir}.args"
readonly guestvars_salt_desiredstate="${guestvars_salt_dir}.desiredstate"

## Script options that can be set using key=value
#
# The keys source, minionversion and loglevel control this script (they are
# the key=value equivalents of --source, --minionversion and --loglevel). They
# are accepted in the same places as salt-minion configuration:
#   - command line   (key=value tokens following --install or --reconfig)
#   - tools.conf     (section [salt_minion])
#   - guest variables (guestinfo./vmware.components.salt_minion.args)
# Precedence, highest first:
#   explicit switch (--source) > command line key=value > tools.conf
#   > guest variables
# These three keys are not case sensitive and are never written to the minion
# configuration, all other key=value options are. Note: Salt's own log_level
# setting is a different key from loglevel and is still written to the minion
# configuration.
# source and minionversion only apply when installing (including --upgrade),
# loglevel applies to every action. They can not set the action.
# An invalid value exits with code 126.
# Note: when VMware Tools adds the guest variables args to the command line,
#       those values have command line precedence, and tools.conf can not
#       override them.
readonly script_opt_keys="source minionversion loglevel"


# Array for minion configuration keys and values
# allows for updates from number of configuration sources before final
# write to /etc/salt/minion
declare -a m_cfg_keys
declare -a m_cfg_values


## Component Manager Installer/Script return/exit status codes
# return/exit Status codes
#  100 + 0 => installed (and running)
#  100 + 1 => installing
#  100 + 2 => notInstalled
#  100 + 3 => installFailed
#  100 + 4 => removing
#  100 + 5 => removeFailed
#  100 + 6 => externalInstall
#  100 + 7 => installedStopped
#  126 => scriptFailed
#  130 => scriptTerminated
declare -A STATUS_CODES_ARY
STATUS_CODES_ARY[installed]=100
STATUS_CODES_ARY[installing]=101
STATUS_CODES_ARY[notInstalled]=102
STATUS_CODES_ARY[installFailed]=103
STATUS_CODES_ARY[removing]=104
STATUS_CODES_ARY[removeFailed]=105
STATUS_CODES_ARY[externalInstall]=106
STATUS_CODES_ARY[installedStopped]=107
STATUS_CODES_ARY[scriptFailed]=126
STATUS_CODES_ARY[scriptTerminated]=130

# log levels available for logging, order sensitive
readonly LOG_MODES_AVAILABLE=(silent error warning info debug)
declare -A LOG_LEVELS_ARY
LOG_LEVELS_ARY[silent]=0
LOG_LEVELS_ARY[error]=1
LOG_LEVELS_ARY[warning]=2
LOG_LEVELS_ARY[info]=3
LOG_LEVELS_ARY[debug]=4


STATUS_CHK=0
DEPS_CHK=0
USAGE_HELP=0
UNINSTALL_FLAG=0
VERBOSE_FLAG=0
VERSION_FLAG=0

CLEAR_ID_KEYS_FLAG=0
CLEAR_ID_KEYS_PARAMS=""

INSTALL_FLAG=0
INSTALL_PARAMS=""

MINION_VERSION_FLAG=0
MINION_VERSION_PARAMS=""

RECONFIG_FLAG=0
RECONFIG_PARAMS=""

STOP_FLAG=0
RESTART_FLAG=0
UPGRADE_FLAG=0

LOG_LEVEL_FLAG=0
LOG_LEVEL_PARAMS=""

#default logging level to errors, similar to Windows script
LOG_LEVEL=${LOG_LEVELS_ARY[warning]}

SOURCE_FLAG=0
SOURCE_PARAMS=""

# desired state (action) from guest variables, retrieved once when needed
GVAR_ACTION_FETCHED=0
GVAR_ACTION=""


# helper functions

_timestamp() {
    date -u "+%Y-%m-%d %H:%M:%S"
}

_log() {
    echo "$(_timestamp) $*" >> \
        "${log_dir}/vmware-${SCRIPTNAME}-${LOG_ACTION}-${logdate}.log"
}

# shellcheck disable=SC2329
_display() {
    if [[ ${VERBOSE_FLAG} -eq 1 ]]; then echo "$1"; fi
    _log "$*"
}

_error_log() {
    if [[ ${LOG_LEVELS_ARY[error]} -le ${LOG_LEVEL} ]]; then
        local log_file=""
        log_file="${log_dir}/vmware-${SCRIPTNAME}-${LOG_ACTION}-${logdate}.log"
        msg="ERROR: $*"
        echo "$msg" 1>&2
        echo "$(_timestamp) $msg" >> "${log_file}"
        echo "One or more errors found. See ${log_file} for details." 1>&2
        CURRENT_STATUS=${STATUS_CODES_ARY[scriptFailed]}
        exit ${STATUS_CODES_ARY[scriptFailed]}
    fi
}

#
# _validation_failed
#
#   Log an error for an invalid parameter value and exit with scriptFailed
#   (126). _error_log only exits when errors are being logged, which is not
#   the case when the log level is silent. An invalid value must never be
#   used, whatever the log level.
#
# Results:
#   Exits with scriptFailed (126)
#

_validation_failed() {
    _error_log "$@"
    CURRENT_STATUS=${STATUS_CODES_ARY[scriptFailed]}
    exit ${STATUS_CODES_ARY[scriptFailed]}
}

_info_log() {
    if [[ ${LOG_LEVELS_ARY[info]} -le ${LOG_LEVEL} ]]; then
        msg="INFO: $*"
        _log "${msg}"
    fi
}

_warning_log() {
    if [[ ${LOG_LEVELS_ARY[error]} -le ${LOG_LEVEL} ]]; then
        msg="WARNING: $*"
        _log "${msg}"
    fi
}

_debug_log() {
    if [[ ${LOG_LEVELS_ARY[debug]} -le ${LOG_LEVEL} ]]; then
        msg="DEBUG: $*"
        _log "${msg}"
    fi
}

# shellcheck disable=SC2329
_yesno() {
read -r -p "Continue (y/n)?" choice
case "$choice" in
  y|Y ) echo "yes";;
  n|N ) echo "no";;
  * ) echo "invalid";;
esac
}


#
# _usage
#
#   Prints out help text
#

 _usage() {
     echo ""
     echo "usage: ${0}"
     echo "             [-c|--clear] [-d|--depend] [-h|--help] [-i|--install]"
     echo "             [-j|--source] [-l|--loglevel] [-m|--minionversion]"
     echo "             [-n|--reconfig] [-q|--stop] [-p|--start]"
     echo "             [-r|--remove] [-s|--status] [-u|--upgrade]"
     echo "             [-v|--version]"
     echo ""
     echo "  -c, --clear     clear previous minion identifier and keys,"
     echo "                     and set specified identifier if present"
     echo "  -d, --depend    check dependencies required to run script exist"
     echo "  -h, --help      this message"
     echo "  -i, --install   install and activate salt-minion configuration"
     echo "                     parameters key=value can also be passed on CLI"
     echo "  -j, --source   specify location to install Salt Minion from"
     echo "                     default is repo.saltproject.io location"
     echo "                 for example: url location"
     echo "                     http://my_web_server.com/my_salt_onedir"
     echo "                     https://my_web_server.com/my_salt_onedir"
     echo "                     file://my_path/my_salt_onedir"
     echo "                     //my_path/my_salt_onedir"
     echo "                 if specific version of Salt Minion specified, -m"
     echo "                 then its appended to source, default[latest]"
     echo "                 invalid value exits with code 126"
     echo "  -l, --loglevel  set log level for logging,"
     echo "                     silent error warning debug info"
     echo "                     default loglevel is warning"
     echo "  -m, --minionversion install salt-minion version, default[latest]"
     echo "                     'latest' and four-digit major (e.g. 3006) pick"
     echo "                     newest GA onedir only; prerelease dirs need"
     echo "                     the exact directory name (e.g. 3008.0rc1)"
     echo "                     invalid value exits with code 126"
     echo "  -n, --reconfig  salt-minion restarts after reading updated config"
     echo "  -q, --stop      stop salt-minion"
     echo "  -p, --start     start salt-minion (restarts salt-minion)"
     echo "  -r, --remove    deactivate and remove the salt-minion"
     echo "  -s, --status    return status for this script"
     echo "  -u, --upgrade   upgrade when installing, used with --install"
     echo "  -v, --version   version of this script"
     echo ""
     echo "  The following can also be set using key=value, with no spaces,"
     echo "  for example: source=https://my_web_server.com/my_salt_onedir"
     echo "      source          same as --source, used when installing"
     echo "      minionversion   same as --minionversion, used when installing"
     echo "      loglevel        same as --loglevel"
     echo "  key=value is read from the command line (after --install or"
     echo "  --reconfig), tools.conf section [salt_minion] and the guest"
     echo "  variable guestinfo./vmware.components.salt_minion.args"
     echo "  Precedence, highest first: switch (for example --source),"
     echo "      key=value on the command line, tools.conf, guest variables"
     echo "  The keys source, minionversion and loglevel are not case"
     echo "  sensitive and are not written to the minion configuration (all"
     echo "  other key=value options are). An invalid value exits with code 126"
     echo "  Note: when VMTools adds the guest variable args to the command"
     echo "  line they have command line precedence over tools.conf"
     echo ""
     echo "  salt-minion VMTools integration script"
     echo "      example: $0 --status"
}


# work functions

#
# _cleanup_int
#
#   Cleanups any running process and areas on control-C
#
#
# Results:
#   Exits with hard-coded value 130
#
# shellcheck disable=SC2329

_cleanup_int() {
    rm -rf "$WORK_DIR"
    _debug_log "$0:${FUNCNAME[0]} Deleted temp working directory $WORK_DIR"

    exit ${STATUS_CODES_ARY[scriptTerminated]}
}

#
# _cleanup_exit
#
#   Cleanups any running process and areas on exit
#
# shellcheck disable=SC2329
_cleanup_exit() {
    rm -rf "$WORK_DIR"
    _debug_log "$0:${FUNCNAME[0]} Deleted temp working directory $WORK_DIR"
    ## exit ${CURRENT_STATUS}
}

trap _cleanup_int INT
trap _cleanup_exit EXIT


# cheap trim relying on echo to convert tabs to spaces and
# all multiple spaces to a single space
_trim() {
    echo "$1"
}


#
# _set_log_level
#
#   Set log_level for logging,
#       log_level 'silent','error','warning','info','debug'
#       default 'warning'
#
# Results:
#   Returns with exit code
#

_set_log_level() {

    _info_log "$0:${FUNCNAME[0]} processing setting set log_level for logging"

    local ip_level=""
    local valid_level=0
    local old_log_level=${LOG_LEVEL}

    ip_level=$( echo "$1" | cut -d ' ' -f 1)
    scam=${#LOG_MODES_AVAILABLE[@]}
    for ((i=0; i<scam; i++)); do
        name=${LOG_MODES_AVAILABLE[i]}
        if [[ "${ip_level}" = "${name}" ]]; then
            valid_level=1
            break
        fi
    done
    if [[ ${valid_level} -ne 1 ]]; then
        _warning_log "$0:${FUNCNAME[0]} attempted to set log_level with "\
            "invalid input, log_level unchanged, currently "\
            "'${LOG_MODES_AVAILABLE[${LOG_LEVEL}]}'"
    else
        LOG_LEVEL=${LOG_LEVELS_ARY[${ip_level}]}
        _info_log "$0:${FUNCNAME[0]} changed log_level from "\
            "'${LOG_MODES_AVAILABLE[${old_log_level}]}' to "\
            "'${LOG_MODES_AVAILABLE[${LOG_LEVEL}]}'"
    fi
    return 0
}


#
# _salt_onedir_dir_is_ga
#
#   True (status 0) if the onedir directory name is GA CalVer, optionally
#       with a -N package-release suffix (e.g. 3008.1 or 3008.1-1).
#       Prerelease names (e.g. 3008.0rc1) are not GA. A -N suffix is a
#       repackage of the same version, not a prerelease, so it counts as GA
#       and can win latest/major-series selection via sort -V.
#
# Results:
#   0 if GA, 1 otherwise
#
_salt_onedir_dir_is_ga() {
    local _ga_re='^[0-9]+\.[0-9]+(\.[0-9]+)*(-[0-9]+)?$'
    [[ -n "$1" && "$1" =~ ${_ga_re} ]]
}


#
# _get_desired_salt_version_fn
#
#   Get the appropriate desirted salt version based on salt_url_version,
#       latest or specified input Salt version, 3008, 3006.9, 3008.0rc1
#       and set salt_specific_version accordinly
#
#   Note: 'latest' and four-digit major (e.g. 3006) choose the newest GA
#         onedir only (sort -V among dirs matching ^[0-9]+\\.[0-9]+(\\.[0-9]+)*$).
#         Prerelease directories must be requested by exact name (directory
#         match or legacy CalVer pattern).
#
#       if an unsupported version is input, for example: 3004.2
#       it will default to installing the latest GA version
#
# Input:
#       directory contains directory list of current available
#           Salt versions, e.g. 3006.x, 3007.1, 3008.0rc1
#
# Results:
#   Returns with exit code (1 if no GA match for latest/major/default)
#
_get_desired_salt_version_fn() {

    if [[ "$#" -ne 1 ]]; then
        _error_log "$0:${FUNCNAME[0]} error expected one parameter "\
            "specifying the location for directories containing versions Salt"
    fi

    _info_log "$0:${FUNCNAME[0]} processing getting desired Salt version "\
        "'$salt_url_version' for salt-minion to install, input directory $1"

    generic_versions_tmpdir="$1"
    curr_pwd=$(pwd)
    cd  ${generic_versions_tmpdir} || return 1

    # something werid is happening with tail, that does not fail in test
    # programs getting failures inside tail hence use bash loop
    _GENERIC_PKG_VERSION=""
    if [ "$salt_url_version" = "latest" ]; then
        # shellcheck disable=SC2010,SC2012
        test_dir=$(ls ./. | grep -v 'index.html' | sort -V -u)
        for idx in $test_dir
        do
            if _salt_onedir_dir_is_ga "$idx"; then
                _GENERIC_PKG_VERSION="$idx"
            fi
        done
        if [[ -z "${_GENERIC_PKG_VERSION}" ]]; then
            cd "${curr_pwd}" || return 1
            _error_log "$0:${FUNCNAME[0]} no GA onedir version directories "\
                "found for 'latest' at '${generic_versions_tmpdir}'"
            return 1
        fi
        _debug_log "$0:${FUNCNAME[0]} latest found GA version "\
            "'${_GENERIC_PKG_VERSION}'"

    elif [[ "${salt_url_version}" =~ ^[0-9]{4}$ ]]; then
        # want newest GA in this major series (3006, 3007, 3008, ...)
        # shellcheck disable=SC2010,SC2012
        test_dir=$(ls ./. | grep -v 'index.html' | sort -V -u \
            | grep -E "^${salt_url_version}\\.")
        for idx in $test_dir
        do
            if _salt_onedir_dir_is_ga "$idx"; then
                _GENERIC_PKG_VERSION="$idx"
            fi
        done
        if [[ -z "${_GENERIC_PKG_VERSION}" ]]; then
            cd "${curr_pwd}" || return 1
            _error_log "$0:${FUNCNAME[0]} no GA onedir version found for "\
                "major series '${salt_url_version}' at "\
                "'${generic_versions_tmpdir}'"
            return 1
        fi
        _debug_log "$0:${FUNCNAME[0]} input ${salt_url_version} found "\
            "GA version '${_GENERIC_PKG_VERSION}'"

    elif [[ -d "./${salt_url_version}" ]]; then
        _GENERIC_PKG_VERSION="${salt_url_version}"
        _debug_log "$0:${FUNCNAME[0]} exact directory match "\
            "'${_GENERIC_PKG_VERSION}'"

    elif [ "$(echo "$salt_url_version" | grep -E '^([3-9][0-5]{2}[6-9](\.[0-9]*)?)')" != "" ]; then
        # Minor version Salt, want specific minor version (incl. prerelease tags)
        # if old style VMTools version 3004.2-1 is used
        # defaults to else and install latest GA
        _GENERIC_PKG_VERSION="$salt_url_version"
        _debug_log "$0:${FUNCNAME[0]} explicit version "\
            "'${_GENERIC_PKG_VERSION}'"
    else
        # default to latest GA version Salt
        # shellcheck disable=SC2010,SC2012
        test_dir=$(ls ./. | grep -v 'index.html' | sort -V -u)
        for idx in $test_dir
        do
            if _salt_onedir_dir_is_ga "$idx"; then
                _GENERIC_PKG_VERSION="$idx"
            fi
        done
        if [[ -z "${_GENERIC_PKG_VERSION}" ]]; then
            cd "${curr_pwd}" || return 1
            _error_log "$0:${FUNCNAME[0]} no GA onedir version directories "\
                "found for default latest at '${generic_versions_tmpdir}'"
            return 1
        fi
        _debug_log "$0:${FUNCNAME[0]} default found GA version "\
            "'${_GENERIC_PKG_VERSION}'"

    fi
    cd "${curr_pwd}" || return 1

    # set specific version of Salt to use
    salt_specific_version="${_GENERIC_PKG_VERSION}"

    return 0
}


#
# _set_install_minion_version_fn
#
#   Set the version of Salt Minion wanted to install
#       default 'latest'
#
#   Note: typically Salt version includes the release number in addition to
#         version number or 'latest' for the most recent release
#
#           for example: 3006.8
#
# Results:
#   Sets salt_url_version to latest or specified input
#       Salt version, 3007, 3006, 3006.x
#   Returns with exit code
#

_set_install_minion_version_fn() {

    if [[ "$#" -ne 1 ]]; then
        _error_log "$0:${FUNCNAME[0]} error expected one parameter "\
            "specifying the version of the salt-minion to install or 'latest'"
    fi

    _info_log "$0:${FUNCNAME[0]} processing setting Salt version for "\
        "salt-minion to install"
    local salt_version=""

    salt_version=$(echo "$1" | cut -d ' ' -f 1)
    if [[ "latest" = "${salt_version}" ]]; then
        # salt_url_version already set to default_salt_url_version
        _debug_log "$0:${FUNCNAME[0]} input Salt version for salt-minion to "\
            "install is 'latest', leaving as default "\
            "'${default_salt_url_version}' for now"

    else
        _debug_log "$0:${FUNCNAME[0]} input Salt version for salt-minion to "\
            "install is '${salt_version}'"

        salt_url_version="${salt_version}"
        _debug_log "$0:${FUNCNAME[0]} set Salt version for salt-minion to "\
            "install to '${salt_url_version}'"
    fi

    return 0
}


#
# _is_script_opt_key
#
#   Check if input key is one of the script options (source, minionversion,
#   loglevel), keys are not case sensitive
#
# Results:
#   Returns 0 if a script option key, 1 otherwise
#

_is_script_opt_key() {
    local chk_key="${1,,}"
    local idx=""

    for idx in ${script_opt_keys}
    do
        if [[ "${chk_key}" = "${idx}" ]]; then
            return 0
        fi
    done
    return 1
}


#
# _split_tokens
#
#   Split input string on whitespace into array SPLIT_TOKENS, without
#   expanding any globbing characters (for example * or ?)
#
# Results:
#   Array SPLIT_TOKENS updated
#

_split_tokens() {
    local IFS=$' \t\n'
    local noglob_was_set=0

    if [[ $- == *f* ]]; then noglob_was_set=1; fi
    set -f
    # shellcheck disable=SC2206
    SPLIT_TOKENS=( $1 )
    if [[ ${noglob_was_set} -eq 0 ]]; then set +f; fi
    return 0
}


#
# _parse_kv_token
#
#   Split a token on the first '=' into KV_KEY and KV_VALUE. A token without
#   an '=', with an empty key or value, or with control characters is invalid
#
# Input:
#   $1  token
#   $2  description of where token was found, used for warning, if empty
#       no warning is logged (the token has been reported elsewhere)
#
# Results:
#   Returns 0 and sets KV_KEY and KV_VALUE if valid, returns 1 otherwise
#

_parse_kv_token() {
    local tok="$1"
    local where="$2"
    local reason=""
    local escaped_tok=""

    KV_KEY=""
    KV_VALUE=""

    if [[ "${tok}" =~ [[:cntrl:]] ]]; then
        reason="contains control characters"
    elif [[ "${tok}" != *=* ]]; then
        reason="expected key=value"
    elif [[ -z "${tok%%=*}" ]]; then
        reason="key is empty"
    elif [[ -z "${tok#*=}" ]]; then
        reason="value is empty"
    fi

    if [[ -n "${reason}" ]]; then
        if [[ -n "${where}" ]]; then
            # token may contain control characters, log it escaped
            printf -v escaped_tok '%q' "${tok}"
            _warning_log "$0:${FUNCNAME[0]} ignoring invalid config token "\
                "${escaped_tok} (${reason}) from ${where}"
        fi
        return 1
    fi

    KV_KEY="${tok%%=*}"
    KV_VALUE="${tok#*=}"
    return 0
}


#
# _update_minion_conf_ary
#
#   Updates the running minion_conf array with input key and value
#   updating with the new value if the key is already found
#
# Results:
#   Updated array
#

_update_minion_conf_ary() {
    local cfg_key="$1"
    local cfg_value="$2"
    local _retn=0

    if [[ "$#" -ne 2 ]]; then
        _error_log "$0:${FUNCNAME[0]} error expect two parameters, "\
            "a key and a value"
    fi

    # now search m_cfg_keys array to see if new key
    key_ary_sz=${#m_cfg_keys[@]}
    if [[ ${key_ary_sz} -ne 0 ]]; then
        # need to check if array has same key
        local chk_found=0
        for ((chk_idx=0; chk_idx<key_ary_sz; chk_idx++))
        do
            if [[ "${m_cfg_keys[${chk_idx}]}" = "${cfg_key}" ]]; then
                m_cfg_values[${chk_idx}]="${cfg_value}"
                _debug_log "$0:${FUNCNAME[0]} updating minion configuration "\
                    "array key '${m_cfg_keys[${chk_idx}]}' with "\
                    "value '${cfg_value}'"
                chk_found=1
                break;
            fi
        done
        if [[ ${chk_found} -eq 0 ]]; then
            # new key for array
            m_cfg_keys[${key_ary_sz}]="${cfg_key}"
            m_cfg_values[${key_ary_sz}]="${cfg_value}"
            _debug_log "$0:${FUNCNAME[0]} adding to minion configuration "\
                "array new key '${cfg_key}' and value '${cfg_value}'"
        fi
    else
        # initial entry
        m_cfg_keys[0]="${cfg_key}"
        m_cfg_values[0]="${cfg_value}"
        _debug_log "$0:${FUNCNAME[0]} adding initial minion configuration "\
            "array, key '${cfg_key}' and value '${cfg_value}'"
    fi
    return ${_retn}
}


#
# _read_tools_conf_salt_minion_lines
#
#   Read the lines in section [salt_minion] of VMTools configuration file
#   tools.conf, blank lines and comment lines (starting with #, ; or ,) are
#   skipped. White space around the line, the key and the value is removed, so
#   'key = value' is the same as 'key=value'. This is the same as the Windows
#   script reads tools.conf.
#
# Results:
#   Array TOOLS_CONF_LINES updated, empty if no file or section
#

_read_tools_conf_salt_minion_lines() {
    local line=""
    local key=""
    local value=""
    local salt_config_flag=0

    TOOLS_CONF_LINES=()
    if [[ ! -f "${vmtools_base_dir_etc}/${vmtools_conf_file}" ]]; then
        return 0
    fi

    # need to extract configuration for salt-minion
    # find section name ${vmtools_salt_minion_section_name}
    # read configuration till next section
    while IFS= read -r line || [[ -n "${line}" ]]
    do
        # comment lines start in the first column
        if [[ "${line}" = [\#\;,]* ]]; then continue; fi
        # remove white space from both ends, includes a CR from CRLF
        line="${line#"${line%%[![:space:]]*}"}"
        line="${line%"${line##*[![:space:]]}"}"
        if [[ -z "${line}" ]]; then continue; fi
        if [[ "${line}" = "["* ]]; then
            if [[ ${salt_config_flag} -eq 1 ]]; then
                # if new section after doing Salt config, we are done
                break;
            fi
            if [[ "${line}" = "[${vmtools_salt_minion_section_name}]" ]]; then
                salt_config_flag=1
            fi
        elif [[ ${salt_config_flag} -eq 1 ]]; then
            if [[ "${line}" = *=* ]]; then
                # remove white space around the first =
                key="${line%%=*}"
                key="${key%"${key##*[![:space:]]}"}"
                value="${line#*=}"
                value="${value#"${value%%[![:space:]]*}"}"
                line="${key}=${value}"
            fi
            TOOLS_CONF_LINES+=( "${line}" )
        fi
    done < "${vmtools_base_dir_etc}/${vmtools_conf_file}"
    return 0
}


#
# _fetch_vmtools_salt_minion_conf_tools_conf
#
#   Retrieve the configuration for salt-minion from VMTools
#                                           configuration file tools.conf
#
#   Script options (source, minionversion, loglevel) are not minion
#   configuration, they are handled by _fetch_script_opts
#
# Results:
#   Exits with new VMTools configuration file if none found or salt-minion
#   configuration file updated with configuration read from VMTools
#   configuration file section for salt_minion
#

_fetch_vmtools_salt_minion_conf_tools_conf() {
    # fetch the current configuration for section salt_minion
    # from vmtoolsd configuration file
    local _retn=0
    local line=""
    if [[ ! -f "${vmtools_base_dir_etc}/${vmtools_conf_file}" ]]; then
        # conf file doesn't exist, create it
        mkdir -p "${vmtools_base_dir_etc}"
        echo "[${vmtools_salt_minion_section_name}]" \
            > "${vmtools_base_dir_etc}/${vmtools_conf_file}"
        _warning_log "$0:${FUNCNAME[0]} creating empty configuration "\
            "file ${vmtools_base_dir_etc}/${vmtools_conf_file}"
    else
        _read_tools_conf_salt_minion_lines
        for line in "${TOOLS_CONF_LINES[@]}"
        do
            _parse_kv_token "${line}" "${vmtools_conf_file}" || continue
            if _is_script_opt_key "${KV_KEY}"; then
                _debug_log "$0:${FUNCNAME[0]} skipping script option "\
                    "'${KV_KEY}' from ${vmtools_conf_file}, not minion "\
                    "configuration"
                continue
            fi
            _update_minion_conf_ary "${KV_KEY}" "${KV_VALUE}" || {
                _error_log "$0:${FUNCNAME[0]} error updating minion "\
                    "configuration array with key '${KV_KEY}' and "\
                    "value '${KV_VALUE}', retcode '$?'";
            }
        done
    fi
    return ${_retn}
}


#
# _fetch_vmtools_salt_minion_conf_guestvars
#
#   Retrieve the configuration for salt-minion from VMTools guest variables
#
#   Script options (source, minionversion, loglevel) are not minion
#   configuration, they are handled by _fetch_script_opts
#
# Results:
#   salt-minion configuration file updated with configuration read
#                                           from VMTools guest variables
#   configuration file section for salt_minion
#

_fetch_vmtools_salt_minion_conf_guestvars() {
    # fetch the current configuration for section salt_minion
    # from guest variables args

    local _retn=0
    local gvar_args=""
    local idx=""

    gvar_args=$(vmtoolsd --cmd "info-get ${guestvars_salt_args}" 2>/dev/null)\
        || { _warning_log "$0:${FUNCNAME[0]} unable to retrieve arguments "\
            "from guest variables location ${guestvars_salt_args}, "\
            "retcode '$?'";
    }

    if [[ -z "${gvar_args}" ]]; then return ${_retn}; fi

    _debug_log "$0:${FUNCNAME[0]} processing arguments from guest variables "\
        "location ${guestvars_salt_args}"

    _split_tokens "${gvar_args}"
    for idx in "${SPLIT_TOKENS[@]}"
    do
        _parse_kv_token "${idx}" \
            "guest variables location ${guestvars_salt_args}" || continue
        if _is_script_opt_key "${KV_KEY}"; then
            _debug_log "$0:${FUNCNAME[0]} skipping script option "\
                "'${KV_KEY}' from guest variables, not minion configuration"
            continue
        fi
        _update_minion_conf_ary "${KV_KEY}" "${KV_VALUE}" || {
            _error_log "$0:${FUNCNAME[0]} error updating minion "\
                "configuration array with key '${KV_KEY}' and value "\
                "'${KV_VALUE}', retcode '$?'";
        }
    done

    return ${_retn}
}


#
# _fetch_vmtools_salt_minion_conf_cli_args
#
#   Retrieve the configuration for salt-minion from any args '$@' passed
#                                               on the command line
#
#   Script options (source, minionversion, loglevel) are not minion
#   configuration, they are handled by _fetch_script_opts
#
# Results:
#   Exits with new VMTools configuration file if none found
#   or salt-minion configuration file updated with configuration read
#   from VMTools configuration file section for salt_minion
#

_fetch_vmtools_salt_minion_conf_cli_args() {
    local _retn=0
    local cli_args=""
    local cli_no_args=0
    local idx=""

    cli_args="$*"
    cli_no_args=$#
    if [[ ${cli_no_args} -ne 0 ]]; then
        _debug_log "$0:${FUNCNAME[0]} processing command line "\
            "arguments '${cli_args}'"
        _split_tokens "${cli_args}"
        for idx in "${SPLIT_TOKENS[@]}"
        do
            # check for start of next option, idx starts with '-' (covers '--')
            if [[ "${idx}" = -* ]]; then
                break
            fi
            _parse_kv_token "${idx}" "command line arguments" || continue
            if _is_script_opt_key "${KV_KEY}"; then
                _debug_log "$0:${FUNCNAME[0]} skipping script option "\
                    "'${KV_KEY}' from command line, not minion configuration"
                continue
            fi
            _update_minion_conf_ary "${KV_KEY}" "${KV_VALUE}" || {
                _error_log "$0:${FUNCNAME[0]} error updating minion "\
                "configuration array with key '${KV_KEY}' and "\
                "value '${KV_VALUE}', retcode '$?'";
            }
        done
    fi
    return ${_retn}
}


#
# _get_desired_state
#
#   Retrieve the desired state (action) set by VMTools in the guest variables,
#   present, absent, status or depend. Only retrieved once
#
# Results:
#   GVAR_ACTION set to the desired state, empty if not set
#

_get_desired_state() {
    if [[ ${GVAR_ACTION_FETCHED} -eq 1 ]]; then
        return 0
    fi
    GVAR_ACTION_FETCHED=1
    GVAR_ACTION=$(vmtoolsd --cmd "info-get ${guestvars_salt_desiredstate}" \
        2>/dev/null) || {
            _warning_log "$0 unable to retrieve any action arguments from "\
                "guest variables ${guestvars_salt_desiredstate}, retcode '$?'";
    }
    return 0
}


#
# _collect_script_opts
#
#   Record any script options (source, minionversion, loglevel) found in the
#   input key=value tokens, other tokens are ignored (they are reported when
#   read as minion configuration)
#
# Input:
#   $1  where the tokens are from, GV (guest variables), TC (tools.conf)
#       or CLI (command line)
#   $@  tokens, after the first
#
# Results:
#   Variables SCRIPT_OPT_<GV|TC|CLI>_<key> updated, last token for a key wins
#

_collect_script_opts() {
    local where="$1"
    local tok=""

    shift
    for tok in "$@"
    do
        _parse_kv_token "${tok}" "" || continue
        _is_script_opt_key "${KV_KEY}" || continue
        printf -v "SCRIPT_OPT_${where}_${KV_KEY,,}" '%s' "${KV_VALUE}"
    done
    return 0
}


#
# _fetch_script_opts
#
#   Retrieve the script options (source, minionversion, loglevel) set using
#   key=value, from the guest variables, tools.conf and command line
#       precedence order: L -> H
#           from VMTools guest variables
#           from VMTools configuration file tools.conf
#           from any key=value on the command line, after --install
#                                                       or --reconfig
#   An explicit switch, for example --source, is higher still and is not
#   changed, see _apply_script_opts
#
# Results:
#   Variables SCRIPT_OPT_<key> set to the value to use, empty if not set
#

_fetch_script_opts() {
    local key=""
    local where=""
    local gvar_args=""
    local cli_args=""
    local tok=""
    local -a cli_tokens=()

    for key in ${script_opt_keys}
    do
        printf -v "SCRIPT_OPT_${key}" '%s' ""
        for where in GV TC CLI
        do
            printf -v "SCRIPT_OPT_${where}_${key}" '%s' ""
        done
    done

    # guest variables
    gvar_args=$(vmtoolsd --cmd "info-get ${guestvars_salt_args}" 2>/dev/null) \
        || gvar_args=""
    _split_tokens "${gvar_args}"
    _collect_script_opts GV "${SPLIT_TOKENS[@]}"

    # tools.conf, each line is a token
    _read_tools_conf_salt_minion_lines
    _collect_script_opts TC "${TOOLS_CONF_LINES[@]}"

    # command line, tokens stop at the next switch
    for cli_args in "${INSTALL_PARAMS}" "${RECONFIG_PARAMS}"
    do
        cli_tokens=()
        _split_tokens "${cli_args}"
        for tok in "${SPLIT_TOKENS[@]}"
        do
            if [[ "${tok}" = -* ]]; then break; fi
            cli_tokens+=( "${tok}" )
        done
        _collect_script_opts CLI "${cli_tokens[@]}"
    done

    # now apply precedence
    for key in ${script_opt_keys}
    do
        for where in CLI TC GV
        do
            tok="SCRIPT_OPT_${where}_${key}"
            if [[ -n "${!tok}" ]]; then
                printf -v "SCRIPT_OPT_${key}" '%s' "${!tok}"
                _debug_log "$0:${FUNCNAME[0]} script option '${key}' set to "\
                    "'${!tok}' from ${where}"
                break
            fi
        done
    done
    return 0
}


#
# _validate_loglevel_param
#
#   Validates a loglevel set using key=value. Exits with scriptFailed (126)
#   if the value is not one of silent, error, warning, info or debug
#
# Input:
#   $1  loglevel value, not case sensitive
#
# Results:
#   Returns 0 if valid; exits 126 via _error_log otherwise
#

_validate_loglevel_param() {
    local level_val="${1,,}"
    local idx=""
    local escaped_val=""

    for idx in "${LOG_MODES_AVAILABLE[@]}"
    do
        if [[ "${level_val}" = "${idx}" ]]; then
            return 0
        fi
    done
    printf -v escaped_val '%q' "$1"
    _validation_failed "$0:${FUNCNAME[0]} Invalid loglevel: ${escaped_val} must be one of "\
        "${LOG_MODES_AVAILABLE[*]}"
    return 1
}


#
# _apply_script_opts
#
#   Apply the script options (source, minionversion, loglevel) found by
#   _fetch_script_opts, unless the equivalent switch was used on the command
#   line, switches have the highest precedence.
#
#   loglevel is applied for every action. source and minionversion are applied
#   only when installing, using --install or, when no switch was used on the
#   command line, a desired state of 'present' in the guest variables.
#
#   Note: does not set CLI_ACTION as that would stop the desired state in the
#         guest variables from being used
#
# Results:
#   Log level, source and minion version updated, exits 126 if a value
#   is invalid
#

_apply_script_opts() {
    local will_install=0
    local sum_switches=0

    _fetch_script_opts

    if [[ ${LOG_LEVEL_FLAG} -eq 0 && -n "${SCRIPT_OPT_loglevel}" ]]; then
        _validate_loglevel_param "${SCRIPT_OPT_loglevel}"
        _set_log_level "${SCRIPT_OPT_loglevel,,}"
    fi

    if [[ -z "${SCRIPT_OPT_source}" && -z "${SCRIPT_OPT_minionversion}" ]]; then
        return 0
    fi

    if [[ ${INSTALL_FLAG} -eq 1 ]]; then
        will_install=1
    else
        sum_switches=$(( STATUS_CHK + DEPS_CHK + SOURCE_FLAG + \
            MINION_VERSION_FLAG + UPGRADE_FLAG + CLEAR_ID_KEYS_FLAG + \
            UNINSTALL_FLAG + VERSION_FLAG + RECONFIG_FLAG + STOP_FLAG + \
            RESTART_FLAG + LOG_LEVEL_FLAG ))
        if [[ ${sum_switches} -eq 0 ]]; then
            # no action on the command line, action from guest variables
            _get_desired_state
            if [[ "${GVAR_ACTION}" = "present" ]]; then
                will_install=1
            fi
        fi
    fi

    if [[ ${will_install} -ne 1 ]]; then
        _debug_log "$0:${FUNCNAME[0]} not installing, ignoring script "\
            "options source and minionversion"
        return 0
    fi

    if [[ ${SOURCE_FLAG} -eq 0 && -n "${SCRIPT_OPT_source}" ]]; then
        LOG_ACTION="install"
        _validate_source_param "${SCRIPT_OPT_source}"
        _source_fn "${SCRIPT_OPT_source}"
    fi
    if [[ ${MINION_VERSION_FLAG} -eq 0 && -n "${SCRIPT_OPT_minionversion}" ]]; then
        LOG_ACTION="install"
        _validate_minion_version_param "${SCRIPT_OPT_minionversion}"
        _set_install_minion_version_fn "${SCRIPT_OPT_minionversion}"
    fi
    return 0
}


#
# _randomize_minion_id
#
#   Added 5 digit random number to input minion identifier
#
# Input:
#       String to add random number to
#       if no input, default string 'minion_' used
#
# Results:
#   exit, return value etc
#

_randomize_minion_id() {

    local ran_minion=""
    local ip_string="$1"

    if [[ -z "${ip_string}" ]]; then
        ran_minion="minion_${RANDOM:0:5}"
    else
        #provided input
        ran_minion="${ip_string}_${RANDOM:0:5}"
    fi
    _debug_log "$0:${FUNCNAME[0]} generated randomized minion "\
            "identifier '${ran_minion}'"
    echo "${ran_minion}"
}


#
# _fetch_vmtools_salt_minion_conf
#
#   Retrieve the configuration for salt-minion
#       precedence order: L -> H
#           from VMware Tools guest Variables
#           from VMware Tools configuration file tools.conf
#           from any command line parameters
#
# Results:
#   Exits with new salt-minion configuration file written
#

_fetch_vmtools_salt_minion_conf() {
    # fetch the current configuration for section salt_minion
    # from vmtoolsd configuration file

    _debug_log "$0:${FUNCNAME[0]} retrieving minion configuration parameters"
    _fetch_vmtools_salt_minion_conf_guestvars || {
        _error_log "$0:${FUNCNAME[0]} failed to process guest variable "\
            "arguments, retcode '$?'";
    }
    _fetch_vmtools_salt_minion_conf_tools_conf || {
        _error_log "$0:${FUNCNAME[0]} failed to process tools.conf file, "\
            "retcode '$?'";
    }
    _fetch_vmtools_salt_minion_conf_cli_args "$*" || {
        _error_log "$0:${FUNCNAME[0]} failed to process command line "\
            "arguments, retcode '$?'";
    }

    # now write minion conf array to salt-minion configuration file
    local mykey_ary_sz=${#m_cfg_keys[@]}
    local myvalue_ary_sz=${#m_cfg_values[@]}
    if [[ "${mykey_ary_sz}" -ne "${myvalue_ary_sz}" ]]; then
        _error_log "$0:${FUNCNAME[0]} key '${mykey_ary_sz}' and "\
            "value '${myvalue_ary_sz}' array sizes for minion_conf "\
            "don't match"
    else
        mkdir -p "${salt_conf_dir}"
        echo "# Minion configuration file - created by VMTools Salt script" \
            > "${salt_minion_conf_file}"
        echo "enable_fqdns_grains: False" >> "${salt_minion_conf_file}"
        for ((chk_idx=0; chk_idx<mykey_ary_sz; chk_idx++))
        do
            # appending to salt-minion configuration file since it
            # should be new and no configuration set

            # check for special case of signed master's public key
            # verify_master_pubkey_sign=master_sign.pub
            if [[ "${m_cfg_keys[${chk_idx}]}" \
                    = "verify_master_pubkey_sign" ]]; then
                _debug_log "$0:${FUNCNAME[0]} processing minion "\
                    "configuration parameters for master public signed key"
                echo "${m_cfg_keys[${chk_idx}]}: True" \
                    >> "${salt_minion_conf_file}"
                mkdir -p "${salt_conf_dir}/pki/minion"
                cp -f "${m_cfg_values[${chk_idx}]}" \
                    "${salt_master_sign_dir}/"
            else
                echo "${m_cfg_keys[${chk_idx}]}: ${m_cfg_values[${chk_idx}]}" \
                    >> "${salt_minion_conf_file}"
            fi
        done
    fi

    _info_log "$0:${FUNCNAME[0]} successfully retrieved the salt-minion "\
        "configuration from configuration sources"
    return 0
}


#
# _fetch_salt_minion
#
#   Retrieve the salt-minion from Salt repository
#
# Note: Only support Salt 3006 and higher with new Broadcom infrastructure
#       salt_url_version is always set with desired version of Salt
#       for example: latest, 3006, 3007, 3006.8, 3007.1
#
# Side Effects:
#   CURRENT_STATUS updated
#
# Results:
#   Exits with 0 or error code
#

_fetch_salt_minion() {

    # fetch the current salt-minion into specified location
    # could check if already there but by always getting it
    # ensure we are not using stale versions
    local _retn=0

    local salt_pkg_name=""
    local salt_url=""

    local local_base_url=""
    local local_file_flag=0

    local salt_pkg_sha256_found=0
    local salt_pkg_shakey=0
    local salt_pkg_sha256=""
    local calc_sha256sum=1

    local install_onedir_chk=0
    local sys_arch=""

    local salt_pkg_metadata=0

    _debug_log "$0:${FUNCNAME[0]} retrieve the salt-minion and check its validity"

    CURRENT_STATUS=${STATUS_CODES_ARY[installFailed]}
    mkdir -p ${base_salt_location}
    cd "${WORK_DIR}" || return $?

    # unless already defined by --source option
    if [[ -z "${base_url}" ]]; then
        _debug_log "$0:${FUNCNAME[0]} no source option used, determine "\
            "version attempting to install, version '${salt_url_version}"
        base_url="${bd_3006_base_url}"
    else
        _debug_log "$0:${FUNCNAME[0]} source url provided, need to scan for "\
        "local file using base_url '${base_url}'"

        # curl on Linux doesn't support file:// support
        if grep -q '^/' <<< "${base_url}" ; then
            local_base_url="${base_url}"
            local_file_flag=1
            _debug_log "$0:${FUNCNAME[0]} using source '${local_base_url}'"\
            "from '${base_url}'"
        elif grep -q '^file://' <<< "${base_url}" ; then
            local_base_url="${base_url//file:/}"
            local_file_flag=1
            _debug_log "$0:${FUNCNAME[0]} using source '${local_base_url}'"\
            "from '${base_url}'"
        else
            _debug_log "$0:${FUNCNAME[0]} using non-local source '${base_url}'"
        fi
    fi

    sys_arch="${MACHINE_ARCH}"

    if [[ ${local_file_flag} -eq 1 ]]; then
        # local absolute path
        # and allow for Linux handling multiple slashes

        # use defaults
        # directory with onedir files and retrieve files from it
        salt_url="${local_base_url}"
        curr_dir=$(pwd)
        _debug_log "$0:${FUNCNAME[0]} current directory ${curr_dir}"

        # get desired specific version of Salt
        _get_desired_salt_version_fn "${salt_url}" || return 1
        cd "${salt_url}" || return 1
        cd "${salt_specific_version}" || return 1
        salt_pkg_name=$(ls "${salt_name}-${salt_specific_version}-onedir-linux-${sys_arch}.tar.xz")
        cd "${curr_dir}" || return 1
        cp -a "${salt_url}/${salt_specific_version}/${salt_pkg_name}" ${salt_pkg_name}
        _debug_log "$0:${FUNCNAME[0]} successfully copied tarball from "\
            "'${salt_url}/${salt_specific_version}' to file '${salt_pkg_name}'"
    else
        # assume use curl for local or remote URI
        # directory with onedir files and retrieve files from it

        _debug_log "$0:${FUNCNAME[0]} using curl to download from url '${base_url}'"

        # get dir listing from url, sort and pick highest
        generic_versions_tmpdir=$(mktemp -d)
        curr_pwd=$(pwd)
        cd  ${generic_versions_tmpdir} || return 1
        # leverage the onedir directories since release Windows and Linux
        wget -r -np -nH --exclude-directories=windows,relenv,macos -x -l 1 "${base_url}/"
        cd ${curr_pwd} || return 1

        url_path=$(printf '%s\n' "$base_url" | sed -E 's|https?://[^/]+/?||')
        url_path=${url_path%/}   
        local_path="${generic_versions_tmpdir}/${url_path}"

        # get desired specific version of Salt
        if ! _get_desired_salt_version_fn \
            "${local_path}"
        then
            rm -fR "${generic_versions_tmpdir}"
            return 1
        fi

        # clean up temp dir
        rm -fR ${generic_versions_tmpdir}

        salt_pkg_name="${salt_name}-${salt_specific_version}-onedir-linux-${sys_arch}.tar.xz"
        salt_url="${base_url}/${salt_specific_version}/${salt_pkg_name}"

        # assume http://, https:// or similar
        wget -q -r -l1 -nd -np -A "${salt_pkg_name}" "${salt_url}"
        _retn=$?
        if [[ ${_retn} -ne 0 ]]; then
            CURRENT_STATUS=${STATUS_CODES_ARY[installFailed]}
            _error_log "$0:${FUNCNAME[0]} downloaded file "\
            "'${salt_pkg_name}' failed to download, error '${_retn}'"
        fi

        salt_pkg_metadata=$(curl "${bd_3006_chksum_base_url}/${salt_specific_version}/${salt_pkg_name}")
        salt_pkg_sha=$(echo "${salt_pkg_metadata}" | grep -w "sha256" | sort | uniq)
        if [[ -n "${salt_pkg_sha}" ]]; then
            # have package metadata to process
            salt_pkg_shakey=$(echo "${salt_pkg_sha}" | awk -F ':' '{print $1}' | awk -F '"' '{print $2}')
            salt_pkg_sha256=$(echo "${salt_pkg_sha}" | awk -F ':' '{print $2}' | awk -F '"' '{print $2}')

            _debug_log "$0:${FUNCNAME[0]} found information for file "\
                "'${salt_pkg_name}', shakey '${salt_pkg_shakey}', "\
                "sha256value '${salt_pkg_sha256}'"

            if [[ "${salt_pkg_shakey}" = "sha256" ]]; then
                # Found sha256
                salt_pkg_sha256_found=1
                _debug_log "$0:${FUNCNAME[0]} successfully found sha256 "\
                    "information on file '${salt_pkg_name}'"
            else
                # sanity check for sha256 key not found
                CURRENT_STATUS=${STATUS_CODES_ARY[installing]}
                _warning_log "$0:${FUNCNAME[0]} failed to find sha256 "\
                    "information for downloaded file '${salt_pkg_name}', "\
                    "error '${salt_pkg_sha256}'"
            fi
        fi

        if [[ ${salt_pkg_sha256_found} -eq 1 ]]; then
            # Have sha256 information to check against
            calc_sha256sum=$(sha256sum "${salt_pkg_name}" | awk -F ' ' '{print $1}')
            if [[ "${calc_sha256sum}" != "${salt_pkg_sha256}" ]]; then
                CURRENT_STATUS=${STATUS_CODES_ARY[installFailed]}
                _error_log "$0:${FUNCNAME[0]} generated checksum "\
                "'${calc_sha256sum}' for downloaded file '${salt_pkg_name}' "\
                "does not match that retrieved from repository '${salt_pkg_sha256}'"
            else
                _debug_log "$0:${FUNCNAME[0]} downloaded file "\
                    "'${salt_pkg_name}' matched checksum retrieved from repository"
            fi
        fi
    fi

    # need to setup salt user and group if not already existing
    _debug_log "$0:${FUNCNAME[0]} setup salt user and group if not "\
        "already existing"
    _SALT_GROUP=salt
    _SALT_USER=salt
    _SALT_NAME=Salt
    # 1. create group if not existing
    if getent group "${_SALT_GROUP}" 1>/dev/null; then
        _debug_log "$0:${FUNCNAME[0]} already group salt, assume user "\
            "and group setup for Salt"
    else
        _debug_log "$0:${FUNCNAME[0]} setup group and user salt"
        # create user to avoid running server as root
        # 1. create group if not existing
        groupadd --system "${_SALT_GROUP}" 2>/dev/null
        # 2. create homedir if not existing
        if [[ ! -d "${salt_dir}" ]]; then
            mkdir -p "${salt_dir}"
        fi
        # 3. create user if not existing
        if ! grep -q "^${_SALT_USER}:" < <(getent passwd); then
          useradd --system --no-create-home -s /sbin/nologin -g \
            "${_SALT_GROUP}" "${_SALT_USER}" 2>/dev/null
        fi
        # 4. adjust passwd entry
        usermod -c "${_SALT_NAME}" -d "${salt_dir}" -g "${_SALT_GROUP}" \
            "${_SALT_USER}" 2>/dev/null
    fi
    tar xf "${salt_pkg_name}" -C "${base_salt_location}" 1>/dev/null
    # 5. adjust file and directory permissions
    chown -R "${_SALT_USER}":"${_SALT_GROUP}" "${salt_dir}"
    _retn=$?
    if [[ ${_retn} -ne 0 ]]; then
        CURRENT_STATUS=${STATUS_CODES_ARY[installFailed]}
        _error_log "$0:${FUNCNAME[0]} tar xf expansion of downloaded "\
            "file '${salt_pkg_name}' failed, return code '${_retn}'"
    fi
    install_onedir_chk=$(_check_onedir_minion_install)
    if [[ ${install_onedir_chk} -eq 0 ]]; then
        CURRENT_STATUS=${STATUS_CODES_ARY[installFailed]}
        _error_log "$0:${FUNCNAME[0]} expansion of downloaded file "\
            "'${salt_url}' failed to provide any onedir installed "\
            "critical files for salt-minion"
    fi
    CURRENT_STATUS=${STATUS_CODES_ARY[installed]}
    cd "${CURRDIR}" || return $?

    _info_log "$0:${FUNCNAME[0]} successfully retrieved salt-minion"
    return 0
}


#
# _check_multiple_script_running
#
#   check if more than one version of the script is running
#
# Results:
#   Checks the number of scripts running, allowing for forks etc
#   from bash etc, as root a single instance of the script returns 3
#   as sudo root a single instance of the script returns 4
#

_check_multiple_script_running() {
    local count=0
    local procs_found=""

    _info_log "$0:${FUNCNAME[0]} checking how many versions of the "\
        "script are running"

    procs_found=$(pgrep -f "${SCRIPTNAME}")
    count=$(echo "${procs_found}" | wc -l)

    _debug_log "$0:${FUNCNAME[0]} checking versions of script are running, "\
        "bashpid '${BASHPID}', processes found '${procs_found}', "\
        "and count '${count}'"

    if [[ ${count} -gt 4 ]]; then
        _error_log "$0:${FUNCNAME[0]} failed to check status, "\
            "multiple versions of the script are running"
    fi

    return 0
}


#
# _check_classic_minion_install
#
# Check if classic salt-minion is installed for the OS
#   for example: install salt-minion from rpm or deb package
#
# Results:
#   0 - No standard classic install found and empty string output
#   !0 - Standard  classic install found and Salt version found output
#

_check_classic_minion_install() {

    # checks for /usr/bin, then /usr/local/bin
    # this catches 80% to 90%  of the regular cases
    # if salt-call is there, then so is a salt-minion
    # as they are installed together

    local _retn=0
    local max_file_sz=200
    local list_of_files_check="
/usr/bin/salt-call
/usr/local/bin/salt-call
"
    _info_log "$0:${FUNCNAME[0]} check if standard classic "\
        "salt-minion installed"

    for idx in ${list_of_files_check}
    do
        if [[ -h "${idx}" ]]; then
            _debug_log "$0:${FUNCNAME[0]} found file '${idx}' "\
                "symbolic link, post-3005 installation"
            break
        elif [[ -f "${idx}" ]]; then
            #check size of file, if larger than 200, not script wrapper file
            local file_sz=0
            file_sz=$(( $(wc -c < "${idx}") ))
            _debug_log "$0:${FUNCNAME[0]} found file '${idx}', "\
                "size '${file_sz}'"
            if [[ ${file_sz} -gt ${max_file_sz} ]]; then
                # get salt-version
                local s_ver=""
                s_ver=$("${idx}" --local test.version |grep -v 'local:' |xargs)
                _debug_log "$0:${FUNCNAME[0]} found standard classic "\
                    "salt-minion, Salt version: '${s_ver}'"
                echo "${s_ver}"
                _retn=1
                break
            fi
        fi
    done
    echo ""
    return ${_retn}
}


#
# _check_onedir_minion_install
#
# Check if onedir pre_3006 or post_3005 salt-minion is installed on the OS
#   for example: install salt-minion from rpm or deb package
#
# Results:
#   Echos the following values:
#   0 - No onedir install found and empty string output
#   1 - pre_3006 onedir install found
#   2 - post_3005 onedir install found
#

_check_onedir_minion_install() {

    # checks for following executables:
    # post_3005 - /opt/saltstack/salt/salt-minion
    # pre_3006  - /opt/saltstack/salt/run/run

    local _retn=0
    local pre_3006=1
    local post_3005=2

    _info_log "$0:${FUNCNAME[0]} check if standard onedir-minion installed"

    if [[ -f "${list_of_onedir_locations_check[0]}" ]]; then
        _debug_log "$0:${FUNCNAME[0]} found pre 3006 version of Salt, "\
                    "at location ${list_of_onedir_locations_check[0]}"
        _retn=${pre_3006}
    elif [[ -f "${list_of_onedir_locations_check[1]}" ]]; then
        _debug_log "$0:${FUNCNAME[0]} found post 3005 version of Salt, "\
                    "at location ${list_of_onedir_locations_check[1]}"
        _retn=${post_3005}
    else
        _debug_log "$0:${FUNCNAME[0]} failed to find a onedir installation"
    fi
    echo ${_retn}
}


#
# _find_salt_pid
#
#   finds the pid for the Salt process
#
# Results:
#   Echos ${salt_pid} which could be empty '' if Salt process not found
#

_find_salt_pid() {
    # find the pid for salt-minion if active
    local salt_pid=0
    if [[ ${POST_3005_FLAG} -eq 1 ]]; then
        salt_pid=$(pgrep -f "\/usr\/bin\/salt-minion" | head -n 1)
    else
        salt_pid=$(pgrep -f "${salt_name}\/run\/run minion" | head -n 1 |
            awk -F " " '{print $1}')
    fi
    _debug_log "$0:${FUNCNAME[0]} checking for salt-minion process id, "\
        "found '${salt_pid}'"
    echo "${salt_pid}"
}

#
# _ensure_id_or_fqdn
#
#   Ensures that a valid minion identifier has been specified, and if not a
#   valid Fully Qualified Domain Name exists (not default Unknown.example.org)
#   else generates a minion id to use.
#
# Note: this function should only be run before starting the salt-minion
#       via systemd after it has been installed
#
# Side Effect:
#   Updates salt-minion configuration file with generated identifier
#       if no valid FQDN
#
# Results:
#   salt-minion configuration contains a valid identifier or FQDN to use.
#   Exits with 0
#

_ensure_id_or_fqdn () {
    # ensure minion id or fqdn for salt-minion

    local minion_fqdn=""

    # quick check if id specified
    if grep -q '^id:' < "${salt_minion_conf_file}"; then
        _debug_log "$0:${FUNCNAME[0]} salt-minion identifier found, no "\
            "need to check further"
        return 0
    fi

    _debug_log "$0:${FUNCNAME[0]} ensuring salt-minion identifier or "\
        "FQDN is specified for salt-minion configuration"
    minion_fqdn=$(/usr/bin/salt-call --local grains.get fqdn |
        grep -v 'local:' | xargs)
    if [[ -n "${minion_fqdn}" &&
        "${minion_fqdn}" != "Unknown.example.org" ]]; then
        _debug_log "$0:${FUNCNAME[0]} non-default salt-minion FQDN "\
            "'${minion_fqdn}' is specified for salt-minion configuration"
        return 0
    fi

    # default FQDN, no id is specified, generate one and update conf file
    local minion_genid=""
    minion_genid=$(_generate_minion_id)
    echo "id: ${minion_genid}" >> "${salt_minion_conf_file}"
    _debug_log "$0:${FUNCNAME[0]} no salt-minion identifier found, "\
        "generated identifier '${minion_genid}'"

    return 0
}


#
# _create_pre_3006_helper_scripts
#
#   Create helper scripts for salt-call and salt-minion
#
#       Example: _create_pre_3006_helper_scripts
#
# Results:
#   Exits with 0 or error code
#

_create_pre_3006_helper_scripts() {

    for idx in ${salt_wrapper_file_list}
    do
        local abs_filepath=""
        abs_filepath="/usr/bin/salt-${idx}"

        _debug_log "$0:${FUNCNAME[0]} creating helper file 'salt-${idx}' "\
            "in directory /usr/bin"

        echo "#!/usr/bin/env bash

# Copyright (c) 2021-2026 Broadcom Inc. All Rights Reserved.
" > "${abs_filepath}" || {
            _error_log "$0:${FUNCNAME[0]} failed to create helper file "\
                "'salt-${idx}' in directory /usr/bin, retcode '$?'";
        }
        {
            echo -n "exec /opt/saltstack/salt/run/run ${idx}";
            echo -n "\"$";
            echo -n "{";
            echo -n "@";
            echo -n ":";
            echo -n "1}";
            echo -n "\"";
        } >> "${abs_filepath}" || {
            _error_log "$0:${FUNCNAME[0]} failed to finish creating helper "\
                "file 'salt-${idx}' in directory /usr/bin, retcode '$?'";
        }
        echo  "" >> "${abs_filepath}"

        # ensure executable
        chmod 755 "${abs_filepath}" || {
            _error_log "$0:${FUNCNAME[0]} failed to make helper file "\
                "'salt-${idx}' executable in directory /usr/bin, retcode '$?'";
        }
    done

}


#
# _status_fn
#
#   discover and return the current status
#
#       0 => installed (and running)
#       1 => installing
#       2 => notInstalled
#       3 => installFailed
#       4 => removing
#       5 => removeFailed
#       6 => externalInstall
#       7 => installedStopped
#       126 => scriptFailed
#
# Side Effects:
#   CURRENT_STATUS updated
#
# Results:
#   Exits numerical status
#

_status_fn() {
    # return status
    local _retn_status=${STATUS_CODES_ARY[notInstalled]}
    local install_onedir_chk=0
    local found_salt_ver=""

    _info_log "$0:${FUNCNAME[0]} checking status for script"

    _check_multiple_script_running

    found_salt_ver=$(_check_classic_minion_install)
    if [[ -n "${found_salt_ver}" ]]; then
        _debug_log "$0:${FUNCNAME[0]}" \
            "existing Standard Classic Salt Installation detected, "\
            "Salt version: '${found_salt_ver}'"
            CURRENT_STATUS=${STATUS_CODES_ARY[externalInstall]}
            _retn_status=${STATUS_CODES_ARY[externalInstall]}
    else
        _debug_log "$0:${FUNCNAME[0]} no standardized classic install found"

        install_onedir_chk=$(_check_onedir_minion_install)
        if [[ ${install_onedir_chk} -eq 2 ]]; then
            POST_3005_FLAG=1    # ensure note 3006 and above
        fi

        svpid=$(_find_salt_pid)
        if [[ ${install_onedir_chk} -eq 0 && -z ${svpid} ]]; then
            # not installed and no process id
            CURRENT_STATUS=${STATUS_CODES_ARY[notInstalled]}
            _retn_status=${STATUS_CODES_ARY[notInstalled]}
        elif [[ ${install_onedir_chk} -ne 0 ]]; then
            # installed, check for pid
            CURRENT_STATUS=${STATUS_CODES_ARY[installed]}
            _retn_status=${STATUS_CODES_ARY[installed]}
            # normal case but double-check
            svpid=$(_find_salt_pid)
            if [[ -z ${svpid} ]]; then
                # Note: someone could have stopped the salt-minion,
                # so installed but not running,
                CURRENT_STATUS=${STATUS_CODES_ARY[installedStopped]}
                _retn_status=${STATUS_CODES_ARY[installedStopped]}
            else
                # have running pid for salt-minion
                CURRENT_STATUS=${STATUS_CODES_ARY[installed]}
                _retn_status=${STATUS_CODES_ARY[installed]}
            fi
        elif [[ -z ${svpid} ]]; then
            # check no process id and
            # main directory still left, =>installedStopped
            if [[ ${install_onedir_chk} -ne 0 ]]; then
                CURRENT_STATUS=${STATUS_CODES_ARY[installedStopped]}
                _retn_status=${STATUS_CODES_ARY[installedStopped]}
            fi
        fi
    fi

    return ${_retn_status}
}


#
# _stop_fn
#
#   stop the salt-minion if running and return the current status
#
#       0 => installed (and running)
#       1 => installing
#       2 => notInstalled
#       3 => installFailed
#       4 => removing
#       5 => removeFailed
#       6 => externalInstall
#       7 => installedStopped
#       126 => scriptFailed
#
# Side Effects:
#   CURRENT_STATUS updated
#
# Results:
#   Exits numerical status
#

_stop_fn() {
    # return status
    local _retn_status=${STATUS_CODES_ARY[notInstalled]}
    local install_onedir_chk=0
    local found_salt_ver=""
    local systemctl_issue=0

    _info_log "$0:${FUNCNAME[0]} checking status for script"

    _check_multiple_script_running

    found_salt_ver=$(_check_classic_minion_install)
    if [[ -n "${found_salt_ver}" ]]; then
        _debug_log "$0:${FUNCNAME[0]}" \
            "existing Standard Classic Salt Installation detected, "\
            "Salt version: '${found_salt_ver}'"
            CURRENT_STATUS=${STATUS_CODES_ARY[externalInstall]}
            _retn_status=${STATUS_CODES_ARY[externalInstall]}
    else
        _debug_log "$0:${FUNCNAME[0]} no standardized classic install found"

        install_onedir_chk=$(_check_onedir_minion_install)
        if [[ ${install_onedir_chk} -eq 2 ]]; then
            POST_3005_FLAG=1    # ensure note 3006 and above
        fi

        if [[ ${install_onedir_chk} -eq 0 ]]; then
            # not installed
            CURRENT_STATUS=${STATUS_CODES_ARY[notInstalled]}
            _retn_status=${STATUS_CODES_ARY[notInstalled]}
        elif [[ ${install_onedir_chk} -ne 0 ]]; then
            # installed, check for pid
            CURRENT_STATUS=${STATUS_CODES_ARY[installed]}
            _retn_status=${STATUS_CODES_ARY[installed]}
            svpid=$(_find_salt_pid)
            if [[ -z ${svpid} ]]; then
                # Note: someone could have stopped the salt-minion,
                # so installed but not running,
                CURRENT_STATUS=${STATUS_CODES_ARY[installedStopped]}
                _retn_status=${STATUS_CODES_ARY[installedStopped]}
            else
                # have pid for salt-minion, need to stop
                systemctl stop salt-minion || {
                    _warning_log "$0:${FUNCNAME[0]} stopping existing Salt "\
                        "functionality salt-minion encountered difficulties "\
                        "using systemctl, retcode '$?'";
                    systemctl_issue=1;
                }
                if [[ "${systemctl_issue}" -eq 0 ]]; then
                    CURRENT_STATUS=${STATUS_CODES_ARY[installedStopped]}
                    _retn_status=${STATUS_CODES_ARY[installedStopped]}
                else
                    CURRENT_STATUS=${STATUS_CODES_ARY[installedStopped]}
                    _retn_status=${STATUS_CODES_ARY[installedStopped]}
                    _error_log "$0:${FUNCNAME[0]} stopping existing Salt "\
                        "functionality salt-minion encountered difficulties "\
                        "using systemctl, run 'systemctl status salt-minion'"\
                        "to resolve issue'";
                fi
            fi
        fi
    fi

    _debug_log "$0:${FUNCNAME[0]} stop returning '${_retn_status}'"
    return ${_retn_status}
}


#
# _restart_fn
#
#   restart the salt-minion if not running and return the current status
#
#       0 => installed (and running)
#       1 => installing
#       2 => notInstalled
#       3 => installFailed
#       4 => removing
#       5 => removeFailed
#       6 => externalInstall
#       7 => installedStopped
#       126 => scriptFailed
#
# Side Effects:
#   CURRENT_STATUS updated
#
# Results:
#   Exits numerical status
#

_restart_fn() {

    # return status
    local _retn_status=${STATUS_CODES_ARY[notInstalled]}
    local install_onedir_chk=0
    local found_salt_ver=""
    local systemctl_issue=0

    _info_log "$0:${FUNCNAME[0]} checking status for script"

    _check_multiple_script_running

    found_salt_ver=$(_check_classic_minion_install)
    if [[ -n "${found_salt_ver}" ]]; then
        _debug_log "$0:${FUNCNAME[0]}" \
            "existing Standard Classic Salt Installation detected, "\
            "Salt version: '${found_salt_ver}'"
            CURRENT_STATUS=${STATUS_CODES_ARY[externalInstall]}
            _retn_status=${STATUS_CODES_ARY[externalInstall]}
    else
        _debug_log "$0:${FUNCNAME[0]} no standardized classic install found"

        install_onedir_chk=$(_check_onedir_minion_install)
        if [[ ${install_onedir_chk} -eq 2 ]]; then
            POST_3005_FLAG=1    # ensure note 3006 and above
        fi

        if [[ ${install_onedir_chk} -eq 0 ]]; then
            # not installed
            CURRENT_STATUS=${STATUS_CODES_ARY[notInstalled]}
            _retn_status=${STATUS_CODES_ARY[notInstalled]}
        elif [[ ${install_onedir_chk} -ne 0 ]]; then
            # installed, check running
            systemctl restart salt-minion || {
                _warning_log "$0:${FUNCNAME[0]} restarting existing Salt "\
                    "functionality salt-minion encountered difficulties "\
                    "using systemctl, retcode '$?'";
                systemctl_issue=1;
            }
            if [[ "${systemctl_issue}" -eq 0 ]]; then
                CURRENT_STATUS=${STATUS_CODES_ARY[installed]}
                _retn_status=${STATUS_CODES_ARY[installed]}
            else
                CURRENT_STATUS=${STATUS_CODES_ARY[installed]}
                _retn_status=${STATUS_CODES_ARY[installed]}
                _error_log "$0:${FUNCNAME[0]} restarting existing Salt "\
                    "functionality salt-minion encountered difficulties "\
                    "using systemctl, run 'systemctl status salt-minion'"\
                    "to resolve issue'";
            fi
        fi
    fi
    _debug_log "$0:${FUNCNAME[0]} restart returning '${_retn_status}'"
    return ${_retn_status}
}



#
# _deps_chk_fn
#
#   Check dependencies for using salt-minion
#
# Side Effects:
# Results:
#   Exits with 0 or error code
#
_deps_chk_fn() {
    # return dependency check
    local error_missing_deps=""

    _info_log "$0:${FUNCNAME[0]} checking script dependencies"
    for idx in ${salt_dep_file_list}
    do
        command -v "${idx}" 1>/dev/null || {
            if [[ -z "${error_missing_deps}" ]]; then
                error_missing_deps="${idx}"
            else
                error_missing_deps="${error_missing_deps} ${idx}"
            fi
        }
    done
    if [[ -n "${error_missing_deps}" ]]; then
        _error_log "$0:${FUNCNAME[0]} failed to find required "\
            "dependencies '${error_missing_deps}'";
    fi
    return 0
}

#
# _find_system_lib_path
#
# find with systemd library path to use
#
# Result:
#   echos the systemd library path
#   will error if no systemd library path can be determined
#
# Note:
#   /lib/systemd/system
#       System units installed by the distribution package manage
#   /usr/lib/systemd/system
#       System units installed by the Administrator
#   /usr/local/lib/systemd/system
#       System units installed by the Administrator (possible on some OS)
#
# Will use /usr/lib/systemd/system available, since this is generally
# the default used on modern Linux OS by salt-minion, some earlier OS's
# (Debian 9, Ubuntu 18.04) use /lib/systemd/system
#
_find_system_lib_path () {

    local path_found=""
    _info_log "$0:${FUNCNAME[0]} finding systemd library path to use"
    if [[ -d "/usr/lib/systemd/system" ]]; then
        path_found="/usr/lib/systemd/system"
    elif [[ -d "/lib/systemd/system" ]]; then
        path_found="/lib/systemd/system"
    elif [[ -d "/usr/local/lib/systemd/system" ]]; then
        path_found="/usr/local/lib/systemd/system"
    else
        _error_log "$0:${FUNCNAME[0]} unable to determine systemd "\
        "library path to use"
    fi
    _debug_log "$0:${FUNCNAME[0]} found library path to use ${path_found}"
    echo "${path_found}"
}


#
# _reconfig_fn
#
# Executes scripts to stop the salt-minion, if active
# Re-read the configuration
# Restart the salt-minion, if it had been active
#
# Results:
#   Exits with 0 or error code
#
_reconfig_fn () {
    local _retn=0
    local minion_was_active=""

    _info_log "$0:${FUNCNAME[0]} processing script install"

    _check_multiple_script_running

    found_salt_ver=$(_check_classic_minion_install)
    if [[ -n "${found_salt_ver}" ]]; then
        _warning_log "$0:${FUNCNAME[0]} failed to install, "\
            "existing Standard Classic Salt Installation detected, "\
            "Salt version: '${found_salt_ver}'"
        CURRENT_STATUS=${STATUS_CODES_ARY[externalInstall]}
        exit ${STATUS_CODES_ARY[externalInstall]}
    else
        _debug_log "$0:${FUNCNAME[0]} no standardized classic install found"
    fi

    minion_was_active=$(systemctl is-active salt-minion) || {
        _error_log "$0:${FUNCNAME[0]} checking running existing salt-minion "\
            "encountered difficulties using systemctl, retcode '$?'";
        }

    # get configuration for salt-minion
    _fetch_vmtools_salt_minion_conf "$@" || {
        _error_log "$0:${FUNCNAME[0]} failed, read configuration for "\
            "salt-minion, retcode '$?'";
    }

    # ensure minion id or fqdn for salt-minion
    _ensure_id_or_fqdn

    cd "${CURRDIR}" || return $?

    # restart the salt-minion using systemd if it was active at the start
    systemctl daemon-reload || {
        _error_log "$0:${FUNCNAME[0]} reloading the systemd daemon "\
            "failed , retcode '$?'";
    }
    _debug_log "$0:${FUNCNAME[0]} successfully executed systemctl "\
        "daemon-reload"
    if [[ "${minion_was_active}" = "active" ]]; then
        local name_service="salt-minion.service"
        systemctl restart "${name_service}" || {
            _error_log "$0:${FUNCNAME[0]} restarting the salt-minion using "\
                "systemctl failed , retcode '$?'";
        }
        _debug_log "$0:${FUNCNAME[0]} successfully executed systemctl "\
            "restart '${name_service}'"
        systemctl enable "${name_service}" || {
            _error_log "$0:${FUNCNAME[0]} enabling the salt-minion using "\
                "systemctl failed , retcode '$?'";
        }
        _debug_log "$0:${FUNCNAME[0]} successfully executed systemctl "\
            "enable '${name_service}'"
    fi
    return ${_retn}
}



#
#  _install_fn
#
#   Executes scripts to install Salt from Salt repository
#       and start the salt-minion using systemd
#
# Results:
#   Exits with 0 or error code
#

_install_fn () {

    # execute install of Salt minion
    local _retn=0
    local existing_chk=""
    local found_salt_ver=""
    local install_onedir_chk=0

    _info_log "$0:${FUNCNAME[0]} processing script install"

    _check_multiple_script_running

    found_salt_ver=$(_check_classic_minion_install)
    if [[ -n "${found_salt_ver}" ]]; then
        _warning_log "$0:${FUNCNAME[0]} failed to install, "\
            "existing Standard Classic Salt Installation detected, "\
            "Salt version: '${found_salt_ver}'"
        CURRENT_STATUS=${STATUS_CODES_ARY[externalInstall]}
        exit ${STATUS_CODES_ARY[externalInstall]}
    else
        _debug_log "$0:${FUNCNAME[0]} no standardized Classic install found"
    fi

    # check if salt-minion or salt-master (salt-cloud etc req master)
    # and log warning that they will be overwritten
    existing_chk=$(pgrep -l "salt-minion|salt-master" | cut -d ' ' -f 2 | uniq)
    if [[ -n  "${existing_chk}" ]]; then
        for idx in ${existing_chk}
        do
            local salt_fn=""
            salt_fn="$(basename "${idx}")"
            if [ "${UPGRADE_FLAG}" -eq 0 ]; then
                # performing a clean install
                _warning_log "$0:${FUNCNAME[0]} existing Salt functionality "\
                    "${salt_fn} shall be stopped and replaced when new "\
                    "salt-minion is installed"
            else
                # performing an upgrade, note in logs
                _warning_log "$0:${FUNCNAME[0]} existing Salt functionality "\
                    "${salt_fn} shall be stopped and upgraded when new "\
                    "salt-minion is installed"
            fi
        done
    fi

    # fetch salt-minion from repository
    _fetch_salt_minion || {
        _error_log "$0:${FUNCNAME[0]} failed to fetch salt-minion "\
            "from repository , retcode '$?'";
    }

    # get configuration for salt-minion
    if [ "${UPGRADE_FLAG}" -eq 0 ]; then
        # performing a clean install
        _fetch_vmtools_salt_minion_conf "$@" || {
            _error_log "$0:${FUNCNAME[0]} failed, read configuration for "\
                "salt-minion, retcode '$?'";
        }
    else
        # performing an upgrade, note in logs, and leave config alone
        _debug_log "$0:${FUNCNAME[0]} performing upgrade, using existing "\
            "read configuration for salt-minion";
    fi

    if [[ ${_retn} -eq 0 && -f "${onedir_pre_3006_location}" ]]; then
        # create helper scripts for /usr/bin to ensure they are present
        # before attempting to use them in _ensure_id_or_fqdn
        # this is for earlier than 3006 versions of Salt onedir
        _debug_log "$0:${FUNCNAME[0]} creating helper files salt-call "\
            "and salt-minion in directory /usr/bin"
        _create_pre_3006_helper_scripts || {
            _error_log "$0:${FUNCNAME[0]} failed to create helper files "\
                "salt-call or salt-minion in directory /usr/bin, retcode '$?'";
        }
    elif [[ ${_retn} -eq 0 && -f "${onedir_post_3005_location}" ]]; then
        # create symbolic links for /usr/bin to ensure they are present
        _debug_log "$0:${FUNCNAME[0]} creating symbolic links for salt-call "\
            "and salt-minion in directory /usr/bin"
        ln -s -f "${salt_dir}/salt-minion" "/usr/bin/salt-minion" || {
            _error_log "$0:${FUNCNAME[0]} failed to create symbolic link "\
                "for salt-minion in directory /usr/bin, retcode '$?'";
        }
        ln -s -f "${salt_dir}/salt-call" "/usr/bin/salt-call" || {
            _error_log "$0:${FUNCNAME[0]} failed to create symbolic link "\
                "for salt-call in directory /usr/bin, retcode '$?'";
        }
    else
        _error_log "$0:${FUNCNAME[0]} problems creating helper files "\
            "or symbolic links for salt-call or salt-minion in "\
            "directory /usr/bin, should not have reached this code point";
    fi

    # ensure minion id or fqdn for salt-minion
    _ensure_id_or_fqdn
    install_onedir_chk=$(_check_onedir_minion_install)

    if [[ ${_retn} -eq 0 && ${install_onedir_chk} -ne 0 ]]; then
        if [[ -n  "${existing_chk}" ]]; then
            # be nice and stop any current Salt functionality found
            for idx in ${existing_chk}
            do
                local salt_fn=""
                salt_fn="$(basename "${idx}")"
                _warning_log "$0:${FUNCNAME[0]} stopping Salt functionality "\
                    "${salt_fn} it's replaced with new installed salt-minion"
                systemctl stop "${salt_fn}" || {
                    _warning_log "$0:${FUNCNAME[0]} stopping existing Salt "\
                        "functionality ${salt_fn} encountered difficulties "\
                        "using systemctl, it will be over-written with the "\
                        "new installed salt-minion regardless, retcode '$?'";
                }
            done
        fi

        # install salt-minion systemd service script
        # first find with systemd library path to use
        local systemd_lib_path=""
        systemd_lib_path=$(_find_system_lib_path)
        local name_service="salt-minion.service"
        _debug_log "$0:${FUNCNAME[0]} copying systemd service script "\
            "${name_service} to directory ${systemd_lib_path}"
        echo "${salt_minion_service_wrapper}" \
            > "${systemd_lib_path}/${name_service}" || {
            _error_log "$0:${FUNCNAME[0]} failed to copy systemd service "\
                "file ${name_service} to directory "\
                "${systemd_lib_path}, retcode '$?'";
        }

        cd "${CURRDIR}" || return $?

        # start the salt-minion using systemd
        systemctl daemon-reload || {
            _error_log "$0:${FUNCNAME[0]} reloading the systemd daemon "\
                "failed , retcode '$?'";
        }
        _debug_log "$0:${FUNCNAME[0]} successfully executed systemctl "\
            "daemon-reload"
        systemctl restart "${name_service}" || {
            _error_log "$0:${FUNCNAME[0]} starting the salt-minion using "\
                "systemctl failed , retcode '$?'";
        }
        _debug_log "$0:${FUNCNAME[0]} successfully executed systemctl "\
            "restart '${name_service}'"
        systemctl enable "${name_service}" || {
            _error_log "$0:${FUNCNAME[0]} enabling the salt-minion using "\
                "systemctl failed , retcode '$?'";
        }
        _debug_log "$0:${FUNCNAME[0]} successfully executed systemctl "\
            "enable '${name_service}'"
    fi
    return ${_retn}
}


#
# _validate_source_param
#
#   Validates the --source parameter value. Exits with scriptFailed (126)
#   if the value is empty, contains control characters, contains shell
#   injection characters, or does not match a recognised protocol prefix.
#
# Input:
#   $1  raw SOURCE_PARAMS string (first word is extracted, matching _source_fn)
#
# Results:
#   Returns 0 if valid; exits 126 via _error_log otherwise
#

_validate_source_param() {

    local source_val="$1"

    if [[ -z "${source_val}" ]]; then
        _validation_failed "$0:${FUNCNAME[0]} Invalid --source: must not be empty"
    fi

    if [[ "${source_val}" =~ [[:cntrl:]] ]]; then
        _validation_failed "$0:${FUNCNAME[0]} Invalid --source: contains control characters"
    fi

    if grep -qE '[`;|&<>]' <<< "${source_val}"; then
        _validation_failed "$0:${FUNCNAME[0]} Invalid --source: contains disallowed characters"
    fi

    if grep -qE '^(https?|ftp)://' <<< "${source_val}"; then
        if grep -q ' ' <<< "${source_val}"; then
            _validation_failed "$0:${FUNCNAME[0]} Invalid --source: URL must not contain whitespace"
        fi
        if ! grep -qE '^(https?|ftp)://[^/]+' <<< "${source_val}"; then
            _validation_failed "$0:${FUNCNAME[0]} Invalid --source: URL has no host"
        fi
    elif grep -qE '^/|^file://' <<< "${source_val}"; then
        # absolute local path or file URI
        :
    else
        _validation_failed "$0:${FUNCNAME[0]} Invalid --source: '${source_val}' "\
            "must start with http://, https://, ftp://, file://, or /"
    fi

    return 0
}


#
# _validate_minion_version_param
#
#   Validates the --minionversion parameter value. Exits with scriptFailed
#   (126) if the value does not match the expected Salt CalVer format.
#
#   Valid: latest, YYYY, YYYY.N, YYYY.N.N, YYYY.NrcN, YYYY.N.N-N
#          (e.g. 3006, 3006.2, 3008.0, 3008.0rc1, 3004.2-1)
#
# Input:
#   $1  raw MINION_VERSION_PARAMS string (first word is extracted)
#
# Results:
#   Returns 0 if valid; exits 126 via _error_log otherwise
#

_validate_minion_version_param() {

    local version_val="$1"

    if ! grep -qE '^(latest|[0-9]{4}(\.[0-9]+(\.[0-9]+)*(rc[0-9]+|-[0-9]+)?)?)$' \
            <<< "${version_val}"; then
        _validation_failed "$0:${FUNCNAME[0]} Invalid --minionversion: '${version_val}'. "\
            "Must be 'latest', a major version (e.g. 3006), "\
            "or a full version (e.g. 3006.2, 3008.0rc1)"
    fi

    return 0
}


#
#  _source_fn
#
#   Set the location to retrieve the Salt Minion from
#       default is to use the Salt Project repository
#
#   Set the version of Salt Minion wanted to install
#       default 'latest'
#
#   Note: handle all protocols (http, https, ftp, file, unc, etc)
#           for example:
#               http://my_web_server.com/my_salt_onedir
#               https://my_web_server.com/my_salt_onedir
#               ftp://my_ftp_server.com/my_salt_onedir
#               file://mytopdir/mymiddledir/my_salt_onedir
#               ///mytopdir/mymiddledir/my_salt_onedir
#
#           If a specific version of the Salt Minion is specified
#           then it will be appended to the specified source location
#           otherwise a default of 'latest' is applied.
#
# Results:
#   Exits with 0 or error code
#

_source_fn () {
    local _retn=0
    local salt_source=""

    if [[ $# -ne 1 ]]; then
        _error_log "$0:${FUNCNAME[0]} error expected one parameter "\
            "specifying the source for location of onedir files"
    fi

    _info_log "$0:${FUNCNAME[0]} processing script source for location "\
        "of onedir files"

    salt_source=$(echo "$1" | cut -d ' ' -f 1)
    _debug_log "$0:${FUNCNAME[0]} input Salt source is '${salt_source}'"

    if [[ -n "${salt_source}" ]]; then
        base_url=${salt_source}
    fi
    _debug_log "$0:${FUNCNAME[0]} input Salt source for salt-minion to "\
            "install from is '${base_url}'"

    return ${_retn}
}


#
# _generate_minion_id
#
#   Searches salt-minion configuration file for current id, and disables it
#   and generates a new id based on the existing id found,
#   or an older commented out id, and provides it with a randomized 5 digit
#   post-pended to it, for example: myminion_12345
#
#   If no previous id found, a generated minion_<random number> is output
#
# Side Effects:
#   Disables any id found in minion configuration file
#
# Result:
#   Outputs randomized minion id for use in a minion configuration file
#   Exits with 0 or error code
#

_generate_minion_id () {

    local salt_id_flag=0
    local minion_id=""
    local cfg_value=""
    local ifield=""
    local tfields=""

    _debug_log "$0:${FUNCNAME[0]} generating a salt-minion identifier"

    # always comment out what was there
    sed -i 's/^id:/# id:/g' "${salt_minion_conf_file}"

    while IFS= read -r line
    do
        line_value=$(_trim "${line}")
        if [[ -n "${line_value}" ]]; then
            if grep -q '^# id:' <<< "${line_value}" ; then
                # get value and write out value_<random>
                cfg_value=$(echo "${line_value}" | cut -d ' ' -f 3)
                if [[ -n "${cfg_value}" ]]; then
                    salt_id_flag=1
                    minion_id=$(_randomize_minion_id "${cfg_value}")
                    _debug_log "$0:${FUNCNAME[0]} found previously used id "\
                        "field, randomizing it"
                fi
            elif grep -q -w 'id:' <<< "${line_value}" ; then
                # might have commented out id, get value and
                # write out value_<random>
                tfields=$(echo "${line_value}"|awk -F ':' '{print $2}'|xargs)
                ifield=$(echo "${tfields}" | cut -d ' ' -f 1)
                if [[ -n ${ifield} ]]; then
                    minion_id=$(_randomize_minion_id "${ifield}")
                    salt_id_flag=1
                    _debug_log "$0:${FUNCNAME[0]} found previously used "\
                        "id field, randomizing it"
                fi
            else
                _debug_log "$0:${FUNCNAME[0]} skipping line '${line}'"
            fi
        fi
    done < "${salt_minion_conf_file}"

    if [[ ${salt_id_flag} -eq 0 ]]; then
        # no id field found, write minion_<random?
        _debug_log "$0:${FUNCNAME[0]} no previous id field found, "\
            "generating new identifier"
        minion_id=$(_randomize_minion_id)
    fi
    _debug_log "$0:${FUNCNAME[0]} generated a salt-minion "\
        "identifier '${minion_id}'"
    echo "${minion_id}"
    return 0
}


#
# _clear_id_key_fn
#
#   Executes scripts to clear the minion identifier and keys and
#   re-generates new identifier, allows for a VM containing a salt-minion,
#   to be cloned and not have conflicting id and keys
#   salt-minion is stopped, id and keys cleared, and restarted
#   if it was previously running, and not an upgrade
#
# Input:
#   Optional specified input ID to be used, default generate randomized value
#
# Note:
#   Normally a salt-minion if no id is specified will rely on
#   it's Fully Qualified Domain Name but with VM Cloning, there is no surety
#   that the FQDN will have been altered, and duplicates can occur.
#   Also if there is no FQDN, then default 'Unknown.example.org' is used,
#   again with the issue of duplicates for multiple salt-minions
#   with no FQDN specified
#
# Side Effects:
#   New minion identifier in configuration file and keys for the salt-minion
#
# Results:
#   Exits with 0 or error code
#

_clear_id_key_fn () {
    # execute clearing of Salt minion id and keys
    local _retn=0
    local salt_minion_pre_active_flag=0
    local salt_id_flag=0
    local minion_id=""
    local minion_ip_id=""
    local install_onedir_chk=0

    _info_log "$0:${FUNCNAME[0]} processing clearing of salt-minion "\
        "identifier and its keys"

    _check_multiple_script_running

    install_onedir_chk=$(_check_onedir_minion_install)
    if [[ ${install_onedir_chk} -eq 0 ]]; then
        _debug_log "$0:${FUNCNAME[0]} salt-minion is not installed, "\
            "nothing to do"
        return ${_retn}
    fi

    # get any minion identifier in case specified
    minion_ip_id=$(echo "$1" | cut -d ' ' -f 1)
    svpid=$(_find_salt_pid)
    if [[ -n ${svpid} ]]; then
        # stop the active salt-minion using systemd
        # and give it a little time to stop
        systemctl stop salt-minion || {
            _error_log "$0:${FUNCNAME[0]} failed to stop salt-minion "\
                "using systemctl, retcode '$?'";
        }
        _debug_log "$0:${FUNCNAME[0]} successfully executed systemctl "\
            "stop salt-minion"
        salt_minion_pre_active_flag=1
    fi

    if [ "${UPGRADE_FLAG}" -eq 0 ]; then
        # perform a clean install and generate new keys and minion id
        rm -fR "${salt_conf_dir}/minion_id"
        rm -fR "${salt_conf_dir}/pki/${salt_minion_conf_name}"
        # always comment out what was there
        sed -i 's/^id/# id/g' "${salt_minion_conf_file}"
        _debug_log "$0:${FUNCNAME[0]} removed '${salt_conf_dir}/minion_id' "\
            "and '${salt_conf_dir}/pki/${salt_minion_conf_name}', and "\
            "commented out id in '${salt_minion_conf_file}'"

        if [[ -z "${minion_ip_id}" ]] ;then
            minion_id=$(_generate_minion_id)
        else
            minion_id="${minion_ip_id}"
        fi

        # add new minion id to bottom of minion configuration file
        echo "id: ${minion_id}" >> "${salt_minion_conf_file}"
        _debug_log "$0:${FUNCNAME[0]} updated salt-minion identifier "\
            "'${minion_id}' in configuration file '${salt_minion_conf_file}'"
    else
        # performing an upgrade, log info
        minion_id="${minion_ip_id}"
        _debug_log "$0:${FUNCNAME[0]} maintaining salt-minion identifier "\
            "'${minion_id}' and keys in configuration file "\
            "'${salt_minion_conf_file}' since performing upgrade"
    fi

    if [[ ${salt_minion_pre_active_flag} -eq 1 ]]; then
        # restart the stopped salt-minion using systemd
        systemctl restart salt-minion || {
            _error_log "$0:${FUNCNAME[0]} failed to restart salt-minion "\
                "using systemctl, retcode '$?'";
        }

        _debug_log "$0:${FUNCNAME[0]} successfully executed systemctl "\
            "restart salt-minion"
    fi

    return ${_retn}
}


#
# _remove_installed_files_dirs
#
#   Removes all Salt files and directories that may be used
#
# Note:
#   funciton only call when performing an uninstall
#
# Results:
#   Exits with 0 or error code
#

_remove_installed_files_dirs() {
    # performing an uninstall
    _debug_log "$0:${FUNCNAME[0]} removing directories and files "\
        "in '${list_file_dirs_to_remove}'"
    for idx in ${list_file_dirs_to_remove}
    do
        rm -fR "${idx}" || {
            _error_log "$0:${FUNCNAME[0]} failed to remove file or "\
                "directory '${idx}' , retcode '$?'";
        }
    done
    return 0
}


#
#  _uninstall_fn
#
#   Executes scripts to uninstall Salt from system
#       stopping the salt-minion using systemd
#
# Side Effects:
#   CURRENT_STATUS updated
#
# Results:
#   Exits with 0 or error code
#

_uninstall_fn () {
    # remove Salt minion
    local _retn=0
    local found_salt_ver=""
    local install_onedir_chk=0

    _info_log "$0:${FUNCNAME[0]} processing script remove"

    _check_multiple_script_running

    found_salt_ver=$(_check_classic_minion_install)
    if [[ -n "${found_salt_ver}" ]]; then
        _warning_log "$0:${FUNCNAME[0]} failed to install, "\
            "existing Standard Classic Salt Installation detected, "\
            "Salt version: '${found_salt_ver}'"
        CURRENT_STATUS=${STATUS_CODES_ARY[externalInstall]}
        exit ${STATUS_CODES_ARY[externalInstall]}
    else
        _debug_log "$0:${FUNCNAME[0]} no standardized classic install found"
    fi

    install_onedir_chk=$(_check_onedir_minion_install)
    if [[ ${install_onedir_chk} -eq 0 ]]; then
        CURRENT_STATUS=${STATUS_CODES_ARY[notInstalled]}

        # assume rest is gone
        # TBD enhancement, could loop thru and check all of files to remove
        # and if salt_pid empty but we error out if issues when uninstalling,
        # so safe for now.
        _retn=0
    else
        CURRENT_STATUS=${STATUS_CODES_ARY[removing]}
        # remove salt-minion from systemd
        # and give it a little time to stop
        systemctl stop salt-minion || {
            _error_log "$0:${FUNCNAME[0]} failed to stop salt-minion "\
                "using systemctl, retcode '$?'";
        }
        _debug_log "$0:${FUNCNAME[0]} successfully executed systemctl "\
            "stop salt-minion"
        systemctl disable salt-minion || {
            _error_log "$0:${FUNCNAME[0]} disabling the salt-minion "\
                "using systemctl failed , retcode '$?'";
        }
        _debug_log "$0:${FUNCNAME[0]} successfully executed systemctl "\
            "disable salt-minion"

        _debug_log "$0:${FUNCNAME[0]} removing systemd directories and files "\
            "in '${list_files_systemd_to_remove}'"
        for idx in ${list_files_systemd_to_remove}
        do
            rm -fR "${idx}" || {
                _error_log "$0:${FUNCNAME[0]} failed to remove file or "\
                    "directory '${idx}' , retcode '$?'";
            }
        done

        systemctl daemon-reload || {
            _error_log "$0:${FUNCNAME[0]} reloading the systemd daemon "\
                "failed , retcode '$?'";
        }
        _debug_log "$0:${FUNCNAME[0]} successfully executed systemctl "\
            "daemon-reload"
        systemctl reset-failed || {
            _error_log "$0:${FUNCNAME[0]} reloading the systemd daemon "\
                "failed , retcode '$?'";
        }
        _debug_log "$0:${FUNCNAME[0]} successfully executed systemctl "\
            "reset-failed"

        if [[ ${_retn} -eq 0 ]]; then
            svpid=$(_find_salt_pid)
            if [[ -n ${svpid} ]]; then
                _debug_log "$0:${FUNCNAME[0]} found salt-minion process "\
                    "id '${salt_pid}', systemctl stop should have "\
                    "eliminated it, killing it now"
                kill "${svpid}"
                ## given it a little time
                sleep 5
            fi
            svpid=$(_find_salt_pid)
            if [[ -n ${svpid} ]]; then
                CURRENT_STATUS=${STATUS_CODES_ARY[removeFailed]}
                _error_log "$0:${FUNCNAME[0]} failed to kill the "\
                    "salt-minion, pid '${svpid}' during uninstall"
            else
                _remove_installed_files_dirs || {
                    _error_log "$0:${FUNCNAME[0]} failed to remove all "\
                        "installed salt-minion files and directories, "\
                        "retcode '$?'";
                }
                CURRENT_STATUS=${STATUS_CODES_ARY[notInstalled]}
            fi
        fi
    fi

    _info_log "$0:${FUNCNAME[0]} successfully removed salt-minion and "\
        "associated files and directories"
    return ${_retn}
}


#
#  _clean_up_log_files
#
#   Limits number of log files by removing oldest log files which exceed
#   limit LOG_FILE_NUMBER
#
# Results:
#   Exits with 0 or error code
#
_clean_up_log_files() {

    _info_log "$0:${FUNCNAME[0]} removing and limiting log files"
    for idx in ${allowed_log_file_action_names}
    do
        local count_f=0
        local found_f=""
        local -a found_f_ary
        found_f=$(ls -t "${log_dir}/vmware-${SCRIPTNAME}-${idx}"* 2>/dev/null)
        count_f=$(echo "${found_f}" | wc | awk -F" " '{print $2}')
        mapfile -t found_f_ary <<< "${found_f}"

        if [[ ${count_f} -gt ${LOG_FILE_NUMBER} ]]; then
            # allow for org-0
            for ((i=count_f-1; i>=LOG_FILE_NUMBER; i--)); do
                _debug_log "$0:${FUNCNAME[0]} removing log file "\
                    "'${found_f_ary[i]}', for count '${i}', "\
                    "limit '${LOG_FILE_NUMBER}'"
                rm -f "${found_f_ary[i]}" || {
                    _error_log "$0:${FUNCNAME[0]} failed to remove file "\
                    "'${found_f_ary[i]}', for count '${i}', "\
                    "limit '${LOG_FILE_NUMBER}'"
                }
            done
        else
            _debug_log "$0:${FUNCNAME[0]} found '${count_f}' "\
                "log files starting with "\
                "${log_dir}/vmware-${SCRIPTNAME}-${idx}-, "\
                "limit '${LOG_FILE_NUMBER}'"
        fi
    done
    return 0
}

################################### MAIN ####################################

# static definitions

CURRDIR=$(pwd)

# get machine architecture once
MACHINE_ARCH=$(uname -m)

# setup work-area
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
# the temp working directory used, within $DIR
WORK_DIR=$(mktemp -d -p "$DIR")

# check if temp working dir was created
if [[ ! "${WORK_DIR}" || ! -d "${WORK_DIR}" ]]; then
  echo "Could not create temp dir"
  exit 1
fi

# default status is notInstalled
CURRENT_STATUS=${STATUS_CODES_ARY[notInstalled]}
export CURRENT_STATUS

## build date-time tag used for logging UTC YYYYMMDDhhmmss
## YearMontDayHourMinuteSecondMicrosecond aka jid
logdate=$(date -u +%Y%m%d%H%M%S)

# set logging information
LOG_FILE_NUMBER=5
SCRIPTNAME=$(basename "$0")
mkdir -p "${log_dir}"

# set to action e.g. 'remove', 'install'
# default is for any logging not associated with a specific action
# for example: debug logging and --version
LOG_ACTION="default"

CLI_ACTION=0

while true; do
    if [[ -z "$1" ]]; then break; fi
    case "$1" in
        -c | --clear )
            CLEAR_ID_KEYS_FLAG=1;
            shift;
            CLEAR_ID_KEYS_PARAMS=$*;
            ;;
        -d | --depend )
            DEPS_CHK=1;
            shift;
            ;;
        -h | --help )
            USAGE_HELP=1;
            shift;
            ;;
        -i | --install )
            INSTALL_FLAG=1;
            shift;
            INSTALL_PARAMS="$*";
            ;;
        -j | --source )
            SOURCE_FLAG=1;
            shift;
            SOURCE_PARAMS="$1";
            ;;
        -l | --loglevel )
            LOG_LEVEL_FLAG=1;
            shift;
            LOG_LEVEL_PARAMS="$*";
            ;;
        -m | --minionversion )
            MINION_VERSION_FLAG=1;
            shift;
            MINION_VERSION_PARAMS="$1";
            ;;
        -n | --reconfig )
            RECONFIG_FLAG=1;
            shift;
            RECONFIG_PARAMS="$*";
            ;;
        -q | --stop )
            STOP_FLAG=1;
            shift;
            ;;
        -p | --start )
            RESTART_FLAG=1;
            shift;
            ;;
        -r | --remove )
            UNINSTALL_FLAG=1;
            shift;
            ;;
        -s | --status )
            STATUS_CHK=1;
            shift;
            ;;
        -v | --version )
            VERSION_FLAG=1;
            shift;
            ;;
        -u | --upgrade )
            UPGRADE_FLAG=1;
            shift;
            ;;

        -- )
            shift;
            break;
            ;;
        * )
            shift;
            ;;
    esac
done

## check if want help, display usage and exit
if [[ ${USAGE_HELP} -eq 1 ]]; then
  _usage
  exit 0
fi


##  MAIN BODY OF SCRIPT

retn=0

# script options set using key=value (source, minionversion, loglevel),
# switches on the command line take precedence. Not needed, and must not be
# able to fail, when only the version of this script was asked for. The
# Windows script exits for -Version before it reads any options.
if [[ ${VERSION_FLAG} -eq 0 || $(( INSTALL_FLAG + RECONFIG_FLAG + STATUS_CHK + \
        DEPS_CHK + CLEAR_ID_KEYS_FLAG + UNINSTALL_FLAG + STOP_FLAG + \
        RESTART_FLAG )) -ne 0 ]]; then
    _apply_script_opts
fi

if [[ ${LOG_LEVEL_FLAG} -eq 1 ]]; then
    # ensure logging level changes are processed before any actions
    CLI_ACTION=1
    _set_log_level "${LOG_LEVEL_PARAMS}"
    retn=$?
fi
if [[ ${STATUS_CHK} -eq 1 ]]; then
    CLI_ACTION=1
    LOG_ACTION="status"
    _status_fn
    retn=$?
fi
if [[ ${DEPS_CHK} -eq 1 ]]; then
    CLI_ACTION=1
    LOG_ACTION="depend"
    _deps_chk_fn
    retn=$?
fi
if [[ ${SOURCE_FLAG} -eq 1 ]]; then
    CLI_ACTION=1
    LOG_ACTION="install"
    # ensure this is processed before install
    _validate_source_param "${SOURCE_PARAMS}"
    _source_fn "${SOURCE_PARAMS}"
    retn=$?
fi
if [[ ${MINION_VERSION_FLAG} -eq 1 ]]; then
    CLI_ACTION=1
    # ensure this is processed before install
    _validate_minion_version_param "${MINION_VERSION_PARAMS}"
    _set_install_minion_version_fn "${MINION_VERSION_PARAMS}"
    retn=$?
fi
if [[ ${UPGRADE_FLAG} -eq 1 ]]; then
    CLI_ACTION=1
    # ensure this is processed before install
    retn=$?
fi
if [[ ${INSTALL_FLAG} -eq 1 ]]; then
    CLI_ACTION=1
    LOG_ACTION="install"
    _install_fn "${INSTALL_PARAMS}"
    retn=$?
fi
if [[ ${CLEAR_ID_KEYS_FLAG} -eq 1 ]]; then
    CLI_ACTION=1
    LOG_ACTION="clear"
    _clear_id_key_fn "${CLEAR_ID_KEYS_PARAMS}"
    retn=$?
fi
if [[ ${UNINSTALL_FLAG} -eq 1 ]]; then
    CLI_ACTION=1
    LOG_ACTION="remove"
    _uninstall_fn
    retn=$?
fi
if [[ ${VERSION_FLAG} -eq 1 ]]; then
    CLI_ACTION=1
    echo "${SCRIPT_VERSION}"
    retn=0
fi
if [[ ${RECONFIG_FLAG} -eq 1 ]]; then
    CLI_ACTION=1
    LOG_ACTION="reconfig"
    _reconfig_fn "${RECONFIG_PARAMS}"
    retn=$?
fi
if [[ ${STOP_FLAG} -eq 1 ]]; then
    CLI_ACTION=1
    LOG_ACTION="default"
    _stop_fn
    retn=$?
fi
if [[ ${RESTART_FLAG} -eq 1 ]]; then
    CLI_ACTION=1
    LOG_ACTION="default"
    _restart_fn
    retn=$?
fi

if [[ ${CLI_ACTION} -eq 0 ]]; then
    # check if guest variables have an action since none from CLI
    # since none presented on the command line
    _get_desired_state

    if [[ -n "${GVAR_ACTION}" ]]; then
        case "${GVAR_ACTION}" in
            depend)
                LOG_ACTION="depend"
                _deps_chk_fn
                retn=$?
                ;;
            present)
                LOG_ACTION="install"
                _install_fn
                retn=$?
                ;;
            absent)
                LOG_ACTION="remove"
                _uninstall_fn
                retn=$?
                ;;
            status)
                LOG_ACTION="status"
                _status_fn
                retn=$?
                ;;
            # TBD what will VM TOOLS do for reconfig, upgrade, stop and start ?
            *)
                ;;
        esac
    fi
fi

_clean_up_log_files

exit ${retn}
