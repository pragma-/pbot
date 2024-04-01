# Virtual Machine

PBot can interact with a virtual machine to safely execute arbitrary user-submitted
system commands and code.

This document will guide you through installing and configuring a Linux
virtual machine on a Linux host by using the widely available [libvirt](https://libvirt.org)
project tools, such as `virt-install`, `virsh`, and `virt-viewer`. Additionally,
if you'd prefer not to use libvirt, this guide will also demonstrate equivalent
Linux system commands and QEMU commands.

Some quick terminology:

 * host: your physical Linux system hosting the virtual machine
 * guest: the Linux system installed inside the virtual machine

The commands below will be prefixed with `host$` or `guest$` to reflect where
the command should be executed.

Many commands can be configured with environment variables. If a variable is
not defined, a sensible default value will be used.

Environment variable | Default value | Description
-------------------- | ------------- | -----------
PBOTVM_DOMAIN        | `pbot-vm`     | The libvirt domain identifier
PBOTVM_ADDR          | `127.0.0.1`   | `vm-server` address for incoming `vm-client` commands
PBOTVM_PORT          | `9000`        | `vm-server` port for incoming `vm-client` commands
PBOTVM_SERIAL        | `5555`        | TCP port for serial communication
PBOTVM_HEART         | `5556`        | TCP port for serial heartbeats
PBOTVM_CID           | `7`           | Context ID for VM socket (if using VSOCK)
PBOTVM_VPORT         | `5555`        | VM socket service port (if using VSOCK)
PBOTVM_TIMEOUT       | `10`          | Duration before command times out (in seconds)
PBOTVM_NOREVERT      | not set       | If set then the VM will not revert to previous snapshot

## Initial virtual machine set-up
These steps need to be done only once during the first-time set-up.

### Prerequisites
For full hardware-supported virtualization at near native system speeds, we
need to ensure your system has enabled CPU Virtualization Technology and that
KVM is set up and loaded.

#### CPU Virtualization Technology
Ensure CPU Virtualization Technology is enabled in your motherboard BIOS.

    host$ egrep '(vmx|svm)' /proc/cpuinfo

If you see your CPUs listed with `vmx` or `svm` flags, you're good to go.
Otherwise, consult your motherboard manual to see how to enable VT.

#### KVM
Ensure KVM is set up and loaded.

    host$ kvm-ok
    INFO: /dev/kvm exists
    KVM acceleration can be used

If you see the above, everything's set up. Otherwise, consult your operating
system manual or KVM manual to install and load KVM.

If you do not have the `kvm-ok` command, you can `ls /dev/kvm` to ensure the KVM device exists.

#### libvirt and QEMU
If using libvirt, ensure it is installed and ready.

    host$ virsh version --daemon
    Compiled against library: libvirt 7.6.0
    Using library: libvirt 7.6.0
    Using API: QEMU 7.6.0
    Running hypervisor: QEMU 6.0.0
    Running against daemon: 7.6.0

Just QEMU (assuming x86_64):

    host$ qemu-system-x86_64 --version
    QEMU emulator version 6.0.0
    Copyright (c) 2003-2021 Fabrice Bellard and the QEMU Project developers

If there's anything missing, please consult your operating system manual to
install the libvirt and/or QEMU packages.

On Ubuntu: `sudo apt install qemu-kvm libvirt-daemon-system`

On OpenSUSE Tumbleweed: `sudo zypper in libvirt virt-install virt-viewer`

#### Make a pbot-vm user or directory
You can either make a new user account or make a new directory in your current user account.
In either case, name it `pbot-vm` so we'll have a home for the virtual machine.

#### Add libvirt group to your user
Add your user (or the `pbot-vm` user) to the `libvirt` group.

    host$ sudo adduser $USER libvirt

or

    host$ sudo usermod -aG libvirt $USER

Log out and then log back in for the new group to take effect. Or use the
`newgrp` command.

#### Download Linux ISO
Download a preferred Linux ISO. For this guide, we'll provide instructions for Fedora
and OpenSUSE Tumbleweed. Why? I was initially using Fedora Rawhide for my PBot VM because
I wanted convenient and reliable access to the latest bleeding-edge versions of software.
I've since switched to OpenSUSE Tumbleweed for easy access to packages that are even more
bleeding-edge than Fedora Rawhide.

If you are more comfortable in another Linux distribution then feel free to choose that instead.
Make sure you choose the minimal install option without a graphical desktop.

The ISOs used in this guide are (you may instead prefer to navigate to the websites to download a more current image):

https://download.fedoraproject.org/pub/fedora/linux/releases/35/Server/x86_64/iso/Fedora-Server-netinst-x86_64-35-1.2.iso

or

https://download.opensuse.org/tumbleweed/iso/openSUSE-Tumbleweed-NET-x86_64-Snapshot20240321-Media.iso

I recommend using OpenSUSE Tumbleweed since that's what I've tested on most recently.

### Create a new virtual machine
To create a new virtual machines, this guide offers two options. The first is
libvirt's `virt-install` command. It greatly simplifies configuration by
automatically creating networking bridges and setting up virtio devices. The
second option is manually using Linux system commands to configure network
bridges and execute QEMU with the correct options.

#### libvirt
To create a new virtual machine we'll use the `virt-install` command. This
command takes care of setting up virtual networking bridges and virtual
hardware for us. If you prefer to manually set things up and use QEMU directly,
skip past the `virt-install` section.

* First, ensure you are the `pbot-vm` user or that you have changed your current working directory to `pbot-vm`. The Linux ISO downloaded earlier should be present in this location.

Execute the following command:

Fedora (using Spice graphical display):

    host$ virt-install --name=pbot-vm --disk=size=12,path=vm.qcow2 --cpu=host --os-variant=fedora34 --graphics=spice --video=virtio --location=Fedora-Server-netinst-x86_64-35-1.2.iso

OpenSUSE Tumbleweed (using PTY serial console):

    host$ virt-install --name=pbot-vm --disk=size=12,path=vm.qcow2 --cpu=host --os-variant=opensusetumbleweed --graphics=none --console=pty,target.type=virtio --serial=pty --extra-args=console=ttyS0,115200n8 --video=virtio --location=openSUSE-Tumbleweed-NET-x86_64-Snapshot20240321-Media.iso

You may use `virt-install --os-variant list` to list the available `--os-variant` options present on your machine.

Note that `disk=size=12` will create a 12 GB sparse file. Sparse means the file
won't actually take up 12 GB. It will start at 0 bytes and grow as needed. You can
use the `du` command to verify this. After a minimal Fedora install, the size will be
approximately 1.7 GB. It will grow to about 2.5 GB with all PBot features installed.

For further information about `virt-install`, read its manual page. While the above command should
give sufficient performance and compatability, there are a great many options worth investigating
if you want to fine-tune your virtual machine.

To list virtual machines and their state use `virsh list --all`.

If you need to ungracefully shutdown the virtual machine use `virsh destroy pbot-vm`.

If you need to delete the virtual machine and its storage volume use: `virsh undefine pbot-vm --storage vda --snapshots-metadata`.

#### QEMU
If you prefer not to use libvirt, we may need to manually create the network
bridge. Use the `ip link` command to list network interfaces:

    host$ sudo ip link
    1: lo: <LOOPBACK,UP,LOWER_UP> mtu 65536 qdisc noqueue state UNKNOWN mode DEFAULT group default qlen 1000
        link/loopback 00:00:00:00:00:00 brd 00:00:00:00:00:00
    2: eth0: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc fq_codel state UP mode DEFAULT group default qlen 1000
        link/ether 74:86:7a:4e:a1:95 brd ff:ff:ff:ff:ff:ff
        altname enp1s0
    3: virbr0: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc noqueue state UP group default qlen 1000
        link/ether 52:54:00:83:3f:59 brd ff:ff:ff:ff:ff:ff
        inet 192.168.123.1/24 brd 192.168.123.255 scope global virbr0
           valid_lft forever preferred_lft forever


Create a new bridged named `pbot-br0`:

    host$ ip link add name pbot-br0 type bridge
    host$ ip link set pbot-br0 up

Add your network interface to the bridge:

    host$ ip link set eth0 master pbot-br0

Give the bridge an IP address (use an appropriate address for your network):

    host$ ip addr add dev pbot-br0 192.168.50.2/24

We will use the `qemu-bridge-helper` program from the `qemu-common` package to
create the TAP interface for us when we start the virtual machine and to remove
the interface when the virtual machine is shut-down. To set the program up, we
need to create its access control list file:

    host$ sudo mkdir /etc/qemu
    host$ sudo chmod 755 /etc/qemu
    host$ sudo echo allow pbot-br0 >> /etc/qemu/bridge.conf
    host$ sudo chmod 640 /etc/qemu/bridge.conf

To allow unprivileged users to create VMs using the network bridge, we must set
the SUID bit on the `qemu-bridge-helper` program:

    host$ chmod u+s /usr/lib/qemu/qemu-bridge-helper

With the bridge configured, we move on to creating a sparse disk image for the
virtual machine:

    host$ qemu-img create -f qcow2 pbot-vm.qcow2 12G

Then we can start QEMU (assuming x86_64) and tell it to boot the installer ISO:

Fedora:

    host$ qemu-system-x86_64 -enable-kvm -cpu host -mem 1024 -hda pbot-vm.qcow2 -cdrom Fedora-Server-netinst-x86_64-35-1.2.iso -boot d -nic bridge,br=pbot-br0 -usb -device usb-tablet

OpenSUSE Tumbleweed:

    host$ qemu-system-x86_64 -enable-kvm -cpu host -mem 1024 -hda pbot-vm.qcow2 -cdrom openSUSE-Tumbleweed-NET-x86_64-Snapshot20240321-Media.iso -boot d -nic bridge,br=pbot-br0 -usb -device usb-tablet

This command is the bare minimum for performant virtualization with networking.
See the QEMU documentation for interesting options to tweak your virtual machine.

#### Install Linux in the virtual machine
After executing the `virt-install` or `qemu` command above, you should now see Linux booting up and launching an installer.
For this guide, we'll walk through the Fedora 35 and the OpenSUSE Tumbleweed installers. You can adapt these steps for your
own distribution of choice.

Fedora:

 * Click `Partition disks`. Don't change anything. Click `Done`.
 * Click `Root account`. Click `Enable root account`. Set a password. Click `Done`.
 * Click `User creation`. Create a new user. Skip Fullname and set Username to `vm`. Untick `Add to wheel` or `Set as administrator`. Untick `Require password`. Click `Done`.
 * Wait until `Software selection` is done processing and is no longer greyed out. Click it. Change install from `Server` to `Minimal`. Click `Done`.
 * Click `Begin installation`.

Installation will download about 328 RPMs consisting of about 425 MB. The `vm.qcow2` file should be about 2 GB after installation completes. You can close the Spice window. To reattach
use `virt-viewer pbot-vm`.

Tumbleweed:

 * Follow on-screen instructions and TAB to `Next` until you reach the `System Role` screen.
 * Ensure you select the `Server` role to install a small set of packages suitable for servers with a text mode interface.
 * On `Suggested Partitioning` TAB to `Guided Setup`.
 * Select `Next` until you reach `Filesystem Options`.
 * TAB to `Btrfs` and press SPACE and then arrow-keys to change this to `Ext4` to improve random-access IO performance and reduce writes. Then TAB to `Next` and continue.
 * Continue following on-screen instructions until you reach the `Local User` screen.
 * Enter `vm` for `Username` and set a password. Then TAB to `Next` and continue.
 * At the `Installation Settings` tab to `Change` and select `Security`. Untick `Enable Firewall` to make things easier. Then TAB to `Next` and continue.
 * Verify installation settings and then TAB to `Install` and begin the installation.

Installation will download about 800 packages consisting of about 1.7 GiB. The `vm.qcow2` file should be about 2.4 GB after installation completes.

The VM will automatically reboot into a shell after installation. You can press `^]` to exit the VM's serial PTY console. To reattach use `virsh console pbot-vm`.

#### Set up serial ports
While the installation is in progress, switch to a terminal on your host system.

##### libvirt
Go into the `applets/pbot-vm/host/devices` directory and run the `add-serials` script to add the `serial-2.xml` and
`serial-3.xml` files to the configuration for the `pbot-vm` libvirt machine.

    host$ ./add-serials

This will enable the `/dev/ttyS2` and `/dev/ttyS3` serial ports in the guest and connect them
to the following TCP addresses on the host: `127.0.0.1:5555` and `127.0.0.1:5556`,
respectively. `ttyS2/5555` is the data channel used to send commands or code to the
virtual machine and to read back output. `ttyS3/5556` is simply a newline sent every
5 seconds, representing a heartbeat, used to ensure that the PBot communication
channel is healthy.

You may use the `PBOTVM_DOMAIN`, `PBOTVM_SERIAL` and `PBOTVM_HEART` environment variables to override
the default values. To use ports `7777` and `7778` instead:

    host$ PBOTVM_SERIAL=7777 PBOTVM_HEART=7778 ./add-serials

If you later want to change the serial ports or the TCP ports, execute the command
`virsh edit pbot-vm` on the host. This will open the `pbot-vm` XML configuration
in your default system editor. Find the `<serial>` tags and edit their attributes.

##### QEMU
Add `-chardev socket,id=charserial1,host=127.0.0.1,port=5555,server=on,wait=off -chardev socket,id=charserial2,host=127.0.0.1,port=5556,server=on,wait=off` to your `qemu` command-line arguments.

See full QEMU command-line arguments [here.](#qemu-command-from-libvirt)

#### Set up virtio-vsock
VM sockets (AF_VSOCK) are a Linux-specific feature (at the time of this writing). They
are the preferred way for PBot to communicate with the PBot VM Guest server. Serial communication
has several limitations. See https://vmsplice.net/~stefan/stefanha-kvm-forum-2015.pdf for an excellent
overview.

To use VM sockets with QEMU and virtio-vsock, you need:

* a Linux hypervisor with kernel 4.8+
* a Linux virtual machine on that hypervisor with kernel 4.8+
* QEMU 2.8+ on the hypervisor, running the virtual machine
* [socat](http://www.dest-unreach.org/socat/) version 1.7.4+

If you do not meet these requirements, the PBot VM will fallback to using serial communication. You may
explicitly disable VM sockets by setting `PBOTVM_CID=0`. You can skip reading the rest of this section.

If you do want to use VM sockets, read on.

First, ensure the `vhost_vsock` Linux kernel module is loaded on the host:

    host$ lsmod | grep vsock
    vhost_vsock            24576  1
    vsock                  45056  2 vmw_vsock_virtio_transport_common,vhost_vsock
    vhost                  53248  2 vhost_vsock,vhost_net

If the module is not loaded, load it with:

    host$ sudo modprobe vhost_vsock

Once the module is loaded, you should have the following character devices:

    host$ ls -l /dev/vhost-vsock
    crw------- 1 root root 10, 53 May  4 11:55 /dev/vhost-vsock
    host$ ls -l /dev/vsock
    crw-rw-rw- 1 root root 10, 54 May  4 11:55 /dev/vsock

A VM sockets address is comprised of a context ID (CID) and a port; just like an IP address and TCP/UDP port.
The CID is represented using an unsigned 32-bit integer. It identifies a given machine as either a hypervisor
or a virtual machine. Several addresses are reserved, including 0, 1, and the maximum value for a 32-bit
integer: 0xffffffff. The hypervisor is always assigned a CID of 2, and VMs can be assigned any CID between 3
and 0xffffffff — 1.

We must attach a `vhost-vsock-pci` device to the guest to enable VM sockets communication.
Each VM on a hypervisor must have a unique context ID (CID). Each service within the VM must
have a unique port. The PBot VM Guest defaults to `7` for the CID and `5555` for the port.

##### libvirt

While still in the `applets/pbot-vm/host/devices` directory, run the `add-vsock` script:

    host$ ./add-vsock

or to configure a different CID:

    host$ PBOTVM_CID=42 ./add-vsock

In the VM guest (once it reboots), there should be a `/dev/vsock` device:

    guest$ ls -l /dev/vsock
    crw-rw-rw- 1 root root 10, 55 May  4 13:21 /dev/vsock

##### QEMU

Add `-device {"driver":"vhost-vsock-pci","id":"vsock0","guest-cid":7,"vhostfd":"28","bus":"pci.7","addr":"0x0"}`
to your `qemu` command-line arguments.

See full QEMU command-line arguments [here.](#qemu-command-from-libvirt)

In the VM guest (once it reboots), there should be a `/dev/vsock` device:

    guest$ ls -l /dev/vsock
    crw-rw-rw- 1 root root 10, 55 May  4 13:21 /dev/vsock

#### Reboot virtual machine

* First ensure you set-up serial/vsock as described above! We are rebooting to ensure the new devices are loaded.

Fedora:

Once the Fedora installation completes inside the virtual machine, click the `Reboot` button
in the installer window. Login as `root` when the virtual machine boots back up.

Tumbleweed:

The Tumbleweed installer will automatically reboot to a shell after the installation. Login
as `root` and run `shutdown now -h`. Then run `virsh start pbot-vm`. (Using `shutdown now -r` to reboot
will not initialize the new serial/vsock devices.) Login as `root` when the virtual machine boots back up.

#### Install software
Now we can install any software and programming languages we want to make available
in the virtual machine. Use the `dnf search` or `zypper se` command or your distribution's documentation
to find packages. I will soon make available a script to install all package necessary for all
languages supported by PBot.

To make use of VM sockets, install the `socat` package:

Fedora:

    guest$ dnf install socat

OpenSUSE Tumbleweed:

    guest$ zypper in socat

For the C programming language you will need at least these:

Fedora:

    guest$ dnf install libubsan libasan gdb gcc clang

OpenSUSE Tumbleweed:

    guest$ zypper in libubsan1 libasan8 gdb gcc clang

Install packages for other languages as desired.

#### Install Perl
Now we need to install Perl on the guest. This allows us to run the PBot VM Guest server
script.

Fedora:

    guest$ dnf install perl-interpreter perl-lib perl-IPC-Run perl-JSON-XS perl-English perl-IPC-Shareable

OpenSUSE Tumbleweed:

    guest$ zypper in perl-IPC-Run perl-JSON-XS make gcc
    guest$ cpan i IPC::Shareable

This installs the minium packages for the Perl interpreter (note we used `perl-interpreter` instead of `perl`),
as well as a few Perl modules.

#### Install PBot VM Guest
Next we install the PBot VM Guest server script that fosters communication between the virtual machine guest
and the physical host system. We'll do this inside the virtual machine guest system, logged on as `root`
while in the `/tmp` directory.

    guest$ cd /tmp

The `rsync` command isn't installed with a Fedora minimal install, but `scp` is available. Replace
`192.168.100.42` below with your own local IP address; `user` with the user account that has the
PBot directory; and `pbot` with the path to the directory.

    guest$ scp -r user@192.168.100.42:~/pbot/applets/pbot-vm/guest .

Once that's done, run the following command:

    guest$ ./guest/bin/setup-guest

This will install `guest-server` to `/usr/local/bin/`, set up some environment variables and
harden the guest system. Additionally, it'll autodetect your chosen OS/distribution and attempt
to run any provisioning scripts from the `./guest/provision` directory. If no provisioning
scripts are available, it will warn you to manually install the packages for the `cc` languages
you want to use. You may use `./guest/provision/tumbleweed` as a reference.

After running the `setup-guest` script, we need to make the environment changes take effect:

    guest$ source /root/.bashrc

We no longer need the `/tmp/guest/` stuff. We can delete it:

    guest$ rm -rf guest/

#### Start PBot VM Guest
We're ready to start the PBot VM Guest server. On the guest, as `root`, execute the command:

    guest$ guest-server

This starts up a server to listen for incoming commands or code and to handle them. We'll leave
this running.

#### Test PBot VM Guest
Let's make sure everything's working up to this point. On the host, there should
be two open TCP ports on `5555` and `5556`. On the host, execute the command:

    host$ nc -zv 127.0.0.1 5555-5556

If it says anything other than `Connection succeeded` then make sure you have completed the steps
under [Set up serial ports](#set-up-serial-ports) and that your network configuration is allowing
access.

Let's make sure the PBot VM Guest server is listening for and can execute commands. The `vm-exec` command
allows you to send commands from the shell. Change your current working directory to `applets/pbot-vm/host/bin`
and run the `vm-exec` command:

    host$ cd applets/pbot-vm/host/bin
    host$ ./vm-exec -lang=sh echo hello world

This should output some logging noise followed by "hello world". You can test other language modules
by changing the `-lang=` option. I recommend testing and verifying that all of your desired language
modules are configured before going on to the next step.

If you have multiple PBot VM Guests, or if you used a different TCP port, you can specify the
`PBOTVM_SERIAL` environment variable when executing the `vm-exec` command:

    host$ PBOTVM_SERIAL=7777 ./vm-exec -lang=sh echo test

#### Save initial state
Switch back to an available terminal on the physical host machine. Enter the following command
to save a snapshot of the virtual machine waiting for incoming commands.

* Before doing this step, ensure all commands are cached by executing them at least once. For example, the `gcc` and `gdb` commands take a long time to load into memory. The initial execution may take a several long seconds to complete. Once completed, the command will be cached. Future invocations will execute significantly quicker.

<!-- -->

    host$ virsh snapshot-create-as pbot-vm 1

If the virtual machine ever times-out or its heartbeat stops responding, PBot
will revert the virtual machine to this saved snapshot.

### Initial virtual machine set-up complete
This concludes the initial one-time set-up. You can close the `virt-viewer` window. The
virtual machine will continue running in the background until it is manually shutdown (via
`shutdown now -h` inside the VM or via `virsh shutdown pbot-vm` on the host).

## Install Fortune package
The PBot VM Host server uses the `fortune` command to generate random STDIN input to use when no `-stdin`
argument is provided to the bot's `cc` command. Ensure you have it installed.

## Start PBot VM Host
To start the PBot VM Host server, change your current working directory to `applets/pbot-vm/host/bin`
and execute the `vm-server` script:

    host$ cd applets/pbot-vm/host/bin
    host$ ./vm-server

This will start a TCP server on port `9000`. It will listen for incoming commands and
pass them along to the virtual machine's TCP serial port `5555`. It will also monitor
the heartbeat port `5556` to ensure the PBot VM Guest server is alive.

You may override any of the defaults by setting environment variables. For example, to
use `other-vm` with a longer `30` second timeout, on different serial and heartbeat ports:

    host$ PBOTVM_DOMAIN="other-vm" PBOTVM_SERVER=9001 PBOTVM_SERIAL=7777 PBOTVM_HEART=7778 PBOTVM_TIMEOUT=30 ./vm-server

### Test PBot
All done. Everything is set up now.

PBot is already preconfigured with commands that invoke the `host/bin/vm-client`
script to send VM commands to `vm-server` on the default port `9000`:

     <pragma-> factshow sh
        <PBot> [global] sh: /call cc -lang=sh
     <pragma-> factshow cc
        <PBot> [global] cc: /call vm-client {"nick":"$nick:json","channel":"$channel:json","code":"$args:json"}
     <pragma-> factshow vm-client
        <PBot> [global] vm-client: pbot-vm/host/bin/vm-client [applet]

In your instance of PBot, the `sh echo hello` command should output `hello`.

    <pragma-> sh echo hello
       <PBot> hello

## QEMU command from libvirt
This is the QEMU command-line arguments used by libvirt. Extract flags as needed, e.g. `-chardev`.

    /usr/bin/qemu-system-x86_64 -name guest=pbot-vm,debug-threads=on -S -object {"qom-type":"secret","id":"masterKey0","format":"raw","file":"/var/lib/libvirt/qemu/domain-2-pbot-vm/master-key.aes"} -machine pc-q35-6.2,usb=off,vmport=off,dump-guest-core=off,memory-backend=pc.ram -accel kvm -cpu IvyBridge-IBRS,ss=on,vmx=on,pdcm=on,pcid=on,hypervisor=on,arat=on,tsc-adjust=on,umip=on,md-clear=on,stibp=on,arch-capabilities=on,ssbd=on,xsaveopt=on,ibpb=on,ibrs=on,amd-stibp=on,amd-ssbd=on,skip-l1dfl-vmentry=on,pschange-mc-no=on,aes=off,rdrand=off -m 2048 -object {"qom-type":"memory-backend-ram","id":"pc.ram","size":2147483648} -overcommit mem-lock=off -smp 2,sockets=2,cores=1,threads=1 -uuid ec9eebba-8ba1-4de3-8ec0-caa6fd808ad4 -no-user-config -nodefaults -chardev socket,id=charmonitor,fd=38,server=on,wait=off -mon chardev=charmonitor,id=monitor,mode=control -rtc base=utc,driftfix=slew -global kvm-pit.lost_tick_policy=delay -no-hpet -no-shutdown -global ICH9-LPC.disable_s3=1 -global ICH9-LPC.disable_s4=1 -boot strict=on -device {"driver":"pcie-root-port","port":16,"chassis":1,"id":"pci.1","bus":"pcie.0","multifunction":true,"addr":"0x2"} -device {"driver":"pcie-root-port","port":17,"chassis":2,"id":"pci.2","bus":"pcie.0","addr":"0x2.0x1"} -device {"driver":"pcie-root-port","port":18,"chassis":3,"id":"pci.3","bus":"pcie.0","addr":"0x2.0x2"} -device {"driver":"pcie-root-port","port":19,"chassis":4,"id":"pci.4","bus":"pcie.0","addr":"0x2.0x3"} -device {"driver":"pcie-root-port","port":20,"chassis":5,"id":"pci.5","bus":"pcie.0","addr":"0x2.0x4"} -device {"driver":"pcie-root-port","port":21,"chassis":6,"id":"pci.6","bus":"pcie.0","addr":"0x2.0x5"} -device {"driver":"pcie-root-port","port":22,"chassis":7,"id":"pci.7","bus":"pcie.0","addr":"0x2.0x6"} -device {"driver":"pcie-root-port","port":23,"chassis":8,"id":"pci.8","bus":"pcie.0","addr":"0x2.0x7"} -device {"driver":"pcie-root-port","port":24,"chassis":9,"id":"pci.9","bus":"pcie.0","multifunction":true,"addr":"0x3"} -device {"driver":"pcie-root-port","port":25,"chassis":10,"id":"pci.10","bus":"pcie.0","addr":"0x3.0x1"} -device {"driver":"pcie-root-port","port":26,"chassis":11,"id":"pci.11","bus":"pcie.0","addr":"0x3.0x2"} -device {"driver":"pcie-root-port","port":27,"chassis":12,"id":"pci.12","bus":"pcie.0","addr":"0x3.0x3"} -device {"driver":"pcie-root-port","port":28,"chassis":13,"id":"pci.13","bus":"pcie.0","addr":"0x3.0x4"} -device {"driver":"pcie-root-port","port":29,"chassis":14,"id":"pci.14","bus":"pcie.0","addr":"0x3.0x5"} -device {"driver":"qemu-xhci","p2":15,"p3":15,"id":"usb","bus":"pci.2","addr":"0x0"} -device {"driver":"virtio-serial-pci","id":"virtio-serial0","bus":"pci.3","addr":"0x0"} -blockdev {"driver":"file","filename":"/home/pbot/pbot-vms/openSUSE-Tumbleweed-Minimal-VM.x86_64-kvm-and-xen.qcow2","node-name":"libvirt-1-storage","auto-read-only":true,"discard":"unmap"} -blockdev {"node-name":"libvirt-1-format","read-only":false,"driver":"qcow2","file":"libvirt-1-storage","backing":null} -device {"driver":"virtio-blk-pci","bus":"pci.4","addr":"0x0","drive":"libvirt-1-format","id":"virtio-disk0","bootindex":1} -netdev {"type":"tap","fd":"39","vhost":true,"vhostfd":"41","id":"hostnet0"} -device {"driver":"virtio-net-pci","netdev":"hostnet0","id":"net0","mac":"52:54:00:03:16:5a","bus":"pci.1","addr":"0x0"} -chardev pty,id=charserial0 -device {"driver":"isa-serial","chardev":"charserial0","id":"serial0","index":0} -chardev socket,id=charserial1,host=127.0.0.1,port=5555,server=on,wait=off -device {"driver":"isa-serial","chardev":"charserial1","id":"serial1","index":2} -chardev socket,id=charserial2,host=127.0.0.1,port=5556,server=on,wait=off -device {"driver":"isa-serial","chardev":"charserial2","id":"serial2","index":3} -chardev socket,id=charchannel0,fd=37,server=on,wait=off -device {"driver":"virtserialport","bus":"virtio-serial0.0","nr":1,"chardev":"charchannel0","id":"channel0","name":"org.qemu.guest_agent.0"} -chardev spicevmc,id=charchannel1,name=vdagent -device {"driver":"virtserialport","bus":"virtio-serial0.0","nr":2,"chardev":"charchannel1","id":"channel1","name":"com.redhat.spice.0"} -device {"driver":"usb-tablet","id":"input0","bus":"usb.0","port":"1"} -audiodev {"id":"audio1","driver":"spice"} -spice port=5901,addr=127.0.0.1,disable-ticketing=on,image-compression=off,seamless-migration=on -device {"driver":"virtio-vga","id":"video0","max_outputs":1,"bus":"pcie.0","addr":"0x1"} -device {"driver":"ich9-intel-hda","id":"sound0","bus":"pcie.0","addr":"0x1b"} -device {"driver":"hda-duplex","id":"sound0-codec0","bus":"sound0.0","cad":0,"audiodev":"audio1"} -chardev spicevmc,id=charredir0,name=usbredir -device {"driver":"usb-redir","chardev":"charredir0","id":"redir0","bus":"usb.0","port":"2"} -chardev spicevmc,id=charredir1,name=usbredir -device {"driver":"usb-redir","chardev":"charredir1","id":"redir1","bus":"usb.0","port":"3"} -device {"driver":"virtio-balloon-pci","id":"balloon0","bus":"pci.5","addr":"0x0"} -object {"qom-type":"rng-random","id":"objrng0","filename":"/dev/urandom"} -device {"driver":"virtio-rng-pci","rng":"objrng0","id":"rng0","bus":"pci.6","addr":"0x0"} -loadvm 1 -sandbox on,obsolete=deny,elevateprivileges=deny,spawn=deny,resourcecontrol=deny -device {"driver":"vhost-vsock-pci","id":"vsock0","guest-cid":7,"vhostfd":"28","bus":"pci.7","addr":"0x0"} -msg timestamp=on
