# Copyright (c) 2021 VMware, Inc. All rights reserved.
# VMware Confidential

# Salt VMware Tools Integration script for Windows
# for useage run this script with the -h option:
#    powershell -file svtminion.ps1 -h
param(
    [Parameter(Mandatory=$false)]
    [Alias("h")]
    [Switch] $Help,

    [Parameter(Mandatory=$false)]
    [ValidateSet("status", "add", "remove", "reset", "depend")]
    [Alias("a")]
    [String] $Action,

    [Parameter(Mandatory=$false)]
    [Alias("l")]
    [ValidateSet("error", "info", "warning", "debug", IgnoreCase=$true)]
    [String] $LogLevel = "error",

    [Parameter(Mandatory=$false)]
    [Alias("i")]
    [Switch] $Install,

    [Parameter(Mandatory=$false)]
    [Alias("v")]
    [String] $Version="3003.3-1",

    [Parameter(Mandatory=$false)]
    [Alias("s")]
    [Switch] $Status,

    [Parameter(Mandatory=$false)]
    [Alias("d")]
    [Switch] $Depend,

    [Parameter(Mandatory=$false)]
    [Alias("c")]
    [Switch] $Clear,

    [Parameter(Mandatory=$false)]
    [Alias("r")]
    [Switch] $Remove,

    # This paramater must be first or else you have to specify all the other
    # parameters explicitely on the cli
    [Parameter(Mandatory=$false,
               Position=0,
               ValueFromRemainingArguments=$true)]
    [String[]] $ConfigOptions
)


################################ REQUIREMENTS ##################################
# Make sure the script is run as Administrator
$Identity = [System.Security.Principal.WindowsIdentity]::GetCurrent()
$Principal = New-Object System.Security.Principal.WindowsPrincipal($Identity)
if (!($Principal.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator))) {
    throw "This script must run as Administrator"
}


################################# LOGGING ######################################
$LOG_LEVELS = @{"error" = 0; "info" = 1; "warning" = 2; "debug" = 3}
$log_level_value = $LOG_LEVELS[$LogLevel.ToLower()]

################################# SETTINGS #####################################
$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"
$download_retry_count = 5
$current_date = Get-Date -Format "yyyy-MM-dd"
$script_name = $myInvocation.MyCommand.Name
$script_log_dir = "$env:ProgramData\VMware\logs"

################################# VARIABLES ####################################
# Repository locations and names
$salt_name = "salt"
#TODO: Set this back to valid version
$salt_version = $Version
$base_url = "https://repo.saltproject.io/salt/vmware-tools-onedir"
$salt_web_file_name = "$salt_name-$salt_version-windows-amd64.zip"
$salt_web_file_url = "$base_url/$salt_version/$salt_web_file_name"
$salt_hash_name = "$salt_name-$salt_version" + "_SHA512"
$salt_hash_url = "$base_url/$salt_version/$salt_hash_name"

# Salt file and directory locations
$base_salt_install_location = "$env:ProgramFiles\Salt Project"
$salt_dir = "$base_salt_install_location\$salt_name"
$salt_bin = "$salt_dir/salt/salt.exe"
$ssm_bin = "$salt_dir/ssm.exe"

$base_salt_config_location = "$env:ProgramData\Salt Project"
$salt_config_dir = "$base_salt_config_location\$salt_name\conf"
$salt_config_name = "minion"
$salt_config_file = "$salt_config_dir/$salt_config_name"
$salt_pki_dir = "$salt_config_dir/pki/$salt_config_name"

# Files/Dirs to remove
$file_dirs_to_remove = [System.Collections.ArrayList]::new()
$file_dirs_to_remove.Add($base_salt_config_location) | Out-Null
$file_dirs_to_remove.Add($base_salt_install_location) | Out-Null

## VMware registry locations
$vmtools_base_reg = "HKLM:\SOFTWARE\VMware, Inc.\VMware Tools"
$vmtools_salt_minion_status_name = "SaltMinionStatus"

$Error.Clear()
try{
    $reg_key = Get-ItemProperty $vmtools_base_reg
} catch {
    Write-Host "Unable to find valid VMtools installation : $Error" -ForeGroundColor Red
    exit 1
}
if (!($reg_key.PSObject.Properties.Name -contains "InstallPath")) {
    Write-Host "Unable to find valid VMtools installation" -ForeGroundColor Red
    exit 1
}

## VMware file and directory locations
$vmtools_base_dir = Get-ItemPropertyValue -Path $vmtools_base_reg -Name "InstallPath"
$vmtools_conf_dir = "$env:ProgramData\VMware\VMware Tools"
$vmtools_conf_file = "$vmtools_conf_dir\tools.conf"
$vmtoolsd_bin = "$vmtools_base_dir\vmtoolsd.exe"

# Files required by this script
$salt_dep_files = @{}
$salt_dep_files["vmtoolsd.exe"] = $vmtools_base_dir
$salt_dep_files["salt-call.bat"] = $PSScriptRoot
$salt_dep_files["salt-minion.bat"] = $PSScriptRoot

## VMware guestVars file and directory locations
$guestvars_base = "guestinfo.vmware.components"
$guestvars_section = "salt_minion"
$guestvars_salt = "$guestvars_base.$guestvars_section"
$guestvars_salt_args = "$guestvars_salt.args"

$STATUS_CODES = @{
    "installed" = 0;
    "installing" = 1;
    "notInstalled" = 2;
    "installFailed" = 3;
    "removing" = 4;
    "removeFailed" = 5;
    0 = "installed";
    1 = "installing";
    2 = "notInstalled";
    3 = "installFailed"
    4 = "removing";
    5 = "removeFailed";
}


############################### HELPER FUNCTIONS ###############################


function Write-Log {
    # Functions for writing logs to the screen and to the log file
    #
    # Args:
    #     Message (string): The log message
    #     Level (string):
    #         The log level. Must be one of error, info, warning, debug. Default
    #         is info
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true, Position=0)]
        [String] $Message,

        [Parameter()]
        [ValidateSet("error", "info", "warning", "debug", IgnoreCase=$true)]
        [String] $Level = "info"
    )

    $Level = $Level.ToUpper()
    $level_text = $Level + " " * (7 - $Level.Length)

    if ( $LOG_LEVELS[$Level.ToLower()] -le $log_level_value ) {
        $date_time = Get-Date -Format "yyyy-MM-dd:HH:mm:ss.ffff"
        $log_message = "[$date_time] [$level_text] $Message"
        $log_file_message = "[$date_time] [$PID] [$level_text] $Message"
        if (!(Test-Path($script_log_dir))) {
            Write-Host "[$date_time] [INFO   ] : Creating log file directory"
            New-Item -Path $script_log_dir -ItemType Directory | Out-Null
        }
        Add-Content "$script_log_dir\$script_name-$current_date.log" $log_file_message
        switch ($Level) {
            "ERROR" { $color = "Red" }
            "WARNING" { $color = "Yellow" }
            default { $color = "White"}
        }
        Write-Host $log_message -ForegroundColor $color
    }
}


function Get-ScriptRunningStatus ([ref]$data){
    # Try to detect if a this script is already running
    #
    # Sets the $script_running_status variable to True if running, otherwise False

    #Get all running powershell processes
    # $PsScriptsRunning = get-wmiobject win32_process | where{$_.processname -eq 'powershell.exe'} | select-object commandline,ProcessId
    $processes = Get-WmiObject Win32_Process -Filter "Name='powershell.exe' AND CommandLine LIKE '%$script_name%'" | Select-Object CommandLine,ProcessId

    $process_found = $false
    foreach ($process in $processes){
        [Int32]$process_pid = $process.ProcessId
        [String]$process_cmd = $process.commandline
        #Are other instances of this script already running?
        if (($process_cmd -match $script_name) -And ($process_pid -ne $PID)) {
            $process_found = $true
        }
    }
    if ($process_found) {
        Write-Log "Found running instance in PID: $process_pid" -Level debug
        $data.Value = $true
    } else {
        Write-Log "Running instance not detected" -Level debug
        $data.Value = $false
    }
}


function Get-Status {
    # Read the status out of the registry
    # If the key is missing that means notInstalled
    # Returns the error level number
    $script_running_status = $null
    Get-ScriptRunningStatus ([ref]$script_running_status)

    Write-Log "Getting status from $vmtools_base_reg\$vmtools_salt_minion_status_name" -Level debug
    $Error.Clear()
    try {
        $current_status = Get-ItemPropertyValue -Path $vmtools_base_reg -Name $vmtools_salt_minion_status_name
        Write-Log "Found status code: $current_status" -Level debug
    } catch {
        Write-Log "Key not set, not installed : $Error" -Level debug
        return 2
    }

    # If status is 1 or 4 (installing or removing) but there isn't another script
    # running, then the status is installFailed or removeFailed
    Write-Log "Checking for failed install or remove operation" -Level debug
    if ((1, 4 -contains $current_status) -and !($script_running_status)) {
        switch ($current_status) {
            1 {
                Write-Log "Found failed install" -Level debug
                $current_status = 3
            }
            4 {
                Write-Log "Found failed remove" -Level debug
                $current_status = 5
            }
        }
    }

    $Error.Clear()
    try {
        $status_lookup = $STATUS_CODES[$current_status]
        Write-Log "Found status: $status_lookup" -Level info
        return $current_status
    } catch {
        Write-Log "Unknown status found: $current_status : $Error" -Level error
        exit 1
    }
}


function Set-Status {
    # Set the numeric value of the status in the registry
    # notInstalled means to remove the key
    #
    # Args:
    #     NewStatus (string):
    #         The status to set. Must be one of the following:
    #             - installed
    #             - installing
    #             - notInstalled
    #             - installFailed
    #             - removing
    #             - removeFailed
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [ValidateSet("installed", "installing", "notInstalled", "installFailed", "removing", "removeFailed")]
        [String] $NewStatus
    )

    $status_code = $STATUS_CODES[$NewStatus]
    Write-Log "Setting status to $NewStatus" -Level debug
    # If it's notInstalled, just remove the propery name
    if ($status_code -eq 2) {
        $Error.Clear()
        try{
            Remove-ItemProperty -Path $vmtools_base_reg -Name $vmtools_salt_minion_status_name
            Write-Log "Removed reg key: $vmtools_base_reg\$vmtools_salt_minion_status_name" -Level debug
            Write-Log "Set status to $NewStatus" -Level debug
        } catch {
            Write-Log "Error removing reg key: $Error" -Level error
            exit 1
        }
    } else {
        $Error.Clear()
        try {
            New-ItemProperty -Path $vmtools_base_reg -Name $vmtools_salt_minion_status_name -Value $status_code -Force | Out-Null
            Write-Log "Set status to $NewStatus" -Level debug
        } catch {
            Write-Log "Error writing status: $Error" -Level error
            exit 1
        }
    }
}


function Set-FailedStatus {
    switch ($Action.ToLower()) {
        "add" { Set-Status installFailed }
        "remove" { Set-Status removeFailed }
    }
}


function Get-WebFile{
    # Downloads a file from the web. Enables the TLS1.2 protocol. If the
    # download times out, wait 10 seconds and try again. Continues retrying
    # until the download retry count max is reached
    #
    # Used by:
    # - Get-SaltFromWeb
    #
    # Args:
    #     Url (string): The url for the file to download
    #     OutFile (string): The location to put the downloaded file
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [String] $Url,

        [Parameter(Mandatory=$true)]
        [String] $OutFile
    )
    [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]'Tls,Tls11,Tls12'
    $url_name = $Url.SubString($Url.LastIndexOf('/'))

    $tries = 1
    $success = $false
    do {
        $Error.Clear()
        try {
            # Download the file
            Write-Log "Downloading (try: $tries/$download_retry_count): $url_name" -Level debug
            Invoke-WebRequest -Uri $Url -OutFile $OutFile
        } catch {
            Write-Log "Error downloading: $Url" -Level warning
            Write-Log "Error message: $Error" -Level warning
        } finally {
            if ((Test-Path -Path "$OutFile") -and ((Get-Item "$OutFile").Length -gt 0kb)) {
                Write-Log "Finished downloading: $url_name" -Level debug
                $success = $true
            } else {
                $tries++
                if ($tries -gt $download_retry_count) {
                    Write-Log "Retry count exceeded" -Level error
                    Set-FailedStatus
                    exit 1
                }
                Write-Log "Trying again after 10 seconds" -Level warning
                Start-Sleep -Seconds 10
            }
        }
    } while (!($success))
}


function Get-HashFromFile {
    # Gets the hash for the file from the hash file which contains a list of
    # hashes and their files
    #
    # Used by:
    # - Get-SaltFromWeb
    #
    # Args:
    #     HashFile (string): The file containing the hashes
    #     FileName (string): The name of the file to search for in the hash file
    #
    # Returns:
    #     Returns the hash for the specified file
    # Errors:
    #     If there is an error, set the failed status and exit with an error
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [String] $HashFile,

        [Parameter(Mandatory=$true)]
        [String] $FileName
    )
    Write-Log "Loading hashfile: $HashFile" -Level debug
    $lines = Get-Content -Path $HashFile
    Write-Log "Searching for hash for: $FileName" -Level debug
    foreach ($lines in $lines) {
        $file_hash, $file_name = $lines -split "\s+"
        if ($FileName -eq $file_name) {
            Write-Log "Found hash: $file_hash" -Level debug
            return $file_hash
        }
    }
    Write-Log "No hash found for: $FileName" -Level error
    Set-FailedStatus
    exit 1
}


function Expand-ZipFile {
    # Extract a zip file
    #
    # Used by:
    # - Install-SaltMinion
    #
    # Args:
    #     ZipFile (string): The file to extract
    #     Destination (string): The location to extract to
    #
    # Error:
    #     Sets the failed status and exits with an error
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string] $ZipFile,

        [Parameter(Mandatory = $true)]
        [string] $Destination
    )

    if (!(Test-Path -Path $Destination)) {
        Write-Log "Creating missing directory: $Destination" -Level debug
        New-Item -ItemType directory -Path $Destination
    }
    Write-Log "Unzipping '$ZipFile' to '$Destination'" -Level debug
    $objShell = New-Object -Com Shell.Application
    $objZip = $objShell.NameSpace($ZipFile)
    $Error.Clear()
    try{
        foreach ($item in $objZip.Items()) {
            $objShell.Namespace($Destination).CopyHere($item, 0x14)
        }
    } catch {
        Write-Log "Failed to unzip $ZipFile : $Error" -Level error
        Set-FailedStatus
        exit 1
    }
    Write-Log "Finished unzipping '$ZipFile' to '$Destination'" -Level debug
}


function Add-SystemPathValue{
    # Add a new entry to the system path environment variable. Only adds the new
    # path if it does not already exist.
    #
    # Used by:
    # - Install-SaltMinion
    #
    # Args:
    #     Path (string): The target path to add
    #
    # Warning:
    #     Logs a warning if the target path does not exist
    #
    # Error:
    #     Sets the failed status and exits with an error
    [Cmdletbinding()]
    param (
        [parameter(Mandatory=$True)]
        [String]$Path
    )

    $path_reg_key = "HKLM:\System\CurrentControlSet\Control\Session Manager\Environment"

    # Make sure the target folder exists
    if (!(Test-Path $Path)) {
        Write-Log "Target path does not exist: $Path" -Level warning
    }

    Write-Log "Getting current path" -Level debug
    $current_path = (Get-ItemProperty -Path $path_reg_key -Name Path).Path
    $new_path_list = [System.Collections.ArrayList]::new()

    Write-Log "Verifying the path is not present" -Level debug
    foreach ($item in $current_path.Split(";")) {
        $regex_path = $Path.Replace("\", "\\")
        # Bail if we find the new path in the current path
        if ($item -imatch "^$regex_path(\\)?$") {
            Write-Log "Target path already exists: $Path" -Level warning
            return
        } else {
            # Add the item to our new path array
            $new_path_list.Add($item) | Out-Null
        }
    }

    # Add the new path to the array
    Write-Log "Adding path: $Path" -Level debug
    $new_path_list.Add($Path) | Out-Null

    $new_path = $new_path_list -join ";"
    $Error.Clear()
    try{
        Write-Log "Updating system path and env path" -Level debug
        Set-ItemProperty -Path $path_reg_key -Name Path -Value $new_path
    } catch {
        Write-Log "Failed to add $Path the system path" -Level error
        Write-Log "Tried to write: $new_path" -Level error
        Write-Log "Error message: $Error" -Level error
        Set-FailedStatus
        exit 1
    }
}


function Remove-SystemPathValue {
    # Removes the specified target path from the system path environment variable
    #
    # Used by:
    # - Remove-SaltMinion
    #
    # Args
    #     Path (string): The target path to remove
    #
    # Error:
    #     Set failed status and exit with error code
    [Cmdletbinding()]
    param (
        [parameter(Mandatory=$True)]
        [String]$Path
    )

    $path_reg_key = "HKLM:\System\CurrentControlSet\Control\Session Manager\Environment"

    Write-Log "Getting current path" -Level debug
    $current_path = (Get-ItemProperty -Path $path_reg_key -Name Path).Path
    $new_path_list = [System.Collections.ArrayList]::new()

    Write-Log "Searching for $Path in the path" -Level debug
    foreach ($item in $current_path.Split(";")) {
        $regex_path = $Path.Replace("\", "\\")
        # Bail if we find the new path in the current path
        if ($item -imatch "^$regex_path(\\)?$") {
            Write-Log "Removing $Path from the path" -Level debug
        } else {
            # Add the item to our new path array
            $new_path_list.Add($item) | Out-Null
        }
    }

    Write-Log "Updating system path" -Level debug
    $new_path = $new_path_list -join ";"
    $Error.Clear()
    try {
        Set-ItemProperty -Path $path_reg_key -Name Path -Value $new_path
    } catch {
        Write-Log "Failed to remove $Path from the system path: $new_path" -Level error
        Write-Log "Tried to write: $new_path" -Level error
        Write-Log "Error message: $Error" -level error
        Set-FailedStatus
        exit 1
    }
}


function Remove-FileOrFolder {
    # Removes a file or a folder recursively from the system
    #
    # Used by:
    # - Remove-SaltMinion
    # - Reset-SaltMinion
    #
    # Args:
    #     Path (string): The file or folder to remove
    #
    # Error:
    #     Sets failed status and exits with error code 1
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [String] $Path
    )
    if (Test-Path -Path "$Path") {
        $Error.Clear()
        try {
            Write-Log "Removing $Path" -Level debug
            Remove-Item -Path $Path -Force -Recurse
            if (Test-Path -Path "$Path") {
                Write-Log "Failed to remove $Path" -Level error
                Set-FailedStatus
                exit 1
            } else {
                Write-Log "Finished removing $Path" -Level debug
            }
        } catch {
            Write-Log "Failed to remove $Path : $Error" -Level error
            Set-FailedStatus
            exit 1
        }
    } else {
        Write-Log "Path not found: $Path" -Level warning
    }
}


function Get-GuestVars {
    # Get guestvars data using vmtoolsd.exe
    # They can be set on the host using vmrun.exe
    # vmrun writeVariable "d:\VMWare\Windows Server 2019\Windows Server 2019.vmx" guestVar vmware./components.salt_minion.args "master=192.168.0.12 id=test_id"
    #
    # Used by:
    # - Get-ConfigGuestVars
    #
    # Args:
    #     GuestVarsPath (string):
    #         The option to get from the guestvars repository. Likely one of the
    #         following:
    #         - guestinfo.vmware.components.salt_minion : The action for this script
    #         - guestinfo.vmware.components.salt_minion.args : Minion config options
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [String] $GuestVarsPath
    )

    $arguments = "--cmd `"info-get $GuestVarsPath`""

    Write-Log "Getting value for $GuestVarsPath" -Level debug
    $ProcessInfo = New-Object System.Diagnostics.ProcessStartInfo
    Write-Log "Running $vmtoolsd_bin $arguments" -Level debug
    $ProcessInfo.FileName = $vmtoolsd_bin
    $ProcessInfo.Arguments = $arguments
    $ProcessInfo.RedirectStandardError = $true
    $ProcessInfo.RedirectStandardOutput = $true
    $ProcessInfo.UseShellExecute = $false
    $Process = New-Object System.Diagnostics.Process
    $Process.StartInfo = $ProcessInfo
    $Process.Start() | Out-Null
    $Process.WaitForExit()
    $stdout = $Process.StandardOutput.ReadToEnd()
    $stderr = $Process.StandardError.ReadToEnd()
    $exitcode = $Process.ExitCode

    if (($exitcode -eq 0) -and !($stdout.Trim() -eq "")) {
        Write-Log "Value found for $GuestVarsPath : '$stdout'" -Level debug
        return $stdout.Trim()
    } else {
        $msg = "No value found for $GuestVarsPath : $stderr"
        Write-Log $msg -Level debug
    }
}


function _parse_config {
    # Parse config options that are in the format key=value
    # These can be passed on the cli, guestvars, or tools.conf
    #
    # Used by:
    # - Get-ConfigCLI
    # - Get-ConfigGuestVars
    # - Get-ConfigToolsConf
    #
    # Args:
    #     KeyValues (string[])
    #         A list of string values in the key=value format
    #
    # Returns:
    #     A hash table containing the config options and their values
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [String[]] $KeyValues
    )

    $count = $KeyValues.Count
    Write-Log "Found $count config options" -Level debug
    $config_options = @{}
    foreach ($key_value in $KeyValues) {
        if ($key_value -like "*=*") {
            Write-Log "Found config: $key_value" -Level debug
            $key, $value = $key_value -split "="
            if ($value) {
                $config_options[$key.ToLower()] = $value.ToLower()
            } else {
                Write-Log "No config value specified: $key_value" -Level warning
            }
        } else {
            Write-Log "Invalid config format ignored: $key_value" -Level warning
        }
    }
    return $config_options
}


function Get-ConfigCLI ([ref]$data){
    # Get salt-minion configuration options from arguments passed on the
    # command line. These key/value pairs are already in the ConfigOptions
    # variable populated by the powershell cli parser. They should be a space
    # delimited list of options in the key=value format.
    #
    # Used by:
    # - Get-MinionConfig
    if ($ConfigOptions) {
        Write-Log "Loading CLI config options" -Level debug
        $data.Value = _parse_config -KeyValues $ConfigOptions
    } else {
        Write-Log "Minion config not passed on CLI" -Level warning
    }
}


function Get-ConfigGuestVars ([ref]$data) {
    # Get salt-minion configuration options defined in the guestvars. That
    # should be a space delimited list of options in the key=value format.
    #
    # Used by:
    # - Get-MinionConfig
    $config_options = Get-GuestVars -GuestVarsPath $guestvars_salt_args
    if ($config_options) {
        Write-Log "Loading GuestVars config options" -Level debug
        $config_options = $config_options.Split()
        $data.Value = _parse_config $config_options
    } else {
        Write-Log "Minion config not defined in guestvars" -Level warning
    }
}


function Read-IniContent {
    # Create a hash table with values from an ini file. Each section will
    # contain a sub hash table with key/value pairs
    #
    # Used by:
    # - Get-ConfigToolsConf
    #
    # Args:
    #     FilePath (string): The location of the ini file to read
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [String] $FilePath
    )

    if (!(Test-Path -Path $FilePath)) {
        Write-Log "File not found: $FilePath" -Level warning
        return
    }

    $ini = New-Object System.Collections.Specialized.OrderedDictionary([System.StringComparer]::OrdinalIgnoreCase)

    switch -regex -file $FilePath {
        # [Section]
        "^(?![#,;])\[(.+)\]$" {
            $section = $matches[1]
            $ini[$section] = @{}
        }
        # key=value
        "^(?![#,;])(.+?)\s*=(.*)$" {
            $key,$value = $matches[1..2]
            $ini[$section][$key] = $value
        }
    }
    return $ini
}


function Get-ConfigToolsConf ([ref]$data){
    # Get config from tools.conf
    # Return hashtable
    #
    # Used by:
    # - Get-MinionConfig
    $config_values = Read-IniContent -FilePath $vmtools_conf_file | Out-Null
    if ($config_options) {
        Write-Log "Loading tools.conf config options" -Level debug
        $data.Value = _parse_config $config_options[$guestvars_section]
    } else {
        Write-Log "Minion config not defined in tools.conf" -Level warning
    }
}


function Get-MinionConfig ([ref]$config_options){
    # Get the minion config values to be place in the minion config file. The
    # Order of priority is as follows:
    # - Get config from the CLI (options passed to the script)
    # - Get config from GuestVars (defined by VMtools)
    # - Get config from tools.conf (older method)
    # - Use salt minion defaults (master: salt, id: hostname)
    #
    # Used by:
    # - Add-MinionConfig
    Get-ConfigCLI -data $config_options
    if ($config_options) {
        Write-Log "Found minion config on the CLI" -Level debug
        return
    }
    Get-ConfigGuestVars -data $config_options
    if ($config_options) {
        Write-Log "Found minion config in GuestVars" -Level debug
        return
    }
    Get-ConfigToolsConf -data $config_options
    if ($config_options) {
        Write-Log "Found minion config in tools.conf" -Level debug
        return
    }
}


function Add-MinionConfig {
    # Write minion config options to the minion config file

    # Make sure the config directory exists
    if (!(Test-Path($salt_config_dir))) {
        Write-Log "Creating config directory: $salt_config_dir" -Level debug
        New-Item -Path $salt_config_dir -ItemType Directory | Out-Null
    }
    # Get the minion config
    $config_options = $null
    Get-MinionConfig ([ref]$config_options)

    if ($config_options) {
        $new_content = [System.Collections.ArrayList]::new()
        foreach ($key in $config_options.keys) {
            $new_content.Add("$($key): $($config_options[$key])") | Out-Null
        }
        $config_content = $new_content -join "`n"
        $Error.Clear()
        try {
            Write-Log "Writing minion config" -Level debug
            Set-Content -Path $salt_config_file -Value $config_content
            Write-Log "Finished writing minion config" -Level debug
        } catch {
            Write-Log "Failed to write minion config: $config_content : $Error" -Level error
            Set-FailedStatus
            exit 1
        }
    } else {
        Write-Log "No minion config found. Defaults will be used" -Level warning
    }
}


function Start-MinionService {
    # Start the minion service
    Write-Log "Starting the salt-minion service" -Level info
    Start-Service -Name salt-minion | Out-Null

    Write-Log "Checking the status of the salt-minion service" -Level debug
    if ((Get-Service -Name salt-minion).Status -eq "Running") {
        Write-Log "Service started successfully" -Level debug
    } else {
        Write-Log "Failed to start the salt-minion service" -Level error
        Set-FailedStatus
        exit 1
    }
}


function Stop-MinionService {
    # Stop the salt-minion service

    Write-Log "Stopping the salt-minion service" -Level info
    Stop-Service -Name salt-minion | Out-Null

    Write-Log "Checking the status of the salt-minion service" -Level debug
    if ((Get-Service -Name salt-minion).Status -eq "Stopped") {
        Write-Log "Service stopped successfully" -Level debug
    } else {
        Write-Log "Failed to stop the salt-minion service" -Level error
        Set-FailedStatus
        exit 1
    }
}


############################### MAIN FUNCTIONS #################################


function Show-Usage {
    # Display the usage text
    $whitespace = " " * "usage: $script_name".Length
    Write-Output ""
    Write-Output "Salt VMware Tools Integration Script for Windows"
    Write-Output ""
    Write-Output "usage: $script_name [-h|-help] [-a|-action <value>] [-l|-loglevel <value>]"
    Write-Output "$whitespace [-<config_key> <config_value>...]"
    Write-Output ""
    Write-Output "  -h, -Help   Display this help message"
    Write-Output ""
    Write-Output "  -a, -Action [Depend|Add|Remove|Reset|Status]"
    Write-Output "              Set the action this script is to perform. Valid"
    Write-Output "              options are as follows:"
    Write-Output "              - Depend: Ensure required dependencies are available"
    Write-Output "              - Add: Install and start the salt-minion service"
    Write-Output "              - Remove: Stop and uninstall the salt-minion service"
    Write-Output "              - Reset: Reset the salt config and keys"
    Write-Output "              - Status: Return the status for this script"
    Write-Output ""
    Write-Output "  -l, -LogLevel [Error|Info|Warning|Debug]"
    Write-Output "              Set the log level for the script. Default is Error"
    Write-Output ""
    Write-Output "  [ConfigOptionName]=[ConfigOptionValue]"
    Write-Output "              Any number of minion config options specified"
    Write-Output "              by the name of the config option as found in"
    Write-Output "              salt docs and its value. All options will be"
    Write-Output "              lower-cased and written to the minion config as"
    Write-Output "              passed. Only applies when the Action is install"
    Write-Output ""
    Write-Output "              eg: Master=192.168.0.10 Minion_Id=dev11"
    Write-Output ""
    Write-Output "  salt-minion vmtools integration script"
    Write-Output ""
    Write-Output "      example: $script_name -Status -LogLevel Debug"
    Write-Output ""
    Write-Output "      example: $script_name -Action Add Master=192.168.0.10 Minion_Id=test_box"
    Write-Output ""
    Write-Output $args
}


function Confirm-Dependencies {
    # Check that the required binaries for this script are present on the system
    #
    # Error:
    #     Exitcode 1 if missing dependencies
    Write-Log "Checking dependencies" -Level info

    # Check for VMware registry location for storing status
    Write-Log "Looking for: $vmtools_base_reg" -Level debug
    if(!(Test-Path("$vmtools_base_reg"))) {
        Write-Log "Unable to find $vmtools_base_reg" -Level error
        exit 1
    }

    # InstallPath reg key
    Write-Log "Looking for valid VMtools installation" -Level debug
    $reg_key = Get-ItemProperty $vmtools_base_reg
    if (!($reg_key.PSObject.Properties.Name -contains "InstallPath")) {
        Write-Log "Unable to find valid VMtools installation" -Level error
        exit 1
    }

    # VMtools files
    foreach ($file in $salt_dep_files.Keys) {
        Write-Log "Looking for: $file in $($salt_dep_files[$file])" -Level debug
        if(!(Test-Path("$($salt_dep_files[$file])\$file"))) {
            Write-Log "Unable to find $file in $($salt_dep_files[$file])" -Level error
            exit 1
        }
    }

    Write-Log "All dependencies found" -Level debug
}


function Get-SaltFromWeb {
    # Download the salt tiamat zip file from the web and verify the hash
    #
    # Error:
    #     Set the status and exit with an error

    Write-Log "Downloading salt from the web" -Level info

    # Make sure the download directory exists
    if ( !( Test-Path -Path $base_salt_install_location) ) {
        Write-Log "Creating directory: $base_salt_install_location" -Level debug
        New-Item -Path $base_salt_install_location -ItemType Directory | Out-Null
    }

    # Download the hash file
    $hash_file = "$base_salt_install_location\$salt_hash_name"
    Get-WebFile -Url $salt_hash_url -OutFile $hash_file

    # Download the salt file
    $salt_file = "$base_salt_install_location\$salt_web_file_name"
    Get-WebFile -Url $salt_web_file_url -OutFile $salt_file

    # Get the hash for the salt file
    $file_hash = (Get-FileHash -Path $salt_file -Algorithm SHA512).Hash
    $expected_hash = Get-HashFromFile -HashFile $hash_file -FileName $salt_web_file_name

    Write-Log "Verifying hash" -Level info
    if ($file_hash -like $expected_hash) {
        Write-Log "Hash verified" -Level debug
    } else {
        Write-Log "Failed to verify hash:" -Level error
        Write-Log "  - $file_hash" -Level error
        Write-Log "  - $expected_hash" -Level error
        Set-FailedStatus
        exit 1
    }
}


function Install-SaltMinion {
    # Installs the tiamat build of the salt minion. Performs the following:
    # - Expands the zipfile into C:\Program Files\Salt Project
    # - Copies the helper scripts into C:\ProgramFiles\Salt Project\Salt
    # - Registers the salt-minion service
    # - Adds the new location to the system path
    #
    # Error:
    #     Sets the failed status and exits with an error code

    # 1. Unzip into Program Files
    Write-Log "Unzipping salt (this may take a few minutes)" -Level info
    Expand-ZipFile -ZipFile "$base_salt_install_location\$salt_web_file_name" -Destination $base_salt_install_location

    # 2. Copy the scripts into Program Files
    Write-Log "Copying scripts" -Level info
    try {
        Write-Log "Copying $PSScriptRoot\salt-call.bat"
        Copy-Item -Path "$PSScriptRoot\salt-call.bat" -Destination "$salt_dir"
    } catch {
        Write-Log "Failed copying $PSScriptRoot\salt-call.bat" -Level error
        Set-FailedStatus
        exit 1
    }
    try {
        Write-Log "Copying $PSScriptRoot\salt-minion.bat"
        Copy-Item -Path "$PSScriptRoot\salt-minion.bat" -Destination "$salt_dir"
    } catch {
        Write-Log "Failed copying $PSScriptRoot\salt-minion.bat" -Level error
        Set-FailedStatus
        exit 1
    }

    # 3. Register the service
    Write-Log "Installing salt-minion service" -Level info
    $arguments = "install salt-minion `"$salt_bin`" minion -c `"$salt_config_dir`""
    Start-Process "$ssm_bin" -ArgumentList $arguments -Wait -NoNewWindow | Out-Null
    $arguments = "set salt-minion Description Salt Minion from VMtools"
    Start-Process "$ssm_bin" -ArgumentList $arguments -Wait -NoNewWindow | Out-Null
    $arguments = "set salt-minion Start SERVICE_AUTO_START"
    Start-Process "$ssm_bin" -ArgumentList $arguments -Wait -NoNewWindow | Out-Null
    $arguments = "set salt-minion AppStopMethodConsole 24000"
    Start-Process "$ssm_bin" -ArgumentList $arguments -Wait -NoNewWindow | Out-Null
    $arguments = "set salt-minion AppStopMethodWindow 2000"
    Start-Process "$ssm_bin" -ArgumentList $arguments -Wait -NoNewWindow | Out-Null
    $arguments = "set salt-minion AppRestartDelay 60000"
    Start-Process "$ssm_bin" -ArgumentList $arguments -Wait -NoNewWindow | Out-Null
    if (!(Get-Service salt-minion -ErrorAction SilentlyContinue).Status) {
        Write-Log "Failed to install salt-minion service" -Level error
        Set-FailedStatus
        exit 1
    } else {
        Write-Log "Finished installing salt-minion service" -Level debug
    }

    # TODO: Add the registry entries (salt 3004)

    # 4. Modify the system path
    Write-Log "Adding salt to the path" -Level info
    Add-SystemPathValue -Path $salt_dir
}


function Remove-SaltMinion {
    # Uninstall the salt minion. Performs the following steps:
    # - Stop the salt-minion service
    # - Remove the salt-minion service
    # - Remove the directories in Program Files and ProgramData
    # - Remove the registry entries
    # - Remove the entry from the system path
    #
    # Error:
    #     Sets the failed status and exits with error code 1

    # Does the service exist
    $service = Get-Service -Name salt-minion -ErrorAction SilentlyContinue

    if ($service -eq $null) {
        Write-Log "salt-minion service not found" -Level warning
    } else {

        # Stop the minion service
        Stop-MinionService

        # Delete the service
        Write-Log "Uninstalling salt-minion service" -Level debug
        $arguments = "delete salt-minion"
        Start-Process sc -ArgumentList $arguments -Wait -NoNewWindow | Out-Null
        if ((Get-Service salt-minion -ErrorAction SilentlyContinue).Status) {
            Write-Log "Failed to uninstall salt-minion service" -Level error
            Set-FailedStatus
            exit 1
        } else {
            Write-Log "Finished uninstalling salt-minion service" -Level debug
        }
    }

    # 3. Remove the files
    # Do this in a for loop for logging
    foreach ($item in $file_dirs_to_remove) {
        Remove-FileOrFolder -Path $item
    }

    # TODO: Remove the registry entries (salt 3004)

    # 4. Remove entry from the path
    Remove-SystemPathValue -Path $salt_dir
}


function Reset-SaltMinion {
    # Resets the salt-minion environment in preperation for imaging. Performs
    # the following steps:
    # - Remove minion_id file
    # - Comment out the minion id in the minion config
    # - Removes the minion public and private keys

    Remove-FileOrFolder "$salt_config_file\minion_id"

    # Comment out id: in the minion config
    $new_content = [System.Collections.ArrayList]::new()
    if (Test-Path -Path "$salt_config_file") {
        Write-Log "Searching minion config file for id" -Level debug
        foreach ($line in Get-Content $salt_config_file) {
            if ($line -match "^id:.*$") {
                Write-Log "Commenting out the id" -Level debug
                $new_content.Add("#" + $line) | Out-Null
            } else {
                $new_content.Add($line) | Out-Null
            }
        }
        $config_content = $new_content -join "`n"
        Write-Log "Writing new minion config"
        $Error.Clear()
        try {
            Set-Content -Path $salt_config_file -Value $config_content
        } catch {
            Write-Log "Failed to write new minion config : $Error" -Level error
            exit 1
        }
    }

    # Remove minion keys (minion.pem and minion.pub"
    Remove-FileOrFolder -Path "$salt_pki_dir\minion.pem"
    Remove-FileOrFolder -Path "$salt_pki_dir\minion.pub"
}


################################### MAIN #######################################

# Check for help switch
if ($help) {
    Show-Usage
    exit 0
}

# Check for Action. If not specified on the command line, get it from guestVars
if ($Action) {
    Write-Log "Action from CLI: $Action" -Level debug
} else {
    if ($Install) { $Action = "add" }
    if ($Status) { $Action = "status" }
    if ($Depend) { $Action = "depend" }
    if ($Clear) { $Action = "reset" }
    if ($Remove) { $Action = "remove" }
    if (!($Action)) {
        $Action = Get-GuestVars -GuestVarsPath $guestvars_salt
        Write-Log "Action from GuestVars: $Action" -Level debug
    }
}
if ($Action) {
    switch ($Action.ToLower()) {
        "depend" {
            Confirm-Dependencies
        }
        "add" {
            # If status is installed(0), installing(1), or removing(4), bail out
            $current_status = Get-Status
            if (0, 1, 4 -contains $current_status) {
                Write-Log "Installation will not continue"
                exit 0
            }
            Confirm-Dependencies
            Set-Status installing
            Get-SaltFromWeb
            Install-SaltMinion
            Add-MinionConfig
            Start-MinionService
            Set-Status installed
        }
        "remove" {
            # If status is installing(1), notInstalled(2), or removing(4), bail out
            $current_status = Get-Status
            if (1, 2, 4 -contains $current_status) {
                Write-Log "Removal will not continue"
                exit 0
            }
            # If status is notInstalled or removing, bail out
            Set-Status removing
            Remove-SaltMinion
            Set-Status notInstalled
        }
        "reset" {
            # If status is installing(1), notInstalled(2), or removing(4), bail out
            $current_status = Get-Status
            if (1, 2, 4 -contains $current_status) {
                Write-Log "Reset will not continue"
                exit 0
            }
            Reset-SaltMinion
        }
        "status" {
            return Get-Status
        }
        default {
            $action_list = "add, remove, depend, reset, status"
            Write-Log "Invalid action: $Action - Must be one of [$action_list]" -Level error
            exit 1
        }
    }
} else {
    # No action specified
    Write-Log "No action specified" -Level error
    exit 1
}
