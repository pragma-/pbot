# Vagrant instructions

### Install libvirt and QEMU/KVM

Follow [PBot VM Prerequisites](../../../doc/VirtualMachine.md#prerequisites) up to the [libvirt and QEMU](../../../doc/VirtualMachine.md#libvirt-and-qemu-1)
section, then return to this guide. If you've reached the section about making
a `pbot-vm` user, adding yourself to the `libvirt` group or downloading any ISOs
then you've read too far!

### Install Vagrant

To install vagrant on openSUSE, use:

    zypper install --no-recommends vagrant

Otherwise see https://vagrant-libvirt.github.io/vagrant-libvirt/installation.html for installation instructions for your platform.

### Install vagrant-libvirt

    vagrant plugin install vagrant-libvirt

### Start Vagrant Box

To start a virtual machine, `cd` into one of the PBot-VM Vagrant sub-directories and run the following command. This will download
the appropriate virtual machine image and automatically configure it as the default PBot VM Guest, `pbot-vm` described by
[`host/config/vm-exec.json`](../host/config/vm-exec.json):

    vagrant up

You may pass optional environment variables to override pbot-vm default configuration (see [PBot VM Environment Variables](../../../doc/VirtualMachine.md#environment-variables)).
For example, to create `pbot-test-vm` described by [`host/config/vm-exec.json`](../host/config/vm-exec.json):

    PBOTVM_DOMAIN=pbot-test-vm PBOTVM_SERIAL=7777 PBOTVM_HEALTH=7778 vagrant up

### Connect to Vagrant Box

Use SSH to connect to the PBot VM Guest:

    vagrant ssh

If you specified a `PBOTVM_DOMAIN`, e.g. `pbot-test-vm`, you must specify it:

    PBOTVM_DOMAIN=pbot-test-vm vagrant ssh

### Start PBot VM Guest Server

Once connected to the PBot VM Guest via SSH, start `guest-server` in the background:

    sudo nohup guest-server &> log &

Some distributions may require you to specify the full path:

    sudo nohup /usr/local/bin/guest-server &> log &

### Disconnect from Vagrant Box

Now you can type `logout` to exit the PBot VM Guest.

### Create snapshot of PBot VM Guest

After you've logged out of the PBot VM Guest with `guest-server` running in the background, create a snapshot. This allows PBot to revert to a known good state when a command times out.
If a `PBOTVM_DOMAIN` was defined, replace `pbot-vm` with that name.

    virsh -c qemu:///system snapshot-create-as pbot-vm 1

### Edit vm-exec.json

If you used `vagrant up` without specifying a `PBOTVM_DOMAIN`, you must edit the [`../host/config/vm-exec.json`](../host/config/vm-exec.json)
configuration file to set the `vagrant` value to `1` for the `pbot-vm` machine.

If you have specified a `PBOTVM_DOMAIN`, ensure the appropriate entries exist in the `vm-exec.json` configuration file.

By default, `pbot-test-vm` already has `vagrant` set to `1`.

### Start PBot VM Host Server

    cd ../host/bin/
    ./vm-server

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
