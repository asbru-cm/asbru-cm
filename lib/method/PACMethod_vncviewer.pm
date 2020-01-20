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

my %DEPTH = (8 => 0, 15 => 1, 16 => 2, 24 => 3, 32 => 4, 'default' => 5);
my %QUALITY = ('auto',0,'high',1,'medium',2,'low',3,'custom',4);
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
    $$self{gui}{spQuality}->set_active($QUALITY{$$options{quality}});
    $$self{gui}{entryVia}->set_text($$options{via});
    $$self{gui}{cbDepth}->set_active($DEPTH{$$options{depth} // 'default'});

    if ($$self{gui}{spQuality} eq 'custon') {
        $$self{gui}{hbox3}->set_sensitive(1);
    } else {
        $$self{gui}{hbox3}->set_sensitive(0);
    }

    return 1;
}

sub get_cfg {
    my $self = shift;

    my %options;

    $options{fullScreen} = $$self{gui}{chFullScreen}->get_active;
    $options{listen} = $$self{gui}{chListen}->get_active;
    $options{viewOnly} = $$self{gui}{chViewOnly}->get_active;
    $options{quality} = $$self{gui}{spQuality}->get_active_text;
    $options{via} = $$self{gui}{entryVia}->get_chars(0, -1);
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
    $hash{quality} = 'auto';
    $hash{depth} = 'default';
    $hash{via} = '';

    my @opts = split(/\s+-/, $cmd_line);
    foreach my $opt (@opts)
    {
        next unless $opt ne '';
        $opt =~ s/\s+$//go;

        if ($opt eq 'fullscreen') {
            $hash{fullScreen} = 1;
            $hash{nsize} = 0;
        }
        if ($opt eq 'listen') {
            $hash{listen} = 1;
        }
        if ($opt eq 'viewonly') {
            $hash{viewOnly} = 1;
        }
        if ($opt =~ /^quality\s+(\w+)$/go) {
            $hash{quality} = $1;
        }
        if ($opt =~ /^depth\s+(\d+)$/go) {
            $hash{depth} = $1;
        }
        if ($opt =~ /^via\s+(.+)$/go) {
            $hash{via} = $1;
        }
    }

    return \%hash;
}

sub _parseOptionsToCfg {
    my $hash = shift;

    my $txt = '';

    if (!$$hash{quality}) {
        $$hash{quality} = 'auto';
    }
    if ($QUALITY{$$hash{quality}} eq '') {
        $$hash{quality} = 'auto';
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
    if (($$hash{depth} ne 'default')&&($$hash{quality} eq 'custom')) {
        $txt .= " -depth $$hash{depth}";
    }
    $txt .= " -quality $$hash{quality}";
    $txt .= " -via $$hash{via}" if $$hash{via};

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

    $w{hbox1} = Gtk3::HBox->new(0, 5);
    $w{vbox}->pack_start($w{hbox1}, 0, 1, 5);

    $w{frQuality} = Gtk3::Label->new('Picture quality :');
    $w{hbox1}->pack_start($w{frQuality}, 0, 0, 0);
    $w{spQuality} = Gtk3::ComboBoxText->new();
    foreach my $q ('auto','high','medium','low','custom') {$w{spQuality}->append_text($q);};
    $w{hbox1}->pack_start($w{spQuality}, 0, 0, 0);

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

    $w{hbox3} = Gtk3::HBox->new(0, 5);
    $w{vbox}->pack_start($w{hbox3}, 0, 0, 0);

    $w{frDepth} = Gtk3::Label->new('Colour depth (bpp):');
    $w{hbox3}->pack_start($w{frDepth}, 0, 1, 0);

    $w{cbDepth} = Gtk3::ComboBoxText->new();
    $w{hbox3}->pack_start($w{cbDepth}, 0, 1, 0);
    foreach my $depth (8, 15, 16, 24, 32, 'default') {$w{cbDepth}->append_text($depth);};

    $w{hbox4} = Gtk3::HBox->new(0, 5);
    $w{vbox}->pack_start($w{hbox4}, 0, 0, 0);

    $w{lblVia} = Gtk3::Label->new('Proxy SSH Via:');
    $w{hbox4}->pack_start($w{lblVia}, 0, 0, 0);
    $w{lblVia}->set_tooltip_text('[-via gateway] : Starts an SSH to tunnel the connection');

    $w{entryVia} = Gtk3::Entry->new;
    $w{hbox4}->pack_start($w{entryVia}, 0, 1, 0);
    $w{entryVia}->set_tooltip_text('[-via gateway] : Starts an SSH to tunnel the connection');

    $w{spQuality}->signal_connect('changed', sub {
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
