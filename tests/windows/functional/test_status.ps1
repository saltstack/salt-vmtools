# Copyright (c) 2021 VMware, Inc. All rights reserved.

function test_Get-Status_notInstalled {
    Remove-ItemProperty -Path $vmtools_base_reg -Name SaltMinionStatus -ErrorAction SilentlyContinue
    $result = Get-Status
    if ($result -eq $STATUS_CODES["notInstalled"]) { return 0 }
    return 1
}

function test_Get-Status_installed {
    $reg_value = $STATUS_CODES["installed"]
    Set-ItemProperty -Path $vmtools_base_reg -Name SaltMinionStatus -Value $reg_value
    $result = Get-Status
    if ($result -eq $STATUS_CODES["installed"]) { return 0 }
    return 1
}

function test_Get-Status_installing
{
    $reg_value = $STATUS_CODES["installing"]
    Set-ItemProperty -Path $vmtools_base_reg -Name SaltMinionStatus -Value $reg_value
    Start-Process powershell -ArgumentList "-file .\svtminion.ps1 -d"
    $result = Get-Status
    if ($result -eq $STATUS_CODES["installing"]) { return 0 }
    return 1
}

function test_Get-Status_installFailed {
    $reg_value = $STATUS_CODES["installFailed"]
    Set-ItemProperty -Path $vmtools_base_reg -Name SaltMinionStatus -Value $reg_value
    $result = Get-Status
    if ($result -eq $STATUS_CODES["installFailed"]) { return 0 }
    return 1
}

function test_Get-Status_removing {
    $reg_value = $STATUS_CODES["removing"]
    Set-ItemProperty -Path $vmtools_base_reg -Name SaltMinionStatus -Value $reg_value
    Start-Process powershell -ArgumentList "-file .\svtminion.ps1 -d"
    $result = Get-Status
    if ($result -eq $STATUS_CODES["removing"]) { return 0 }
    return 1
}

function test_Get-Status_removeFailed {
    $reg_value = $STATUS_CODES["removeFailed"]
    Set-ItemProperty -Path $vmtools_base_reg -Name SaltMinionStatus -Value $reg_value
    $result = Get-Status
    if ($result -eq $STATUS_CODES["removeFailed"]) { return 0 }
    return 1
}

function test_Get-Status_unknownStatus {
    Set-ItemProperty -Path $vmtools_base_reg -Name SaltMinionStatus -Value 7
    $result = Get-Status
    if ($result -eq 7) { return 0 }
    return 1
}

function test_Set-Status_installed {
    Set-Status -NewStatus installed
    $result = Get-ItemProperty -Path $vmtools_base_reg -Name SaltMinionStatus
    if ($result.SaltMinionStatus -eq $STATUS_CODES["installed"]) { return 0 }
    return 1
}

function test_Set-Status_installing {
    Set-Status -NewStatus installing
    $result = Get-ItemProperty -Path $vmtools_base_reg -Name SaltMinionStatus
    if ($result.SaltMinionStatus -eq $STATUS_CODES["installing"]) { return 0 }
    return 1
}

function test_Set-Status_notInstalled {
    Set-Status -NewStatus notInstalled
    $result = Get-Status
    if ($result -eq $STATUS_CODES["notInstalled"]) { return 0 }
    return 1
}

function test_Set-Status_installFailed {
    Set-Status -NewStatus installFailed
    $result = Get-ItemProperty -Path $vmtools_base_reg -Name SaltMinionStatus
    if ($result.SaltMinionStatus -eq $STATUS_CODES["installFailed"]) { return 0 }
    return 1
}

function test_Set-Status_removing {
    Set-Status -NewStatus removing
    $result = Get-ItemProperty -Path $vmtools_base_reg -Name SaltMinionStatus
    if ($result.SaltMinionStatus -eq $STATUS_CODES["removing"]) { return 0 }
    return 1
}

function test_Set-Status_removeFailed {
    Set-Status -NewStatus removeFailed
    $result = Get-ItemProperty -Path $vmtools_base_reg -Name SaltMinionStatus
    if ($result.SaltMinionStatus -eq $STATUS_CODES["removeFailed"]) { return 0 }
    return 1
}

function test_Set-FailedStatus_installFailed {
    $Action = "add"
    Set-FailedStatus
    $result = Get-ItemProperty -Path $vmtools_base_reg -Name SaltMinionStatus
    if ($result.SaltMinionStatus -eq $STATUS_CODES["installFailed"]) { return 0 }
    return 1
}

function test_Set-FailedStatus_removeFailed {
    $Action = "remove"
    Set-FailedStatus
    $result = Get-ItemProperty -Path $vmtools_base_reg -Name SaltMinionStatus
    if ($result.SaltMinionStatus -eq $STATUS_CODES["removeFailed"]) { return 0 }
    return 1
}
