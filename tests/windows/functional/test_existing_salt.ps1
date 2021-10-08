# Copyright (c) 2021 VMware, Inc. All rights reserved.

function test_Find-StandardSaltInstallation {
    $result = Find-StandardSaltInstallation
    if ($result -eq $false) { return 0 } else { return 1 }
}

function test_Find-StandardSaltInstallation_existing_old_location {
    New-Item -Path "C:\salt\bin\python.exe" -ItemType file -Force | Out-Null
    $result = Find-StandardSaltInstallation
    Remove-Item -Path "C:\salt\bin\python.exe" -Force | Out-Null
    if ($result -eq $true) { return 0 } else { return 1 }
}

function test_Find-StandardSaltInstallation_existing_new_location {
    New-Item -Path "$salt_dir\bin\python.exe" -ItemType file -Force | Out-Null
    $result = Find-StandardSaltInstallation
    Remove-Item -Path "$salt_dir\bin\python.exe" -Force | Out-Null
    if ($result -eq $true) { return 0 } else { return 1 }
}
