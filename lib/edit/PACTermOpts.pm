package PACTermOpts;

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

# PAC modules
use PACUtils;

# END: Import Modules
###################################################################

###################################################################
# Define GLOBAL CLASS variables

my %CURSOR_SHAPE = (
    'block' => 0,
    'ibeam' => 1,
    'underline' => 2
);

my %BACKSPACE_BINDING = (
    'auto' => 0,
    'ascii-backspace' => 1,
    'ascii-delete' => 2,
    'delete-sequence' => 3,
    'tty' => 4
);

# END: Define GLOBAL CLASS variables
###################################################################

###################################################################
# START: Public class methods

sub new {
    my $class = shift;

    my $self = {};

    $self->{cfg} = shift;
    $self->{variables} = shift;

    $self->{container} = undef;
    $self->{gui} = undef;

    _buildTermOptsGUI($self);
    if (defined $$self{cfg}) {
        PACTermOpts::update($$self{cfg});
    }

    bless($self, $class);
    return $self;
}

sub update {
    my $self = shift;
    my $cfg = shift;

    if (defined $cfg) {
        $$self{cfg} = $cfg;
    }

    $$self{gui}{cbCTRLDisable}->set_active($$cfg{'disable CTRL key bindings'} // 0);
    $$self{gui}{cbALTDisable}->set_active($$cfg{'disable ALT key bindings'} // 0);
    $$self{gui}{cbSHIFTDisable}->set_active($$cfg{'disable SHIFT key bindings'} // 0);

    $$self{gui}{cbAudibleBell}->set_active($$cfg{'audible bell'} // 0);

    $$self{gui}{cbUsePersonal}->set_active(1); # Just to force 'toggled' signal to trigger that callback and update GUI
    $$self{gui}{cbUsePersonal}->set_active($$cfg{'use personal settings'} // 0);

    $$self{gui}{entryCfgPrompt}->set_text($$cfg{'command prompt'} // '[#%\$>]|\:\/\s*$');
    $$self{gui}{entryCfgUserPrompt}->set_text($$cfg{'username prompt'} // '([lL]ogin|[uU]suario|[uU]ser-?[nN]ame|[uU]ser):\s*$');
    $$self{gui}{entryCfgPasswordPrompt}->set_text($$cfg{'password prompt'} // '([pP]ass|[pP]ass[wW]or[dt](\s+for\s+|\w+@\w+)*|[cC]ontrase.a|Enter passphrase for key \'.+\')\s*:\s*$');

    $$self{gui}{cbTabBackColor}->set_active($$cfg{'use tab back color'} // 0);
    _updateWidgetColor($self, $cfg, $$self{gui}{colorTabBack}, 'tab back color', '#000000000000');
    $$self{gui}{colorTabBack}->set_sensitive($$self{gui}{cbTabBackColor}->get_active);
    _updateWidgetColor($self, $cfg, $$self{gui}{colorText}, 'text color', '#cc62cc62cc62');
    _updateWidgetColor($self, $cfg, $$self{gui}{colorBack}, 'back color', '#000000000000');
    _updateWidgetColor($self, $cfg, $$self{gui}{colorBold}, 'bold color', $$cfg{'text color'} // '#cc62cc62cc62');
    $$self{gui}{cbBoldAsText}->set_active($$cfg{'bold color like text'} // 1);
    $$self{gui}{colorBold}->set_sensitive(! $$self{gui}{cbBoldAsText}->get_active);
    $$self{gui}{fontTerminal}->set_font_name($$cfg{'terminal font'} // 'Monospace 9');
    $$self{gui}{comboCursorShape}->set_active($CURSOR_SHAPE{$$cfg{'cursor shape'} // 'block'});
    $$self{gui}{spCfgTerminalScrollback}->set_value($$cfg{'terminal scrollback lines'} // 5000);
    $$self{gui}{spCfgTerminalTransparency}->set_value($$cfg{'terminal transparency'} // 0);
    if ($PACMain::FUNCS{_MAIN}{_CFG}{'defaults'}{'terminal support transparency'}) {
        $$self{gui}{spCfgTerminalTransparency}->set_sensitive(1);
        $$self{gui}{spCfgTerminalTransparency}->set_tooltip_text("");
    } else {
        $$self{gui}{spCfgTerminalTransparency}->set_sensitive(0);
        $$self{gui}{spCfgTerminalTransparency}->set_tooltip_text("Transparency has been disabled globally.  See your global preferences to activate transparency.");
    }

    $$self{gui}{entrySelectWords}->set_text($$cfg{'terminal select words'} // '-.:_/');

    $$self{gui}{spCfgTmoutConnect}->set_value($$cfg{'timeout connect'} // 40);
    $$self{gui}{spCfgTmoutCommand}->set_value($$cfg{'timeout command'} // 40);

    $$self{gui}{cbCfgNewInTab}->set_active($$cfg{'open in tab'} // 1);
    $$self{gui}{cbCfgNewInWindow}->set_active(! ($$cfg{'open in tab'} // 1) );
    $$self{gui}{spCfgNewWindowWidth}->set_value($$cfg{'terminal window hsize'} // 800);
    $$self{gui}{spCfgNewWindowHeight}->set_value($$cfg{'terminal window vsize'} // 600);

    $$self{gui}{comboBackspace}->set_active($BACKSPACE_BINDING{$$cfg{'terminal backspace'} // 'auto'} // '0');

    $$self{gui}{comboEncoding}->set_active(($PACMain::FUNCS{_CONFIG}{_ENCODINGS_MAP}{$$cfg{'terminal character encoding'} // 'UTF-8'}) // -1);
    $$self{gui}{lblEncoding}->set_text(($PACMain::FUNCS{_CONFIG}{_ENCODINGS_HASH}{$$cfg{'terminal character encoding'} // 'RFC 3629'}) // '');

    return 1;
}

sub get_cfg {
    my $self = shift;

    my %options;

    $options{'disable CTRL key bindings'} = $$self{gui}{cbCTRLDisable}->get_active;
    $options{'disable ALT key bindings'} = $$self{gui}{cbALTDisable}->get_active;
    $options{'disable SHIFT key bindings'} = $$self{gui}{cbSHIFTDisable}->get_active;

    $options{'audible bell'} = $$self{gui}{cbAudibleBell}->get_active;

    $options{'use personal settings'} = $$self{gui}{cbUsePersonal}->get_active // 0;

    $options{'command prompt'} = $$self{gui}{entryCfgPrompt}->get_chars(0, -1);
    $options{'username prompt'} = $$self{gui}{entryCfgUserPrompt}->get_chars(0, -1);
    $options{'password prompt'} = $$self{gui}{entryCfgPasswordPrompt}->get_chars(0, -1);

    $options{'use tab back color'} = $$self{gui}{cbTabBackColor}->get_active;
    $options{'tab back color'} = $$self{gui}{colorTabBack}->get_color->to_string;
    $options{'text color'} = $$self{gui}{colorText}->get_color->to_string;
    $options{'back color'} = $$self{gui}{colorBack}->get_color->to_string;
    $options{'bold color'} = $$self{gui}{colorBold}->get_color->to_string;
    $options{'bold color like text'} = $$self{gui}{cbBoldAsText}->get_active;
    $options{'terminal font'} = $$self{gui}{fontTerminal}->get_font_name;
    $options{'cursor shape'} = $$self{gui}{comboCursorShape}->get_active_text;
    $options{'terminal scrollback lines'} = $$self{gui}{spCfgTerminalScrollback}->get_chars(0, -1);
    $options{'terminal transparency'} = $$self{gui}{spCfgTerminalTransparency}->get_value();
    $options{'terminal transparency'} =~ s/,/\./go;
    $options{'terminal select words'} = $$self{gui}{entrySelectWords}->get_chars(0, -1);

    $options{'timeout connect'} = $$self{gui}{spCfgTmoutConnect}->get_value;
    $options{'timeout command'} = $$self{gui}{spCfgTmoutCommand}->get_value;

    $options{'open in tab'} = $$self{gui}{cbCfgNewInTab}->get_active;
    $options{'terminal window hsize'} = $$self{gui}{spCfgNewWindowWidth}->get_value;
    $options{'terminal window vsize'} = $$self{gui}{spCfgNewWindowHeight}->get_value;
    $options{'terminal character encoding'} = $$self{gui}{comboEncoding}->get_active_text;
    $options{'terminal backspace'} = $$self{gui}{comboBackspace}->get_active_text;

    return \%options;
}

# END: Public class methods
###################################################################

###################################################################
# START: Private functions definitions

sub _buildTermOptsGUI {
    my $self = shift;

    my $container = $self->{container};
    my $cfg = $self->{cfg};

    my %w;

    # Build main vbox
    $w{vbox} = Gtk3::VBox->new(0, 0);

    $w{hboxopts} = Gtk3::HBox->new(0, 0);
    $w{vbox}->pack_start($w{hboxopts}, 0, 1, 0);

    $w{frameBindings} = Gtk3::Frame->new(" Disable next key bindings for this connection  ");
    $w{hboxopts}->pack_start($w{frameBindings}, 0, 1, 0);
    $w{frameBindings}->set_tooltip_text("Here you can select which key bindings will not be available in this connection. ");

    $w{hboxKBD} = Gtk3::HBox->new(0, 0);
    $w{frameBindings}->add($w{hboxKBD});
    $w{frameBindings}->set_shadow_type('GTK_SHADOW_NONE');
    $w{hboxKBD}->set_border_width(5);

    $w{cbCTRLDisable} = Gtk3::CheckButton->new_with_label('CTRL');
    $w{hboxKBD}->pack_start($w{cbCTRLDisable}, 0, 1, 0);

    $w{cbALTDisable} = Gtk3::CheckButton->new_with_label('ALT');
    $w{hboxKBD}->pack_start($w{cbALTDisable}, 0, 1, 0);

    $w{cbSHIFTDisable} = Gtk3::CheckButton->new_with_label('SHIFT');
    $w{hboxKBD}->pack_start($w{cbSHIFTDisable}, 0, 1, 0);

    $w{frameBell} = Gtk3::Frame->new(" Other options  ");
    $w{hboxopts}->pack_start($w{frameBell}, 0, 1, 0);

    $w{hboxbell} = Gtk3::HBox->new(0, 0);
    $w{frameBell}->add($w{hboxbell});
    $w{frameBell}->set_shadow_type('GTK_SHADOW_NONE');
    $w{hboxbell}->set_border_width(5);

    $w{cbAudibleBell} = Gtk3::CheckButton->new_with_label('Audible bell');
    $w{hboxbell}->pack_start($w{cbAudibleBell}, 0, 1, 0);

    $w{frameSuper} = Gtk3::Frame->new;
    $w{vbox}->pack_start($w{frameSuper}, 1, 1, 0);

    $w{cbUsePersonal} = Gtk3::CheckButton->new_with_label(' Use these personal options  ');
    $w{frameSuper}->set_label_widget($w{cbUsePersonal});
    $w{frameSuper}->set_shadow_type('GTK_SHADOW_NONE');

    $w{vbox1} = Gtk3::VBox->new(0, 0);
    $w{frameSuper}->add($w{vbox1});
    $w{vbox1}->set_border_width(5);

    my $hbox1 = Gtk3::HBox->new(0, 0);
    $w{vbox1}->pack_start($hbox1, 0, 1, 0);

    my $frameCommandPrompt = Gtk3::Frame->new(' Prompt RegExp  ');
    $hbox1->pack_start($frameCommandPrompt, 1, 1, 0);

    $w{entryCfgPrompt} = Gtk3::Entry->new;
    $w{entryCfgPrompt}->set_icon_from_stock('primary', 'asbru-prompt');
    $frameCommandPrompt->add($w{entryCfgPrompt});
    $frameCommandPrompt->set_shadow_type('GTK_SHADOW_NONE');

    my $frameUserPrompt = Gtk3::Frame->new(' Username RegExp  ');
    $hbox1->pack_start($frameUserPrompt, 1, 1, 0);

    $w{entryCfgUserPrompt} = Gtk3::Entry->new;
    $frameUserPrompt->add($w{entryCfgUserPrompt});
    $frameUserPrompt->set_shadow_type('GTK_SHADOW_NONE');

    my $framePasswordPrompt = Gtk3::Frame->new(' Password RegExp  ');
    $hbox1->pack_start($framePasswordPrompt, 1, 1, 0);

    $w{entryCfgPasswordPrompt} = Gtk3::Entry->new;
    $framePasswordPrompt->add($w{entryCfgPasswordPrompt});
    $framePasswordPrompt->set_shadow_type('GTK_SHADOW_NONE');

    my $frameTermUI = Gtk3::Frame->new(' Terminal UI  ');
    $w{vbox1}->pack_start($frameTermUI, 0, 1, 0);

    my $vboxTermUI = Gtk3::VBox->new(0, 0);
    $frameTermUI->add ($vboxTermUI);
    $frameTermUI->set_shadow_type('GTK_SHADOW_NONE');

    my $hboxTermUI1 = Gtk3::HBox->new(0, 0);
    $vboxTermUI->add ($hboxTermUI1);
    $hboxTermUI1->set_border_width(5);

    my $frameTxtFore = Gtk3::Frame->new('Text color:');
    $hboxTermUI1->pack_start($frameTxtFore, 0, 1, 0);
    $frameTxtFore->set_shadow_type('GTK_SHADOW_NONE');

    $w{colorText} = Gtk3::ColorButton->new;
    $frameTxtFore->add($w{colorText});

    my $frameTxtBack = Gtk3::Frame->new('Back color:');
    $hboxTermUI1->pack_start($frameTxtBack, 0, 1, 0);
    $frameTxtBack->set_shadow_type('GTK_SHADOW_NONE');

    $w{colorBack} = Gtk3::ColorButton->new;
    $frameTxtBack->add($w{colorBack});

    my $frameTxtBold = Gtk3::Frame->new;
    $hboxTermUI1->pack_start($frameTxtBold, 0, 1, 0);
    $frameTxtBold->set_shadow_type('GTK_SHADOW_NONE');

    $w{cbBoldAsText} = Gtk3::CheckButton->new_with_label(' Bold color like Text color  ');
    $frameTxtBold->set_label_widget($w{cbBoldAsText});

    $w{colorBold} = Gtk3::ColorButton->new;
    $frameTxtBold->add($w{colorBold});

    my $frameFont = Gtk3::Frame->new('Font:');
    $hboxTermUI1->pack_start($frameFont, 0, 1, 0);
    $frameFont->set_shadow_type('GTK_SHADOW_NONE');

    $w{fontTerminal} = Gtk3::FontButton->new;
    $frameFont->add($w{fontTerminal});

    my $frameTabBackColor = Gtk3::Frame->new;
    $hboxTermUI1->pack_start($frameTabBackColor, 0, 1, 0);
    $frameTabBackColor->set_shadow_type('GTK_SHADOW_NONE');

    $w{cbTabBackColor} = Gtk3::CheckButton->new_with_label(' Use this Tab background color  ');
    $frameTabBackColor->set_label_widget($w{cbTabBackColor});

    $w{colorTabBack} = Gtk3::ColorButton->new;
    $frameTabBackColor->add($w{colorTabBack});

    my $hboxTermUI2 = Gtk3::HBox->new(0, 0);
    $vboxTermUI->add ($hboxTermUI2);
    $hboxTermUI2->set_border_width(5);

    my $frameCursor = Gtk3::Frame->new('Cursor Shape:');
    $hboxTermUI2->pack_start($frameCursor, 0, 1, 0);
    $frameCursor->set_shadow_type('GTK_SHADOW_NONE');

    $w{comboCursorShape} = Gtk3::ComboBoxText->new;
    $frameCursor->add($w{comboCursorShape});
    foreach my $cursor (sort {$a cmp $b} keys %CURSOR_SHAPE) {$w{comboCursorShape}->append_text($cursor);};

    my $frameScroll = Gtk3::Frame->new('Scrollback lines:');
    $hboxTermUI2->pack_start($frameScroll, 0, 1, 0);
    $frameScroll->set_shadow_type('GTK_SHADOW_NONE');

    $w{spCfgTerminalScrollback} = Gtk3::SpinButton->new_with_range(1, 99999, 100);
    $frameScroll->add($w{spCfgTerminalScrollback});

    my $frameTransparency = Gtk3::Frame->new('Transparency:');
    $hboxTermUI2->pack_start($frameTransparency, 1, 1, 0);
    $frameTransparency->set_shadow_type('GTK_SHADOW_NONE');

    $w{spCfgTerminalTransparency} = Gtk3::HScale->new(Gtk3::Adjustment->new(0, 0, 1, 0.01, 0.2, 0.01));
    $w{spCfgTerminalTransparency}->set_digits(2);
    $frameTransparency->add($w{spCfgTerminalTransparency});

    my $frameSelectWords = Gtk3::Frame->new(' Select Word CHARS  ');
    $hboxTermUI2->pack_start($frameSelectWords, 0, 1, 0);

    $w{entrySelectWords} = Gtk3::Entry->new;
    $frameSelectWords->add($w{entrySelectWords});
    $frameSelectWords->set_shadow_type('GTK_SHADOW_NONE');

    $w{hboxTimeSize} = Gtk3::HBox->new(0, 0);
    $w{vbox1}->pack_start($w{hboxTimeSize}, 0, 1, 0);

    my $frameTimeOuts = Gtk3::Frame->new(' Time outs (seconds)  ');
    $w{hboxTimeSize}->pack_start($frameTimeOuts, 0, 1, 0);

    my $hbox2 = Gtk3::HBox->new(0, 0);
    $frameTimeOuts->add($hbox2);
    $frameTimeOuts->set_shadow_type('GTK_SHADOW_NONE');
    $hbox2->set_border_width(5);

    my $frameTOConn = Gtk3::Frame->new(' Connection ');
    $hbox2->pack_start($frameTOConn, 0, 1, 0),
    $frameTOConn->set_shadow_type('GTK_SHADOW_NONE');
    $frameTOConn->set_tooltip_text('Set to 0 (zero) to wait forever until connection is established');

    $w{spCfgTmoutConnect} = Gtk3::SpinButton->new_with_range(0, 86400, 1);
    $frameTOConn->add($w{spCfgTmoutConnect});

    my $frameTOCmd = Gtk3::Frame->new(' Expect Cmd exec  ');
    $hbox2->pack_start($frameTOCmd, 0, 1, 0),
    $frameTOCmd->set_shadow_type('GTK_SHADOW_NONE');
    $frameTOCmd->set_tooltip_text('Set to 0 (zero) to wait forever for Expect and equivalentes commands to complete');

    $w{spCfgTmoutCommand} = Gtk3::SpinButton->new_with_range(0, 86400, 1);
    $frameTOCmd->add($w{spCfgTmoutCommand});

    my $frameWindowSize = Gtk3::Frame->new(' Open NEW connection on  ');
    $w{hboxTimeSize}->pack_start($frameWindowSize, 0, 1, 0);

    my $vboxWindowSize = Gtk3::VBox->new(0, 0);
    $frameWindowSize->add($vboxWindowSize);
    $frameWindowSize->set_shadow_type('GTK_SHADOW_NONE');

    $w{cbCfgNewInTab} = Gtk3::RadioButton->new_with_label(undef, 'Tab');
    $vboxWindowSize->pack_start($w{cbCfgNewInTab}, 0, 1, 0);

    my $hboxWindowSize = Gtk3::HBox->new(0, 0);
    $vboxWindowSize->pack_start($hboxWindowSize, 0, 1, 0);

    $w{cbCfgNewInWindow} = Gtk3::RadioButton->new_with_label($w{cbCfgNewInTab}, 'Window');
    $hboxWindowSize->pack_start($w{cbCfgNewInWindow}, 0, 1, 0);

    $w{hboxWidthHeight} = Gtk3::HBox->new(0, 0);
    $hboxWindowSize->pack_start($w{hboxWidthHeight}, 0, 1, 0);

    $w{hboxWidthHeight}->pack_start(Gtk3::Label->new(' Width  '), 0, 1, 0);
    $w{spCfgNewWindowWidth} = Gtk3::SpinButton->new_with_range(1, 4096, 10);
    $w{hboxWidthHeight}->pack_start($w{spCfgNewWindowWidth}, 0, 1, 0);

    $w{hboxWidthHeight}->pack_start(Gtk3::Label->new(' Height  '), 0, 1, 0);
    $w{spCfgNewWindowHeight} = Gtk3::SpinButton->new_with_range(1, 4096, 10);
    $w{hboxWidthHeight}->pack_start($w{spCfgNewWindowHeight}, 0, 1, 0);

    my $frameBackspace = Gtk3::Frame->new(' Backspace binding  ');
    $w{hboxTimeSize}->pack_start($frameBackspace, 0, 1, 0);

    $w{comboBackspace} = Gtk3::ComboBoxText->new;
    $frameBackspace->add($w{comboBackspace});
    $frameBackspace->set_shadow_type('GTK_SHADOW_NONE');

    my $frameEncoding = Gtk3::Frame->new(' Character Encoding  ');
    $w{vbox1}->pack_start($frameEncoding, 1, 1, 0);

    my $vboxEnc = Gtk3::VBox->new(0, 0);
    $frameEncoding->add($vboxEnc);
    $frameEncoding->set_shadow_type('GTK_SHADOW_NONE');

    $w{comboEncoding} = Gtk3::ComboBoxText->new;
    $vboxEnc->pack_start($w{comboEncoding}, 0, 1, 0);

    $w{lblEncoding} = Gtk3::Label->new('');
    $vboxEnc->pack_start($w{lblEncoding}, 1, 1, 0);

    my $sep = Gtk3::HSeparator->new;
    $w{vbox1}->pack_start($sep, 0, 1, 5);

    $w{btnResetDefaults} = Gtk3::Button->new_with_label('Reset to DEFAULT values');
    $w{vbox1}->pack_start($w{btnResetDefaults}, 0, 1, 0);
    $w{btnResetDefaults}->set_image(Gtk3::Image->new_from_stock('gtk-undo', 'menu') );

    $$self{container} = $w{vbox};
    $$self{gui} = \%w;

    # Populate the Encodings combobox
    foreach my $enc (sort {uc($a) cmp uc($b)} keys %{$PACMain::FUNCS{_CONFIG}{_ENCODINGS_ARRAY}}) {$w{comboEncoding}->append_text($enc);}

    # Populate the Backspace binding combobox
    foreach my $key ('auto', 'ascii-backspace', 'ascii-delete', 'delete-sequence', 'tty') {$w{comboBackspace}->append_text($key);}

    # Setup some callbacks
    $w{cbUsePersonal}->signal_connect('toggled' => sub {$w{vbox1}->set_sensitive($w{cbUsePersonal}->get_active);});
    $w{cbTabBackColor}->signal_connect('toggled' => sub {$w{colorTabBack}->set_sensitive($w{cbTabBackColor}->get_active);});
    $w{cbBoldAsText}->signal_connect('toggled' => sub {$w{colorBold}->set_sensitive(! $w{cbBoldAsText}->get_active);});
    $w{comboEncoding}->signal_connect('changed' => sub {$w{lblEncoding}->set_text($PACMain::FUNCS{_CONFIG}{_ENCODINGS_HASH}{$w{comboEncoding}->get_active_text} // '');});
    $w{cbCfgNewInWindow}->signal_connect('toggled' => sub {$w{hboxWidthHeight}->set_sensitive($w{cbCfgNewInWindow}->get_active); return 1;});
    $w{btnResetDefaults}->signal_connect('clicked' => sub {
        my %default_cfg;
        defined $default_cfg{'defaults'}{1} or 1;

        PACUtils::_cfgSanityCheck(\%default_cfg);
        $self->update(\%default_cfg);
    });

    return 1;
}

# END: Private functions definitions
###################################################################

1;
