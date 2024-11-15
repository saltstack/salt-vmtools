# Copyright 2021-2023 VMware, Inc.
# SPDX-License-Identifier: Apache-2

function setUpScript {

    Write-Host "Resetting environment: " -NoNewline
    Reset-Environment *> $null
    Write-Done

    Write-Host "Installing salt: " -NoNewline
    function Get-GuestVars { "master=gv_master id=gv_minion" }
    $MinionVersion = "3006.1"
    Install *> $null
    Write-Done

    Write-Host "Resetting the minion: " -NoNewline
    Reset-SaltMinion *> $null
    Write-Done

}

function tearDownScript {
    Write-Host "Resetting environment: " -NoNewline
    Reset-Environment *> $null
    Write-Done
}

function test_minion_id_removed{
    # Verify that minion_id file is removed
    if (Test-Path "$salt_config_dir\minion_id") { return 1 }
    return 0
}

function test_minion.d_removed{
    # Verify that minion.d directory is removed
    if (Test-Path "$salt_config_dir\minion.d") { return 1 }
    return 0
}

function test_config_correct {
    # Verify that the old minion id is commented out
    foreach ($line in Get-Content $salt_config_file) {
        if ($line -match "^#id: gv_minion$") { return 0 }
    }
    return 1
}

function test_new_random_minion_id {
    # Verify that a new randomized minion id is set
    foreach ($line in Get-Content $salt_config_file) {
        if ($line -match "^id: gv_minion_.{5}$") { return 0 }
    }
    return 1
}

function test_remove_minion_private_key {
    # Ensure minion private key is removed
    if (Test-Path "$salt_pki_dir\minion.pem") { return 1 }
    return 0
}

function test_remove_minion_public_key {
    # Ensure minion public key is removed
    if (Test-Path "$salt_pki_dir\minion.pub") { return 1 }
    return 0
}
