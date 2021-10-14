# Copyright (c) 2021 VMware, Inc. All rights reserved.

$test_path = "$env:Temp\spongebob"
$test_symlink = "$env:Temp\squidward"
$test_junction = "$env:Temp\patrick"

function setUpScript {
    Write-Host "Creating test directory: " -NoNewline
    New-Item -Path $test_path -Type Directory -Force | Out-Null
    Write-Done

    Write-Host "Creating test symlink: " -NoNewline
    New-Item -ItemType SymbolicLink -Path $test_symlink -Target $test_path | Out-Null
    Write-Done

    Write-Host "Creating test junction: " -NoNewline
    New-Item -ItemType Junction -Path $test_junction -Target $test_path | Out-Null
    Write-Done
}

function tearDownScript {
    Write-Host "Removing test symlink: " -NoNewline
    [System.IO.Directory]::Delete($test_symlink, $true) | Out-Null
    Write-Done

    Write-Host "Removing test junction: " -NoNewline
    [System.IO.Directory]::Delete($test_junction, $true) | Out-Null
    Write-Done

    Write-Host "Removing test directory: " -NoNewline
    Remove-Item -Path $test_path -Force | Out-Null
    Write-Done

}

function test_Get-IsSymlink_directory {
    $result = Get-IsSymLink -Path $test_path

    if (!$result) { return 0 }
    return 1
}

function test_Get-IsSymlink_symlink {
    $result = Get-IsSymLink -Path $test_symlink

    if ($result) { return 0 }
    return 1
}

function test_Get-IsSymlink_junction {
    $result = Get-IsSymLink -Path $test_junction

    if ($result) { return 0 }
    return 1
}
