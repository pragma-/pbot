# Vagrant instructions

### Install Vagrant

To install vagrant on openSUSE, use:

    zypper install --no-recommends vagrant vagrant-libvirt

Otherwise see https://vagrant-libvirt.github.io/vagrant-libvirt/installation.html for installation instructions for your platform.

### Install vagrant-libvirt

If your distribution does not have a `vagrant-libvirt` package or if you need an up-to-date version use Vagrant's plugin manager:

    vagrant plugin install vagrant-libvirt

### Start Vagrant Box

To start a virtual machine, `cd` into one of the PBot-VM Vagrant sub-directories and run:

    vagrant up

You may pass optional environment variables to override pbot-vm default configuration (see [Virtual Machine](../../../doc/VirtualMachine.md)):

    PBOTVM_SERIAL=7777 PBOTVM_HEART=7778 vagrant up

### Shutdown Vagrant Box

    vagrant halt

### Destroy Vagrant Box

    vagrant destroy

### Delete Vagrant Box

    vagrant box list
    vagrant box remove <name>

### (Optional) Install Alterantive Vagrant Box

To install an alternative Vagrant box with your preferred OS/distribution, search for one at https://app.vagrantup.com/boxes/search
and then run the following command to download its Vagrantfile:

    vagrant init <OS/distribution>

Examples:

    vagrant init debian/testing64
    vagrant init debian/bookworm64
    vagrant init opensuse/Tumbleweed.x86_64
    vagrant init archlinux/archlinux
    vagrant init freebsd/FreeBSD-14.0-CURRENT
    vagrant init generic/openbsd7

Then use one of the existing PBot-VM Vagrantfiles as a guide for adjusting your alternative Vagrantfile.
