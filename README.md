# salt-vm-tools

The VMTools salt integration script installs, removes, or checks the status of a Salt minion
(`salt-minion`) in a VMware controlled Virtual Machine environment.

This script operates as a BASH script in Linux environments and a PowerShell
script in Windows environments.

The Salt minion is a [Tiamat](https://gitlab.com/saltstack/pop/tiamat) based
Python 3 Salt minion leveraging [PyInstaller's](https://www.pyinstaller.org/)
onedir option internally. The Salt minion is fully self-contained and requires
no additional dependencies.

The script can install, remove, and check the status of an installed Salt minion
either using a direct command line option or via VMware's use of Guest Variables,
commonly referred to as guestVars.


## Configuration options

You can pass configuration to this script in 3 ways: guestVars, tools.conf and
the command line. Each option has an order of precedence. The lowest being
guestVars, followed by tools.conf, with the highest precedence being the command
line. Each option is explained in the following sections.

### guestVars (lowest preference)

VMware guestVars can contain the action this script performs as well as the
minion config options to be set by this script. The config values here will
override any config options defined in `tools.conf` with the same name.

The guestVars paths are as follows:

| Option | guestVars Location |
| ------ | ------------------ |
| Action | `vmware.components.salt_minion` |
| Config | `vmware.components.salt_minion.args` |

If set, the `Action` option will return a single word that is the action this
script will perform. If set, the `Config` option will return a space delimited
list of minion config options. For example: `master=198.51.100.1 id=my_minion
multiprocessing=false`

These values are set on the host OS using the `vmrun` binary. For example:

    # To set the Action
    vmrun writeVariable "<path/to/vmx/file>" guestVar vmware.components.salt_minion "install"

    # To set the Config Options
    vmrun writeVariable "<path/to/vmx/file>" guestVar vmware.components.salt_minion.args "master=203.0.113.1"

They can be read on the guest OS using the `vmtoolsd` binary. For example:

    # To read the Config Options
    [root@fedora]# vmtoolsd --cmd "info-get guestinfo.vmware.components.salt_minion.args"
    master=203.0.113.1

### tools.conf (medium preference)

The `tools.conf` file contains the configurations for vmtools in an `.ini` format.
This tool looks for the `salt_minion` section and uses the configurations defined
under that section. This file is stored at:

| OS  | Location |
| --- | -------- |
| Linux | `/etc/vmware-tools/tools.conf` |
| Windows | `C:\ProgramData\VMware\VMware Tools\tools.conf` |

Below is an example of the `salt_minion` section as it may be defined in
`tools.conf`:

    [salt_minion]
    master=203.0.113.1
    conf_file=/etc/salt/minion
    id=dev_minion

**Note:** Only minion config options are available in `tools.conf`. The desired
script action cannot be obtained from `tools.conf`.

### Command Line (highest preference)

Any input passed to the script on the command line will take precedence over:

- The action and config options set in guestVars
- Anything configured in `tools.conf` with the same name.

Linux example:

    [root@fedora]# svtminion.sh --install master=198.51.100.1

Windows example (note the single dash):

    # Powershell
    PS> svtminion.ps1 -install master=198.51.100.1

    # cmd
    C:\>powershell -file svtminion.ps1 -install master=198.51.100.1

**Note:** Higher preference configuration options will supersede lower
preference values.  For example, in the configuration preference examples
outlined above, the final value for master is `198.51.100.1`. Command line
option for master overrides the `tools.conf` value of `203.0.113.1` and the
guestVars value of `203.0.113.1` because the command line arguments have the
highest precedence.

**Note:*** On Windows, if the minion ID is not passed, the guest host name will
be used. However, on Linux there is no guarantee that a host name will be set.
Therefore, a minion ID is automatically generated for the Salt minion. In either
case, the minion ID can be specified in any of the 3 config options. For example:

    id=myminion

**Note:** At all times preference is given to actions presented on the command
line over those available from guestVars.

For example, if the following is passed on the command line:

    [root@fedora]# svtminion.sh --install

And the following is defined in guestVars:

    [root@fedora]# vmtoolsd --cmd "info-get guestinfo.vmware.components.salt_minion"
    remove

Preference is given to the command line argument and the Salt minion package will
be installed.


## Logging

This script creates a log file at the following location:

| OS  | Location |
| --- | -------- |
| Linux | `/var/log` |
| Windows | `C:\ProgramData\VMware\logs` |

The content of the log file depends on the `LogLevel` passed on the command
line. The default value is `warning`. Valid options are:

| Log Level | Description |
| --------- | ----------- |
| `silent`  | Suppresses displayed output but logs errors and warnings |
| `error`   | Displays and logs only errors |
| `warning` | Displays and logs errors and warnings |
| `info`    | Displays and logs errors, warnings, and info messages |
| `debug`   | Displays and logs all messages |

The names of Log files are based on the action that the script is performing. The
`action` can be defined on the command line or by setting a value in guestVars.
Any logging that is unrelated to an action uses the keyword `default`. Valid
actions are as follows:

- `clear`
- `depend`
- `install`
- `remove`
- `status`

For example, running the script without a defined action results in a log
file with the following name:

    # Linux
    bash>svtminion.sh --version --loglevel debug

    /etc/log/vmware-svtminion.sh-default-YYYYMMDDhhmmss.log

    # Windows
    PS>.\svtminion.ps1 -LogLevel debug

    or

    cmd>powershell -file .\svtminion.ps1 -LogLevel debug

    C:\ProgramData\VMware\logs\vmware-svtminion-default-YYYYMMDDhhmmss.log

Only the 10 most recent log files for each action are maintained. Excess log
files are removed. Log files are not removed when the salt-minion service is uninstalled.


## Linux Environment:

On Linux systems, the install script is a bash script with the following
pre-requisites:

- systemctl
- curl
- sha512sum
- vmtoolsd
- grep
- awk
- sed
- cut

`svtminion.sh --help` shows the command line options

    Usage for the script svtminion.sh

        usage: ./svtminion.sh  [-c|--clear] [-d|--depend] [-h|--help] [-i|--install]
                     [-l|--loglevel] [-m|--minionversion] [-r|--remove]
                     [-s|--status] [-v|--version]

          -c, --clear     clear previous minion identifer and keys,
                             and set specified identifer if present
          -d, --depend    check dependencies required to run this script exist
          -h, --help      this message
          -i, --install   install and activate the salt-minion
                             parameters key=value can also be passed on the CLI
          -l, --loglevel  set log level for logging, silent error warning debug info
                             default loglevel is warning
          -m, --minionversion salt-minion version to install, default[latest]
          -r, --remove    deactivate and remove the salt-minion
          -s, --status    return status for this script
          -v, --version   version of this script

          salt-minion vmtools integration script
              example: ./svtminion.sh --status


Windows Environment:
--------------------

On Windows systems, the install script is a powershell script. The only
prerequisite for Windows is the `vmtoolsd.exe` binary, which is used to query
guestVars data. You can get help for this script by running `svtminion.ps1 -h`
or `Get-Help svtminion.ps1`:

    NAME
        .\svtminion.ps1

    SYNOPSIS
        VMware Tools script for managing the Salt minion on a Windows guest

    SYNTAX
        .\svtminion.ps1 [-Install] [-MinionVersion <String>] [[-ConfigOptions] <String[]>] [-LogLevel <String>] [-Help] [-Version] [<CommonParameters>]
        .\svtminion.ps1 [-Remove] [-LogLevel <String>] [-Help] [-Version] [<CommonParameters>]
        .\svtminion.ps1 [-Clear] [-LogLevel <String>] [-Help] [-Version] [<CommonParameters>]
        .\svtminion.ps1 [-Status] [-LogLevel <String>] [-Help] [-Version] [<CommonParameters>]
        .\svtminion.ps1 [-Depend] [-LogLevel <String>] [-Help] [-Version] [<CommonParameters>]
        .\svtminion.ps1 [-Help] [<CommonParameters>]
        .\svtminion.ps1 [-Version] [<CommonParameters>]

    DESCRIPTION
        This script manages the Salt minion on a Windows guest. The minion is a tiamat
        build hosted on https://repo.saltproject.io/salt/vmware-tools-onedir. You can
        install the minion, remove it, check script dependencies, get the Salt minion
        installation status, and reset the Salt minion configuration.

        When this script is run without any parameters, the action is obtained from
        guestVars (if present). If no action is found, the script will exit with a
        scriptFailed exit code.

        If an action is passed on the CLI or found in guestVars, minion config options
        (master=198.51.100.1, etc.) are queried from guestVars. Config options are then
        obtained from tools.conf. Config options obtained from tools.conf will overwrite
        any config options obtained from guestVars with the same name. Config options
        passed on the CLI will overwrite any config options obtained from either of the
        previous two methods. The order of precedence is CLI options first, then
        tools.conf, and finally guestVars.

        This script returns exit codes to signal its success or failure. The exit codes
        are as follows:

        0 - scriptSuccess
        126 - scriptFailed
        130 - scriptTerminated

        If the Status option is passed, then the exit code will signal the status of the
        Salt minion installation. Status exit codes are as follows:

        100 - installed
        101 - installing
        102 - notInstalled
        103 - installFailed
        104 - removing
        105 - removeFailed

        NOTE: This script must be run with Administrator privileges

    PARAMETERS
        -Install [<SwitchParameter>]
            Downloads, installs, and starts the salt-minion service. Exits with
            scriptFailed exit (126) code under the following conditions:
            - Existing Standard Salt Installation detected
            - Unknown status found
            - Installation in progress
            - Removal in progress
            - Installation failed
            - Missing script dependencies

            Exits with scriptSuccess exit code (0) under the following conditions:
            - Installed successfully
            - Already installed

        -MinionVersion <String>
            The version of Salt minion to install. Default is "latest".

        -ConfigOptions <String[]>
            Any number of minion config options specified by the name of the config
            option as found in Salt documentation. All options will be lowercased and
            written to the minion config as passed. All values are in the key=value
            format. For example: master=localhost

        -Remove [<SwitchParameter>]
            Stops and uninstalls the salt-minion service. Exits with scriptFailed exit
            code (126) under the following conditions:
            - Unknown status found
            - Installation in progress
            - Removal in progress
            - Installation failed
            - Missing script dependencies

            Exits with scriptSuccess exit code (0) under the following conditions:
            - Removed successfully
            - Already removed

        -Clear [<SwitchParameter>]
            Resets the salt-minion by randomizing the minion ID and removing the
            minion keys. The randomized minion ID will be the old minion ID, an
            underscore, and 5 random digits.

            Exits with scriptFailed exit code (126) under the following conditions:
            - Unknown status found
            - Missing script dependencies

            Exits with scriptSuccess exit code (0) under the following conditions:
            - Cleared successfully
            - Not installed

        -Status [<SwitchParameter>]
            Gets the status of the Salt minion installation. This command returns an
            exit code that corresponds to one of the following:
            100 - installed
            101 - installing
            102 - notInstalled
            103 - installFailed
            104 - removing
            105 - removeFailed

            Exits with scriptFailed exit code (126) under the following conditions:
            - Unknown status found
            - Missing script dependencies

        -Depend [<SwitchParameter>]
            Ensures the required dependencies are available. Exits with a scriptFailed
            exit code (126) if any dependencies are missing. Exits with a
            scriptSuccess exit code (0) if all dependencies are present.

        -LogLevel <String>
            Sets the log level to display and log. Default is warning. Silent
            suppresses all logging output. Available options are:
            - silent
            - error
            - warning
            - info
            - debug

        -Help [<SwitchParameter>]
            Displays help for this script.

        -Version [<SwitchParameter>]
            Displays the version of this script.

        <CommonParameters>
            This cmdlet supports the common parameters: Verbose, Debug,
            ErrorAction, ErrorVariable, WarningAction, WarningVariable,
            OutBuffer, PipelineVariable, and OutVariable. For more information, see
            about_CommonParameters (https:/go.microsoft.com/fwlink/?LinkID=113216).

        -------------------------- EXAMPLE 1 --------------------------
        PS>svtminion.ps1 -Install
        PS>svtminion.ps1 -Install -MinionVersion 3004-1 master=192.168.10.10 id=dev_box

        -------------------------- EXAMPLE 2 --------------------------
        PS>svtminion.ps1 -Clear

        -------------------------- EXAMPLE 3 --------------------------
        PS>svtminion.ps1 -Status

        -------------------------- EXAMPLE 4 --------------------------
        PS>svtminion.ps1 -Depend

        -------------------------- EXAMPLE 5 --------------------------
        PS>svtminion.ps1 -Remove -LogLevel debug

    REMARKS
        To see the examples, type: "get-help .\svtminion.ps1 -examples".
        For more information, type: "get-help .\svtminion.ps1 -detailed".
        For technical information, type: "get-help .\svtminion.ps1 -full".
