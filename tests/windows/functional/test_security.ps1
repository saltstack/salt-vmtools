# Copyright (c) 2021 VMware, Inc. All rights reserved.

$test_path = "$env:Temp\spongebob"

function setUp {
    New-Item -Path $test_path -Type Directory -Force | Out-Null
}

function tearDown {
    Remove-Item -Path $test_path -Force
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
    Set-Security -Path $test_path

    $sd = Get-Acl($test_path)

    $result = ($sd | Select-Object Owner).Owner

    if ($result.EndsWith("SYSTEM")) { return 0 }
    return 1
}

function test_Set-Security_owner_administrators {
    Set-Security -Path $test_path -Owner "Administrators"

    $sd = Get-Acl($test_path)

    $result = ($sd | Select-Object Owner).Owner

    if ($result.EndsWith("Administrators")) { return 0 }
    return 1
}
