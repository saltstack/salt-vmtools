function setUpScript {
    Write-Header "Setting things up" -Filler "-"
    Write-Host "Installing salt..."
    function Get-GuestVars { "master=gv_master id=gv_minion" }
    Install
    Write-Header -Filler "-"
}

function tearDownScript {

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

function test_Remove {
    $failed = 0

    Remove

    # Is the status set to notInstalled
    try {
        $current_status = Get-ItemPropertyValue -Path $vmtools_base_reg -Name $vmtools_salt_minion_status_name
    } catch {
        # You'll only get here if the path isn't present
        $current_status = 2
    }
    if ($current_status -ne 2) { $failed = 1 }

    # Is the config directory removed
    if (Test-Path "$env:ProgramData\Salt Project") { $failed = 1 }

    # Is the install directory removed
    if (Test-Path "$env:ProgramFiles\Salt Project") { $failed = 1 }

    # Is the salt-minion service unregistered
    $service = Get-Service -Name salt-minion -ErrorAction SilentlyContinue
    if ($service) { $failed = 1 }

    # Is salt removed from the system path
    $path = "$env:ProgramFiles\Salt Project\salt"
    $path_reg_key = "HKLM:\System\CurrentControlSet\Control\Session Manager\Environment"
    $current_path = (Get-ItemProperty -Path $path_reg_key -Name Path).Path
    if ($current_path -like "*$path*") { $failed = 1 }

    return $failed
}
