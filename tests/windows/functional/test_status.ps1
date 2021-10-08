# Copyright (c) 2021 VMware, Inc. All rights reserved.

function test_Get-Status_notInstalled {
    Remove-ItemProperty -Path $vmtools_base_reg -Name SaltMinionStatus -ErrorAction SilentlyContinue
    $result = Get-Status
    if ($result -eq 2) { return 0 } else { return 1 }
}

function test_Get-Status_installed {
    New-ItemProperty -Path $vmtools_base_reg -Name SaltMinionStatus -Value 0 | Out-Null
    $result = Get-Status
    if ($result -eq 0) { return 0 } else { return 1 }
}

function test_Get-Status_installing
{
    Set-ItemProperty -Path $vmtools_base_reg -Name SaltMinionStatus -Value 1
    Start-Process powershell -ArgumentList "-file .\svtminion.ps1 -d"
    $result = Get-Status
    if ($result -eq 1) { return 0 } else { return 1 }
}

function test_Get-Status_installFailed {
    Set-ItemProperty -Path $vmtools_base_reg -Name SaltMinionStatus -Value 3
    $result = Get-Status
    if ($result -eq 3) { return 0 } else { return 1 }
}

function test_Get-Status_removing {
    Set-ItemProperty -Path $vmtools_base_reg -Name SaltMinionStatus -Value 4
    Start-Process powershell -ArgumentList "-file .\svtminion.ps1 -d"
    $result = Get-Status
    if ($result -eq 4) { return 0 } else { return 1 }
}

function test_Get-Status_removeFailed {
    Set-ItemProperty -Path $vmtools_base_reg -Name SaltMinionStatus -Value 5
    $result = Get-Status
    if ($result -eq 5) { return 0 } else { return 1 }
}

function test_Get-Status_unknownStatus {
    Write-Host "- Unknown Status: " -NoNewline
    Set-ItemProperty -Path $vmtools_base_reg -Name SaltMinionStatus -Value 7
    $result = Get-Status
    if ($result -eq 7) { return 0 } else { return 1 }
}

function test_Set-Status_installed {
    Set-Status -NewStatus installed
    $result = Get-ItemProperty -Path $vmtools_base_reg -Name SaltMinionStatus
    if ($result.SaltMinionStatus -eq 0) { return 0 } else { return 1 }
}

function test_Set-Status_installing {
    Set-Status -NewStatus installing
    $result = Get-ItemProperty -Path $vmtools_base_reg -Name SaltMinionStatus
    if ($result.SaltMinionStatus -eq 1) { return 0 } else { return 1 }
}

function test_Set-Status_notInstalled {
    Set-Status -NewStatus notInstalled
    $result = Get-Status
    if ($result -eq 2) { return 0 } else { return 1 }
}

function test_Set-Status_installFailed {
    Set-Status -NewStatus installFailed
    $result = Get-ItemProperty -Path $vmtools_base_reg -Name SaltMinionStatus
    if ($result.SaltMinionStatus -eq 3) { return 0 } else { return 1 }
}

function test_Set-Status_removing {
    Set-Status -NewStatus removing
    $result = Get-ItemProperty -Path $vmtools_base_reg -Name SaltMinionStatus
    if ($result.SaltMinionStatus -eq 4) { return 0 } else { return 1 }
}

function test_Set-Status_removing {
    Set-Status -NewStatus removeFailed
    $result = Get-ItemProperty -Path $vmtools_base_reg -Name SaltMinionStatus
    if ($result.SaltMinionStatus -eq 5) { return 0 } else { return 1 }
}

function test_Set-FailedStatus_installFailed {
    $Action = "add"
    Set-FailedStatus
    $result = Get-ItemProperty -Path $vmtools_base_reg -Name SaltMinionStatus
    if ($result.SaltMinionStatus -eq 3) { return 0 } else { return 1 }
}

function test_Set-FailedStatus_removeFailed {
    $Action = "remove"
    Set-FailedStatus
    $result = Get-ItemProperty -Path $vmtools_base_reg -Name SaltMinionStatus
    if ($result.SaltMinionStatus -eq 5) { return 0 } else { return 1 }
}
