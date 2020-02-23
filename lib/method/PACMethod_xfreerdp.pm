package PACMethod_xfreerdp;

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

my %BPP = (8 => 0, 15 => 1, 16 => 2, 24 => 3, 32 => 4);

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

    $$self{gui}{cbBPP}->set_active($BPP{$$options{bpp} // 24});
    $$self{gui}{chAttachToConsole}->set_active($$options{attachToConsole});
    $$self{gui}{chUseCompression}->set_active($$options{useCompression});
    $$self{gui}{chFullscreen}->set_active($$options{fullScreen});
    $$self{gui}{chEmbed}->set_active($$options{embed});
    $$self{gui}{chPercentage}->set_active($$options{percent});
    $$self{gui}{chWidthHeight}->set_active($$options{wh});
    $$self{gui}{spGeometry}->set_value($$options{geometry}) if $$options{percent};
    $$self{gui}{spWidth}->set_value($$options{width} // 640);
    $$self{gui}{spHeight}->set_value($$options{height} // 480);
    $$self{gui}{spGeometry}->set_sensitive($$options{percent});
    $$self{gui}{hboxWidthHeight}->set_sensitive($$options{wh});
    $$self{gui}{entryKeyboard}->set_text($$options{keyboardLocale});
    $$self{gui}{cbRedirSound}->set_active($$options{redirSound} // 1);
    $$self{gui}{cbRedirClipboard}->set_active($$options{redirClipboard} // 0);
    $$self{gui}{entryDomain}->set_text($$options{domain} // '');
    $$self{gui}{chIgnoreCert}->set_active($$options{ignoreCert} // 0);
    $$self{gui}{chNoAuth}->set_active($$options{noAuth} // 0);
    $$self{gui}{chNoFastPath}->set_active($$options{nofastPath} // 0);
    $$self{gui}{chRFX}->set_active($$options{rfx} // 0);
    $$self{gui}{chNSCodec}->set_active($$options{nsCodec} // 0);
    $$self{gui}{chDynamicResolution}->set_active($$options{dynamicResolution} // 0);
    $$self{gui}{chNoRDP}->set_active($$options{noRDP} // 0);
    $$self{gui}{chNoTLS}->set_active($$options{noTLS} // 0);
    $$self{gui}{chNoNLA}->set_active($$options{noNLA} // 0);
    $$self{gui}{chFontSmooth}->set_active($$options{fontSmooth} // 0);
    $$self{gui}{chNoGrabKbd}->set_active($$options{noGrabKbd} // 0);
    $$self{gui}{entryStartupShell}->set_text($$options{startupshell} // '');
    $$self{gui}{entryOtherOptions}->set_text($$options{otherOptions} // '');

    # Destroy previuos widgets
    $$self{gui}{vbRedirect}->foreach(sub {$_[0]->destroy();});

    # Empty disk redirect widgets' list
    $$self{listRedir} = [];

    # Now, add the -new?- local forwarded disk shares widgets
    foreach my $hash (@{$$options{redirDisk}}) {$self->_buildRedir($hash);}

    return 1;
}

sub get_cfg {
    my $self = shift;

    my %options;

    $options{bpp} = $$self{gui}{cbBPP}->get_active_text;
    $options{attachToConsole} = $$self{gui}{chAttachToConsole}->get_active;
    $options{useCompression} = $$self{gui}{chUseCompression}->get_active;
    $options{fullScreen} = $$self{gui}{chFullscreen}->get_active;
    $options{geometry} = $$self{gui}{spGeometry}->get_value;
    $options{percent} = $$self{gui}{chPercentage}->get_active;
    $options{width} = $$self{gui}{spWidth}->get_chars(0, -1);
    $options{height} = $$self{gui}{spHeight}->get_chars(0, -1);
    $options{wh} = $$self{gui}{chWidthHeight}->get_active;
    $options{embed} = ! ($$self{gui}{chFullscreen}->get_active || $$self{gui}{chPercentage}->get_active || $$self{gui}{chWidthHeight}->get_active);
    $options{keyboardLocale} = $$self{gui}{entryKeyboard}->get_chars(0, -1);
    $options{redirSound} = $$self{gui}{cbRedirSound}->get_active;
    $options{redirClipboard} = $$self{gui}{cbRedirClipboard}->get_active;
    $options{domain} = $$self{gui}{entryDomain}->get_chars(0, -1);
    $options{ignoreCert} = $$self{gui}{chIgnoreCert}->get_active;
    $options{noAuth} = $$self{gui}{chNoAuth}->get_active;
    $options{nofastPath} = $$self{gui}{chNoFastPath}->get_active;
    $options{rfx} = $$self{gui}{chRFX}->get_active;
    $options{nsCodec} = $$self{gui}{chNSCodec}->get_active;
    $options{dynamicResolution} = $$self{gui}{chDynamicResolution}->get_active;
    $options{noRDP} = $$self{gui}{chNoRDP}->get_active;
    $options{noTLS} = $$self{gui}{chNoTLS}->get_active;
    $options{noNLA} = $$self{gui}{chNoNLA}->get_active;
    $options{fontSmooth} = $$self{gui}{chFontSmooth}->get_active;
    $options{noGrabKbd} = $$self{gui}{chNoGrabKbd}->get_active;
    $options{startupshell} = $$self{gui}{entryStartupShell}->get_chars(0, -1);
    $options{otherOptions} = $$self{gui}{entryOtherOptions}->get_chars(0, -1);

    foreach my $w (@{$$self{listRedir}}) {
        my %hash;
        $hash{'redirDiskShare'} = $$w{entryRedirShare}->get_chars(0, -1) || '';
        $hash{'redirDiskPath'} = $$w{fcForwardPath}->get_uri;
        $hash{'redirDiskPath'} =~ s/^(.+?\/\/)(.+)$/$2/go;
        next unless $hash{'redirDiskShare'} && $hash{'redirDiskPath'};
        push(@{$options{redirDisk}}, \%hash);
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
    $hash{bpp} = 24;
    $hash{attachToConsole} = 0;
    $hash{useCompression} = 0;
    $hash{fullScreen} = 0;
    $hash{embed} = 1;
    $hash{percent} = 0;
    $hash{geometry} = 90;
    $hash{wh} = 0;
    $hash{width} = 640;
    $hash{height} = 480;
    $hash{keyboardLocale} = '';
    $hash{redirDiskShare} = '';
    $hash{redirDiskPath} = $ENV{'HOME'};
    $hash{redirSound} = 0;
    $hash{redirClipboard} = 0;
    $hash{domain} = '';
    $hash{ignoreCert} = 0;
    $hash{noAuth} = 0;
    $hash{nofastPath} = 0;
    $hash{rfx} = 0;
    $hash{nsCodec} = 0;
    $hash{dynamicResolution} = 0;
    $hash{noRDP} = 0;
    $hash{noTLS} = 0;
    $hash{noNLA} = 0;
    $hash{fontSmooth} = 0;
        $hash{noGrabKbd} = 0;
    $hash{startupshell} = '';
    $hash{otherOptions} = '';

    my @opts = split(/ /, $cmd_line);
    foreach my $opt (@opts) {
        next unless $opt ne '';
        $opt =~ s/\s+$//go;

        if ($opt =~ /^\/bpp:(8|15|16|24|32)$/go)    {$hash{bpp} = $1;}
        elsif ($opt eq '/admin')    {$hash{attachToConsole} = 1;}
        elsif ($opt eq '+compression')    {$hash{useCompression} = 1;}
        elsif ($opt =~ /^\/shell:(.+)$/go)    {$hash{startupshell} = $1;}
        elsif ($opt eq '/f')        {$hash{fullScreen} = 1; $hash{percent} = 0; $hash{wh} = 0; $hash{'embed'} = 0;}
        elsif ($opt =~ /^\/size:(\d+(\.\d+)?)%$/go)    {$hash{geometry} = $1; $hash{percent} = 1; $hash{wh} = 0; $hash{'embed'} = 0;}
        elsif ($opt =~ /^\/size:(\d+)x(\d+)$/go)    {$hash{width} = $1; $hash{height} = $2; $hash{wh} = 1; $hash{percent} = 0; $hash{'embed'} = 0;}
        elsif ($opt =~ /^\/kbd:(.+)$/go)    {$hash{keyboardLocale} = $1;}
        elsif ($opt =~ /^\/sound:sys:alsa$/go)    {$hash{redirSound} = 1;}
        elsif ($opt eq '+clipboard')    {$hash{redirClipboard} = 1;}
        elsif ($opt =~ /^\/d:(.+)$/go)        {$hash{domain} = $1;}
        elsif ($opt eq '/cert-ignore')    {$hash{ignoreCert} = 1;}
        elsif ($opt =~ /^-authentication$/go)    {$hash{noAuth} = 1;}
        elsif ($opt eq '-fast-path')    {$hash{nofastPath} = 1;}
        elsif ($opt eq '/rfx')    {$hash{rfx} = 1;}
        elsif ($opt eq '/nsc')    {$hash{nsCodec} = 1;}
        elsif ($opt eq '/dynamic-resolution')    {$hash{dynamicResolution} = 1;}
        elsif ($opt eq '-sec-rdp')    {$hash{noRDP} = 1;}
        elsif ($opt eq '-sec-tls')    {$hash{noTLS} = 1;}
        elsif ($opt eq '-sec-nla')    {$hash{noNLA} = 1;}
        elsif ($opt eq '+fonts')    {$hash{fontSmooth} = 1;}
        elsif ($opt eq '-grab-keyboard')    {$hash{noGrabKbd} = 1;}
        elsif ($opt =~ /^\/drive:(.+),(.+)$/g)
        {
            my %redir;
            $redir{redirDiskShare} = $1;
            $redir{redirDiskPath} = $2;
            push(@{$hash{redirDisk}}, \%redir);
        }
        else {$hash{otherOptions}    .= ' ' . $opt;}
    }

    return \%hash;
}

sub _parseOptionsToCfg {
    my $hash = shift;

    my $txt = '';

    $txt .= ' /bpp:' . $$hash{bpp};
    $txt .= ' /admin' if $$hash{attachToConsole};
    $txt .= ' +compression' if $$hash{useCompression};
    $txt .= ' /f' if $$hash{fullScreen};
    if ($$hash{percent})
    {
        $txt .= ' /size:' . $$hash{geometry} . '%';
    }
    elsif ($$hash{wh})
    {
        $txt .= ' /size:' . $$hash{width} . 'x' . $$hash{height};
    }
    $txt .= ' /kbd:' . $$hash{keyboardLocale} if $$hash{keyboardLocale} ne '';
    $txt .= ' /shell:' . $$hash{startupshell} if $$hash{startupshell} ne '';
    $txt .= ' /d:' . $$hash{domain} if $$hash{domain} ne '';
    $txt .= ' +clipboard' if $$hash{redirClipboard};
        $txt .= ' /sound:sys:alsa' if $$hash{redirSound};
    $txt .= ' /cert-ignore' if $$hash{ignoreCert};
    $txt .= ' -authentication' if $$hash{noAuth};
    $txt .= ' -fast-path' if $$hash{nofastPath};
    $txt .= ' /rfx' if $$hash{rfx};
    $txt .= ' /nsc' if $$hash{nsCodec};
    $txt .= ' /dynamic-resolution' if $$hash{dynamicResolution};
    $txt .= ' -sec-rdp' if $$hash{noRDP};
    $txt .= ' -sec-tls' if $$hash{noTLS};
    $txt .= ' -sec-nla' if $$hash{noNLA};
    $txt .= ' +fonts' if $$hash{fontSmooth};
    $txt .= ' -grab-keyboard' if $$hash{noGrabKbd};

    foreach my $redir (@{$$hash{redirDisk}}) {$txt .= " /drive:$$redir{redirDiskShare},$$redir{redirDiskPath}";}

    $txt .= ' ' . $$hash{otherOptions} if $$hash{otherOptions} ne '';

    return $txt;
}

sub embed {
    my $self = shift;
    return ! ($$self{gui}{chFullscreen}->get_active || $$self{gui}{chPercentage}->get_active || $$self{gui}{chWidthHeight}->get_active);
}

sub _buildGUI {
    my $self = shift;

    my $container = $self->{container};
    my $cfg = $self->{cfg};

    my %w;

    $w{vbox} = $container;

        $w{hbox1} = Gtk3::HBox->new(0, 5);
        $w{vbox}->pack_start($w{hbox1}, 0, 1, 5);

            $w{frBPP} = Gtk3::Frame->new('BPP:');
            $w{hbox1}->pack_start($w{frBPP}, 0, 1, 0);
            $w{frBPP}->set_shadow_type('GTK_SHADOW_NONE');
            $w{frBPP}->set_tooltip_text('[/bpp:] : Sets the colour depth for the connection (8, 15, 16, 24 or 32)');

                $w{cbBPP} = Gtk3::ComboBoxText->new;
                $w{frBPP}->add($w{cbBPP});
                foreach my $bpp (8, 15, 16, 24, 32) {$w{cbBPP}->append_text($bpp);};

            $w{chAttachToConsole} = Gtk3::CheckButton->new_with_label('Attach to console');
            $w{hbox1}->pack_start($w{chAttachToConsole}, 0, 1, 0);
            $w{chAttachToConsole}->set_tooltip_text('[/admin] : Attach to admin console of server (requires Windows Server 2003 or newer)');

            $w{chUseCompression} = Gtk3::CheckButton->new_with_label('Compression');
            $w{hbox1}->pack_start($w{chUseCompression}, 0, 1, 0);
            $w{chUseCompression}->set_tooltip_text('[+compression] : Enable compression of the RDP datastream');

            $w{chIgnoreCert} = Gtk3::CheckButton->new_with_label('Ignore verification of logon certificate');
            $w{hbox1}->pack_start($w{chIgnoreCert}, 0, 1, 0);
            $w{chIgnoreCert}->set_tooltip_text("/cert-ignore: ignore verification of logon certificate");

            $w{chFontSmooth} = Gtk3::CheckButton->new_with_label('Font Smooth');
            $w{hbox1}->pack_start($w{chFontSmooth}, 0, 1, 0);
            $w{chFontSmooth}->set_tooltip_text("+fonts: enable font smoothing");

            $w{chNoGrabKbd} = Gtk3::CheckButton->new_with_label('Do not grab keyboard');
            $w{hbox1}->pack_start($w{chNoGrabKbd}, 0, 1, 0);
            $w{chNoGrabKbd}->set_tooltip_text("-grab-keyboard: do not grab keyboard");

        $w{hbox3} = Gtk3::HBox->new(0, 5);
        $w{vbox}->pack_start($w{hbox3}, 0, 1, 5);

            $w{chNoAuth} = Gtk3::CheckButton->new_with_label('No Authentication');
            $w{hbox3}->pack_start($w{chNoAuth}, 0, 1, 0);
            $w{chNoAuth}->set_tooltip_text("-authentication: disable authentication");

            $w{chNoFastPath} = Gtk3::CheckButton->new_with_label('No Fast Path');
            $w{hbox3}->pack_start($w{chNoFastPath}, 0, 1, 0);
            $w{chNoFastPath}->set_tooltip_text("-fast-path: disable fast-path");

            $w{chRFX} = Gtk3::CheckButton->new_with_label('Enable RemoteFX');
            $w{hbox3}->pack_start($w{chRFX}, 0, 1, 0);
            $w{chRFX}->set_tooltip_text("/rfx: enable RemoteFX");

            $w{chNSCodec} = Gtk3::CheckButton->new_with_label('Enable NSCodec');
            $w{hbox3}->pack_start($w{chNSCodec}, 0, 1, 0);
            $w{chNSCodec}->set_tooltip_text("/nsc: enable NSCodec (experimental)");

            $w{chDynamicResolution} = Gtk3::CheckButton->new_with_label('Enable dynamic resolution');
            $w{hbox3}->pack_start($w{chDynamicResolution}, 0, 1, 0);
            $w{chDynamicResolution}->set_tooltip_text("/dynamic-resolution: Send resolution updates when the window is resized)");

        $w{hbox4} = Gtk3::HBox->new(0, 5);
        $w{vbox}->pack_start($w{hbox4}, 0, 1, 5);

            $w{chNoRDP} = Gtk3::CheckButton->new_with_label('Disable RDP encryption');
            $w{hbox4}->pack_start($w{chNoRDP}, 0, 1, 0);
            $w{chNoRDP}->set_tooltip_text("-sec-rdp: disable Standard RDP encryption");

            $w{chNoTLS} = Gtk3::CheckButton->new_with_label('Disable TLS encryption');
            $w{hbox4}->pack_start($w{chNoTLS}, 0, 1, 0);
            $w{chNoTLS}->set_tooltip_text("-sec-tls: disable TLS encryption");

            $w{chNoNLA} = Gtk3::CheckButton->new_with_label('Disable Network Level Authentication');
            $w{hbox4}->pack_start($w{chNoNLA}, 0, 1, 0);
            $w{chNoNLA}->set_tooltip_text("-sec-nla: disable network level authentication");

        $w{hboxss} = Gtk3::HBox->new(0, 5);
        $w{vbox}->pack_start($w{hboxss}, 0, 1, 5);

            $w{lblStartupShell} = Gtk3::Label->new('Startup shell: ');
            $w{hboxss}->pack_start($w{lblStartupShell}, 0, 1, 0);

            $w{entryStartupShell} = Gtk3::Entry->new;
            $w{entryStartupShell}->set_tooltip_text("[/shell:'startupshell command'] : start given startupshell/command instead of explorer");
            $w{hboxss}->pack_start($w{entryStartupShell}, 1, 1, 5);

        $w{hboxoo} = Gtk3::HBox->new(0, 5);
        $w{vbox}->pack_start($w{hboxoo}, 0, 1, 5);

            $w{lblOtherOptions} = Gtk3::Label->new('Other options: ');
            $w{hboxoo}->pack_start($w{lblOtherOptions}, 0, 1, 0);

            $w{entryOtherOptions} = Gtk3::Entry->new;
            $w{entryOtherOptions}->set_tooltip_text("Insert other options not implemented in Asbru (launch 'xfreerdp --help' to see them all)");
            $w{hboxoo}->pack_start($w{entryOtherOptions}, 1, 1, 5);

        $w{hbox2} = Gtk3::HBox->new(0, 5);
        $w{vbox}->pack_start($w{hbox2}, 0, 1, 5);

            $w{frGeometry} = Gtk3::Frame->new(' RDP Window size: ');
            $w{hbox2}->pack_start($w{frGeometry}, 1, 1, 0);
            $w{frGeometry}->set_tooltip_text('[/size] : Amount of screen to use');

                $w{hboxsize} = Gtk3::VBox->new(0, 5);
                $w{frGeometry}->add($w{hboxsize});

                    $w{hboxfsebpc} = Gtk3::HBox->new(0, 5);
                    $w{hboxsize}->pack_start($w{hboxfsebpc}, 1, 1, 0);

                    $w{chFullscreen} = Gtk3::RadioButton->new_with_label(undef, 'Fullscreen');
                    $w{hboxfsebpc}->pack_start($w{chFullscreen}, 1, 1, 0);
                    $w{chFullscreen}->set_tooltip_text('[/f] : Enable fullscreen mode (toggled at any time using Ctrl-Alt-Enter)');

                    $w{chEmbed} = Gtk3::RadioButton->new_with_label($w{chFullscreen}, 'Embed in TAB(*)');
                    $w{hboxfsebpc}->pack_start($w{chEmbed}, 1, 1, 0);
                    $w{chEmbed}->set_tooltip_text("[-X:xid] : Embed RDP window in an Asbru TAB\n*WARNING*: if embedded windows doesn't fit perfect install Perl module X11::GUITest");
                    $w{chEmbed}->set_sensitive(1);
                    $w{chEmbed}->set_active(0);

                    $w{hbox69} = Gtk3::HBox->new(0, 5);
                    $w{hboxfsebpc}->pack_start($w{hbox69}, 1, 1, 0);

                        $w{chWidthHeight} = Gtk3::RadioButton->new_with_label($w{chFullscreen}, 'Width x Height:');
                        $w{chWidthHeight}->set_tooltip_text('[/size:WIDTHxHEIGHT] : Define a fixed WIDTH x HEIGHT geometry window');
                        $w{hbox69}->pack_start($w{chWidthHeight}, 0, 1, 0);

                        $w{hboxWidthHeight} = Gtk3::HBox->new(0, 5);
                        $w{hbox69}->pack_start($w{hboxWidthHeight}, 0, 1, 0);

                            $w{spWidth} = Gtk3::SpinButton->new_with_range(1, 4096, 10);
                            $w{hboxWidthHeight}->pack_start($w{spWidth}, 0, 1, 0);
                            $w{spHeight} = Gtk3::SpinButton->new_with_range(1, 4096, 10);
                            $w{hboxWidthHeight}->pack_start($w{spHeight}, 0, 1, 0);
                            $w{hboxWidthHeight}->set_sensitive(0);

                    $w{hboxPercentage} = Gtk3::HBox->new(0, 5);
                    $w{hboxsize}->pack_start($w{hboxPercentage}, 0, 1, 0);

                        $w{chPercentage} = Gtk3::RadioButton->new_with_label($w{chFullscreen}, 'Screen percentage:');
                        $w{chPercentage}->set_tooltip_text('[/size:percentage%] : Amount of screen to use');
                        $w{chPercentage}->set_active(1);
                        $w{hboxPercentage}->pack_start($w{chPercentage}, 0, 1, 0);

                        $w{spGeometry} = Gtk3::HScale->new(Gtk3::Adjustment->new(90, 10, 100, 1.0, 1.0, 1.0) );
                        $w{hboxPercentage}->pack_start($w{spGeometry}, 1, 1, 0);

            $w{frKeyboard} = Gtk3::Frame->new('Keyboard layout:');
            $w{hbox2}->pack_start($w{frKeyboard}, 0, 1, 0);
            $w{frKeyboard}->set_tooltip_text('[/kbd] : Keyboard layout');

                $w{entryKeyboard} = Gtk3::Entry->new;
                $w{entryKeyboard}->set_tooltip_text("List keyboard layouts launching 'xfreerdp /kbd-list' (0x00000...)");
                $w{frKeyboard}->add($w{entryKeyboard});

        $w{hboxDomain} = Gtk3::HBox->new(0, 5);
        $w{vbox}->pack_start($w{hboxDomain}, 0, 1, 5);

            $w{hboxDomain}->pack_start(Gtk3::Label->new('Windows Domain: '), 0, 1, 0);
            $w{entryDomain} = Gtk3::Entry->new;
            $w{hboxDomain}->pack_start($w{entryDomain}, 1, 1, 0);

            $w{cbRedirClipboard} = Gtk3::CheckButton->new_with_label('Clipboard redirect');
            $w{hboxDomain}->pack_start($w{cbRedirClipboard}, 0, 1, 0);

            $w{cbRedirSound} = Gtk3::CheckButton->new_with_label('Sound redirect');
            $w{hboxDomain}->pack_start($w{cbRedirSound}, 0, 1, 0);

        $w{frameRedirDisk} = Gtk3::Frame->new(' Disk redirects: ');
        $w{vbox}->pack_start($w{frameRedirDisk}, 1, 1, 0);
        $w{frameRedirDisk}->set_tooltip_text('[/drive:<8_chars_sharename>:<path>] : Redirects a <path> to the share \\tsclient\<8_chars_sharename> on the server');

            $w{vbox_enesimo} = Gtk3::VBox->new(0, 0);
            $w{frameRedirDisk}->add($w{vbox_enesimo},);

                # Build 'add' button
                $w{btnadd} = Gtk3::Button->new_from_stock('gtk-add');
                $w{vbox_enesimo}->pack_start($w{btnadd}, 0, 1, 0);

                # Build a scrolled window
                $w{sw} = Gtk3::ScrolledWindow->new();
                $w{vbox_enesimo}->pack_start($w{sw}, 1, 1, 0);
                $w{sw}->set_policy('automatic', 'automatic');
                $w{sw}->set_shadow_type('none');

                    $w{vp} = Gtk3::Viewport->new();
                    $w{sw}->add($w{vp});
                    $w{vp}->set_shadow_type('GTK_SHADOW_NONE');

                        # Build and add the vbox that will contain the redirect widgets
                        $w{vbRedirect} = Gtk3::VBox->new(0, 0);
                        $w{vp}->add($w{vbRedirect});

    # Capture 'Full Screen' checkbox toggled state
    $w{chFullscreen}->signal_connect('toggled' => sub {$w{hboxWidthHeight}->set_sensitive($w{chWidthHeight}->get_active); $w{spGeometry}->set_sensitive(! $w{chFullscreen}->get_active);});
    $w{chPercentage}->signal_connect('toggled' => sub {$w{hboxWidthHeight}->set_sensitive($w{chWidthHeight}->get_active); $w{spGeometry}->set_sensitive(! $w{chFullscreen}->get_active);});
    $w{chWidthHeight}->signal_connect('toggled' => sub {$w{hboxWidthHeight}->set_sensitive($w{chWidthHeight}->get_active); $w{spGeometry}->set_sensitive(! $w{chFullscreen}->get_active);});

    $$self{gui} = \%w;

    $w{btnadd}->signal_connect('clicked', sub {
        $$self{cfg} = $self->get_cfg;
        my $opt_hash = _parseCfgToOptions($$self{cfg});
        push(@{$$opt_hash{redirDisk}}, {'redirDiskShare' => $ENV{'USER'}, 'redirDiskPath' => $ENV{'HOME'}});
        $$self{cfg} = _parseOptionsToCfg($opt_hash);
        $self->update($$self{cfg});
        return 1;
    });

    return 1;
}

sub _buildRedir {
    my $self = shift;
    my $hash = shift;

    my $redirDiskShare = $$hash{'redirDiskShare'}    // $ENV{'USER'};
    my $redirDiskPath = $$hash{'redirDiskPath'}    // $ENV{'HOME'};

    my @undo;
    my $undoing = 0;

    my %w;

    $w{position} = scalar @{$$self{listRedir}};

    # Make an HBox to contain local address, local port, remote address, remote port and delete
    $w{hbox} = Gtk3::HBox->new(0, 0);

        $w{hbox}->pack_start(Gtk3::Label->new('Share Name (8 chars max.!):'), 0, 1, 0);
        $w{entryRedirShare} = Gtk3::Entry->new;
        $w{hbox}->pack_start($w{entryRedirShare}, 0, 1, 0);
        $w{entryRedirShare}->set_text($redirDiskShare);

        $w{fcForwardPath} = Gtk3::FileChooserButton->new('Select a path to share', 'GTK_FILE_CHOOSER_ACTION_SELECT_FOLDER');
        $redirDiskPath =~ s/(.+)/file:\/\/$1/g;
        $w{fcForwardPath}->set_uri($redirDiskPath);
        $w{hbox}->pack_start($w{fcForwardPath}, 1, 1, 0);

        # Build delete button
        $w{btn} = Gtk3::Button->new_from_stock('gtk-delete');
        $w{hbox}->pack_start($w{btn}, 0, 1, 0);

    # Add built control to main container
    $$self{gui}{vbRedirect}->pack_start($w{hbox}, 0, 1, 0);
    $$self{gui}{vbRedirect}->show_all;

    $$self{listRedir}[$w{position}] = \%w;

    # Setup some callbacks

    # Asign a callback for deleting entry
    $w{btn}->signal_connect('clicked' => sub
    {
        $$self{cfg} = $self->get_cfg();
        splice(@{$$self{listRedir}}, $w{position}, 1);
        $$self{cfg} = $self->get_cfg();
        $self->update($$self{cfg});
        return 1;
    });

    return %w;
}

# END: Private functions definitions
###################################################################

1;
