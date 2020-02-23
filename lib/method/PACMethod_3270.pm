package PACMethod_3270;

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

    $$self{gui}{chAllBold}->set_active($$options{allbold});
    $$self{gui}{chCbreak}->set_active($$options{cbreak});
    $$self{gui}{chNoprompt}->set_active($$options{noprompt});
    $$self{gui}{chMono}->set_active($$options{mono});
    $$self{gui}{'rbPrepend' . $$options{prepend}}->set_active(1);
    $$self{gui}{'rbModel' . $$options{model}}->set_active(1);
    $$self{gui}{entryEBCDIC}->set_text($$options{charset} // '');
    $$self{gui}{entryIM}->set_text($$options{im} // '');
    $$self{gui}{entryKM}->set_text($$options{keymap} // '');
    $$self{gui}{entryLU}->set_text($$options{printerlu} // '');
    $$self{gui}{entryTN}->set_text($$options{tn} // '');

    return 1;
}

sub get_cfg {
    my $self = shift;

    my %options;

    $options{allbold} = $$self{gui}{chAllBold}->get_active;
    $options{cbreak} = $$self{gui}{chCbreak}->get_active;
    $options{noprompt} = $$self{gui}{chNoprompt}->get_active;
    $options{mono} = $$self{gui}{chMono}->get_active;
    $options{charset} = $$self{gui}{entryEBCDIC}->get_chars(0, -1);
    $options{im} = $$self{gui}{entryIM}->get_chars(0, -1);
    $options{keymap} = $$self{gui}{entryKM}->get_chars(0, -1);
    $options{printerlu} = $$self{gui}{entryLU}->get_chars(0, -1);
    $options{tn} = $$self{gui}{entryTN}->get_chars(0, -1);
    $options{model} = '3279-4';
    foreach my $model ('3278-2', '3278-3', '3278-4', '3278-5', '3279-2', '3279-3', '3279-4', '3279-5')
    {
        $options{model} = $model if $$self{gui}{'rbModel' . $model}->get_active;
    }
    $options{prepend} = '';
    foreach my $prepend ('', 'P', 'S', 'N', 'L')
    {
        $options{prepend} = $prepend if $$self{gui}{'rbPrepend' . $prepend}->get_active;
    }

    return _parseOptionsToCfg(\%options);
}

# END: Public class methods
###################################################################

###################################################################
# START: Private functions definitions

sub _parseCfgToOptions {
    my $cmd_line = shift;

    my %hash;
    $hash{allbold} = 0;
    $hash{cbreak} = 0;
    $hash{noprompt} = 0;
    $hash{mono} = 0;
    $hash{prepend} = '';
    $hash{model} = '3279-4';
    $hash{charset} = '';
    $hash{im} = '';
    $hash{keymap} = '';
    $hash{printerlu} = '';
    $hash{tn} = '';

    my @opts = split(/\s+-/, $cmd_line);
    foreach my $opt (@opts)
    {
        next unless $opt ne '';
        $opt =~ s/\s+$//go;

        $opt eq 'allbold'                and    $hash{allbold} = 1;
        $opt eq 'cbreak'                and    $hash{cbreak} = 1;
        $opt eq 'noprompt'                and    $hash{noprompt} = 1;
        $opt eq 'mono'                    and    $hash{mono} = 1;
        $opt =~ /model (.+)/go            and $hash{model} = $1;
        $opt =~ /prepend_([P|S|N|L])/go    and $hash{prepend} = $1;
        $opt =~ /charset (.+)/go        and $hash{charset} = $1;
        $opt =~ /im (.+)/go                and $hash{im} = $1;
        $opt =~ /keymap (.+)/go            and $hash{keymap} = $1;
        $opt =~ /printerlu (.+)/go        and $hash{printerlu} = $1;
        $opt =~ /tn (.+)/go                and $hash{tn} = $1;
    }

    return \%hash;
}

sub _parseOptionsToCfg {
    my $hash = shift;

    my $txt = '';

    $txt .= ' -allbold'                            if $$hash{allbold} ;
    $txt .= ' -cbreak'                            if $$hash{cbreak} ;
    $txt .= ' -noprompt'                        if $$hash{noprompt} ;
    $txt .= ' -mono'                            if $$hash{mono} ;
    $txt .= ' -model ' . $$hash{model};
    $txt .= ' -prepend_' . $$hash{prepend}        if $$hash{prepend} ne '';
    $txt .= ' -charset ' . $$hash{charset}        if $$hash{charset} ne '';
    $txt .= ' -im ' . $$hash{im}                if $$hash{im} ne '';
    $txt .= ' -keymap ' . $$hash{keymap}        if $$hash{keymap} ne '';
    $txt .= ' -printerlu ' . $$hash{printerlu}    if $$hash{printerlu} ne '';
    $txt .= ' -tn ' . $$hash{tn}                if $$hash{tn} ne '';

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

    $w{frModel} = Gtk3::Frame->new(' Select display model: ');
    $w{frModel}->set_tooltip_text('[-model (3278|3279)-(2|3|4|5)] : Selects a display model(3278 BW , 3279 Colour, with different number of rows and columns');
    $w{vbox}->pack_start($w{frModel}, 0, 1, 0);

    $w{hboxModel} = Gtk3::HBox->new(0, 0);
    $w{frModel}->add($w{hboxModel});

    $w{'rbModel3278-2'} = Gtk3::RadioButton->new_with_label(undef, '3278-2');
    $w{hboxModel}->pack_start($w{'rbModel3278-2'}, 0, 1, 0);

    $w{'rbModel3278-3'} = Gtk3::RadioButton->new_with_label($w{'rbModel3278-2'}, '3278-3');
    $w{hboxModel}->pack_start($w{'rbModel3278-3'}, 0, 1, 0);

    $w{'rbModel3278-4'} = Gtk3::RadioButton->new_with_label($w{'rbModel3278-2'}, '3278-4');
    $w{hboxModel}->pack_start($w{'rbModel3278-4'}, 0, 1, 0);

    $w{'rbModel3278-5'} = Gtk3::RadioButton->new_with_label($w{'rbModel3278-2'}, '3278-5');
    $w{hboxModel}->pack_start($w{'rbModel3278-5'}, 0, 1, 0);

    $w{'rbModel3279-2'} = Gtk3::RadioButton->new_with_label($w{'rbModel3278-2'}, '3279-2');
    $w{hboxModel}->pack_start($w{'rbModel3279-2'}, 0, 1, 0);

    $w{'rbModel3279-3'} = Gtk3::RadioButton->new_with_label($w{'rbModel3278-2'}, '3279-3');
    $w{hboxModel}->pack_start($w{'rbModel3279-3'}, 0, 1, 0);

    $w{'rbModel3279-4'} = Gtk3::RadioButton->new_with_label($w{'rbModel3278-2'}, '3279-4');
    $w{hboxModel}->pack_start($w{'rbModel3279-4'}, 0, 1, 0);

    $w{'rbModel3279-5'} = Gtk3::RadioButton->new_with_label($w{'rbModel3278-2'}, '3279-5');
    $w{hboxModel}->pack_start($w{'rbModel3279-5'}, 0, 1, 0);

    $w{'rbModel3279-4'}->set_active(1);

    $w{frPrepend} = Gtk3::Frame->new(' Connect method: ');
    $w{vbox}->pack_start($w{frPrepend}, 0, 1, 0);

    $w{hboxPrepend} = Gtk3::HBox->new(0, 0);
    $w{frPrepend}->add($w{hboxPrepend});

    $w{rbPrepend} = Gtk3::RadioButton->new_with_label(undef, 'Standard');
    $w{hboxPrepend}->pack_start($w{rbPrepend}, 0, 1, 0);
    $w{rbPrepend}->set_tooltip_text('Do not prepend any character [P|S|N|L] to the host. That is, do a standard connection.');

    $w{rbPrependP} = Gtk3::RadioButton->new_with_label($w{rbPrepend}, 'Telnet-passthru');
    $w{hboxPrepend}->pack_start($w{rbPrependP}, 0, 1, 0);
    $w{rbPrependP}->set_tooltip_text('[P:] : causes the connection to go through the telnet-passthru service rather than directly to the host.');

    $w{rbPrependS} = Gtk3::RadioButton->new_with_label($w{rbPrepend}, 'NO Extended Data Stream');
    $w{hboxPrepend}->pack_start($w{rbPrependS}, 0, 1, 0);
    $w{rbPrependS}->set_tooltip_text('[S:] : Removes the "extended data stream" option reported to the host.');

    $w{rbPrependN} = Gtk3::RadioButton->new_with_label($w{rbPrepend}, 'NO TN3270E support');
    $w{hboxPrepend}->pack_start($w{rbPrependN}, 0, 1, 0);
    $w{rbPrependN}->set_tooltip_text('[N:] : Turns off TN3270E support for the session.');

    $w{rbPrependL} = Gtk3::RadioButton->new_with_label($w{rbPrepend}, 'Use SSL Tunnel');
    $w{hboxPrepend}->pack_start($w{rbPrependL}, 0, 1, 0);
    $w{rbPrependL}->set_tooltip_text('[L:] : Causes c3270 to first create an SSL tunnel to the host, and then create a TN3270 session inside the tunnel.');

    $w{rbPrepend}->set_active(1);

    $w{hboxSwitch1} = Gtk3::HBox->new(0, 0);
    $w{vbox}->pack_start($w{hboxSwitch1}, 0, 1, 0);

    $w{chAllBold} = Gtk3::CheckButton->new_with_label('ALL characters in bold');
    $w{hboxSwitch1}->pack_start($w{chAllBold}, 0, 1, 0);
    $w{chAllBold}->set_tooltip_text('[-allbold] : Forces all characters to be displayed in bold.');

    $w{chCbreak} = Gtk3::CheckButton->new_with_label('Use cbreak mode');
    $w{hboxSwitch1}->pack_start($w{chCbreak}, 0, 1, 0);
    $w{chCbreak}->set_tooltip_text('[-cbreak] : Causes c3270 to operate in cbreak mode, instead of raw mode.');

    $w{chNoprompt} = Gtk3::CheckButton->new_with_label('Disable command-prompt mode');
    $w{hboxSwitch1}->pack_start($w{chNoprompt}, 0, 1, 0);
    $w{chNoprompt}->set_tooltip_text('[-noprompt] : Disables command-prompt mode.');

    $w{chMono} = Gtk3::CheckButton->new_with_label('Force Monochrome');
    $w{hboxSwitch1}->pack_start($w{chMono}, 0, 1, 0);
    $w{chMono}->set_tooltip_text('[-mono] : Prevents c3270 from using color, ignoring any color capabilities reported by the terminal.');

    $w{vbox}->pack_start(Gtk3::HSeparator->new, 0, 1, 5);

    $w{hboxSwitch2} = Gtk3::HBox->new(0, 5);
    $w{vbox}->pack_start($w{hboxSwitch2}, 0, 1, 0);

    $w{lblEBCDIC} = Gtk3::Label->new('EBCDIC character set:');
    $w{hboxSwitch2}->pack_start($w{lblEBCDIC}, 0, 1, 0);

    $w{entryEBCDIC} = Gtk3::Entry->new;
    $w{entryEBCDIC}->set_tooltip_text('[-charset <name>] : Specifies an EBCDIC host character set.');
    $w{hboxSwitch2}->pack_start($w{entryEBCDIC}, 1, 1, 0);

    $w{lblIM} = Gtk3::Label->new(' Input Method:');
    $w{hboxSwitch2}->pack_start($w{lblIM}, 0, 1, 0);

    $w{entryIM} = Gtk3::Entry->new;
    $w{entryIM}->set_tooltip_text('[-im <method>] : Specifies the name of the input method to use for multi-byte input.');
    $w{hboxSwitch2}->pack_start($w{entryIM}, 1, 1, 0);

    $w{hboxSwitch3} = Gtk3::HBox->new(0, 0);
    $w{vbox}->pack_start($w{hboxSwitch3}, 0, 1, 0);

    $w{lblKM} = Gtk3::Label->new('Keyboard Map:');
    $w{hboxSwitch3}->pack_start($w{lblKM}, 0, 1, 0);

    $w{entryKM} = Gtk3::Entry->new;
    $w{entryKM}->set_tooltip_text('[-keymap <name>] : Specifies a keyboard map to be found in the resource c3270.keymap.name or the file name.');
    $w{hboxSwitch3}->pack_start($w{entryKM}, 1, 1, 0);

    $w{lblLU} = Gtk3::Label->new(' Printer LU:');
    $w{hboxSwitch3}->pack_start($w{lblLU}, 0, 1, 0);

    $w{entryLU} = Gtk3::Entry->new;
    $w{entryLU}->set_tooltip_text('[-printerlu <luname>] : Causes c3270 to automatically start a pr3287 printer session.');
    $w{hboxSwitch3}->pack_start($w{entryLU}, 1, 1, 0);

    $w{hboxSwitch4} = Gtk3::HBox->new(0, 0);
    $w{vbox}->pack_start($w{hboxSwitch4}, 0, 1, 0);

    $w{lblTN} = Gtk3::Label->new('Terminal Name:');
    $w{hboxSwitch4}->pack_start($w{lblTN}, 0, 1, 0);

    $w{entryTN} = Gtk3::Entry->new;
    $w{entryTN}->set_tooltip_text('[-tn <name>] : Specifies  the terminal name to be transmitted over the telnet connection.  The default name is IBM-model_name-E.');
    $w{hboxSwitch4}->pack_start($w{entryTN}, 1, 1, 0);

    $$self{gui} = \%w;

    return 1;
}

# END: Private functions definitions
###################################################################

1;
