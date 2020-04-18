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
    my $buildgui = shift;
    my $self;

    $self->{cfg} = shift;
    $self->{container} = undef;

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

    if (!$unicode && ($keyval =~ /F\d+|Page_Down|Page_Up|Home|End|Insert|KP_Enter/)) {
        return ($keyval,1,"$alt$ctrl$shift$keyval");
    }

    if (!$unicode || (!$ctrl && !$alt)) {
        return ($keyval,$unicode,'');
    }
    return ($keyval,$unicode,"$alt$ctrl+$keyval");
}

sub GetAction {
    my ($self,$window, $widget, $event) = @_;
    my $cfg = $self->{cfg};

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
    if ($$cfg{$window}{$keymask}) {
        return $$cfg{$window}{$keymask}[1];
    }
    return $keymask;
}

sub update {
    my $self = shift;
    my $cfg;
    my %actions;

    if (!$self->{cfg}) {
        $self->_initCFG();
    }
    $cfg = $self->{cfg};
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
            push(@{$$self{frame}{keylist}{'data'}}, {value => [ $$wk{$k}[0],$$wk{$k}[2],$kb,$$wk{$k}[1] ], children => []});
        }
    }
}

sub get_cfg {
}

# END: Public class methods
###################################################################

###################################################################
# START: Private Methods

sub _initCFG {
    my $self = shift;
    my $cfg = $self->{cfg};

    $$cfg{'treeFavourites'}{'Alt+e'} = ['Favourites Tree','edit_node','Edit selected node'];
    $$cfg{'treeHistory'}{'Alt+e'} = ['History Tree','edit_node','Edit selected node'];
    $$cfg{'treeClusters'}{'Alt+e'} = ['Clusters Tree','edit_node','Edit selected node'];
    $$cfg{'treeConnections'}{'Alt+e'} = ['Connections Tree','edit_node','Edit selected node'];
    $$cfg{'treeConnections'}{'Ctrl+f'} = ['Connections Tree','find','Find in connection tree'];
    $$cfg{'treeConnections'}{'Ctrl+r'} = ['Connections Tree','expand_all','Expand tree completly'];
    $$cfg{'treeConnections'}{'Ctrl+t'} = ['Connections Tree','collaps_all','Collaps tree completly'];
    $$cfg{'treeConnections'}{'Ctrl+d'} = ['Connections Tree','clone','Clone connection'];
    $$cfg{'treeConnections'}{'Ctrl+c'} = ['Connections Tree','copy','Copy node'];
    $$cfg{'treeConnections'}{'Ctrl+x'} = ['Connections Tree','copy','Cut node'];
    $$cfg{'treeConnections'}{'Ctrl+v'} = ['Connections Tree','paste','Paste node'];
    $$cfg{'treeConnections'}{'Alt+e'} = ['Connections Tree','edit','Edit node'];
    $$cfg{'treeConnections'}{'Alt+r'} = ['Connections Tree','protection','Toggle protection'];
    $$cfg{'treeConnections'}{'F2'} = ['Connections Tree','rename','Rename node'];
    $$cfg{'pactabs'}{'Ctrl+Tab'} = ['Tabbed terminals','last','Last Tab'];
    $$cfg{'pactabs'}{'CtrlPage_Down'} = ['Tabbed terminals','next','Next Tab'];
    $$cfg{'pactabs'}{'CtrlPage_Up'} = ['Tabbed terminals','previous','Previous Tab'];
    $$cfg{'pactabs'}{'undef-infotab'} = ['Tabbed terminals','infotab','Got to Info Tab'];
    $$cfg{'pacmain'}{'Ctrl+f'} = ['Main Window','find','Find in connection tree'];
    $$cfg{'pacmain'}{'Ctrl+q'} = ['Main Window','quit','Exit Ásbrú'];
    $$cfg{'pacmain'}{'Ctrl+t'} = ['Main Window','localshell','Open a local shell'];
    $$cfg{'terminal'}{'F11'} = ['Terminal','fullscreen','Go full screen'];
    $$cfg{'terminal'}{'Ctrl+Return'} = ['Terminal','start','Start Terminal'];
    $$cfg{'terminal'}{'AltCtrl+X'} = ['Terminal','reset','Reset Terminal'];
    $$cfg{'terminal'}{'CtrlAlt+r'} = ['Terminal','remove_from_cluster','Remove terminal from cluster'];
    $$cfg{'terminal'}{'CtrlInsert'} = ['Terminal','copy','Copy selection to clipboard'];
    $$cfg{'terminal'}{'ShiftInsert'} = ['Terminal','paste','Paste selection into terminal'];
    $$cfg{'terminal'}{'Ctrl+p'} = ['Terminal','paste-passwd','Paste terminal password'];
    $$cfg{'terminal'}{'Ctrl+b'} = ['Terminal','paste-delete','Paste and delete'];
    $$cfg{'terminal'}{'Ctrl+g'} = ['Terminal','hostname','Guess hostname'];
    $$cfg{'terminal'}{'Ctrl+w'} = ['Terminal','close','Close Terminal'];
    $$cfg{'terminal'}{'Ctrl+q'} = ['Terminal','quit','Exit Ásbrú'];
    $$cfg{'terminal'}{'Ctrl+f'} = ['Terminal','find','Find in connection tree'];
    $$cfg{'terminal'}{'F4'} = ['Terminal','closealltabs','Close all tabs'];
    $$cfg{'terminal'}{'Ctrl+n'} = ['Terminal','close-disconected','Close disconnected sessions'];
    $$cfg{'terminal'}{'Ctrl+d'} = ['Terminal','duplicate','Duplicate connection'];
    $$cfg{'terminal'}{'Ctrl+r'} = ['Terminal','restart','Restart connection (close and start)'];
    $$cfg{'terminal'}{'Ctrl+i'} = ['Terminal','infotab','Show the Info tab'];
    $$cfg{'terminal'}{'CtrlF3'} = ['Terminal','find-terminal','Find Terminal'];
    $$cfg{'terminal'}{'Alt+n'} = ['Terminal','showconnections','Show connections list'];
    $$cfg{'terminal'}{'Alt+e'} = ['Terminal','edit','Edit Connection'];
    $$cfg{'terminal'}{'Ctrl+plus'} = ['Terminal','zoomin','Zoom in text'];
    $$cfg{'terminal'}{'Ctrl+minus'} = ['Terminal','zoomout','Zoom out text'];
    $$cfg{'terminal'}{'Ctrl+0'} = ['Terminal','zoomreset','Zoom reset text'];
    $self->{cfg} = $cfg;
}

sub _buildGUI {
    my $self = shift;
    my %w;


    $w{scroll} = Gtk3::ScrolledWindow->new();
    $w{scroll}->set_overlay_scrolling(0);
    $w{scroll}->set_policy('automatic', 'automatic');

    # Attach to class attribute
    $$self{container} = $w{scroll};
    $$self{frame} = \%w;

    # Build a vbox
    #$w{vbox} = Gtk3::VBox->new(0,0);
    $w{keylist} = PACTree->new(
        'Window' => 'text',
        'Action' => 'text',
        'Keys' => 'text',
        'kbaction' => 'hidden',
    );
    $w{keylist}->set_enable_tree_lines(0);
    $w{keylist}->set_headers_visible(1);
    $w{keylist}->set_enable_search(0);
    $w{keylist}->set_has_tooltip(0);
    $w{keylist}->set_show_expanders(0);
    $w{keylist}->set_activate_on_single_click(1);
    $w{keylist}->set_grid_lines('GTK_TREE_VIEW_GRID_LINES_BOTH');
    $w{keylist}->get_selection()->set_mode('GTK_SELECTION_SINGLE');
    $w{scroll}->add($w{keylist});

    #$w{vbox}->pack_start($w{keylist},1,1,1);

    $w{keylist}->signal_connect('key_press_event' => sub {
        my ($widget, $event) = @_;
        my $selection = $w{keylist}->get_selection();
        my $model   = $w{keylist}->get_model();
        my @paths   = _getSelectedRows($selection);
        my $entry   = $model->get_value($model->get_iter($paths[0]),1);

        my ($keyval, $unicode, $keymask) = $self->GetKeyMask($widget, $event);

        print "$keyval, $unicode, $keymask\n";

        if ($unicode == 8 || $unicode == 127) {
            print "Borrar\n";
            return 1;
        } elsif (!$keymask) {
            return 0;
        }

        if (!$keymask) {
            return 0;
        }

        print STDERR "KEYPRESS ($entry): $keymask\n";
        return 1;
    });
}

1;
