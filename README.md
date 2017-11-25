# Ásbrú Connection Manager

<img alt="Ásbrú Connection Manager" src="https://www.asbru-cm.net/assets/img/asbru-logo-200.png" style="float: right; width: 200px;">

## A free and open-source connection manager

Ásbrú Connection Manager is a user interface that helps organizing remote terminal sessions and automating repetitive tasks.

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
- [KeePassX](https://www.keepassx.org/) integration
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

We recommend installing Ásbrú Connection Manager using our latest pre-built packages hosted on [packagecould.io](https://packagecloud.io/).

To do so, execute the following commands:

- Debian / Ubuntu

  ````
  $ curl -s https://packagecloud.io/install/repositories/asbru-cm/asbru-cm/script.deb.sh | sudo bash
  $ sudo apt-get install asbru-cm
  ````

- Fedora

  ````
  $ curl -s https://packagecloud.io/install/repositories/asbru-cm/asbru-cm/script.rpm.sh | sudo bash
  $ sudo dnf install asbru-cm
  ````

- Arch / Manjaro

  ````
  yaourt -S asbru-cm-git
  ````

Once installed on your system, type ````/opt/asbru/asbru```` in your terminal.

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

### License

Ásbrú Connection Manager is licensed under the GNU General Public License version 3 <http://www.gnu.org/licenses/gpl-3.0.html>.  A full copy of the license can be found in the [LICENSE](https://github.com/asbru-cm/asbru-cm/blob/master/LICENSE) file.
