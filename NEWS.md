# NEWS
Here you can find important news on the project

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
