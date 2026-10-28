# Translations

Ásbrú uses gettext (text domain `asbru-cm`).

- Perl code marks user visible strings with `_t('...')`; strings with
  variables use `sprintf(_t('... %s ...'), $value)`.
- `res/asbru.glade` strings are translated through `Gtk3::Builder`
  (`_gladeBuilder()` in `PACUtils.pm`). Combo box items stay untranslated:
  their text is stored in the configuration and compared in the code.
- Compiled catalogs are installed in `res/locale/<lang>/LC_MESSAGES/asbru-cm.mo`.
  `Locale::gettext` is optional: without it the interface stays in English.

## Updating

```bash
po/update-pot.sh
```

regenerates `po/asbru-cm.pot`, merges it into every `po/<lang>.po` and
compiles the `.mo` files.

## Adding a language

```bash
msginit --input=po/asbru-cm.pot --locale=de_DE.UTF-8 --output=po/de.po
# translate po/de.po, then
po/update-pot.sh
```

Leave empty the entries that are values rather than text (`22`, `/bin/bash`,
`<<ASK_PASS>>`, internal variable names, ...).
