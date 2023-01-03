package PACMethod_remote_tty;

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

$|++;

###################################################################
# Import Modules

# Standard
use strict;
use warnings;
use FindBin qw ($RealBin $Bin $Script);

# GTK
use Gtk3 '-init';

# END: Import Modules
###################################################################

###################################################################
# Define GLOBAL CLASS variables

my $RES_DIR = $RealBin . '/res';

# END: Define GLOBAL CLASS variables
###################################################################

###################################################################
# START: Public class methods

sub new
{
    my $class = shift;
    my $self = {};

    $self->{container} = shift;

    $self->{cfg} = undef;
    $self->{cfg_array} = undef;
    $self->{gui} = undef;
    $self->{frame} = {};

    _buildGUI($self);

    bless($self, $class);
    return $self;
}

sub update
{
    my $self = shift;
    my $cfg = shift;
    my $cfg_array = shift;

    defined $cfg and $$self{cfg} = $cfg;
    defined $cfg_array and $$self{cfg_array} = $cfg_array;

    my $options = _parseCfgToOptions($$self{cfg});

    $$self{gui}{chRestricted}->set_active($$options{'restricted'});
    $$self{gui}{ch7Bit}->set_active($$options{'7Bit'});

    return 1;
}

sub get_cfg_array
{
    my $self = shift;

    my %options_array;

    return \%options_array;
}

sub get_cfg
{
    my $self = shift;

    my %options;

    $options{'restricted'} = $$self{gui}{chRestricted}->get_active;
    $options{'7Bit'} = $$self{gui}{ch7Bit}->get_active;

    return _parseOptionsToCfg(\%options);
}

# END: Public class methods
###################################################################

###################################################################
# START: Private functions definitions

sub _parseCfgToOptions
{
    my $cmd_line = shift;

    my %hash;
    $hash{passive} = 0;
    $hash{noInteractive} = 0;

    my @opts = split('-', $cmd_line);
    foreach my $opt (@opts)
    {
        next unless $opt ne '';
        $opt =~ s/\s+$//go;

        $opt eq 'r'    and    $hash{restricted} = 1;
        $opt eq '7'    and    $hash{'7Bit'} = 1;
    }

    return \%hash;
}

sub _parseOptionsToCfg
{
    my $hash = shift;

    my $txt = '';

    $txt .= ' -r' if $$hash{restricted} ;
    $txt .= ' -7' if $$hash{'7Bit'} ;

    return $txt;
}

sub embed
{
    my $self = shift;
    return 0;
}

sub _buildGUI
{
    my $self = shift;

    my $container = $self->{container};
    my $cfg = $self->{cfg};

    my %w;

    $w{vbox} = $container;

        $w{chRestricted} = Gtk3::CheckButton->new_with_label('Set restricted mode');
        $w{vbox}->pack_start($w{chRestricted}, 0, 1, 0);
        $w{chRestricted}->set_tooltip_text("[-r] : Don't allow changing of logging status, suspending of remote-tty or setting of line options");

        $w{ch7Bit} = Gtk3::CheckButton->new_with_label('Set 7bit mode');
        $w{vbox}->pack_start($w{ch7Bit}, 0, 1, 0);
        $w{ch7Bit}->set_tooltip_text('[-7] : Set 7bit connection mode');

    $$self{gui} = \%w;

    return 1;
}

# END: Private functions definitions
###################################################################

1;
