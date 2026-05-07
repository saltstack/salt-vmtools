function invoke_script {
    param([String[]] $Arguments)
    & powershell.exe -File .\windows\svtminion.ps1 @Arguments *> $null
    return $LASTEXITCODE
}

function test_invalid_source_spaces_exits_126 {
    $exit_code = invoke_script @("-Install", "-Source", "https://bad url.com")
    if ($exit_code -ne 126) { return 1 }
    return 0
}

function test_invalid_source_semicolon_exits_126 {
    $exit_code = invoke_script @("-Install", "-Source", "https://evil.com/path;bad")
    if ($exit_code -ne 126) { return 1 }
    return 0
}

function test_invalid_source_bad_scheme_exits_126 {
    $exit_code = invoke_script @("-Install", "-Source", "notascheme://bad")
    if ($exit_code -ne 126) { return 1 }
    return 0
}

function test_invalid_minionversion_exits_126 {
    $exit_code = invoke_script @("-Install", "-MinionVersion", "bad version")
    if ($exit_code -ne 126) { return 1 }
    return 0
}

function test_invalid_minionversion_injection_exits_126 {
    $exit_code = invoke_script @("-Install", "-MinionVersion", "3006;evil")
    if ($exit_code -ne 126) { return 1 }
    return 0
}
