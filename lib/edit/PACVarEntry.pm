package PACVarEntry;

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

use FindBin qw ($RealBin $Bin $Script);

# GTK
use Gtk3 '-init';

# PAC modules
use PACUtils;

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

    my $self = {};

    $self->{cfg} = shift;

    $self->{container} = undef;
    $self->{frame} = {};
    $self->{list} = [];

    _buildVarGUI($self);
    defined $self->{cfg} and PACVarEntry::update($self->{cfg});

    bless($self, $class);
    return $self;
}

sub update {
    my $self = shift;
    my $cfg = shift;

    defined $cfg and $$self{cfg} = $cfg;

    # Destroy previous widgets
    $$self{frame}{vbvar}->foreach(sub {$_[0]->destroy();});

    # Empty parent widgets' list
    $$self{list} = [];

    # Now, add the -new?- widgets
    foreach my $hash (@{$$self{cfg}}) {_buildVar($self, $hash);}

    return 1;
}

sub get_cfg {
    my $self = shift;

    my @cfg;

    foreach my $w (@{$self->{list}}) {push(@cfg, {txt => $$w{txt}->get_chars(0, -1), hide => $$w{hide}->get_active});}

    return \@cfg;
}

# END: Public class methods
###################################################################

###################################################################
# START: Private functions definitions

sub _buildVarGUI {
    my $self = shift;

    my $cfg = $self->{cfg};

    my %w;

    # Build a vbox for:buttons, separator and expect widgets
    $w{vbox} = Gtk3::VBox->new(0, 0);

    # Build a hbuttonbox for widgets actions (add, etc.)
    $w{bbox} = Gtk3::HButtonBox->new();
    $w{vbox}->pack_start($w{bbox}, 0, 1, 0);
    $w{bbox}->set_layout('GTK_BUTTONBOX_START');

    # Build 'add' button
    $w{btnadd} = Gtk3::Button->new_from_stock('gtk-add');
    $w{bbox}->add($w{btnadd});

    # Build a separator
    $w{sep} = Gtk3::HSeparator->new();
    $w{vbox}->pack_start($w{sep}, 0, 1, 5);

    # Build a scrolled window
    $w{sw} = Gtk3::ScrolledWindow->new();
    $w{vbox}->pack_start($w{sw}, 1, 1, 0);
    $w{sw}->set_policy('automatic', 'automatic');
    $w{sw}->set_shadow_type('none');

    $w{vp} = Gtk3::Viewport->new();
    $w{sw}->add($w{vp});
    $w{vp}->set_property('border-width', 5);
    $w{vp}->set_shadow_type('none');

    # Build and add the vbox that will contain the expect widgets
    $w{vbvar} = Gtk3::VBox->new(0, 0);
    $w{vp}->add($w{vbvar});

    $$self{container} = $w{vbox};
    $$self{frame} = \%w;

    # Button(s) callback(s)

    $w{btnadd}->signal_connect('clicked', sub {
        # Save current cfg
        $$self{cfg} = $self->get_cfg();
        # Append an empty var entry to cfg
        push(@{$$self{cfg}}, '');
        # Update gui
        $self->update();
        # Set keyboard focus on latest created entry
        $$self{list}[$#{$$self{list}}]{txt}->grab_focus();
        return 1;
    });

    return 1;
}

sub _buildVar {
    my $self = shift;
    my $hash = shift;

    my $txt;
    my $hide;

    if (ref($hash) ne 'HASH') {
        $txt = $hash;
        $hide = 0;
    } else {
        $txt = $$hash{txt};
        $hide = $$hash{hide};
    }

    my @undo;
    my $undoing = 0;

    my %w;

    $w{position} = scalar @{$$self{list}};

    # Make an HBox to contain label, entry and del button
    $w{hbox} = Gtk3::HBox->new(0, 0);

    # Build label

    $w{lbl} = Gtk3::Label->new("<V:$w{position}> (");
    $w{hbox}->pack_start($w{lbl}, 0, 1, 0);

    $w{hide} = Gtk3::CheckButton->new('hide) ');
    $w{hbox}->pack_start($w{hide}, 0, 1, 0);
    $w{hide}->set_active($hide // 0);
    $w{hide}->signal_connect(toggled => sub {$w{txt}->set_visibility(! $w{hide}->get_active);});

    # Build entry
    $w{txt} = Gtk3::Entry->new();
    $w{hbox}->pack_start($w{txt}, 1, 1, 0);
    $w{txt}->set_text($txt);
    $w{txt}->set_visibility(! $w{hide}->get_active);

    # Build delete button
    $w{btn} = Gtk3::Button->new_from_stock('gtk-delete');
    $w{hbox}->pack_start($w{btn}, 0, 1, 0);

    # Add built control to main container
    $$self{frame}{vbvar}->pack_start($w{hbox}, 0, 1, 0);
    $$self{frame}{vbvar}->show_all;

    $$self{list}[$w{position}] = \%w;

    # Setup some callbacks

    # Asign a callback for deleting entry
    $w{btn}->signal_connect('clicked' => sub {
        $$self{cfg} = $self->get_cfg();
        splice(@{$$self{list}}, $w{position}, 1);
        splice(@{$$self{cfg}}, $w{position}, 1);
        $self->update();
        return 1;
    });

    $w{txt}->signal_connect('delete_text' => sub {! $undoing and push(@undo, $w{txt}->get_chars(0, -1) ); return $_[1], $_[3];});
    $w{txt}->signal_connect('insert_text' => sub {! $undoing and push(@undo, $w{txt}->get_chars(0, -1) ); return $_[1], $_[3];});
    $w{txt}->signal_connect('key_press_event' => sub {
        my ($widget, $event) = @_;
        my $keyval = '' . ($event->keyval);
        my $state = '' . ($event->state);
        # Check if <Ctrl>z is pushed
        if (($event->state >= 'control-mask') && (chr($keyval) eq 'z') && (scalar @undo) ) {
            $undoing = 1;
            $w{txt}->set_text(pop(@undo) );
            $undoing = 0;
            return 1;
        }
        return 0;
    });

    return %w;
}

# END: Private functions definitions
###################################################################

1;
