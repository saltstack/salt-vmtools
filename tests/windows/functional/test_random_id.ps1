# Copyright (c) 2021 VMware, Inc. All rights reserved.

function test_Get-RandomizedId_random_id {
    $random_id = Get-RandomizedMinionId
    if ($random_id -match "^minion_[\w\d]{5}$") { return 0 } else { return 1 }
}

function test_Get-RandomizedId_second_id {
    $random_id = Get-RandomizedMinionId
    $random_id_2 = Get-RandomizedMinionId
    if ($random_id -ne $random_id_2) { return 0 } else { return 1 }
}

function test_Get-RandomizedId_custom_prefix {
    $random_id = Get-RandomizedMinionId -Prefix spongebob
    if ($random_id -match "^spongebob_[\w\d]{5}$") { return 0 } else { return 1 }
}

function test_Get-RandomizedId_custom_length {
    $random_id = Get-RandomizedMinionId -Length 7
    if ($random_id -match "^minion_[\w\d]{7}$") { return 0 } else { return 1 }
}

function test_Get-RandomizedId_custom_length_and_prefix {
    $random_id = Get-RandomizedMinionId -Prefix spongebob -Length 7
    if ($random_id -match "^spongebob_[\w\d]{7}$") { return 0 } else { return 1 }
}
