# Copyright (c) 2021 VMware, Inc. All rights reserved.
$path_dir = "$env:Temp\RemoveDir"
$path_file = "$env:Temp\RemoveFile.txt"

function setUpScript {
    Write-Host "Creating test files: " -NoNewline
    New-Item -Path $path_dir -ItemType directory -Force | Out-Null
    New-Item -Path $path_file -ItemType file -Force | Out-Null
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
    Remove-FileOrFolder -Path "C:\path\that\does\not\exist"
    return 0
}
