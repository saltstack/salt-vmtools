# salt-vm-tools

VMTools salt integration script to install/remove/check status for a
salt-minion in a VMware controled Virtual Machine environment

This script operates as a BASH script in Linux enviuronments and a
PowerShell script in Windows environments

The salt-minion is a Tiamat based Python 3 salt-minion leveraging
PyInstaller's onedir option internally. The salt-minion is fully
self-contained and requires no additional dependencies.

Pre-requisties:
    The following utilities are expected to be available on the system:
        systemctl
        curl
        sha512sum
        vmtoolsd

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

    Middle preference:
        guestVars   guestinfo.vmware.components.salt_minion.args

        For example:
        [root@fedora]# vmtoolsd --cmd "info-get guestinfo.vmware.components.salt_minion.args"
        master=192.168.0.121

    Highest preference:
        script command line install options, for example:

        svtminion.sh --install master=192.168.0.121


    Note: Subsequent configuration parameters, if specified will update
          previously set values.  For example: in the configuration
          preference examples outlined above, the final value for
          master is '192.168.0.121' which updates the previous value
          of '192.168.0.118' since the script command line install arguments
          have higher precedence than those read from 'tools.conf'.

    Note: A minion identifier is automatically generated for the salt-minion,
          however one can be specified using key=value.

            For example: id=myminion

    Note: At all times preference is given to actions presented on the
          command line, over those available from guest variables or
          from tools.conf.

          For example:
            on the command line:
                svtminion.sh --install

            guest variable
                guestinfo.vmware.components.salt_minion
                    returns 'remove'

            Preference will be given to the command line argument and
            the salt-minion shall be installed.


    Usage for the script svtminion.sh

        usage: ./svtminion.sh  [-c|--status] [-d|--debug] [-e|--depend]
                     [-h|--help] [-i|--install] [-r|--remove] [-v|--verbose]

          -c, --status    return status for this script
          -d, --debug     enable debugging logging
          -e, --depend    check dependencies required to run this script exist
          -h, --help      this message
          -i, --install   install and activate the salt-minion
          -r, --remove    deactivate and remove the salt-minion
          -v, --verbose   enable verbose logging and messages

          salt-minion vmtools integration script
              example: ./svtminion.sh --status


Windows Environment:
