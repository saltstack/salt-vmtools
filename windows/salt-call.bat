:: Copyright (c) 2021 VMware, Inc. All rights reserved.

:: Script for starting the Salt-Minion
:: Accepts all parameters that Salt-Minion Accepts
@ echo off
net session >nul 2>&1
if %errorLevel%==0 (
    :: Define Variables
    Set SaltBin=%~dp0\salt\salt.exe

    :: Launch Script
    "%SaltBin%" call %*
) else (
    echo ***** This script must be run as Administrator *****
)
