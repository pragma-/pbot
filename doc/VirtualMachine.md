# Virtual Machine

<!-- md-toc-begin -->
* [About](#about)
* [Initial virtual machine set-up](#initial-virtual-machine-set-up)
  * [Prerequisites](#prerequisites)
    * [CPU Virtualization Technology](#cpu-virtualization-technology)
    * [KVM](#kvm)
    * [libvirt](#libvirt)
    * [Make a pbot-vm user or directory](#make-a-pbot-vm-user-or-directory)
    * [Add libvirt group to your user](#add-libvirt-group-to-your-user)
    * [Download Linux ISO](#download-linux-iso)
  * [Creating a new virtual machine](#creating-a-new-virtual-machine)
    * [Installing Linux in the virtual machine](#installing-linux-in-the-virtual-machine)
    * [Configuring virtual machine for PBot](#configuring-virtual-machine-for-pbot)
    * [Set up serial ports](#set-up-serial-ports)
    * [Install Perl](#install-perl)
    * [Install PBot VM Guest](#install-pbot-vm-guest)
    * [Install software](#install-software)
    * [Start PBot VM Guest](#start-pbot-vm-guest)
    * [Test PBot VM Guest](#test-pbot-vm-guest)
    * [Save initial state](#save-initial-state)
  * [Initial virtual machine set-up complete](#initial-virtual-machine-set-up-complete)
* [Start PBot VM Host](#start-pbot-vm-host)
  * [Test PBot](#test-pbot)
<!-- md-toc-end -->

## About

PBot can interact with a virtual machine to safely execute arbitrary user-submitted
system commands and code.

This document will guide you through installing and configuring a virtual machine
by using the widely available [libvirt](https://libvirt.org) project tools, such as
`virt-install`, `virsh`, `virt-manager`, `virt-viewer`, etc.

If you're more comfortable working with QEMU directly instead, feel free to do that.
I hope this guide will answer everything you need to know to set that up. If not,
open an GitHub issue or /msg me on IRC.

Some quick terminology:

 * host: your physical Linux system hosting the virtual machine
 * guest: the Linux system installed inside the virtual machine

## Initial virtual machine set-up
These steps need to be done only once during the first-time set-up.

### Prerequisites
#### CPU Virtualization Technology
Ensure CPU Virtualization Technology is enabled in your motherboard BIOS.

    $ egrep '(vmx|svm)' /proc/cpuinfo

If you see your CPUs listed with `vmx` or `svm` flags, you're good to go.
Otherwise, consult your motherboard manual to see how to enable VT.

#### KVM
Ensure KVM is set up and loaded.

    $ kvm-ok
    INFO: /dev/kvm exists
    KVM acceleration can be used

If you see the above, everything's set up. Otherwise, consult your operating
system manual or KVM manual to install and load KVM.

#### libvirt
Ensure libvirt is installed and ready.

    $ virsh version --daemon
    Compiled against library: libvirt 7.6.0
    Using library: libvirt 7.6.0
    Using API: QEMU 7.6.0
    Running hypervisor: QEMU 6.0.0
    Running against daemon: 7.6.0

If there's anything missing, please consult your operating system manual to
install the libvirt and QEMU packages.

On Ubuntu: `sudo apt install qemu-kvm libvirt-daemon-system`

#### Make a pbot-vm user or directory
You can either make a new user account or make a new directory in your current user account.
In either case, name it `pbot-vm` so we'll have one place for the install ISO file and the
virtual machine disk and snapshot files.

#### Add libvirt group to your user
Add your user or the `pbot-vm` user to the `libvirt` group.

    $ sudo adduser $USER libvirt

Log out and then log back in for the new group to take effect on your user.

#### Download Linux ISO
Download a preferred Linux ISO. For this guide, we'll use Fedora. Why? I'm
using Fedora Rawhide for my PBot VM because I want convenient and reliable
access to the latest bleeding-edge versions of software.

I recommend using the Fedora Stable net-installer for this guide unless you
are more comfortable in another Linux distribution. Make sure you choose
the minimal install option without a graphical desktop.

https://download.fedoraproject.org/pub/fedora/linux/releases/35/Server/x86_64/iso/Fedora-Server-netinst-x86_64-35-1.2.iso
is the Fedora Stable net-installer ISO used in this guide.

### Creating a new virtual machine
To create a new virtual machine we'll use the `virt-install` command. First, ensure you are
the `pbot-vm` user or that you have changed your current working directory to `pbot-vm`.

    $ virt-install --name=pbot-vm --disk=size=12,cache=none,driver.io=native,snapshot=external,path=vm.qcow2 --cpu=host --os-variant=fedora34 --graphics=spice,gl.enable=yes --video=virtio --location=Fedora-Server-netinst-x86_64-35-1.2.iso

If you are installing over an X-forwarded SSH session, strip the `,gl.enable=yes`
part. Note that `disk=size=12` will create a 12 GB sparse file. Sparse means the file
won't actually take up 12 GB. It will start at 0 bytes and grow as needed. You can
use the `du` command to verify this. After a minimal Fedora install, the size will be
approximately 1.7 GB. It will grow to about 2.5 GB with most PBot features installed.

For further information about `virt-install`, read its manual page. While the above command should
give sufficient performance and compatability, there are a great many options worth investigating
if you want to fine-tune your virtual machine.

#### Installing Linux in the virtual machine
After executing the `virt-install` command above, you should now see a window
showing Linux booting up and launching an installer. For this guide, we'll walk
through the Fedora 35 installer. You can adapt these steps for your own distribution
of choice.

 * Click `Partition disks`. Don't change anything. Click `Done`.
 * Click `Root account`. Click `Enable root account`. Set a password. Click `Done`.
 * Click `User creation`. Create a new user. Skip Fullname and set Username to `vm`. Untick `Add to wheel` or `Set as administrator`. Untick `Require password`.
 * Wait until `Software selection` is done processing and is no longer greyed out. Click it. Change install from `Server` to `Minimal`. Click `Done`.
 * Click `Begin installation`.

Installation will need to download about 328 RPMs consisting of about 425 MB. It'll take 5 minutes to an hour or longer
depending on your hardware and network configuration.

#### Configuring virtual machine for PBot
Once the install finishes, click the `Reboot` button in the Fedora installer in the virtual machine window.

#### Set up serial ports
Now, while the virtual machine is rebooting, switch to a terminal on your host system. Go into the
`pbot-vm/host/devices` directory and run the `add-serials` script. Feel free to look inside. It will add
the `serial-2.xml` and `serial-3.xml` files to the configuration for the `pbot-vm` libvirt machine.

This will enable and connect the `/dev/ttyS1` and `/dev/ttyS2` serial ports inside the virtual machine
to TCP connections on `127.0.0.1:5555` and `127.0.0.1:5556`, respectively. `ttyS1/5555` is the data
channel used to send commands or code to the virtual machine and to read back output. `ttyS2/5556` is
simply a newline sent every 5 seconds, representing a heartbeat, used to ensure that the PBot communication
channel is healthy.

Once that's done, switch back to the virtual machine window. Once the virtual machine has rebooted,
log in as `root`. Now go ahead and shut the virtual machine down with `shutdown now -h`. We need to
restart the virtual machine itself so it loads the new serial device configuration. Once the machine
has shutdown, bring it right back up with the following commands on the host system in the terminal
used for `virt-install`:

    $ virsh start pbot-vm

Now the virtual machine will start back up in the background.

    $ virt-viewer pbot-vm

Now you should see the virtual machine window after a few seconds. Log in as `root` once the login
prompt appears.

#### Install Perl
Now we need to install Perl inside the virtual machine. This allows us to run the PBot VM Guest
script.

    $ dnf install perl-interpreter perl-lib perl-IPC-Run perl-JSON-XS perl-English

That installs the minium packages for the Perl interpreter (note we used `perl-interpreter` instead of `perl`),
the package for the Perl `lib`, `IPC::Run`, `JSON::XS` and `English` modules.

#### Install PBot VM Guest
Next we install the PBot VM Guest script that fosters communication between the virtual machine guest
and the physical host system. We'll do this inside the virtual machine guest system.

The `rsync` command isn't installed in a Fedora minimal install, but `scp` is available. Replace
`192.168.100.42` below with your own local IP address and `user` with the user account that has the
PBot directory and `pbot` with the path to the directory.

    $ scp -r user@192.168.100.42:~/pbot/applets/pbot-vm/guest .

Once that's done, run the following command:

    $ ./guest/bin/setup-guest

Feel free to take a look inside to see what it does. It's very short. After running
the `setup-guest` script make sure you run `source /root/.bashrc` so the environment
changes take effect.

#### Install software
Now you can install any languages you want to use.

Python3 is already installed.

For the C programming language you will need at least these:

    $ dnf install libubsan libasan gdb gcc clang

I'll list all the packages for the others soon. You can use `dnf search <name>` to find packages
in Fedora.

#### Start PBot VM Guest
We're ready to start the PBot VM Guest.

    $ start-guest

This starts up a server to listen for incoming commands or code and to handle them. We'll leave
this running.

#### Test PBot VM Guest
Let's make sure everything's working up to this point. There should be two open TCP ports on
`5555` and `5556`.

    $ nc -zv 127.0.0.1 5555-5556

If it says anything other than `Connection succeeded` then make sure you have completed the steps
under [Set up serial ports](#set-up-serial-ports) and that your network configuration is allowing
access.

Let's make sure the PBot VM Guest is listening for and can execute commands. The `vm-exec` command
in the `applets/pbot-vm/host/bin` directory allows you to send commands from the shell.

    $ vm-exec -lang=sh echo hello world

This should output some logging noise followed by "hello world". You can test other language modules
by changing the `-lang=` option. I recommend testing and verifying that all of your desired language
modules are configured before going on to the next step.

If you have multiple PBot VM Guests, or if you used a different TCP port, you can specify the
`PBOT_VM_PORT` environment variable when executing the `vm-exec` command:

    $ PBOT_VM_PORT=6666 vm-exec -lang=sh echo test

#### Save initial state
Switch back to an available terminal on the physical host machine. Enter the following command
to save a snapshot of the virtual machine waiting for incoming commands.

    $ virsh snapshot-create-as pbot-vm 1

This will create a snapshot file `vm.1` next to the `vm.qcow2` disk file. If the virtual machine
ever times-out or its heartbeat stops responding, PBot will reset the virtual machine to this
saved snapshot.

### Initial virtual machine set-up complete
This concludes the initial one-time set-up. You can close the `virt-viewer` window. The
virtual machine will continue running in the background until it is manually shutdown (via
`shutdown now -h` inside the VM or via `virsh shutdown pbot-vm` on the host).

## Start PBot VM Host
To start the PBot VM Host server, execute the `vm-server` script in the
`applets/pbot_vm/host/bin` directory on the host.

This will start a TCP server on port `9000`. It will listen for incoming commands and
pass them along to the virtual machine's TCP serial port.

### Test PBot
All done. Everything is set up now. In your instance of PBot, the `sh echo hello` command should output `hello`.
