#!/usr/bin/bash

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

SCRIPT_VERSION='2021.09.02.01'

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

STATUS_CHK=0
DEBUG_FLAG=0
DEPS_CHK=0
USAGE_HELP=0
LOG_MODE='debug'
INSTALL_FLAG=0
UNINSTALL_FLAG=0
VERBOSE_FLAG=0

# helper functions

_timestamp() {
    date "+%Y-%m-%d %H:%M:%S:"
}

_log() {
    echo "$1" | sed "s/^/$(_timestamp) /" >>"${LOGGING}"
}

# Both echo and log
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
    exit 1
}

_warning() {
    msg="WARNING: $1"
    echo "$msg" 1>&2
    echo "$(_timestamp) $msg" >>"${LOGGING}"
}

_yesno() {
read -p "Continue (y/n)?" choice
case "$choice" in
  y|Y ) echo "yes";;
  n|N ) echo "no";;
  * ) echo "invalid";;
esac
}

 _usage() {
     echo ""
     echo "usage: ${0}  [-c|--status] [-d|--debug] [-e|--depends]"
     echo "             [-h|--help] [-i|--install] [-r|--remove] [-v|--verbose]"
     echo ""
     echo "  -c, --status    return status for this script"
     echo "  -d, --debug     enable debugging logging"
     echo "  -e, --depend    check dependencies required to run this script exist"
     echo "  -h, --help      this message"
     echo "  -i, --install   install and activate the salt-minion"
     echo "  -r, --remove    deactivate and remove the salt-minion"
     echo "  -v, --verbose   enable verbose logging and messages"
     echo ""
     echo "  salt-minion vmtools integration script"
     echo "      example: $0 --status"
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
    # could check if alreasdy there but by always getting it
    # ensure we are not using stale versions
    local retn=0
    CURRENT_STATUS=${STATUS_CODES[${installing}]}
    mkdir -p ${salt_dir}
    cd ${salt_dir}
    curl -o "${salt_pkg_name}" -fsSL "${salt_url}"
    tar -xvzf ${salt_pkg_name}
    if [[ ! -f ${salt_name} ]]; then
        CURRENT_STATUS=${STATUS_CODES[${installFailed}]}
        retn=1
    fi
    CURRENT_STATUS=${STATUS_CODES[${installed}]}
    return ${retn}
}

_find_salt_pip() {
    # find the pid for salt if active
    local salt_pid=$(ps -ef | grep -v 'grep' | grep salt | head -n 1 | awk -F " " '{print $2}')
    echo ${salt_pid}
}

## Note: main command functions use return , not echo
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
    local retn==0
    if [[ -f "${salt_dir}/{${salt_name}" ]]; then
        CURRENT_STATUS=${STATUS_CODES[${installed}]}
        retn=0
    else
        CURRENT_STATUS=${STATUS_CODES[${notInstalled}]}
        retn=1
    fi
   return ${retn} 
}


_install_fn () {
    # execute install of Salt minion
    _fetch_salt_minion
    local retn=$?

    #TBD need to pull in args for master key, master IP or DNS, minion id
    if [[ ${retn} -eq 0 && -f "${salt_dir}/${salt_name}" ]]; then
        echo "_install_fn starting ${salt_dir}/${salt_name} minion in bg"
        $(nohup ${salt_dir}/${salt_name} "minion" &)
        retn=0
    fi
    return ${retn}
}


_uninstall_fn () {
    # remove Salt miniona
    local retn=0
    if [[ -f "${salt_dir}/{${salt_name}" ]]; then
        CURRENT_STATUS=${STATUS_CODES[${notInstalled}]}
        retn=1
    fi
    CURRENT_STATUS=${STATUS_CODES[${removing}]}
    svpid=$(_find_salt_pip)
    if [[ -n ${svpid} ]]; then
        kill ${svpid} 
        ## given it a little time
        sleep 1 
    fi
    svpid=$(_find_salt_pip)
    if [[ -n ${svpid} ]]; then
        CURRENT_STATUS=${STATUS_CODES[$removeFailed]}
        retn=1
    else
        rm -fR ${base_salt_location}
        CURRENT_STATUS=${STATUS_CODES[$notInstalled]}
    fi
    return ${retn}
}



################################### MAIN ####################################

# static definitions

CURRDIR=$(pwd)

# default status is notInstalled
CURRENT_STATUS=${STATUS_CODES[$notInstalled]}

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
    -e | --depends ) DEPS_CHK=1; shift ;;
    -h | --help ) USAGE_HELP=1; shift ;;
    -i | --install ) INSTALL_FLAG=1; shift ;;
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

_display "$SCRIPTNAME: autobuild started"

# check if salt-minion is installed
if [[ -f "${salt_dir}/{${salt_name}" ]]; then CURRENT_STATUS=${STATUS_CODES[$notInstalled]}; fi
_ddebug "$SCRIPTNAME: CURRENT_STATUS on startup is ${CURRENT_STATUS}"

retn=0

if [[ ${STATUS_CHK} -eq 1 ]]; then
    _status_fn
    retn=$?
    exit ${retn}
elif [[ ${DEPS_CHK} -eq 1 ]]; then
    _deps_chk_fn
    retn=$?
    exit ${retn}
elif [[ ${INSTALL_FLAG} -eq 1 ]]; then
    _install_fn
    retn=$?
    exit ${retn}
elif [[ ${UNINSTALL_FLAG} -eq 1 ]]; then
    _uninstall_fn
    retn=$?
    exit ${retn}
else
    _usage
fi

# doing this until onedir and daemonization is available
# exit is by Cntl-C
while [[ ${CURRENT_STATUS} -eq ${STATUS_CODES[${installed}]} ]];
do 
    sleep 2
done


