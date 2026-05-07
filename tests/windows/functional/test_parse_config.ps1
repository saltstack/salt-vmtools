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

function test__parse_config_control_chars {
    # Entries containing control characters should be silently skipped; valid
    # entries in the same input must still be parsed correctly.
    $null_byte = [char]0x00
    $bad_key = "bad${null_byte}key=value"
    $bad_val = "key=bad${null_byte}value"
    $result = _parse_config -KeyValues "master=test $bad_key $bad_val id=minion"
    if ($result["master"] -ne "test") { return 1 }
    if ($result["id"] -ne "minion") { return 1 }
    if ($result.ContainsKey("bad${null_byte}key")) { return 1 }
    if ($result.ContainsKey("key")) { return 1 }
    return 0
}
