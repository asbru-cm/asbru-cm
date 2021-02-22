package PACKeyBindings;

###############################################################################
# This file is part of Ásbrú Connection Manager
#
# Copyright (C) 2017-2021 Ásbrú Connection Manager team (https://asbru-cm.net)
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

# GTK
use Gtk3 '-init';

# PAC modules
use PACUtils;
use PACTree;

# END: Import Modules
###################################################################

###################################################################
# Define GLOBAL CLASS variables



# END: Define GLOBAL CLASS variables
###################################################################

###################################################################
# START: Public class methods

sub new {
    my $class = shift;
    my $self;

    $self->{cfg} = shift;
    $self->{parent} = shift;
    $self->{container} = undef;
    $self->{hotkey} = {};
    $self->{verbose} = 0;

    _buildGUI($self);

    bless($self, $class);
    return $self;
}

sub GetKeyMask {
    my ($self, $widget, $event) = @_;
    my $keyval  = Gtk3::Gdk::keyval_name($event->keyval) // '';
    my $unicode = Gtk3::Gdk::keyval_to_unicode($event->keyval); # 0 if not a character
    my $state   = $event->get_state();
    my $shift   = $state * ['shift-mask']   ? 'Shift' : '';
    my $ctrl    = $state * ['control-mask'] ? 'Ctrl'  : '';
    my $alt     = $state * ['mod1-mask']    ? 'Alt'   : '';

    #print "$keyval : $unicode : $ctrl : $shift\n";

    # Test special keys
    if ($keyval =~ /^KP_(.+)/) {
        # Unify keypad and keyboard to be the same
        my $kp = $1;
        if ($kp =~ /\d/) {
            $keyval = $kp;
        } else {
            my %kp2key = ('Add','plus','Subtract','minus','Multiply','asterix','Divide','slash','Decimal','period','Enter','Return');
            if ($kp2key{$kp}) {
                $keyval = $kp2key{$kp};
            }
        }
        if (!$unicode) {
            $unicode = 1;
        }
    } elsif (!$unicode && ($keyval =~ /F\d+|Page_Down|Page_Up|Home|End|Insert|Left|Right|Up|Down|Scroll_Lock|Pause|Break/)) {
        if ("$alt$ctrl$shift") {
            return ($keyval,0,"$alt$ctrl$shift+$keyval");
        } elsif ($keyval =~ /F\d+/) {
            return ($keyval,0,$keyval);
        }
        return ($keyval,0,'');
    }

    if (!$unicode || (!$ctrl && !$alt)) {
        return ($keyval,$unicode,'');
    }
    return ($keyval,$unicode,"$alt$ctrl+$keyval");
}

sub GetAction {
    my ($self, $window, $widget, $event, $uuid) = @_;
    my $cfg = $self->{cfg};
    my $hk  = $self->{hotkey};

    if (!$window) {
        return wantarray ? (0,'') : '';
    }
    if (!$cfg) {
        return wantarray ? (0,'') : '';
    }
    my ($keyval, $unicode, $keymask) = $self->GetKeyMask($widget, $event);
    if (!$keymask) {
        return wantarray ? ($keyval,'') : $keyval;
    }
    if ($$cfg{$window}{$keymask}) {
        return wantarray ? ($$cfg{$window}{$keymask}[1],$keymask) : $$cfg{$window}{$keymask}[1];
    } elsif ($uuid && $$hk{$uuid}{$window}{$keymask}) {
        return wantarray ? ($$hk{$uuid}{$window}{$keymask}[1],$keymask) : $$hk{$uuid}{$window}{$keymask}[1];
    } elsif ($$hk{$window}{$keymask}) {
        return wantarray ? ($$hk{$window}{$keymask}[1],$keymask) : $$hk{$window}{$keymask}[1];
    }
    return wantarray ? ($keymask,'') : $keymask;
}

sub GetHotKeyCommand {
    my ($self,$window,$keymask,$uuid) = @_;
    my $hk  = $self->{hotkey};
    my $cmd = $$hk{$window}{$keymask}[2];

    if ($uuid && $$hk{$uuid}{$window}{$keymask}[2]) {
        $cmd = $$hk{$uuid}{$window}{$keymask}[2];
    }
    if (defined $cmd && $cmd eq '') {
        return (0,'');
    }
    if ($cmd =~ s/^\?//) {
        return (1,$cmd);
    }
    return (0,$cmd);
}

sub ListKeyBindings {
    my ($self,$window) = @_;
    my $cfg = $self->{cfg};
    my $kbs = $$cfg{$window};
    my $list = "<b>Keybindings for : $window</b>\n\n<span font_family='monospace'>";
    my $tab = '';

    foreach my $kb (sort keys %$kbs) {
        if ($kb =~ /^undef-/) {
            next;
        }
        $list .= sprintf("<b>%-20s</b>$tab\t%s\n",$kb,$$kbs{$kb}[2]);
    }
    return "$list</span>";
}

sub GetAccelerator {
    my ($self,$window,$action) = @_;
    my $cfg = $self->{cfg};
    my $kbs = $$cfg{$window};
    my $acc = '';

    foreach my $kb (sort keys %$kbs) {
        if ($$kbs{$kb}[1] eq $action) {
            my ($mod,$key) = split /\+/,$kb;
            if (!$key) {
                $key = $mod;
            }
            if ($kb =~ /^undef-/) {
                next;
            }
            if ($kb =~ /Ctrl/) {
                $acc .= '<control>';
            }
            if ($kb =~ /Alt/) {
                $acc .= '<alt>';
            }
            if ($kb =~ /Shift/) {
                $acc .= '<shift>';
            }
            if ($key =~ /[A-Z]/) {
                $acc .= '<shift>';
            }
            $acc .= $key;
            last;
        }
    }
    return $acc;
}

sub LoadHotKeys {
    my ($self,$cfg,$uuid) = @_;
    my $CFG = {};
    my @what;

    if ($uuid) {
        $CFG = $$cfg{'environments'}{$uuid};
        @what = ('macros','local connected');
    } else {
        $CFG = $$cfg{'defaults'};
        @what = ('remote commands','local commands');
    }
    foreach my $w (@what) {
        foreach my $hash (@{$$CFG{$w}}) {
            if ($$hash{keybind}) {
                my $lf  = $$hash{intro} ? "\n" : '';
                my $ask = $$hash{confirm} ? "?" : '';
                $self->RegisterHotKey('terminal',$$hash{keybind},"HOTKEY_CMD:$w","$ask$$hash{txt}$lf",$uuid);
            }
        }
    }
}

# This function overwrites duplicated keybindings
# Programmer should use HotKeyIsFree, to avoid duplicates
sub RegisterHotKey {
    my ($self,$window,$keymask,$action,$command,$uuid) = @_;
    my $cfg = $self->{cfg};
    my $hk  = $self->{hotkey};

    if (!$window || !$keymask || !$action || !$command) {
        return (0,"window,keymask,action,command : are required");
    }
    if ($uuid) {
        $$hk{$uuid}{$window}{$keymask} = ['User hotkey',$action,$command];
    } else {
        $$hk{$window}{$keymask} = ['User hotkey',$action,$command];
    }
    return (1,'');
}

sub UnRegisterHotKey {
    my ($self,$window,$keymask,$uuid) = @_;
    my $cfg = $self->{cfg};
    my $hk  = $self->{hotkey};

    if (!$window || !$keymask) {
        return (0,"window,keymask : are required");
    }
    if ($uuid) {
        delete $$hk{$uuid}{$window}{$keymask};
    } else {
        delete $$hk{$window}{$keymask};
    }
    return (1,'');
}

sub HotKeyIsFree {
    my ($self,$window,$keymask,$uuid,$hotkey_only) = @_;
    my $cfg = $self->{cfg};
    my $hk  = $self->{hotkey};

    if (!$window || !$keymask) {
        return (0,"window,keymask : are required");
    }
    if ($$hk{$window}{$keymask}) {
        return (0,"<i>$keymask</i> already assigned to <b>hotkey</b>\n\n$$hk{$window}{$keymask}[2]");
    }
    if ($uuid && $$hk{$uuid}{$window}{$keymask}) {
        return (0,"<i>$keymask</i> already assigned to <b>hotkey</b>\n\n$$hk{$window}{$keymask}[2]");
    }
    if ($hotkey_only) {
        return (1,'');
    }
    # Full check other windows
    if ($$cfg{$window}{$keymask}) {
        return (0,"<i>$keymask</i> already assigned to <b>$$cfg{$window}{$keymask}[0]</b>\n\n$$cfg{$window}{$keymask}[2]");
    }
    foreach my $w (sort keys %$cfg) {
        if ($w eq $window) {
            next;
        }
        if ($$cfg{$w}{$keymask}) {
            return (0,"<i>$keymask</i> already assigned to <b>$$cfg{$w}{$keymask}[0]</b>\n\n$$cfg{$w}{$keymask}[2]");
        }
    }
    return (1,'');
}

sub update {
    my $self = shift;
    my $cfg = shift;
    my $default_cfg = $self->_getDefaultConfig();
    my %actions;

    if (!$cfg && !$self->{cfg}) {
        $cfg = $default_cfg;
    } elsif ($cfg) {
        $self->{cfg} = $cfg;
    } else {
        $cfg = $self->{cfg};
    }

    $self->_updateConfig($default_cfg);

    @{$$self{frame}{keylist}{'data'}} = ();
    foreach my $w (sort keys %$cfg) {
        my $wk = $$cfg{$w};
        %actions = ();
        foreach my $k (keys %$wk) {
            $actions{$$wk{$k}[2]} = $k;
        }
        foreach my $a (sort keys %actions) {
            my $k = $actions{$a};
            my $kb = $k;
            if ($kb =~ /^undef-/) {
                $kb = '';
            }
            push(@{$$self{frame}{keylist}{'data'}}, {value => [ "<b>$$wk{$k}[0]</b>",$$wk{$k}[2],$kb,$$wk{$k}[1],$w ], children => []});
        }
    }
}

sub get_cfg {
    my $self = shift;

    return $self->{cfg};
}

# END: Public class methods
###################################################################

###################################################################
# START: Private Methods

# Check if we have a new keybinding in the default configuration that needs to be added
# This is required to add the new keybindings that were not existing when the current
# configuration has been created.
sub _updateConfig {
    my $self = shift;
    my $default_cfg = shift // $self->_getDefaultConfig();
    my %keybindings = ();

    # List all keybindings in default configurating
    foreach my $w (keys %$default_cfg) {
        my $wk = $$default_cfg{$w};
        foreach my $k (keys %$wk) {
            my $action = $$wk{$k}[1];
            %{$keybindings{"$w-$action"}} = ('window' => $w, 'key' => $k);
        }
    }
    # Remove all used keybindings defined in the current configuration
    foreach my $w (keys %{$self->{cfg}}) {
        my $cfg = $self->{cfg};
        my $wk = $$cfg{$w};
        foreach my $k (keys %$wk) {
            my $action = $$wk{$k}[1];
            if (defined($keybindings{"$w-$action"})) {
                delete $keybindings{"$w-$action"};
            }
        }
    }
    # Any remaining keybinding is a newly added keybinding that needs to be added to the current configuration
    foreach my $ka (keys %keybindings) {
        my $k = $keybindings{$ka}{key};
        my $w = $keybindings{$ka}{window};
        my $wk = $$default_cfg{$w};
        print("WARN: Adding new keybinding [$k] for [$$wk{$k}[0]]/[$$wk{$k}[2]]...\n");
        ${$self->{cfg}}{$w}{$k} = $$wk{$k};
    }
}

sub _newKeyBind {
    my ($self,$appwin,$keybind,$window,$action,$desc) = @_;
    my $cfg = $self->{cfg};

    if ($self->_exists($appwin,$action)) {
        return 0;
    }
    $$cfg{$appwin}{$keybind} = [$window,$action,$desc];
}

sub _exists {
    my ($self,$appwin,$action) = @_;
    my $cfg = $self->{cfg};
    my $wk = $$cfg{$appwin};

    if (!$wk) {
        return 0;
    }
    foreach my $k (keys %$wk) {
        if ($$wk{$k}[1] eq $action) {
            return 1;
        }
    }
    return 0;
}

sub _getDefaultConfig {
    my $self = shift;
    my $cfg;

    #      app_window_name  keybind       User window name    action     user description
    $$cfg{'treeFavourites'}{'Alt+e'}   = ['Favourites Tree','edit_node','Edit selected node'];
    $$cfg{'treeFavourites'}{'Alt+F'}   = ['Favourites Tree','del_favourite','Remove connection from favourites'];
    $$cfg{'treeHistory'}{'Alt+e'}      = ['History Tree','edit_node','Edit selected node'];
    $$cfg{'treeClusters'}{'Alt+e'}     = ['Clusters Tree','edit_node','Edit selected node'];
    $$cfg{'treeConnections'}{'Alt+e'}  = ['Connections Tree','edit_node','Edit selected node'];
    $$cfg{'treeConnections'}{'Alt+f'}  = ['Connections Tree','add_favourite','Add connection to favourites'];
    $$cfg{'treeConnections'}{'Alt+F'}  = ['Connections Tree','del_favourite','Remove connection from favourites'];
    $$cfg{'treeConnections'}{'Ctrl+f'} = ['Connections Tree','find','Find in connection tree'];
    $$cfg{'treeConnections'}{'Ctrl+r'} = ['Connections Tree','expand_all','Expand tree completly'];
    $$cfg{'treeConnections'}{'Ctrl+t'} = ['Connections Tree','collaps_all','Collaps tree completly'];
    $$cfg{'treeConnections'}{'Ctrl+d'} = ['Connections Tree','clone','Clone connection'];
    $$cfg{'treeConnections'}{'Ctrl+c'} = ['Connections Tree','copy','Copy node'];
    $$cfg{'treeConnections'}{'Ctrl+x'} = ['Connections Tree','cut','Cut node'];
    $$cfg{'treeConnections'}{'Ctrl+v'} = ['Connections Tree','paste','Paste node'];
    $$cfg{'treeConnections'}{'Alt+r'}  = ['Connections Tree','protection','Toggle protection'];
    $$cfg{'treeConnections'}{'F2'}     = ['Connections Tree','rename','Rename node'];
    $$cfg{'treeConnections'}{'Alt+c'}  = ['Connections Tree','connect_node','Connect selected node'];
    $$cfg{'pactabs'}{'Ctrl+F4'}        = ['Tabs','close','Close current Tab'];
    $$cfg{'pactabs'}{'Ctrl+Tab'}       = ['Tabs','last','Last focused Tab'];
    $$cfg{'pactabs'}{'Ctrl+Page_Down'} = ['Tabs','next','Next Tab'];
    $$cfg{'pactabs'}{'Ctrl+Page_Up'}   = ['Tabs','previous','Previous Tab'];
    $$cfg{'pactabs'}{'undef-infotab'}  = ['Tabs','infotab','Got to Info Tab'];
    $$cfg{'pacmain'}{'Ctrl+f'}         = ['Main Window','find','Find in connection tree'];
    $$cfg{'pacmain'}{'Ctrl+q'}         = ['Main Window','quit','Exit Ásbrú'];
    $$cfg{'pacmain'}{'Ctrl+T'}         = ['Main Window','localshell','Open a local shell'];
    $$cfg{'pacmain'}{'Alt+n'}          = ['Main Window','showconnections','Show/Hide connections list'];
    $$cfg{'terminal'}{'F11'}           = ['Terminal','fullscreen','Go full screen'];
    $$cfg{'terminal'}{'Ctrl+Return'}   = ['Terminal','start','Start Terminal'];
    $$cfg{'terminal'}{'AltCtrl+x'}     = ['Terminal','reset','Reset Terminal'];
    $$cfg{'terminal'}{'AltCtrl+X'}     = ['Terminal','reset-clear','Reset Terminal and Clear window'];
    $$cfg{'terminal'}{'CtrlAlt+r'}     = ['Terminal','remove_from_cluster','Remove terminal from cluster'];
    $$cfg{'terminal'}{'Ctrl+C'}        = ['Terminal','copy','Copy selection to clipboard'];
    $$cfg{'terminal'}{'Ctrl+V'}        = ['Terminal','paste','Paste clipboard into terminal'];
    $$cfg{'terminal'}{'Ctrl+Insert'}   = ['Terminal','copy','Copy selection to clipboard'];
    $$cfg{'terminal'}{'Shift+Insert'}  = ['Terminal','paste-primary','Paste selection into terminal'];
    $$cfg{'terminal'}{'Ctrl+p'}        = ['Terminal','paste-passwd','Paste terminal password'];
    $$cfg{'terminal'}{'Ctrl+b'}        = ['Terminal','paste-delete','Paste and regex delete'];
    $$cfg{'terminal'}{'Ctrl+g'}        = ['Terminal','hostname','Guess hostname'];
    $$cfg{'terminal'}{'Ctrl+w'}        = ['Terminal','close','Close Terminal'];
    $$cfg{'terminal'}{'Ctrl+W'}        = ['Terminal','disconnect','Disconnect Terminal'];
    $$cfg{'terminal'}{'Ctrl+q'}        = ['Terminal','quit','Exit Ásbrú'];
    $$cfg{'terminal'}{'Ctrl+f'}        = ['Terminal','find','Find in connection tree'];
    $$cfg{'terminal'}{'CtrlShift+F4'}  = ['Terminal','closealltabs','Close all tabs'];
    $$cfg{'terminal'}{'Ctrl+N'}        = ['Terminal','close-disconected','Close disconnected sessions'];
    $$cfg{'terminal'}{'Ctrl+D'}        = ['Terminal','duplicate','Duplicate connection'];
    $$cfg{'terminal'}{'Ctrl+R'}        = ['Terminal','restart','Restart connection (close and start)'];
    $$cfg{'terminal'}{'Ctrl+I'}        = ['Terminal','infotab','Show the Info tab'];
    $$cfg{'terminal'}{'Ctrl+F3'}       = ['Terminal','find-terminal','Find Terminal'];
    $$cfg{'terminal'}{'Alt+n'}         = ['Terminal','showconnections','Show/Hide connections list'];
    $$cfg{'terminal'}{'Alt+e'}         = ['Terminal','edit_node','Edit Connection'];
    $$cfg{'terminal'}{'Ctrl+plus'}     = ['Terminal','zoomin','Zoom in text'];
    $$cfg{'terminal'}{'Ctrl+minus'}    = ['Terminal','zoomout','Zoom out text'];
    $$cfg{'terminal'}{'Ctrl+0'}        = ['Terminal','zoomreset','Zoom reset text'];
    $$cfg{'terminal'}{'Ctrl+ampersand'}= ['Terminal','cisco','Send Cisco interrupt keypress'];
    $$cfg{'terminal'}{'AltCtrl+s'}     = ['Terminal','sftp','Open SFTP session'];

    return $cfg;
}

sub _buildGUI {
    my $self = shift;
    my %w;

    # Build a vbox
    $w{vbox} = Gtk3::VBox->new(0,0);
    $w{hbox} = Gtk3::HBox->new(0, 0);

    # Attach to class attribute
    $$self{container} = $w{vbox};
    $$self{frame} = \%w;
    $w{vbox}->pack_start($w{hbox}, 0, 1, 0);

    $w{btnreset} = Gtk3::Button->new('Set default values');
    $w{hbox}->pack_start($w{btnreset}, 0, 0, 0);

    $w{help} = Gtk3::LinkButton->new('https://docs.asbru-cm.net/Manual/Preferences/KeyBindings/');
    $w{help}->set_halign('GTK_ALIGN_END');
    $w{help}->set_label('');
    $w{help}->set_tooltip_text('Open Online Help');
    $w{help}->set_always_show_image(1);
    $w{help}->set_image(Gtk3::Image->new_from_stock('asbru-help', 'button'));
    $w{hbox}->pack_start($w{help}, 1, 1, 0);

    $w{scroll} = Gtk3::ScrolledWindow->new();
    $w{scroll}->set_overlay_scrolling(1);
    $w{scroll}->set_policy('automatic', 'automatic');
    $w{vbox}->pack_start($w{scroll},1,1,1);

    $w{keylist} = PACTree->new(
        'Window'   => 'markup',
        'Action'   => 'text',
        'Keybind'  => 'text',
        'kbaction' => 'hidden',
        'pacwin'   => 'hidden',
    );
    $w{keylist}->set_enable_tree_lines(0);
    $w{keylist}->set_headers_visible(1);
    $w{keylist}->set_enable_search(0);
    $w{keylist}->set_has_tooltip(0);
    $w{keylist}->set_show_expanders(0);
    $w{keylist}->set_activate_on_single_click(1);
    $w{keylist}->set_grid_lines('GTK_TREE_VIEW_GRID_LINES_NONE');
    $w{keylist}->get_selection()->set_mode('GTK_SELECTION_SINGLE');
    $w{scroll}->add($w{keylist});
    my @col = $w{keylist}->get_columns();
    $col[2]->set_alignment(0.5);
    my ($c) = $col[2]->get_cells();
    $c->set_alignment(0.5,0.5);

    $w{btnreset}->signal_connect('clicked' => sub {
        if (!_wConfirm($self->{parent}, "Reset all keybindings to there default values?")) {
            return 1;
        }
        delete $self->{cfg};
        $self->update();
    });
    $w{keylist}->signal_connect('key_press_event' => sub {
        my ($widget, $event) = @_;
        my $selection = $w{keylist}->get_selection();
        my $model     = $w{keylist}->get_model();
        my @paths     = _getSelectedRows($selection);

        if (!@paths) {
            return 0;
        }

        my ($window,$desc,$keybind,$action,$pacwin) = $model->get($model->get_iter($paths[0]));
        my ($keyval, $unicode, $keymask) = $self->GetKeyMask($widget, $event);

        if ($self->{verbose}) {
            print "INFO: KEY: $keyval, $unicode, $keymask\n";
            print "INFO: ROW: $window : $desc : $keybind : $action : $pacwin\n";
        }

        if (!$keymask && ($unicode == 8 || $unicode == 127)) {
            $self->_updateKeyBinding($selection,$model,$paths[0],"undef-$action",$pacwin,$keybind,$action);
            return 1;
        } elsif (!$keymask) {
            return 0;
        }

        $self->_updateKeyBinding($selection,$model,$paths[0],$keymask,$pacwin,$keybind,$action);
        return 1;
    });
}

sub _updateKeyBinding {
    my ($self,$selection,$model,$path,$keynew,$window,$keyold,$action) = @_;
    my $cfg = $self->{cfg};
    my $undef = $keynew =~ /^undef-/;

    if ("$window$keynew" eq "$window$keyold") {
        return 0;
    } elsif ($$cfg{$window}{$keynew} && $undef) {
        return 0;
    }

    if ($$cfg{$window}{$keynew}) {
        _wMessage($self->{parent},"<i>$keynew</i> already in use by\n\n<b>$$cfg{$window}{$keynew}[0]</b> : $$cfg{$window}{$keynew}[2]");
        return 0;
    } elsif (!$undef) {
        my ($free,$msg) = $self->HotKeyIsFree('terminal',$keynew,'',1);
        if (!$free) {
            _wMessage($self->{parent},$msg);
            return 0;
        }
        foreach my $w (sort keys %$cfg) {
            if ($w eq $window) {
                next;
            }
            if ($$cfg{$w}{$keynew}) {
                my $warning = '';
                my $other = '';

                if ($$cfg{$window}{"undef-$action"}) {
                    $other = $$cfg{$window}{"undef-$action"}[0];
                } else {
                    $other = $$cfg{$window}{$keyold}[0];
                }

                if ($w lt $window) {
                    $warning = "This keybind will not be available when <b>$$cfg{$w}{$keynew}[0]</b> is visible.";
                } else {
                    $warning = "This keybind will not be available for window <b>$$cfg{$w}{$keynew}[0]</b>\nwhen <b>$other</b> is visible.";
                }
                _wMessage($self->{parent},"<i>$keynew</i> used in\n\n<b>$$cfg{$w}{$keynew}[0]</b> : $$cfg{$w}{$keynew}[2]\n\n$warning");
            }
        }
    }
    if ($$cfg{$window}{"undef-$action"}) {
        $$cfg{$window}{$keynew} = $$cfg{$window}{"undef-$action"};
        delete $$cfg{$window}{"undef-$action"};
    } else {
        $$cfg{$window}{$keynew} = $$cfg{$window}{$keyold};
        delete $$cfg{$window}{$keyold};
    }
    if ($undef) {
        $keynew = '';
    }
    $model->set_value($model->get_iter($path), 2, Glib::Object::Introspection::GValueWrapper->new('Glib::String', $keynew));
}

# END: Private Methods
###################################################################

1;
