# Copyright 2021-2024 VMware, Inc.
# SPDX-License-Identifier: Apache-2

function setUpScript {

    Write-Host "Resetting environment: " -NoNewline
    Reset-Environment *> $null
    Write-Done

    $MinionVersion = "3005.1-4"
    Write-Host "Installing salt ($MinionVersion): " -NoNewline
    function Get-GuestVars { "master=existing_master id=existing_minion" }
    Install *> $null
    Write-Done

    $MinionVersion = "3006.1"
    $Upgrade = $true
    Write-Host "Upgrading salt ($MinionVersion): " -NoNewline
    function Get-GuestVars { "master=gv_master id=gv_minion" }
    Install *> $null
    Write-Done

}

function tearDownScript {
    Write-Host "Resetting environment: " -NoNewline
    Reset-Environment *> $null
    Write-Done
}

function test_status_installed {
    # Is the status set to installed
    try {
        $current_status = Get-ItemPropertyValue -Path $vmtools_base_reg -Name $vmtools_salt_minion_status_name
    } catch {
        $current_status = $STATUS_CODES["notInstalled"]
    }
    if ($current_status -ne $STATUS_CODES["installed"]) { return 1 }
    return 0
}

function test_binaries_present{
    # Is the SSM Binary present
    if (!(Test-Path $ssm_bin)) { return 1 }
    if (!(Test-Path "$salt_dir\salt-call.exe")) { return 1 }
    if (!(Test-Path "$salt_dir\salt-minion.exe")) { return 1 }
    return 0
}

function test_service_installed {
    # Is the salt-minion service registerd
    $service = Get-Service -Name salt-minion -ErrorAction SilentlyContinue
    if (!($service)) { return 1 }
    return 0
}

function test_service_running {
    # Is the salt minion service running
    if ((Get-Service -Name salt-minion).Status -ne "Running") { return 1 }
    return 0
}

function test_config_present {
    # Is the minion config file present
    if (!(Test-Path $salt_config_file)) { return 1 }
    return 0
}

function test_config_correct {
    # We have to do it this way so -bor will return 0 when both are 0
    $minion_not_found = 1
    $master_not_found = 1
    # Verify that the old minion id is commented out
    foreach ($line in Get-Content $salt_config_file) {
        if ($line -match "^id: existing_minion$") { $minion_not_found = 0}
        if ($line -match "^master: existing_master$") { $master_not_found = 0}
    }
    return $minion_not_found -bor $master_not_found
}

function test_salt_added_to_path {
    # Has salt been added to the system path
    $path_reg_key = "HKLM:\System\CurrentControlSet\Control\Session Manager\Environment"
    $current_path = (Get-ItemProperty -Path $path_reg_key -Name Path).Path
    if (!($current_path -like "*$salt_dir*")) { return 1 }
    return 0
}

function test_salt_call {
    $failed = 0
    $result = & "$salt_dir\salt-call" --local test.ping
    if (!($result -like "local:*")) { $failed = 1 }
    if (!($result -like "*True")) { $failed = 1 }
    return $failed
}
