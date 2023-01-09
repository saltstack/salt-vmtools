# Copyright 2021-2023 VMware, Inc.
# SPDX-License-Identifier: Apache-2

$target_dir = "$env:Temp\TargetDir"
$target_file = "$env:Temp\TargetFile.txt"
$path_dir = "$env:Temp\RemoveDir"
$path_file = "$env:Temp\RemoveFile.txt"
$path_link = "$env:Temp\RemoveSymlink.txt"
$path_junction = "$env:Temp\RemoveJunction.txt"
$path_hardlink = "$env:Temp\RemoveHardlink.txt"
$path_readonly = "$env:Temp\RemoveReadOnly"

function setUpScript {
    Write-Host "Creating test files: " -NoNewline
    # Simple Tests
    New-Item -Path $target_dir -ItemType Directory -Force | Out-Null
    New-Item -Path $target_file -ItemType File -Force | Out-Null
    New-Item -Path $path_dir -ItemType Directory -Force | Out-Null
    New-Item -Path $path_file -ItemType File -Force | Out-Null
    New-Item -Path $path_link -ItemType SymbolicLink -Target $target_dir | Out-Null
    New-Item -Path $path_junction -ItemType Junction -Target $target_dir | Out-Null
    New-Item -Path $path_hardlink -ItemType HardLink -Target $target_file | Out-Null

    # Old Salt Directory test where the pem file is readonly
    New-Item -Path $path_readonly -ItemType Directory -Force | Out-Null
    New-Item -Path "$path_readonly\conf\pki\minion\minion.pem" -ItemType File -Force | Out-Null
    Set-ItemProperty "$path_readonly\conf\pki\minion\minion.pem" -Name IsReadOnly -Value $true

    Write-Done
}

function tearDownScript {
    if (Test-Path -Path "$path_dir") {
        Write-Host "Removing $($path_dir): " -NoNewline
        Remove-Item -Path "$path_dir" -Force -Recurse
        Write-Done
    }
    if (Test-Path -Path "$path_file") {
        Write-Host "Removing $($path_file): " -NoNewline
        Remove-Item -Path "$path_file" -Force
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
        Remove-Item -Path "$path_hardlink" -Force
        Write-Done
    }
    if (Test-Path -Path "$target_dir") {
        Write-Host "Removing $($target_dir): " -NoNewline
        Remove-Item -Path "$target_dir" -Force -Recurse
        Write-Done
    }
    if (Test-Path -Path "$target_file") {
        Write-Host "Removing $($target_file): " -NoNewline
        Remove-Item -Path "$target_file"
        Write-Done
    }
    if (Test-Path -Path "$path_readonly") {
        Write-Host "Removing $($path_readonly): " -NoNewline
        Remove-Item -Path "$path_readonly" -Force -Recurse
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

function test_Remove-FileOrFolder_contains_readonly {
    # Contains a read only file...
    Remove-FileOrFolder -Path $path_readonly
    if (Test-Path -Path $path_readonly) { return 1 }
    return 0
}
