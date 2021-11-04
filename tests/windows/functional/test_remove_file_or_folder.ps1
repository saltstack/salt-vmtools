# Copyright (c) 2021 VMware, Inc. All rights reserved.
$path_dir = "$env:Temp\RemoveDir"
$path_file = "$env:Temp\RemoveFile.txt"
$path_link = "$env:Temp\RemoveSymlink.txt"
$path_junction = "$env:Temp\RemoveJunction.txt"
$path_hardlink = "$env:Temp\RemoveHardlink.txt"
$path_hardlink_file = "$env:Temp\hardlink_target.txt"

function setUpScript {
    Write-Host "Creating test files: " -NoNewline
    New-Item -Path $path_dir -ItemType directory -Force | Out-Null
    New-Item -Path $path_file -ItemType file -Force | Out-Null
    New-Item -Path $path_link -ItemType SymbolicLink -Target $base_salt_install_location | Out-Null
    New-Item -Path $path_junction -ItemType Junction -Target $base_salt_install_location | Out-Null
    New-Item -Path $path_hardlink_file -ItemType File | Out-Null
    New-Item -Path $path_hardlink -ItemType HardLink -Target $path_hardlink_file | Out-Null
    Write-Done
}

function tearDownScript {
    if (Test-Path -Path "$path_dir") {
        Write-Host "Removing $($path_dir): " -NoNewline
        Remove-Item -Path "$path_dir"
        Write-Done
    }
    if (Test-Path -Path "$path_file") {
        Write-Host "Removing $($path_file): " -NoNewline
        Remove-Item -Path "$path_file"
        Write-Done
    }
    if (Test-Path -Path "$path_link") {
        Write-Host "Removing $($path_link): " -NoNewline
        [System.IO.Directory]::Delete($path_link, $true) | Out-Null
        Write-Done
    }
    if (Test-Path -Path "$path_junction") {
        Write-Host "Removing $($path_junction): " -NoNewline
        [System.IO.Directory]::Delete($path_junction, $true) | Out-Null
        Write-Done
    }
    if (Test-Path -Path "$path_hardlink") {
        Write-Host "Removing $($path_hardlink): " -NoNewline
        [System.IO.Directory]::Delete($path_hardlink, $true) | Out-Null
        Write-Done
    }
    if (Test-Path -Path "$path_hardlink_file") {
        Write-Host "Removing $($path_hardlink_file): " -NoNewline
        Remove-Item -Path "$path_hardlink_file"
        Write-Done
    }
}

function test_Remove-FileOrFolder_directory {
    Remove-FileOrFolder -Path $path_dir
    if (Test-Path -Path $path_dir) { return 1 }
    return 0
}

function test_Remove-FileOrFolder_file {
    Remove-FileOrFolder -Path $path_file
    if (Test-Path -Path $path_file) { return 1 }
    return 0
}

function test_Remove-FileOrFolder_not_exist {
    # Should not throw an error
    Remove-FileOrFolder -Path "C:\path\that\does\not\exist"
    return 0
}

function test_Remove-FileOrFolder_symlink {
    Remove-FileOrFolder -Path $path_link
    if (Test-Path -Path $path_link) { return 1 }
    return 0
}

function test_Remove-FileOrFolder_junction {
    Remove-FileOrFolder -Path $path_junction
    if (Test-Path -Path $path_junction) { return 1 }
    return 0
}

function test_Remove-FileOrFolder_hardlink {
    Remove-FileOrFolder -Path $path_hardlink
    if (Test-Path -Path $path_hardlink) { return 1 }
    return 0
}
