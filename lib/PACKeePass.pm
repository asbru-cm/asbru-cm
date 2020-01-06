package PACKeePass;

###############################################################################
# This file is part of Ásbrú Connection Manager
#
# Copyright (C) 2017-2019 Ásbrú Connection Manager team (https://asbru-cm.net)
# Copyright (C) 2010-2016 David Torrejon Vaquerizas
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

use utf8;
binmode STDOUT,':utf8';
binmode STDERR,':utf8';

$|++;

###################################################################
# Import Modules

# Standard
use strict;
use warnings;

use Encode;
use FindBin qw ($RealBin $Bin $Script);
use IPC::Open2;
use IPC::Open3;

# GTK
use Gtk3 '-init';

# PAC modules
use PACUtils;

# END: Import Modules
###################################################################

###################################################################
# Define GLOBAL CLASS variables

my $KPXC_MP = $ENV{'KPXC_MP'};

# END: Define GLOBAL CLASS variables
###################################################################

###################################################################
# START: Public class methods

sub new {
    my $class = shift;
    my $buildgui = shift;
    my $self;

    $self->{cfg} = shift;
    $self->{container} = undef;
    $self->{frame} = {};

    _testCapabilities($self);
    if ($buildgui) {
        _buildKeePassGUI($self);
    }

    bless($self, $class);
    return $self;
}

sub update {
    my $self = shift;
    my $cfg = shift;

    defined $cfg and $$self{cfg} = $cfg;

    my $file = $$self{cfg}{'database'};
    if (!defined $file) {
        return 0;
    }
    if ($$self{disable_keepassxc}) {
        $$self{cfg}{use_keepass} = 0;
    }
    $$self{frame}{fcbKeePassFile}->set_filename($file);
    $$self{frame}{hboxkpmain}->set_sensitive($$self{cfg}{use_keepass});
    if (!$$self{cfg}{use_keepass}) {
        return 1;
    }
    $$self{frame}{entryKeePassPassword}->set_text($$self{cfg}{'password'});
    $$self{frame}{cbUseKeePass}->set_active($$self{cfg}{use_keepass});
    $$self{frame}{hboxkpmain}->set_sensitive($$self{cfg}{use_keepass});
    if ($$self{cfg}{'password'}) {
        $KPXC_MP = $$self{cfg}{'password'};
        $ENV{'KPXC_MP'} = $$self{cfg}{'password'};
    } elsif (!$KPXC_MP) {
        # Get Password user
        getMasterPassword($self);
    }
    return 1;
}

sub getMasterPassword {
    my $self = shift;
    my $mp = '';

    while (!$mp) {
        $mp = _wEnterValue($self, 'KeePassX Integration', "Please, enter KeePassX MASTER password\nto unlock database file '$$self{cfg}{'database'}'", '', 0, 'pac-keepass');
        # Test Master Password
        if ($mp) {
            $KPXC_MP = $mp;
            my ($msg,$flg) = TestMasterKey($self,'a','b');
            if ((!$flg)&&($msg =~ /^Error/)) {
                $KPXC_MP='';
                $mp = '';
            }
        } else {
            last;
        }
    }
    $KPXC_MP = $mp;
    $ENV{'KPXC_MP'} = $mp;
    return $mp;
}

sub TestMasterKey {
    my ($s,$field,$uid) = @_;
    my ($pid,$cfg);
    my $ok = 0;
    my @err;
    my @out;

    if ($$s{cfg}) {
        $cfg = $$s{cfg};
    } else {
        $cfg = $s->get_cfg();
    }
    $pid = open3(*Writer,*Reader,*ErrReader,"keepassxc-cli show $$s{kpxc_show_protected} $$s{kpxc_keyfile_opt} $$cfg{database} '$uid'");
    print Writer "$KPXC_MP\n";
    close Writer;
    @out = <Reader>;
    @err = <ErrReader>;
    # Wait so we do not create zombies
    waitpid($pid,0);
    close Reader;
    close ErrReader;
    if ($?) {
        return ($err[0],0);
    }
    return ('',1);
}

sub GetFieldValueFromString {
    my ($s,$str) = @_;
    my ($ok,$value,$field,$uid,$flg,$cfg);

    if (!$str) {
        return ($str,1);
    }
    if ($str !~ /<\w+:\w+>/) {
        return ($str,1);
    }
    if ($$s{cfg}) {
        $cfg = $$s{cfg};
    } else {
        $cfg = $s->get_cfg();
    }
    $str =~ s/[<>]//g;
    ($field,$uid) = split /:/,$str;
    ($value,$flg) = $s->GetFieldValue($field,$uid);
    return ($value,$flg);
}

sub GetFieldValue {
    my ($s,$field,$uid) = @_;
    my ($pid,$cfg);
    my $data='';
    my @out;

    if ($$s{cfg}) {
        $cfg = $$s{cfg};
    } else {
        $cfg = $s->get_cfg();
    }
    if (!$KPXC_MP) {
        # Get Password from config file or from user
        if ($$cfg{password}) {
            $KPXC_MP = $$cfg{password};
        } else {
            $s->getMasterPassword();
            if (!$KPXC_MP) {
                # We could not get a valid password
                return ('Bad key/master password',0);
            }
        }
    }
    $pid = open2(*Reader,*Writer,"keepassxc-cli show $$s{kpxc_show_protected} $$s{kpxc_keyfile_opt} $$cfg{database} '$uid'");
    print Writer "$KPXC_MP\n";
    close Writer;
    @out = <Reader>;
    # Wait so we do not create zombies
    waitpid($pid,0);
    close Reader;
    foreach $data (@out) {
        $data =~ s/\n//g;
        if ($data =~ s/$field: *//i) {
            return ($data,1);
        }
    }
    return ('',0);
}

sub get_cfg {
    my $self = shift;

    my %hash;
    $hash{use_keepass} = $$self{frame}{'cbUseKeePass'}->get_active();
    $hash{database} = $$self{frame}{'fcbKeePassFile'}->get_filename();
    if (defined $$self{frame}{'fcbKeePassKeyFile'}) {
        $hash{keyfile} = $$self{frame}{'fcbKeePassKeyFile'}->get_filename();
        if (($$self{kpxc_keyfile})&&($hash{keyfile})&&(-e $hash{keyfile})) {
            $$self{kpxc_keyfile_opt} = "$$self{kpxc_keyfile} '$hash{keyfile}'";
        } else {
            $$self{kpxc_keyfile_opt} = '';
        }
    }
    $hash{password} = ($$self{frame}{'cbUseKeePass'}->get_active()) ? $$self{frame}{'entryKeePassPassword'}->get_chars(0, -1) : '';
    return \%hash;
}

# END: Public class methods
###################################################################

###################################################################
# START: Private functions definitions

sub _buildKeePassGUI {
    my $self = shift;

    my $cfg = $self->{cfg};
    my %w;

    # Build a vbox
    $w{vbox} = Gtk3::VBox->new(0,0);

    $w{cbUseKeePass} = Gtk3::CheckButton->new('Use KeePassXC');
    $w{vbox}->pack_start($w{cbUseKeePass}, 0, 1, 0);

    $w{hboxkpmain} = Gtk3::HBox->new(0, 0);
    $w{vbox}->pack_start($w{hboxkpmain}, 0, 1, 0);

    $w{hboxkpmain}->pack_start(Gtk3::Label->new('Database file:'), 0, 1, 0);

    $w{fcbKeePassFile} = Gtk3::FileChooserButton->new('','GTK_FILE_CHOOSER_ACTION_OPEN');
    $w{fcbKeePassFile}->set_show_hidden(1);
    $w{hboxkpmain}->pack_start($w{fcbKeePassFile}, 1, 1, 0);
    $w{hboxkpmain}->pack_start(Gtk3::Label->new('Master Password:'), 0, 1, 0);

    $w{entryKeePassPassword} = Gtk3::Entry->new;
    $w{hboxkpmain}->pack_start($w{entryKeePassPassword}, 0, 1, 0);
    $w{entryKeePassPassword}->set_visibility(0);

    if ($$self{kpxc_keyfile}) {
        $w{hboxkpmain}->pack_start(Gtk3::Label->new('Key File:'), 0, 1, 0);
        $w{fcbKeePassKeyFile} = Gtk3::FileChooserButton->new('','GTK_FILE_CHOOSER_ACTION_OPEN');
        $w{fcbKeePassKeyFile}->set_show_hidden(1);
        $w{hboxkpmain}->pack_start($w{fcbKeePassKeyFile}, 0, 1, 0);
    }
    my $usage =  Gtk3::Label->new();
    $usage->set_halign('start');
    $w{vbox}->pack_start($usage, 0, 1, 0);

    $$self{container} = $w{vbox};
    $$self{frame} = \%w;

    $w{cbUseKeePass}->signal_connect('toggled', sub {
        $w{hboxkpmain}->set_sensitive($w{cbUseKeePass}->get_active);
    });
    if ($$self{disable_keepassxc}) {
        $usage->set_markup("\n\n<b>keepassxc-cli</b> Not installed, integration disabled");
        $w{cbUseKeePass}->set_sensitive(0);
        $w{cbUseKeePass}->set_active(0);
        $w{hboxkpmain}->set_sensitive(0);
    } else {
        my $capabilities;
        if ($$self{kpxc_keyfile}) {
            $capabilities .= "<b>Use Key File</b> Enabled\n";
        } else {
            $capabilities .= "<b>Use Key File</b> Disabled (update to latest version)\n";
        }
        if ($$self{kpxc_show_protected}) {
            $capabilities .= "<b>Protected passwords</b> Yes\n";
        } else {
            $capabilities .= "<b>Protected passwords</b> No\n";
        }
        $usage->set_markup("\n\n<b>keepassxc-cli</b> Version $$self{kpxc_version}\n\n$capabilities");
    }
    $w{hboxkpmain}->set_sensitive($$self{cfg}{use_keepass});
    return 1;
}

sub _testCapabilities {
    my $self = shift;
    my ($c);

    $$self{kpxc_keyfile} = '';
    $$self{kpxc_show_protected} = '';
    $$self{kpxc_keyfile_opt} = '';
    $$self{kpxc_version} = `keepassxc-cli -v 2>/dev/null`;
    $$self{kpxc_version} =~ s/\n//g;
    if (!$$self{kpxc_version}) {
        $$self{disable_keepassxc} = 1;
        return 0;
    }
    $c = `keepassxc-cli -h`;
    $$self{disable_keepassxc} = 0;
    if ($c =~ /--key-file/) {
        $$self{kpxc_keyfile} = '--key-file';
    }
    if ($c =~ /--show-protected/) {
        $$self{kpxc_show_protected} = '--show-protected';
    }
    if ((defined $$self{cfg})&&($$self{kpxc_keyfile})&&($$self{cfg}{keyfile})&&(-e $$self{cfg}{keyfile})) {
        $$self{kpxc_keyfile_opt} = "$$self{kpxc_keyfile} '$$self{cfg}{keyfile}'";
    }
}

# END: Private functions definitions
###################################################################

1;
