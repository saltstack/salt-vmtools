# Copyright (c) 2023 VMware, Inc. All rights reserved.

function tearDownScript {
    if (Test-Path -Path "$env:Temp\salt-call.bat") {
        Write-Host "Removing salt-call.bat: " -NoNewline
        Remove-Item -Path "$env:Temp\salt-call.bat"
        Write-Done
    }
    if (Test-Path -Path "$env:Temp\salt-minion.bat") {
        Write-Host "Removing salt-minion.bat: " -NoNewline
        Remove-Item -Path "$env:Temp\salt-minion.bat"
        Write-Done
    }
}

function test_New-SaltCallScript {
    $path = "$env:Temp\salt-call.bat"
    New-SaltCallScript -Path $path
    if (!(Test-Path -Path $path)) { return 1 }
    $content = Get-Content -Path $path
    if (!($content -like "*Copyright*VMware*" )) { return 1 }
    if (!($content -like '*"%SaltBin%" call %*')) { return 1 }
    return 0
}

function test_New-SaltMinionScript {
    $path = "$env:Temp\salt-minion.bat"
    New-SaltMinionScript -Path $path
    if (!(Test-Path -Path $path)) { return 1 }
    $content = Get-Content -Path $path
    if (!($content -like "*Copyright*VMware*" )) { return 1 }
    if (!($content -like '*"%SaltBin%" minion %*')) { return 1 }
    return 0
}
