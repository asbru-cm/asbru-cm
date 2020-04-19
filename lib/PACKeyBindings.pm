package PACKeyBindings;

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
    if (!$unicode && ($keyval =~ /F\d+|Page_Down|Page_Up|Home|End|Insert|KP_Enter/)) {
        if ("$alt$ctrl$shift") {
            return ($keyval,0,"$alt$ctrl$shift+$keyval");
        }
        return ($keyval,0,$keyval);
    }

    if (!$unicode || (!$ctrl && !$alt)) {
        return ($keyval,$unicode,'');
    }
    return ($keyval,$unicode,"$alt$ctrl+$keyval");
}

sub GetAction {
    my ($self,$window, $widget, $event) = @_;
    my $cfg = $self->{cfg};
    my $hk  = $self->{hotkey};

    if (!$window) {
        return '';
    }
    if (!$cfg) {
        return '';
    }
    my ($keyval, $unicode, $keymask) = $self->GetKeyMask($widget, $event);
    if (!$keymask) {
        return $keyval;
    }

    #print "$window : $keymask => $$cfg{$window}{$keymask}\n";
    #foreach my $w (sort keys %$cfg) {my $wk = $$cfg{$w};foreach my $k (keys %$wk) {print "cfg{$w}{$k} = $$cfg{$w}{$k}\n";}}

    if ($$cfg{$window}{$keymask}) {
        return $$cfg{$window}{$keymask}[1];
    } elsif ($$hk{$window}{$keymask}) {
        return $$hk{$window}{$keymask}[1];
    }
    return $keymask;
}

sub RegisterHotKey {
    my ($self,$window,$keymask,$action,$description) = @_;
    my $cfg = $self->{cfg};
    my $hk  = $self->{hotkey};

    if (!$window || !$keymask || !$action || !$description) {
        return (0,"window,keymask,action,description : are required");
    }
    if ($$cfg{$window}{$keymask}) {
        return (0,"Key binding already in use by global settings : $$cfg{$window}{$keymask}[2]");
    }
    if ($$hk{$window}{$keymask}) {
        return (0,"Key binding already in use by hotkey : $$hk{$window}{$keymask}[2]");
    }
    $$hk{$window}{$keymask} = ['User hotkey',$action,$description];
    return (1,'');
}

sub update {
    my $self = shift;
    my $cfg = shift;
    my %actions;

    if (!$cfg) {
        $self->_initCFG();
        $cfg = $self->{cfg};
    } else {
        $self->{cfg} = $cfg;
    }
    _updateDefaultCFG();
    @{$$self{frame}{keylist}{'data'}} = ();
    foreach my $w (sort keys %$cfg) {
        my $wk = $$cfg{$w};
        %actions = ();
        foreach my $k (keys %$wk) {
            $actions{$$wk{$k}[1]} = $k;
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

sub _updateDefaultCFG {
    my $self = shift;

    # Add new default keybindigs here
    # $self->_newKeyBind('app_window_name','keybind','User window name','action','user description');
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

sub _initCFG {
    my $self = shift;
    my $cfg;

    #      app_window_name  keybind       User window name    action     user description
    $$cfg{'treeFavourites'}{'Alt+e'}   = ['Favourites Tree','edit_node','Edit selected node'];
    $$cfg{'treeHistory'}{'Alt+e'}      = ['History Tree','edit_node','Edit selected node'];
    $$cfg{'treeClusters'}{'Alt+e'}     = ['Clusters Tree','edit_node','Edit selected node'];
    $$cfg{'treeConnections'}{'Alt+e'}  = ['Connections Tree','edit_node','Edit selected node'];
    $$cfg{'treeConnections'}{'Ctrl+f'} = ['Connections Tree','find','Find in connection tree'];
    $$cfg{'treeConnections'}{'Ctrl+R'} = ['Connections Tree','expand_all','Expand tree completly'];
    $$cfg{'treeConnections'}{'Ctrl+T'} = ['Connections Tree','collaps_all','Collaps tree completly'];
    $$cfg{'treeConnections'}{'Ctrl+d'} = ['Connections Tree','clone','Clone connection'];
    $$cfg{'treeConnections'}{'Ctrl+c'} = ['Connections Tree','copy','Copy node'];
    $$cfg{'treeConnections'}{'Ctrl+x'} = ['Connections Tree','copy','Cut node'];
    $$cfg{'treeConnections'}{'Ctrl+v'} = ['Connections Tree','paste','Paste node'];
    $$cfg{'treeConnections'}{'Alt+e'}  = ['Connections Tree','edit','Edit node'];
    $$cfg{'treeConnections'}{'Alt+r'}  = ['Connections Tree','protection','Toggle protection'];
    $$cfg{'treeConnections'}{'F2'}     = ['Connections Tree','rename','Rename node'];
    $$cfg{'pactabs'}{'Ctrl+Tab'}       = ['Tabs','last','Last focused Tab'];
    $$cfg{'pactabs'}{'Ctrl+Page_Down'} = ['Tabs','next','Next Tab'];
    $$cfg{'pactabs'}{'Ctrl+Page_Up'}   = ['Tabs','previous','Previous Tab'];
    $$cfg{'pactabs'}{'undef-infotab'}  = ['Tabs','infotab','Got to Info Tab'];
    $$cfg{'pacmain'}{'Ctrl+f'}         = ['Main Window','find','Find in connection tree'];
    $$cfg{'pacmain'}{'Ctrl+q'}         = ['Main Window','quit','Exit Ásbrú'];
    $$cfg{'pacmain'}{'Ctrl+t'}         = ['Main Window','localshell','Open a local shell'];
    $$cfg{'terminal'}{'F11'}           = ['Terminal','fullscreen','Go full screen'];
    $$cfg{'terminal'}{'Ctrl+Return'}   = ['Terminal','start','Start Terminal'];
    $$cfg{'terminal'}{'AltCtrl+X'}     = ['Terminal','reset','Reset Terminal'];
    $$cfg{'terminal'}{'CtrlAlt+r'}     = ['Terminal','remove_from_cluster','Remove terminal from cluster'];
    $$cfg{'terminal'}{'Ctrl+Insert'}   = ['Terminal','copy','Copy selection to clipboard'];
    $$cfg{'terminal'}{'Shift+Insert'}  = ['Terminal','paste','Paste selection into terminal'];
    $$cfg{'terminal'}{'Ctrl+p'}        = ['Terminal','paste-passwd','Paste terminal password'];
    $$cfg{'terminal'}{'Ctrl+b'}        = ['Terminal','paste-delete','Paste and delete'];
    $$cfg{'terminal'}{'Ctrl+g'}        = ['Terminal','hostname','Guess hostname'];
    $$cfg{'terminal'}{'Ctrl+w'}        = ['Terminal','close','Close Terminal'];
    $$cfg{'terminal'}{'Ctrl+q'}        = ['Terminal','quit','Exit Ásbrú'];
    $$cfg{'terminal'}{'Ctrl+f'}        = ['Terminal','find','Find in connection tree'];
    $$cfg{'terminal'}{'F4'}            = ['Terminal','closealltabs','Close all tabs'];
    $$cfg{'terminal'}{'Ctrl+n'}        = ['Terminal','close-disconected','Close disconnected sessions'];
    $$cfg{'terminal'}{'Ctrl+d'}        = ['Terminal','duplicate','Duplicate connection'];
    $$cfg{'terminal'}{'Ctrl+r'}        = ['Terminal','restart','Restart connection (close and start)'];
    $$cfg{'terminal'}{'Ctrl+i'}        = ['Terminal','infotab','Show the Info tab'];
    $$cfg{'terminal'}{'Ctrl+F3'}       = ['Terminal','find-terminal','Find Terminal'];
    $$cfg{'terminal'}{'Alt+n'}         = ['Terminal','showconnections','Show connections list'];
    $$cfg{'terminal'}{'Alt+e'}         = ['Terminal','edit','Edit Connection'];
    $$cfg{'terminal'}{'Ctrl+plus'}     = ['Terminal','zoomin','Zoom in text'];
    $$cfg{'terminal'}{'Ctrl+minus'}    = ['Terminal','zoomout','Zoom out text'];
    $$cfg{'terminal'}{'Ctrl+0'}        = ['Terminal','zoomreset','Zoom reset text'];
    $self->{cfg} = $cfg;
}

sub _buildGUI {
    my $self = shift;
    my %w;

    # Build a vbox
    $w{vbox} = Gtk3::VBox->new(0,0);
    # Attach to class attribute
    $$self{container} = $w{vbox};
    $$self{frame} = \%w;

    $w{scroll} = Gtk3::ScrolledWindow->new();
    $w{scroll}->set_overlay_scrolling(0);
    $w{scroll}->set_policy('automatic', 'automatic');
    $w{vbox}->pack_start($w{scroll},1,1,1);

    $w{keylist} = PACTree->new(
        'Window'   => 'markup',
        'Action'   => 'text',
        'Keybind'     => 'text',
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

    $w{keylist}->signal_connect('key_press_event' => sub {
        my ($widget, $event) = @_;
        my $selection = $w{keylist}->get_selection();
        my $model     = $w{keylist}->get_model();
        my @paths     = _getSelectedRows($selection);
        my ($window,$desc,$keybind,$action,$pacwin) = $model->get($model->get_iter($paths[0]));
        my ($keyval, $unicode, $keymask) = $self->GetKeyMask($widget, $event);

        #print "$keyval, $unicode, $keymask\n"; print "ROW:$window : $desc : $keybind : $action : $pacwin\n";

        if ($unicode == 8 || $unicode == 127) {
            $self->_updateKeyBinding($selection,$model,$paths[0],"undef-$action",$pacwin,$keybind);
            return 1;
        } elsif (!$keymask) {
            return 0;
        }

        if (!$keymask) {
            return 0;
        }

        #print STDERR "KEYPRESS ($desc): $keymask\n";
        $self->_updateKeyBinding($selection,$model,$paths[0],$keymask,$pacwin,$keybind);
        return 1;
    });
}

sub _updateKeyBinding {
    my ($self,$selection,$model,$path,$keynew,$window,$keyold) = @_;
    my $cfg = $self->{cfg};

    if ("$window$keynew" eq "$window$keyold") {
        return 0;
    }
    if ($$cfg{$window}{$keynew}) {
        _wMessage($self->{parent},"Keybind $keynew already in use by\n\n<b>$$cfg{$window}{$keynew}[0]</b> : $$cfg{$window}{$keynew}[2]");
        return 0;
    }
    $$cfg{$window}{$keynew} = $$cfg{$window}{$keyold};
    delete $$cfg{$window}{$keyold};
    if ($keynew =~ /^undef-/) {
        $keynew = '';
    }
    my $gvalue = Glib::Object::Introspection::GValueWrapper->new('Glib::String', $keynew);
    $model->set_value($model->get_iter($path), 2, $gvalue);
}

1;
