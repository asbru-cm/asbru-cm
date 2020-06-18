# Ásbrú Connection Manager Documentation

[<img src="https://www.asbru-cm.net/assets/img/asbru-logo-200.png" align="right" width="200px" height="200px" />](https://asbru-cm.net)

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
- [KeePass](https://keepass.info/) database file (.kdbx) integration
- Ability to connect to machines through a proxy server
- Cluster connections
- Tabbed/Windowed terminals
- Wake On LAN capabilities
- Local and global variables, eg.: write down a password once, use it ANY where, centralizing its modification for faster changes! use them for:
    - password vault
    - reusing connection strings
- Seamless Gnome/Gtk integration
- Tray icon for 'right button' quick launching of managed connections. Screenshots and statistics.
- DEB, RPM and .TAR.GZ packages available

### Frequenty Asked Questions

- Why did you call that project "Ásbrú" ?

    In Norse mythology, [Ásbrú](https://en.wikipedia.org/wiki/Bifr%C3%B6st) refers to a burning rainbow bridge that connects Midgard (Earth) and Asgard, the realm of the gods.

- Is this a fork of PAC (Perl Auto Connector) Manager ?

    Yes.
  
    As [David Torrejon Vaquerizas](https://github.com/perseo22), the author of PAC Manager, could not find time, for some reasons that we respect, to continue the work on his project and was not open for external contributions ([see this](https://github.com/perseo22/pacmanager/issues/57)), a fork was needed to ensure the future and give the opportunity to the community to take over.
  
More questions can be found on the [dedicated project wiki page](https://github.com/asbru-cm/asbru-cm/wiki/Frequently-Asked-Questions).

### License

Ásbrú Connection Manager is licensed under the GNU General Public License version 3 <http://www.gnu.org/licenses/gpl-3.0.html>.  A full copy of the license can be found in the [LICENSE](https://github.com/asbru-cm/asbru-cm/blob/master/LICENSE) file.

### Packages

The repositories for our RPM and DEB builds are thankfully sponsored by [packagecloud](https://packagecloud.io/). A great thanks to them.

<a title="Private Maven, RPM, DEB, PyPi and RubyGem Repository" href="https://packagecloud.io/"><img height="46" width="158" alt="Private Maven, RPM, DEB, PyPi and RubyGem Repository" src="https://packagecloud.io/images/packagecloud-badge.png" /></a>
