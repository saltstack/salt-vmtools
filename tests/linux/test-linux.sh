#!/bin/bash

# Testing assumes RedHat family

oldpwd=$(pwd)
mkdir -p /root/ || true
## echo "machine gitlab.com login gitlab-ci-token password ${CI_JOB_TOKEN}" >> ~/.netrc
id
date
yum makecache
ls -alh
sleep 1
ls -alh linux/svtminion.sh
sleep 1
cd linux
./svtminion.sh --depend || { _retn=$?; if [[ ${_retn} -eq 126 ]]; then echo "test correct"; else echo "test failed, should be missing at least the vmtoolsd dependency, returned '${_retn}'"; exit 1; fi; }
ls -alh /var/log/vmware-svtminion.sh-depend-*
yum -y install open-vm-tools
yum -y install --allowerasing curl
yum -y install wget
yum -y install procps-ng
# Validate --source parameter
./svtminion.sh --source "https://bad url.com" --install || \
    { _retn=$?; if [[ ${_retn} -eq 126 ]]; then echo "test correct"; \
      else echo "test failed, bad source should exit 126, got '${_retn}'"; exit 1; fi; }
./svtminion.sh --source "notascheme://bad" --install || \
    { _retn=$?; if [[ ${_retn} -eq 126 ]]; then echo "test correct"; \
      else echo "test failed, bad source scheme should exit 126, got '${_retn}'"; exit 1; fi; }
./svtminion.sh --source "https://evil.com/path;bad" --install || \
    { _retn=$?; if [[ ${_retn} -eq 126 ]]; then echo "test correct"; \
      else echo "test failed, source with injection char should exit 126, got '${_retn}'"; exit 1; fi; }
# Validate --minionversion parameter
./svtminion.sh --minionversion "bad version" --install || \
    { _retn=$?; if [[ ${_retn} -eq 126 ]]; then echo "test correct"; \
      else echo "test failed, bad minionversion should exit 126, got '${_retn}'"; exit 1; fi; }
./svtminion.sh --minionversion "3006;evil" --install || \
    { _retn=$?; if [[ ${_retn} -eq 126 ]]; then echo "test correct"; \
      else echo "test failed, minionversion injection should exit 126, got '${_retn}'"; exit 1; fi; }
./svtminion.sh --depend --loglevel info || { _retn=$?; echo "test failed, there should be no missing dependencies, returned '${_retn}'"; }
ls -l /var/log/vmware-svtminion.sh-depend-* | wc -l
if [[ 2 -eq $(ls -l /var/log/vmware-svtminion.sh-depend-* | wc -l) ]]; then echo "test correct"; else "test failed, should be 2 depend log files"; exit 1; fi
ps -ef | grep svtminion
pgrep -f "svtminion.sh"
./svtminion.sh --status --loglevel info || { _retn=$?; if [[ ${_retn} -eq 102 ]]; then echo "test correct"; else echo "test failed, salt-minion should not be installed, returned '${_retn}'"; exit 1; fi; }
ls -alh /var/log/vmware-svtminion.sh-status-*
./svtminion.sh --status && { echo "test failed- expecting 102 exit code, salt-minion should not be installed"; exit 1; }
./svtminion.sh --install master=192.168.0.5 --loglevel debug
cat /etc/salt/minion
cat /etc/salt/minion | grep 'master:\ 192.168.0.5' 1>/dev/null
myhost=$(hostname)
myfqdn=$(/usr/bin/salt-call --local grains.get fqdn | sed "s/'//g")
if [[ "${myhost}" = "${myfqdn}" ]]; then "echo test correct" else echo "test failed, FQDN '${myfqdn}' should have match hostname '${myhost}'"; exit 1; fi
ls -alh /opt/saltstack/salt/salt-minion
ls -alh /usr/bin/salt-call
ls -alh /usr/bin/salt-minion
getent group salt | grep -w salt
cat /etc/passwd | grep -w salt
/usr/bin/salt-call --local test.versions
/usr/bin/salt-call --local grains.items
/usr/bin/salt-call --local cmd.run "ls -al /"
./svtminion.sh --status || { _retn=$?; if [[ ${_retn} -eq 100 ]]; then echo "test correct"; else echo "test failed, salt-minion should be installed, returned '${_retn}'"; exit 1; fi; }
./svtminion.sh --clear myminion
cat /etc/salt/minion | grep 'id:\ myminion' 1>/dev/null
./svtminion.sh --clear
cat /etc/salt/minion | grep '# id:\ myminion' 1>/dev/null
cat /etc/salt/minion | grep 'id:\ myminion_' 1>/dev/null
./svtminion.sh --remove || { _retn=$?; echo "test failed, did not uninstall the salt-minion, returned '${_retn}'"; }
list_dirs_to_chk_removed="/opt/saltstack /etc/salt /var/run/salt /var/cache/salt /var/log/salt"
for idx in ${list_dirs_to_chk_removed}; do if [[ -d "${idx}" ]]; then echo "directory ${idx} is left after a remove"; exit 1; fi; done
list_files_to_chk_removed="/usr/bin/salt-call /usr/bin/salt-minion /usr/lib/systemd/system/salt-minion.service /etc/systemd/system/salt-minion.service"
for idx in ${list_files_to_chk_removed}; do if [[ -f "${idx}" ]]; then echo "file ${idx} is left after a remove"; exit 1; fi; done
./svtminion.sh --status || { _retn=$?; if [[ ${_retn} -eq 102 ]]; then echo "test correct"; else echo "test failed, salt-minion should not be installed, returned '${_retn}'"; exit 1; fi; }
./svtminion.sh --status && { echo "test failed- expecting 102 exit code, salt-minion should not be installed"; exit 1; }
./svtminion.sh --version --loglevel debug
ls -alh /var/log/vmware-svtminion.sh-default-*
# if version not found, defaults to latest
./svtminion.sh --minionversion "3004.2-1" --install master=192.168.0.6 --loglevel debug
ls -alh /opt/saltstack/salt/run/
cat /etc/salt/minion | grep 'master:\ 192.168.0.6' 1>/dev/null
myhost=$(hostname)
myfqdn=$(/usr/bin/salt-call --local grains.get fqdn | sed "s/'//g")
if [[ "${myhost}" = "${myfqdn}" ]]; then "echo test correct" else echo "test failed, FQDN '${myfqdn}' should have match hostname '${myhost}'"; exit 1; fi
./svtminion.sh --status --loglevel debug || { _retn=$?; if [[ ${_retn} -eq 100 ]]; then echo "test correct"; else echo "test failed, salt-minion should be installed, returned '${_retn}'"; exit 1; fi; }
sleep 1
./svtminion.sh --status --loglevel debug || { _retn=$?; if [[ ${_retn} -eq 100 ]]; then echo "test correct"; else echo "test failed, salt-minion should be installed, returned '${_retn}'"; exit 1; fi; }
sleep 1
./svtminion.sh --status --loglevel debug || { _retn=$?; if [[ ${_retn} -eq 100 ]]; then echo "test correct"; else echo "test failed, salt-minion should be installed, returned '${_retn}'"; exit 1; fi; }
sleep 1
./svtminion.sh --status --loglevel debug || { _retn=$?; if [[ ${_retn} -eq 100 ]]; then echo "test correct"; else echo "test failed, salt-minion should be installed, returned '${_retn}'"; exit 1; fi; }
sleep 1
./svtminion.sh --status --loglevel debug || { _retn=$?; if [[ ${_retn} -eq 100 ]]; then echo "test correct"; else echo "test failed, salt-minion should be installed, returned '${_retn}'"; exit 1; fi; }
sleep 1
./svtminion.sh --status --loglevel debug || { _retn=$?; if [[ ${_retn} -eq 100 ]]; then echo "test correct"; else echo "test failed, salt-minion should be installed, returned '${_retn}'"; exit 1; fi; }
sleep 1
./svtminion.sh --status --loglevel debug || { _retn=$?; if [[ ${_retn} -eq 100 ]]; then echo "test correct"; else echo "test failed, salt-minion should be installed, returned '${_retn}'"; exit 1; fi; }
sleep 1
./svtminion.sh --status --loglevel debug || { _retn=$?; if [[ ${_retn} -eq 100 ]]; then echo "test correct"; else echo "test failed, salt-minion should be installed, returned '${_retn}'"; exit 1; fi; }
sleep 1
./svtminion.sh --status --loglevel debug || { _retn=$?; if [[ ${_retn} -eq 100 ]]; then echo "test correct"; else echo "test failed, salt-minion should be installed, returned '${_retn}'"; exit 1; fi; }
sleep 1
./svtminion.sh --status --loglevel debug || { _retn=$?; if [[ ${_retn} -eq 100 ]]; then echo "test correct"; else echo "test failed, salt-minion should be installed, returned '${_retn}'"; exit 1; fi; }
sleep 1
./svtminion.sh --status --loglevel debug || { _retn=$?; if [[ ${_retn} -eq 100 ]]; then echo "test correct"; else echo "test failed, salt-minion should be installed, returned '${_retn}'"; exit 1; fi; }
sleep 1
./svtminion.sh --status --loglevel debug || { _retn=$?; if [[ ${_retn} -eq 100 ]]; then echo "test correct"; else echo "test failed, salt-minion should be installed, returned '${_retn}'"; exit 1; fi; }
sleep 1
./svtminion.sh --status --loglevel debug || { _retn=$?; if [[ ${_retn} -eq 100 ]]; then echo "test correct"; else echo "test failed, salt-minion should be installed, returned '${_retn}'"; exit 1; fi; }
sleep 1
./svtminion.sh --status --loglevel debug || { _retn=$?; if [[ ${_retn} -eq 100 ]]; then echo "test correct"; else echo "test failed, salt-minion should be installed, returned '${_retn}'"; exit 1; fi; }
ls -l /var/log/vmware-svtminion.sh-status-*
ls -l /var/log/vmware-svtminion.sh-status-* | wc -l
if [[ 5 -eq $(ls -l /var/log/vmware-svtminion.sh-status-* | wc -l) ]]; then echo "test correct"; else "test failed, should be only 5 status log files"; exit 1; fi
./svtminion.sh --remove || { _retn=$?; echo "test failed, did not uninstall the salt-minion, returned '${_retn}'"; }
./svtminion.sh --source ${oldpwd}/tests/testarea --install master=192.168.0.5 --loglevel debug
cat /etc/salt/minion
cat /etc/salt/minion | grep 'master:\ 192.168.0.5' 1>/dev/null
./svtminion.sh --status --loglevel debug || { _retn=$?; if [[ ${_retn} -eq 100 ]]; then echo "test correct"; else echo "test failed, salt-minion should be installed, returned '${_retn}'"; exit 1; fi; }
sleep 1
./svtminion.sh --remove || { _retn=$?; echo "test failed, did not uninstall the salt-minion, returned '${_retn}'"; }
./svtminion.sh --source file:/${oldpwd}/tests/testarea --install master=192.168.0.5 --loglevel debug
./svtminion.sh --status --loglevel debug || { _retn=$?; if [[ ${_retn} -eq 100 ]]; then echo "test correct"; else echo "test failed, salt-minion should be installed, returned '${_retn}'"; exit 1; fi; }
sleep 1
cat /etc/salt/minion
cat /etc/salt/minion | grep 'master:\ 192.168.0.5' 1>/dev/null
./svtminion.sh --remove || { _retn=$?; echo "test failed, did not uninstall the salt-minion, returned '${_retn}'"; }
./svtminion.sh --source ${oldpwd}/tests/testarea --install master=192.168.0.5 --loglevel debug
./svtminion.sh --status --loglevel debug || { _retn=$?; if [[ ${_retn} -eq 100 ]]; then echo "test correct"; else echo "test failed, salt-minion should be installed, returned '${_retn}'"; exit 1; fi; }
sleep 1
cat /etc/salt/minion
cat /etc/salt/minion | grep 'master:\ 192.168.0.5' 1>/dev/null
./svtminion.sh --remove || { _retn=$?; echo "test failed, did not uninstall the salt-minion, returned '${_retn}'"; }
./svtminion.sh --install master=192.168.0.5 --loglevel debug --source file:/${oldpwd}/tests/testarea -m "3003.3-1"
./svtminion.sh --status --loglevel debug || { _retn=$?; if [[ ${_retn} -eq 100 ]]; then echo "test correct"; else echo "test failed, salt-minion should be installed, returned '${_retn}'"; exit 1; fi; }
sleep 1
cat /etc/salt/minion
cat /etc/salt/minion | grep 'master:\ 192.168.0.5' 1>/dev/null
./svtminion.sh --remove || { _retn=$?; echo "test failed, did not uninstall the salt-minion, returned '${_retn}'"; }
./svtminion.sh --source ${oldpwd}/tests/testarea -m "3006.8" --install master=192.168.0.5 --loglevel debug
./svtminion.sh --status --loglevel debug || { _retn=$?; if [[ ${_retn} -eq 100 ]]; then echo "test correct"; else echo "test failed, salt-minion should be installed, returned '${_retn}'"; exit 1; fi; }
sleep 1
cat /etc/salt/minion
cat /etc/salt/minion | grep 'master:\ 192.168.0.5' 1>/dev/null
./svtminion.sh --remove || { _retn=$?; echo "test failed, did not uninstall the salt-minion, returned '${_retn}'"; }
./svtminion.sh --status --loglevel debug || { _retn=$?; if [[ ${_retn} -eq 102 ]]; then echo "test correct"; else echo "test failed, salt-minion should be installed, returned '${_retn}'"; exit 1; fi; }
sleep 1
./svtminion.sh --source ${oldpwd}/tests/testarea --install master=192.168.0.5 --loglevel debug --minionversion 3006
cat /etc/salt/minion
cat /etc/salt/minion | grep 'master:\ 192.168.0.5' 1>/dev/null
./svtminion.sh --remove || { _retn=$?; echo "test failed, did not uninstall the salt-minion, returned '${_retn}'"; }
./svtminion.sh --source ${oldpwd}/tests/testarea --install master=192.168.0.5 --loglevel debug --minionversion 3006.9
./svtminion.sh --status --loglevel debug || { _retn=$?; if [[ ${_retn} -eq 100 ]]; then echo "test correct"; else echo "test failed, salt-minion should be installed, returned '${_retn}'"; exit 1; fi; }
sleep 1
cat /etc/salt/minion
cat /etc/salt/minion | grep 'master:\ 192.168.0.5' 1>/dev/null
./svtminion.sh --remove || { _retn=$?; echo "test failed, did not uninstall the salt-minion, returned '${_retn}'"; }
# GA vs RC (testarea includes 3008.0rc1 Linux onedir): default latest must be
# max GA (3007.1), not the RC; major 3008 has no GA yet; exact 3008.0rc1 installs RC.
./svtminion.sh --source ${oldpwd}/tests/testarea --install master=192.168.0.5 --loglevel debug
./svtminion.sh --status --loglevel debug || { _retn=$?; if [[ ${_retn} -ne 100 ]]; then echo "test failed, salt-minion should be installed (latest GA), returned '${_retn}'"; exit 1; fi; }
_salt_ver_out=$(/usr/bin/salt-call --local test.version --out=txt 2>/dev/null || true)
if echo "${_salt_ver_out}" | grep -q "3007.1" && ! echo "${_salt_ver_out}" | grep -qi "rc"; then
    echo "test correct: default latest from testarea is GA 3007.1 not RC"
else
    echo "test failed: expected GA 3007.1 without rc in test.version, got '${_salt_ver_out}'"
    exit 1
fi
./svtminion.sh --remove || { _retn=$?; echo "test failed, did not uninstall the salt-minion, returned '${_retn}'"; exit 1; }

./svtminion.sh --source ${oldpwd}/tests/testarea --minionversion 3008 --install master=192.168.0.5 --loglevel debug
./svtminion.sh --status --loglevel debug || { _retn=$?; if [[ ${_retn} -eq 102 ]]; then echo "test correct: no GA for major 3008, minion not installed"; else echo "test failed, expected status 102 after install with -m 3008 and no GA, got '${_retn}'"; exit 1; fi; }
./svtminion.sh --remove || true

./svtminion.sh --source ${oldpwd}/tests/testarea --minionversion 3008.0rc1 --install master=192.168.0.5 --loglevel debug
./svtminion.sh --status --loglevel debug || { _retn=$?; if [[ ${_retn} -ne 100 ]]; then echo "test failed, salt-minion should be installed (3008.0rc1), returned '${_retn}'"; exit 1; fi; }
_salt_ver_rc=$(/usr/bin/salt-call --local test.version --out=txt 2>/dev/null || true)
if echo "${_salt_ver_rc}" | grep -qi "3008.0rc1"; then
    echo "test correct: exact RC 3008.0rc1 installed"
else
    echo "test failed: expected 3008.0rc1 in test.version, got '${_salt_ver_rc}'"
    exit 1
fi
./svtminion.sh --remove || { _retn=$?; echo "test failed, did not uninstall the salt-minion, returned '${_retn}'"; exit 1; }

## Major-version, exact-version, and upgrade-chain coverage, data-driven off
## generate.py's SALT_VERSIONS (the single source of truth for which Salt
## versions this repo tests). Sourced from the real network default so this
## also exercises real packages.broadcom.com resolution, not local testarea
## fixtures. Gated by $SALT_TEST_VERSION so each CI matrix job exercises
## only its assigned entry; unset (local ad-hoc run) exercises all of them.
_generate_py="${oldpwd}/.github/workflows/templates/generate.py"

_run_major_check() {
    local _major="$1"
    ./svtminion.sh --install master=192.168.0.5 --loglevel debug --minionversion "${_major}"
    ./svtminion.sh --status --loglevel debug || { _retn=$?; if [[ ${_retn} -eq 100 ]]; then echo "test correct"; else echo "test failed, salt-minion should be installed (major ${_major}), returned '${_retn}'"; exit 1; fi; }
    cat /etc/salt/minion
    cat /etc/salt/minion | grep 'master:\ 192.168.0.5' 1>/dev/null
    ./svtminion.sh --remove || { _retn=$?; echo "test failed, did not uninstall the salt-minion, returned '${_retn}'"; exit 1; }
}

_run_exact_check() {
    local _exact="$1"
    ./svtminion.sh --install master=192.168.0.5 --loglevel debug --minionversion "${_exact}"
    ./svtminion.sh --status --loglevel debug || { _retn=$?; if [[ ${_retn} -eq 100 ]]; then echo "test correct"; else echo "test failed, salt-minion should be installed (exact ${_exact}), returned '${_retn}'"; exit 1; fi; }
    _ver_out=$(/usr/bin/salt-call --local test.version --out=txt 2>/dev/null || true)
    if echo "${_ver_out}" | grep -q "${_exact}"; then echo "test correct"; else echo "test failed: expected ${_exact} in test.version, got '${_ver_out}'"; exit 1; fi
    ./svtminion.sh --remove || { _retn=$?; echo "test failed, did not uninstall the salt-minion, returned '${_retn}'"; exit 1; }
}

_run_upgrade_check() {
    local _from="$1" _to="$2"
    # Thin check before the upgrade - just confirm the starting version.
    ./svtminion.sh --install master=192.168.0.5 id="tup" --loglevel debug --minionversion "${_from}"
    if [[ "$(/usr/bin/salt-call --local test.version --out=pprint | awk '{print $2}' | cut -d "'" -f 2)" != "${_from}" ]]; then echo "test failed, wrong starting version for upgrade ${_from} -> ${_to}"; exit 1; fi

    ./svtminion.sh --upgrade --install --loglevel debug --minionversion "${_to}"

    # Only check things that relate to the upgrade itself - binaries
    # present and ping are already covered by the fresh-install tests and
    # don't exercise anything upgrade-specific.
    ./svtminion.sh --status --loglevel debug || { _retn=$?; if [[ ${_retn} -eq 100 ]]; then echo "test correct"; else echo "test failed, salt-minion should be installed after upgrade ${_from} -> ${_to}, returned '${_retn}'"; exit 1; fi; }
    systemctl is-active salt-minion || { echo "test failed, salt-minion service not active after upgrade ${_from} -> ${_to}"; exit 1; }
    # An upgrade preserves the existing config - the guest vars passed to
    # the upgrade call above are expected to be ignored.
    cat /etc/salt/minion | grep 'master:\ 192.168.0.5' 1>/dev/null || { echo "test failed, master not preserved after upgrade ${_from} -> ${_to}"; exit 1; }
    cat /etc/salt/minion | grep 'id:\ tup' 1>/dev/null || { echo "test failed, id not preserved after upgrade ${_from} -> ${_to}"; exit 1; }
    if [[ "$(/usr/bin/salt-call --local test.version --out=pprint | awk '{print $2}' | cut -d "'" -f 2)" != "${_to}" ]]; then echo "test failed, wrong version after upgrade ${_from} -> ${_to}"; exit 1; fi

    ./svtminion.sh --remove || { _retn=$?; echo "test failed, did not uninstall the salt-minion, returned '${_retn}'"; exit 1; }
}

if [[ "${SALT_TEST_VERSION:-}" =~ ^upgrade-([0-9]+)$ ]]; then
    _to_major="${BASH_REMATCH[1]}"
    while read -r _from_exact _to_major_row _to_exact; do
        if [[ "${_to_major_row}" == "${_to_major}" ]]; then
            _run_upgrade_check "${_from_exact}" "${_to_exact}"
        fi
    done < <(python3 "${_generate_py}" --print-upgrade-steps)
elif [[ -n "${SALT_TEST_VERSION:-}" ]]; then
    if [[ "${SALT_TEST_VERSION}" =~ ^([0-9]+)-([0-9]+)$ ]]; then
        _run_exact_check "${BASH_REMATCH[1]}.${BASH_REMATCH[2]}"
    elif [[ "${SALT_TEST_VERSION}" =~ ^[0-9]+$ ]]; then
        _run_major_check "${SALT_TEST_VERSION}"
    fi
else
    while read -r _major _exact; do
        _run_major_check "${_major}"
        _run_exact_check "${_exact}"
    done < <(python3 "${_generate_py}" --print-versions)
    while read -r _from_exact _to_major _to_exact; do
        _run_upgrade_check "${_from_exact}" "${_to_exact}"
    done < <(python3 "${_generate_py}" --print-upgrade-steps)
fi

# test stop and start
./svtminion.sh --install master=192.168.0.5 --loglevel debug --source https://packages.broadcom.com/artifactory/saltproject-generic/onedir
./svtminion.sh --status --loglevel debug || { _retn=$?; if [[ ${_retn} -eq 100 ]]; then echo "test correct"; else echo "test failed, salt-minion should be installed, returned '${_retn}'"; exit 1; fi; }
sleep 1
cat /etc/salt/minion
cat /etc/salt/minion | grep 'master:\ 192.168.0.5' 1>/dev/null
ps -ef | grep salt
systemctl is-active salt-minion
./svtminion.sh --stop --loglevel debug || { _retn=$?; if [[ ${_retn} -eq 107 ]]; then echo "test correct"; else echo "test failed, salt-minion should be stopped, returned '${_retn}'"; exit 1; fi; }
ps -ef | grep salt
systemctl is-active salt-minion || { echo "test correct"; }
ps -ef | grep salt
./svtminion.sh --start --loglevel debug || { _retn=$?; if [[ ${_retn} -eq 100 ]]; then echo "test correct"; else echo "test failed, salt-minion should be running, returned '${_retn}'"; exit 1; fi; }
ps -ef | grep salt
systemctl is-active salt-minion || { echo "test failed, salt-minion should be running"; exit 1; }
# test reconfig
cat /etc/salt/minion
./svtminion.sh --reconfig master=192.168.0.7 --loglevel debug
sleep 3
./svtminion.sh --status --loglevel debug || { _retn=$?; if [[ ${_retn} -eq 100 ]]; then echo "test correct"; else echo "test failed, salt-minion should be running, returned '${_retn}'"; exit 1; fi; }
cat /etc/salt/minion
cat /etc/salt/minion | grep 'master:\ 192.168.0.7' 1>/dev/null
ps -ef | grep salt
systemctl is-active salt-minion
## The 3006->3007->3008 upgrade chain is now covered above by the
## data-driven _run_upgrade_check loop.
./svtminion.sh --remove || { _retn=$?; echo "test failed, did not uninstall the salt-minion, returned '${_retn}'"; }
sleep 1
./svtminion.sh --source ${oldpwd}/tests/testarea --install master=192.168.0.5 --loglevel debug
cat /etc/salt/minion
cat /etc/salt/minion | grep 'master:\ 192.168.0.5' 1>/dev/null
./svtminion.sh --remove || { _retn=$?; echo "test failed, did not uninstall the salt-minion, returned '${_retn}'"; }
./svtminion.sh --install master=192.168.0.5 --loglevel debug --source file:/${oldpwd}/tests/testarea -m 3007
./svtminion.sh --status --loglevel debug || { _retn=$?; if [[ ${_retn} -eq 100 ]]; then echo "test correct"; else echo "test failed, salt-minion should be installed, returned '${_retn}'"; exit 1; fi; }
cat /etc/salt/minion
cat /etc/salt/minion | grep 'master:\ 192.168.0.5' 1>/dev/null
./svtminion.sh --remove || { _retn=$?; echo "test failed, did not uninstall the salt-minion, returned '${_retn}'"; }
./svtminion.sh --install master=192.168.0.5 --loglevel debug --source https://packages.broadcom.com/artifactory/saltproject-generic/onedir
./svtminion.sh --status --loglevel debug || { _retn=$?; if [[ ${_retn} -eq 100 ]]; then echo "test correct"; else echo "test failed, salt-minion should be installed, returned '${_retn}'"; exit 1; fi; }
cat /etc/salt/minion
cat /etc/salt/minion | grep 'master:\ 192.168.0.5' 1>/dev/null
./svtminion.sh --remove || { _retn=$?; echo "test failed, did not uninstall the salt-minion, returned '${_retn}'"; }
./svtminion.sh --source ${oldpwd}/tests/testarea --install master=192.168.0.5 --loglevel debug
cat /etc/salt/minion
cat /etc/salt/minion | grep 'master:\ 192.168.0.5' 1>/dev/null
./svtminion.sh --status --loglevel debug || { _retn=$?; if [[ ${_retn} -eq 100 ]]; then echo "test correct"; else echo "test failed, salt-minion should be installed, returned '${_retn}'"; exit 1; fi; }
./svtminion.sh --remove || { _retn=$?; echo "test failed, did not uninstall the salt-minion, returned '${_retn}'"; }
bash -x ./svtminion.sh --install master=192.168.0.5 --loglevel debug --source file:/${oldpwd}/tests/testarea -m 3007.1
cat /etc/salt/minion
cat /etc/salt/minion | grep 'master:\ 192.168.0.5' 1>/dev/null
./svtminion.sh --status --loglevel debug || { _retn=$?; if [[ ${_retn} -eq 100 ]]; then echo "test correct"; else echo "test failed, salt-minion should be installed, returned '${_retn}'"; exit 1; fi; }
./svtminion.sh --remove || { _retn=$?; echo "test failed, did not uninstall the salt-minion, returned '${_retn}'"; }

# test with classic package installed
# Use 3005 Redhat 9 for Rocky 9 container
rpm --import ${oldpwd}/tests/classic/SALTSTACK-GPG-KEY2.pub
cp -a ${oldpwd}/tests/classic/3005.repo /etc/yum.repos.d/salt.repo
echo "baseurl=file:///${oldpwd}/testarea/classic" >> /etc/yum.repos.d/salt.repo
echo "gpgkey=file:///${oldpwd}/testarea/classic/SALTSTACK-GPG-KEY2.pub" >> /etc/yum.repos.d/salt.repo
yum makecache
yum -y install salt-minion

./svtminion.sh --install master=192.168.0.5 --loglevel debug || { _retn=$?; if [[ ${_retn} -eq 106 ]]; then echo "test correct"; else echo "test failed, should fail since be standard salt-minion installed, returned '${_retn}'"; exit 1; fi; }
./svtminion.sh --status --loglevel info || { _retn=$?; if [[ ${_retn} -eq 106 ]]; then echo "test correct"; else echo "test failed, classic salt-minion should be installed and external install detected, returned '${_retn}'"; exit 1; fi; }
./svtminion.sh --remove || { _retn=$?; if [[ ${_retn} -eq 106 ]]; then echo "test correct"; else echo "test failed, should fail since be standard salt-minion installed and script remove not valid, returned '${_retn}'"; exit 1; fi; }
