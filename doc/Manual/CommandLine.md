# Command Line

This section explains how to start Ásbrú from the command line and the available options.

!!! tip "start from the command line"
    Starting asbru-cm from the command line helps you to detect possible errors if the application:  crashes, freezed or behaves in un expected ways.

    This messages will be help full at the time to report a bug.

## asbru-cm

To start execute : `./asbru-cm` or `perl asbru-cm`

```
Usage: asbru-cm [options]
Options:
	--help : show this message
	--config-dir=path : absolute '/path' or relative 'path' to ~/.config/
	--no-backup : do no create alternative config files as a backup (faster shutdown)
	--start-shell : start a local terminal
	--password=<pwd> : automatically logon with given password without prompting user
	--start-uuid=<uuid>[:<cluster] : start connection in cluster (if given)
	--edit-uuid=<uuid> : edit connection
	--dump-uuid=<uuid> : dump data for given connection
	--scripts : open scripts window
	--start-script=<script> : start given script
	--preferences : open global preferences dialog
	--quick-conn : open the Quick Connect dialog on startup
	--list-uuids : list existing connections/groups and their UUIDs
	--no-splash : no splash screen on startup
	--iconified : go to tray once started
	--readonly : start in read only mode (no config changes allowed)
	--verbose : display more debugging information

See 'man asbru' for additional information.

```

## Options

We will detail options that might need additional detail or have some useful uses.

### --config-dir

Let's you start asrbu-cm using a different configuration path.

This path could be a shared directory or it can be used to creates tests etc.

Path can be a relative or absolute path

+ __Relative paths__ to : `/home/user/.config`
+ __Absolute paths__ : Any path defined from root

Example usage:

Start asbru-cm with test connections

`perl asbru-cm --config-dir=asbru.test`

Will open or create a complete config directory in : `/home/user/.config/asbru.test`

Start asru-cm with a set of completely new settings

`perl asbru-cm --config-dir=/home/user/asbru.new`

Will open or create a complete config directory in : `/home/user/asbru.new`

### --start-shell

Start asbru-cm and launch a shell after loading.

### --password

If you defined a lock password for asbru-cm, this option allows you to pass that password to asbru-cm so it does not asks for it.

### --verbose

Display more information to help debug an issue.

## Execution example

__Use default configuration__

```
perl asbru-cm

INFO: Ásbrú Connection Manager 6.2.0 (asbru-cm) started with PID 2247
INFO: Desktop environment detected : cinnamon
INFO: Config directory is '/home/xxxx/.config/asbru'
INFO: Used config file '/home/xxxx/.config/asbru/asbru.nfreeze'
INFO: Virtual terminal emulator (VTE) version is 0.52
INFO: Theme directory is '/home/xxxx/asbru-cm/res/themes/default'
INFO: Using Gnome tray icon
```

__Use test configuration__

```
perl asbru-cm --verbose --config-dir=asbru.test

INFO: Ásbrú Connection Manager 6.2.0 (asbru-cm) started with PID 4522
INFO: Desktop environment detected : cinnamon
INFO: Config directory is '/home/xxxx/.config/asbru.test'
INFO: Used config file '/home/xxxx/.config/asbru.test/asbru.nfreeze'
INFO: Virtual terminal emulator (VTE) version is 0.52
       - has_bright = 1
       - major_version = 0
       - minor_version = 52
       - vte_feed_binary = 1
       - vte_feed_child = 0
INFO: Theme directory is '/home/xxxx/asbru-cm/res/themes/asbru-color'
INFO: Using Gnome tray icon

```
