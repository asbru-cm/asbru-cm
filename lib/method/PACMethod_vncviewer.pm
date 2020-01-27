package PACMethod_vncviewer;

###############################################################################
# This file is part of Ásbrú Connection Manager
#
# Copyright (C) 2017-2019 Ásbrú Connection Manager team (https://asbru-cm.net)
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
my %DEPTHR = (8 => 0, 64 => 1, 256 => 2, 'full' => 3);
my %depthR = (8 => 'rgb111', 64 => 'rgb222', 256 => 'pal8', 'full' => 'full');
my %Rdepth = ('rgb111'=>8,'rgb222'=>64,'pal8'=>256, 'full' => 'full');
my %QUALITY = ('auto',0,'high',1,'medium',2,'low',3,'custom',4);
my %CLIENT = ('TigerVNC',0,'TightVNC',1,'RealVNC',2);
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

    $$self{gui}{spVNC}->set_active($CLIENT{$$options{vncClient}});

    $$self{gui}{chNaturalSize}->set_active(! ($$options{fullScreen}) );
    $$self{gui}{chFullScreen}->set_active($$options{fullScreen});
    $$self{gui}{chListen}->set_active($$options{listen});
    $$self{gui}{chViewOnly}->set_active($$options{viewOnly});
    $$self{gui}{spCompressLevel}->set_value($$options{compressLevel} // 0);
    $$self{gui}{entryVia}->set_text($$options{via});

    _setGUIState($self,$options);

    return 1;
}

sub get_cfg {
    my $self = shift;

    my %options;

    $options{vncClient} = $$self{gui}{spVNC}->get_active_text;

    $options{fullScreen} = $$self{gui}{chFullScreen}->get_active;
    $options{listen} = $$self{gui}{chListen}->get_active;
    $options{viewOnly} = $$self{gui}{chViewOnly}->get_active;
    $options{compressLevel} = $$self{gui}{spCompressLevel}->get_value;
    if ($options{vncClient} eq 'RealVNC') {
        $options{quality} = $$self{gui}{spQualityR}->get_active_text;
    } else {
        $options{quality} = $$self{gui}{spQuality}->get_value;
    }
    $options{via} = $$self{gui}{entryVia}->get_chars(0, -1);
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

    if ($$options{vncClient} eq 'RealVNC') {
        $$self{gui}{hbox1R}->set_sensitive(1);
        $$self{gui}{spQualityR}->set_active($QUALITY{$$options{quality}});
        if (!defined $DEPTHR{$$options{depth}}) {
            $$options{depth} = 'full';
        }
        $$self{gui}{cbDepth}->remove_all();
        foreach my $depth (8, 64, 256, 'full') {$$self{gui}{cbDepth}->append_text($depth);};
        $$self{gui}{cbDepth}->set_active($DEPTHR{$$options{depth}});
        if ($$options{quality} eq 'custom') {
            $$self{gui}{hbox3}->set_sensitive(1);
        } else {
            $$self{gui}{hbox3}->set_sensitive(0);
        }
        $$self{gui}{spQuality}->set_value(5);
        $$self{gui}{hbox1}->set_sensitive(0);
        $$self{gui}{hbox1}->hide();
        $$self{gui}{hbox1R}->set_sensitive(1);
        $$self{gui}{hbox1R}->show();
        $$self{gui}{hbox4}->set_sensitive(0);
        $$self{gui}{hbox4}->hide();
    } else {
        if (!defined $DEPTH{$$options{depth}}) {
            $$options{depth} = 'default';
        }
        $$self{gui}{cbDepth}->remove_all();
        foreach my $depth (8, 15, 16, 24, 32, 'default') {$$self{gui}{cbDepth}->append_text($depth);};
        $$self{gui}{cbDepth}->set_active($DEPTH{$$options{depth}});
        $$self{gui}{hbox3}->set_sensitive(1);
        $$self{gui}{spQuality}->set_value($$options{quality});
        $$self{gui}{spQualityR}->set_active(0);
        $$self{gui}{hbox1}->set_sensitive(1);
        $$self{gui}{hbox1}->show();
        $$self{gui}{hbox1R}->set_sensitive(0);
        $$self{gui}{hbox1R}->hide();
        $$self{gui}{hbox4}->set_sensitive(1);
        $$self{gui}{hbox4}->show();
    }
}

sub _parseCfgToOptions {
    my $cmd_line = shift;

    my %hash;
    $hash{vncClient} = 'TigerVNC';
    $hash{fullScreen} = 0;
    $hash{nsize} = 1;
    $hash{compressLevel} = 8;
    $hash{via} = '';

    my @opts = split(/\s+-/, $cmd_line);
    foreach my $opt (@opts)
    {
        next unless $opt ne '';
        $opt =~ s/\s+$//go;

        if ($opt =~ /^client\s+(\w+)$/go) {
            $hash{vncClient} = $1;
        } elsif ($opt =~ /^compresslevel\s+(\d+)$/) {
            $hash{compressLevel} = $1;
        } elsif ($opt =~ /^quality/go) {
            if ($hash{vncClient} eq 'RealVNC') {
                $hash{depth} = 'full';
                $hash{quality} = 'auto';
                if ($opt =~ /^quality\s+([a-z]+)$/) {
                    $hash{quality} = $1;
                }
            } else {
                $hash{depth} = 'default';
                $hash{quality} = 5;
                if ($opt =~ /^quality\s+(\d+)$/) {
                    $hash{quality} = $1;
                }
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
        } elsif ($opt =~ /^via\s+(.+)$/) {
            $hash{via} = $1;
        }
    }

    return \%hash;
}

sub _parseOptionsToCfg {
    my $hash = shift;
    my $txt = '';

    $txt .= " -client $$hash{vncClient}";
    if (!$$hash{quality}) {
        if ($$hash{vncClient} eq 'RealVNC') {
            $$hash{quality} = 'auto';
            if ($QUALITY{$$hash{quality}} eq '') {
                $$hash{quality} = 'auto';
            }
        } else {
            $$hash{quality} = 5;
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
    $txt .= " -quality $$hash{quality}";
    if ($$hash{vncClient} eq 'RealVNC') {
        if ($$hash{quality} eq 'custom') {
            $txt .= " -colorlevel $depthR{$$hash{depth}}";
        }
    } else {
        $txt .= " -depth $$hash{depth}";
        $txt .= " -compresslevel $$hash{compressLevel}";
    }
    if ($$hash{via}) {
        $txt .= " -via $$hash{via}";
    }

    #print "$txt\n";
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

    $w{hboxvnc} = Gtk3::HBox->new(0, 5);
    $w{vbox}->pack_start($w{hboxvnc}, 0, 1, 5);
    $w{frVNC} = Gtk3::Label->new('VNC Client :');
    $w{hboxvnc}->pack_start($w{frVNC}, 0, 0, 0);
    $w{spVNC} = Gtk3::ComboBoxText->new();
    foreach my $q ('TigerVNC','TightVNC','RealVNC') {$w{spVNC}->append_text($q);};
    $w{hboxvnc}->pack_start($w{spVNC}, 0, 0, 0);

    # TigerVNC
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


    # RealVNC
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
    foreach my $depth (8, 15, 16, 24, 32, 'default') {$w{cbDepth}->append_text($depth);};

    # TigerVNC
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

    $w{hbox4} = Gtk3::HBox->new(0, 5);
    $w{vbox}->pack_start($w{hbox4}, 0, 0, 0);

    $w{lblVia} = Gtk3::Label->new('Proxy SSH Via:');
    $w{hbox4}->pack_start($w{lblVia}, 0, 0, 0);
    $w{lblVia}->set_tooltip_text('[-via gateway] : Starts an SSH to tunnel the connection');

    $w{entryVia} = Gtk3::Entry->new;
    $w{hbox4}->pack_start($w{entryVia}, 0, 1, 0);
    $w{entryVia}->set_tooltip_text('[-via gateway] : Starts an SSH to tunnel the connection');

    $w{spQualityR}->signal_connect('changed', sub {
        my $w = shift;

        if ($w->get_active_text eq 'custom') {
            $$self{gui}{hbox3}->set_sensitive(1);
        } else {
            $$self{gui}{hbox3}->set_sensitive(0);
        }
    });
    $w{spVNC}->signal_connect('changed', sub {
        my $w = shift;

        if ($w->get_active_text eq 'RealVNC') {
            $$self{gui}{hbox1R}->show();
            $$self{gui}{hbox1}->hide();
            $$self{gui}{hbox1R}->set_sensitive(1);
            $$self{gui}{hbox1}->set_sensitive(0);
            if ((defined $$self{gui}{spQualityR}->get_active_text)&&($$self{gui}{spQualityR}->get_active_text eq 'custom')) {
                $$self{gui}{hbox3}->set_sensitive(1);
            } else {
                $$self{gui}{hbox3}->set_sensitive(0);
            }
            $$self{gui}{hbox4}->set_sensitive(0);
            $$self{gui}{hbox4}->hide();
            $$self{gui}{cbDepth}->remove_all();
            foreach my $depth (8, 64, 256, 'full') {$$self{gui}{cbDepth}->append_text($depth);};
            $$self{gui}{cbDepth}->set_active(3);
        } else {
            $$self{gui}{hbox1}->show();
            $$self{gui}{hbox1R}->hide();
            $$self{gui}{hbox1R}->set_sensitive(0);
            $$self{gui}{hbox1}->set_sensitive(1);
            $$self{gui}{hbox4}->set_sensitive(1);
            $$self{gui}{hbox4}->show();
            $$self{gui}{cbDepth}->remove_all();
            foreach my $depth (8, 15, 16, 24, 32, 'default') {$$self{gui}{cbDepth}->append_text($depth);};
            $$self{gui}{cbDepth}->set_active(5);
        }
    });

    $$self{gui} = \%w;

    return 1;
}

# END: Private functions definitions
###################################################################

1;
