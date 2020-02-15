package PACMethod_realvnc;

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
my %DEPTHR = (8 => 0, 64 => 1, 256 => 2, 'full' => 3);
my %depthR = (8 => 'rgb111', 64 => 'rgb222', 256 => 'pal8', 'full' => 'full');
my %Rdepth = ('rgb111'=>8,'rgb222'=>64,'pal8'=>256, 'full' => 'full');
my %QUALITY = ('auto',0,'high',1,'medium',2,'low',3,'custom',4);
my $RES_DIR = "$RealBin/res";

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

    _setGUIState($self,$options);

    return 1;
}

sub get_cfg {
    my $self = shift;

    my %options;

    $options{fullScreen} = $$self{gui}{chFullScreen}->get_active;
    $options{listen} = $$self{gui}{chListen}->get_active;
    $options{viewOnly} = $$self{gui}{chViewOnly}->get_active;
    $options{quality} = $$self{gui}{spQualityR}->get_active_text;
    $options{depth} = $$self{gui}{cbDepth}->get_active_text;

    return _parseOptionsToCfg(\%options);
}

# END: Public class methods
###################################################################

###################################################################
# START: Private functions definitions

sub _setGUIState {
    my $self = shift;
    my $options = shift;

    $$self{gui}{hbox1R}->set_sensitive(1);
    $$self{gui}{spQualityR}->set_active($QUALITY{$$options{quality}});
    if (!defined $DEPTHR{$$options{depth}}) {
        $$options{depth} = 'full';
    }
    if ($$options{quality} eq 'custom') {
        $$self{gui}{hbox3}->set_sensitive(1);
    } else {
        $$self{gui}{hbox3}->set_sensitive(0);
    }
    $$self{gui}{hbox1R}->set_sensitive(1);
    $$self{gui}{hbox1R}->show();
}

sub _parseCfgToOptions {
    my $cmd_line = shift;

    my %hash;
    $hash{fullScreen} = 0;
    $hash{nsize} = 1;
    $hash{compressLevel} = 8;
    $hash{depth} = 'full';
    $hash{quality} = 'auto';

    my @opts = split(/\s+-/, $cmd_line);
    foreach my $opt (@opts)
    {
        next unless $opt ne '';
        $opt =~ s/\s+$//go;

        if ($opt =~ /^quality/go) {
            if ($opt =~ /^quality\s+([a-z]+)$/) {
                $hash{quality} = $1;
            }
        } elsif ($opt eq 'fullscreen') {
            $hash{fullScreen} = 1;
            $hash{nsize} = 0;
        } elsif ($opt eq 'listen') {
            $hash{listen} = 1;
        } elsif ($opt eq 'viewonly') {
            $hash{viewOnly} = 1;
        } elsif ($opt =~ /^depth\s+(\d+)$/) {
            $hash{depth} = $1;
        } elsif ($opt =~ /^colorlevel\s+(\w+)$/) {
            $hash{depth} = $Rdepth{$1};
        }
    }

    return \%hash;
}

sub _parseOptionsToCfg {
    my $hash = shift;
    my $txt = '';

    if (!$$hash{quality}) {
        $$hash{quality} = 'auto';
        if ($QUALITY{$$hash{quality}} eq '') {
            $$hash{quality} = 'auto';
        }
    }
    if ($$hash{fullScreen}) {
        $txt .= ' -fullscreen';
    }
    if ($$hash{listen}) {
        $txt .= ' -listen';
    }
    if ($$hash{viewOnly}) {
        $txt .= ' -viewonly';
    }
    if ($$hash{depth}) {
        $txt .= " -colorlevel $depthR{$$hash{depth}}";
    }
    $txt .= " -quality $$hash{quality}";

    #print "$txt\n";
    return $txt;
}

sub embed {
    my $self = shift;
    # vncviewer client does not support that mode anymore
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
    $w{lblClient}->set_markup('<b>RealVNC configuration</b>');
    $w{hboxReal}->pack_start($w{lblClient}, 0, 0, 0);


    $w{hbox1R} = Gtk3::HBox->new(0, 5);
    $w{vbox}->pack_start($w{hbox1R}, 0, 1, 5);
    $w{frQualityR} = Gtk3::Label->new('Picture quality :');
    $w{hbox1R}->pack_start($w{frQualityR}, 0, 0, 0);
    $w{spQualityR} = Gtk3::ComboBoxText->new();
    foreach my $q ('auto','high','medium','low','custom') {$w{spQualityR}->append_text($q);};
    $w{hbox1R}->pack_start($w{spQualityR}, 0, 0, 0);

    # Both
    $w{hbox3} = Gtk3::HBox->new(0, 5);
    $w{vbox}->pack_start($w{hbox3}, 0, 0, 0);
    $w{frDepth} = Gtk3::Label->new('Colour depth (bpp):');
    $w{hbox3}->pack_start($w{frDepth}, 0, 1, 0);

    $w{cbDepth} = Gtk3::ComboBoxText->new();
    $w{hbox3}->pack_start($w{cbDepth}, 0, 1, 0);
    foreach my $depth (8, 64, 256, 'full') {$w{cbDepth}->append_text($depth);};

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

    $w{spQualityR}->signal_connect('changed', sub {
        my $w = shift;

        if ($w->get_active_text eq 'custom') {
            $$self{gui}{hbox3}->set_sensitive(1);
        } else {
            $$self{gui}{hbox3}->set_sensitive(0);
        }
    });

    $$self{gui} = \%w;

    return 1;
}

# END: Private functions definitions
###################################################################

1;
