# What's new about Ásbrú Connection Manager ?
Here you can find important news on the project

## 12.04.2020

Dear testers,

We are about to merge a change (see [#515](https://github.com/asbru-cm/asbru-cm/pull/515)) that will require your attention as it may have some impact on your working environment.

This change is related to [#182](https://github.com/asbru-cm/asbru-cm/issues/182) and will basically rename the default configuration file from ```~/.config/pac``` to ```~/.config/asbru``` to move forward in the rebranding of the forked application.

As of version 6.2.0, that is under testing in our ["loki" branch](https://github.com/asbru-cm/asbru-cm#testing-new-features), you will be required to migrate your existing configuration to the new file layout.

At application startup, a warning message will give you the opportunity to think twice about it.

We believe we did everything to make this as smooth and transparent as possible.

But what you may want to understand:

* Nothing will be lost
* A safe copy of your existing configuration will be done to ```~/.config/pac.old```
* Older versions of Ásbrú will not be able to read that new configuration
* When starting an old version (6.0 or higher), you can use ```--config-dir ~/.config/pac.old``` to use your old configuration
* When starting an old version (6.1.x), Ásbrú will propose to downgrade your migrated configuration or recover your old configuration
* Upgrade and downgrade scripts are available in the ```utils``` directory

Please comme issue [#569](https://github.com/asbru-cm/asbru-cm/issues/569) if you have any concern with this change ; or simply thumb it up if you understand what will happen in the next days and are ready to test this to ensure a proper release of 6.2.0.

Happy Easter testing !

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
