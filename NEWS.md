# NEWS

Here you can find important news on the project

## 13.11.2022

We are pleased to announce a new version (6.4.0) of Ásbrú Connection Manager that brings some new important features:

- Support for AppImage ([#804](https://github.com/asbru-cm/asbru-cm/issues/804))
- Add "postpend" command ([#850](https://github.com/asbru-cm/asbru-cm/issues/850))
- Support vendor configuration ([#860](https://github.com/asbru-cm/asbru-cm/pull/860))
- Add SSH option that create random SOCKS tunnel on connection startup ([#771](https://github.com/asbru-cm/asbru-cm/issues/771))

And other improvements or bugfixes:

- Sort open connections alphabetically in the "Goto Tabs" submenu ([#962](https://github.com/asbru-cm/asbru-cm/issues/962))
- Support configuration directory to be in a smb/cifs shared directory ([#909](https://github.com/asbru-cm/asbru-cm/issues/909))
- Programatically send string only when Idle ([#902](https://github.com/asbru-cm/asbru-cm/pull/902))
- Show nicer warning when a tunnel has already be open in another terminal ([#862](https://github.com/asbru-cm/asbru-cm/pull/863))
- Rearrange authentication user/password and manual mode ([#788](https://github.com/asbru-cm/asbru-cm/issues/788))
- Improve display of keybindings ([#787](https://github.com/asbru-cm/asbru-cm/issues/787))
- Improve show/hide connections list behaviour ([#786](https://github.com/asbru-cm/asbru-cm/issues/786))
- Show better error message when KeePassXC lookup fails ([#770](https://github.com/asbru-cm/asbru-cm/issues/770))
- Support for Crypt::CBC 3.04 ([#816](https://github.com/asbru-cm/asbru-cm/issues/816))
- Display local port when showing jump server command line ([#982](https://github.com/asbru-cm/asbru-cm/issues/982))
- Accept 0 as port number for Jump Server ([#888](https://github.com/asbru-cm/asbru-cm/issues/888))
- Fix tray icon ([#870](https://github.com/asbru-cm/asbru-cm/issues/870))
- Allow multiple copy/paste of the same node, with mouse ([#729](https://github.com/asbru-cm/asbru-cm/issues/729))
- Fix read of KeePass file in a folder with cyrillic letter ([#859](https://github.com/asbru-cm/asbru-cm/issues/859))
- Do not reset connection list when removing an element from a cluster ([#862](https://github.com/asbru-cm/asbru-cm/pull/862))

Please share this information so we can get even more contributors to continue our efforts making Ásbrú Connection Manager even better !

## 21.05.2022

We are pleased to announce a bug fix release (6.3.3) of Ásbrú Connection Manager that addresses several issues:

- Closing one tab in cluster disconnects whole cluster ([#634](https://github.com/asbru-cm/asbru-cm/pull/634))
- Power Cluster Controller (PCC) can't close multiple exploded tabs ([#791](https://github.com/asbru-cm/asbru-cm/pull/791))
- Error when using an entry of a KeePass database with a pipe ("|") on title ([#794](https://github.com/asbru-cm/asbru-cm/pull/794))
- KeepassXC password exposed on asbru-cm local shell terminal ([#801](https://github.com/asbru-cm/asbru-cm/pull/801))
- Add support for PubkeyAcceptedKeyTypes option ([#853](https://github.com/asbru-cm/asbru-cm/pull/853))
- Can't close tab after doing split-unsplit ([#871](https://github.com/asbru-cm/asbru-cm/pull/871))
- SFTP via jumphost to target with private key instead of password doesn't work ([#913](https://github.com/asbru-cm/asbru-cm/pull/913))
- Settings password set if dialogs canceled ([#922](https://github.com/asbru-cm/asbru-cm/pull/922))
- Support for KeepassXC 2.7.0 (and above) ([#924](https://github.com/asbru-cm/asbru-cm/pull/924))

Please share this information so we can get even more contributors to continue our efforts making Ásbrú Connection Manager even better !

## 27.02.2021

We are pleased to announce a bug fix release (6.3.2) of Ásbrú Connection Manager that addresses several issues:

- Better install instructions for Pacman-based distribution ([#784](https://github.com/asbru-cm/asbru-cm/pull/784))
- Blank window when starting iconified ([#783](https://github.com/asbru-cm/asbru-cm/issues/783))
- Install issue on older Debian-based distribution ([#782](https://github.com/asbru-cm/asbru-cm/issues/782))

Please share this information so we can get even more contributors to continue our efforts making Ásbrú Connection Manager even better !

## 22.02.2021

We are pleased to announce a bug fix release (6.3.1) of Ásbrú Connection Manager that addresses several minor issues:

- Maximized connections list in compact layout ([#778](https://github.com/asbru-cm/asbru-cm/issues/778))
- Issues when using a configuration directory that contains a space ([#777](https://github.com/asbru-cm/asbru-cm/issues/777))
- Do not depend on nmap but ncat ([#776](https://github.com/asbru-cm/asbru-cm/issues/776))
- Explode/ReTab in Power Cluster Controller ([#775](https://github.com/asbru-cm/asbru-cm/issues/775))
- Empty clusters view on startup ([#753](https://github.com/asbru-cm/asbru-cm/issues/753))

Please share this information so we can get even more contributors to continue our efforts making Ásbrú Connection Manager even better !

## 16.02.2021

We are pleased to announce a new version (6.3.0) of Ásbrú Connection Manager that brings some new important features:

- Support for custom key bindings (fixes [#556](https://github.com/asbru-cm/asbru-cm/issues/556) [#285](https://github.com/asbru-cm/asbru-cm/issues/285) [#43](https://github.com/asbru-cm/asbru-cm/issues/43) [#590](https://github.com/asbru-cm/asbru-cm/issues/590) [#543](https://github.com/asbru-cm/asbru-cm/issues/543))
- Start all connections of a selected group ([#534](https://github.com/asbru-cm/asbru-cm/issues/534))
- Use KeePass for Host and IP of jump and proxy server ([#470](https://github.com/asbru-cm/asbru-cm/issues/470))
- Support for drag and drop connections into groups ([#167](https://github.com/asbru-cm/asbru-cm/issues/167))
- Support for default port in SSH connections ([#754](https://github.com/asbru-cm/asbru-cm/issues/754))
- Support for infinite scrollback ([#739](https://github.com/asbru-cm/asbru-cm/issues/739))

And other improvements or bugfixes:

- Improve jump server and mosh support (fixes [#470](https://github.com/asbru-cm/asbru-cm/issues/470) [#490](https://github.com/asbru-cm/asbru-cm/issues/490) [#424](https://github.com/asbru-cm/asbru-cm/issues/424))
- Ensure focus is set on terminal when right-clicking on it ([#604](https://github.com/asbru-cm/asbru-cm/issues/604))
- Add option to print timestamp in session logs ([#603](https://github.com/asbru-cm/asbru-cm/issues/603))
- Set focus to RDP terminals when entering the embed window ([#148](https://github.com/asbru-cm/asbru-cm/issues/148), [#638](https://github.com/asbru-cm/asbru-cm/issues/638))
- Support KeePass in global network settings ([#639](https://github.com/asbru-cm/asbru-cm/issues/639))
- Align buttons and layout in the "info" tab
- Toggle display when entering/leaving the connections list when on the info tab ([#683](https://github.com/asbru-cm/asbru-cm/issues/683))
- Fix regression when cleaning up terminal escape sequences
- Process right clicks correctly when several nodes are selected ([#617](https://github.com/asbru-cm/asbru-cm/issues/617))
- Fix panel refresh when terminal method is changed
- Fix exception when closing a failed remote desktop connection
- Can't enter User / Password for new SSH-Connection using generic command ([#735](https://github.com/asbru-cm/asbru-cm/issues/735))

Please share this information so we can get even more contributors to continue our efforts making Ásbrú Connection Manager even better !

## 07.11.2020

We are pleased to announce a bug fix release (6.2.2) of Ásbrú Connection Manager that addresses several issues.

Most important to note is the move from Packagecloud to Cloudsmith for several reasons. We will be keeping the Packagecloud repository alive for some time. However new OS releases will only be published to Cloudsmith.

Please check our [Installinstructions](https://docs.asbru-cm.net) for information on the new repositories.

## 06.06.2020

We are pleased to announce a bug fix release (6.2.1) of Ásbrú Connection Manager that addresses the following issues:

- Fix edit of generic commands - [#625](https://github.com/asbru-cm/asbru-cm/issues/625)
- Resolve KeePass connection password when pasted with shortcut key - [#627](https://github.com/asbru-cm/asbru-cm/issues/627)
- Escape VNC password properly - [#641](https://github.com/asbru-cm/asbru-cm/issues/641)

Please share this information so we can get even more contributors to continue our efforts making Ásbrú Connection Manager even better !

## 15.05.2020

We are pleased to announce a new version (6.2.0) of Ásbrú Connection Manager that brings some new important features:

- Review KeePass database file support (now based on [keepassxc-cli](https://keepassxc.org/))
- Add 4 themes (default, color, dark, system)
- Support for your own custom themes
- Add access to online help (https://docs.asbru-cm.net)
- Migrate legacy `.config/pac` configuration directory to `.config/asbru`
- Improve user interface
- Support for terminal zoom in/out
- Support copy/paste in "Get command line" dialog
- Improve anonymized export
- Many other minor bug fixes & enhancements

Please share this information so we can get even more contributors to continue our efforts making Ásbrú Connection Manager even better !

## 15.02.2020

Dear testers,

We have merged the codebase for version 6.1.0 into master. This release will bring some cleanups and a few new features which require testing.

These new features are:

* Support for SOCKS Proxy (for VNC/RDP/SSH/SFTP today) using [ncat](https://nmap.org/ncat/) for advanced cases
* Support for Jump Host to simplify SSH tunneling for VNC/RDP/SSH connections.

We would be happy if you can test the master snapshots as we would like to release the first official *rc1* build soon.

Attention: please make sure you have a safe copy of your configuration directory (which is ~/.config/pac) by default before proceeding with your tests.

Thanks and happy testing.

## 16.12.2019

* We are disabling the el-test repository. In future you will find the rpms for el7 and el8 in the main packagecloud repostory asbru-cm/asbru-cm
* gtk3 branch has been merged into master therefore we are disabling snapshot generation from the gtk3 branch.
