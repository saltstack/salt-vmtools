# Copyright 2021-2023 VMware, Inc.
# SPDX-License-Identifier: Apache-2

function setUpScript {

    Write-Host "Resetting environment: " -NoNewline
    Reset-Environment *> $null
    Write-Done

    Write-Host "Installing salt: " -NoNewline
    function Get-GuestVars { "master=gv_master id=gv_minion" }
    $MinionVersion = "3005.1-4"
    Install *> $null
    Write-Done

    Write-Host "Removing salt: " -NoNewline
    Remove *> $null
    Write-Done

}

function tearDownScript {
    Write-Host "Resetting environment: " -NoNewline
    Reset-Environment *> $null
    Write-Done
}

function test_status_notInstalled {
    # Is the status set to notInstalled
    try {
        $current_status = Get-ItemPropertyValue -Path $vmtools_base_reg -Name $vmtools_salt_minion_status_name
    } catch {
        # You'll only get here if the path isn't present
        $current_status = $STATUS_CODES["notInstalled"]
    }
    if ($current_status -ne $STATUS_CODES["notInstalled"]) { return 1 }
    return 0
}

function test_config_dir_removed {
    # Is the config directory removed
    if (Test-Path "$base_salt_config_location") { return 1 }
    return 0
}

function test_install_dir_removed {
    # Is the install directory removed
    if (Test-Path "$base_salt_install_location") { return 1 }
    return 0
}

function test_service_removed {
    # Is the salt-minion service unregistered
    $service = Get-Service -Name salt-minion -ErrorAction SilentlyContinue
    if ($service) { return 1 }
    return 0
}

function test_path_removed {
    # Is salt removed from the system path
    $path = "$salt_dir"
    $path_reg_key = "HKLM:\System\CurrentControlSet\Control\Session Manager\Environment"
    $current_path = (Get-ItemProperty -Path $path_reg_key -Name Path).Path
    if ($current_path -like "*$path*") { return 1 }
    return 0
}
