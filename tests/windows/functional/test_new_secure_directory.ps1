# Copyright 2021-2023 VMware, Inc.
# SPDX-License-Identifier: Apache-2

$target_file = "$env:Temp\mr.krabbs"
$target_dir = "$env:Temp\spongebob"
$test_file = "$env:Temp\flying.dutchman"
$test_directory = "$env:Temp\gary"
$test_symlink_dir = "$env:Temp\squarepants"
$test_symlink_file = "$env:Temp\squarepants.txt"
$test_junction = "$env:Temp\sandy"
$test_hardlink = "$env:Temp\plankton"
$test_insecure_owner = "$env:Temp\squidward"
$test_not_empty = "$env:Temp\patrick"

function setUpScript {
    Write-Host "Creating target file: " -NoNewline
    New-Item -Path $target_file -Type file -Force | Out-Null
    Write-Done

    Write-Host "Creating target directory: " -NoNewline
    New-Item -Path $target_dir -Type Directory -Force | Out-Null
    Write-Done

    Write-Host "Creating test file: " -NoNewline
    New-Item -Path $test_file -Type file -Force | Out-Null
    Write-Done

    Write-Host "Creating existing test directory: " -NoNewline
    New-Item -Path $test_directory -Type Directory -Force | Out-Null
    Write-Done

    Write-Host "Creating symlink test directory: " -NoNewline
    New-Item -ItemType SymbolicLink -Path $test_symlink_dir -Target $target_dir | Out-Null
    Write-Done

    Write-Host "Creating symlink test file: " -NoNewline
    New-Item -ItemType SymbolicLink -Path $test_symlink_file -Target $target_file | Out-Null
    Write-Done

    Write-Host "Creating junction test directory: " -NoNewline
    New-Item -ItemType Junction -Path $test_junction -Target $target_dir | Out-Null
    Write-Done

    Write-Host "Creating hardlink test file: " -NoNewline
    New-Item -ItemType Hardlink -Path $test_hardlink -Target $target_file | Out-Null
    Write-Done

    Write-Host "Creating insecure owner test directory: " -NoNewline
    New-Item -Path $test_insecure_owner -Type Directory -Force | Out-Null
    $file_acl = Get-Acl -Path $test_insecure_owner
    $file_acl.SetOwner([System.Security.Principal.NTAccount]"BUILTIN\Users")
    Set-Acl -Path $test_insecure_owner -AclObject $file_acl
    Write-Done

    Write-Host "Creating not empty test directory: " -NoNewline
    New-Item -Path $test_not_empty -Type Directory -Force | Out-Null
    New-Item -Path "$test_not_empty\dir1" -Type Directory -Force | Out-Null
    New-Item -Path "$test_not_empty\dir2" -Type Directory -Force | Out-Null
    New-Item -Path "$test_not_empty\file1.txt" -Type File -Force | Out-Null
    New-Item -Path "$test_not_empty\file2.txt" -Type File -Force | Out-Null
    Write-Done
}

function tearDownScript {
    if (Test-Path -Path $test_directory) {
        Write-Host "Removing existing test directory: " -NoNewline
        Remove-Item -Path $test_directory -Recurse -Force
        Write-Done
    }

    if (Test-Path -Path $test_file) {
        Write-Host "Removing existing test file: " -NoNewline
        Remove-Item -Path $test_file -Recurse -Force
        Write-Done
    }

    if (Test-Path -Path $test_symlink_dir) {
        Write-Host "Removing symlink test directory: " -NoNewline
        [System.IO.Directory]::Delete($test_symlink_dir, $true) | Out-Null
        Write-Done
    }

    if (Test-Path -Path "$test_symlink_dir-$script_date.insecure") {
        Write-Host "Removing symlink insecure directory: " -NoNewline
        [System.IO.Directory]::Delete("$test_symlink_dir-$script_date.insecure", $true) | Out-Null
        Write-Done
    }

    while (Test-Path -Path $test_symlink_file) {
        if ((Get-Item -Path $test_symlink_file) -is [System.IO.DirectoryInfo]) {
            Write-Host "Removing symlink test file directory: " -NoNewline
            [System.IO.Directory]::Delete($test_symlink_file, $true) | Out-Null
            Write-Done
        } else {
            Write-Host "Removing symlink test file: " -NoNewline
            [System.IO.File]::Delete($test_symlink_file) | Out-Null
            Write-Done
        }
    }

    if (Test-Path -Path "$test_symlink_file-$script_date.insecure") {
        Write-Host "Removing symlink insecure file: " -NoNewline
        [System.IO.File]::Delete("$test_symlink_file-$script_date.insecure") | Out-Null
        Write-Done
    }

    if (Test-Path -Path $test_junction) {
        Write-Host "Removing junction test directory: " -NoNewline
        [System.IO.Directory]::Delete($test_junction, $true) | Out-Null
        Write-Done
    }

    if (Test-Path -Path "$test_junction-$script_date.insecure") {
        Write-Host "Removing junction insecure directory: " -NoNewline
        [System.IO.Directory]::Delete("$test_junction-$script_date.insecure", $true) | Out-Null
        Write-Done
    }

    if (Test-Path -Path $test_hardlink) {
        Write-Host "Removing hardlink test file: " -NoNewline
        Remove-Item -Path $test_hardlink -Force
        Write-Done
    }

    if (Test-Path -Path "$test_hardlink-$script_date.insecure") {
        Write-Host "Removing hardlink insecure file: " -NoNewline
        Remove-Item -Path "$test_hardlink-$script_date.insecure" -Force
        Write-Done
    }

    if (Test-Path -Path $test_insecure_owner) {
        Write-Host "Removing owner test directory: " -NoNewline
        Remove-Item -Path $test_insecure_owner -Force
        Write-Done
    }

    if (Test-Path -Path "$test_insecure_owner-$script_date.insecure") {
        Write-Host "Removing owner insecure test directory: " -NoNewline
        Remove-Item -Path "$test_insecure_owner-$script_date.insecure" -Force
        Write-Done
    }

    if (Test-Path -Path $test_not_empty) {
        Write-Host "Removing not empty test directory: " -NoNewline
        Remove-Item -Path $test_not_empty -Recurse -Force
        Write-Done
    }

    if (Test-Path -Path "$test_not_empty-$script_date.insecure") {
        # This shouldn't get hit
        Write-Host "Removing not empty insecure test directory: " -NoNewline
        Remove-Item -Path "$test_not_empty-$script_date.insecure" -Recurse -Force
        Write-Done
    }

    if (Test-Path -Path $target_file) {
        Write-Host "Removing target file: " -NoNewline
        Remove-Item -Path $target_file -Recurse -Force
        Write-Done
    }

    if (Test-Path -Path $target_dir) {
        Write-Host "Removing target directory: " -NoNewline
        Remove-Item -Path $target_dir -Recurse -Force
        Write-Done
    }
}

function test_New-SecureDirectory_directory {
    # We're deleting anything we find, so the creation date should be different
    $before_time = (Get-Item -Path $test_directory).CreationTime
    New-SecureDirectory -Path $test_directory
    $after_time= (Get-Item -Path $test_directory).CreationTime
    if ($before_time -lt $after_time) { return 0 }
    return 1
}

function test_New-SecureDirectory_file {
    # If there's a file with the same name, rename it, and create the directory
    New-SecureDirectory -Path $test_file
    if ((Get-Item -Path $test_file) -is [System.IO.FileInfo]) { return 1 }
    return 0
}

function test_New-SecureDirectory_symlink_dir {
    # Should rename the symlink
    $failed = 0
    $before_time = (Get-Item -Path $test_symlink_dir).CreationTime
    New-SecureDirectory -Path $test_symlink_dir
    $after_time= (Get-Item -Path $test_symlink_dir).CreationTime
    if (!($before_time -lt $after_time)) { $failed = 1 }
    if (!(Test-Path -Path "$test_symlink_dir-$script_date.insecure")) { $failed = 1 }
    if (!(Get-IsReparsePoint -Path "$test_symlink_dir-$script_date.insecure")) { $failed = 1 }
    if ((Get-Item -Path "$test_symlink_dir-$script_date.insecure").LinkType -ne "SymbolicLink") { $failed = 1 }
    return $failed
}

function test_New-SecureDirectory_symlink_file {
    # Should rename the symlink
    $failed = 0
    $before_time = (Get-Item -Path $test_symlink_file).CreationTime
    New-SecureDirectory -Path $test_symlink_file
    $after_time= (Get-Item -Path $test_symlink_file).CreationTime
    if (!($before_time -lt $after_time)) { $failed = 1 }
    if (!(Test-Path -Path "$test_symlink_file-$script_date.insecure")) { $failed = 1 }
    if (!(Get-IsReparsePoint -Path "$test_symlink_file-$script_date.insecure")) { $failed = 1 }
    if ((Get-Item -Path "$test_symlink_file-$script_date.insecure").LinkType -ne "SymbolicLink") { $failed = 1 }
    return $failed
}

function test_New-SecureDirectory_junction {
    # Should rename the symlink
    $failed = 0
    $before_time = (Get-Item -Path $test_junction).CreationTime
    New-SecureDirectory -Path $test_junction
    $after_time= (Get-Item -Path $test_junction).CreationTime
    if (!($before_time -lt $after_time)) { $failed = 1 }
    if (!(Test-Path -Path "$test_junction-$script_date.insecure")) { $failed = 1 }
    if (!(Get-IsReparsePoint -Path "$test_junction-$script_date.insecure")) { $failed = 1 }
    if ((Get-Item -Path "$test_junction-$script_date.insecure").LinkType -ne "Junction") { $failed = 1 }
    return $failed
}

function test_New-SecureDirectory_hardlink {
    # Hardlinks get treated like files, just remove them
    New-SecureDirectory -Path $test_hardlink
    if ((Get-Item -Path $test_hardlink) -is [System.IO.FileInfo]) { return 1 }
    return 0
}

function test_New-SecureDirectory_insecure_owner {
    # Should rename the directory and keep owner
    $failed = 0
    $before_time = (Get-Item -Path $test_insecure_owner).CreationTime
    New-SecureDirectory -Path $test_insecure_owner
    $after_time= (Get-Item -Path $test_insecure_owner).CreationTime
    if (!($before_time -lt $after_time)) { $failed = 1 }
    if (!(Test-Path -Path "$test_insecure_owner-$script_date.insecure")) { $failed = 1 }
    # Make sure we didn't change the owner
    $file_acl = Get-Acl -Path "$test_insecure_owner-$script_date.insecure"
    if ($file_acl.Owner -ne "BUILTIN\Users") { $failed = 1 }
    return $failed
}

function test_New-SecureDirectory_not_empty {
    # Should wipe out the directory and create a new empty directory
    $failed = 0
    $before_time = (Get-Item -Path $test_not_empty).CreationTime
    New-SecureDirectory -Path $test_not_empty
    $after_time= (Get-Item -Path $test_not_empty).CreationTime
    if (!($before_time -lt $after_time)) { $failed = 1 }
    if((Get-ChildItem -Path $test_not_empty | Measure-Object).Count -ne 0) { $failed = 1 }
    return $failed
}
