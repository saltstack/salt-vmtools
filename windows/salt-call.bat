:: Copyright (c) 2021 VMware, Inc. All rights reserved.
:: VMware Confidential

:: Script for starting the Salt-Minion
:: Accepts all parameters that Salt-Minion Accepts
@ echo off

:: Define Variables
Set SaltBin=%~dp0\salt\salt.exe

:: Launch Script
"%SaltBin%" call %*
