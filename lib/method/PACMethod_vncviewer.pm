package PACMethod_vncviewer;

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

my $ENCODINGS = "Tight Zlib Hextile CoRRE RRE CopyRect Raw";
my %DEPTH = (8 => 0, 15 => 1, 16 => 2, 24 => 3, 32 => 4, 'default' => 5);
my $RES_DIR = $RealBin . '/res';

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
    my $method = shift;

    defined $cfg and $$self{cfg} = $cfg;

    my $options = _parseCfgToOptions($$self{cfg});

    $$self{gui}{chNaturalSize}->set_active(! ($$options{fullScreen}) );
    $$self{gui}{chFullScreen}->set_active($$options{fullScreen});
    $$self{gui}{chListen}->set_active($$options{listen});
    $$self{gui}{chViewOnly}->set_active($$options{viewOnly});
    $$self{gui}{spQuality}->set_value($$options{quality});
    $$self{gui}{spCompressLevel}->set_value($$options{compressLevel});
    $$self{gui}{cbDepth}->set_active($DEPTH{$$options{depth} // 'default'});

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
    $options{depth} = $$self{gui}{cbDepth}->get_active_text;

    return _parseOptionsToCfg(\%options);
}

# END: Public class methods
###################################################################

###################################################################
# START: Private functions definitions

sub _parseCfgToOptions {
    my $cmd_line = shift;

    my %hash;
    $hash{fullScreen} = 0;
    $hash{nsize} = 1;
    $hash{quality} = 5;
    $hash{compressLevel} = 8;
    $hash{depth} = 'default';

    my @opts = split(/\s+-/, $cmd_line);
    foreach my $opt (@opts)
    {
        next unless $opt ne '';
        $opt =~ s/\s+$//go;

        if ($opt eq 'fullscreen')            {$hash{fullScreen} = 1; $hash{nsize} = 0;}
        $opt eq 'listen'                    and    $hash{listen} = 1;
        $opt eq 'viewonly'                    and    $hash{viewOnly} = 1;
        $opt =~ /^compresslevel\s+(\d+)$/go    and    $hash{compressLevel} = $1;
        $opt =~ /^quality\s+(\d+)$/go        and    $hash{quality} = $1;
        $opt =~ /^depth\s+(\d+)$/go            and    $hash{depth} = $1;
    }

    return \%hash;
}

sub _parseOptionsToCfg {
    my $hash = shift;

    my $txt = '';

    $txt .= ' -fullscreen'        if $$hash{fullScreen};
    $txt .= ' -listen'            if $$hash{listen};
    $txt .= ' -viewonly'        if $$hash{viewOnly};
    $txt .= ' -depth '            . $$hash{depth} if ($$hash{depth} ne 'default');
    $txt .= ' -compresslevel '    . $$hash{compressLevel};
    $txt .= ' -quality '        . $$hash{quality};
    $txt .= " -encodings \"$ENCODINGS\"";
    $txt .= ' -autopass';

    return $txt;
}

sub embed {
    my $self = shift;
    # TightVNC client does not support that mode anymore
    return 0;
}

sub _buildGUI {
    my $self = shift;

    my $container = $$self{container};
    my $cfg = $$self{cfg};

    my %w;

    $w{vbox} = $container;

    $w{hboxReal} = Gtk3::HBox->new(0, 5);
    $w{vbox}->pack_start($w{hboxReal}, 0, 1, 5);
    $w{lblClient} = Gtk3::Label->new();
    $w{lblClient}->set_markup('<b>VNC configuration</b>');
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

    $w{hbox2} = Gtk3::HBox->new(0, 5);
    $w{vbox}->pack_start($w{hbox2}, 0, 1, 5);

    $w{chFullScreen} = Gtk3::RadioButton->new_with_label(undef, 'Fullscreen');
    $w{hbox2}->pack_start($w{chFullScreen}, 0, 1, 0);
    $w{chFullScreen}->set_tooltip_text('[-fullscreen] : Fullscreen window');

    $w{chNaturalSize} = Gtk3::RadioButton->new_with_label($w{chFullScreen}, 'Natural Size');
    $w{hbox2}->pack_start($w{chNaturalSize}, 0, 1, 0);

    $w{chListen} = Gtk3::CheckButton->new_with_label('Listen');
    $w{hbox2}->pack_start($w{chListen}, 0, 1, 0);
    $w{chListen}->set_tooltip_text('[-listen] : Listen for incoming connections');

    $w{chViewOnly} = Gtk3::CheckButton->new_with_label('View Only');
    $w{hbox2}->pack_start($w{chViewOnly}, 0, 1, 0);
    $w{chViewOnly}->set_tooltip_text('[-viewonly] : View only mode');

    $w{frDepth} = Gtk3::Frame->new('Colour depth (bpp):');
    $w{hbox2}->pack_start($w{frDepth}, 0, 1, 0);
    $w{frDepth}->set_shadow_type('GTK_SHADOW_NONE');
    $w{frDepth}->set_tooltip_text('[-depth bits_per_pixel] : Attempt to use the specified colour depth (in bits per pixel)');

    $w{cbDepth} = Gtk3::ComboBoxText->new;
    $w{frDepth}->add($w{cbDepth});
    foreach my $depth (8, 15, 16, 24, 32, 'default') {$w{cbDepth}->append_text($depth);};

    $$self{gui} = \%w;

    return 1;
}

# END: Private functions definitions
###################################################################

1;
