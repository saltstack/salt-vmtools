# Copyright 2021-2023 VMware, Inc.
# SPDX-License-Identifier: Apache-2

function setUp {
    Remove-Item -Path "C:\salt\bin\python.exe" -Force -ErrorAction SilentlyContinue
    New-Item -Path "HKLM:\SOFTWARE\Salt Project" -ErrorAction SilentlyContinue | Out-Null
    New-Item -Path "HKLM:\SOFTWARE\Salt Project\Salt" -ErrorAction SilentlyContinue | Out-Null
    Remove-ItemProperty -Path "HKLM:\SOFTWARE\Salt Project\Salt" -Name "install_dir" -ErrorAction SilentlyContinue
}

function tearDown {
    Remove-Item -Path "C:\salt\bin\python.exe" -Force -ErrorAction SilentlyContinue
    Remove-ItemProperty -Path "HKLM:\SOFTWARE\Salt Project\Salt" -Name "install_dir" -ErrorAction SilentlyContinue
}

function test_Find-StandardSaltInstallation {
    $result = Find-StandardSaltInstallation
    if ($result -eq $false) { return 0 }
    return 1
}

function test_Find-StandardSaltInstallation_existing_newer {
    New-ItemProperty -Path "HKLM:\SOFTWARE\Salt Project\Salt" -Name "install_dir" -Value "%WINDIR%" | Out-Null
    function Get-SaltVersion { return "3004" }
    $result = Find-StandardSaltInstallation
    if ($result -eq $true) { return 0 }
    return 1
}

function test_Find-StandardSaltInstallation_existing_old {
    New-Item -Path "C:\salt\bin\python.exe" -ItemType file -Force | Out-Null
    function Get-SaltVersion { return "3003" }
    $result = Find-StandardSaltInstallation
    if ($result -eq $true) { return 0 }
    return 1
}
