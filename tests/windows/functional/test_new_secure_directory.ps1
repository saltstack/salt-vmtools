# Copyright (c) 2021 VMware, Inc. All rights reserved.

$test_existing = "$env:Temp\spongebob"
$test_existing_symlink = "$env:Temp\squarepants"
$test_existing_insecure_owner = "$env:Temp\squidward"
$test_existing_not_empty = "$env:Temp\patrick"

function setUpScript {
    Write-Host "Creating existing test directory: " -NoNewline
    New-Item -Path $test_existing -Type Directory -Force | Out-Null
    $Script:existing_time = (Get-Item -Path $test_existing).CreationTime
    Write-Done

    Write-Host "Creating symlink test directory: " -NoNewline
    New-Item -ItemType SymbolicLink -Path $test_existing_symlink -Target $test_existing | Out-Null
    Write-Done

    Write-Host "Creating insecure owner test directory: " -NoNewline
    New-Item -Path $test_existing_insecure_owner -Type Directory -Force | Out-Null
    $file_acl = Get-Acl -Path $test_existing_insecure_owner
    $file_acl.SetOwner([System.Security.Principal.NTAccount]"BUILTIN\Users")
    Set-Acl -Path $test_existing_insecure_owner -AclObject $file_acl
    Write-Done

    Write-Host "Creating not empty test directory: " -NoNewline
    New-Item -Path $test_existing_not_empty -Type Directory -Force | Out-Null
    New-Item -Path "$test_existing_not_empty\dir1" -Type Directory -Force | Out-Null
    New-Item -Path "$test_existing_not_empty\dir2" -Type Directory -Force | Out-Null
    New-Item -Path "$test_existing_not_empty\file1.txt" -Type File -Force | Out-Null
    New-Item -Path "$test_existing_not_empty\file2.txt" -Type File -Force | Out-Null
    Write-Done

}

function tearDownScript {
    if (Test-Path -Path $test_existing_symlink) {
        Write-Host "Removing symlink test directory: " -NoNewline
        [System.IO.Directory]::Delete($test_existing_symlink, $true) | Out-Null
        Write-Done
    }

    if (Test-Path -Path "$test_existing_symlink.insecure") {
        Write-Host "Removing symlink insecure directory: " -NoNewline
        [System.IO.Directory]::Delete("$test_existing_symlink.insecure", $true) | Out-Null
        Write-Done
    }

    if (Test-Path -Path $test_existing_insecure_owner) {
        Write-Host "Removing owner test directory: " -NoNewline
        Remove-Item -Path $test_existing_insecure_owner -Force
        Write-Done
    }

    if (Test-Path -Path "$test_existing_insecure_owner.insecure") {
        Write-Host "Removing owner insecure test directory: " -NoNewline
        Remove-Item -Path "$test_existing_insecure_owner.insecure" -Force
        Write-Done
    }

    if (Test-Path -Path $test_existing_not_empty) {
        Write-Host "Removing not empty test directory: " -NoNewline
        Remove-Item -Path $test_existing_not_empty -Recurse -Force
        Write-Done
    }

    if (Test-Path -Path "$test_existing_not_empty.insecure") {
        Write-Host "Removing not empty insecure test directory: " -NoNewline
        Remove-Item -Path "$test_existing_not_empty.insecure" -Recurse -Force
        Write-Done
    }

    if (Test-Path -Path $test_existing) {
        Write-Host "Removing existing test directory: " -NoNewline
        Remove-Item -Path $test_existing -Recurse -Force
        Write-Done
    }

}

function test_New-SecureDirectory_existing {
    # We're deleting anything we find, so the creation date should be different
    $before_time = (Get-Item -Path $test_existing).CreationTime
    New-SecureDirectory -Path $test_existing
    $after_time= (Get-Item -Path $test_existing).CreationTime
    if ($before_time -lt $after_time) { return 0 }
    return 1
}

function test_New-SecureDirectory_symlink {
    # Should rename the symlink
    New-SecureDirectory -Path $test_existing_symlink
    if (Get-IsSymLink -Path $test_existing_symlink) { return 1 }
    if (!(Test-Path -Path "$test_existing_symlink-$script_date.insecure")) { return 1 }
    return 0
}

function test_New-SecureDirectory_insecure_owner {
    # Should rename the directory
    New-SecureDirectory -Path $test_existing_insecure_owner
    if (!(Test-Path -Path "$test_existing_insecure_owner-$script_date.insecure")) { return 1 }
    return 0
}

function test_New-SecureDirectory_not_empty {
    # Should wipe out the directory and create a new empty directory
    New-SecureDirectory -Path $test_existing_not_empty
    if((Get-ChildItem -Path $test_existing_not_empty | Measure-Object).Count -ne 0) { return 1 }
    return 0
}
