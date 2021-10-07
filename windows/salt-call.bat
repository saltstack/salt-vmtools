:: Copyright (c) 2021 VMware, Inc. All rights reserved.

:: Script for starting the Salt-Minion
:: Accepts all parameters that Salt-Minion Accepts
@ echo off

:: Define Variables
Set SaltBin=%~dp0\salt\salt.exe

net session >nul 2>&1
if %errorLevel%==0 (
    :: Launch Script
    "%SaltBin%" call %*
) else (
    echo ***** This script must be run as Administrator *****
)
