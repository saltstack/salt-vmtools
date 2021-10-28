# Copyright (c) 2021 VMware, Inc. All rights reserved.

function setUp {
    Remove-Item -Path "C:\salt\bin\python.exe" -Force -ErrorAction SilentlyContinue
    Remove-Item -Path "$env:ProgramFiles\Salt Project\Salt\bin\python.exe" -Force -ErrorAction SilentlyContinue
}

function tearDown {
    Remove-Item -Path "C:\salt\bin\python.exe" -Force -ErrorAction SilentlyContinue
    Remove-Item -Path "$env:ProgramFiles\Salt Project\Salt\bin\python.exe" -Force -ErrorAction SilentlyContinue
}

function test_Find-StandardSaltInstallation {
    $result = Find-StandardSaltInstallation
    if ($result -eq $false) { return 0 }
    return 1
}

function test_Find-StandardSaltInstallation_existing_old_location {
    New-Item -Path "C:\salt\bin\python.exe" -ItemType file -Force | Out-Null
    function Get-SaltVersion { return "3004" }
    $result = Find-StandardSaltInstallation
    if ($result -eq $true) { return 0 }
    return 1
}

function test_Find-StandardSaltInstallation_existing_new_location {
    New-Item -Path "$env:ProgramFiles\Salt Project\Salt\bin\python.exe" -ItemType file -Force | Out-Null
    function Get-SaltVersion { return "3004" }
    $result = Find-StandardSaltInstallation
    if ($result -eq $true) { return 0 }
    return 1
}
