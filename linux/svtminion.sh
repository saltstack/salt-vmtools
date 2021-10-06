#!/usr/bin/env bash

# Copyright (c) 2021 VMware, Inc. All rights reserved.

## Salt VTtools Integration script
##  integration with Component Manager and GuestStore Helper

## Currently this script leverages the Salt Tiamat based SingleBinary Linux salt-minion
## TBD to leverage the Salt Tiamat based OneDir Linux salt-minion, once it is available

## set -u
## set -xT
set -o functrace
set -o pipefail
## set -o errexit

# using bash for now
# run this script as root, as needed to run salt

## SCRIPT_VERSION='2021.09.20.01'

# definitions

CURL_DOWNLOAD_RETRY_COUNT=5

## TBD these definitions will parse repo.json for 'latest' and download that when available
## these value in use for poc

## Repository locations and naming
readonly salt_name="salt"
readonly salt_url_version="3003.3-1"
readonly salt_pkg_name="${salt_name}-${salt_url_version}-linux-amd64.tar.gz"
readonly base_url="https://repo.saltproject.io/salt/vmware-tools-onedir"
readonly salt_url="${base_url}/${salt_url_version}/${salt_pkg_name}"
readonly salt_url_chksum_file="${salt_name}-${salt_url_version}_SHA512"
readonly salt_url_chksum="${base_url}/${salt_url_version}/${salt_url_chksum_file}"

# Salt file and directory locations
readonly base_salt_location="/opt/saltstack"
readonly salt_dir="${base_salt_location}/${salt_name}"
readonly test_exists_file="${salt_dir}/run/run"

readonly salt_conf_dir="/etc/salt"
readonly salt_minion_conf_name="minion"
readonly salt_minion_conf_file="${salt_conf_dir}/${salt_minion_conf_name}"
readonly salt_master_sign_dir="${salt_conf_dir}/pki/${salt_minion_conf_name}"

readonly salt_usr_bin_file_list="salt-minion
salt-call
"

readonly salt_systemd_file_list="salt-minion.service
"

readonly list_file_dirs_to_remove="${base_salt_location}
/etc/salt
/var/run/salt
/var/cache/salt
/var/log/salt
/usr/bin/salt-*
/usr/lib/systemd/system/salt-minion.service
/etc/systemd/system/salt-minion.service
"

readonly salt_dep_file_list="systemctl
curl
sha512sum
vmtoolsd
grep
awk
cut
"

## VMware file and directory locations
readonly vmtools_base_dir_etc="/etc/vmware-tools"
readonly vmtools_conf_file="tools.conf"
readonly vmtools_salt_minion_section_name="salt_minion"

## VMware guestVars file and directory locations
readonly guestvars_base_dir="guestinfo./vmware.components"
readonly guestvars_salt_dir="${guestvars_base_dir}.${vmtools_salt_minion_section_name}"
readonly guestvars_salt_args="${guestvars_salt_dir}.args"


# Array for minion configuration keys and values
# allows for updates from number of configuration sources before final write to /etc/salt/minion
declare -a minion_conf_keys
declare -a minion_conf_values


## Component Manager Installer/Script return/exit status codes
# return/exit Status codes
#  0 => installed
#  1 => installing
#  2 => notInstalled
#  3 => installFailed
#  4 => removing
#  5 => removeFailed
#  127 => scriptFailed
readonly STATUS_CODES=(installed installing notInstalled installFailed removing removeFailed scriptFailed)
scam=${#STATUS_CODES[@]}
for ((i=0; i<scam; i++)); do
    name=${STATUS_CODES[i]}
    if [[ "scriptFailed" = "${name}" ]]; then
        declare -r "${name}"=127
    else
        declare -r "${name}"=$i
    fi
done

STATUS_CHK=0
DEBUG_FLAG=0
DEPS_CHK=0
USAGE_HELP=0
## LOG_MODE='debug'
INSTALL_FLAG=0
CLEAR_ID_KEYS_FLAG=0
UNINSTALL_FLAG=0
VERBOSE_FLAG=0

# helper functions

_timestamp() {
    date "+%Y-%m-%d %H:%M:%S:"
}

_log() {
    echo "$(_timestamp) $1" >>"${LOGGING}"
}

# Both echo and log
# TBD logging needs update for "error", "info", "warning", "debug" similar to Windows

_display() {
    if [[ ${VERBOSE_FLAG} -eq 1 ]]; then echo "$1"; fi
    _log "$1"
}

_ddebug() {
    if [[ ${DEBUG_FLAG} -eq 1 ]]; then
        echo "$1"
        _log "$1"
    fi
}

_error() {
    msg="ERROR: $1"
    echo "$msg" 1>&2
    echo "$(_timestamp) $msg" >>"${LOGGING}"
    echo "One or more errors found. See ${LOGGING} for details." 1>&2
    CURRENT_STATUS="${STATUS_CODES[${scriptFailed}]}"
    exit 127
}

_warning() {
    msg="WARNING: $1"
    if [[ ${VERBOSE_FLAG} -eq 1 ]]; then echo "$msg" 1>&2; fi
    echo "$(_timestamp) $msg" >>"${LOGGING}"
}

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
     echo "usage: ${0}  [-c|--status] [-d|--debug] [-e|--depend] [-h|--help]"
     echo "             [-i|--install] [-k|--clear] [-r|--remove] [-v|--verbose]"
     echo ""
     echo "  -c, --status    return status for this script"
     echo "  -d, --debug     enable debugging logging"
     echo "  -e, --depend    check dependencies required to run this script exist"
     echo "  -h, --help      this message"
     echo "  -i, --install   install and activate the salt-minion"
     echo "  -k, --clear     clear previous minion identifer and keys,"
     echo "                     and set specified identifer if present"
     echo "  -r, --remove    deactivate and remove the salt-minion"
     echo "  -v, --verbose   enable verbose logging and messages"
     echo ""
     echo "  salt-minion vmtools integration script"
     echo "      example: $0 --status"
}


#
# _cleanup
#
#   Cleanups any running process and areas on exit or control-C
#
# Side Effects:
#   CURRENT_STATUS updated
#
# Results:
#   Exits with status
#

_cleanup() {
    # clean up any items if die and burn
    # last check of status on exit, interrupt, etc
    if [[ "${CURRENT_STATUS}" = "${STATUS_CODES[${scriptFailed}]}" ]]; then
        exit 127
    elif [[ "${CURRENT_STATUS}" = "${STATUS_CODES[${installing}]}" ]]; then
        CURRENT_STATUS="${STATUS_CODES[${installFailed}]}"
        exit 3
    elif [[ "${CURRENT_STATUS}" = "${STATUS_CODES[${installed}]}" ]]; then
        # normal case with exit 0, but double-check
        svpid=$(_find_salt_pid)
        if [[ -z ${svpid} || ! -f "${test_exists_file}" ]]; then
            CURRENT_STATUS="${STATUS_CODES[${installFailed}]}"
            exit 3
        fi
    elif [[ "${CURRENT_STATUS}" = "${STATUS_CODES[${removing}]}" ]]; then
        CURRENT_STATUS="${STATUS_CODES[${removeFailed}]}"
        svpid=$(_find_salt_pid)
        if [[ -z ${svpid} ]]; then
            if [[ ! -f "${test_exists_file}" ]]; then
                CURRENT_STATUS="${STATUS_CODES[$notInstalled]}"
                exit 2
            fi
        fi
        exit 5
    else
        # assume not installed
        CURRENT_STATUS="${STATUS_CODES[${notInstalled}]}"
        exit 2
    fi
    exit 0
}


## trap _cleanup INT TERM EXIT
trap _cleanup INT EXIT

## cheap trim relying on echo to convert tabs to spaces and all multiple spaces to a single space
_trim() {
    echo "$1"
}

# work functions
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
    local retn=0

    if [[ "$#" -ne 2 ]]; then
        _error "$0:${FUNCNAME[0]} error expect two parameters, a key and a value"
    fi

    # now search minion_conf_keys array to see if new key
    key_ary_sz=${#minion_conf_keys[@]}
    if [[ ${key_ary_sz} -ne 0 ]]; then
        # need to check if array has same key
        local chk_found=0
        for ((chk_idx=0; chk_idx<key_ary_sz; chk_idx++))
        do
            if [[ "${minion_conf_keys[${chk_idx}]}" = "${cfg_key}" ]]; then
                minion_conf_values[${chk_idx}]="${cfg_value}"
                chk_found=1
                break;
            fi
        done
        if [[ ${chk_found} -eq 0 ]]; then
            # new key for array
            minion_conf_keys[${key_ary_sz}]="${cfg_key}"
            minion_conf_values[${key_ary_sz}]="${cfg_value}"
        fi
    else
        # initial entry
        minion_conf_keys[0]="${cfg_key}"
        minion_conf_values[0]="${cfg_value}"
    fi
    return ${retn}
}


# work functions
#
# _fetch_vmtools_salt_minion_conf_tools_conf
#
#   Retrieve the configuration for salt-minion from vmtools configuration file tools.conf
#
# Results:
#   Exits with new vmtools configuration file if none found
#   or salt-minion configuration file updated with configuration read from vmtools
#   configuration file section for salt_minion
#

_fetch_vmtools_salt_minion_conf_tools_conf() {
    # fetch the current configuration for section salt_minion
    # from vmtoolsd configuration file
    local retn=0
    if [[ ! -f "${vmtools_base_dir_etc}/${vmtools_conf_file}" ]]; then
        # conf file doesn't exist, create it
        mkdir -p "${vmtools_base_dir_etc}"
        echo "[${vmtools_salt_minion_section_name}]" > "${vmtools_base_dir_etc}/${vmtools_conf_file}"
        _warning "Creating empty configuration file ${vmtools_base_dir_etc}/${vmtools_conf_file}"
    else
        # need to extract configuration for salt-minion
        # find section name ${vmtools_salt_minion_section_name}
        # read configuration till next section, and output to salt-minion conf file

        local salt_config_flag=0
        while IFS= read -r line
        do
            line_value=$(_trim "${line}")
            if [[ -n "${line_value}" ]]; then
                if echo "${line_value}" | grep -q '^\[' ; then
                    if [[ ${salt_config_flag} -eq 1 ]]; then
                        # if new section after doing salt config, we are done
                        break;
                    fi
                    if [[ ${line_value} = "[${vmtools_salt_minion_section_name}]" ]]; then
                        # have section, get configuration values, set flag and
                        #  start fresh salt-minion configuration file
                        salt_config_flag=1
                    fi
                elif [[ ${salt_config_flag} -eq 1 ]]; then
                    # read config here ahead of section check , better logic flow
                    cfg_key=$(echo "${line}" | cut -d '=' -f 1)
                    cfg_value=$(echo "${line}" | cut -d '=' -f 2)
                    _update_minion_conf_ary "${cfg_key}" "${cfg_value}" || {
                        _error "$0:${FUNCNAME[0]} error updating minion configuration array with key '${cfg_key}' and value '${cfg_value}', retcode '$?'";
                    }
                else
                    _display "skipping line '${line}'"
                fi
            fi
        done < "${vmtools_base_dir_etc}/${vmtools_conf_file}"
    fi
    return ${retn}
}

# work functions
#
# _fetch_vmtools_salt_minion_conf_guestvars
#
#   Retrieve the configuration for salt-minion from vmtools guest variables
#
# Results:
#   salt-minion configuration file updated with configuration read from vmtools guest variables
#   configuration file section for salt_minion
#

_fetch_vmtools_salt_minion_conf_guestvars() {
    # fetch the current configuration for section salt_minion
    # from  guest variables args

    local retn=0
    local gvar_args=""

    gvar_args=$(vmtoolsd --cmd "info-get ${guestvars_salt_args}") || {
        _warning "unable to retrieve arguments from guest variables location ${guestvars_salt_args}, retcode '$?'";
    }

    if [[ -z "${gvar_args}" ]]; then return ${retn}; fi

    for idx in ${gvar_args}
    do
        cfg_key=$(echo "${idx}" | cut -d '=' -f 1)
        cfg_value=$(echo "${idx}" | cut -d '=' -f 2)
        _update_minion_conf_ary "${cfg_key}" "${cfg_value}" || {
            _error "$0:${FUNCNAME[0]} error updating minion configuration array with key '${cfg_key}' and value '${cfg_value}', retcode '$?'";
        }
    done

    return ${retn}
}

# work functions
#
# _fetch_vmtools_salt_minion_conf_cli_args
#
#   Retrieve the configuration for salt-minion from any argsi '$@' passed on the command line
#
# Results:
#   Exits with new vmtools configuration file if none found
#   or salt-minion configuration file updated with configuration read from vmtools
#   configuration file section for salt_minion
#

_fetch_vmtools_salt_minion_conf_cli_args() {
    local retn=0
    local cli_args=""
    local cli_no_args=0

    cli_args="$*"
    cli_no_args=$#
    if [[ ${cli_no_args} -ne 0 ]]; then
        for idx in ${cli_args}
        do
            cfg_key=$(echo "${idx}" | cut -d '=' -f 1)
            cfg_value=$(echo "${idx}" | cut -d '=' -f 2)
            _update_minion_conf_ary "${cfg_key}" "${cfg_value}" || {
                _error "$0:${FUNCNAME[0]} error updating minion configuration array with key '${cfg_key}' and value '${cfg_value}', retcode '$?'";
            }
        done
    fi
    return ${retn}
}


# work functions

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
    echo "${ran_minion}"
}


#
# _fetch_vmtools_salt_minion_conf
#
#   Retrieve the configuration for salt-minion from vmtools configuration file
#
# Results:
#   Exits with new vmtools configuration file if none found
#   or salt-minion configuration file updated with configuration read from vmtools
#   configuration file section for salt_minion
#

_fetch_vmtools_salt_minion_conf() {
    # fetch the current configuration for section salt_minion
    # from vmtoolsd configuration file
    local retn=0
    _fetch_vmtools_salt_minion_conf_tools_conf || {
        _error "$0:${FUNCNAME[0]} failed to process tools.conf file, retcode '$?'";
    }
    _fetch_vmtools_salt_minion_conf_guestvars || {
        _error "$0:${FUNCNAME[0]} failed to process guest variable arguments, retcode '$?'";
    }
    _fetch_vmtools_salt_minion_conf_cli_args "$*" || {
        _error "$0:${FUNCNAME[0]} failed to process command line arguments, retcode '$?'";
    }

    # now write minion conf array to salt-minion configuration file
    local mykey_ary_sz=${#minion_conf_keys[@]}
    local myvalue_ary_sz=${#minion_conf_values[@]}
    if [[ "${mykey_ary_sz}" -ne "${myvalue_ary_sz}" ]]; then
        _error "$0:${FUNCNAME[0]} key '${mykey_ary_sz}' and value '${myvalue_ary_sz}' array sizes for minion_conf don't match"
    else
        mkdir -p "${salt_conf_dir}"
        echo "# Minion configuration file - created by vmtools salt script" > "${salt_minion_conf_file}"
        echo "enable_fqdns_grains: False" >> "${salt_minion_conf_file}"
        for ((chk_idx=0; chk_idx<mykey_ary_sz; chk_idx++))
        do
            # appending to salt-minion configuration file since it
            # should be new and no configuration set

            # check for special case of signed master's public key
            # verify_master_pubkey_sign=master_sign.pub
            if [[ "${minion_conf_keys[${chk_idx}]}" = "verify_master_pubkey_sign" ]]; then
                echo "${minion_conf_keys[${chk_idx}]}: True" >> "${salt_minion_conf_file}"
                mkdir -p "/etc/salt/pki/minion"
                cp -f "${minion_conf_values[${chk_idx}]}" "${salt_master_sign_dir}/"
            else
                echo "${minion_conf_keys[${chk_idx}]}: ${minion_conf_values[${chk_idx}]}" >> "${salt_minion_conf_file}"
            fi
        done
    fi
    return ${retn}
}


#
# _curl_download
#
#   Retrieve file from specifed url to specific file
#
# Results:
#   Exits with ${retn}
#

_curl_download() {
    local file_name="$1"
    local file_url="$2"
    local download_retry_failed=1       # assume issues

    for ((i=0; i<CURL_DOWNLOAD_RETRY_COUNT; i++))
    do
        curl -o "${file_name}" -fsSL "${file_url}" || {
            _warning "$0:${FUNCNAME[0]} failed to download file '${file_url}' on '${i}' attempt, retcode '$?'";
        } && {
            download_retry_failed=0
            break
        }
    done
    if [[ ${download_retry_failed} -ne 0 ]]; then
        _error "$0:${FUNCNAME[0]} failed to download file '${file_url}', retcode '$?'";
    fi
    return ${retn}
}


#
# _fetch_salt_minion
#
#   Retrieve the salt-minion from Salt repository
#
# Side Effects:
#   CURRENT_STATUS updated
#
# Results:
#   Exits with ${retn}
#

_fetch_salt_minion() {
    # fetch the current salt-minion into specified location
    # could check if alreasdy there but by always getting it
    # ensure we are not using stale versions
    local retn=0
    local calc_sha512sum=1
    local download_retry_failed=1       # assume issues

    CURRENT_STATUS="${STATUS_CODES[${installFailed}]}"
    mkdir -p ${base_salt_location}
    cd ${base_salt_location} || return $?
    _curl_download "${salt_pkg_name}" "${salt_url}"
    _curl_download "${salt_url_chksum_file}" "${salt_url_chksum}"
    calc_sha512sum=$(grep "${salt_pkg_name}" ${salt_url_chksum_file} | sha512sum --check --status)
    if [[ $calc_sha512sum -ne 0 ]]; then
        CURRENT_STATUS="${STATUS_CODES[${installFailed}]}"
        _error "$0:${FUNCNAME[0]} downloaded file '${salt_url}' failed to match checksum in file '${salt_url_chksum}'"
    fi

    tar -xvzf ${salt_pkg_name} 1>/dev/null
    if [[ ! -f ${test_exists_file} ]]; then
        CURRENT_STATUS="${STATUS_CODES[${installFailed}]}"
        _error "$0:${FUNCNAME[0]} expansiion of downloaded file '${salt_url}' failed to provide critical file '${test_exists_file}'"
    fi
    CURRENT_STATUS="${STATUS_CODES[${installed}]}"
    cd "${CURRDIR}" || return $?
    return ${retn}
}


#
# _find_salt_pid
#
#   finds the pid for the salt process
#
# Results:
#   Echos ${salt_pid} which could be empty '' if salt process not found
#

_find_salt_pid() {
    # find the pid for salt-minion if active
    local salt_pid=0
    salt_pid=$(pgrep -f "${salt_name}\/run\/run minion" | head -n 1 | awk -F " " '{print $1}')
    echo "${salt_pid}"
}

#
# _ensure_id_or_fqdn
#
#   Ensures that a valid minion identifier has been specified, and if not
#   a valid Fully Qualified Domain Name exists (not the default Unknown.example.org)
#   else generates a minion id to use.
#
# Note: this function should only be run before starting the salt-minion via systemd
#       after it has been installed
#
# Side Effect:
#   Updates salt-minion configuration file with generated identifer if no valid FQDN
#
# Results:
#   salt-minion configuration contains a valid identifier or FQDN to use.
#

_ensure_id_or_fqdn () {
    # ensure minion id or fqdn for salt-minion

    local retn=0
    local minion_fqdn=""

    minion_fqdn=$(/usr/bin/salt-call --local grains.get fqdn | grep -v 'local:' | xargs)
    if [[ -n "${minion_fqdn}" && "${minion_fqdn}" != "Unknown.example.org" ]]; then
        return ${retn}
    fi

    # default FQDN, check if id specified
    grep '^id:' < "${salt_minion_conf_file}" 1>/dev/null || {
        # no id is specified, generate one and update conf file
        echo "id: $(_generate_minion_id)" >> "${salt_minion_conf_file}"
    }

    return ${retn}
}


## Note: main command functions use return , not echo

#
# _status_fn
#
#   discover and return the current status
#
#       0 => installed
#       1 => installing
#       2 => notInstalled
#       3 => installFailed
#       4 => removing
#       5 => removeFailed
#
# Side Effects:
#   CURRENT_STATUS updated
#
# Results:
#   Exits numerical ${CURRENT_STATUS}
#

_status_fn() {
    # return status
    local retn_status=${notInstalled}
    if [[  "${CURRENT_STATUS}" = "${STATUS_CODES[${installing}]}"
        || "${CURRENT_STATUS}" = "${STATUS_CODES[${installFailed}]}"
        || "${CURRENT_STATUS}" = "${STATUS_CODES[${removing}]}"
        || "${CURRENT_STATUS}" = "${STATUS_CODES[${removeFailed}]}" ]]; then

        case "${CURRENT_STATUS}" in
            "${STATUS_CODES[${installing}]}")
                retn_status=${installing}
                ;;
            "${STATUS_CODES[${installFailed}]}")
                retn_status=${installFailed}
                ;;
            "${STATUS_CODES[${removing}]}")
                retn_status=${removing}
                ;;
            "${STATUS_CODES[${removeFailed}]}")
                retn_status=${removeFailed}
                ;;
            *)
                retn_status=${notInstalled}
                ;;
        esac
    elif [[ -f "${test_exists_file}" ]]; then
        CURRENT_STATUS="${STATUS_CODES[${installed}]}"
        retn_status=${installed}
    else
        CURRENT_STATUS="${STATUS_CODES[${notInstalled}]}"
        retn_status=${notInstalled}
    fi
    return "${retn_status}"
}


#
# _deps_chk_fn
#
#   Check dependencies for using salt-minion
#
#
# Side Effects:
#   CURRENT_STATUS updated
#
# Results:
#   Exits with ${retn}
#
_deps_chk_fn() {
    # return dependency check
    local retn=0
    local error_missing_deps=""

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
        _error "$0:${FUNCNAME[0]} failed to find required dependenices '${error_missing_deps}'";
    fi
    return ${retn}
}


#
#  _install_fn
#
#   Executes scripts to install Salt from Salt repository
#       and start the salt-minion using systemd
#
# Side Effects:
#   CURRENT_STATUS updated
#
# Results:
#   Exits with ${retn}
#

_install_fn () {
    # execute install of Salt minion
    local retn=0
    local existing_chk=""
    # check if salt-minion or salt-master (salt-cloud etc req master)
    # and log warning that they will be overwritten
    existing_chk=$(pgrep -l "salt-minion|salt-master" | cut -d ' ' -f 2 | uniq)
    if [[ -n  "${existing_chk}" ]]; then
        for idx in ${existing_chk}
        do
            local salt_fn=""
            salt_fn="$(basename "${idx}")"
            _warning "existing salt functionality ${salt_fn} shall be stopped and replaced when new salt-minion is installed"
        done
    fi

    # fetch salt-minion form repository
    _fetch_salt_minion || {
        _error "$0:${FUNCNAME[0]} failed to fetch salt-minion from repository , retcode '$?'";
    }

    # get configuration for salt-minion from tools.conf
    _fetch_vmtools_salt_minion_conf "$@" || {
        _error "$0:${FUNCNAME[0]} failed , read configuration for salt-minion from tools.conf, retcode '$?'";
    }

    # ensure minion id or fqdn for salt-minion
    _ensure_id_or_fqdn

    if [[ ${retn} -eq 0 && -f "${test_exists_file}" ]]; then
        # copy helper script for /usr/bin
        for idx in ${salt_usr_bin_file_list}
        do
            cp -a "${idx}" /usr/bin/ || {
                _error "$0:${FUNCNAME[0]} failed to copy helper file '${idx}' to directory /usr/bin, retcode '$?'";
            }
        done
        if [[ -n  "${existing_chk}" ]]; then
            # be nice and stop any current salt functionalty found
            for idx in ${existing_chk}
            do
                local salt_fn=""
                salt_fn="$(basename "${idx}")"
                _warning "stopping salt functionality ${salt_fn} as it is replaced with new installed salt-minion"
                systemctl stop "${salt_fn}" || {
                    _warning "$0:${FUNCNAME[0]} stopping existing salt functionality ${salt_fn} encountered difficulties using systemctl, it will be over-written with the new installed salt-minion regarlessly, retcode '$?'";
                }
            done
        fi
        # install salt-minion systemd service script
        for idx in ${salt_systemd_file_list}
        do
            cp -a "${idx}" /usr/lib/systemd/system/ || {
                _error "$0:${FUNCNAME[0]} failed to copy systemd service file '${idx}' to directory /usr/lib/systemd/system, retcode '$?'";
            }
            cd /etc/systemd/system || return $?
            rm -f "${idx}"
            ln -s "/usr/lib/systemd/system/${idx}" "${idx}" || {
                _error "$0:${FUNCNAME[0]} failed to symbolic link systemd service file '${idx}' in directory /etc/systemd/system, retcode '$?'";
            }
            cd "${CURRDIR}" || return $?

            # start the salt-minion using systemd
            systemctl daemon-reload || {
                _error "$0:${FUNCNAME[0]} reloading the systemd daemon failed , retcode '$?'";
            }
            local name_service=''
            name_service=$(echo "${idx}" | cut -d '.' -f 1)
            systemctl restart "${name_service}" || {
                _error "$0:${FUNCNAME[0]} starting the salt-minion using systemctl failed , retcode '$?'";
            }
            systemctl enable "${name_service}" || {
                _error "$0:${FUNCNAME[0]} enabling the salt-minion using systemctl failed , retcode '$?'";
            }
        done
    fi
    return ${retn}
}

#
# _generate_minion_id
#
#   Searchs salt-minion configuration file for current id, and disables it
#   and generates a new id based from the existng id found,
#   or an older commented out id, and provides it with a randomized 5 digit
#   postpended to it, for example:  myminion_12345
#
#   if no previous id found, a generated minion_<random number> is output
#
# Side Effects:
#   Disables any id found in minion configuration file
#
# Result:
#   Outputs randomized minion id for use in a minion configuration file

_generate_minion_id () {

    local retn=0
    local salt_id_flag=0
    local minion_id=""
    local cfg_value=""
    local ifield=""
    local tfields=""

    # always comment out what was there
    sed -i 's/^id/# id/g' "${salt_minion_conf_file}"

    while IFS= read -r line
    do
        line_value=$(_trim "${line}")
        if [[ -n "${line_value}" ]]; then
            if echo "${line_value}" | grep -q '^# id:' ; then
                # get value and write out value_<random>
                cfg_value=$(echo "${line_value}" | cut -d ' ' -f 3)
                if [[ -n "${cfg_value}" ]]; then
                    salt_id_flag=1
                    minion_id=$(_randomize_minion_id "${cfg_value}")
                fi
            elif echo "${line_value}" | grep -q -w 'id:' ; then
                # might have commented out id, get value and write out value_<random>
                ## tfields=$(sed 's/^[[:space:]]*//' <<< "$(echo "${line_value}" | awk -F ':' '{print $2}')")
                tfields=$(echo "${line_value}" | awk -F ':' '{print $2}' | xargs)
                ifield=$(echo "${tfields}" | cut -d ' ' -f 1)
                if [[ -n ${ifield} ]]; then
                    minion_id=$(_randomize_minion_id "${ifield}")
                    salt_id_flag=1
                fi
            else
                _display "skipping line '${line}'"
            fi
        fi
    done < "${salt_minion_conf_file}"

    if [[ ${salt_id_flag} -eq 0 ]]; then
        # no id field found, write minion_<random?
        minion_id=$(_randomize_minion_id)
    fi
    echo "${minion_id}"
    return ${retn}
}


#
# _clear_id_key_fn
#
#   Executes scripts to clear the minion identifer and keys and re-generates new identifer
#   allows for a VM containing a salt-minion, to be cloned and not have conflicting id and keys
#   salt-minion is stopped, id and keys cleared, and restarted if it was previously running
#
# Input:
#   Optional specified input ID to be used, default generate randomized value
#
# Note:
#   Normally a salt-minion if no id is specified will rely on it's Fully Qualified Domain Name
#   but with VM Cloning, there is no surety that the FQDN will have been altered, and duplicates
#   can occur. Also if there is no FQDN, then default 'Unknown.example.org' is used, again with
#   the issue of duplicates for multiple salt-minions with no FQDN specified
#
# Side Effects:
#   New minion identifier in configuration file and keys for the salt-minion
#
# Results:
#   Exits with ${retn}
#

_clear_id_key_fn () {
    # execute clearing of Salt minion id and keys
    local retn=0
    local salt_minion_pre_active_flag=0
    local salt_id_flag=0
    local minion_id=""
    local minion_ip_id=""

    if [[ ! -f "${test_exists_file}" ]]; then
        # salt-minion is not installed, nothing to do
        return ${retn}
    fi

    # get any minion identifier in case specified
    minion_ip_id="$1"
    svpid=$(_find_salt_pid)
    if [[ -n ${svpid} ]]; then
        # stop the active salt-minion using systemd
        # and give it a little time to stop
        systemctl stop salt-minion || {
            _error "$0:${FUNCNAME[0]} failed to stop salt-minion using systemctl, retcode '$?'";
        }
        salt_minion_pre_active_flag=1
    fi

    rm -fR "${salt_conf_dir}/minion_id"
    rm -fR "${salt_conf_dir}/pki/${salt_minion_conf_name}"
    # always comment out what was there
    sed -i 's/^id/# id/g' "${salt_minion_conf_file}"

    if [[ -z "${minion_ip_id}" ]] ;then
        minion_id=$(_generate_minion_id)
    else
        minion_id="${minion_ip_id}"
    fi

    # add new minion id to bottom of minion configuration file
    echo "id: ${minion_id}" >> "${salt_minion_conf_file}"

    if [[ ${salt_minion_pre_active_flag} -eq 1 ]]; then
        # restart the stopped salt-minion using systemd
        systemctl restart salt-minion || {
            _error "$0:${FUNCNAME[0]} failed to restart salt-minion using systemctl, retcode '$?'";
        }
    fi

    exit ${retn}
}


#
# _remove_installed_files_dirs
#
#   Removes all Salt files and directories that may be used
#

 _remove_installed_files_dirs() {
    local retn=0
    for idx in ${list_file_dirs_to_remove}
    do
        rm -fR "${idx}" || {
            _error "$0:${FUNCNAME[0]} failed to remove file or directory '${idx}' , retcode '$?'";
        }
    done
    return ${retn}
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
#   Exits with ${retn}
#

_uninstall_fn () {
    # remove Salt minion
    local retn=0
    if [[ ! -f "${test_exists_file}" ]]; then
        CURRENT_STATUS="${STATUS_CODES[${notInstalled}]}"

        # assumme rest is gone
        # TBD enhancement, could loop thru and check all of files to remove and if salt_pid empty
        #   but we error out if issues when uninstalling, so safe for now.
        retn=0
    else
        CURRENT_STATUS="${STATUS_CODES[${removing}]}"
        svpid=$(_find_salt_pid)
        if [[ -n ${svpid} ]]; then
            # stop the active salt-minion using systemd
            # and give it a little time to stop
            systemctl stop salt-minion || {
                _error "$0:${FUNCNAME[0]} failed to stop salt-minion using systemctl, retcode '$?'";
            }
            systemctl disable salt-minion || {
                _error "$0:${FUNCNAME[0]} disabling the salt-minion using systemctl failed , retcode '$?'";
            }
        fi

        if [[ ${retn} -eq 0 ]]; then
            svpid=$(_find_salt_pid)
            if [[ -n ${svpid} ]]; then
                kill "${svpid}"
                ## given it a little time
                sleep 5
            fi
            svpid=$(_find_salt_pid)
            if [[ -n ${svpid} ]]; then
                CURRENT_STATUS="${STATUS_CODES[$removeFailed]}"
                _error "$0:${FUNCNAME[0]} failed to kill the salt-minion, pid '${svpid}' during uninstall"
            else
                _remove_installed_files_dirs || {
                    _error "$0:${FUNCNAME[0]} failed to remove all installed salt-minion files and directories, retcode '$?'";
                }
                CURRENT_STATUS="${STATUS_CODES[$notInstalled]}"
            fi
        fi
    fi
    return ${retn}
}



################################### MAIN ####################################

# static definitions

CURRDIR=$(pwd)

# default status is notInstalled
CURRENT_STATUS="${STATUS_CODES[$notInstalled]}"

## build designation tag used for auto builds is YearMontDayHourMinuteSecondMicrosecond aka jid
date_long=$(date +%Y%m%d%H%M%S%N)
curr_date="${date_long::-2}"

# set logging infomation
## want verbose while developing
LOGGING="/dev/null"
SCRIPTNAME=$(basename "$0")
log_file="/var/log/salt/$SCRIPTNAME-${curr_date}.log"

if [[ ${VERBOSE_FLAG} -ne 0 ]];then
    LOGGING="${log_file}"
else
    LOGGING="/dev/null"
fi


## need support at a minimum for the following:
## depends
## deploy
## remove
## check
##
## Optionals:
##   predeploy
##   postdeploy
##   preremove
##   postremove
##
## ##    -l | --log )  LOG_MODE="$2"; shift 2 ;;

while true; do
    case "$1" in
        -c | --status ) STATUS_CHK=1; shift ;;
        -d | --debug )  DEBUG_FLAG=1; shift ;;
        -e | --depend ) DEPS_CHK=1; shift ;;
        -h | --help ) USAGE_HELP=1; shift ;;
        -i | --install ) INSTALL_FLAG=1; shift ;;
        -k | --clear ) CLEAR_ID_KEYS_FLAG=1; shift ;;
        -r | --remove ) UNINSTALL_FLAG=1; shift ;;
        -v | --verbose ) VERBOSE_FLAG=1; shift ;;
        -- ) shift; break ;;
        * ) break ;;
    esac
done

## check if want help, display usage and exit
if [[ ${USAGE_HELP} -eq 1 ]]; then
  _usage
  exit 0
fi


##  MAIN BODY OF SCRIPT

# check if salt-minion is installed
if [[ -f "${test_exists_file}" ]]; then CURRENT_STATUS="${STATUS_CODES[$installed]}"; fi

retn=0

if [[ ${STATUS_CHK} -eq 1 ]]; then
    _status_fn
    retn=$?
elif [[ ${DEPS_CHK} -eq 1 ]]; then
    _deps_chk_fn
    retn=$?
elif [[ ${INSTALL_FLAG} -eq 1 ]]; then
    _install_fn "$@"
    retn=$?
elif [[ ${CLEAR_ID_KEYS_FLAG} -eq 1 ]]; then
    _clear_id_key_fn "$@"
    retn=$?
elif [[ ${UNINSTALL_FLAG} -eq 1 ]]; then
    _uninstall_fn
    retn=$?
else
    # check if guest variables have an action
    # since none presented on the command line
    gvar_action=$(vmtoolsd --cmd "info-get ${guestvars_salt_dir}") || {
        _warning "unable to retrieve any action arguments from guest variables ${guestvars_salt_dir}, retcode '$?'";
    }

    if [[ -z "${gvar_action}" ]]; then
        _usage
    else
        case "${gvar_action}" in
            depend)
                _deps_chk_fn
                retn=$?
                ;;
            add)
                _install_fn
                retn=$?
                ;;
            remove)
                _uninstall_fn
                retn=$?
                ;;
            status)
                _status_fn
                retn=$?
                ;;
            *)
                ;;
        esac
    fi
fi

exit ${retn}
