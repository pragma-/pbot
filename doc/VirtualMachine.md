# Virtual Machine

## About

PBot can interact with a virtual machine to safely execute arbitrary user-submitted
system commands and code.

This document will guide you through installing and configuring a virtual machine
by using the widely available [libvirt](https://libvirt.org) project tools, such as
`virt-install`, `virsh`, `virt-manager`, `virt-viewer`, etc.

Though there are many, many tutorials and walk-throughs available for these tools,
this guide will demonstrate the necessary `virt-install` and `virsh` commands to
configure the virtual machine.

You may install a guest Linux distribution of your choice. Any of the recent popular
Linux distributions should suffice. This guide will use Fedora Rawhide because
playing around with the latest bleeding-edge software is fun!

Then we will show you the necessary commands to configure the Linux guest system
to be able to communicate with PBot. Commands and code snippets are sent over a
virtual serial cable. We'll show you how to set that up.

We'll also show a few tips and tricks to help secure the virtual machine against
malicious user-submitted commands.

Let's get started.

## Creating a new virtual machine

## Configuring the virtual machine

## Installing Linux in the virtual machine

## Configuring Linux for PBot Communication

## Hardening the PBot virtual machine
