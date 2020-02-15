package PACMethod_tigervnc;

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

# END: Import Modules
###################################################################

###################################################################
# Define GLOBAL CLASS variables

my $RES_DIR = $RealBin . '/res';
my %COLOURS = (8 => 0, 64 => 1, 256 => 2, 'AutoSelect' => 3);
my %REVCOLOURS = (0 => 0, 1 => 1, 2 => 2, 'AutoSelect' => 3);

# END: Define GLOBAL CLASS variables
###################################################################

###################################################################
# START: Public class methods

sub new {
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

sub update {
    my $self = shift;
    my $cfg = shift;

    defined $cfg and $$self{cfg} = $cfg;

    my $options = _parseCfgToOptions($$self{cfg});

    $$self{gui}{chFullScreen}->set_active($$options{fullScreen});
    $$self{gui}{chListen}->set_active($$options{listen});
    $$self{gui}{chViewOnly}->set_active($$options{viewOnly});
    $$self{gui}{spQuality}->set_value($$options{quality});
    $$self{gui}{spCompressLevel}->set_value($$options{compressLevel});
    $$self{gui}{cbColours}->set_active($REVCOLOURS{$$options{colours}});

    return 1;
}

sub get_cfg {
    my $self = shift;

    my %options;

    $options{fullScreen} = $$self{gui}{chFullScreen}->get_active;
    $options{listen} = $$self{gui}{chListen}->get_active;
    $options{viewOnly} = $$self{gui}{chViewOnly}->get_active;
    $options{quality} = $$self{gui}{spQuality}->get_value;
    $options{compressLevel} = $$self{gui}{spCompressLevel}->get_value;
    $options{colours} = $$self{gui}{cbColours}->get_active_text;

    return _parseOptionsToCfg(\%options);
}

# END: Public class methods
###################################################################

###################################################################
# START: Private functions definitions

sub _parseCfgToOptions {
    my $cmd_line = shift;

    my %hash;
    $hash{colours} = 'AutoSelect';
    $hash{fullScreen} = 0;
    $hash{quality} = 5;
    $hash{compressLevel} = 8;
    $hash{viewOnly} = 0;
    $hash{listen} = 0;

    my @opts = split(/\s+-/, $cmd_line);
    foreach my $opt (@opts)
    {
        next unless $opt ne '';
        $opt =~ s/\s+$//go;

        $opt =~ /^LowColourLevel\s+(\d)$/go    and    $hash{colours} = $1;
        $opt =~ /^FullScreen=(\d+)$/go        and    $hash{fullScreen} = $1;
        $opt =~ /^listen=(\d+)$/go            and    $hash{listen} = $1;
        $opt =~ /^ViewOnly=(\d+)$/go        and    $hash{viewOnly} = $1;
        $opt =~ /^CompressLevel=(\d+)$/go    and    $hash{compressLevel} = $1;
        $opt =~ /^QualityLevel=(\d+)$/go    and    $hash{quality} = $1;
    }

    return \%hash;
}

sub _parseOptionsToCfg {
    my $hash = shift;

    my $txt = '';

    ($$hash{colours} ne 'AutoSelect') and $txt .= ' -AutoSelect=0';
    ($$hash{colours} ne 'AutoSelect') and $txt .= ' -LowColourLevel '    . ($COLOURS{$$hash{colours}});
    $txt .= ' -FullScreen='        . ($$hash{fullScreen}    || '0');
    $txt .= ' -listen='            . ($$hash{listen}        || '0');
    $txt .= ' -ViewOnly='        . ($$hash{viewOnly}    || '0');
    $txt .= ' -CompressLevel='    . $$hash{compressLevel};
    $txt .= ' -QualityLevel='    . $$hash{quality};

    return $txt;
}

sub embed {
    my $self = shift;
    # TigerVNC client does not support that mode anymore
    return 0;
}

sub _buildGUI {
    my $self = shift;

    my $container = $self->{container};
    my $cfg = $self->{cfg};

    my %w;

    $w{vbox} = $container;

    $w{hboxReal} = Gtk3::HBox->new(0, 5);
    $w{vbox}->pack_start($w{hboxReal}, 0, 1, 5);
    $w{lblClient} = Gtk3::Label->new();
    $w{lblClient}->set_markup('<b>TigerVNC configuration</b>');
    $w{hboxReal}->pack_start($w{lblClient}, 0, 0, 0);

    $w{hbox1} = Gtk3::HBox->new(0, 5);
    $w{vbox}->pack_start($w{hbox1}, 0, 1, 5);

    $w{frCompressLevel} = Gtk3::Frame->new('Compression level (1: min, 10: max) :');
    $w{hbox1}->pack_start($w{frCompressLevel}, 1, 1, 0);
    $w{frCompressLevel}->set_tooltip_text('[-g] : Percentage of the whole screen to use');

    $w{spCompressLevel} = Gtk3::HScale->new(Gtk3::Adjustment->new(8, 1, 11, 1.0, 1.0, 1.0) );
    $w{frCompressLevel}->add($w{spCompressLevel});

    $w{frQuality} = Gtk3::Frame->new('Picture quality (1: min, 10: max) :');
    $w{hbox1}->pack_start($w{frQuality}, 1, 1, 0);
    $w{frQuality}->set_tooltip_text('[-g] : Percentage of the whole screen to use');

    $w{spQuality} = Gtk3::HScale->new(Gtk3::Adjustment->new(5, 1, 11, 1.0, 1.0, 1.0) );
    $w{frQuality}->add($w{spQuality});

    $w{frColour} = Gtk3::Frame->new('Colour Level:');
    $w{hbox1}->pack_start($w{frColour}, 1, 1, 0);
    $w{frColour}->set_tooltip_text('Select the reduced colour level, or leave as automatic');

    $w{cbColours} = Gtk3::ComboBoxText->new;
    $w{frColour}->add($w{cbColours});
    foreach my $depth (8, 64, 256, 'AutoSelect') {$w{cbColours}->append_text($depth);};

    $w{hbox2} = Gtk3::HBox->new(0, 5);
    $w{vbox}->pack_start($w{hbox2}, 0, 1, 5);

    $w{chFullScreen} = Gtk3::CheckButton->new_with_label('Fullscreen');
    $w{hbox2}->pack_start($w{chFullScreen}, 0, 1, 0);
    $w{chFullScreen}->set_tooltip_text('[-FullScreen] : Fullscreen window');

    $w{chListen} = Gtk3::CheckButton->new_with_label('Listen');
    $w{hbox2}->pack_start($w{chListen}, 0, 1, 0);
    $w{chListen}->set_tooltip_text('[-listen] : Listen for incoming connections');

    $w{chViewOnly} = Gtk3::CheckButton->new_with_label('View Only');
    $w{hbox2}->pack_start($w{chViewOnly}, 0, 1, 0);
    $w{chViewOnly}->set_tooltip_text('[-ViewOnly] : View only mode');

    $$self{gui} = \%w;

    return 1;
}

# END: Private functions definitions
###################################################################

1;
