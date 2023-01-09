# Copyright 2021-2023 VMware, Inc.
# SPDX-License-Identifier: Apache-2

function test__parse_config_normal {
    $result = _parse_config -KeyValues "master=test id=test_min"
    if ($result["master"] -ne "test") { return 1 }
    if ($result["id"] -ne "test_min") { return 1 }
    return 0
}

function test__parse_config_extra_spaces {
    $result = _parse_config -KeyValues "  master=test     id=test_min   "
    if ($result["master"] -ne "test") { return 1 }
    if ($result["id"] -ne "test_min") { return 1 }
    return 0
}
