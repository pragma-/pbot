# Vagrant instructions

### Install libvirt and QEMU/KVM

Follow [PBot VM Prerequisites](../../../doc/VirtualMachine.md#prerequisites) up to the [libvirt and QEMU](../../../doc/VirtualMachine.md#libvirt-and-qemu)
section, then return to this guide.

### Install Vagrant

To install vagrant on openSUSE, use:

    zypper install --no-recommends vagrant vagrant-libvirt

Otherwise see https://vagrant-libvirt.github.io/vagrant-libvirt/installation.html for installation instructions for your platform.

### Install vagrant-libvirt

If your distribution does not have a `vagrant-libvirt` package or if you need an up-to-date version use Vagrant's plugin manager:

    vagrant plugin install vagrant-libvirt

### Start Vagrant Box

To start a virtual machine, `cd` into one of the PBot-VM Vagrant sub-directories and run the following command. This will download
the appropriate virtual machine image and automatically configure it as a PBot VM Guest.

    vagrant up

You may pass optional environment variables to override pbot-vm default configuration (see [PBot VM Environment Variables](../../../doc/VirtualMachine.md#environment-variables)):

    PBOTVM_SERIAL=7777 PBOTVM_HEART=7778 vagrant up

### Connect to Vagrant Box

    vagrant ssh

### Start PBot VM Guest Server

    sudo guest-server

Some distributions may require you to specify the full path:

    sudo /usr/local/bin/guest-server

### Start PBot VM Host Server

After starting the guest-server, you must now start the host server.

    ../host/bin/vm-server

### Test PBot VM

In your instance of PBot, the `sh` and `cc`, etc, commands should now produce output:

    <pragma-> sh echo Hello world!
       <PBot> Hello world!

### Shutdown Vagrant Box

    vagrant halt

### Destroy Vagrant Box

    vagrant destroy

### Delete Vagrant Box

    vagrant box list
    vagrant box remove <name>

### (Optional) Install Alternative Vagrant Box

To install an alternative Vagrant box with your preferred OS/distribution, search for one at https://app.vagrantup.com/boxes/search
and then make a new directory, e.g. FreeBSD-14, and copy one of the existing PBot-VM Vagrantfiles into
this directory, and then edit the `config.vm.box` line to point at the chosen OS/distribution, e.g. `freebsd/FreeBSD-14.0-CURRENT`.

Some boxes may have specific settings that you may need to copy over. To obtain and examine the box's Vagrantfile:

    vagrant init <OS/distribution>

Examples:

    vagrant init debian/testing64
    vagrant init debian/bookworm64
    vagrant init opensuse/Tumbleweed.x86_64
    vagrant init archlinux/archlinux
    vagrant init freebsd/FreeBSD-14.0-CURRENT
    vagrant init generic/openbsd7

Then use one of the existing PBot-VM Vagrantfiles as a guide for adjusting your alternative Vagrantfile.
