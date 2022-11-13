package PACMethod_sftp;

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

use PACUtils;

# GTK
use Gtk3 '-init';

# END: Import Modules
###################################################################

###################################################################
# Define GLOBAL CLASS variables

my %SSH_VERSION = (1 => 0, 'any' => 1);
my $RES_DIR = $RealBin . '/res';
my %SSH_ADV_OPTS = (
    'A' => ['AddressFamily'],
    'B' => ['BatchMode', 'BindAddress'],
    'C' => ['CanonicalDomains', 'CanonicalizeFallbackLocal', 'CanonicalizeHostname', 'CanonicalizeMaxDots', 'CanonicalizePermittedCNAMEs', 'ChallengeResponseAuthentication', 'CheckHostIP', 'Cipher', 'Ciphers', 'ClearAllForwardings', 'Compression', 'CompressionLevel', 'ConnectionAttempts', 'ConnectTimeout', 'ControlMaster', 'ControlPath', 'ControlPersist'],
    'D' => ['DynamicForward'],
    'E' => ['EscapeChar', 'ExitOnForwardFailure'],
    'F' => ['ForwardAgent', 'ForwardX11', 'ForwardX11Timeout', 'ForwardX11Trusted'],
    'G' => ['GatewayPorts', 'GlobalKnownHostsFile', 'GSSAPIAuthentication', 'GSSAPIDelegateCredentials'],
    'H' => ['HashKnownHosts', 'Host', 'HostbasedAuthentication', 'HostKeyAlgorithms', 'HostKeyAlias', 'HostName'],
    'I' => ['IdentityAgent', 'IdentityFile', 'IdentitiesOnly', 'IPQoS'],
    'K' => ['KbdInteractiveAuthentication', 'KbdInteractiveDevices', 'KexAlgorithms'],
    'L' => ['LocalCommand', 'LocalForward', 'LogLevel'],
    'M' => ['MACs', 'Match'],
    'N' => ['NoHostAuthenticationForLocalhost', 'NumberOfPasswordPrompts'],
    'P' => ['PasswordAuthentication', 'PermitLocalCommand', 'PKCS11Provider', 'Port', 'PreferredAuthentications', 'Protocol', 'ProxyCommand', 'ProxyUseFdpass', 'PubkeyAuthentication'],
    'R' => ['RekeyLimit', 'RemoteForward', 'RequestTTY', 'RhostsRSAAuthentication', 'RSAAuthentication'],
    'S' => ['SendEnv', 'ServerAliveInterval', 'ServerAliveCountMax', 'StrictHostKeyChecking'],
    'T' => ['TCPKeepAlive', 'Tunnel', 'TunnelDevice'],
    'U' => ['UsePrivilegedPort', 'User', 'UserKnownHostsFile'],
    'V' => ['VerifyHostKeyDNS', 'VisualHostKey'],
    'X' => ['XAuthLocation']
);

# END: Define GLOBAL CLASS variables
###################################################################

###################################################################
# START: Public class methods

sub new
{
    my $class = shift;
    my $self = {};

    $self->{container} = shift;

    $self->{cfg} = undef;
    $self->{cfg_array} = undef;
    $self->{gui} = undef;
    $self->{frame} = {};
    $self->{listAdvOpt} = [];

    _buildGUI($self);

    bless($self, $class);
    return $self;
}

sub update
{
    my $self = shift;
    my $cfg = shift;
    my $cfg_array = shift;

    defined $cfg and $$self{cfg} = $cfg;
    defined $cfg_array and $$self{cfg_array} = $cfg_array;

    my $options = _parseCfgToOptions($$self{cfg});

    $$self{gui}{cbSSHVersion}->set_active($SSH_VERSION{$$options{sshVersion} // 'any'});
    $$self{gui}{chUseCompression}->set_active($$options{useCompression});

    $$self{gui}{vbAdvOpt}->foreach(sub {$_[0]->destroy;});
    # Now, add the -new?- dynamic socks widgets
    foreach my $hash (sort {$$a{option} cmp $$b{option}} @{$$options{advancedOption}}) {$self->_buildAdvOpt($hash);}
    $$self{gui}{lblAdvOpt}->set_markup('Advanced Options (<b>' . (scalar(@{$$self{listAdvOpt}}) ) . '</b>)');

    return 1;
}

sub get_cfg_array
{
    my $self = shift;

    my %options_array;

    return \%options_array;
}

sub get_cfg
{
    my $self = shift;

    my %options;

    $options{sshVersion} = $$self{gui}{cbSSHVersion}->get_active_text;
    $options{useCompression} = $$self{gui}{chUseCompression}->get_active;

    $options{advancedOption} = ();
    foreach my $w (@{$$self{listAdvOpt}}) {
        my %hash;
        $hash{'option'} = $$w{entryAdvOptOption}->get_chars(0, -1) || '';
        $hash{'value'} = $$w{entryAdvOptValue}->get_chars(0, -1) || '';
        next unless $hash{'option'} && $hash{'value'};
        push(@{$options{advancedOption}}, \%hash);
    }


    return _parseOptionsToCfg(\%options);
}

# END: Public class methods
###################################################################

###################################################################
# START: Private functions definitions

sub _parseCfgToOptions
{
    my $cmd_line = shift;

    my %hash;
    $hash{sshVersion} = 'any';
    $hash{useCompression} = 0;
    @{$hash{advancedOption}} = ();

    my @opts = split(/\s+-o /, $cmd_line);
    foreach my $opt (@opts)
    {
        $opt =~ s/^ -//;
        next unless $opt ne '';
        $opt =~ s/\s+$//go;

        if ($opt =~ /^([1|2]$)/go) {
            $hash{sshVersion} = $1;
        }
        if ($opt eq 'C') {
            $hash{useCompression} = 1;
        }
        while ($opt =~ /\"(.+?)\"$/go) {
            my %opts;
            my $tmpopt = $1;
            $tmpopt =~ /\s*(.+?)\s*=\s*(.+)\s*/go;
            ($opts{option}, $opts{value}) = ($1, $2);
            push(@{$hash{advancedOption}}, \%opts);
        }
    }

    return \%hash;
}

sub _parseOptionsToCfg
{
    my $hash = shift;

    my $txt = '';

    $txt .= ' -1' unless $$hash{sshVersion} eq 'any';
    $txt .= ' -C' if $$hash{useCompression} ;
    foreach my $opt (@{$$hash{advancedOption}}) {
        $txt .= " -o \"$$opt{option}=$$opt{value}\"";
    }

    return $txt;
}

sub embed
{
    my $self = shift;
    return 0;
}

sub _buildGUI
{
    my $self = shift;

    my $container = $self->{container};
    my $cfg = $self->{cfg};

    my %w;

    $w{vbox} = $container;

    $w{hbox1} = Gtk3::HBox->new(0, 5);
    $w{vbox}->pack_start($w{hbox1}, 0, 1, 5);

    $w{frSSHVersion} = Gtk3::Frame->new('SSH Version:');
    $w{hbox1}->pack_start($w{frSSHVersion}, 0, 1, 0);
    $w{frSSHVersion}->set_shadow_type('GTK_SHADOW_NONE');
    $w{frSSHVersion}->set_tooltip_text('-(1|any) : Use SSH v1 or let negotiate any of them');

    $w{cbSSHVersion} = Gtk3::ComboBoxText->new;
    $w{frSSHVersion}->add($w{cbSSHVersion});
    foreach my $ssh_version (sort {$a cmp $b} keys %SSH_VERSION) {$w{cbSSHVersion}->append_text($ssh_version);};

    $w{chUseCompression} = Gtk3::CheckButton->new_with_label('Use Compression');
    $w{hbox1}->pack_start($w{chUseCompression}, 1, 1, 0);
    $w{chUseCompression}->set_tooltip_text('[-C] : Use or not compression');

    $w{vbox}->pack_start(Gtk3::HSeparator->new, 0, 1, 5);

    $w{vbox}->pack_start(Gtk3::Label->new('Advanced Options:'), 0, 1, 0);

    $w{vboxAdvOpt} = Gtk3::VBox->new(0, 0);
    $w{vbox}->pack_start($w{vboxAdvOpt}, 1, 1, 5);
    $w{lblAdvOpt} = Gtk3::Label->new('Advanced Options');
    $w{vboxAdvOpt}->set_tooltip_text('[-o "ssh_option=value"]');
    $w{vboxAdvOpt}->set_border_width(5);

    # Build 'add' button
    $w{btnaddAdvOpt} = Gtk3::Button->new_from_stock('gtk-add');
    $w{vboxAdvOpt}->pack_start($w{btnaddAdvOpt}, 0, 1, 0);

    # Build a scrolled window
    $w{swAdvOpt} = Gtk3::ScrolledWindow->new;
    $w{vboxAdvOpt}->pack_start($w{swAdvOpt}, 1, 1, 0);
    $w{swAdvOpt}->set_policy('automatic', 'automatic');
    $w{swAdvOpt}->set_shadow_type('none');

    $w{vpAdvOpt} = Gtk3::Viewport->new;
    $w{swAdvOpt}->add($w{vpAdvOpt});
    $w{vpAdvOpt}->set_shadow_type('GTK_SHADOW_NONE');

    # Build and add the vbox that will contain the advanced options widgets
    $w{vbAdvOpt} = Gtk3::VBox->new(0, 0);
    $w{vpAdvOpt}->add($w{vbAdvOpt});

    $w{vbox}->pack_start(Gtk3::HSeparator->new, 0, 1, 5);

    $$self{gui} = \%w;

    $w{btnaddAdvOpt}->signal_connect('clicked', sub {
        $$self{cfg} = $self->get_cfg();
        my $opt_hash = _parseCfgToOptions($$self{cfg});
        push(@{$$opt_hash{advancedOption}}, {'option' => 'SFTP option (right-click here to show list)', 'value' => 'value'});
        $$self{cfg} = _parseOptionsToCfg($opt_hash);
        $$self{cfg_array} = $self->get_cfg_array();
        $self->update($$self{cfg}, $$self{cfg_array});
        return 1;
    });

    return 1;
}

sub _buildAdvOpt
{
    my $self = shift;
    my $hash = shift;

    my $option = $$hash{'option'}    // '';
    my $value = $$hash{'value'}    // '';

    my @undo;
    my $undoing = 0;

    my %w;

    $w{position} = scalar @{$$self{listAdvOpt}};

    # Make an HBox to contain option, value and delete
    $w{hbox} = Gtk3::HBox->new(0, 0);

    $w{frAdvOptOption} = Gtk3::Frame->new('Option:');
    $w{hbox}->pack_start($w{frAdvOptOption}, 1, 1, 0);
    $w{frAdvOptOption}->set_shadow_type('GTK_SHADOW_NONE');

    $w{entryAdvOptOption} = Gtk3::Entry->new;
    $w{frAdvOptOption}->add($w{entryAdvOptOption});
    $w{entryAdvOptOption}->set_size_request(30, 20);
    $w{entryAdvOptOption}->set_text($option);

    $w{frAdvOptValue} = Gtk3::Frame->new('Value:');
    $w{hbox}->pack_start($w{frAdvOptValue}, 1, 1, 0);
    $w{frAdvOptValue}->set_shadow_type('GTK_SHADOW_NONE');

    $w{entryAdvOptValue} = Gtk3::Entry->new;
    $w{frAdvOptValue}->add($w{entryAdvOptValue});
    $w{entryAdvOptValue}->set_size_request(30, 20);
    $w{entryAdvOptValue}->set_text($value);

    # Build delete button
    $w{btn} = Gtk3::Button->new_from_stock('gtk-delete');
    $w{hbox}->pack_start($w{btn}, 0, 1, 0);

    # Add built control to main container
    $$self{gui}{vbAdvOpt}->pack_start($w{hbox}, 0, 1, 0);
    $$self{gui}{vbAdvOpt}->show_all;

    $$self{listAdvOpt}[$w{position}] = \%w;

    # Setup some callbacks

    # Asign a callback for deleting entry
    $w{btn}->signal_connect('clicked' => sub {
        $$self{cfg} = $self->get_cfg();
        splice(@{$$self{listAdvOpt}}, $w{position}, 1);
        $$self{cfg} = $self->get_cfg();
        $$self{cfg_array} = $self->get_cfg_array();
        $self->update($$self{cfg}, $$self{cfg_array});
        return 1;
    });


    # Prepare 'undo' for this entry
    $w{entryAdvOptOption}->signal_connect('delete_text' => sub {! $undoing and push(@undo, $w{entryAdvOptOption}->get_chars(0, -1) ); return $_[1], $_[3];});
    $w{entryAdvOptOption}->signal_connect('insert_text' => sub {! $undoing and push(@undo, $w{entryAdvOptOption}->get_chars(0, -1) ); return $_[1], $_[3];});
    $w{entryAdvOptOption}->signal_connect('key_press_event' => sub {
        my ($widget, $event) = @_;
        my $keyval = '' . ($event->keyval);
        my $state = '' . ($event->state);
        # Check if <Ctrl>z is pushed
        if (($event->state >= 'control-mask') && (chr($keyval) eq 'z') && (scalar @undo) ) {
            $undoing = 1;
            $w{entryAdvOptOption}->set_text(pop(@undo) );
            $undoing = 0;
            return 1;
        }
        return 0;
    });

    # Prepare 'undo' for this entry
    $w{entryAdvOptValue}->signal_connect('delete_text' => sub {! $undoing and push(@undo, $w{entryAdvOptValue}->get_chars(0, -1) ); return $_[1], $_[3];});
    $w{entryAdvOptValue}->signal_connect('insert_text' => sub {! $undoing and push(@undo, $w{entryAdvOptValue}->get_chars(0, -1) ); return $_[1], $_[3];});
    $w{entryAdvOptValue}->signal_connect('key_press_event' => sub {
        my ($widget, $event) = @_;
        my $keyval = '' . ($event->keyval);
        my $state = '' . ($event->state);
        # Check if <Ctrl>z is pushed
        if (($event->state >= 'control-mask') && (chr($keyval) eq 'z') && (scalar @undo) ) {
            $undoing = 1;
            $w{entryAdvOptValue}->set_text(pop(@undo) );
            $undoing = 0;
            return 1;
        }
        return 0;
    });

    # Capture right mouse click to show custom context menu with SSH advanced options
    $w{entryAdvOptOption}->signal_connect('button_press_event' => sub {
        my ($widget, $event) = @_;
        return 0 unless $event->button eq 3;
        my @menu_items;
        foreach my $let (sort {$a cmp $b} keys %SSH_ADV_OPTS) {
            my @letmenu;
            foreach my $opt (sort {$a cmp $b} @{$SSH_ADV_OPTS{$let}}) {
                push(@letmenu, {label => $opt, code => sub {$w{entryAdvOptOption}->set_text($opt);} });
            }
            push(@menu_items, {label => $let, submenu => \@letmenu});
        }
        _wPopUpMenu(\@menu_items, $event);

        return 1;
    });

    return %w;
}

# END: Private functions definitions
###################################################################

1;
