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

function test__parse_config_preserve_case{
    $result = _parse_config -KeyValues "signing_algorithm=PKCS1v15-SHA224 encryption_algorithm=OAEP-SHA224"
    if ($result["signing_algorithm"] -cne "PKCS1v15-SHA224") { return 1 }
    if ($result["encryption_algorithm"] -cne "OAEP-SHA224") { return 1 }
    return 0
}
