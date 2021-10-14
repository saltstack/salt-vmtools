# Copyright (c) 2021 VMware, Inc. All rights reserved.

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
