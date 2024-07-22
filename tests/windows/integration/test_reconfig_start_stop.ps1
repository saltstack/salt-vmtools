# Copyright 2021-2023 VMware, Inc.
# SPDX-License-Identifier: Apache-2

function setUpScript {

    Write-Host "Resetting environment: " -NoNewline
    Reset-Environment *> $null
    Write-Done

    Write-Host "Installing salt: " -NoNewline
    function Get-GuestVars { "master=gv_master id=gv_minion" }
    $MinionVersion = "3006.0"
    Install *> $null
    Write-Done
}

function tearDownScript {
    Write-Host "Resetting environment: " -NoNewline
    Reset-Environment *> $null
    Write-Done
}

function test_reconfig{
    # test reconfig
    function Get-GuestVars { "master=reconfig_master id=reconfig_minion_id" }
    Reconfigure

    $result = & "$salt_dir\salt-call.exe" --local config.get master
    if (!($result -like "local:*")) { return 1 }
    if (!($result -like "*reconfig_master")) { return 1 }

    $result = & "$salt_dir\salt-call.exe" --local config.get id
    if (!($result -like "local:*")) { return 1 }
    if (!($result -like "*reconfig_minion_id")) { return 1 }

    return 0
}

function test_stop {
    # test stop
    Stop-MinionService

    $service_status = Get-ServiceStatus
    if ( !($service_status -eq "Stopped") ) { return 1 }

    return 0
}

function test_start {
    # test start

    # let's stop it first...
    Stop-MinionService
    $service_status = Get-ServiceStatus
    if ( !($service_status -eq "Stopped") ) { return 1 }

    # now let's start it...
    Start-MinionService
    $service_status = Get-ServiceStatus
    if ( !($service_status -eq "Running") ) { return 1 }

    return 0
}
