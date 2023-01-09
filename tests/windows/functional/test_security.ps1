# Copyright 2021-2023 VMware, Inc.
# SPDX-License-Identifier: Apache-2

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

function test_Set-Security_sddl {
    Set-Security -Path $test_path

    $sd = Get-Acl($test_path)
    $owner = ($sd | Select-Object Owner).Owner

    $expected = "PAI(A;OICI;0x1200a9;;;WD)(A;OICI;FA;;;SY)(A;OICI;FA;;;BA)"
    $result = $sd.Sddl

    if ($result.ToLower().EndsWith($expected.ToLower())) { return 0 }
    return 1
}

function test_Set-Security_owner_default {
    $sd = Get-Acl($test_path)
    $before_owner = ($sd | Select-Object Owner).Owner

    Set-Security -Path $test_path

    $sd = Get-Acl($test_path)
    $after_owner = ($sd | Select-Object Owner).Owner

    if ($before_owner -eq $after_owner) { return 0 }
    return 1
}

function test_Set-Security_owner_administrators {
    Set-Security -Path $test_path -Owner "Administrators"

    $sd = Get-Acl($test_path)

    $result = ($sd | Select-Object Owner).Owner

    if ($result.EndsWith("Administrators")) { return 0 }
    return 1
}

function test_Set-Security_owner_system {
    Set-Security -Path $test_path -Owner "SYSTEM"

    $sd = Get-Acl($test_path)

    $result = ($sd | Select-Object Owner).Owner

    if ($result.EndsWith("SYSTEM")) { return 0 }
    return 1
}
