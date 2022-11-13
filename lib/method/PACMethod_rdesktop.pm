package PACMethod_rdesktop;

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

my %RDP_VERSION = (4 => 0, 5 => 1);
my %BPP = (8 => 0, 15 => 1, 16 => 2, 24 => 3, 32 => 4);
my %SOUND = ('local' => 0, 'off' => 1, 'remote' => 2, 'local:alsa' => 3, 'local:pulseaudio' =>4);

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

    $$self{gui}{cbRDPVersion}->set_active($RDP_VERSION{$$options{RDPVersion} // 5});
    $$self{gui}{cbBPP}->set_active($BPP{$$options{bpp} // 24});
    $$self{gui}{chClipboard}->set_active($$options{clipboard} // 1);
    $$self{gui}{chAttachToConsole}->set_active($$options{attachToConsole});
    $$self{gui}{chBitmapCaching}->set_active($$options{bitmapCaching});
    $$self{gui}{chUseCompression}->set_active($$options{useCompression});
    $$self{gui}{chNoGrabKbd}->set_active($$options{noGrabKbd} // 0);
    $$self{gui}{chFullscreen}->set_active($$options{fullScreen});
    $$self{gui}{chEmbed}->set_active($$options{embed});
    $$self{gui}{chWidthHeight}->set_active($$options{wh});
    $$self{gui}{spWidth}->set_value($$options{width} // 640);
    $$self{gui}{spHeight}->set_value($$options{height} // 480);
    $$self{gui}{hboxWidthHeight}->set_sensitive($$options{wh});
    $$self{gui}{entryKeyboard}->set_text($$options{keyboardLocale});
    $$self{gui}{cbRedirSound}->set_active($SOUND{$$options{redirSound} // 'off'});
    $$self{gui}{entryDomain}->set_text($$options{domain} // '');
    $$self{gui}{cbScard}->set_active($$options{scard} // 0);
    $$self{gui}{cbEnableSeamless}->set_active($$options{seamless} // 0);
    $$self{gui}{entryStartupShell}->set_text($$options{startupshell} // '');
    $$self{gui}{entryOtherOptions}->set_text($$options{otherOptions} // '');

    # Destroy previuos widgets
    $$self{gui}{vbRedirect}->foreach(sub {$_[0]->destroy();});

    # Empty parent's forward ports widgets' list
    $$self{listRedir} = [];

    # Now, add the -new?- local forward widgets
    foreach my $hash (@{$$options{redirDisk}}) {$self->_buildRedir($hash);}

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

    $options{RDPVersion} = $$self{gui}{cbRDPVersion}->get_active_text;
    $options{bpp} = $$self{gui}{cbBPP}->get_active_text;
    $options{clipboard} = $$self{gui}{chClipboard}->get_active;
    $options{attachToConsole} = $$self{gui}{chAttachToConsole}->get_active;
    $options{bitmapCaching} = $$self{gui}{chBitmapCaching}->get_active;
    $options{useCompression} = $$self{gui}{chUseCompression}->get_active;
    $options{noGrabKbd} = $$self{gui}{chNoGrabKbd}->get_active;
    $options{fullScreen} = $$self{gui}{chFullscreen}->get_active;
    $options{width} = $$self{gui}{spWidth}->get_chars(0, -1);
    $options{height} = $$self{gui}{spHeight}->get_chars(0, -1);
    $options{wh} = $$self{gui}{chWidthHeight}->get_active;
    $options{embed} = ! ($$self{gui}{chFullscreen}->get_active || $$self{gui}{chWidthHeight}->get_active);
    $options{keyboardLocale} = $$self{gui}{entryKeyboard}->get_chars(0, -1);
    $options{redirSound} = $$self{gui}{cbRedirSound}->get_active_text;
    $options{domain} = $$self{gui}{entryDomain}->get_chars(0, -1);
    $options{scard} = $$self{gui}{cbScard}->get_active;
    $options{seamless} = $$self{gui}{cbEnableSeamless}->get_active;
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
    $hash{RDPVersion} = 5;
    $hash{bpp} = 24;
    $hash{clipboard} = 1;
    $hash{attachToConsole} = 0;
    $hash{bitmapCaching} = 0;
    $hash{useCompression} = 0;
    $hash{noGrabKbd} = 0;
    $hash{fullScreen} = 0;
    $hash{scard} = 0;
    $hash{embed} = 1;
    $hash{wh} = 0;
    $hash{width} = 640;
    $hash{height} = 480;
    $hash{keyboardLocale} = '';
    $hash{redirDiskShare} = '';
    $hash{redirDiskPath} = $ENV{'HOME'};
    $hash{redirSound} = 'off';
    $hash{domain} = '';
    $hash{seamless} = 0;
    $hash{startupshell} = '';
    $hash{otherOptions} = '';

    my @opts = ($cmd_line =~ /-\w?\s?[^-]+/g);
    foreach my $opt (@opts) {
        next unless $opt ne '';
        $opt =~ s/\s+$//go;

        if ($opt =~ /^-(4|5)$/go)                     {$hash{RDPVersion} = $1;}
        elsif ($opt =~ /^-a\s+(8|15|16|24|32)$/go)        {$hash{bpp} = $1;}
        elsif ($opt eq '-0')                      {$hash{attachToConsole} = 1;}
        elsif ($opt eq '-P')                      {$hash{bitmapCaching} = 1;}
        elsif ($opt eq '-z')                      {$hash{useCompression} = 1;}
        elsif ($opt eq '-A')                      {$hash{seamless} = 1;}
        elsif ($opt eq '-K')                      {$hash{noGrabKbd} = 1;}
        elsif ($opt =~ /^-s\s+(.+)$/go)               {$hash{startupshell} = $1;}
        elsif ($opt eq '-f')                      {$hash{fullScreen} = 1; $hash{wh} = 0; $hash{'embed'} = 0;}
        elsif ($opt =~ /^-g\s+(\d+)x(\d+)$/go)            {$hash{width} = $1; $hash{height} = $2; $hash{wh} = 1; $hash{'embed'} = 0;}
        elsif ($opt =~ /^-k\s+(.+)$/go)               {$hash{keyboardLocale} = $1;}
        elsif ($opt =~ /^-r\s+sound:(.+)$/go)         {$hash{redirSound} = $1;}
        elsif ($opt =~ /^-r\s+scard$/go)              {$hash{scard} = 1;}
        elsif ($opt =~ /^-r\s+clipboard:(.+)$/go)     {$hash{clipboard} = 1;}
        elsif ($opt =~ /^-d\s+(.+)$/go)               {$hash{domain} = $1;}
        elsif ($opt =~ /^-r\s+disk:(.+)=\"(.+)\"$/go)
        {
            my %redir;
            $redir{redirDiskShare} = $1;
            $redir{redirDiskPath} = $2;
            push(@{$hash{redirDisk}}, \%redir);
        }
        else {$hash{otherOptions} .= ' ' . $opt . ' ';}
    }

    return \%hash;
}

sub _parseOptionsToCfg {
    my $hash = shift;

    my $txt = '';

    $txt .= ' -' . $$hash{RDPVersion};
    $txt .= ' -a ' . $$hash{bpp};
    $txt .= ' -0' if $$hash{attachToConsole};
    $txt .= ' -P' if $$hash{bitmapCaching};
    $txt .= ' -z' if $$hash{useCompression};
    $txt .= ' -f' if $$hash{fullScreen};
    $txt .= ' -A' if $$hash{seamless};
    $txt .= ' -K' if $$hash{noGrabKbd};
    $txt .= ' -s ' . $$hash{startupshell} if $$hash{startupshell} ne '';
    if ($$hash{wh}) {
        $txt .= ' -g ' . $$hash{width} . 'x' . $$hash{height};
    }
    $txt .= ' -k ' . $$hash{keyboardLocale} if $$hash{keyboardLocale} ne '';
    $txt .= ' -r sound:' . $$hash{redirSound};
    $txt .= ' -r scard' if $$hash{scard};
    $txt .= ' -r clipboard:PRIMARYCLIPBOARD' if $$hash{clipboard};
    $txt .= " -d $$hash{domain}" if $$hash{domain} ne '';
    foreach my $redir (@{$$hash{redirDisk}}) {$txt .= " -r disk:$$redir{redirDiskShare}=\"$$redir{redirDiskPath}\"";}

    $txt .= ' ' . $$hash{otherOptions} if $$hash{otherOptions} ne '';

    return $txt;
}

sub embed {
    my $self = shift;
    return ! ($$self{gui}{chFullscreen}->get_active || $$self{gui}{chWidthHeight}->get_active);
}

sub _buildGUI {
    my $self = shift;

    my $container = $self->{container};
    my $cfg = $self->{cfg};

    my %w;

    $w{vbox} = $container;

        $w{hbox1} = Gtk3::HBox->new(0, 5);
        $w{vbox}->pack_start($w{hbox1}, 0, 1, 5);

            $w{frRDPVersion} = Gtk3::Frame->new('RDP Version:');
            $w{hbox1}->pack_start($w{frRDPVersion}, 1, 1, 0);
            $w{frRDPVersion}->set_shadow_type('GTK_SHADOW_NONE');
            $w{frRDPVersion}->set_tooltip_text('-(4|5) : Use RDP v4 or v5 (default)');

                $w{cbRDPVersion} = Gtk3::ComboBoxText->new;
                $w{frRDPVersion}->add($w{cbRDPVersion});
                foreach my $rdp_version (4, 5) {$w{cbRDPVersion}->append_text($rdp_version);};

            $w{frBPP} = Gtk3::Frame->new('BPP:');
            $w{hbox1}->pack_start($w{frBPP}, 1, 1, 0);
            $w{frBPP}->set_shadow_type('GTK_SHADOW_NONE');
            $w{frBPP}->set_tooltip_text('[-a] : Sets the colour depth for the connection (8, 15, 16, 24 or 32)');

                $w{cbBPP} = Gtk3::ComboBoxText->new;
                $w{frBPP}->add($w{cbBPP});
                foreach my $bpp (8, 15, 16, 24, 32) {$w{cbBPP}->append_text($bpp);};

            $w{vboxup} = Gtk3::VBox->new(0, 0);
            $w{hbox1}->pack_start($w{vboxup}, 0, 1, 5);

                $w{hboxup} = Gtk3::HBox->new(0, 0);
                $w{vboxup}->pack_start($w{hboxup}, 1, 1, 0);

                    $w{chAttachToConsole} = Gtk3::CheckButton->new_with_label('Attach to console');
                    $w{hboxup}->pack_start($w{chAttachToConsole}, 1, 1, 0);
                    $w{chAttachToConsole}->set_tooltip_text('[-0] : Attach to console of server (requires Windows Server 2003 or newer)');

                    $w{chBitmapCaching} = Gtk3::CheckButton->new_with_label('Bitmap Cache');
                    $w{hboxup}->pack_start($w{chBitmapCaching}, 1, 1, 0);
                    $w{chBitmapCaching}->set_tooltip_text('[-P] : Enable caching of bitmaps to disk (persistent bitmap caching)');

                    $w{chUseCompression} = Gtk3::CheckButton->new_with_label('Compression');
                    $w{hboxup}->pack_start($w{chUseCompression}, 1, 1, 0);
                    $w{chUseCompression}->set_tooltip_text('[-z] : Enable compression of the RDP datastream');

                    $w{cbScard} = Gtk3::CheckButton->new_with_label('Use SmartCard');
                    $w{hboxup}->pack_start($w{cbScard}, 0, 1, 0);
                    $w{cbScard}->set_tooltip_text('[-r scard] : Enable SmartCard usage');

                $w{hboxdown} = Gtk3::HBox->new(0, 0);
                $w{vboxup}->pack_start($w{hboxdown}, 1, 1, 0);

                    $w{chClipboard} = Gtk3::CheckButton->new_with_label('Clipboard forwarding');
                    $w{chClipboard}->set_tooltip_text('[-r clipboard:PRIMARYCLIPBOARD] : Enable clipboard forwarding');
                    $w{hboxdown}->pack_start($w{chClipboard}, 0, 1, 0);

                    $w{cbEnableSeamless} = Gtk3::CheckButton->new_with_label('Enable SeamlessRDP ');
                    $w{cbEnableSeamless}->set_tooltip_text('[-A] : Enable SeamlessRDP');
                    $w{hboxdown}->pack_start($w{cbEnableSeamless}, 0, 1, 0);

                    $w{chNoGrabKbd} = Gtk3::CheckButton->new_with_label('Keep WM key bindings');
                    $w{chNoGrabKbd}->set_tooltip_text("[-K] : keep window manager key bindings");
                    $w{hboxdown}->pack_start($w{chNoGrabKbd}, 0, 1, 0);



        $w{hboxss} = Gtk3::HBox->new(0, 5);
        $w{vbox}->pack_start($w{hboxss}, 0, 1, 5);

            $w{lblStartupShell} = Gtk3::Label->new('Startup shell: ');
            $w{hboxss}->pack_start($w{lblStartupShell}, 0, 1, 0);

            $w{entryStartupShell} = Gtk3::Entry->new;
            $w{entryStartupShell}->set_tooltip_text("[-s 'startupshell command'] : start given startupshell/command instead of explorer");
            $w{hboxss}->pack_start($w{entryStartupShell}, 1, 1, 5);

        $w{hboxoo} = Gtk3::HBox->new(0, 5);
        $w{vbox}->pack_start($w{hboxoo}, 0, 1, 5);

            $w{lblOtherOptions} = Gtk3::Label->new('Other options: ');
            $w{hboxoo}->pack_start($w{lblOtherOptions}, 0, 1, 0);

            $w{entryOtherOptions} = Gtk3::Entry->new;
            $w{entryOtherOptions}->set_tooltip_text("Insert other options not implemented in Asbru (launch 'rdesktop --help' to see them all)");
            $w{hboxoo}->pack_start($w{entryOtherOptions}, 1, 1, 5);

        $w{hbox2} = Gtk3::HBox->new(0, 5);
        $w{vbox}->pack_start($w{hbox2}, 0, 1, 5);

            $w{frGeometry} = Gtk3::Frame->new(' RDP Window size: ');
            $w{hbox2}->pack_start($w{frGeometry}, 1, 1, 0);
            $w{frGeometry}->set_tooltip_text('[-g] : Amount of screen to use');

                $w{hboxsize} = Gtk3::VBox->new(0, 5);
                $w{frGeometry}->add($w{hboxsize});

                    $w{hboxfsebpc} = Gtk3::HBox->new(0, 5);
                    $w{hboxsize}->pack_start($w{hboxfsebpc}, 1, 1, 0);

                    $w{chFullscreen} = Gtk3::RadioButton->new_with_label(undef, 'Fullscreen');
                    $w{hboxfsebpc}->pack_start($w{chFullscreen}, 1, 1, 0);
                    $w{chFullscreen}->set_tooltip_text('[-f] : Enable fullscreen mode (toggled at any time using Ctrl-Alt-Enter)');

                    $w{chEmbed} = Gtk3::RadioButton->new_with_label($w{chFullscreen}, 'Embed in TAB');
                    $w{hboxfsebpc}->pack_start($w{chEmbed}, 1, 1, 0);
                    $w{chEmbed}->set_tooltip_text('Embed terminal window in Asbru TAB, using Asbru\'s GUI size');

                    $w{hbox69} = Gtk3::HBox->new(0, 5);
                    $w{hboxfsebpc}->pack_start($w{hbox69}, 1, 1, 0);

                        $w{chWidthHeight} = Gtk3::RadioButton->new_with_label($w{chFullscreen}, 'Width x Height:');
                        $w{chWidthHeight}->set_tooltip_text('[-g WIDTHxHEIGHT] : Define a fixed WIDTH x HEIGHT geometry window');
                        $w{hbox69}->pack_start($w{chWidthHeight}, 0, 1, 0);

                        $w{hboxWidthHeight} = Gtk3::HBox->new(0, 5);
                        $w{hbox69}->pack_start($w{hboxWidthHeight}, 0, 1, 0);

                            $w{spWidth} = Gtk3::SpinButton->new_with_range(1, 4096, 10);
                            $w{hboxWidthHeight}->pack_start($w{spWidth}, 0, 1, 0);
                            $w{spHeight} = Gtk3::SpinButton->new_with_range(1, 4096, 10);
                            $w{hboxWidthHeight}->pack_start($w{spHeight}, 0, 1, 0);
                            $w{hboxWidthHeight}->set_sensitive(0);

            $w{frKeyboard} = Gtk3::Frame->new('Keyboard layout:');
            $w{hbox2}->pack_start($w{frKeyboard}, 0, 1, 0);
            $w{frKeyboard}->set_tooltip_text('[-k] : Keyboard layout');

                $w{entryKeyboard} = Gtk3::Entry->new;
                $w{frKeyboard}->add($w{entryKeyboard});

        $w{hboxDomain} = Gtk3::HBox->new(0, 5);
        $w{vbox}->pack_start($w{hboxDomain}, 0, 1, 5);

            $w{hboxDomain}->pack_start(Gtk3::Label->new('Windows Domain: '), 0, 1, 0);
            $w{entryDomain} = Gtk3::Entry->new;
            $w{hboxDomain}->pack_start($w{entryDomain}, 1, 1, 0);

            $w{hboxDomain}->pack_start(Gtk3::Label->new('Sound redirect: '), 0, 1, 0);
            $w{cbRedirSound} = Gtk3::ComboBoxText->new;
            $w{hboxDomain}->pack_start($w{cbRedirSound}, 1, 1, 0);
            foreach my $sound ('local', 'off', 'remote', 'local:alsa', 'local:pulseaudio') {$w{cbRedirSound}->append_text($sound);};

        $w{frameRedirDisk} = Gtk3::Frame->new(' Disk redirects: ');
        $w{vbox}->pack_start($w{frameRedirDisk}, 1, 1, 0);
        $w{frameRedirDisk}->set_tooltip_text('[-r disk:<8_chars_sharename>=<path>] : Redirects a <path> to the share \\tsclient\<8_chars_sharename> on the server');

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
    $w{chFullscreen}->signal_connect('toggled' => sub {$w{hboxWidthHeight}->set_sensitive($w{chWidthHeight}->get_active);});
    $w{chEmbed}->signal_connect('toggled' => sub {$w{hboxWidthHeight}->set_sensitive($w{chWidthHeight}->get_active);});
    $w{chWidthHeight}->signal_connect('toggled' => sub {$w{hboxWidthHeight}->set_sensitive($w{chWidthHeight}->get_active);});

    $$self{gui} = \%w;

    $w{btnadd}->signal_connect('clicked', sub {
        $$self{cfg} = $self->get_cfg;
        my $opt_hash = _parseCfgToOptions($$self{cfg});
        push(@{$$opt_hash{redirDisk}}, {'redirDiskShare' => $ENV{'USER'}, 'redirDiskPath' => $ENV{'HOME'}});
        $$self{cfg} = _parseOptionsToCfg($opt_hash);
        $$self{cfg_array} = $self->get_cfg_array();
        $self->update($$self{cfg}, $$self{cfg_array});
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
        $$self{cfg_array} = $self->get_cfg_array();
        $self->update($$self{cfg}, $$self{cfg_array});
        return 1;
    });

    return %w;
}

# END: Private functions definitions
###################################################################

1;
