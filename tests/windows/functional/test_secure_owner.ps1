# Copyright (c) 2023 VMware, Inc. All rights reserved.

$test_path = "$env:Temp\spongebob"

function setUpScript {
    Write-Host "Creating test directory: " -NoNewline
    New-Item -Path $test_path -Type Directory -Force | Out-Null
    Write-Done
}

function tearDownScript {
    Write-Host "Removing test directory: " -NoNewline
    Remove-Item -Path $test_path -Force
    Write-Done
}

function test_Get-IsSecureOwner_administrators {
    $file_acl = Get-Acl -Path $test_path
    $file_acl.SetOwner([System.Security.Principal.NTAccount]"Administrators")
    Set-Acl -Path $test_path -AclObject $file_acl

    $result = Get-IsSecureOwner -Path $test_path

    if ($result) { return 0 }
    return 1
}

function test_Get-IsSecureOwner_system {
    $file_acl = Get-Acl -Path $test_path
    $file_acl.SetOwner([System.Security.Principal.NTAccount]"SYSTEM")
    Set-Acl -Path $test_path -AclObject $file_acl

    $result = Get-IsSecureOwner -Path $test_path

    if ($result) { return 0 }
    return 1
}

function test_Get-IsSecureOwner_users {
    $file_acl = Get-Acl -Path $test_path
    $file_acl.SetOwner([System.Security.Principal.NTAccount]"Users")
    Set-Acl -Path $test_path -AclObject $file_acl

    $result = Get-IsSecureOwner -Path $test_path

    if (!$result) { return 0 }
    return 1
}
