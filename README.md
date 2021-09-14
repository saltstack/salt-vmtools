# salt-vm-tools

VMTools salt integration script to install/remove/check status for a
salt-minion in a VMware controled Virtual Machine environment

This script operates as a BASH script in Linux enviuronments and a
PowerShell script in Windows environments

The salt-minion is a Tiamat based Python 3 salt-minion leveraging
PyInstaller's onedir option internally. The salt-minion is fully
self-contained and requires no additional dependencies.

Linux Environment:
    The script can install, remove and check the status of an installed
    salt-minion either by direct command line option or via VMware's use
    of Guest Variables, commonly referred to as guestVars.

    svtminion.sh --help shows the command line options

    guestVars   location for salt-minion settings, component status and
                arguments are available from:
                    guestinfo.vmware.components.salt_minion

    Configuration parameters for the salt-minion can be read from a number
    of sources, in the following preference order:

    Lowest preference:
        VMTools configuration file /etc/vmware-tools/tools.conf

        For example:
            [salt_minion]
            master=192.168.0.118
            id=myminion

    Middle preference:
        guestVars   guestinfo.vmware.components.salt_minion.args

    Highest preference:
        script command line install options, for example:

        svtminion.sh --install master=192.168.0.121 id=myminion


    Note: subsequent configuration parameters, if specified will update
          previously set values.  For example: in the configuration
          preference examples outlined above, the final value for
          master is '192.168.0.121' which updates the previous value
          of '192.168.0.118' since the script command line install arguments
          have higher precedence than those read from 'tools.conf'.


Windows Environment:
