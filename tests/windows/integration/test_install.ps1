# Copyright (c) 2021 VMware, Inc. All rights reserved.

function setUpScript {

    Write-Header "Cleaning Up" -Filler "-"
    # Stop and remove the salt-minion service if it exists
    $service = Get-Service -Name salt-minion -ErrorAction SilentlyContinue
    if ($service) {
        Write-Host "Stopping the salt-minion service..."
        Stop-Service -Name salt-minion
        Write-Host "Removing the salt-minion service..."
        $service = Get-WmiObject -Class Win32_Service -Filter "Name='salt-minion'"
        $service.delete() *> $null
    }

    # Remove Program Data directory
    if (Test-Path "$env:ProgramData\Salt Project") {
        Write-Host "Removing config directory..."
        Remove-Item "$env:ProgramData\Salt Project" -Force -Recurse
    }

    # Remove Program Files directory
    if (Test-Path "$env:ProgramFiles\Salt Project") {
        Write-Host "Removing install directory..."
        Remove-Item "$env:ProgramFiles\Salt Project" -Force -Recurse
    }

    # Removing from the path

    $path = "$env:ProgramFiles\Salt Project\salt"
    $path_reg_key = "HKLM:\System\CurrentControlSet\Control\Session Manager\Environment"
    $current_path = (Get-ItemProperty -Path $path_reg_key -Name Path).Path
    $new_path_list = [System.Collections.ArrayList]::new()
    foreach ($item in $current_path.Split(";")) {
        $regex_path = $path.Replace("\", "\\")
        # Bail if we find the new path in the current path
        if ($item -imatch "^$regex_path(\\)?$") {
            # Remove this one
            Write-Host "Removing salt from the system path..."
        } else {
            # Add the item to our new path array
            $new_path_list.Add($item) | Out-Null
        }
    }
    $new_path = $new_path_list -join ";"
    Set-ItemProperty -Path $path_reg_key -Name Path -Value $new_path

    Write-Header -Filler "-"
}

function tearDownScript {
    setUpScript
}

function test_Install {
    $failed = 0

    function Get-GuestVars { "master=gv_master id=gv_minion" }
    Install

    # Is the status set to installed
    try {
        $current_status = Get-ItemPropertyValue -Path $vmtools_base_reg -Name $vmtools_salt_minion_status_name
    } catch {
        $current_status = 2
    }
    if ($current_status -ne 0) { $failed = 1 }

    # Is the salt binary present
    if (!(Test-Path $salt_bin)) { $failed = 1 }

    # Is the SSM Binary present
    if (!(Test-Path $ssm_bin)) { $failed = 1 }

    # Is salt-call.bat present
    if (!(Test-Path "$salt_dir\salt-call.bat")) { $failed = 1 }

    # Is salt-minion.bat present
    if (!(Test-Path "$salt_dir\salt-minion.bat")) { $failed = 1 }

    # Is the salt-minion service registerd
    $service = Get-Service -Name salt-minion -ErrorAction SilentlyContinue
    if (!($service)) { Write-Failed; $failed = 1 }

    # Is the salt minion service running
    if ((Get-Service -Name salt-minion).Status -ne "Running") { $failed = 1 }

    # Is the minion config file present
    if (!(Test-Path $salt_config_file)) { $failed = 1 }

    # Has salt been added to the system path
    $path = "$env:ProgramFiles\Salt Project\salt"
    $path_reg_key = "HKLM:\System\CurrentControlSet\Control\Session Manager\Environment"
    $current_path = (Get-ItemProperty -Path $path_reg_key -Name Path).Path
    if (!($current_path -like "*$path*")) { $failed = 1 }

    return $failed
}

function test_Install_salt-call {
    $failed = 0
    $result = & "$salt_dir\salt-call" --local test.ping
    if (!($result -like "local:*")) { $failed = 1 }
    if (!($result -like "*True")) { $failed = 1 }
    return $failed
}
