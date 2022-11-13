package PACMethod_mosh;

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

sub new {
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

sub update {
    my $self = shift;
    my $cfg = shift;
    my $cfg_array = shift;

    defined $cfg and $$self{cfg} = $cfg;
    defined $cfg_array and $$self{cfg_array} = $cfg_array;

    my $options = _parseCfgToOptions($$self{cfg});

    $$self{gui}{rbPredictAdaptive}->set_active($$options{predictAdaptive});
    $$self{gui}{rbPredictAlways}->set_active($$options{predictAlways});
    $$self{gui}{rbPredictNever}->set_active($$options{predictNever});
    $$self{gui}{sbUDPPort}->set_value($$options{udpPort});
    $$self{gui}{sbUDPPort2}->set_value($$options{udpPort2});

    return 1;
}

sub get_cfg_array
{
    my $self = shift;

    my %options_array;

    return \%options_array;
}

sub get_cfg {
    my $self = shift;

    my %options;

    $options{predictAdaptive} = $$self{gui}{rbPredictAdaptive}->get_active;
    $options{predictAlways} = $$self{gui}{rbPredictAlways}->get_active;
    $options{predictNever} = $$self{gui}{rbPredictNever}->get_active;
    $options{udpPort} = $$self{gui}{sbUDPPort}->get_chars(0, -1);
    $options{udpPort2} = $$self{gui}{sbUDPPort2}->get_chars(0, -1);

    return _parseOptionsToCfg(\%options);
}

# END: Public class methods
###################################################################

###################################################################
# START: Private functions definitions

sub _parseCfgToOptions {
    my $cmd_line = shift;

    my %hash;
    $hash{predictAdaptive} = 1;
    $hash{predictAlways} = 0;
    $hash{predictNever} = 0;
    $hash{udpPort}  = 60000;
    $hash{udpPort2} = 60005;

    my @opts = split(/\s+-/, $cmd_line);
    foreach my $opt (@opts) {
        if ($opt eq '') {
            next;
        }
        $opt =~ s/\s+$//go;

        if ($opt eq 'a') {
            $hash{predictAlways} = 1;
        }
        if ($opt eq 'n') {
            $hash{predictNever} = 1;
        }
        if ($opt =~ /p\s+(\d+):(\d+)/go) {
            $hash{udpPort}  = $1;
            $hash{udpPort2} = $2;
        } elsif ($opt =~ /p\s+(\d+)/go) {
            $hash{udpPort} = $1;
            $hash{udpPort2} = $hash{udpPort}+5;
        }
    }

    return \%hash;
}

sub _parseOptionsToCfg {
    my $hash = shift;

    my $txt = '';
    if ($$hash{predictAlways}) {
        $txt .= ' -a';
    }
    if ($$hash{predictNever}) {
        $txt .= ' -n'
    }
    if (defined $$hash{udpPort}) {
        if (!$$hash{udpPort2} || $$hash{udpPort2} <= $$hash{udpPort}) {
            $$hash{udpPort2} = $$hash{udpPort}+5;
        }
        $txt .= " -p $$hash{udpPort}:$$hash{udpPort2}";
    }

    return $txt;
}

sub embed {
    my $self = shift;
    return 0;
}

sub _buildGUI {
    my $self = shift;

    my $container = $self->{container};
    my $cfg = $self->{cfg};

    my %w;

    $w{vbox} = $container;

    $w{frPredict} = Gtk3::Frame->new(' Select speculative local echo (predictions) model: ');
    $w{frPredict}->set_tooltip_text('[-(a|n)] : Controls use of speculative local echo (defaults to "adaptive")');
    $w{frPredict}->set_shadow_type('GTK_SHADOW_NONE');
    $w{vbox}->pack_start($w{frPredict}, 0, 1, 0);

    $w{hboxPredict} = Gtk3::HBox->new(0, 0);
    $w{frPredict}->add($w{hboxPredict});

    $w{rbPredictAdaptive} = Gtk3::RadioButton->new_with_label(undef, 'Adaptive');
    $w{hboxPredict}->pack_start($w{'rbPredictAdaptive'}, 0, 1, 0);

    $w{rbPredictAlways} = Gtk3::RadioButton->new_with_label($w{rbPredictAdaptive}, 'Always');
    $w{hboxPredict}->pack_start($w{rbPredictAlways}, 0, 1, 0);

    $w{rbPredictNever} = Gtk3::RadioButton->new_with_label($w{rbPredictAdaptive}, 'Never');
    $w{hboxPredict}->pack_start($w{rbPredictNever}, 0, 1, 0);

    $w{rbPredictAdaptive}->set_active(1);

    $w{vbox}->pack_start(Gtk3::HSeparator->new, 0, 1, 5);

    $w{hbUDPPort} = Gtk3::HBox->new(0, 0);
    $w{vbox}->pack_start($w{hbUDPPort}, 0, 1, 0);

    $w{hbUDPPort}->pack_start(Gtk3::Label->new('Server-side UDP Port Start: '), 0, 1, 0);
    $w{sbUDPPort} = Gtk3::SpinButton->new(Gtk3::Adjustment->new(60000, 1, 65535, 1, 10, 0), 1, 0);
    $w{hbUDPPort}->pack_start($w{sbUDPPort}, 0, 1, 0);

    $w{hbUDPPort}->pack_start(Gtk3::Label->new('Server-side UDP Port End: '), 0, 1, 0);
    $w{sbUDPPort2} = Gtk3::SpinButton->new(Gtk3::Adjustment->new(60005, 1, 65535, 1, 10, 0), 1, 0);
    $w{hbUDPPort}->pack_start($w{sbUDPPort2}, 0, 1, 0);

    $$self{gui} = \%w;

    # Avoid the enter of non numeric values in this entry
    $w{sbUDPPort}->signal_connect('insert_text' => sub {
        $_[1] =~ s/[^\d]//go;
        return $_[1], $_[3];
    });
    $w{sbUDPPort2}->signal_connect('insert_text' => sub {
        $_[1] =~ s/[^\d]//go;
        return $_[1], $_[3];
    });

    # Do not allow inverse port range or overlap, at least 1 unit difference
    $w{sbUDPPort}->signal_connect('value-changed' => sub {
        if ($w{sbUDPPort}->get_chars(0, -1) ge $w{sbUDPPort2}->get_chars(0, -1)) {
            $w{sbUDPPort2}->set_value(int($w{sbUDPPort}->get_chars(0, -1)) + 1);
        }
    });
    $w{sbUDPPort2}->signal_connect('value-changed' => sub {
        if ($w{sbUDPPort}->get_chars(0, -1) ge $w{sbUDPPort2}->get_chars(0, -1)) {
            $w{sbUDPPort}->set_value(int($w{sbUDPPort2}->get_chars(0, -1)) - 1);
        }
    });

    return 1;
}

# END: Private functions definitions
###################################################################

1;
