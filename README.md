# Ásbrú Connection Manager

[![Travis][travis-badge]][travis-url]
[![License][license-badge]][license-url]
[![RPM Packages][rpm-badge]][rpm-url]
[![Debian Packages][deb-badge]][deb-url]
[![Liberapay][liberapay-badge]][liberapay-url]
[![Donate Bitcoins][bitcoin-badge]][bitcoin-url]

[<img src="https://www.asbru-cm.net/assets/img/asbru-logo-200.png" align="right" width="200px" height="200px" />](https://asbru-cm.net)

## A free and open-source connection manager

**Ásbrú Connection Manager** is a user interface that helps organizing remote terminal sessions and automating repetitive tasks.

### Features

- Simple GUI to manage/launch connections to remote machines
- Scripting possibilities, 'ala' SecureCRT
- Configurable pre or post connection local commands execution
- Configurable list of macros (commands) to execute locally when connected or to send to connected client
- Configurable list of conditional executions on connected machine via 'Expect':
  - forget about SSH certificates
  - chain multiple SSH connections
  - automate tunnels creation
  - with line-send delay capabilities
- [KeePassXC](https://keepassxc.org/) integration
- Ability to connect to machines through a Proxy server
- Cluster connections
- Tabbed/Windowed terminals
- Wake On LAN capabilities
- Local and global variables, eg.: write down a password once, use it ANY where, centralizing its modification for faster changes! use them for:
  - password vault
  - reusing connection strings
- Seamless Gnome/Gtk integration
- Tray icon for 'right button' quick launching of managed connections. Screenshots and statistics.
- DEB, RPM and .TAR.GZ packages available

### Installation

We recommend installing Ásbrú Connection Manager using our latest pre-built packages hosted on [cloudsmith.io](https://cloudsmith.io/).

To do so, execute the following commands:

- Debian / Ubuntu

  ````
  curl -1sLf 'https://dl.cloudsmith.io/public/asbru-cm/release/cfg/setup/bash.deb.sh' | sudo -E bash
  sudo apt-get install asbru-cm
  ````

- Fedora

  ````
  curl -1sLf 'https://dl.cloudsmith.io/public/asbru-cm/release/cfg/setup/bash.rpm.sh' | sudo -E bash
  sudo dnf install asbru-cm
  ````

- Pacman-based (e.g. Arch Linux, Manjaro)

  ````
  git clone https://aur.archlinux.org/asbru-cm-git.git && cd asbru-cm-git
  makepkg -si
  ````
  
- MX Linux

  Ásbrú Connection Manager can be installed through the MX Package Installer under the Test Repo tab
  or by enabling the Test Repo and running
  ````
  sudo apt-get install asbru-cm
  ````
  
- Windows

  It is possible to run Asbru-CM on Windows 10 by enabling WSL and installing [Xming](http://www.straightrunning.com/XmingNotes/).
  The application [Asbru-CM Runner](https://github.com/SegiH/Asbru-CM-Runner) has detailed instructions on how to do this and allows you to run Asbru-CM on Windows 10 without a console window open in the background.
  
Once installed on your system, type ````asbru-cm```` in your terminal.

### Testing new features

Our master and the snapshots are being kept as stable as possible. New features for new major releases are being developed inside the "loki" branch.

Beware that [Loki](https://en.wikipedia.org/wiki/Loki) can sometimes behave in an unexpected manner to you.  This is somehow the same concept as the "[Debian sid](https://www.debian.org/releases/sid/)" release.

You are welcome to contribute and test by checking out "loki" or by installing our builds.

If you do not wish to run third party scripts on your systems, you can always access manual install instructions at https://cloudsmith.io/~asbru-cm/repos/loki/setup/

- Debian / Ubuntu

  ````
   curl -1sLf 'https://dl.cloudsmith.io/public/asbru-cm/loki/cfg/setup/bash.deb.sh' | sudo -E bash
  ````

- Fedora

  ````
   curl -1sLf 'https://dl.cloudsmith.io/public/asbru-cm/loki/cfg/setup/bash.rpm.sh' | sudo -E bash
  ````


### Installation of legacy 5.x

- Debian / Ubuntu

  ````
  $ curl -s https://packagecloud.io/install/repositories/asbru-cm/v5/script.deb.sh | sudo bash
  $ sudo apt-get install asbru-cm
  ````

- Fedora

  ````
  $ curl -s https://packagecloud.io/install/repositories/asbru-cm/v5/script.rpm.sh | sudo bash
  $ sudo dnf install asbru-cm
  ````


### Frequenty Asked Questions

- Why did you call that project "Ásbrú" ?

  In Norse mythology, [Ásbrú](https://en.wikipedia.org/wiki/Bifr%C3%B6st) refers to a burning rainbow bridge that connects Midgard (Earth) and Asgard, the realm of the gods.

- Is this a fork of PAC (Perl Auto Connector) Manager ?

  Yes.

  As [David Torrejon Vaquerizas](https://github.com/perseo22), the author of PAC Manager, could not find time, for some reasons that we respect, to continue the work on his project and was not open for external contributions ([see this](https://github.com/perseo22/pacmanager/issues/57)), a fork was needed to ensure the future and give the opportunity to the community to take over.

More questions can be found on the [dedicated project wiki page](https://github.com/asbru-cm/asbru-cm/wiki/Frequently-Asked-Questions).

### Contributing

If you want to contribute to Ásbrú Connection Manager, first check out the [issues](https://github.com/asbru-cm/asbru-cm/issues) and see if your request is not listed yet.  Issues and pull requests will be triaged and responded to as quickly as possible.

Before contributing, please review our [contributing doc](https://github.com/asbru-cm/asbru-cm/blob/master/CONTRIBUTING.md) for info on how to make feature requests and bear in mind that we adhere to the [Contributor Covenant code of conduct](https://github.com/asbru-cm/asbru-cm/blob/master/CODE_OF_CONDUCT.md).

### Financial support

If you like Ásbrú Connection Manager, you may also consider supporting the project financially by donating on <a title="Donate Liberapay" href="https://liberapay.com/asbru-cm/donate">Liberapay</a> or by donating to one of <a href="https://docs.asbru-cm.net/Contributing/Financial_Contribution/">our cryptocurrency addresses</a>.

### License

Ásbrú Connection Manager is licensed under the GNU General Public License version 3 <http://www.gnu.org/licenses/gpl-3.0.html>.  A full copy of the license can be found in the [LICENSE](https://github.com/asbru-cm/asbru-cm/blob/master/LICENSE) file.

### Sponsors

<a title="Cloudflare" href="https://cloudflare.com/"><img height="105" width="230" alt="Cloudflare" src="https://www.cloudflare.com/img/logo-web-badges/cf-logo-on-white-bg.svg" /></a>

### Packages

The repositories for our RPM and DEB builds are thankfully sponsored by [packagecloud](https://packagecloud.io/) and [Cloudsmith](https://cloudsmith.io). A great thanks to them.

<a title="Private Maven, RPM, DEB, PyPi and RubyGem Repository" href="https://packagecloud.io/"><img height="46" width="158" alt="Private Maven, RPM, DEB, PyPi and RubyGem Repository" src="https://packagecloud.io/images/packagecloud-badge.png" /></a>

<a href="https://cloudsmith.com/"><img height="46" widht="158" alt="Fast, secure development and distribution. Universal, web-scale package management" src="https://www.asbru-cm.net/assets/img/misc/cloudsmith-logo-color.png" /></a>

[travis-badge]: https://travis-ci.com/asbru-cm/asbru-cm.svg?branch=master
[travis-url]: https://travis-ci.com/asbru-cm/asbru-cm
[license-badge]: https://img.shields.io/badge/License-GPL--3-blue.svg?style=flat
[license-url]: LICENSE
[deb-badge]: https://img.shields.io/badge/Packages-Debian-blue.svg?style=flat
[deb-url]: https://packagecloud.io/asbru-cm/asbru-cm?filter=debs
[rpm-badge]: https://img.shields.io/badge/Packages-RPM-blue.svg?style=flat
[rpm-url]: https://packagecloud.io/asbru-cm/asbru-cm?filter=rpms
[liberapay-badge]: http://img.shields.io/liberapay/patrons/asbru-cm.svg?logo=liberapay
[liberapay-url]: https://liberapay.com/asbru-cm/donate
[bitcoin-badge]: https://img.shields.io/badge/bitcoin-19ZsvCafwRCwQSPcvfzgyiHD3Viptb4F45-D28138.svg?style=flat-square
[bitcoin-url]: https://blockchain.info/address/19ZsvCafwRCwQSPcvfzgyiHD3Viptb4F45
