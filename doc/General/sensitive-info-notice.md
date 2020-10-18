## Sensitive information 

### Using 'hidden' flag in GUI

When a user sets a string as 'hidden' in 'EXPECT', then in config or in backups of config (i.e. $HOME/.config/pac/bak/asbru.yml.0) there're strings like '53616c7-omited-848993645' inplace. These strings represent user input encoded, not encrypted.

### GUI password

GUI password does NOT encrypts your config entries - it alters only GUI window & startup - GUI window asks for a password.

There is no real protection of your sensitive data provided by Ásbrú. It is simply encoded but can be decoded easily.

### Keep config files safe (and better use KeePassXC) 

We strongly discourage you from storing any sensitive data in 'EXPECT' fields. And if you do, you should consider the .yml configuration (and the backup copies) with adequate care.

For sensitive data, we recommend to store them into KeePass and retrieve the information you need using the new (6.2) KeePass integration module, see https://docs.asbru-cm.net/Manual/Preferences/KeePassXC/.
