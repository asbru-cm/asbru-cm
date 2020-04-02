package PACKeePass;

###############################################################################
# This file is part of Ásbrú Connection Manager
#
# Copyright (C) 2017-2020 Ásbrú Connection Manager team (https://asbru-cm.net)
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
my @KPXC_LIST;
my %KPXC_CACHE = ();
my $CLI = 'keepassxc-cli';

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
    $self->{'last_timestamp'} = '';

    _setCapabilities($self);
    if ($buildgui) {
        _buildKeePassGUI($self);
    }

    bless($self, $class);
    return $self;
}

sub isKeePassMask {
    my ($class, $str) = @_;
    return $str =~ /<.\w+\|.+?>/;
}

# END: Public class methods
###################################################################

###################################################################
# START: Public object methods

sub update {
    my $self = shift;
    my $cfg = shift;

    defined $cfg and $$self{cfg} = $cfg;

    my $file = $$self{cfg}{'database'};
    my $pathcli = $$self{cfg}{'pathcli'} // '';
    my $key = $$self{cfg}{'keyfile'};
    if ((!defined $file)||(-d $file)||(!-e $file)) {
        return 0;
    }
    if (!-e $pathcli) {
        $pathcli = '';
    }
    if ($$self{disable_keepassxc}) {
        $$self{cfg}{use_keepass} = 0;
    }
    $$self{frame}{fcbKeePassFile}->set_filename($file);

    if ($pathcli) {
        $$self{frame}{fcbCliFile}->set_filename($pathcli);
        $CLI = $pathcli;
    }
    if ($key) {
        $$self{frame}{fcbKeePassKeyFile}->set_filename($key);
        $$self{kpxc_keyfile_opt} = "--key-file '$key'";
    }
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
    }
    return 1;
}

sub getUseKeePass {
    my $self = shift;

    return $$self{cfg}{use_keepass} // 0;
}

sub getMasterPassword {
    my $self = shift;
    my $parent = shift;
    my $mp = '';

    while (!$mp) {
        $mp = _wEnterValue($parent, 'KeePass database', "Enter your MASTER password to unlock\nyour KeePass file '$$self{cfg}{'database'}'", '', 0, 'asbru-keepass');
        # Test Master Password
        if ($mp) {
            $KPXC_MP = $mp;
            my ($msg, $flg) = testMasterKey($self, 'a', 'ASBRUKeePassXCTEST');
            if (!$flg && $msg !~ /ASBRUKeePassXCTEST/) {
                $KPXC_MP='';
                $mp = '';
                _wMessage($parent,"<b>keepassxc-cli message</b>\n\n$msg");
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
    my ($self, $field, $uid) = @_;
    my ($pid,$cfg);
    my $ok = 0;
    my @err;
    my @out;

    if ($$self{cfg}) {
        $cfg = $$self{cfg};
    } else {
        $cfg = $self->get_cfg();
    }
    $pid = open3(*Writer, *Reader, *ErrReader, "$CLI $$self{kpxc_cli} show $$self{kpxc_show_protected} $$self{kpxc_keyfile_opt} '$$cfg{database}' '$uid'");
    print Writer "$KPXC_MP\n";
    close Writer;
    @out = <Reader>;
    @err = <ErrReader>;
    # Wait so we do not create zombies
    waitpid($pid,0);
    close Reader;
    close ErrReader;
    if (@err) {
        my $msg = join('',@err);
        return (decode('utf8',$msg),0);
    }
    return ('',1);
}

sub getFieldValueFromString {
    my ($self, $str) = @_;
    my ($ok, $value, $field, $uid, $flg, $cfg);

    if (!$str) {
        return ($str, 1);
    }
    if (!PACKeePass->isKeePassMask($str)) {
        return ($str, 1);
    }
    if ($$self{cfg}) {
        $cfg = $$self{cfg};
    } else {
        $cfg = $self->get_cfg();
    }
    $str =~ s/[<>]//g;
    ($field, $uid) = split /\|/, $str;
    ($value, $flg) = $self->getFieldValue($field, $uid);
    return ($value, $flg);
}

sub regexTransform {
    my ($self, $field, $uid) = @_;

    my ($value, $flg) = $self->getFieldValue($field, $uid);
    if ($flg) {
        return $value;
    }
    return '';
}

sub applyMask {
    my ($self, $value) = @_;
    $value =~ s/<(\w+)\|(.+?)>/$self->regexTransform($1, $2)/eg;
    return $value;
}

sub getFieldValue {
    my ($self, $field, $uid) = @_;
    my ($pid, $cfg,@err);
    my $data='';
    my $flg = 0;
    my @out;

    $field = lc($field);
    if ($KPXC_CACHE{"$field,$uid"}) {
        return ($KPXC_CACHE{"$field,$uid"}, 1);
    }
    if ($$self{cfg}) {
        $cfg = $$self{cfg};
    } else {
        $cfg = $self->get_cfg();
    }
    if (!$KPXC_MP) {
        # Get Password from config file or from user
        if ($$cfg{password}) {
            $KPXC_MP = $$cfg{password};
        } else {
            $self->getMasterPassword();
            if (!$KPXC_MP) {
                # We could not get a valid password
                return ('Bad key/master password',0);
            }
        }
    }
    $pid = open3(*Writer, *Reader, *ErrReader, "$CLI $$self{kpxc_cli} show $$self{kpxc_show_protected} $$self{kpxc_keyfile_opt} '$$cfg{database}' '$uid'");
    print Writer "$KPXC_MP\n";
    close Writer;
    @out = <Reader>;
    @err = <ErrReader>;
    # Wait so we do not create zombies
    waitpid($pid, 0);
    close Reader;
    close ErrReader;
    foreach $data (@out) {
        $data =~ s/\n//g;
        if ($data =~ /(username|password|url|title): (.*)/i) {
            my $f = lc ($1);
            my $v = $2;
            $KPXC_CACHE{"$f,$uid"} = $v;
        }
    }
    if ($KPXC_CACHE{"$field,$uid"}) {
        return ($KPXC_CACHE{"$field,$uid"}, 1);
    }
    return ('', 0);
}

sub get_cfg {
    my $self = shift;
    my $from_pref = shift;

    my %hash;
    $hash{use_keepass} = $$self{frame}{'cbUseKeePass'}->get_active();
    $hash{database} = $$self{frame}{'fcbKeePassFile'}->get_filename();
    $hash{pathcli} = $$self{frame}{'fcbCliFile'}->get_filename();
    $hash{keyfile} = $$self{frame}{'fcbKeePassKeyFile'}->get_filename();
    if ((!defined $hash{database})||(-d $hash{database})||(!-e $hash{database})) {
        $hash{database} = '';
        $$self{disable_keepassxc} = 1;
    }
    if (($$self{kpxc_keyfile})&&($hash{keyfile})&&(-e $hash{keyfile})) {
        $$self{kpxc_keyfile_opt} = "$$self{kpxc_keyfile} '$hash{keyfile}'";
    } else {
        $$self{kpxc_keyfile_opt} = '';
    }
    $hash{password} = ($$self{frame}{'cbUseKeePass'}->get_active()) ? $$self{frame}{'entryKeePassPassword'}->get_chars(0, -1) : '';
    if ($$self{disable_keepassxc}) {
        # Avoid saving information that will not work
        if ($from_pref && $hash{use_keepass}) {
            _wMessage($PACMain::FUNCS{_CONFIG}{_WINDOWCONFIG},"KeePassXC was disabled, information was incomplete");
        }
        $hash{use_keepass} = 0;
        $hash{database} = '';
        $hash{pathcli} = '';
        $hash{keyfile} = '';
        $hash{password} = '';
        $$self{kpxc_keyfile_opt} = '';
        $self->_updateUsage(1);
    }
    return \%hash;
}

sub listEntries {
    my $self = shift;
    my $parent = shift;
    my ($mp,$list,%w,$entry);

    if (!$KPXC_MP) {
        # Get Password user
        getMasterPassword($self, $parent);
    }
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
    $w{window}{data}->set_icon_name('asbru-app-big');
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
    $w{window}{gui}{lblsearch} = Gtk3::Label->new('Search database:');
    $w{window}{gui}{hbox}->pack_start($w{window}{gui}{lblsearch}, 0, 0, 5);

    # Search Entry
    $w{window}{gui}{entry} = Gtk3::Entry->new();
    $w{window}{gui}{hbox}->pack_start($w{window}{gui}{entry}, 0, 0, 0);
    $w{window}{gui}{entry}->set_activates_default(1);
    $w{window}{gui}{entry}->set_visibility(1);
    $w{window}{gui}{scroll1} = Gtk3::ScrolledWindow->new();
    $w{window}{gui}{scroll1}->set_policy('automatic', 'automatic');
    $w{window}{gui}{vbox}->pack_start($w{window}{gui}{scroll1}, 1, 1, 1);

    $w{window}{gui}{treelist} = PACTree->new('Matching entries:' => 'text');
    $w{window}{gui}{scroll1}->add($w{window}{gui}{treelist});
    $w{window}{gui}{treelist}->set_enable_tree_lines(0);
    $w{window}{gui}{treelist}->set_headers_visible(1);
    $w{window}{gui}{treelist}->set_enable_search(1);
    $w{window}{gui}{treelist}->set_has_tooltip(0);
    $w{window}{gui}{treelist}->set_grid_lines('GTK_TREE_VIEW_GRID_LINES_NONE');
    $w{window}{gui}{treelist}->get_selection()->set_mode('GTK_SELECTION_SINGLE');
    @{$w{window}{gui}{treelist}{'data'}} = ();

    $w{window}{gui}{entry}->signal_connect('key_release_event' => sub {
        my ($widget, $event) = @_;
        my @list = ();

        if (length($widget->get_text())>0) {
            @{$w{window}{gui}{treelist}{'data'}} = ();
            @list = $self->_locateEntries($widget->get_text());
            foreach my $el (@list) {
                if ($el !~ qw|^/|) {
                    next;
                }
                $el =~ s/\n//g;
                $el = decode('UTF-8', $el);
                push(@{$w{window}{gui}{treelist}{'data'}}, {value => [ $el ], children => []});
            }
        }
    });
    $w{window}{gui}{treelist}->signal_connect('row_activated' => sub {
        my $selection = $w{window}{gui}{treelist}->get_selection();
        my $model = $w{window}{gui}{treelist}->get_model();
        my @paths = _getSelectedRows($selection);
        $entry = $model->get_value($model->get_iter($paths[0]),0);
        $w{window}{data}->response(0);
        return 1;
    });

    # Show the window (in a modal fashion)
    $w{window}{data}->set_transient_for($parent);
    $w{window}{data}->show_all();

    my $ok = $w{window}{data}->run();

    if ($ok eq 'ok') {
        my $selection = $w{window}{gui}{treelist}->get_selection();
        my $model = $w{window}{gui}{treelist}->get_model();
        my @paths = _getSelectedRows($selection);
        $entry = $model->get_value($model->get_iter($paths[0]),0);
    }

    $w{window}{data}->destroy();

    while (Gtk3::events_pending) {
        Gtk3::main_iteration();
    }

    return $entry;
}

sub setRigthClickMenuEntry {
    my ($self, $win, $what, $input, $menu_items) = @_;
    my ($lbl,$field);

    if (!$self->getUseKeePass()) {
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
                my $selection = $self->listEntries($win);
                if ($selection) {
                    if ($field eq 'url') {
                        $input->set_text("<$field|$selection>");
                    } else {
                        $input->insert_text("<$field|$selection>", -1, $input->get_position);
                    }
                }
            }
        });
    }
    return 1;
}

sub hasKeePassField {
    my $self = shift;
    my $cfg = shift;
    my $uuid = shift;
    my $useKeePass = $$cfg{defaults}{keepass}{use_keepass} && $uuid ne '__PAC_SHELL__';
    my $kpxc;

    if (!$useKeePass) {
        return 0;
    }

    foreach my $fieldName ('user', 'pass', 'passphrase', 'passphrase user', 'ip', 'proxy pass' , 'proxy user') {
        if ($self->isKeePassMask($$cfg{'environments'}{$uuid}{$fieldName})) {
            return 1;
        }
    }

    foreach my $exp (@{$$cfg{'environments'}{$uuid}{'expect'}}) {
        if ($self->isKeePassMask($$exp{'send'})) {
            return 1;
        }
    }

    return 0;
}

# END: Public object methods
###################################################################

###################################################################
# START: Private functions definitions

sub _locateEntries {
    my ($self, $str) = @_;
    my ($pid,$cfg);
    my $timestamp;
    my @out;

    if ($$self{cfg}) {
        $cfg = $$self{cfg};
    } else {
        $cfg = $self->get_cfg();
    }
    $timestamp = (stat($$cfg{database}))[9];
    if (!@KPXC_LIST || $$self{'last_timestamp'} != $timestamp) {
        @KPXC_LIST = ();
        $$self{'last_timestamp'} = $timestamp;
        {
            no warnings 'once';
            open(SAVERR,">&STDERR");
            open(STDERR,"> /dev/null");
            $pid = open2(*Reader,*Writer,"$CLI $$self{kpxc_cli} locate $$self{kpxc_keyfile_opt} '$$cfg{database}' '/'");
            print Writer "$KPXC_MP\n";
            close Writer;
            @KPXC_LIST = <Reader>;
            # Wait so we do not create zombies
            waitpid($pid,0);
            close Reader;
            open(STDERR,">&SAVERR");
        };
    }
    @out = sort grep(/$str/i,@KPXC_LIST);
    return @out;
}

sub _buildKeePassGUI {
    my $self = shift;
    my $cfg = $self->{cfg};
    my %w;
    my $width = 150;

    # Build a vbox
    $w{vbox} = Gtk3::VBox->new(0,0);

    # Attach to class attribute
    $$self{container} = $w{vbox};
    $$self{frame} = \%w;

    # Option to activate KeePass use (or not)
    $w{cbUseKeePass} = Gtk3::CheckButton->new('Activate use of a KeePass database file');
    $w{cbUseKeePass}->set_margin_top(10);
    $w{cbUseKeePass}->set_margin_bottom(5);
    $w{cbUseKeePass}->set_halign('GTK_ALIGN_START');

    # Build 'help' button
    $w{help} = Gtk3::LinkButton->new('https://docs.asbru-cm.net/Manual/Preferences/KeePassXC/');
    $w{help}->set_halign('GTK_ALIGN_END');
    $w{help}->set_label('');
    $w{help}->set_tooltip_text('Open Online Help');
    $w{help}->set_always_show_image(1);
    $w{help}->set_image(Gtk3::Image->new_from_stock('asbru-help', 'button'));

    # Hbox to arrange first
    $w{hbox} = Gtk3::HBox->new(1,0);
    $w{hbox}->pack_start($w{cbUseKeePass}, 0, 1, 0);
    $w{hbox}->pack_start($w{help},0,1,0);
    $w{vbox}->pack_start($w{hbox}, 0, 0, 0);

    $w{hboxkpmain} = Gtk3::HBox->new(0, 4);
    $w{vbox}->pack_start($w{hboxkpmain}, 0, 1, 3);

    $w{dblabel} = Gtk3::Label->new('Database file');
    $w{dblabel}->set_size_request($width,-1);
    $w{dblabel}->set_xalign(0);
    $w{hboxkpmain}->pack_start($w{dblabel}, 0, 0, 0);

    $w{fcbKeePassFile} = Gtk3::FileChooserButton->new('','GTK_FILE_CHOOSER_ACTION_OPEN');
    $w{fcbKeePassFile}->set_show_hidden(0);
    $w{hboxkpmain}->pack_start($w{fcbKeePassFile}, 0, 0, 0);

    $w{btnClearPassFile} = Gtk3::Button->new('Clear');
    $w{hboxkpmain}->pack_start($w{btnClearPassFile}, 0, 1, 0);

    $w{hboxkpmain}->pack_start(Gtk3::Label->new('Master Password'), 0, 1, 0);
    $w{entryKeePassPassword} = Gtk3::Entry->new();
    $w{hboxkpmain}->pack_start($w{entryKeePassPassword}, 1, 1, 5);
    $w{entryKeePassPassword}->set_visibility(0);

    # Key file selection
    $w{hboxkpkeyfile} = Gtk3::HBox->new(0, 3);
    $w{keylabel} = Gtk3::Label->new('Key file');
    $w{vbox}->pack_start($w{hboxkpkeyfile}, 0, 1, 0);
    $w{hboxkpkeyfile}->pack_start($w{keylabel}, 0, 0, 0);
    $w{keylabel}->set_size_request($width,-1);
    $w{keylabel}->set_xalign(0);
    $w{fcbKeePassKeyFile} = Gtk3::FileChooserButton->new('','GTK_FILE_CHOOSER_ACTION_OPEN');
    $w{fcbKeePassKeyFile}->set_show_hidden(0);
    $w{hboxkpkeyfile}->pack_start($w{fcbKeePassKeyFile}, 0, 1, 0);

    $w{btnClearkeyfile} = Gtk3::Button->new('Clear');
    $w{hboxkpkeyfile}->pack_start($w{btnClearkeyfile}, 0, 1, 0);

    $w{btnClearkeyfile}->signal_connect('clicked' => sub {
        $w{fcbKeePassKeyFile}->set_uri("file://$ENV{'HOME'}");
        $w{fcbKeePassKeyFile}->unselect_uri("file://$ENV{'HOME'}");
    });
    if (!$$self{kpxc_keyfile}) {
        $w{hboxkpkeyfile}->set_sensitive(0);
    }

    # CLI binary selection
    $w{clilabel} = Gtk3::Label->new('keepassxc-cli binary');
    $w{clilabel}->set_size_request($width,-1);
    $w{clilabel}->set_xalign(0);
    $w{clilabel}->set_tooltip_text("Specify the keepassxc-cli binary file to use.\nIf not specified, the system wide keepassxc-cli will be used.");
    $w{fcbCliFile} = Gtk3::FileChooserButton->new('','GTK_FILE_CHOOSER_ACTION_OPEN');
    $w{fcbCliFile}->set_show_hidden(0);
    $w{btnClearclifile} = Gtk3::Button->new('Clear');
    $w{hboxkpclifile} = Gtk3::HBox->new(0, 3);
    $w{hboxkpclifile}->pack_start($w{clilabel}, 0, 0, 0);
    $w{hboxkpclifile}->pack_start($w{fcbCliFile}, 0, 1, 0);
    $w{hboxkpclifile}->pack_start($w{btnClearclifile}, 0, 1, 0);
    $w{vbox}->pack_start($w{hboxkpclifile}, 0, 1, 2);

    # Information about the selected keepassxc-cli
    $w{intro_usage} = Gtk3::Label->new();
    $w{intro_usage}->set_markup("Information about <i>keepassxc-cli</i> currently in use:");
    $w{intro_usage}->set_halign('start');
    $w{intro_usage}->set_margin_top(24);
    $w{usage} = Gtk3::Label->new();
    $w{usage}->set_halign('start');
    $w{usage}->set_margin_top(4);
    $w{usage}->set_margin_left(8);
    $w{vbox}->pack_start($w{intro_usage}, 0, 1, 0);
    $w{vbox}->pack_start($w{usage}, 0, 1, 0);

    $w{hboxkpmain}->set_sensitive($$self{cfg}{use_keepass});
    $w{hboxkpclifile}->set_sensitive($$self{cfg}{use_keepass});
    if ($$self{kpxc_keyfile}) {
        $w{hboxkpkeyfile}->set_sensitive($$self{cfg}{use_keepass});
    }

    _updateUsage($self);

    # Register callbacks
    $w{cbUseKeePass}->signal_connect('toggled', sub {
        if ($w{cbUseKeePass}->get_active()) {
            $$self{cfg}{use_keepass} = 1;
            $self->_setCapabilities();
        }
        $self->_updateUsage();
    });

    $w{btnClearPassFile}->signal_connect('clicked' => sub {
        $w{fcbKeePassFile}->set_uri("file://$ENV{'HOME'}");
        $w{fcbKeePassFile}->unselect_uri("file://$ENV{'HOME'}");
        if ($KPXC_MP || $ENV{'KPXC_MP'}) {
            $KPXC_MP = '';
            $ENV{'KPXC_MP'} = '';
        }
    });

    $w{btnClearclifile}->signal_connect('clicked' => sub {
        $$self{cfg}{pathcli} = '';
        $CLI = 'keepassxc-cli';
        $w{fcbCliFile}->set_uri("file://$ENV{'HOME'}");
        $w{fcbCliFile}->unselect_uri("file://$ENV{'HOME'}");
        $self->_setCapabilities();
        $self->_updateUsage();
    });

    $w{fcbKeePassFile}->signal_connect('selection-changed' => sub {
        if ($KPXC_MP || $ENV{'KPXC_MP'}) {
            $KPXC_MP = '';
            $ENV{'KPXC_MP'} = '';
        }
    });

    $w{fcbCliFile}->signal_connect('selection-changed' => sub {
        my ($fc) = @_;
        if (defined $fc->get_filename()) {
            $$self{cfg}{pathcli} = $fc->get_filename();
            $CLI = $fc->get_filename();
            $self->_setCapabilities();
            $self->_updateUsage();
            if ($CLI ne $fc->get_filename()) {
                # Remove selected file name, setCapabilities failed with this file
                $fc->set_uri("file://$ENV{'HOME'}");
                $fc->unselect_uri("file://$ENV{'HOME'}");
            }
        }
    });

    return 1;
}

sub _updateUsage {
    my $self = shift;
    my $uncheck = shift;
    my $capabilities;
    my $w = $$self{frame};

    # Lets make sure there is an UI to update (asrbu_conn does not creates an UI)
    if (!defined $w) {
        return 0;
    }
    if ($$self{_VERBOSE}) {
        print "DEBUG:KEEPASS: Update usage\n";
    }
    if ($$self{disable_keepassxc}) {
        $capabilities = "<span color='red'><b>keepassxc-cli</b> Not installed, choose a working keepassxc-cli or AppImage</span>";
    } else {
        my $warn = '';
        $capabilities  = "<b>Location</b>\t\t$CLI  $$self{kpxc_cli}\n$warn";
        $capabilities .= "<b>Version</b>\t\t\t$$self{kpxc_version}\n";
        $capabilities .= "<b>Support key file</b>\t" . ($$self{kpxc_keyfile} ? "Yes" : "No (update to latest version)") . "\n";
        $capabilities .= "<b>Show protected</b>\t" . ($$self{kpxc_show_protected} ? "Yes" : "No") . "\n";
    }
    if ($uncheck) {
        # Remove checkbox if there is not an available keepassxc-cli
        $$w{cbUseKeePass}->set_active(0);
    }
    $$w{usage}->set_markup($capabilities);
    $$w{hboxkpmain}->set_sensitive($$w{cbUseKeePass}->get_active());
    $$w{hboxkpclifile}->set_sensitive($$w{cbUseKeePass}->get_active());
    if ($$self{kpxc_keyfile} || $$w{cbUseKeePass}->get_active()==0 || $$self{disable_keepassxc}) {
        $$w{hboxkpkeyfile}->set_sensitive($$w{cbUseKeePass}->get_active());
    }
}

sub _setCapabilities {
    my $self = shift;
    my ($c);

    # Test the UI exists and is visible
    if (ref($self) eq 'PACKeePass') {
        # Ignore this call
        if (!$$self{frame}{cbUseKeePass}->is_visible()) {
            return 0;
        }
    }
    # Is start up or preferences are visible
    $$self{kpxc_keyfile} = '';
    $$self{kpxc_show_protected} = '';
    $$self{kpxc_keyfile_opt} = '';
    $$self{kpxc_version} = '';
    $$self{kpxc_cli} = '';
    $$self{disable_keepassxc} = 0;
    if (!$$self{cfg}{use_keepass}) {
        return 0;
    }
    if ($$self{_VERBOSE}) {
        print "DEBUG:KEYPASS: testCapabilities\n";
    }
    if ((defined $$self{cfg})&&($$self{cfg}{pathcli})&&(-e $$self{cfg}{pathcli})) {
        $CLI = $$self{cfg}{pathcli};
    }
    if (_getMagicBytes($CLI) eq '41490200') {
        $$self{kpxc_cli} = 'cli';
    }
    if ($$self{_VERBOSE}) {
        print "DEBUG:KEEPASS: $CLI $$self{kpxc_cli}\n";
    }
    $$self{kpxc_version} = `$CLI $$self{kpxc_cli} -v 2>/dev/null`;
    $$self{kpxc_version} =~ s/\n//g;
    if ($$self{kpxc_version} !~ /[0-9]+\.[0-9]+\.[0-9]+/) {
        # Invalid version number, user did not select a valid KeePassXC file
        $$self{kpxc_version} = '';
        $$self{cfg}{pathcli} = '';
        _wMessage($PACMain::FUNCS{_CONFIG}{_WINDOWCONFIG},"File is not a valid keepassxc-cli binary.");
    }
    if (!$$self{kpxc_version}) {
        if ($CLI eq 'keepassxc-cli') {
            # We do not have keepassxc-cli available
            $$self{disable_keepassxc} = 1;
            $$self{kpxc_cli} = '';
            return 0;
        } else {
            # Test if we have a system wide installation
            $$self{kpxc_cli} = '';
            $CLI = 'keepassxc-cli';
            $$self{kpxc_version} = `$CLI -v 2>/dev/null`;
            $$self{kpxc_version} =~ s/\n//g;
            if (!$$self{kpxc_version}) {
                # We do not have keepassxc-cli available, the user defined is not working
                $$self{cfg}{pathcli} = '';
                $$self{disable_keepassxc} = 1;
                return 0;
            }
        }
    }
    $c = `$CLI $$self{kpxc_cli} -h show 2>&1`;
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

# Check magic bytes, AppImage magic bytes : 41490200
sub _getMagicBytes {
    my $file = shift;
    my ($fh,$magic_bytes,$n);

    if (!$file || !-e $file) {
        return '';
    }
    open ($fh, '<:raw', $file) or return '';
    $n = read($fh, $magic_bytes, 32);
    close $fh;
    my $data = unpack("H*",$magic_bytes);
    return substr($data,16,8);
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

    $kpxc = PACKeePass->new(OPT_BG,CFG);
    OPT_BG = [0|1]
            1 : Create object and Build GUI to configure
            0 : Create object to access available methods
    CFG    = Pointer to a valid PACConfig configuration

=head1 DESCRIPTION

=head2

Important object variables

    $KPXC_MP : holds the current database master password

B<Warning>

    asbru_conn does not creates an UI, the code must not execute UI actions
    test that the UI object $$self{'frame'} exists, before

=head2 sub update

Updates configuration settings from current selections in gui

=head2 sub isKeePassMask

Returns true if the given string is a mask for a KeePass entry

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

=head2 sub listEntries

Build a window with a search entry and a listbox, show results from search entry in the listbox

    call _locateEntries on each typed key by user (3 characters are required to start the search)

Allow user to select a row and return the selected key path

head2 sub _locateEntries

Query the complete database for a search pattern and show the entries found in a listbox

=head2 sub _updateUsage

Update capabilities lables, and update the UIs preferences

=head2 sub _setCapabilities

Get keepassxc-cli version numbers and list of available parameters

    --show-protected        Older versions of keepassxc-cli showed by default clear passwords
                            when the show command is called. Later versions requiere this option
    --key-file              This version is capable to use a key-file

=head2 sub _getMagicBytes

Read first 32 bytes from binary and return the position for the magic bytes for AppImages
