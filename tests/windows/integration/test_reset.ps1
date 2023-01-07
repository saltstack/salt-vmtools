# Copyright (c) 2023 VMware, Inc. All rights reserved.

function setUpScript {
    Write-Host "Installing salt: " -NoNewline
    function Get-GuestVars { "master=gv_master id=gv_minion" }
    Install
    Write-Done

    Write-Host "Resetting the minion: " -NoNewline
    Reset-SaltMinion
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

function test_Reset_minion_id_directory_removed {
    # Verify that minion_id directory is removed
    if (Test-Path "$salt_config_file\minion_id") { return 1 }
    return 0
}

function test_Reset_minion_id_is_commented_out {
    # Verify that the old minion id is commented out
    foreach ($line in Get-Content $salt_config_file) {
        if ($line -match "^#id: gv_minion$") { return 0 }
    }
    return 1
}

function test_Reset_new_random_minion_id {
    # Verify that a new randomized minion id is set
    foreach ($line in Get-Content $salt_config_file) {
        if ($line -match "^id: gv_minion_.{5}$") { return 0 }
    }
    return 1
}

function test_Reset_remove_minion_private_key {
    # Ensure minion private key is removed
    if (Test-Path "$salt_pki_dir\minion.pem") { return 1 }
    return 0
}

function test_Reset_remove_minion_public_key {
    # Ensure minion public key is removed
    if (Test-Path "$salt_pki_dir\minion.pub") { return 1 }
    return 0
}
