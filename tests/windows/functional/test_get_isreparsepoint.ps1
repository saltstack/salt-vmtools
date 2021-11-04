# Copyright (c) 2021 VMware, Inc. All rights reserved.

$test_directory = "$env:Temp\spongebob"
$test_file = "$env:Temp\mr.krabbs"
$test_symlink = "$env:Temp\squidward"
$test_junction = "$env:Temp\patrick"
$test_hardlink = "$env:Temp\plankton"

function setUpScript {
    Write-Host "Creating test directory: " -NoNewline
    New-Item -Path $test_directory -Type Directory -Force | Out-Null
    Write-Done

    Write-Host "Creating test file: " -NoNewline
    New-Item -Path $test_file -Type File -Force | Out-Null
    Write-Done

    Write-Host "Creating test symlink: " -NoNewline
    New-Item -ItemType SymbolicLink -Path $test_symlink -Target $test_directory | Out-Null
    Write-Done

    Write-Host "Creating test junction: " -NoNewline
    New-Item -ItemType Junction -Path $test_junction -Target $test_directory | Out-Null
    Write-Done

    Write-Host "Creating test hardlink: " -NoNewline
    New-Item -ItemType Junction -Path $test_hardlink -Target $test_directory | Out-Null
    Write-Done
}

function tearDownScript {
    Write-Host "Removing test symlink: " -NoNewline
    [System.IO.Directory]::Delete($test_symlink, $true) | Out-Null
    Write-Done

    Write-Host "Removing test junction: " -NoNewline
    [System.IO.Directory]::Delete($test_junction, $true) | Out-Null
    Write-Done

    Write-Host "Removing test hardlink: " -NoNewline
    [System.IO.Directory]::Delete($test_hardlink, $true) | Out-Null
    Write-Done

    Write-Host "Removing test directory: " -NoNewline
    Remove-Item -Path $test_directory -Force | Out-Null
    Write-Done

    Write-Host "Removing test file: " -NoNewline
    Remove-Item -Path $test_file -Force | Out-Null
    Write-Done
}

function test_Get-IsReparsePoint_directory {
    $result = Get-IsReparsePoint -Path $test_directory

    if (!$result) { return 0 }
    return 1
}

function test_Get-IsReparsePoint_file {
    $result = Get-IsReparsePoint -Path $test_file

    if (!$result) { return 0 }
    return 1
}

function test_Get-IsReparsePoint_symlink {
    $result = Get-IsReparsePoint -Path $test_symlink

    if ($result) { return 0 }
    return 1
}

function test_Get-IsReparsePoint_junction {
    $result = Get-IsReparsePoint -Path $test_junction

    if ($result) { return 0 }
    return 1
}

function test_Get-IsReparsePoint_hardlink {
    $result = Get-IsReparsePoint -Path $test_hardlink

    if ($result) { return 0 }
    return 1
}
