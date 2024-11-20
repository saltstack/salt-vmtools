#!/bin/bash

# Copyright 2021-2024 VMware, Inc.
# SPDX-License-Identifier: Apache-2

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

# DGM TBD no more rpeo.json - test source installs with repo.json
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
./svtminion.sh --install master=192.168.0.5 --loglevel debug --source file:/${oldpwd}/tests/testarea -m "3003.3-1" # DGM FIX
./svtminion.sh --status --loglevel debug || { _retn=$?; if [[ ${_retn} -eq 100 ]]; then echo "test correct"; else echo "test failed, salt-minion should be installed, returned '${_retn}'"; exit 1; fi; }
sleep 1
cat /etc/salt/minion
cat /etc/salt/minion | grep 'master:\ 192.168.0.5' 1>/dev/null
./svtminion.sh --remove || { _retn=$?; echo "test failed, did not uninstall the salt-minion, returned '${_retn}'"; }
./svtminion.sh --install master=192.168.0.5 --loglevel debug --source https://repo.saltproject.io/salt/vmware-tools-onedir # DGM FIX
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
./svtminion.sh --source ${oldpwd}/tests/testarea --install master=192.168.0.5 --loglevel debug --minionversion 3006 # DGM FIX
cat /etc/salt/minion
cat /etc/salt/minion | grep 'master:\ 192.168.0.5' 1>/dev/null
./svtminion.sh --remove || { _retn=$?; echo "test failed, did not uninstall the salt-minion, returned '${_retn}'"; }
./svtminion.sh --source ${oldpwd}/tests/testarea --install master=192.168.0.5 --loglevel debug --minionversion 3006.9 # DGM FIX
./svtminion.sh --status --loglevel debug || { _retn=$?; if [[ ${_retn} -eq 100 ]]; then echo "test correct"; else echo "test failed, salt-minion should be installed, returned '${_retn}'"; exit 1; fi; }
sleep 1
cat /etc/salt/minion
cat /etc/salt/minion | grep 'master:\ 192.168.0.5' 1>/dev/null
./svtminion.sh --remove || { _retn=$?; echo "test failed, did not uninstall the salt-minion, returned '${_retn}'"; }
./svtminion.sh --source ${oldpwd}/tests/testarea --install master=192.168.0.5 --loglevel debug --minionversion 3007 # DGM FIX
./svtminion.sh --status --loglevel debug || { _retn=$?; if [[ ${_retn} -eq 100 ]]; then echo "test correct"; else echo "test failed, salt-minion should be installed, returned '${_retn}'"; exit 1; fi; }
sleep 1
cat /etc/salt/minion
cat /etc/salt/minion | grep 'master:\ 192.168.0.5' 1>/dev/null
## wait for RC with 3008
## ./svtminion.sh --remove || { _retn=$?; echo "test failed, did not uninstall the salt-minion, returned '${_retn}'"; }
## ./svtminion.sh --install master=192.168.0.5 --loglevel debug --source https://packages.broadcom.com/saltproject-generic/onedir
## ./svtminion.sh --status --loglevel debug || { _retn=$?; if [[ ${_retn} -eq 100 ]]; then echo "test correct"; else echo "test failed, salt-minion should be installed, returned '${_retn}'"; exit 1; fi; }
## sleep 1
cat /etc/salt/minion
cat /etc/salt/minion | grep 'master:\ 192.168.0.5' 1>/dev/null
./svtminion.sh --remove || { _retn=$?; echo "test failed, did not uninstall the salt-minion, returned '${_retn}'"; }
# test stop and start
./svtminion.sh --install master=192.168.0.5 --loglevel debug --source https://packages.broadcom.com/saltproject-generic/onedir
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
# test 3006-3007 and upgrade
./svtminion.sh --remove || { _retn=$?; echo "test failed, did not uninstall the salt-minion, returned '${_retn}'"; }
sleep 1
./svtminion.sh --source ${oldpwd}/tests/testarea --install master=192.168.0.5 id="tup" --loglevel debug --minionversion 3006 # DGM FIX
cat /etc/salt/minion
cat /etc/salt/minion | grep 'master:\ 192.168.0.5' 1>/dev/null
cat /etc/salt/minion | grep 'id:\ tup' 1>/dev/null
ps -ef | grep salt
systemctl is-active salt-minion
if [[ $(/usr/bin/salt-call --local test.version --out=pprint | awk '{print $2}' | cut -d "'" -f 2 | awk -F "." '{print $1}') -eq 3006 ]]; then echo "test correct"; else echo "test failed, wrong major version for salt-minion"; exit 1; fi
./svtminion.sh --source ${oldpwd}/tests/testarea --upgrade --install --loglevel debug --minionversion 3007 # DGM FIX
cat /etc/salt/minion
cat /etc/salt/minion | grep 'master:\ 192.168.0.5' 1>/dev/null
cat /etc/salt/minion | grep 'id:\ tup' 1>/dev/null
ps -ef | grep salt
systemctl is-active salt-minion
if [[ $(/usr/bin/salt-call --local test.version --out=pprint | awk '{print $2}' | cut -d "'" -f 2 | awk -F "." '{print $1}') -eq 3007 ]]; then echo "test correct"; else echo "test failed, wrong major version for salt-minion"; exit 1; fi
./svtminion.sh --source ${oldpwd}/tests/testarea --install master=192.168.0.5 --loglevel debug # DGM FIX
cat /etc/salt/minion
cat /etc/salt/minion | grep 'master:\ 192.168.0.5' 1>/dev/null
./svtminion.sh --remove || { _retn=$?; echo "test failed, did not uninstall the salt-minion, returned '${_retn}'"; }
./svtminion.sh --install master=192.168.0.5 --loglevel debug --source file:/${oldpwd}/tests/testarea -m 3007
./svtminion.sh --status --loglevel debug || { _retn=$?; if [[ ${_retn} -eq 100 ]]; then echo "test correct"; else echo "test failed, salt-minion should be installed, returned '${_retn}'"; exit 1; fi; }
cat /etc/salt/minion
cat /etc/salt/minion | grep 'master:\ 192.168.0.5' 1>/dev/null
./svtminion.sh --remove || { _retn=$?; echo "test failed, did not uninstall the salt-minion, returned '${_retn}'"; }
./svtminion.sh --install master=192.168.0.5 --loglevel debug --source https://packages.broadcom.com/saltproject-generic/onedir
./svtminion.sh --status --loglevel debug || { _retn=$?; if [[ ${_retn} -eq 100 ]]; then echo "test correct"; else echo "test failed, salt-minion should be installed, returned '${_retn}'"; exit 1; fi; }
cat /etc/salt/minion
cat /etc/salt/minion | grep 'master:\ 192.168.0.5' 1>/dev/null
./svtminion.sh --remove || { _retn=$?; echo "test failed, did not uninstall the salt-minion, returned '${_retn}'"; }
./svtminion.sh --source ${oldpwd}/tests/testarea --install master=192.168.0.5 --loglevel debug
cat /etc/salt/minion
cat /etc/salt/minion | grep 'master:\ 192.168.0.5' 1>/dev/null
./svtminion.sh --status --loglevel debug || { _retn=$?; if [[ ${_retn} -eq 100 ]]; then echo "test correct"; else echo "test failed, salt-minion should be installed, returned '${_retn}'"; exit 1; fi; }
./svtminion.sh --remove || { _retn=$?; echo "test failed, did not uninstall the salt-minion, returned '${_retn}'"; }
bash -x ./svtminion.sh --install master=192.168.0.5 --loglevel debug --source file:/${oldpwd}/tests/testarea -m 3007.1 # DGM FIX
cat /etc/salt/minion
cat /etc/salt/minion | grep 'master:\ 192.168.0.5' 1>/dev/null
./svtminion.sh --status --loglevel debug || { _retn=$?; if [[ ${_retn} -eq 100 ]]; then echo "test correct"; else echo "test failed, salt-minion should be installed, returned '${_retn}'"; exit 1; fi; }
./svtminion.sh --remove || { _retn=$?; echo "test failed, did not uninstall the salt-minion, returned '${_retn}'"; }
# test with classic package installed
rpm --import https://repo.saltproject.io/py3/redhat/8/x86_64/3005/SALTSTACK-GPG-KEY.pub # DGM FIX
curl -fsSL https://repo.saltproject.io/py3/redhat/8/x86_64/3005.repo | tee /etc/yum.repos.d/salt.repo # DGM FIX
yum makecache
yum -y install salt-minion
./svtminion.sh --install master=192.168.0.5 --loglevel debug || { _retn=$?; if [[ ${_retn} -eq 106 ]]; then echo "test correct"; else echo "test failed, should fail since be standard salt-minion installed, returned '${_retn}'"; exit 1; fi; }
./svtminion.sh --status --loglevel info || { _retn=$?; if [[ ${_retn} -eq 106 ]]; then echo "test correct"; else echo "test failed, classic salt-minion should be installed and external install detected, returned '${_retn}'"; exit 1; fi; }
./svtminion.sh --remove || { _retn=$?; if [[ ${_retn} -eq 106 ]]; then echo "test correct"; else echo "test failed, should fail since be standard salt-minion installed and script remove not valid, returned '${_retn}'"; exit 1; fi; }
