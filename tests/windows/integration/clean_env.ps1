Import-Module .\tests\windows\helpers.ps1
Write-Label $MyInvocation.MyCommand.Name

Write-TestLabel "Cleaning the environment"

# Stop and remove the salt-minion service if it exists
$service = Get-Service -Name salt-minion -ErrorAction SilentlyContinue
if ($service) {
    # Stop the minion service
    Write-Host "Stopping the minion service..."
    Stop-Service -Name salt-minion

    # Delete the service
    Write-Host "Removing the minion service..."
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
Write-Host "Removing from path..."
$path = "$env:ProgramFiles\Salt Project\salt"
$path_reg_key = "HKLM:\System\CurrentControlSet\Control\Session Manager\Environment"
$current_path = (Get-ItemProperty -Path $path_reg_key -Name Path).Path
$new_path_list = [System.Collections.ArrayList]::new()
foreach ($item in $current_path.Split(";")) {
    $regex_path = $path.Replace("\", "\\")
    # Bail if we find the new path in the current path
    if ($item -imatch "^$regex_path(\\)?$") {
        # Remove this one
    } else {
        # Add the item to our new path array
        $new_path_list.Add($item) | Out-Null
    }
}
$new_path = $new_path_list -join ";"
Set-ItemProperty -Path $path_reg_key -Name Path -Value $new_path

Write-Label "="
Write-Host ""
