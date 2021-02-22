package PACMethod_ftp;

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

    defined $cfg and $$self{cfg} = $cfg;

    my $options = _parseCfgToOptions($$self{cfg});

    $$self{gui}{chPassive}->set_active($$options{passive});
    $$self{gui}{chNoInteractive}->set_active($$options{noInteractive});
    $$self{gui}{chVerbose}->set_active($$options{verbose});

    return 1;
}

sub get_cfg
{
    my $self = shift;

    my %options;

    $options{passive} = $$self{gui}{chPassive}->get_active;
    $options{noInteractive} = $$self{gui}{chNoInteractive}->get_active;
    $options{verbose} = $$self{gui}{chVerbose}->get_active;

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
    $hash{verbose} = 0;

    my @opts = split('-', $cmd_line);
    foreach my $opt (@opts)
    {
        next unless $opt ne '';
        $opt =~ s/\s+$//go;

        $opt eq 'p'    and    $hash{passive} = 1;
        $opt eq 'i'    and    $hash{noInteractive} = 1;
        $opt eq 'v'    and    $hash{verbose} = 1;
    }

    return \%hash;
}

sub _parseOptionsToCfg
{
    my $hash = shift;

    my $txt = '';

    $txt .= ' -p' if $$hash{passive} ;
    $txt .= ' -i' if $$hash{noInteractive} ;
    $txt .= ' -v' if $$hash{verbose} ;

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

        $w{chPassive} = Gtk3::CheckButton->new_with_label('Passive mode data transfers');
        $w{vbox}->pack_start($w{chPassive}, 0, 1, 0);
        $w{chPassive}->set_tooltip_text('[-p] : Use passive mode for data transfers');

        $w{chNoInteractive} = Gtk3::CheckButton->new_with_label('Turn off interactive prompt for multiple file transfers');
        $w{vbox}->pack_start($w{chNoInteractive}, 0, 1, 0);
        $w{chNoInteractive}->set_tooltip_text('[-i] : Turns off interactive prompting during multiple file transfers');

        $w{chVerbose} = Gtk3::CheckButton->new_with_label('Verbose connection');
        $w{vbox}->pack_start($w{chVerbose}, 0, 1, 0);
        $w{chVerbose}->set_tooltip_text('[-v] : Show all responses from the remote server, as well as report on data transfer statistics');

    $$self{gui} = \%w;

    return 1;
}

# END: Private functions definitions
###################################################################

1;
