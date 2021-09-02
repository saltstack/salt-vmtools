#!/usr/bin/bash

set -u
set -o functrace
set -o pipefail
## set -o errexit

# using bash for now
# run this script as root, as needed to run salt

SCRIPT_VERSION='2021.09.01.01'

# definitions

## TBD these definitions will parse repo.json for 'latest' and download that when available
## these value in use for poc

readonly salt_name="salt"
readonly salt_pkg_name="salt-3003-3-linux-amd64.tar.gz"
readonly base_url="https://repo.saltproject.io/salt/singlebin"
readonly salt_url="${base_url}/3003/${salt_pkg_name}"
readonly salt_url_chksum="${base_url}/3003/salt-3003_SHA3_512"

readonly base_salt_location="/opt/saltstack"
readonly salt_dir="${base_salt_location}/salt"

# return Status codes
#  0 => installed
#  1 => installing
#  2 => notInstalled
#  3 => installFailed
#  4 => removing
#  5 => removeFailed
readonly STATUS_CODES=(installed installing notInstalled installFailed removing removeFailed)
scam=${#STATUS_CODES[@]}
for ((i=0; i<${scam}; i++)); do
    name=${STATUS_CODES[i]}
    declare -r ${name}=$i
done


# helper functions

_timestamp() {
    date "+%Y-%m-%d %H:%M:%S:"
}

_log() {
    echo "$1" | sed "s/^/$(_timestamp) /" >>"${LOGGING}"
}

# Both echo and log
_display() {
    if [[ ${VERBOSE} ]]; then echo "$1"; fi
    _log "$1"
}

_ddebug() {
    if [[ ${DEBUG} ]]; then
        echo "$1"
        _log "$1"
    fi
}

_error() {
    msg="ERROR: $1"
    echo "$msg" 1>&2
    echo "$(_timestamp) $msg" >>"${LOGGING}"
    echo "One or more errors found. See ${LOGGING} for details." 1>&2
    exit 1
}

_warning() {
    msg="WARNING: $1"
    echo "$msg" 1>&2
    echo "$(_timestamp) $msg" >>"${LOGGING}"
}

    [-c | --status]
    [-e | --depends]
    [-i | --install]
    [-r | --remove]
    [-v | --verbose]
_usage() {
    echo ""
    echo "usage: ${0}  [-c|--status] [-d|--debug] [-e|--depends]"
    echo "             [-i|--install] [-r|--remove] [-v|--verbose]"
    echo ""
    echo "  salt-minion vmtools integration script"
    echo "      example: $0 --status"
    echo ""
}


_yesno() {
read -p "Continue (y/n)?" choice
case "$choice" in
  y|Y ) echo "yes";;
  n|N ) echo "no";;
  * ) echo "invalid";;
esac
}


_cleanup() {
    # clean up any items if die and burn
    # don't know the worth of setting the current status, since script died
    if [[ ${CURRENT_STATUS} -eq ${STATUS_CODES[${installing}]} ]]; then
        CURRENT_STATUS=${STATUS_CODES[${installFailed}]}
    elif [[ ${CURRENT_STATUS} -eq ${STATUS_CODES[${removing}]} ]]; then
        CURRENT_STATUS=${STATUS_CODES[${removeFailed}]}
    else
        CURRENT_STATUS=${STATUS_CODES[${notInstalled}]}
    fi
}


trap _cleanup INT TERM EXIT

# work functions

_fetch_salt_minion() {
    # fetch the current salt-minion into specified location
    CURRENT_STATUS=${STATUS_CODES[${installing}]}
    mkdir -p ${salt_dir}
    cd ${salt_dir}
    curl -fsSL ${salt_url}
    tar -xvzf ${salt_pkg_name}
    if [[ -f ${salt_name} ]]; then
        CURRENT_STATUS=${STATUS_CODES[${installed}]}
    else
        CURRENT_STATUS=${STATUS_CODES[${installFailed}]}
        exit
    fi
}

_find_salt_pip() {
    # find the pid for salt if active
    salt_pid=$(ps -ef | grep -v 'grep' | grep salt | head -n 1 | awk -F " " '{print $2}')
    return ${salt_pid}
}

_status_fn() {
    # return status
    if [[ ${CURRENT_STATUS} -eq  ${STATUS_CODES[${installing}]}
        || ${CURRENT_STATUS} -eq ${STATUS_CODES[${installFailed}]}
        || ${CURRENT_STATUS} -eq ${STATUS_CODES[${removing}]}
        || ${CURRENT_STATUS} -eq ${STATUS_CODES[${removeFailed}]} ]]; then
        return ${CURRENT_STATUS}
    fi
    if [[ -f "${salt_dir}/{${salt_name}" ]]; then
        CURRENT_STATUS=${STATUS_CODES[${installed}]}
    else
        CURRENT_STATUS=${STATUS_CODES[${notInstalled}]}
    fi
    return ${CURRENT_STATUS}
}

_deps_chk_fn() {
    # return dependency check
    if [[ "${salt_dir}/{${salt_name}" ]]; then
        CURRENT_STATUS=${STATUS_CODES[${installed}]}
    else
        CURRENT_STATUS=${STATUS_CODES[${notInstalled}]}
    fi
    _debug "$SCRIPTNAME: _deps_chk_fn CURRENT_STATUS is ${CURRENT_STATUS}"
}


_install_fn () {
    # execute install of Salt minion
    _fetch_salt_minion

    #TBD need to pull in args for master key, master IP or DNS, minion id
    if [[ "${salt_dir}/{${salt_name}" ]]; then
        cd "${salt_dir}/{${salt_name}"
        ./salt&
    fi
}


_uninstall_fn () {
    # remove Salt minion
    if [[ "${salt_dir}/{${salt_name}" ]]; then
        CURRENT_STATUS=${STATUS_CODES[${notInstalled}]}
        return
    fi
    CURRENT_STATUS=${STATUS_CODES[${removing}]}
    pid=_find_salt_pip
    if [[ -n ${pid} ]]; then kill ${pid}; fi
    ## given it a little time
    sleep 1
    pid=_find_salt_pip
    if [[ -n ${pid} ]]; then
        CURRENT_STATUS=${STATUS_CODES[$removeFailed]}
    else
        rm -fR ${base_salt_location}
        CURRENT_STATUS=${STATUS_CODES[$notInstalled]}
    fi
}



################################### MAIN ####################################

# static definitions

CURRDIR=$(pwd)

VERBOSE=0
DEBUG=False
USAGE_HELP=False
LOG_MODE='debug'

# default status is notInstalled
CURRENT_STATUS=${STATUS_CODES[$notInstalled]}

## build designation tag used for auto builds is YearMontDayHourMinuteSecondMicrosecond aka jid
date_long=$(date +%Y%m%d%H%M%S%N)
curr_date="${date_long::-2}"

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

##    -l | --log )  LOG_MODE="$2"; shift 2 ;;
##    -z | --nfs_absdir ) NFS_ABSDIR="$2"; shift 2 ;;


while true; do
  case "${1}" in
    -c | --status ) STATUS_CHK=1; shift ;;
    -d | --debug )  DEBUG=True; shift ;;
    -e | --depends ) DEPS_CHK=1; shift ;;
    -i | --install ) INSTALL=1; shift ;;
    -r | --remove ) UNINSTALL=1; shift ;;
    -v | --verbose ) VERBOSE=1; shift ;;
    -- ) shift; break ;;
    * ) break ;;
  esac
done

## check if want help, display usage and exit
[[ ${USAGE_HELP} = 'false' ]] || {
  _usage
  exit 0
}

# set logging infomation
## want verbose while developing
LOGGING="/dev/null"
SCRIPTNAME=$(basename "$0")
log_file="/var/log/salt/$SCRIPTNAME-${curr_date}.log"

if [[ ${VERBOSE} -ne 0 ]];then
    LOGGING="${log_file}"
else
    LOGGING="/dev/null"
fi


##  MAIN BODY OF SCRIPT

_display "$SCRIPTNAME: autobuild started"

# check if salt-minion is installed
if [[ -f "${salt_dir}/{${salt_name}" ]]; then CURRENT_STATUS=${STATUS_CODES[$notInstalled]}; fi
_debug "$SCRIPTNAME: CURRENT_STATUS on startup is ${CURRENT_STATUS}"

if [[ ${STATUS_CHK} ]]; then
    retn=$(_status_fn)
    exit ${retn}
elif [[ ${DEPS_CHK} ]]; then
    retn=$(_deps_chk_fn)
    exit ${retn}
elif [[ ${INSTALL} ]]; then
    retn=$(_install_fn)
    exit ${retn}
elif [[ ${UNINSTALL} ]]; then
    retn=$(_uninstall_fn)
    exit ${retn}
else
    usage
fi



