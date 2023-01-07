# Copyright (c) 2023 VMware, Inc. All rights reserved.

function setUpScript {

    Write-Host "Installing salt: " -NoNewline
    function Get-GuestVars { "master=gv_master id=gv_minion" }
    Install
    Write-Done

    Write-Host "Removing salt using Remove: " -NoNewline
    Remove
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
    if (Test-Path "$base_salt_config_location") {
        Write-Host "Removing config directory: " -NoNewline
        Remove-Item "$base_salt_config_location" -Force -Recurse
        Write-Done
    }

    # Remove Program Files directory
    if (Test-Path "$base_salt_install_location") {
        Write-Host "Removing install directory: " -NoNewline
        Remove-Item "$base_salt_install_location" -Force -Recurse
        Write-Done
    }

    # Removing from the path

    $path = "$salt_dir"
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

function test_Remove_status_notInstalled {
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

function test_Remove_config_dir_removed {
    # Is the config directory removed
    if (Test-Path "$base_salt_config_location") { return 1 }
    return 0
}

function test_Remove_install_dir_removed {
    # Is the install directory removed
    if (Test-Path "$base_salt_install_location") { return 1 }
    return 0
}

function test_Remove_service_removed {
    # Is the salt-minion service unregistered
    $service = Get-Service -Name salt-minion -ErrorAction SilentlyContinue
    if ($service) { return 1 }
    return 0
}

function test_Remove_path_removed {
    # Is salt removed from the system path
    $path = "$salt_dir"
    $path_reg_key = "HKLM:\System\CurrentControlSet\Control\Session Manager\Environment"
    $current_path = (Get-ItemProperty -Path $path_reg_key -Name Path).Path
    if ($current_path -like "*$path*") { return 1 }
    return 0
}
