#!/bin/bash
# Rigenera po/asbru-cm.pot dai sorgenti, aggiorna i .po esistenti e
# compila i .mo in res/locale/<lingua>/LC_MESSAGES/asbru-cm.mo.
# Uso (dalla radice del repository): po/update-pot.sh
set -e
cd "$(dirname "$0")/.."

VERSION=$(grep -oP "APPVERSION = '\K[^']+" lib/PACUtils.pm)

xgettext --from-code=UTF-8 --language=Perl --keyword= --keyword=_t \
    --add-comments=TRANSLATORS --sort-by-file \
    --package-name=asbru-cm --package-version="$VERSION" \
    --msgid-bugs-address=https://github.com/asbru-cm/asbru-cm/issues \
    -o po/perl.pot asbru-cm lib/*.pm lib/edit/*.pm lib/method/*.pm
xgettext --from-code=UTF-8 --language=Glade -o po/glade.pot res/asbru.glade
msgcat --use-first po/perl.pot po/glade.pot -o po/asbru-cm.pot
rm -f po/perl.pot po/glade.pot

for po in po/*.po; do
    [ -e "$po" ] || continue
    lang=$(basename "$po" .po)
    msgmerge --quiet --update --backup=none "$po" po/asbru-cm.pot
    mkdir -p "res/locale/$lang/LC_MESSAGES"
    msgfmt --check -o "res/locale/$lang/LC_MESSAGES/asbru-cm.mo" "$po"
done
