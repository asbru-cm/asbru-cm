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
use PACTree;

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
    if ((!defined $file)||(-d $file)||(!-e $file)) {
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

sub getUseKeePass {
    my $self = shift;

    return $$self{cfg}{use_keepass} // 0;
}

sub getMasterPassword {
    my $self = shift;
    my $mp = '';

    while (!$mp) {
        $mp = _wEnterValue($self, 'KeePassXC Integration', "Please, enter KeePassX MASTER password\nto unlock database file '$$self{cfg}{'database'}'", '', 0, 'pac-keepass');
        # Test Master Password
        if ($mp) {
            $KPXC_MP = $mp;
            my ($msg,$flg) = testMasterKey($self,'a','ASBRUKeePassXCTEST');
            if ((!$flg)&&($msg !~ /ASBRUKeePassXCTEST/)) {
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

sub testMasterKey {
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
    $pid = open3(*Writer,*Reader,*ErrReader,"keepassxc-cli show $$s{kpxc_show_protected} $$s{kpxc_keyfile_opt} '$$cfg{database}' '$uid'");
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

sub getFieldValueFromString {
    my ($s,$str) = @_;
    my ($ok,$value,$field,$uid,$flg,$cfg);

    if (!$str) {
        return ($str,1);
    }
    if ($str !~ /<.+?\|.+>/) {
        return ($str,1);
    }
    if ($$s{cfg}) {
        $cfg = $$s{cfg};
    } else {
        $cfg = $s->get_cfg();
    }
    $str =~ s/[<>]//g;
    ($field,$uid) = split /\|/,$str;
    ($value,$flg) = $s->getFieldValue($field,$uid);
    return ($value,$flg);
}

sub regexTransform {
    my ($s,$field,$uid) = @_;

    my ($value,$flg) = $s->getFieldValue($field,$uid);
    if ($flg) {
        return $value;
    }
    return '';
}

sub getFieldValue {
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
    $pid = open2(*Reader,*Writer,"keepassxc-cli show $$s{kpxc_show_protected} $$s{kpxc_keyfile_opt} '$$cfg{database}' '$uid'");
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
    if ((!defined $hash{database})||(-d $hash{database})||(!-e $hash{database})) {
        $hash{database} = '';
    }
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

sub listEntries {
    my $self = shift;
    my $parent = shift;
    my ($mp,$list,%w,$entry);

    # Create the dialog window,
    $w{window}{data} = Gtk3::Dialog->new_with_buttons(
        "KeePassXC Search",
        undef,
        'modal',
        'gtk-cancel' => 'cancel',
        'gtk-ok' => 'ok'
    );
    # and setup some dialog properties.
    $w{window}{data}->set_default_response('ok');
    $w{window}{data}->set_position('center');
    $w{window}{data}->set_icon_name('pac-app-big');
    $w{window}{data}->set_resizable(1);
    $w{window}{data}->set_default_size(600,400);
    $w{window}{data}->set_resizable(0);
    $w{window}{data}->set_border_width(5);

    $w{window}{gui}{vbox} = Gtk3::VBox->new(0, 0);
    $w{window}{data}->get_content_area->pack_start($w{window}{gui}{vbox}, 1, 1, 5);
    $w{window}{gui}{vbox}->set_border_width(0);

    # Create an HBox to contain a picture and a label
    $w{window}{gui}{hbox} = Gtk3::HBox->new(0, 0);
    $w{window}{gui}{vbox}->pack_start($w{window}{gui}{hbox}, 0, 0, 0);
    $w{window}{gui}{hbox}->set_border_width(0);

    # Create 1st label
    $w{window}{gui}{lblsearch} = Gtk3::Label->new('Keywords');
    $w{window}{gui}{hbox}->pack_start($w{window}{gui}{lblsearch}, 0, 0, 0);

    # Search Entry
    $w{window}{gui}{entry} = Gtk3::Entry->new;
    $w{window}{gui}{hbox}->pack_start($w{window}{gui}{entry}, 0, 0, 0);
    $w{window}{gui}{entry}->set_activates_default(1);
    $w{window}{gui}{entry}->set_visibility(1);
    $w{window}{gui}{scroll1} = Gtk3::ScrolledWindow->new;
    $w{window}{gui}{scroll1}->set_policy('automatic', 'automatic');
    $w{window}{gui}{vbox}->pack_start($w{window}{gui}{scroll1}, 1, 1, 1);

    $w{window}{gui}{treelist} = PACTree->new('Entry:' => 'markup');
    $w{window}{gui}{scroll1}->add($w{window}{gui}{treelist});
    $w{window}{gui}{treelist}->set_enable_tree_lines(0);
    $w{window}{gui}{treelist}->set_headers_visible(1);
    $w{window}{gui}{treelist}->set_enable_search(1);
    $w{window}{gui}{treelist}->set_has_tooltip(0);
    $w{window}{gui}{treelist}->set_grid_lines('GTK_TREE_VIEW_GRID_LINES_NONE');
    # Implement a "TreeModelSort" to auto-sort the data
    #my $sort_model_conn = Gtk3::TreeModelSort->new_with_model($w{window}{gui}{treelist}->get_model);
    #$w{window}{gui}{treelist}->set_model($sort_model_conn);
    #$sort_model_conn->set_default_sort_func(\&__treeSort, $$self{_CFG});
    $w{window}{gui}{treelist}->get_selection->set_mode('GTK_SELECTION_SINGLE');
    @{$w{window}{gui}{treelist}{'data'}}=();

    $w{window}{gui}{entry}->signal_connect('key_release_event' => sub {
        my ($widget, $event) = @_;
        my @list = ();

        if (length($widget->get_text())>2) {
            @{$w{window}{gui}{treelist}{'data'}}=();
            @list = $self->_locateEntries($widget->get_text());
            foreach my $el (@list) {
                if ($el !~ qw|^/|) {
                    next;
                }
                $el =~ s/\n//g;
                $el = decode('UTF-8',$el);
                push(@{$w{window}{gui}{treelist}{'data'}},{value => [ $el ],children => []});
            }
        }
    });
    $w{window}{gui}{treelist}->signal_connect('row_activated' => sub {
        my $selection = $w{window}{gui}{treelist}->get_selection;
        my $model = $w{window}{gui}{treelist}->get_model;
        my @paths = _getSelectedRows($selection);
        $entry = $model->get_value($model->get_iter($paths[0]),0);
        $w{window}{data}->response(0);
        return 1;
    });

    # Show the window (in a modal fashion)
    $w{window}{data}->set_transient_for($parent);
    $w{window}{data}->show_all;

    my $ok = $w{window}{data}->run;

    if ($ok eq 'ok') {
        my $selection = $w{window}{gui}{treelist}->get_selection;
        my $model = $w{window}{gui}{treelist}->get_model;
        my @paths = _getSelectedRows($selection);
        $entry = $model->get_value($model->get_iter($paths[0]),0);
    }

    $w{window}{data}->destroy;

    while (Gtk3::events_pending) {
        Gtk3::main_iteration;
    }

    return $entry;
}

sub setRigthClickMenuEntry {
    my ($s,$win,$what,$input,$menu_items) = @_;
    my ($lbl,$field);

    if (!$s->getUseKeePass()) {
        return 0;
    } elsif (!$what) {
        return 0;
    }
    foreach $field (split /,/,$what) {
        $lbl = ucfirst($field);

        push(@$menu_items, {
            label => "Add $lbl KeePassXC",
            tooltip => "KeePassXC $lbl",
            code => sub {
                my $pos = $input->get_property('cursor_position');
                my $selection = $s->listEntries($win);
                if ($selection) {
                    $input->insert_text("<$field|$selection>", -1, $input->get_position);
                }
            }
        });
    }
    return 1;
}

# END: Public class methods
###################################################################

###################################################################
# START: Private functions definitions

sub _locateEntries {
    my ($s,$str) = @_;
    my ($pid,$cfg);
    my @out;

    $str =~ s/[\'\"]//g;
    if ($$s{cfg}) {
        $cfg = $$s{cfg};
    } else {
        $cfg = $s->get_cfg();
    }
    {
        no warnings 'once';
        open(SAVERR,">&STDERR");
        open(STDERR,"> /dev/null");
        $pid = open2(*Reader,*Writer,"keepassxc-cli locate $$s{kpxc_keyfile_opt} '$$cfg{database}' '$str'");
        print Writer "$KPXC_MP\n";
        close Writer;
        @out = <Reader>;
        # Wait so we do not create zombies
        waitpid($pid,0);
        close Reader;
        open(STDERR,">&SAVERR");
    };

    return @out;
}

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
    $c = `keepassxc-cli show -á 2>&1`;
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

__END__

=encoding utf8

=head1 NAME

PACKeePass.pm

=head1 SYNOPSIS

Handles integration to KeePassXC using : keepassxc-cli

    $kpxc = PACKeePass->new(OPT_BG);
    OPT_BG = [0|1]
             1 : Create object and Build GUI to configure
             0 : Create object to access available methods

=head1 DESCRIPTION

=head2

Important object variables

    $KPXC_MP : holds the current database master password

=head2 sub update

Updates configuration settings from current selections in gui

=head2 sub getMasterPassword

Routine to ask for master password to user, infinite retries or cancel to exit

=head2 sub testMasterKey

Connects to database with an unknown field value to test if response is:

    Error : Could not connect, so password is wrong
    Could not find XXXXXX uuid, so it could connect

=head2 sub getFieldValueFromString

Check if string has the correct format <field|uuid>

    false: return dame string
    true : extract field and uuid and call getFieldValue(field,uuid)

=head2 sub regexTransform

Use this method inside a regex expression to replace keepassxc ocurrences in a string

Usage:

    $str =~ s/<(.+?)\|(.+?)>/$kpxc->regexTransform($1,$2)/ge;

=head2 sub getFieldValue

Connect to database and query field value, return value or empty if not found

=head2 sub get_cfg

Recover settings from current GUI configuration

head2 sub listEntries

Build a window with a search entry and a listbox, show results from search entry in the listbox

    call _locateEntries on each typed key by user (3 characters are required to start the search)

Allow user to select a row and return the selected key path

head2 sub _locateEntries

Query the complete database for a search pattern and show the entries found in a listbox

