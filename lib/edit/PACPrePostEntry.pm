package PACPrePostEntry;

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
    $self->{variables} = shift;

    $self->{container} = undef;
    $self->{frame} = {};
    $self->{list} = [];

    _buildPrePostGUI($self);
    defined $self->{cfg} and PACPrePostEntry::update($self->{cfg});

    bless($self, $class);
    return $self;
}

sub update {
    my $self = shift;
    my $cfg = shift;
    my $variables = shift;

    defined $cfg and $$self{cfg} = $cfg;
    defined $variables and $$self{variables} = $variables;

    # Destroy previous widgets
    $$self{frame}{vbexec}->foreach(sub {$_[0]->destroy();});

    # Empty parent's widgets' list
    $$self{list} = [];

    # Now, add the -new?- widgets
    foreach my $hash (@{$$self{cfg}}) {_buildPrePost($self, $hash);}

    return 1;
}

sub get_cfg {
    my $self = shift;

    my @cfg;

    foreach my $w (@{$self->{list}}) {
        my %hash;
        $hash{command} = $$w{command}->get_chars(0, -1);
        $hash{default} = $$w{default}->get_active;
        $hash{ask} = $$w{ask}->get_active;
        push(@cfg, \%hash);
    }

    return \@cfg;
}

# END: Public class methods
###################################################################

###################################################################
# START: Private functions definitions

sub _buildPrePostGUI {
    my $self = shift;

    my $cfg = $self->{cfg};

    my %w;

    # Build a vbox for:buttons, separator and expect widgets
    $w{vbox} = Gtk3::VBox->new(0, 0);
    $w{hbox} = Gtk3::HBox->new(1, 0);

    # Build a hbuttonbox for widgets actions (add, etc.)
    $w{bbox} = Gtk3::HButtonBox->new();
    $w{vbox}->pack_start($w{hbox}, 0, 1, 0);
    $w{hbox}->pack_start($w{bbox}, 0, 1, 0);
    $w{bbox}->set_layout('GTK_BUTTONBOX_START');

    # Build 'add' button
    $w{btnadd} = Gtk3::Button->new_from_stock('gtk-add');
    $w{bbox}->add($w{btnadd});

    $w{help} = Gtk3::LinkButton->new('https://docs.asbru-cm.net/Manual/Connections/SSH/#pre-post-exec');
    $w{help}->set_halign('GTK_ALIGN_END');
    $w{help}->set_label('');
    $w{help}->set_tooltip_text('Open Online Help');
    $w{help}->set_always_show_image(1);
    $w{help}->set_image(Gtk3::Image->new_from_stock('asbru-help', 'button'));
    $w{hbox}->pack_start($w{help}, 0, 1, 0);

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
    $w{vbexec} = Gtk3::VBox->new(0, 0);
    $w{vp}->add($w{vbexec});

    $$self{container} = $w{vbox};
    $$self{frame} = \%w;

    # Button(s) callback(s)

    $w{btnadd}->signal_connect('clicked', sub {
        # Save current cfg
        $$self{cfg} = $self->get_cfg();
        # Append an empty exec entry to cfg
        push(@{$$self{cfg}}, {'command' => '', 'def' => 1});
        # Update gui
        $self->update();
        # Set keyboard focus on last created entry
        $$self{list}[$#{$$self{list}}]{command}->grab_focus();
        return 1;
    });

    return 1;
}

sub _buildPrePost {
    my $self = shift;
    my $hash = shift;

    my $command = $$hash{command} // '';
    my $def = $$hash{default} // 0;
    my $ask = $$hash{ask} // 1;

    my @undo;
    my $undoing = 0;

    my %w;

    $w{position} = scalar @{$$self{list}};

    # Make an HBox to contain checkbox and entry
    $w{hbox} = Gtk3::HBox->new(0, 0);

    # Build checkbox
    $w{ask} = Gtk3::CheckButton->new_with_label('Ask: ' . ($ask ? 'YES' : 'NO') );
    $w{hbox}->pack_start($w{ask}, 0, 1, 0);
    $w{ask}->set_active($ask);

    # Build checkbox
    $w{default} = Gtk3::CheckButton->new_with_label('Default: ' . ($def ? 'YES' : 'NO') );
    $w{hbox}->pack_start($w{default}, 0, 1, 0);
    $w{default}->set_active($def);

    # Build entry
    $w{command} = Gtk3::Entry->new;
    $w{hbox}->pack_start($w{command}, 1, 1, 0);
    $w{command}->set_icon_from_stock('primary', 'gtk-execute');
    $w{command}->set_text($command);
    $w{default}->set_sensitive($command ne '');

    # Build delete button
    $w{btn} = Gtk3::Button->new_from_stock('gtk-delete');
    $w{hbox}->pack_start($w{btn}, 0, 1, 0);

    # Add built control to main container
    $$self{frame}{vbexec}->pack_start($w{hbox}, 0, 1, 0);
    $$self{frame}{vbexec}->show_all;

    $$self{list}[$w{position}] = \%w;

    # Setup some callbacks

    # Asign a callback for modifying toggle ask  checkbutton label
    $w{ask}->signal_connect('toggled' => sub {
        $w{ask}->set_property('label', 'Ask: ' . ($w{ask}->get_active ? 'YES' : 'NO') );
        $w{default}->set_active(! $w{ask}->get_active);
        return 1;
    });
    # Asign a callback for modifying toggle default checkbutton label
    $w{default}->signal_connect('toggled' => sub {$w{default}->set_property('label', 'Default: ' . ($w{default}->get_active ? 'YES' : 'NO') ); return 1;});

    # Capture 'pre_exec' entry chenge (to un/activate default checkbox)
    $w{command}->signal_connect('changed' => sub {
        $w{default}->set_active($w{command}->get_chars(0, -1) ne     '');
        $w{default}->set_sensitive($w{command}->get_chars(0, -1) );
        return 1;
    });

    # Asign a callback for deleting entry
    $w{btn}->signal_connect('clicked' => sub {
        $$self{cfg} = $self->get_cfg();
        splice(@{$$self{list}}, $w{position}, 1);
        splice(@{$$self{cfg}}, $w{position}, 1);
        $self->update();
        return 1;
    });

    # Asign a callback to populate this entry with oir own context menu
    $w{command}->signal_connect('button_press_event' => sub {
        my ($widget, $event) = @_;

        return 0 unless $event->button eq 3;

        my @menu_items;

        # Populate with user defined variables
        my @variables_menu;
        my $i = 0;
        foreach my $value (map{$_->{txt} // ''} @{$$self{variables}}) {
            my $j = $i;
            push(@variables_menu, {
                label => "<V:$j> ($value)",
                code => sub {$w{command}->insert_text("<V:$j>", -1, $w{command}->get_position);}
            });
            ++$i;
        }
        push(@menu_items, {
            label => 'User variables...',
            sensitive => scalar @{$$self{variables}},
            submenu => \@variables_menu
        });

        # Populate with global defined variables
        my @global_variables_menu;
        foreach my $var (sort {$a cmp $b} keys %{$PACMain::FUNCS{_MAIN}{_CFG}{'defaults'}{'global variables'}}) {
            my $val = $PACMain::FUNCS{_MAIN}{_CFG}{'defaults'}{'global variables'}{$var}{'value'};
            push(@global_variables_menu, {
                label => "<GV:$var> ($val)",
                code => sub {$w{command}->insert_text("<GV:$var>", -1, $w{command}->get_position);}
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
                label => "<ENV:$key>",
                tooltip => "$key=$value",
                code => sub {$w{command}->insert_text("<ENV:$key>", -1, $w{command}->get_position);}
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
            stockicon => 'gtk-execute',
            code => sub {
                my $pos = $w{command}->get_property('cursor_position');
                $w{command}->insert_text('<CMD:command to launch>', -1, $w{command}->get_position);
                $w{command}->select_region($pos + 5, $pos + 22);
            }
        });

        # Populate with Ásbrú Connection Manager internal variables
        my @int_variables_menu;
        push(@int_variables_menu, {label => "UUID",code => sub {$w{command}->insert_text("<UUID>", -1, $w{command}->get_position);} });
        push(@int_variables_menu, {label => "TIMESTAMP",code => sub {$w{command}->insert_text("<TIMESTAMP>", -1, $w{command}->get_position);} });
        push(@int_variables_menu, {label => "DATE_Y",code => sub {$w{command}->insert_text("<DATE_Y>", -1, $w{command}->get_position);} });
        push(@int_variables_menu, {label => "DATE_M",code => sub {$w{command}->insert_text("<DATE_M>", -1, $w{command}->get_position);} });
        push(@int_variables_menu, {label => "DATE_D",code => sub {$w{command}->insert_text("<DATE_D>", -1, $w{command}->get_position);} });
        push(@int_variables_menu, {label => "TIME_H",code => sub {$w{command}->insert_text("<TIME_H>", -1, $w{command}->get_position);} });
        push(@int_variables_menu, {label => "TIME_M",code => sub {$w{command}->insert_text("<TIME_M>", -1, $w{command}->get_position);} });
        push(@int_variables_menu, {label => "TIME_S",code => sub {$w{command}->insert_text("<TIME_S>", -1, $w{command}->get_position);} });
        push(@int_variables_menu, {label => "NAME",code => sub {$w{command}->insert_text("<NAME>", -1, $w{command}->get_position);} });
        push(@int_variables_menu, {label => "TITLE",code => sub {$w{command}->insert_text("<TITLE>", -1, $w{command}->get_position);} });
        push(@int_variables_menu, {label => "IP",code => sub {$w{command}->insert_text("<IP>", -1, $w{command}->get_position);} });
        push(@int_variables_menu, {label => "USER",code => sub {$w{command}->insert_text("<USER>", -1, $w{command}->get_position);} });
        push(@int_variables_menu, {label => "PASS",code => sub {$w{command}->insert_text("<PASS>", -1, $w{command}->get_position);} });
        push(@menu_items, {label => 'Internal variables...', submenu => \@int_variables_menu});

        $PACMain::FUNCS{_KEEPASS}->setRigthClickMenuEntry($PACMain::FUNCS{_EDIT}{_WINDOWEDIT},'username,password',$w{command},\@menu_items);

        _wPopUpMenu(\@menu_items, $event);

        return 1;
    });

    $w{command}->signal_connect('delete_text' => sub {! $undoing and push(@undo, $w{command}->get_chars(0, -1) ); return $_[1], $_[3];});
    $w{command}->signal_connect('insert_text' => sub {! $undoing and push(@undo, $w{command}->get_chars(0, -1) ); return $_[1], $_[3];});
    $w{command}->signal_connect('key_press_event' => sub
    {
        my ($widget, $event) = @_;
        my $keyval = '' . ($event->keyval);
        my $state = '' . ($event->state);
        # Check if <Ctrl>z is pushed
        if (($event->state >= 'control-mask') && (chr($keyval) eq 'z') && (scalar @undo) ) {
            $undoing = 1;
            $w{command}->set_text(pop(@undo) );
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
