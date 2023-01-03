package PACEdit;

###############################################################################
# This file is part of Ásbrú Connection Manager
#
# Copyright (C) 2017-2022 Ásbrú Connection Manager team (https://asbru-cm.net)
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

use FindBin qw ($RealBin $Bin $Script);
use lib $RealBin . '/lib/edit';

# Standard
use strict;
use warnings;

use YAML qw (LoadFile DumpFile);
use Storable qw (dclone nstore nstore_fd fd_retrieve);
use Encode;
use Glib::IO; # GSettings

use Config;

# GTK
use Gtk3 '-init';
use Gtk3::SimpleList;

# PAC modules
use PACUtils;
use PACMethod;
use PACExpectEntry;
use PACExecEntry;
use PACPrePostEntry;
use PACVarEntry;
use PACTermOpts;
use PACKeePass;

# END: Import Modules
###################################################################

###################################################################
# Define GLOBAL CLASS variables

my $APPNAME = $PACUtils::APPNAME;
my $APPVERSION = $PACUtils::APPVERSION;
my $RES_DIR = "$RealBin/res";
my $AUTOSTART_FILE = "$RES_DIR/asbru_start.desktop";
my $THEME_DIR = "$RES_DIR/themes/defualt";
my $GLADE_FILE = "$RES_DIR/asbru.glade";
my $INIT_CFG_FILE = "$RES_DIR/asbru.yml";
my $CFG_DIR = $ENV{"ASBRU_CFG"};
my $CFG_FILE = "$CFG_DIR/asbru.yml";

# END: Define GLOBAL CLASS variables
###################################################################

###################################################################
# START: Define PUBLIC CLASS methods

sub new {
    my $class = shift;
    my $self = {};

    $self->{_CFG} = shift;

    $self->{_UUID} = undef;

    $self->{_GLADE} = undef;

    $self->{EMBED} = 0;

    $self->{_IS_NEW} = 0;
    $self->{_WINDOWEDIT} = undef;
    $self->{_SPECIFIC} = undef;
    $self->{_PRE_EXEC} = undef;
    $self->{_POST_EXEC} = undef;
    $self->{_EXPECT_EXEC} = undef;
    $self->{_MACROS} = undef;
    $self->{_LOCAL_EXEC} = undef;
    $self->{_TXTOPTSBUFFER} = undef;

    if ($$self{_CFG}{defaults}{theme}) {
        $THEME_DIR = "$RES_DIR/themes/$$self{_CFG}{defaults}{theme}";
    }

    # Setup known connection methods
    %{$$self{_METHODS}} = _getMethods($self,$THEME_DIR);

    # Build the GUI
    _initGUI($self) or return 0;

    # Setup callbacks
    _setupCallbacks($self);

    bless($self, $class);
    return $self;
}

# DESTRUCTOR
sub DESTROY {
    my $self = shift;
    undef $self;
    return 1;
}

# Start GUI
sub show {
    my $self = shift;
    $$self{_UUID} = shift;
    $$self{_IS_NEW} = shift // 0;

    $self->_updateGUIPreferences();

    my $title;
    if ($$self{_IS_NEW} eq 'quick') {
        _($self, 'btnSaveEdit')->set_label('_Start Connection');
        _($self, 'btnSaveEdit')->set_image(Gtk3::Image->new_from_stock('asbru-quick-connect', 'button') );
        _($self, 'btnCloseEdit')->set_label('_Cancel Quick connect');
        _($self, 'btnCloseEdit')->set_image(Gtk3::Image->new_from_stock('gtk-close', 'button') );
        $title = "Quick Connect : $APPNAME (v$APPVERSION)";
    } else {
        _($self, 'btnSaveEdit')->set_label('_Save and Close');
        _($self, 'btnSaveEdit')->set_image(Gtk3::Image->new_from_stock('gtk-save', 'button') );
        _($self, 'btnCloseEdit')->set_label('_Close without saving');
        _($self, 'btnCloseEdit')->set_image(Gtk3::Image->new_from_stock('gtk-close', 'button') );
        $title = "Editing '$PACMain::FUNCS{_MAIN}{_CFG}{'environments'}{$$self{_UUID}}{'name'}' : $APPNAME (v$APPVERSION)";
    }

    $$self{_WINDOWEDIT}->set_title($title);

    if ($$self{_IS_NEW}) {
        _($self, 'nbProps')->set_current_page(0);
        _($self, 'entryIP')->grab_focus;
        _($self, 'nbDetails')->set_current_page(0);
    }

    $$self{_WINDOWEDIT}->set_modal(1);

    return 1;
}

# END: Define PUBLIC CLASS methods
###################################################################

###################################################################
# START: Define PRIVATE CLASS functions

sub _initGUI {
    my $self = shift;

    # Load XML Glade file
    defined $$self{_GLADE} or $$self{_GLADE} = Gtk3::Builder->new_from_file($GLADE_FILE) or die "ERROR: Could not load GLADE file '$GLADE_FILE' ($!)";

    # Save main, about and add windows
    $$self{_WINDOWEDIT} = $$self{_GLADE}->get_object('windowEdit');
    $$self{_WINDOWEDIT}->set_size_request(-1, 550);

    _($self, 'imgBannerEditIcon')->set_from_file($THEME_DIR . '/asbru-edit.svg');
    _($self, "linkHelpConn1")->set_label('');
    _($self, "linkHelpConn1")->set_image(Gtk3::Image->new_from_stock('asbru-help', 'button'));
    _($self, "linkHelpNetwokSettings")->set_label('');
    _($self, "linkHelpNetwokSettings")->set_image(Gtk3::Image->new_from_stock('asbru-help', 'button'));

    _($self, 'btnEditNetworkSettingsCheckKPX')->set_label('');
    _($self, 'btnEditNetworkSettingsCheckKPX')->set_image(Gtk3::Image->new_from_stock('asbru-keepass', 'button') );

    $$self{_SPECIFIC} = PACMethod->new();
    _($self, 'alignSpecific')->add($PACMethod::CONTAINER);
    _($self, 'alignTermOpts')->add(($$self{_TERMOPTS} = PACTermOpts->new())->{container});
    _($self, 'imgTermOpts')->set_from_stock('asbru-terminal-ok-small', 'button');
    _($self, 'alignVar')->add(($$self{_VARIABLES} = PACVarEntry->new())->{container});
    _($self, 'alignPreExec')->add(($$self{_PRE_EXEC} = PACPrePostEntry->new())->{container});
    _($self, 'alignPostExec')->add(($$self{_POST_EXEC} = PACPrePostEntry->new())->{container});
    _($self, 'alignMacros')->add(($$self{_MACROS} = PACExecEntry->new(undef, undef, 'cremote'))->{container});
    _($self, 'alignLocal')->add(($$self{_LOCAL_EXEC} = PACExecEntry->new(undef, undef, 'clocal'))->{container});
    _($self, 'alignExpect')->add(($$self{_EXPECT_EXEC} = PACExpectEntry->new())->{container});
    _($self, 'nbProps')->show_all();

    # Populate 'Method' combobox
    my $i = 0;
    foreach my $method (sort {$a cmp $b} keys %{$$self{_METHODS}}) {
        _($self, 'comboMethod')->append_text($method);
        $$self{_METHODS}{$method}{'position'} = $i++;
    }

    # Initialize main window
    $$self{_WINDOWEDIT}->set_icon_name('asbru-app-big');
    $$self{_WINDOWEDIT}->set_position('center');

    $$self{cbShowHidden} = Gtk3::CheckButton->new_with_mnemonic('Show _hidden files');
    _($self, 'fileCfgPublicKey')->set_extra_widget($$self{cbShowHidden});

    $$self{cbLogsShowHidden} = Gtk3::CheckButton->new_with_mnemonic('Show _hidden files');
    _($self, 'btnEditSaveSessionLogs')->set_extra_widget($$self{cbLogsShowHidden});

    _($self, 'btnCheckKPX')->set_image(Gtk3::Image->new_from_stock('asbru-keepass', 'button') );
    _($self, 'btnCheckKPX')->set_label('');

    _($self, 'btnSaveEdit')->set_use_underline(1);
    _($self, 'btnCloseEdit')->set_use_underline(1);
    _($self, 'btnCheckKPX')->set_sensitive($$self{'_CFG'}{'defaults'}{'keepass'}{'use_keepass'});

    return 1;
}

sub __checkRBAuth {
    my $self = shift;

    if (_($self, 'comboMethod')->get_active_text() =~ /SSH|SFTP/i) {
        _($self, 'entryCfgJumpConnPass')->set_sensitive(1);
        _($self, 'entryCfgJumpConnPass')->set_visible(1);
        _($self, 'lblJumpPass')->set_sensitive(1);
        _($self, 'lblJumpPass')->set_visible(1);
        if(_($self, 'rbCfgAuthManual')->get_active()) {
            _($self, 'frameExpect')->set_sensitive(0);
            _($self, 'labelExpect')->set_sensitive(0);
            _($self, 'labelExpect')->set_tooltip_text("Authentication is set to Manual.\nExpect disabled.");
            _($self, 'alignExpect')->set_tooltip_text("Authentication is set to Manual.\nExpect disabled.");
        }
        else{
            _($self, 'frameExpect')->set_sensitive(1);
            _($self, 'labelExpect')->set_sensitive(1);
            _($self, 'labelExpect')->set_tooltip_text("EXPECT remote patterns AND-THEN-EXECUTE remote commands");
            _($self, 'alignExpect')->set_has_tooltip(0);

        }
        my $status = _($self, 'rbUseProxyJump')->get_active();
        _($self, 'rbUseProxyJump')->set_sensitive(1);
        _($self, 'rbUseProxyJump')->set_tooltip_text("If selected, use a SSH jump host for this connection.\n\nAn alternative to SSH tunneling to access internal machines through gateway.");
        _($self, 'vboxJumpCfgOptions')->set_sensitive(_($self, 'rbUseProxyJump')->get_active());
        _($self, 'vboxJumpCfgOptions')->set_sensitive($status);
        _($self, 'vboxJumpCfg')->set_visible(1);
        _($self, 'vboxCfgManualProxyConn')->set_visible(1);
    } elsif (_($self, 'comboMethod')->get_active_text() =~ /RDP|VNC/) {
        _($self, 'rbUseProxyJump')->set_sensitive(1);
        _($self, 'vboxJumpCfgOptions')->set_sensitive(1);
        _($self, 'rbUseProxyJump')->set_tooltip_text("If selected, use a SSH tunnel to simulate a jump host for this connection.");
        _($self, 'vboxJumpCfgOptions')->set_sensitive(_($self, 'rbUseProxyJump')->get_active());
        _($self, 'vboxJumpCfg')->set_visible(1);
        _($self, 'entryCfgJumpConnPass')->set_sensitive(0);
        _($self, 'entryCfgJumpConnPass')->set_visible(0);
        _($self, 'vboxCfgManualProxyConn')->set_visible(1);
        _($self, 'lblJumpPass')->set_sensitive(0);
        _($self, 'lblJumpPass')->set_visible(0);
        _($self, 'entryCfgJumpConnPass')->set_text('');
    } else {
        if (_($self, 'rbUseProxyJump')->get_active()) {
            _($self, 'rbUseProxyIfCFG')->set_active(1);
        }
        _($self, 'vboxJumpCfg')->set_visible(0);
        _($self, 'rbUseProxyJump')->set_sensitive(0);
        _($self, 'vboxJumpCfgOptions')->set_sensitive(0);
        _($self, 'rbUseProxyJump')->set_tooltip_text("If selected, use a SSH tunnel to simulate a jump host for this connection.");
        _($self, 'vboxJumpCfgOptions')->set_sensitive(_($self, 'rbUseProxyJump')->get_active());
        _($self, 'vboxCfgManualProxyConn')->set_visible(0);
    }

    _($self, 'alignUserPass')->set_sensitive(_($self, 'rbCfgAuthUserPass')->get_active() || _($self, 'rbCfgAuthManual')->get_active());
    _($self, 'alignPublicKey')->set_sensitive(_($self, 'rbCfgAuthPublicKey')->get_active());
    _($self, 'hboxAuthPassword')->set_sensitive(!_($self, 'rbCfgAuthManual')->get_active());

    return 1;
}

sub _setupCallbacks {
    my $self = shift;

    # Capture 'Show hidden files' checkbox for private key files
    $$self{cbShowHidden}->signal_connect('toggled' => sub {
        _($self, 'fileCfgPublicKey')->set_show_hidden($$self{cbShowHidden}->get_active());
    });

    # Capture 'Show hidden files' checkbox for session log files
    $$self{cbLogsShowHidden}->signal_connect('toggled' => sub {
        _($self, 'btnEditSaveSessionLogs')->set_show_hidden($$self{cbLogsShowHidden}->get_active());
    });

    # Capture 'Method' changed
    _($self, 'comboMethod')->signal_connect('changed' => sub {
        my $method = _($self, 'comboMethod')->get_active_text();

        my $installed = &{$$self{_METHODS}{$method}{'installed'}};
        _($self, 'btnSaveEdit')->set_sensitive($installed eq '1');
        $installed ne '1' and _wMessage($$self{_WINDOWEDIT}, $installed);

        &{$$self{_METHODS}{$method}{'updateGUI'}}($$self{_CFG}{'environments'}{$$self{_UUID}});
        $$self{_SPECIFIC}->change($method, $$self{_CFG}{'environments'}{$$self{_UUID}});
        $$self{_WINDOWEDIT}->show_all(); # Without this line, $$self{_SPECIFIC} widgets WILL NOT BE SHOWN!!!!!!!!!
        __checkRBAuth($self);
    });

    # Capture "User/Pass" connection radiobutton state change
    _($self, 'rbCfgAuthUserPass')->signal_connect(toggled => sub {$self->__checkRBAuth();});
    _($self, 'rbCfgAuthPublicKey')->signal_connect(toggled => sub {$self->__checkRBAuth();});
    _($self, 'rbCfgAuthManual')->signal_connect(toggled => sub {$self->__checkRBAuth();});

    # Capture 'show password' checkbox toggled state
    _($self, 'cbConnShowPass')->signal_connect('toggled' => sub {
        _($self, 'entryPassword')->set_visibility(_($self, 'cbConnShowPass')->get_active());
    });

    # Capture 'show passphrase' checkbox toggled state
    _($self, 'cbConnShowPassphrase')->signal_connect('toggled' => sub {
        _($self, 'entryPassphrase')->set_visibility(_($self, 'cbConnShowPassphrase')->get_active());
    });

    # Capture 'save' button clicked
    _($self, 'btnSaveEdit')->signal_connect('clicked' => sub {
        if ($$self{_IS_NEW} eq 'quick') {
            $self->_saveConfiguration or return 1;
            $self->_closeConfiguration();
            $PACMain::FUNCS{_MAIN}->_launchTerminals([['__PAC__QUICK__CONNECT__'] ]);
        } else {
            $self->_saveConfiguration or return 1;
            $self->_closeConfiguration();
        }
    });

    # Capture 'programatically send string' checkbox toggled state
    _($self, 'cbEditSendString')->signal_connect('toggled' => sub {
        _($self, 'hboxEditSendString')->set_sensitive(_($self, 'cbEditSendString')->get_active());
    });

    # Capture 'open folder' button clicked
    _($self, 'btnEditOpenSessionLogs')->signal_connect('clicked' => sub {
        my $folder = _($self, 'btnEditSaveSessionLogs')->get_current_folder();
        if (!-e $folder) {
            $folder = "$CFG_DIR/session_logs";
            _($self, 'btnEditSaveSessionLogs')->get_current_folder($folder);
        }
        system("$ENV{'ASBRU_ENV_FOR_EXTERNAL'} /usr/bin/xdg-open $folder");
    });

    # Capture 'Get Command line' button clicked
    _($self, 'btnEditGetCMD')->signal_connect('clicked' => sub {
        # DevNote: please make sure to keep double quotes in "$RealBin/lib/asbru_conn" since it might be replaced by packagers (see RPM spec)
        if (!$ENV{'KPXC_MP'} && $PACMain::FUNCS{_KEEPASS}->hasKeePassField($$self{_CFG},$$self{_UUID})) {
            if ($$self{_CFG}{defaults}{keepass}{password}) {
                $ENV{'KPXC_MP'} = $$self{_CFG}{defaults}{keepass}{password};
            } else {
                my $kpxc = PACKeePass->new(0, $$self{_CFG}{defaults}{keepass});
                $kpxc->getMasterPassword($$self{_WINDOWEDIT});
            }
        }
        my $cmd = `'$^X' "$RealBin/lib/asbru_conn" "$CFG_DIR/asbru.nfreeze" "$$self{_UUID}" 0 1`;
        _wMessage($$self{_WINDOWEDIT}, $cmd, 1, 1, 'w-info');
    });

    # Capture "Save session logs" checkbox
    _($self, 'cbEditSaveSessionLogs')->signal_connect(toggled => sub {
        _($self, 'vboxEditSaveSessionLogs')->set_sensitive(_($self, 'cbEditSaveSessionLogs')->get_active());
    });

    # Capture "Prepend command" checkbox
    _($self, 'cbEditPrependCommand')->signal_connect(toggled => sub {
        _($self, 'entryEditPrependCommand')->set_sensitive(_($self, 'cbEditPrependCommand')->get_active());
        _($self, 'cbCfgQuoteCommand')->set_sensitive(_($self, 'cbEditPrependCommand')->get_active());
    });

    # Capture "Postpend command" checkbox
    _($self, 'cbEditPostpendCommand')->signal_connect(toggled => sub {
        _($self, 'entryEditPostpendCommand')->set_sensitive(_($self, 'cbEditPostpendCommand')->get_active());
        _($self, 'cbCfgQuotePostCommand')->set_sensitive(_($self, 'cbEditPostpendCommand')->get_active());
    });

    # Capture 'check keepassx' button clicked
    _($self, 'btnCheckKPX')->signal_connect('clicked' => sub {
        if (!$ENV{'KPXC_MP'} && $$self{_CFG}{defaults}{keepass}{password}) {
            $ENV{'KPXC_MP'} = $$self{_CFG}{defaults}{keepass}{password};
        }
        my $selection = $PACMain::FUNCS{_KEEPASS}->listEntries($$self{_WINDOWEDIT});
        if ($selection) {
            # Commented for the time being, until keepassxc-cli team implements get the UUID
            # Feature request at https://github.com/keepassxreboot/keepassxc/issues/4112
            # Feature request at https://github.com/keepassxreboot/keepassxc/issues/4113
            #my ($title,$ok) = $PACMain::FUNCS{_KEEPASS}->getFieldValue('Uuid',$selection);

            # For the time being, we will use the full path
            my $title = $selection;
            if ($title) {
                _($self, 'entryIP')->set_text("<url|$title>");
                if (_($self, 'rbCfgAuthUserPass')->get_active) {
                    _($self, 'entryUser')->set_text("<username|$title>");
                    _($self, 'entryPassword')->set_text("<password|$title>");
                } elsif (_($self, 'rbCfgAuthPublicKey')->get_active) {
                    _($self, 'entryUserPassphrase')->set_text("<username|$title>");
                    _($self, 'entryPassphrase')->set_text("<password|$title>");
                }
            }
        }
        return 1;
    });

    # Capture 'close' button clicked
    _($self, 'btnCloseEdit')->signal_connect('clicked' => sub {
        $self->_closeConfiguration();
    });

    # Capture right mouse click to show custom context menu on "Programatically send string"
    _($self, "entryEditSendString")->signal_connect('button_press_event' => sub {
        my ($widget, $event) = @_;

        return 0 unless $event->button eq 3;

        my @menu_items;

        # Populate with user defined variables
        my @variables_menu;
        my $i = 0;
        foreach my $value (map{$_->{txt} // ''} @{$self->{_VARIABLES}->{cfg}}) {
            my $j = $i;
            push(@variables_menu, {
                label => "<V:$j> ($value)",
                code => sub {_($self, "entryEditSendString")->insert_text("<V:$j>", -1, _($self, "entryEditSendString")->get_position);}
            });
            ++$i;
        }
        push(@menu_items, {
            label => 'User variables...',
            sensitive => scalar @{$self->{_VARIABLES}->{cfg}},
            submenu => \@variables_menu
        });

        # Populate with global defined variables
        my @global_variables_menu;
        foreach my $var (sort {$a cmp $b} keys %{$PACMain::FUNCS{_MAIN}{_CFG}{'defaults'}{'global variables'}}) {
            my $val = $PACMain::FUNCS{_MAIN}{_CFG}{'defaults'}{'global variables'}{$var}{'value'};
            push(@global_variables_menu, {
                label => "<GV:$var> ($val)",
                code => sub {_($self, "entryEditSendString")->insert_text("<GV:$var>", -1, _($self, "entryEditSendString")->get_position);}
            });
        }
        push(@menu_items, {
            label => 'Global variables...',
            sensitive => scalar(@global_variables_menu),
            submenu => \@global_variables_menu
        });

        # Populate with environment variables
        my @environment_menu;
        foreach my $key (sort {$a cmp $b} keys %ENV) {
            # Do not offer Master Password, or any other environment variable with word PRIVATE, TOKEN
            if ($key =~ /KPXC|PRIVATE|TOKEN/i) {
                next;
            }
            my $value = $ENV{$key};
            push(@environment_menu, {
                label => "<ENV:" . __($key) . ">",
                tooltip => "$key=$value",
                code => sub {_($self, "entryEditSendString")->insert_text("<ENV:$key>", -1, _($self, "entryEditSendString")->get_position);}
            });
        }
        push(@menu_items, {
            label => 'Environment variables...',
            submenu => \@environment_menu
        });

        # Populate with <CMD:*> special string
        push(@menu_items, {
            label => 'Use a command output as value',
            tooltip => 'The given command line will be locally executed, and its output (both STDOUT and STDERR) will be used to replace this value',
            code => sub {
                my $pos = _($self, "entryEditSendString")->get_property('cursor_position');
                _($self, "entryEditSendString")->insert_text('<CMD:command to launch>', -1, _($self, "entryEditSendString")->get_position);
                _($self, "entryEditSendString")->select_region($pos + 5, $pos + 22);
            }
        });

        _wPopUpMenu(\@menu_items, $event);

        return 1;
    });

    # Capture proxy usage change
    _($self, 'rbUseProxyAlways')->signal_connect('toggled' => sub {
        _($self, 'vboxCfgManualProxyConnOptions')->set_sensitive(_($self, 'rbUseProxyAlways')->get_active());
        _updateCfgProxyKeePass($self);
    });

    # Capture jump host change
    _($self, 'rbUseProxyJump')->signal_connect('toggled' => sub {
        _($self, 'vboxJumpCfgOptions')->set_sensitive(_($self, 'rbUseProxyJump')->get_active());
        _updateCfgProxyKeePass($self);
    });

    _($self, 'btnEditClearJumpPrivateKey')->signal_connect('clicked' => sub {
        _($self, 'entryCfgJumpConnKey')->set_uri("file://$ENV{'HOME'}");
        _($self, 'entryCfgJumpConnKey')->unselect_uri("file://$ENV{'HOME'}");
    });

    _($self, 'btnEditClearPrivateKey')->signal_connect('clicked' => sub {
        _($self, 'fileCfgPublicKey')->set_uri("file://$ENV{'HOME'}");
        _($self, 'fileCfgPublicKey')->unselect_uri("file://$ENV{'HOME'}");
    });

    # Capture right mouse click to show custom context menu
    foreach my $w ('IP', 'Port', 'User', 'Password', 'EditPrependCommand', 'EditPostpendCommand', 'TabWindowTitle', 'UserPassphrase', 'Passphrase','CfgProxyConnUser','CfgProxyConnPassword','CfgJumpConnUser','CfgJumpConnPass','CfgProxyConnIP','CfgJumpConnIP') {_($self, "entry$w")->signal_connect('button_press_event' => sub {
            my ($widget, $event) = @_;

            return 0 unless $event->button eq 3;

            my @menu_items;

            # Populate with <<ASK_PASS>> special string
            push(@menu_items, {
                label => 'Interactive Password input',
                code => sub {_($self, "entry$w")->delete_text(0, -1); _($self, "entry$w")->insert_text('<<ASK_PASS>>', -1, 0);}
            }) if $w eq 'Password';

            # Populate with user defined variables
            my @variables_menu;
            my $i = 0;
            foreach my $value (map{$_->{txt} // ''} @{$self->{_VARIABLES}->{cfg}}) {
                my $j = $i;
                push(@variables_menu, {
                    label => "<V:$j> ($value)",
                    code => sub {_($self, "entry$w")->insert_text("<V:$j>", -1, _($self, "entry$w")->get_position);}
                });
                ++$i;
            }
            push(@menu_items, {
                label => 'User variables...',
                sensitive => scalar @{$self->{_VARIABLES}->{cfg}},
                submenu => \@variables_menu
            });

            # Populate with global defined variables
            my @global_variables_menu;
            foreach my $var (sort {$a cmp $b} keys %{$PACMain::FUNCS{_MAIN}{_CFG}{'defaults'}{'global variables'}}) {
                my $val = $PACMain::FUNCS{_MAIN}{_CFG}{'defaults'}{'global variables'}{$var}{'value'};
                push(@global_variables_menu, {
                    label => "<GV:$var> ($val)",
                    code => sub {_($self, "entry$w")->insert_text("<GV:$var>", -1, _($self, "entry$w")->get_position);}
                });
            }
            push(@menu_items, {
                label => 'Global variables...',
                sensitive => scalar(@global_variables_menu),
                submenu => \@global_variables_menu
            });

            # Populate with environment variables
            my @environment_menu;
            foreach my $key (sort {$a cmp $b} keys %ENV) {
                my $value = $ENV{$key};
                push(@environment_menu, {
                    label => "<ENV:" . __($key) . ">",
                    tooltip => "$key=$value",
                    code => sub {_($self, "entry$w")->insert_text("<ENV:$key>", -1, _($self, "entry$w")->get_position);}
                });
            }

            push(@menu_items, {
                label => 'Environment variables...',
                submenu => \@environment_menu
            });

            # Populate with <ASK:#> special string
            push(@menu_items, {
                label => 'Interactive user input',
                tooltip => 'User will be prompted to provide a value with a text box (free data type)',
                code => sub {
                    my $pos = _($self, "entry$w")->get_property('cursor_position');
                    _($self, "entry$w")->insert_text('<ASK:number>', -1, _($self, "entry$w")->get_position);
                    _($self, "entry$w")->select_region($pos + 5, $pos + 11);
                }
            }) unless ($w eq 'Password' || $w eq 'TabWindowTitle');

            # Populate with <ASK:*|> special string
            push(@menu_items, {
                label => 'Interactive user choose from list',
                tooltip => 'User will be prompted to choose a value form a user defined list separated with "|" (pipes without quotes)',
                code => sub {
                    my $pos = _($self, "entry$w")->get_property('cursor_position');
                    _($self, "entry$w")->insert_text('<ASK:descriptive line|opt1|opt2|...|optN>', -1, _($self, "entry$w")->get_position);
                    _($self, "entry$w")->select_region($pos + 5, $pos + 40);
                }
            }) unless $w eq 'TabWindowTitle';

            # Populate with <CMD:*> special string
            push(@menu_items, {
                label => 'Use a command output as value',
                tooltip => 'The given command line will be locally executed, and its output (both STDOUT and STDERR) will be used to replace this value',
                code => sub {
                    my $pos = _($self, "entry$w")->get_property('cursor_position');
                    _($self, "entry$w")->insert_text('<CMD:command to launch>', -1, _($self, "entry$w")->get_position);
                    _($self, "entry$w")->select_region($pos + 5, $pos + 22);
                }
            });

            if ($w eq 'IP' || $w =~ /ConnIP/) {
                $PACMain::FUNCS{_KEEPASS}->setRigthClickMenuEntry($PACMain::FUNCS{_EDIT}{_WINDOWEDIT},'url',_($self, "entry$w"),\@menu_items);
            } elsif ($w =~ /ConnUser/) {
                $PACMain::FUNCS{_KEEPASS}->setRigthClickMenuEntry($PACMain::FUNCS{_EDIT}{_WINDOWEDIT},'username',_($self, "entry$w"),\@menu_items);
            } elsif ($w =~ /ConnPass/) {
                $PACMain::FUNCS{_KEEPASS}->setRigthClickMenuEntry($PACMain::FUNCS{_EDIT}{_WINDOWEDIT},'password',_($self, "entry$w"),\@menu_items);
            }

            _wPopUpMenu(\@menu_items, $event);

            return 1;
        });
    }

    # Capture window closing
    $$self{_WINDOWEDIT}->signal_connect('delete_event' => sub {
        $self->_closeConfiguration();
        return 1;
    });

    $$self{_WINDOWEDIT}->signal_connect('key_press_event' => sub {
        my ($widget, $event) = @_;
        # Capture 'Esc' keypress to close window
        if ($event->keyval == 65307) {
            $self->_closeConfiguration();
        }
        return 0;
    });

    # Capture 'startup script' checkbutton changed
    _($self, 'cbStartScript')->signal_connect(toggled => sub {
        _($self, 'comboStartScript')->set_sensitive(_($self, 'cbStartScript')->get_active());
        _($self, 'cbStartScript')->get_active() and _($self, 'comboStartScript')->popup();
    });

    # Associated proxy settings to KeePass entries
    _($self, 'btnEditNetworkSettingsCheckKPX')->signal_connect('clicked' => sub {
        # User selects an entry in KeePass
        my $title = $PACMain::FUNCS{_KEEPASS}->listEntries($$self{_WINDOWEDIT});

        if ($title) {
            if (_($self, 'rbUseProxyAlways')->get_active) {
                _($self, 'entryCfgProxyConnIP')->set_text("<url|$title>");
                _($self, 'entryCfgProxyConnUser')->set_text("<username|$title>");
                _($self, 'entryCfgProxyConnPassword')->set_text("<password|$title>");
            } elsif (_($self, 'rbUseProxyJump')->get_active) {
                _($self, 'entryCfgJumpConnIP')->set_text("<url|$title>");
                _($self, 'entryCfgJumpConnUser')->set_text("<username|$title>");
                _($self, 'entryCfgJumpConnPass')->set_text("<password|$title>");
            }
        }
    });

    return 1;
}

sub _updateGUIPreferences {
    my $self = shift;
    my $uuid = $$self{_UUID};

    ####################################
    # General options
    ####################################

    if (!defined $$self{_CFG}{'environments'}{$uuid}{'use proxy'}) {
        $$self{_CFG}{'environments'}{$uuid}{'use proxy'} = 0;
    }
    # Test for missing folders, wrong migrations paths, alternate config paths
    if (!$$self{_CFG}{'environments'}{$uuid}{'session logs folder'} || !-d $$self{_CFG}{'environments'}{$uuid}{'session logs folder'}) {
        $$self{_CFG}{'environments'}{$uuid}{'session logs folder'} = "$CFG_DIR/session_logs";
    }
    _($self, 'rbUseProxyIfCFG')->set_active($$self{_CFG}{'environments'}{$uuid}{'use proxy'} == 0);
    _($self, 'rbUseProxyAlways')->set_active($$self{_CFG}{'environments'}{$uuid}{'use proxy'} == 1);
    _($self, 'rbUseProxyNever')->set_active($$self{_CFG}{'environments'}{$uuid}{'use proxy'} == 2);
    _($self, 'rbUseProxyJump')->set_active($$self{_CFG}{'environments'}{$uuid}{'use proxy'} == 3);
    _($self, 'vboxCfgManualProxyConnOptions')->set_sensitive(_($self, 'rbUseProxyAlways')->get_active());
    # SOCKS Proxy
    _($self, 'entryCfgProxyConnIP')->set_text($$self{_CFG}{'environments'}{$uuid}{'proxy ip'} // '');
    _($self, 'entryCfgProxyConnPort')->set_value($$self{_CFG}{'environments'}{$uuid}{'proxy port'} // 8080);
    _($self, 'entryCfgProxyConnUser')->set_text($$self{_CFG}{'environments'}{$uuid}{'proxy user'} // '');
    _($self, 'entryCfgProxyConnPassword')->set_text($$self{_CFG}{'environments'}{$uuid}{'proxy pass'} // '');
    # Jump Server
    _($self, 'entryCfgJumpConnIP')->set_text($$self{_CFG}{'environments'}{$uuid}{'jump ip'} // '');
    _($self, 'entryCfgJumpConnPort')->set_range(0, 65536);
    _($self, 'entryCfgJumpConnPort')->set_value($$self{_CFG}{'environments'}{$uuid}{'jump port'} // 22);
    _($self, 'entryCfgJumpConnUser')->set_text($$self{_CFG}{'environments'}{$uuid}{'jump user'} // '');
    _($self, 'entryCfgJumpConnPass')->set_text($$self{_CFG}{'environments'}{$uuid}{'jump pass'} // '');
    _($self, 'chkPseudoJumpServer')->set_active($$self{_CFG}{'environments'}{$uuid}{'pseudo jump'} // 0);
    if ((defined $$self{_CFG}{'environments'}{$uuid}{'jump key'})&&($$self{_CFG}{'environments'}{$uuid}{'jump key'} ne '')) {
        _($self, 'entryCfgJumpConnKey')->set_uri("file://$$self{_CFG}{'environments'}{$uuid}{'jump key'}");
    } else {
        _($self, 'entryCfgJumpConnKey')->set_uri("file://$ENV{'HOME'}");
        _($self, 'entryCfgJumpConnKey')->unselect_uri("file://$ENV{'HOME'}");
    }
    _($self, 'vboxJumpCfgOptions')->set_sensitive(_($self, 'rbUseProxyJump')->get_active());

    _($self, 'cbEditUseSudo')->set_active($$self{_CFG}{'environments'}{$uuid}{'use sudo'});
    _($self, 'cbEditSaveSessionLogs')->set_active($$self{_CFG}{'environments'}{$uuid}{'save session logs'});
    _($self, 'cbEditPrependCommand')->set_active($$self{_CFG}{'environments'}{$uuid}{'use prepend command'} // 0);
    _($self, 'entryEditPrependCommand')->set_text($$self{_CFG}{'environments'}{$uuid}{'prepend command'} // '');
    _($self, 'entryEditPrependCommand')->set_sensitive(_($self, 'cbEditPrependCommand')->get_active());
    _($self, 'cbEditPostpendCommand')->set_active($$self{_CFG}{'environments'}{$uuid}{'use postpend command'} // 0);
    _($self, 'entryEditPostpendCommand')->set_text($$self{_CFG}{'environments'}{$uuid}{'postpend command'} // '');
    _($self, 'entryEditPostpendCommand')->set_sensitive(_($self, 'cbEditPostpendCommand')->get_active());
    _($self, 'cbCfgQuoteCommand')->set_active($$self{_CFG}{'environments'}{$uuid}{'quote command'} // 0);
    _($self, 'cbCfgQuoteCommand')->set_sensitive(_($self, 'cbEditPrependCommand')->get_active());
    _($self, 'cbCfgQuotePostCommand')->set_active($$self{_CFG}{'environments'}{$uuid}{'quotepost command'} // 0);
    _($self, 'cbCfgQuotePostCommand')->set_sensitive(_($self, 'cbEditPostpendCommand')->get_active());
    _($self, 'vboxEditSaveSessionLogs')->set_sensitive($$self{_CFG}{'environments'}{$uuid}{'save session logs'});
    _($self, 'entryEditLogFileName')->set_text($$self{_CFG}{'environments'}{$uuid}{'session log pattern'});
    _($self, 'btnEditSaveSessionLogs')->set_current_folder($$self{_CFG}{'environments'}{$uuid}{'session logs folder'});
    _($self, 'spEditSaveSessionLogs')->set_value($$self{_CFG}{'environments'}{$uuid}{'session logs amount'} // 10);
    _($self, 'entryUserPassphrase')->set_text($$self{_CFG}{'environments'}{$uuid}{'passphrase user'} // '');
    _($self, 'entryPassphrase')->set_text($$self{_CFG}{'environments'}{$uuid}{'passphrase'} // '');
    if  (($$self{_CFG}{'environments'}{$uuid}{'public key'})&&(!-d $$self{_CFG}{'environments'}{$uuid}{'public key'})&& (-e $$self{_CFG}{'environments'}{$uuid}{'public key'})) {
        _($self, 'fileCfgPublicKey')->set_uri("file://$$self{_CFG}{'environments'}{$uuid}{'public key'}");
    } else {
        _($self, 'fileCfgPublicKey')->set_uri("file://$ENV{'HOME'}");
        _($self, 'fileCfgPublicKey')->unselect_uri("file://$ENV{'HOME'}");
    }
    _($self, 'entryIP')->set_text($$self{_CFG}{'environments'}{$uuid}{'ip'});
    _($self, 'entryPort')->set_value($$self{_CFG}{'environments'}{$uuid}{'port'});
    _($self, 'entryUser')->set_text($$self{_CFG}{'environments'}{$uuid}{'user'});
    _($self, 'entryPassword')->set_text($$self{_CFG}{'environments'}{$uuid}{'pass'});
    _($self, 'cbCfgAuthFallback')->set_active(! $$self{_CFG}{'environments'}{$uuid}{'auth fallback'});
    _($self, 'comboMethod')->set_active($$self{_METHODS}{$$self{_CFG}{'environments'}{$uuid}{'method'}}{'position'} // 4);
    _($self, 'imageMethod')->set_from_stock('asbru-' . $$self{_CFG}{'environments'}{$uuid}{'method'}, 'button');
    _($self, 'entryTabWindowTitle')->set_text($$self{_CFG}{'environments'}{$uuid}{'title'} || "$$self{_CFG}{'environments'}{$uuid}{'name'} ");
    _($self, 'cbEditSendString')->set_active($$self{_CFG}{'environments'}{$uuid}{'send string active'});
    _($self, 'hboxEditSendString')->set_sensitive($$self{_CFG}{'environments'}{$uuid}{'send string active'});
    _($self, 'cbEditSendStringIntro')->set_active($$self{_CFG}{'environments'}{$uuid}{'send string intro'});
    _($self, 'cbSendStringOnlyWhenIdle')->set_active($$self{_CFG}{'environments'}{$uuid}{'send string only when idle'});
    _($self, 'entryEditSendString')->set_text($$self{_CFG}{'environments'}{$uuid}{'send string txt'} // '');
    _($self, 'entryEditSendStringSeconds')-> set_value($$self{_CFG}{'environments'}{$uuid}{'send string every'} // 0);
    _($self, 'cbCfgAutoreconnect')->set_active($$self{_CFG}{'environments'}{$uuid}{'autoreconnect'} // 0);
    _($self, 'cbCfgStartupLaunch')->set_active($$self{_CFG}{'environments'}{$uuid}{'startup launch'} // 0);
    _($self, 'sbCfgSendSlow')->set_value($$self{_CFG}{'environments'}{$uuid}{'send slow'} // 0);
    _($self, 'cbAutossh')->set_active($$self{_CFG}{'environments'}{$uuid}{'autossh'} // 0);
    _($self, 'entryUUID')->set_text($uuid);
    _($self, 'cbCfgRemoveCtrlChars')->set_active($$self{_CFG}{'environments'}{$uuid}{'remove control chars'});
    _($self, 'cbCfgLogTimestamp')->set_active($$self{_CFG}{'environments'}{$uuid}{'log timestamp'});

    # Populate 'comboStartScript' combobox
    _($self, 'comboStartScript')->remove_all();
    my $i = my $j = -1;
    foreach my $script (sort {lc($a) cmp lc($b)} $PACMain::FUNCS{_SCRIPTS}->scriptsList) {
        ++$i;
        _($self, 'comboStartScript')->append_text($script);
        next unless defined $$self{_CFG}{'environments'}{$uuid}{'startup script name'};
        $$self{_CFG}{'environments'}{$uuid}{'startup script name'} eq $script and $j = $i;
    }
    _($self, 'comboStartScript')->set_active($j >= 0 ? $j : ($i >= 0 ? 0 : -1) );
    _($self, 'comboStartScript')->set_sensitive(($$self{_CFG}{'environments'}{$uuid}{'startup script'} // 0) && ($j >= 0) );
    _($self, 'cbStartScript')->set_active(($$self{_CFG}{'environments'}{$uuid}{'startup script'} // 0) && ($j >= 0) );


    if (_($self, 'rbCfgAuthPublicKey')->get_active()) {
        _($self, 'entryPassphrase')->get_chars(0, -1) or _($self, 'entryPassphrase')->set_text(_($self, 'entryPassword')->get_chars(0, -1) );
    }

    ##################
    # Specific options
    ##################
    $$self{_SPECIFIC}->update($$self{_CFG}{'environments'}{$uuid});
    $$self{_TERMOPTS}->update($$self{_CFG}{'environments'}{$uuid}{'terminal options'});
    $$self{_VARIABLES}->update($$self{_CFG}{'environments'}{$uuid}{'variables'});
    $$self{_PRE_EXEC}->update($$self{_CFG}{'environments'}{$uuid}{'local before'}, $$self{_CFG}{'environments'}{$uuid}{'variables'});
    $$self{_POST_EXEC}->update($$self{_CFG}{'environments'}{$uuid}{'local after'}, $$self{_CFG}{'environments'}{$uuid}{'variables'});
    $$self{_MACROS}->update($$self{_CFG}{'environments'}{$uuid}{'macros'}, $$self{_CFG}{'environments'}{$uuid}{'variables'}, 'remote', $uuid);
    $$self{_LOCAL_EXEC}->update($$self{_CFG}{'environments'}{$uuid}{'local connected'}, $$self{_CFG}{'environments'}{$uuid}{'variables'}, 'local', $uuid);
    _($self, 'frameExpect')->set_sensitive(! _($self, 'rbCfgAuthManual')->get_active());
    _($self, 'labelExpect')->set_sensitive(! _($self, 'rbCfgAuthManual')->get_active());
    $$self{_EXPECT_EXEC}->update($$self{_CFG}{'environments'}{$uuid}{'expect'}, $$self{_CFG}{'environments'}{$uuid}{'variables'});

    &{$$self{_METHODS}{_($self, 'comboMethod')->get_active_text()}{'updateGUI'}}($$self{_CFG}{'environments'}{$$self{_UUID}});

    ##########################################################################################################
    $$self{_WINDOWEDIT}->show_all(); # Without this line, $$self{_SPECIFIC} widgets WILL NOT BE SHOWN!!!!!!!!!
    $$self{_WINDOWEDIT}->present();
    ##########################################################################################################
    _($self, 'rbCfgAuthUserPass')->set_active($$self{_CFG}{'environments'}{$uuid}{'auth type'} eq 'userpass');
    _($self, 'rbCfgAuthPublicKey')->set_active($$self{_CFG}{'environments'}{$uuid}{'auth type'} eq 'publickey');
    _($self, 'rbCfgAuthManual')->set_active($$self{_CFG}{'environments'}{$uuid}{'auth type'} eq 'manual');
    $self->__checkRBAuth();

    if ($$self{_CFG}{'environments'}{$uuid}{'_protected'}) {
        _($self, 'imgProtectedEdit')->set_from_stock('asbru-protected', 'button');
        _($self, 'btnSaveEdit')->set_sensitive(0);
        _($self, 'lblProtectedEdit')->set_markup('Connection is <b><span foreground="#E60023">PROTECTED</span></b> against changes. You <b>can not</b> save changes.');
    } else {
        _($self, 'imgProtectedEdit')->set_from_stock('asbru-unprotected', 'button');
        _($self, 'btnSaveEdit')->set_sensitive(1);
        _($self, 'lblProtectedEdit')->set_markup('Connection is <b><span foreground="#04C100">UNPROTECTED</span></b> against changes. You <b>can</b> save changes.');
    }

    # Show Jump options in network settings (only for SSH method)
    if ($$self{_CFG}{'environments'}{$uuid}{'method'} =~ /SSH|SFTP/i) {
        # Control SSH capabilities
        my $ssh = `$ENV{'ASBRU_ENV_FOR_EXTERNAL'} ssh 2>&1`;
        $ssh =~ s/\n//g;
        $ssh =~ s/[ \t][ \t]+/ /g;
        if ($ssh =~ /-J /) {
            # Enable Jump Host
            _($self, 'rbUseProxyJump')->set_tooltip_text("If selected, use a jump host for this connection.\n\nAn alternative to SSH tunneling to access internal machines through gateway.");
        } else {
            # Jump Host cannot be used, will need to create a SSH tunnel to simulate
            _($self, 'rbUseProxyJump')->set_tooltip_text("If selected, use a SSH tunnel to simulate a jump host for this connection.");
        }
        _($self, 'vboxJumpCfg')->set_visible(1);
        _($self, 'rbUseProxyJump')->set_sensitive(1);
        _($self, 'vboxJumpCfgOptions')->set_sensitive(_($self, 'rbUseProxyJump')->get_active());
    } elsif ($$self{_CFG}{'environments'}{$uuid}{'method'} =~ /VNC|RDP/) {
        _($self, 'vboxJumpCfg')->set_visible(1);
        _($self, 'rbUseProxyJump')->set_sensitive(1);
        _($self, 'rbUseProxyJump')->set_tooltip_text("If selected, use a SSH tunnel to simulate a jump host for this connection.");
        _($self, 'vboxJumpCfgOptions')->set_sensitive(_($self, 'rbUseProxyJump')->get_active());
    } else {
        _($self, 'vboxJumpCfg')->set_visible(0);
        _($self, 'rbUseProxyJump')->set_sensitive(0);
        _($self, 'vboxJumpCfgOptions')->set_sensitive(0);
    }

    _updateCfgProxyKeePass($self);

    return 1;
}

sub _saveConfiguration {
    my $self = shift;
    my $uuid = $$self{_UUID};

    ##################################################################################
    # Before saving, check that the data is valid/enough for this connection method...
    ##################################################################################
    my @faults = &{$$self{_METHODS}{_($self, 'comboMethod')->get_active_text()}{'checkCFG'}}($$self{_CFG}{'environments'}{$$self{_UUID}});
    $$self{_SPECIFIC}->get_cfg =~ /^CONFIG ERROR: (.+)/go and push(@faults, $1);
    if (scalar(@faults) ) {
        _wMessage($$self{_WINDOWEDIT}, "<b>Please, check:</b>\n\n" . (join("\n", @faults) ) . "\n\n<b>before saving this connection data!!</b>");
        return 0;
    }

    # Check if proxy ip and port are defined in case "force use proxy" is checked
    if ((_($self, 'rbUseProxyAlways')->get_active() == 1) && (!_($self,'entryCfgProxyConnIP')->get_chars(0,-1) || ! _($self, 'entryCfgProxyConnPort')->get_chars(0,-1))) {
        _wMessage($$self{_WINDOWEDIT}, "<b>Please, check:</b>\n\nSOCKS IP / PORT can't be empty\n\n<b>before saving this connection data!!</b>");
        return 0;
    }

    ##############################
    # IP, Port, User, Pass, ...
    ##############################

    if (_($self, 'rbUseProxyIfCFG')->get_active()) {
        $$self{_CFG}{'environments'}{$uuid}{'use proxy'} = 0;
    } elsif (_($self, 'rbUseProxyAlways')->get_active()) {
        $$self{_CFG}{'environments'}{$uuid}{'use proxy'} = 1;
    } elsif (_($self, 'rbUseProxyJump')->get_active()) {
        $$self{_CFG}{'environments'}{$uuid}{'use proxy'} = 3;
    } else {
        $$self{_CFG}{'environments'}{$uuid}{'use proxy'} = 2;
    }
    # SOCKS Proxy
    $$self{_CFG}{'environments'}{$uuid}{'proxy ip'} = _($self, 'entryCfgProxyConnIP')->get_chars(0, -1);
    $$self{_CFG}{'environments'}{$uuid}{'proxy port'} = _($self, 'entryCfgProxyConnPort')->get_chars(0, -1);
    $$self{_CFG}{'environments'}{$uuid}{'proxy user'} = _($self, 'entryCfgProxyConnUser')->get_chars(0, -1);
    $$self{_CFG}{'environments'}{$uuid}{'proxy pass'} = _($self, 'entryCfgProxyConnPassword')->get_chars(0, -1);
    # Jump server
    $$self{_CFG}{'environments'}{$uuid}{'jump ip'} = _($self, 'entryCfgJumpConnIP')->get_chars(0, -1);
    $$self{_CFG}{'environments'}{$uuid}{'jump port'} = _($self, 'entryCfgJumpConnPort')->get_chars(0, -1);
    $$self{_CFG}{'environments'}{$uuid}{'jump user'} = _($self, 'entryCfgJumpConnUser')->get_chars(0, -1);
    $$self{_CFG}{'environments'}{$uuid}{'jump pass'} = _($self, 'entryCfgJumpConnPass')->get_chars(0, -1);
    $$self{_CFG}{'environments'}{$uuid}{'pseudo jump'} = _($self, 'chkPseudoJumpServer')->get_active();
    if (_($self, 'rbCfgAuthUserPass')->get_active()) {
        $$self{_CFG}{'environments'}{$uuid}{'auth type'} = 'userpass';
    } elsif (_($self, 'rbCfgAuthPublicKey')->get_active()) {
        $$self{_CFG}{'environments'}{$uuid}{'auth type'} = 'publickey';
    } elsif (_($self, 'rbCfgAuthManual')->get_active()) {
        $$self{_CFG}{'environments'}{$uuid}{'auth type'} = 'manual';
    }
    if ($$self{_CFG}{'environments'}{$uuid}{'use proxy'} == 3) {
        $$self{_CFG}{'environments'}{$uuid}{'jump key'} = _($self, 'entryCfgJumpConnKey')->get_filename() // '';
    } else {
        $$self{_CFG}{'environments'}{$uuid}{'jump key'} = '';
    }


    $$self{_CFG}{'environments'}{$uuid}{'passphrase user'} = _($self, 'entryUserPassphrase')->get_chars(0, -1);
    $$self{_CFG}{'environments'}{$uuid}{'passphrase'} = _($self, 'entryPassphrase')->get_chars(0, -1);
    my $keyfile = _($self, 'fileCfgPublicKey')->get_filename();
    if  (($keyfile)&&(!-d $keyfile)&& (-e $keyfile)) {
        $$self{_CFG}{'environments'}{$uuid}{'public key'} = $keyfile;
    } else {
        $$self{_CFG}{'environments'}{$uuid}{'public key'} = '';
    }
    $$self{_CFG}{'environments'}{$uuid}{'use prepend command'} = _($self, 'cbEditPrependCommand')->get_active();
    $$self{_CFG}{'environments'}{$uuid}{'prepend command'} = _($self, 'entryEditPrependCommand')->get_chars(0, -1);
    $$self{_CFG}{'environments'}{$uuid}{'use postpend command'} = _($self, 'cbEditPostpendCommand')->get_active();
    $$self{_CFG}{'environments'}{$uuid}{'postpend command'} = _($self, 'entryEditPostpendCommand')->get_chars(0, -1);
    $$self{_CFG}{'environments'}{$uuid}{'quote command'} = _($self, 'cbCfgQuoteCommand')->get_active();
    $$self{_CFG}{'environments'}{$uuid}{'quotepost command'} = _($self, 'cbCfgQuotePostCommand')->get_active();
    $$self{_CFG}{'environments'}{$uuid}{'use sudo'} = _($self, 'cbEditUseSudo')->get_active();
    $$self{_CFG}{'environments'}{$uuid}{'save session logs'} = _($self, 'cbEditSaveSessionLogs')->get_active();
    $$self{_CFG}{'environments'}{$uuid}{'session log pattern'} = _($self, 'entryEditLogFileName')->get_chars(0, -1);
    $$self{_CFG}{'environments'}{$uuid}{'session logs folder'} = _($self, 'btnEditSaveSessionLogs')->get_current_folder();
    $$self{_CFG}{'environments'}{$uuid}{'session logs amount'} = _($self, 'spEditSaveSessionLogs')->get_text();
    $$self{_CFG}{'environments'}{$uuid}{'ip'} = _($self, 'entryIP')->get_chars(0, -1);
    $$self{_CFG}{'environments'}{$uuid}{'port'} = _($self, 'entryPort')->get_chars(0, -1);
    $$self{_CFG}{'environments'}{$uuid}{'user'} = _($self, 'entryUser')->get_chars(0, -1);
    $$self{_CFG}{'environments'}{$uuid}{'pass'} = _($self, 'entryPassword')->get_property('text');
    $$self{_CFG}{'environments'}{$uuid}{'method'} = _($self, 'comboMethod')->get_active_text();
    $$self{_CFG}{'environments'}{$uuid}{'title'} = _($self, 'entryTabWindowTitle')->get_chars(0, -1) || "$$self{_CFG}{'environments'}{$uuid}{'name'} ";
    $$self{_CFG}{'environments'}{$uuid}{'auth fallback'} = ! _($self, 'cbCfgAuthFallback')->get_active();
    $$self{_CFG}{'environments'}{$uuid}{'send string active'} = _($self, 'cbEditSendString')->get_active();
    $$self{_CFG}{'environments'}{$uuid}{'send string txt'} = _($self, 'entryEditSendString')->get_chars(0,-1);
    $$self{_CFG}{'environments'}{$uuid}{'send string intro'} = _($self, 'cbEditSendStringIntro')->get_active();
    $$self{_CFG}{'environments'}{$uuid}{'send string only when idle'} = _($self, 'cbSendStringOnlyWhenIdle')->get_active();
    $$self{_CFG}{'environments'}{$uuid}{'send string every'} = _($self, 'entryEditSendStringSeconds')->get_chars(0, -1);
    $$self{_CFG}{'environments'}{$uuid}{'autoreconnect'} = _($self, 'cbCfgAutoreconnect')->get_active();
    $$self{_CFG}{'environments'}{$uuid}{'startup launch'} = _($self, 'cbCfgStartupLaunch')->get_active();
    $$self{_CFG}{'environments'}{$uuid}{'send slow'} = _($self, 'sbCfgSendSlow')->get_chars(0, -1);
    $$self{_CFG}{'environments'}{$uuid}{'startup script'} = _($self, 'cbStartScript')->get_active && _($self, 'comboStartScript')->get_active_text;
    $$self{_CFG}{'environments'}{$uuid}{'startup script name'} = _($self, 'comboStartScript')->get_active_text;
    $$self{_CFG}{'environments'}{$uuid}{'autossh'} = _($self, 'cbAutossh')->get_active;
    $$self{_CFG}{'environments'}{$uuid}{'remove control chars'} = _($self, 'cbCfgRemoveCtrlChars')->get_active;
    $$self{_CFG}{'environments'}{$uuid}{'log timestamp'} = _($self, 'cbCfgLogTimestamp')->get_active;

    # Remove lefovers from user in : network connections and authentication
    if ($$self{_CFG}{'environments'}{$uuid}{'auth type'} eq 'userpass') {
        $$self{_CFG}{'environments'}{$uuid}{'passphrase user'} = '';
        $$self{_CFG}{'environments'}{$uuid}{'passphrase'} = '';
    } elsif ($$self{_CFG}{'environments'}{$uuid}{'auth type'} eq 'publickey') {
        $$self{_CFG}{'environments'}{$uuid}{'user'} = '';
        $$self{_CFG}{'environments'}{$uuid}{'pass'} = '';
    } else {
        $$self{_CFG}{'environments'}{$uuid}{'passphrase user'} = '';
        $$self{_CFG}{'environments'}{$uuid}{'passphrase'} = '';
        $$self{_CFG}{'environments'}{$uuid}{'pass'} = '';
    }

    if ($$self{_CFG}{'environments'}{$uuid}{'use proxy'} == 1) {
        # Use proxy
        $$self{_CFG}{'environments'}{$uuid}{'jump ip'} = '';
        $$self{_CFG}{'environments'}{$uuid}{'jump user'} = '';
        $$self{_CFG}{'environments'}{$uuid}{'jump pass'} = '';
    } elsif ($$self{_CFG}{'environments'}{$uuid}{'use proxy'} == 3) {
        # Jump Server
        $$self{_CFG}{'environments'}{$uuid}{'proxy ip'} = '';
        $$self{_CFG}{'environments'}{$uuid}{'proxy user'} = '';
        $$self{_CFG}{'environments'}{$uuid}{'proxy pass'} = '';
    } else {
        # Global or direct connection
        $$self{_CFG}{'environments'}{$uuid}{'proxy ip'} = '';
        $$self{_CFG}{'environments'}{$uuid}{'proxy user'} = '';
        $$self{_CFG}{'environments'}{$uuid}{'proxy pass'} = '';
        $$self{_CFG}{'environments'}{$uuid}{'jump ip'} = '';
        $$self{_CFG}{'environments'}{$uuid}{'jump user'} = '';
        $$self{_CFG}{'environments'}{$uuid}{'jump pass'} = '';
    }
    ##################
    # Other options...
    ##################
    $$self{_CFG}{'environments'}{$uuid}{'options'} = $$self{_SPECIFIC}->get_cfg();
    $$self{_CFG}{'environments'}{$uuid}{'connection options'} = $$self{_SPECIFIC}->get_cfg_array();
    $$self{_CFG}{'environments'}{$uuid}{'terminal options'} = $$self{_TERMOPTS}->get_cfg();
    $$self{_CFG}{'environments'}{$uuid}{'variables'} = $$self{_VARIABLES}->get_cfg();
    $$self{_CFG}{'environments'}{$uuid}{'local before'} = $$self{_PRE_EXEC}->get_cfg();
    $$self{_CFG}{'environments'}{$uuid}{'local after'} = $$self{_POST_EXEC}->get_cfg();
    $$self{_CFG}{'environments'}{$uuid}{'expect'} = $$self{_EXPECT_EXEC}->get_cfg();
    $$self{_CFG}{'environments'}{$uuid}{'macros'} = $$self{_MACROS}->get_cfg();
    $$self{_CFG}{'environments'}{$uuid}{'local connected'} = $$self{_LOCAL_EXEC}->get_cfg();

    $$self{_CFG}{'environments'}{$uuid}{'embed'} = $$self{_SPECIFIC}->embed();

    return 1 if $$self{_IS_NEW} eq 'quick';

    $PACMain::FUNCS{_MAIN}->_setCFGChanged(1);

    # Send a signal to every started terminal for this $uuid to realize the new CFG
    map {eval {$$_{'terminal'}->_updateCFG;};} (values %PACMain::RUNNING);

    # Update the connection icon
    my $selection = $PACMain::FUNCS{_MAIN}{_GUI}{treeConnections}->get_selection();
    my $modelsort = $PACMain::FUNCS{_MAIN}{_GUI}{treeConnections}->get_model();
    my $model = $modelsort->get_model();
    my ($path) = _getSelectedRows($selection);

    $model->set($modelsort->convert_iter_to_child_iter($modelsort->get_iter($path) ), 0, $$self{_METHODS}{$$self{_CFG}{'environments'}{$uuid}{'method'}}{'icon'});

    return 1;
}

sub _closeConfiguration {
    my $self = shift;

    $$self{_WINDOWEDIT}->hide();
}

sub _updateCfgProxyKeePass {
    my $self = shift;

    _($self, 'btnEditNetworkSettingsCheckKPX')->set_sensitive($$self{'_CFG'}{'defaults'}{'keepass'}{'use_keepass'} && (_($self, 'rbUseProxyAlways')->get_active() || _($self, 'rbUseProxyJump')->get_active()));
}

# END: Define PRIVATE CLASS functions
###################################################################

1;
