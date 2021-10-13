# Copyright (c) 2021 VMware, Inc. All rights reserved.

function setUpScript {

    # Stop and remove the salt-minion service if it exists
    $service = Get-Service -Name salt-minion -ErrorAction SilentlyContinue
    if ($service) {
        Write-Host "Stopping the salt-minion service: " -NoNewline
        Stop-Service -Name salt-minion
        Write-Done
        Write-Host "Removing the salt-minion service: " -NoNewline
        $service = Get-WmiObject -Class Win32_Service -Filter "Name='salt-minion'"
        $service.delete() *> $null
        Write-Done
    }

    # Remove Program Data directory
    if (Test-Path "$env:ProgramData\Salt Project") {
        Write-Host "Removing config directory: " -NoNewline
        Remove-Item "$env:ProgramData\Salt Project" -Force -Recurse
        Write-Done
    }

    # Remove Program Files directory
    if (Test-Path "$env:ProgramFiles\Salt Project") {
        Write-Host "Removing install directory: " -NoNewline
        Remove-Item "$env:ProgramFiles\Salt Project" -Force -Recurse
        Write-Done
    }

    # Removing from the path

    $path = "$env:ProgramFiles\Salt Project\salt"
    $path_reg_key = "HKLM:\System\CurrentControlSet\Control\Session Manager\Environment"
    $current_path = (Get-ItemProperty -Path $path_reg_key -Name Path).Path
    $new_path_list = [System.Collections.ArrayList]::new()
    $removed = 0
    foreach ($item in $current_path.Split(";")) {
        $regex_path = $path.Replace("\", "\\")
        # Bail if we find the new path in the current path
        if ($item -imatch "^$regex_path(\\)?$") {
            # Remove this one
            Write-Host "Removing salt from the system path: " -NoNewline
            $removed = 1
        } else {
            # Add the item to our new path array
            $new_path_list.Add($item) | Out-Null
        }
    }
    if ($removed) {
        $new_path = $new_path_list -join ";"
        Set-ItemProperty -Path $path_reg_key -Name Path -Value $new_path
        Write-Done
    }

    Write-Host "Installing salt: " -NoNewline
    function Get-GuestVars { "master=gv_master id=gv_minion" }
    Install
    Write-Done

}

function tearDownScript {

    # Stop and remove the salt-minion service if it exists
    $service = Get-Service -Name salt-minion -ErrorAction SilentlyContinue
    if ($service) {
        Write-Host "Stopping the salt-minion service: " -NoNewline
        Stop-Service -Name salt-minion
        Write-Done
        Write-Host "Removing the salt-minion service: " -NoNewline
        $service = Get-WmiObject -Class Win32_Service -Filter "Name='salt-minion'"
        $service.delete() *> $null
        Write-Done
    }

    # Remove Program Data directory
    if (Test-Path "$env:ProgramData\Salt Project") {
        Write-Host "Removing config directory: " -NoNewline
        Remove-Item "$env:ProgramData\Salt Project" -Force -Recurse
        Write-Done
    }

    # Remove Program Files directory
    if (Test-Path "$env:ProgramFiles\Salt Project") {
        Write-Host "Removing install directory: " -NoNewline
        Remove-Item "$env:ProgramFiles\Salt Project" -Force -Recurse
        Write-Done
    }

    # Removing from the path

    $path = "$env:ProgramFiles\Salt Project\salt"
    $path_reg_key = "HKLM:\System\CurrentControlSet\Control\Session Manager\Environment"
    $current_path = (Get-ItemProperty -Path $path_reg_key -Name Path).Path
    $new_path_list = [System.Collections.ArrayList]::new()
    $removed = 0
    foreach ($item in $current_path.Split(";")) {
        $regex_path = $path.Replace("\", "\\")
        # Bail if we find the new path in the current path
        if ($item -imatch "^$regex_path(\\)?$") {
            # Remove this one
            Write-Host "Removing salt from the system path: " -NoNewline
            $removed = 1
        } else {
            # Add the item to our new path array
            $new_path_list.Add($item) | Out-Null
        }
    }
    if ($removed) {
        $new_path = $new_path_list -join ";"
        Set-ItemProperty -Path $path_reg_key -Name Path -Value $new_path
        Write-Done
    }

}

function test_Install_status_installed {
    # Is the status set to installed
    try {
        $current_status = Get-ItemPropertyValue -Path $vmtools_base_reg -Name $vmtools_salt_minion_status_name
    } catch {
        $current_status = $STATUS_CODES["notInstalled"]
    }
    if ($current_status -ne $STATUS_CODES["installed"]) { return 1 }
    return 0
}

function test_Install_salt_binary_present {
    # Is the salt binary present
    if (!(Test-Path $salt_bin)) { return 1 }
    return 0
}

function test_Install_ssm_binary_present {
    # Is the SSM Binary present
    if (!(Test-Path $ssm_bin)) { return 1 }
    return 0
}

function test_Install_salt-call_bat_present {
    # Is salt-call.bat present
    if (!(Test-Path "$salt_dir\salt-call.bat")) { return 1 }
    return 0
}

function test_Install_salt-minion_bat_present {
    # Is salt-minion.bat present
    if (!(Test-Path "$salt_dir\salt-minion.bat")) { return 1 }
    return 0
}

function test_Install_salt-minion_service_installed {
    # Is the salt-minion service registerd
    $service = Get-Service -Name salt-minion -ErrorAction SilentlyContinue
    if (!($service)) { return 1 }
    return 0
}

function test_Install_salt-minion_service_running {
    # Is the salt minion service running
    if ((Get-Service -Name salt-minion).Status -ne "Running") { return 1 }
    return 0
}

function test_Install_salt-minion_config_present {
    # Is the minion config file present
    if (!(Test-Path $salt_config_file)) { return 1 }
    return 0
}

function test_Install_minion_id_in_config {
    # Verify that the old minion id is commented out
    foreach ($line in Get-Content $salt_config_file) {
        if ($line -match "^id: gv_minion$") { return 0 }
    }
    return 1
}

function test_Install_salt_added_to_path {
    # Has salt been added to the system path
    $path = "$env:ProgramFiles\Salt Project\salt"
    $path_reg_key = "HKLM:\System\CurrentControlSet\Control\Session Manager\Environment"
    $current_path = (Get-ItemProperty -Path $path_reg_key -Name Path).Path
    if (!($current_path -like "*$path*")) { return 1 }
    return 0
}

function test_Install_salt-call {
    $failed = 0
    $result = & "$salt_dir\salt-call" --local test.ping
    if (!($result -like "local:*")) { $failed = 1 }
    if (!($result -like "*True")) { $failed = 1 }
    return $failed
}
