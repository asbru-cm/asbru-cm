package PACMethod_cu;

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
my %PARITY = ('even' => 0, 'none' => 1, 'odd' => 2);

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

    $$self{gui}{entryLine}->set_text($$options{'line'} || '');
    $$self{gui}{spSpeed}->set_value($$options{'speed'} || 9660);
    $$self{gui}{entryPort}->set_text($$options{'port'} || '');
    $$self{gui}{cbParity}->set_active($PARITY{$$options{'parity'} // 'none'});
    $$self{gui}{chHalfDuplex}->set_active($$options{'halfduplex'} // 0);
    $$self{gui}{chNoStop}->set_active($$options{'nostop'} // 0);

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

    $options{'line'} = $$self{gui}{entryLine}->get_text;
    $options{'speed'} = $$self{gui}{spSpeed}->get_value;
    $options{'port'} = $$self{gui}{entryPort}->get_text;
    $options{'parity'} = $$self{gui}{cbParity}->get_active_text;
    $options{'halfduplex'} = $$self{gui}{chHalfDuplex}->get_active;
    $options{'nostop'} = $$self{gui}{chNoStop}->get_active;

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
    $hash{line} = '';
    $hash{speed} = 0;
    $hash{parity} = 'none';
    $hash{halfduplex} = 0;
    $hash{nostop} = 0;

    my @opts = split(/-+/, $cmd_line);
    foreach my $opt (@opts)
    {
        next unless $opt ne '';
        $opt =~ s/\s+$//go;

        $opt =~ /l\s+(.+)/        and    $hash{'line'} = $1;
        $opt =~ /s\s+(\d+)/        and    $hash{'speed'} = $1;
        $opt =~ /p\s+(.+)/        and    $hash{'port'} = $1;
        $opt =~ /parity=(.+)/    and    $hash{'parity'} = $1;
        $opt =~ /halfduplex/    and    $hash{'halfduplex'} = 1;
        $opt =~ /nostop/        and    $hash{'nostop'} = 1;
    }

    return \%hash;
}

sub _parseOptionsToCfg
{
    my $hash = shift;

    my $txt = '';

    $txt .= " -l $$hash{'line'}" if $$hash{'line'} ;
    $txt .= " -s $$hash{'speed'}" if $$hash{'speed'} ;
    $txt .= " -p $$hash{'port'}" if $$hash{'port'} ;
    $txt .= " --parity=$$hash{'parity'}" if $$hash{'parity'} ;
    $txt .= " --halfduplex" if $$hash{'halfduplex'} ;
    $txt .= " --nostop" if $$hash{'nostop'} ;

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

        $w{hbox1} = Gtk3::HBox->new(0, 0);
        $w{vbox}->pack_start($w{hbox1}, 0, 1, 0);

            $w{hbox1}->pack_start(Gtk3::Label->new('Line: '), 0, 1, 0);
            $w{entryLine} = Gtk3::Entry->new();
            $w{hbox1}->pack_start($w{entryLine}, 0, 1, 0);
            $w{entryLine}->set_tooltip_text("[-l|--line] : Line to use to connect. Ex: /dev/ttyUSB0");

            $w{hbox1}->pack_start(Gtk3::Label->new(' Speed: '), 0, 1, 0);
            $w{spSpeed} = Gtk3::SpinButton->new_with_range(1, 1999999, 1);
            $w{hbox1}->pack_start($w{spSpeed}, 0, 1, 0);
            $w{spSpeed}->set_tooltip_text("[-s|--speed] : Speed to use to connect. Ex: 9660");
            $w{spSpeed}->set_value(9660);

            $w{hbox1}->pack_start(Gtk3::Label->new(' Port: '), 0, 1, 0);
            $w{entryPort} = Gtk3::Entry->new();
            $w{hbox1}->pack_start($w{entryPort}, 0, 1, 0);
            $w{entryPort}->set_tooltip_text("[-p|--port] : Port to connect");

            $w{hbox1}->pack_start(Gtk3::Label->new(' Parity: '), 0, 1, 0);
            $w{cbParity} = Gtk3::ComboBoxText->new;
            $w{cbParity}->set_tooltip_text("-(e|o|none) : Use 'even', 'odd' or 'no' parity");
            $w{hbox1}->pack_start($w{cbParity}, 0, 1, 0);
            foreach my $parity (sort {$a cmp $b} keys %PARITY) {$w{cbParity}->append_text($parity);};

        $w{hbox2} = Gtk3::HBox->new(0, 0);
        $w{vbox}->pack_start($w{hbox2}, 0, 1, 0);

            $w{chHalfDuplex} = Gtk3::CheckButton->new_with_label('Half Duplex');
            $w{hbox2}->pack_start($w{chHalfDuplex}, 0, 1, 0);
            $w{chHalfDuplex}->set_tooltip_text("[-h] : Echo characters locally (half-duplex mode)");

            $w{chNoStop} = Gtk3::CheckButton->new_with_label('Turn off XON/XOFF handling');
            $w{hbox2}->pack_start($w{chNoStop}, 0, 1, 0);
            $w{chNoStop}->set_tooltip_text("[--nostop] : Turn off XON/XOFF handling (it is on by default)");


    $$self{gui} = \%w;

    return 1;
}

# END: Private functions definitions
###################################################################

1;
