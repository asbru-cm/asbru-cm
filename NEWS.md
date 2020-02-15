# NEWS
Here you can find important news on the project

## 15.02.2020

Dear testers,

We have merged the codebase for version 6.1.0 into master. This release will bring some cleanups and a few new features which require testing.

These new features are:

* Support for SOCKS Proxy (for VNC/RDP/SSH/SFTP today) using [ncat](https://nmap.org/ncat/) for advanced cases
* Support for Jump Host (for SSH)

We would be happy if you can test the master snapshots as we would like to release the first official *rc1* build soon.

Attention: please make sure you have a safe copy of your configuration directory (which is ~/.config/pac) by default before proceeding with your tests.

Thanks and happy testing.

## 16.12.2019
* We are disabling the el-test repository. In future you will find the rpms for el7 and el8 in the main packagecloud repostory asbru-cm/asbru-cm
* gtk3 branch has been merged into master therefore we are disabling snapshot generation from the gtk3 branch.
