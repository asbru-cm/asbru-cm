# Redistributing Ásbrú Connection Manager

When redistributing Ásbrú Connection Manager (e.g acting as a vendor), you can customize some aspects of it to better accomodate the specific distribution/environment you are distributing it on.

## Customizing Default Configuration

You can override the default options that are loaded on the first start without having to provide a full configuration file, overriding only the options you need to override.

To do this, create a YAML file on path (relative to project root) `vendor/asbru-conf-default-overrides.yml`.

To discourage accidental usage of this pattern, the YAML document must contain the configurations inside the root key `__PAC__EXPORTED__PARTIAL_CONF`.

An example of this file that changes the default fonts to `Ubuntu Mono 12` is as follows:

```yaml
---
__PAC__EXPORTED__PARTIAL_CONF:
  defaults:
    info font: Ubuntu Mono 12
    terminal font: Ubuntu Mono 12
    tree font: Ubuntu Mono 12
```

Since this file is used as a source before the application's hard-coded default options, you can also use it to store connections or any other configuration which normally resides in the `asbru.yml` configuration file.
