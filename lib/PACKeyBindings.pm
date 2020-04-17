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

# Global Methods

sub GetKeyMask {
    my ($self, $widget, $event) = @_;
    my $keyval  = Gtk3::Gdk::keyval_name($event->keyval) // '';
    my $unicode = Gtk3::Gdk::keyval_to_unicode($event->keyval); # 0 if not a character
    my $state   = $event->get_state();
    my $shift   = $state * ['shift-mask']   ? 'Shift' : '';
    my $ctrl    = $state * ['control-mask'] ? 'Ctrl'  : '';
    my $alt     = $state * ['mod1-mask']    ? 'Alt'   : '';

    if (!$unicode || (!$ctrl && !$alt)) {
        return ($unicode,'');
    }
    return ($unicode,"$alt$ctrl+$keyval");
}

# Private Methods

sub _buildGUI {
    my $self = shift;
    my $cfg = $self->{cfg};
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
        'Location' => 'text',
        'Action' => 'text',
        'Keys' => 'text',
        'fcall' => 'hidden',
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

        my ($unicode, $keymask) = $self->GetKeyMask($widget, $event);

        if ($unicode == 8 || $unicode == 127) {
            print "Borrar\n";
            return 1;
        } elsif (!$unicode) {
            return 0;
        }

        if (!$keymask) {
            return 0;
        }

        print STDERR "KEYPRESS ($entry): $keymask\n";
        return 1;
    });
}

sub update {
    my $self = shift;

    @{$$self{frame}{keylist}{'data'}} = ();
    foreach my $x ('Main Window|First Tab|Ctrl+1|move_to_tab','Terminal|Zoom in text|Ctrl++|zoom_in','Terminal|Zoom out text|Ctrl+-|zoom_out','Terminal|Zoom reset|Ctrl+0|zoom_reset') {
        my ($l,$a,$k,$f) = split /\|/,$x;
        push(@{$$self{frame}{keylist}{'data'}}, {value => [ $l,$a,$k,$f ], children => []});
    }
}

sub get_cfg {
}

1;
