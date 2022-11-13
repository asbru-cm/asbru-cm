#!/usr/bin/perl

###############################################################################
# This file is part of Ásbrú Connection Manager
#
# Copyright (C) 2020 Ásbrú Connection Manager team (https://asbru-cm.net)
#
# Ásbrú Connection Manager is free software: you can redistribute it and/or
# modify it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# Ásbrú Connection Manager is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License version 3
# along with Ásbrú Connection Manager.
# If not, see <http://www.gnu.org/licenses/gpl-3.0.html>.
###############################################################################

use strict;
use utf8;
binmode STDOUT, ":utf8";
binmode STDERR, ":utf8";

use FindBin qw ($RealBin $Bin $Script);
use lib "$RealBin/lib", "$RealBin/lib/ex", "$RealBin/lib/edit";

use Config;

our $VERBOSE        = $ARGV[2];
our $CFG_DIR        = $ENV{"ASBRU_CFG"};
our $BACKUP_DIR     = "bak";
our $CFG_FILE_NAME  = "asbru.yml";

if ($VERBOSE) {
    print STDERR "INFO: Executing migration from PAC to Ásbrú\n";
    print STDERR "INFO: $ARGV[0] , $ARGV[1]\n";
    print STDERR "INFO: RealBin = $RealBin\n";
}

if (!$ARGV[0] || !$ARGV[1]) {
    print STDERR "INFO: Migration aborted missing directories\n";
    exit 1;
}

migrate($ARGV[0], $ARGV[1]);

exit 0;

sub migrate {
    my ($old_dir, $new_dir) = @_;
    my ($ss);

    if ($VERBOSE) {
        print "INFO: Migration messages:\n";
        print "  - Show confirmation dialog\n";
    }
    my $resp = _wPopUP('Confirm', 'Ásbrú Migration Confirmation', setMessage("$old_dir.old"));
    if ($resp ne 'OK') {
        if ($resp eq 'NOT AVAILABLE') {
            print "WARN: Continue without gtk3 warning\n";
        } else {
            print "WARN: Ásbrú migration aborted\n";
            if ($old_dir =~ /\.migration/) {
                # Fix non standard config dir back to how it was
                if ($VERBOSE) {
                    print "  - Recover none standard directory $old_dir -> $new_dir\n";
                }
                system "$ENV{'ASBRU_ENV_FOR_EXTERNAL'} mv -f $old_dir $new_dir";
            }
            exit 1;
        }
    }
    if (-e $new_dir) {
        if ($VERBOSE) {
            print "  - $new_dir exists, we should not be here\n";
        }
        # Migrate only once
        return 0;
    }
    # Move saved dirs forward
    for (my $n = 8; $n >= 0; $n--) {
        my $m = $n+1;
        if (-e "$old_dir.old$n") {
            if (-e "$old_dir.old$m") {
                system "$ENV{'ASBRU_ENV_FOR_EXTERNAL'} rm -Rf $old_dir.old$m";
            }
            system "$ENV{'ASBRU_ENV_FOR_EXTERNAL'} mv -f $old_dir.old$n $old_dir.old$m";
        }
    }
    if (-e "$old_dir.old") {
        system "$ENV{'ASBRU_ENV_FOR_EXTERNAL'} mv -f $old_dir.old $old_dir.old0";
    }
    system "$ENV{'ASBRU_ENV_FOR_EXTERNAL'} cp -rfpL $old_dir $old_dir.old";
    if ($VERBOSE) {
        print "  - Create $new_dir\n";
    }
    system "$ENV{'ASBRU_ENV_FOR_EXTERNAL'} mv $old_dir $new_dir";
    foreach my $f ('pac.yml', 'pac_notray.notified', 'pac.pcc', 'pac.yml.gui', 'pac.yml.tree', 'pac_start.desktop', 'pac.dumper') {
        my $n = $f;
        $n =~ s/pac/asbru/;
        if (-e "$new_dir/$f") {
            if ($VERBOSE) {print "  - move $f -> $n\n";}
            system "$ENV{'ASBRU_ENV_FOR_EXTERNAL'} mv -f $new_dir/$f $new_dir/$n";
        }
    }
    foreach my $f ('pac_start.desktop') {
        my $n = $f;
        $n =~ s/pac/asbru/;
        if (-e "$new_dir/autostart/$f") {
            if ($VERBOSE) {
                print "  - mv $f -> $n\n";
            }
            system "$ENV{'ASBRU_ENV_FOR_EXTERNAL'} mv -f $new_dir/autostart/$f $new_dir/autostart/$n";
        }
    }
    # Rename Backups
    my $BACKUP_CFG_FILE  = "$CFG_DIR/$BACKUP_DIR/pac.yml";
    if ($VERBOSE) {
        print "  - Move backups\n";
    }
    for (my $n=0; $n < 10; $n++) {
        if (-e "$BACKUP_CFG_FILE.$n") {
            system "$ENV{'ASBRU_ENV_FOR_EXTERNAL'} mv -f $BACKUP_CFG_FILE.$n $CFG_DIR/$BACKUP_DIR/$CFG_FILE_NAME.$n";
        }
    }
    # Rename screenshost
    if ($VERBOSE) {
        print "  - Rename screenshots\n";
    }
    opendir($ss, "$new_dir/screenshots");
    while (my $f = readdir($ss)) {
        if ($f =~ /\.png/) {
            my $n = $f;
            $n =~ s/pac/asbru/;
            system "$ENV{'ASBRU_ENV_FOR_EXTERNAL'} mv -f $new_dir/screenshots/$f $new_dir/screenshots/$n";
        }
    }
    # Process pac.yml
    if ($VERBOSE) {
        print "  - Fix paths in asbru.yml\n";
    }
    open(YMLO, "<:utf8", "$new_dir/asbru.yml");
    open(YMLN, ">:utf8", "$new_dir/asbru.yml.new");
    while (my $l = <YMLO>) {
        if ($l =~ m|$old_dir|) {
            $l =~ s|$old_dir|$new_dir|;
        } elsif ($l =~ /pac_/) {
            $l =~ s|pac_|asbru_|g;
        }
        print YMLN $l;
    }
    close YMLO;
    close YMLN;
    system "$ENV{'ASBRU_ENV_FOR_EXTERNAL'} mv -f $new_dir/asbru.yml.new $new_dir/asbru.yml";
    # Remove nfreeze
    if ($VERBOSE) {print "  - Remove nfreeze files to be recreated\n";}
    system "$ENV{'ASBRU_ENV_FOR_EXTERNAL'} rm -f $new_dir/*.nfreeze";
    return 0;

    # Set warning message, do not worrie about tabs, spaces at the beggining
    # Pango markup is OK
    sub setMessage {
        my $dir = shift;
        my $msg = qq”Before you can use this version of Ásbrú Connection Manager, your configuration needs to be migrated.

        A backup copy of your original configuration will be created at : <b>$dir</b>

        You can downgrade from your package manager if the migration fails.

        You may click <b>Cancel</b> to stop this operation immediately,
        or <b>Continue</b> to start the migration.
        ”;

        if (!$VERBOSE) {
            $msg .= "\nTo see detailed messages during the migration process,\nrun <b><i>asbru-cm --verbose</i></b> in a terminal.\n";
        }

        return $msg;
    }
}

sub _wPopUP {
    my ($type, $title, $msg) = @_;
    my $PATH = "$RealBin/";

    $msg =~ s/\t//mg;
    $msg =~ s/^ +//mg;
    $msg =~ s/\n/&cr;/g;
    $msg =~ s/\"/&dquot;/g;
    $msg =~ s/\'/&squot;/g;
    return `'$^X' $PATH/asbru_confirm.pl '$type' '$title' '$msg' `;
}
