# How can I install Ásbrú Connection Manager ?

**Ásbrú Connection Manager** is packaged for a large range of distributions.

We have 3 stages in our release process:

- Master : the greatest and latest stable version
- Snapshot : the next version to be released (aka the testing area)
- Loki : our development release with the most advanced features but not considered as stable so it is not recommended for production

Our master and the snapshots are being kept as stable as possible. New features for new major releases are being developed inside the "loki" branch.

Beware that [Loki](https://en.wikipedia.org/wiki/Loki) can sometimes behave in an unexpected manner to you.  This is somehow the same concept as the "[Debian sid](https://www.debian.org/releases/sid/)" release.

## Ubuntu
**Master release**

To install the latest release on a fresh [Ubuntu](https://www.ubuntu.com/) system, use the following instructions:

```
sudo apt-add-repository multiverse
sudo apt install curl
curl -s https://packagecloud.io/install/repositories/asbru-cm/asbru-cm/script.deb.sh | sudo bash
sudo apt install asbru-cm
```

**Snapshot release**

To install the latest snapshot for testing, use the following instructions:

```
sudo apt-add-repository multiverse
sudo apt install curl
curl -s https://packagecloud.io/install/repositories/asbru-cm/snapshots/script.deb.sh | sudo bash
sudo apt install asbru-cm
```

**Loki**

To test the latest development package, use the following instructions:

```
sudo apt-add-repository multiverse
sudo apt install curl
curl -s https://packagecloud.io/install/repositories/asbru-cm/loki/script.deb.sh | sudo bash
sudo apt install asbru-cm
```

## Mint
**Master release**

To install the latest release on a fresh [Mint](https://linuxmint.com/) system, use the following instructions:

```
curl -s https://packagecloud.io/install/repositories/asbru-cm/asbru-cm/script.deb.sh | sudo bash
sudo apt install asbru-cm
```

**Snapshot release**

To install the latest snapshot for testing, use the following instructions:

```
curl -s https://packagecloud.io/install/repositories/asbru-cm/asbru-cm/script.deb.sh | sudo bash
curl -s https://packagecloud.io/install/repositories/asbru-cm/snapshots/script.deb.sh | sudo bash
sudo apt install asbru-cm
```

**Loki**

To test the latest development package, use the following instructions:

```
curl -s https://packagecloud.io/install/repositories/asbru-cm/loki/script.deb.sh | sudo bash
sudo apt install asbru-cm
```

## Debian
**Master release**

To install the latest release on a fresh [Debian](https://www.debian.org/) system, use the following instructions:

```
sudo apt update
sudo apt install curl
curl -s https://packagecloud.io/install/repositories/asbru-cm/asbru-cm/script.deb.sh | sudo bash
sudo apt install asbru-cm
```

**Snapshot release**

To install the latest snapshot for testing, use the following instructions:

```
sudo apt update
sudo apt install curl
curl -s https://packagecloud.io/install/repositories/asbru-cm/snapshots/script.deb.sh | sudo bash
sudo apt install asbru-cm
```

**Loki**

To test the latest development package, use the following instructions:

```
sudo apt update
sudo apt install curl
curl -s https://packagecloud.io/install/repositories/asbru-cm/loki/script.deb.sh | sudo bash
sudo apt install asbru-cm
```

## Fedora
**Master release**

To install the latest release on a fresh [Fedora](https://getfedora.org/) system, use the following instructions:

```
curl -s https://packagecloud.io/install/repositories/asbru-cm/asbru-cm/script.rpm.sh | sudo bash
sudo dnf install asbru-cm
```

**Snapshot release**

To install the latest snapshot for testing, use the following instructions:

```
curl -s https://packagecloud.io/install/repositories/asbru-cm/snapshots/script.rpm.sh | sudo bash
sudo dnf install asbru-cm
```

**Loki**

To test the latest development package, use the following instructions:

```
curl -s https://packagecloud.io/install/repositories/asbru-cm/loki/script.rpm.sh | sudo bash
sudo dnf install asbru-cm
```

## Installation of legacy 5.x

If you need to install the legacy v5 version of Ásbrú Connection Manager (using Gtk2 library), the legacy packages are still available.

**Debian / Ubuntu**

```
curl -s https://packagecloud.io/install/repositories/asbru-cm/v5/script.deb.sh | sudo bash
sudo apt-get install asbru-cm
```

**Fedora**

```
curl -s https://packagecloud.io/install/repositories/asbru-cm/v5/script.rpm.sh | sudo bash
sudo dnf install asbru-cm
```

## Manual
If you don't want to use any of the pre-built package, here are instructions to start Ásbrú Connection Manager from the sources.

### Prerequisites

- Perl 5.22 or above (https://www.perl.org/)
- VTE 0.48 or above(GNOME Terminal Emulator widget, https://developer.gnome.org/vte/)
- Perl interface to the GNOME libraries (http://gtk2-perl.sourceforge.net/)
- OpenSSH client
- Telnet client
- FTP client

### Clone repository

```
$ git clone https://github.com/asbru-cm/asbru-cm.git
```

### Start application

```
$ cd asbru-cm
$ ./asbru-cm
```

### Additional information for Debian systems

If you are using a Debian-based system, here are the list of dependency package to install:

```
apt install perl libvte-2.91-0 libcairo-perl libglib-perl libpango-perl libsocket6-perl libexpect-perl libnet-proxy-perl libyaml-perl libcrypt-cbc-perl libcrypt-blowfish-perl libgtk3-perl libnet-arp-perl libossp-uuid-perl openssh-client telnet ftp libcrypt-rijndael-perl libxml-parser-perl libcanberra-gtk-module dbus-x11 libx11-guitest-perl libgtk3-simplelist-perl gir1.2-wnck-3.0 gir1.2-vte-2.91
```

### Legacy v5.x

For the records, the legacy v5.x version of Ásbrú Connection Manager was based on Gtk2.  Here are the list of packages to install

```
apt install perl gtk2-engines-pixbuf libvte9 libcairo-perl libgtk2-perl libglib-perl libpango-perl libgnome2-gconf-perl libsocket6-perl libexpect-perl libnet-proxy-perl libyaml-perl libcrypt-cbc-perl libcrypt-blowfish-perl libgtk2-perl libgtk2-gladexml-perl libgtk2-ex-simple-list-perl libnet-arp-perl libossp-uuid-perl openssh-client telnet ftp libcrypt-rijndael-perl libxml-parser-perl libgtk2-unique-perl
```

**Gnome2::Vte**

0) The VTE dev package is required to get Gnome2::Vte compiled for your environment

```
sudo apt install libvte-dev
```

1) Start CPAN shell

```
perl -MCPAN -e shell
```

2) The very fist time you start CPAN, it will ask you some questions.  Please chose the best option for your environement, in this example, we will assume the following choices:

```
Would you like to configure as much as possible automatically?   --> yes
What approach do you want?   --> sudo
```

3) In the CPAN shell, install Gnome2::Vte

```
cpan[1] > install Gnome2::Vte
```

This will download the latest version (0.11), compile it and install it under ```/usr/local/lib```.

4) Cleaning up:

(those steps are optional, think carefully about your own environment !  This may potentially break your system. **You have been warned**)

If you don't need the development packages anymore:

```
sudo apt purge libvte-dev
sudo apt autoremove
```

If it was the first time you used CPAN and you don't want to keep .cpan configuration, sources, etc.

```
rm -rf .cpan
```
