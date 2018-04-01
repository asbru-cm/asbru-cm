package PACUtils;

###############################################################################
# This file is part of Ásbrú Connection Manager
#
# Copyright (C) 2017-2018 Ásbrú Connection Manager team (https://asbru-cm.net)
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

use FindBin qw ( $RealBin $Bin $Script );
use POSIX qw ( strftime );
use Storable qw ( freeze thaw dclone );
use Crypt::CBC;
use Socket;
use Socket6;
use Sys::Hostname;
use Net::ARP;
use Net::Ping;
use YAML;
use OSSP::uuid;
use Encode;
use KeePass;
use DynaLoader; # Required for PACTerminal and PACShell modules

# GTK2
use Gtk2 '-init';

# Module's functions/variables to export
use vars qw( $VERSION @ISA @EXPORT @EXPORT_OK );
require Exporter;
@ISA        = qw( Exporter );
@EXPORT     = qw(
	_
	__
	_screenshot
	_scale
	_pixBufFromFile
	_getMethods
	_registerPACIcons
	_sortTreeData
	_menuFavouriteConnections
	_menuAvailableConnections
	_menuClusterConnections
	_wEnterValue
	_wAddRenameNode
	_wPopUpMenu
	_wConfirm
	_wMessage
	_wProgress
	_wYesNoCancel
	_wSetPACPassword
	_wPrePostEntry
	_wExecEntry
	_cfgCheckMigrationV3
	_cfgSanityCheck
	_updateSSHToIPv6
	_cipherCFG
	_decipherCFG
	_substCFG
	_subst
	_wakeOnLan
	_deleteOldestSessionLog
	_replaceBadChars
	_removeEscapeSeqs
	_purgeUnusedOrMissingScreenshots
	_purgeUnusedScreenshots
	_purgeMissingScreenshots
	_splash
	_getXWindowsList
	_getREADME
	_checkREADME
	_showUpdate
	_getEncodings
	_findKP
	_makeDesktopFile
); # Functions/varibles to export

@EXPORT_OK  = qw();

# END: Import Modules
###################################################################

###################################################################
# Define GLOBAL CLASS variables

our $APPNAME		= decode( 'UTF-8', 'Ásbrú Connection Manager' );
our $APPVERSION		= '5.0.1';
our $DEBUG_LEVEL	= 1;
our $ARCH			= '';
my $ARCH_TMP		= `/bin/uname -m 2>&1`;
if		( $ARCH_TMP =~ /x86_64/gio )	{ $ARCH = 64; }
elsif	( $ARCH_TMP =~ /ppc64/gio )		{ $ARCH = 'PPC64'; }
elsif	( $ARCH_TMP =~ /armv7l/gio )	{ $ARCH = 'ARMV7L'; }
elsif	( $ARCH_TMP =~ /arm/gio )		{ $ARCH = 'ARM'; }
else									{ $ARCH = 32; }
my $RES_DIR			= $RealBin . '/res';
my $SPLASH_IMG		= $RES_DIR . '/asbru-logo-400.png';
my $CFG_DIR			= $ENV{'HOME'} . '/.config/pac';
my $CFG_FILE		= $CFG_DIR . '/pac.yml';
my $R_CFG_FILE		= $PACMain::R_CFG_FILE;
my $CIPHER			= Crypt::CBC -> new( -key => 'Àsbrù Connection Manager (https://www.asbru-cm.net/)', -cipher => 'Blowfish', -salt => '12345678' ) or die "ERROR: $!";

my %WINDOWSPLASH;
my %WINDOWPROGRESS;
my $WIDGET_POPUP;

our @DONATORS_LIST	= (
	'Angelo Maria Lambiasi',
	'TWEB Inc',
	'Jeff Bakst',
	'Sebastian Treu',
	"Brian's Consultant Services",
	'Cheah CH',
	'Joseph Whipple',
	'Felix Brack',
	'Kalmykov Alexander',
	'Paul Verreth',
	'Iftimie Catalin Panaite',
	'Andre Geißler',
	'Arend de Boer',
	'Taylor Finklea',
	'Egbert Gerber',
	'Гусаров Андрей',
	'Carlos Bragatto',
	'Nicklas Börjesson',
	'Peter Taylor',
	'Javier Martin Garcia-Asenjo',
	'Helmut Kleinhans',
	'Richard Kozel',
	'Timo Büttner',
	'Max Maskevich',
	'1one - 18mind',
	'von Karman Institute',
	'Julian Thomas Bourne',
	'iPERFEX',
	'Joaquín Ferrero San Pedro',
	'Yan Lebedev ',
	'Florian Jerusalem',
	'Brendan Bell',
	'Microflow Software SA De CB',
	'Giuseppe Massimiani',
	'Рукавков Никита',
	'Miguel Rodriguez Vazquez',
	'Voronkov Vladislav',
	'Murathan Bostanci',
	'Adrian King',
	'Sebastian Treu',
	'Voronkov Vladislav',
	'Dejan Korent',
	'Diego Vasquez',
	'Christoph Korn',
	'Victor Demonchy',
	'Ilir Pruthi',
	'Robson Ramaldes',
	'justine cattiaux',
	'Ralph Hübner',
	'Kalin Ivanov',
	'Nikolay Penev',
	'panagiotis palias',
	'Lomakova Anastasia',
	'Andre M Saunite',
	'Jason Cyr',
	'Andreas Diesner',
	'Liam Ward',
	'Andrei Padshyvalau',
	'Gaston Martini',
	'Host Revenda Ltda',
	'Otto Schakenbos',
	'Fernando Moreira',
	'Don Jacobs'
);
our @PACDESKTOP		= (
'[Desktop Entry]',
'Name=PAC',
'Comment=Perl Auto Connector (auto start)',
'Terminal=false',
'Icon=pac',
'Type=Application',
'Exec=/usr/bin/asbru --no-splash',
'StartupNotify=false',
'Name[en_US]=PAC',
'Comment[en_US]=Perl Auto Connector (auto start)',
'Categories=Applications;Network;',
'X-GNOME-Autostart-enabled=true',
);

# Gnome2 - VTE (here be dragons...)
eval q {
	unshift( @INC, $RealBin . '/lib/ex/vte' . $PACUtils::ARCH );
	
	package Gnome2::Vte;
	
	our @ISA = qw(DynaLoader);
	
	sub import {
		my $self = shift();
		$self -> VERSION(@_);
	}
	sub dl_load_flags	{ 0x01 }
	
	eval { Gnome2::Vte -> bootstrap; };
	! $@ and return 1;
};
die "ERROR: Could not load Gnome2::Vte Perl module from $RealBin/lib/ex/vte${PACUtils::ARCH} directories! ($@)" if $@;

# END: Define GLOBAL CLASS variables
###################################################################

######################################################
# START: Private functions definitions

sub _ { return shift -> {_GLADE} -> get_widget( shift ); };

sub __ {
	my $str = shift // '';
	
	$str =~ s/\&/&amp;/go;
	$str =~ s/\'/&apos;/go;
	$str =~ s/\"/&quot;/go;
	$str =~ s/</&lt;/go;
	$str =~ s/>/&gt;/go;
	
	return $str;
};

sub _findKP {
	my $list	= shift;
	my $where	= shift // 'title';
	my $what	= shift // qr/.*/;
	
	my @kpx = ();
	foreach my $hash ( @{ $list } ) {
		if ( ref( $what ) eq 'Regexp' )	{ next unless $$hash{$where} =~ /^$what$/ ; }
		else							{ next unless $$hash{$where} eq $what; }
		push( @kpx, {
			title		=> $$hash{title},
			url			=> $$hash{url},
			username	=> $$hash{username},
			password	=> $$hash{password},
			created		=> $$hash{created},
			comment		=> $$hash{comment}
		} );
	}
	return wantarray ? @kpx : scalar( @kpx );
}

sub _splash {
	my $show	= shift;
	my $txt		= shift // "<b>Starting $APPNAME (v$APPVERSION)...</b>";
	my $partial	= shift // 0;
	my $total	= shift // 1;
	
	return 1 if $PACMain::_NO_SPLASH;
	
	if ( ! defined $WINDOWSPLASH{_GUI} ) {
		$WINDOWSPLASH{_GUI} = Gtk2::Window -> new;
		$WINDOWSPLASH{_GUI} -> set_type_hint( 'splashscreen' );
		$WINDOWSPLASH{_GUI} -> set_position('center');
		$WINDOWSPLASH{_GUI} -> set_keep_above( 1 );

		$WINDOWSPLASH{_VBOX} = Gtk2::VBox -> new( 0, 0 );
		$WINDOWSPLASH{_GUI} -> add( $WINDOWSPLASH{_VBOX} );

		$WINDOWSPLASH{_IMG} = Gtk2::Image -> new_from_file( $SPLASH_IMG );
		$WINDOWSPLASH{_VBOX} -> pack_start( $WINDOWSPLASH{_IMG}, 1, 1, 0 );

		$WINDOWSPLASH{_LBL} = Gtk2::ProgressBar -> new;
		$WINDOWSPLASH{_VBOX} -> pack_start( $WINDOWSPLASH{_LBL}, 1, 1, 5 );
	}
	
	$WINDOWSPLASH{_LBL} -> set_text( $txt );
	$WINDOWSPLASH{_LBL} -> set_fraction( $partial / $total );
	
	if ( $show ) {
		$WINDOWSPLASH{_GUI} -> show_all;
		$WINDOWSPLASH{_GUI} -> present;
		Gtk2 -> main_iteration while Gtk2 -> events_pending;
	} else {
		$WINDOWSPLASH{_GUI} -> hide_all;
		$WINDOWSPLASH{_GUI} -> destroy;
	}
	
	return 1;
}

sub _screenshot {
	my $widget	= shift;
	my $file	= shift;
	
	my $gdkpixbuf = Gtk2::Gdk::Pixbuf -> new( 'rgb', 0, 8, $widget -> allocation -> width, $widget -> allocation -> height );
	$gdkpixbuf -> get_from_drawable( $widget -> window, undef, $widget -> allocation -> x, $widget -> allocation -> y, 0, 0, $widget -> allocation -> width, $widget -> allocation -> height );
	
	return defined $file ? $gdkpixbuf -> save( $file, 'jpeg' ) : $gdkpixbuf;
}

sub _scale {
	my $file	= shift;
	my $w		= shift;
	my $h		= shift;
	my $ratio	= shift // '';
	
	my $gdkpixbuf;
	eval { $gdkpixbuf = ref( $file ) ? $file : Gtk2::Gdk::Pixbuf -> new_from_file( $file ) };
	return 0 if $@;
	
	if ( $ratio && ( ( $gdkpixbuf -> get_width > $w ) || ( $gdkpixbuf -> get_height > $h ) ) ) {
		if ( $gdkpixbuf -> get_width > $gdkpixbuf -> get_height ) {
			$h = int( ( $w * $gdkpixbuf -> get_height ) / $gdkpixbuf -> get_width );
		} elsif ( $gdkpixbuf -> get_height >= $gdkpixbuf -> get_width) {
			$w = int( ( $h * $gdkpixbuf -> get_width ) / $gdkpixbuf -> get_height );
		}
	}
	
	return $gdkpixbuf -> scale_simple( $w, $h, 'GDK_INTERP_HYPER' );
}

sub _pixBufFromFile {
	my $file = shift;
	
	my $gdkpixbuf;
	eval { $gdkpixbuf = Gtk2::Gdk::Pixbuf -> new_from_file( $file ) };
	
	return 0 if $@;
	return $gdkpixbuf;
}

sub _getMethods {
	my $self = shift;
	
	my %methods;
	
	`which rdesktop 1>/dev/null 2>&1`; my $rdesktop = $?;
	$methods{ 'RDP (rdesktop)' } = {
		'installed' => sub { return ( ! $rdesktop ) ? 1 : "No 'rdesktop' binary found.\nTo use this option, please, install :'rdesktop'"; },
		'checkCFG' => sub {
			my $cfg		= shift;
			
			my @faults;
			
			push( @faults, 'IP/Hostname' )	if ! _( $self, 'entryIP' ) -> get_chars( 0, -1 );
			push( @faults, 'Port' )			if ! _( $self, 'entryPort' ) -> get_chars( 0, -1 );
			if ( ( _( $self, 'rbCfgAuthUserPass' ) -> get_active ) && ( ! _( $self, 'cbInferUserPassKPX' ) -> get_active ) ) {
				push( @faults, 'User (User/Password authentication method selected)' )		if ! _( $self, 'entryUser' ) -> get_chars( 0, -1 );
				push( @faults, 'Password (User/Password authentication method selected)' )	if ! _( $self, 'entryPassword' ) -> get_chars( 0, -1 );
			}
			
			return @faults;
		},
		'updateGUI'	=> sub {
			my $cfg = shift;
			
			my $method	= 'RDP (rdesktop)';
			my $pixbuf	= $$self{_METHODS}{ $method }{'icon'};
			
			_( $self, 'imageMethod' )			-> set_from_pixbuf( $pixbuf );
			_( $self, 'imageConnOptions' )		-> set_from_pixbuf( $pixbuf );
			#_( $self, 'vboxVarious' )			-> set_sensitive( 1 );
			_( $self, 'framePort' )				-> set_sensitive( 1 );
			_( $self, 'entryPort' )				-> set_value( $method eq $$cfg{method} ? $$cfg{port} : 3389 );
			_( $self, 'labelIP' )				-> set_text( 'Host: ' );
			_( $self, 'entryIP' )				-> set_property( 'tooltip-markup', 'IP or Hostname of the machine to connect to' );
			_( $self, 'entryIP' )				-> set_text( $$cfg{ip} // '' );
			_( $self, 'entryUser' )				-> set_sensitive( 1 );
			_( $self, 'entryUser' )				-> set_text( $$cfg{user} // '' );
			_( $self, 'entryPassword' )			-> set_text( $$cfg{pass} // '' );
			_( $self, 'cbCfgAuthFallback' )		-> set_sensitive( 0 );
			_( $self, 'alignAuthMethod' )		-> set_sensitive( 1 );
			_( $self, 'alignUserPass' )			-> set_sensitive( 1 );
			_( $self, 'rbCfgAuthUserPass' )		-> set_active( $$cfg{'auth type'} eq 'userpass' );
			_( $self, 'framePublicKey' )		-> set_sensitive( 0 );
			_( $self, 'alignManual' )			-> set_sensitive( 1 );
			_( $self, 'rbCfgAuthManual' )		-> set_active( $$cfg{'auth type'} eq 'manual' );
			_( $self, 'entryPassphrase' )		-> set_text( '' );
			_( $self, 'fileCfgPublicKey' )		-> unselect_all;
			_( $self, 'frameExpect' )			-> set_sensitive( 0 );
			_( $self, 'frameRemoteMacros' )		-> set_sensitive( 0 );
			_( $self, 'frameLocalMacros' )		-> set_sensitive( 0 );
			_( $self, 'frameVariables' )		-> set_sensitive( 0 );
			_( $self, 'frameTerminalOptions' )	-> set_sensitive( 1 );
			_( $self, 'labelConnOptions' )		-> set_markup( "'<b>$method</b>'" );
			_( $self, 'labelExpect' )			-> set_sensitive( 0 );
			_( $self, 'labelRemoteMacros' )		-> set_sensitive( 0 );
			_( $self, 'labelLocalMacros' )		-> set_sensitive( 0 );
			_( $self, 'labelVariables' )		-> set_sensitive( 0 );
			_( $self, 'labelTerminalOptions' )	-> set_sensitive( 1 );
			_( $self, 'labelCmdLineOptions' )	-> set_markup( " '<b>$method</b>' command line options: " );
			_( $self, 'cbAutossh' )				-> set_sensitive( 0 );
			_( $self, 'cbAutossh' )				-> set_active( 0 );
		},
		'icon' => Gtk2::Gdk::Pixbuf -> new_from_file_at_scale( $RES_DIR . '/pac_method_rdesktop.jpg', 16, 16, 0 ),
		'escape' => [ "\cc" ]
	};
	
	`which xfreerdp 1>/dev/null 2>&1`; my $xfreerdp = $?;
	$methods{ 'RDP (xfreerdp)' } = {
		'installed' => sub { return ( ! $xfreerdp ) ? 1 : "No 'xfreerdp' binary found.\nTo use this option, please, install:\n'freerdp-x11'"; },
		'checkCFG' => sub {
			my $cfg		= shift;
			
			my @faults;
			
			push( @faults, 'IP/Hostname' )	if ! _( $self, 'entryIP' ) -> get_chars( 0, -1 );
			push( @faults, 'Port' )			if ! _( $self, 'entryPort' ) -> get_chars( 0, -1 );
			if ( ( _( $self, 'rbCfgAuthUserPass' ) -> get_active ) && ( ! _( $self, 'cbInferUserPassKPX' ) -> get_active ) ) {
				push( @faults, 'User (User/Password authentication method selected)' )		if ! _( $self, 'entryUser' ) -> get_chars( 0, -1 );
				push( @faults, 'Password (User/Password authentication method selected)' )	if ! _( $self, 'entryPassword' ) -> get_chars( 0, -1 );
			}
			
			return @faults;
		},
		'updateGUI'	=> sub {
			my $cfg = shift;
			
			my $method	= 'RDP (xfreerdp)';
			my $pixbuf	= $$self{_METHODS}{ $method }{'icon'};
			
			_( $self, 'imageMethod' )			-> set_from_pixbuf( $pixbuf );
			_( $self, 'imageConnOptions' )		-> set_from_pixbuf( $pixbuf );
			#_( $self, 'vboxVarious' )			-> set_sensitive( 1 );
			_( $self, 'framePort' )				-> set_sensitive( 1 );
			_( $self, 'entryPort' )				-> set_value( $method eq $$cfg{method} ? $$cfg{port} : 3389 );
			_( $self, 'labelIP' )				-> set_text( 'Host: ' );
			_( $self, 'entryIP' )				-> set_property( 'tooltip-markup', 'IP or Hostname of the machine to connect to' );
			_( $self, 'entryIP' )				-> set_text( $$cfg{ip} // '' );
			_( $self, 'entryUser' )				-> set_sensitive( 1 );
			_( $self, 'entryUser' )				-> set_text( $$cfg{user} // '' );
			_( $self, 'entryPassword' )			-> set_text( $$cfg{pass} // '' );
			_( $self, 'cbCfgAuthFallback' )		-> set_sensitive( 0 );
			_( $self, 'alignAuthMethod' )		-> set_sensitive( 1 );
			_( $self, 'alignUserPass' )			-> set_sensitive( 1 );
			_( $self, 'rbCfgAuthUserPass' )		-> set_active( $$cfg{'auth type'} eq 'userpass' );
			_( $self, 'framePublicKey' )		-> set_sensitive( 0 );
			_( $self, 'alignManual' )			-> set_sensitive( 1 );
			_( $self, 'rbCfgAuthManual' )		-> set_active( $$cfg{'auth type'} eq 'manual' );
			_( $self, 'entryPassphrase' )		-> set_text( '' );
			_( $self, 'fileCfgPublicKey' )		-> unselect_all;
			_( $self, 'frameExpect' )			-> set_sensitive( 0 );
			_( $self, 'frameRemoteMacros' )		-> set_sensitive( 0 );
			_( $self, 'frameLocalMacros' )		-> set_sensitive( 0 );
			_( $self, 'frameVariables' )		-> set_sensitive( 0 );
			_( $self, 'frameTerminalOptions' )	-> set_sensitive( 1 );
			_( $self, 'labelConnOptions' )		-> set_markup( "'<b>$method</b>'" );
			_( $self, 'labelExpect' )			-> set_sensitive( 0 );
			_( $self, 'labelRemoteMacros' )		-> set_sensitive( 0 );
			_( $self, 'labelLocalMacros' )		-> set_sensitive( 0 );
			_( $self, 'labelVariables' )		-> set_sensitive( 0 );
			_( $self, 'labelTerminalOptions' )	-> set_sensitive( 1 );
			_( $self, 'labelCmdLineOptions' )	-> set_markup( " '<b>$method</b>' command line options: " );
			_( $self, 'cbAutossh' )				-> set_sensitive( 0 );
			_( $self, 'cbAutossh' )				-> set_active( 0 );
		},
		'icon' => Gtk2::Gdk::Pixbuf -> new_from_file_at_scale( $RES_DIR . '/pac_method_rdesktop.jpg', 16, 16, 0 ),
		'escape' => [ "\cc" ]
	};
	
	`which vncviewer 1>/dev/null 2>&1`;				my $xtightvncviewer = $?;
	`vncviewer --help 2>&1 | /bin/grep TigerVNC`;	my $tigervnc = $?;
	$methods{ 'VNC' } = {
		'installed' => sub { return ! $xtightvncviewer || ! $tigervnc ? 1 : "No 'vncviewer' binary found.\nTo use this option, please, install any of:\n'xtightvncviewer' or 'tigervnc'\n'tigervnc' is preferred, since it allows embedding it's window into PAC"; },
		'checkCFG' => sub {
			
			my $cfg = shift;
			
			my @faults;
			
			push( @faults, 'IP/Hostname' )	if ! _( $self, 'entryIP' ) -> get_chars( 0, -1 );
			push( @faults, 'Port' )			if ! _( $self, 'entryPort' ) -> get_chars( 0, -1 );
			push( @faults, "Password (User/Password authentication method selected)" ) if ( ( _( $self, 'rbCfgAuthUserPass' ) -> get_active ) && ( _( $self, 'entryPassword' ) -> get_chars( 0, -1 ) eq '' ) && ( ! _( $self, 'cbInferUserPassKPX' ) -> get_active ) );
			
			return @faults;
		},
		'updateGUI'	=> sub {
			my $cfg		= shift;
			
			my $method	= 'VNC';
			my $pixbuf	= $$self{_METHODS}{ $method }{'icon'};
			
			_( $self, 'imageMethod' )			-> set_from_pixbuf( $pixbuf );
			_( $self, 'imageConnOptions' )		-> set_from_pixbuf( $pixbuf );
			#_( $self, 'vboxVarious' )			-> set_sensitive( 1 );
			_( $self, 'framePort' )				-> set_sensitive( 1 );
			_( $self, 'entryPort' )				-> set_value( $method eq $$cfg{method} ? $$cfg{port} : 5900 );
			_( $self, 'labelIP' )				-> set_text( 'Host: ' );
			_( $self, 'entryIP' )				-> set_property( 'tooltip-markup', 'IP or Hostname of the machine to connect to' );
			_( $self, 'entryIP' )				-> set_text( $$cfg{ip} );
			_( $self, 'alignAuthMethod' )		-> set_sensitive( 1 );
			_( $self, 'entryUser' )				-> set_sensitive( 1 );
			_( $self, 'entryUser' )				-> set_text( $$cfg{user} );
			_( $self, 'entryPassword' )			-> set_text( $$cfg{pass} );
			_( $self, 'cbCfgAuthFallback' )		-> set_sensitive( 0 );
			_( $self, 'alignUserPass' )			-> set_sensitive( 1 );
			_( $self, 'rbCfgAuthUserPass' )		-> set_active( $$cfg{'auth type'} eq 'userpass' );
			_( $self, 'framePublicKey' )		-> set_sensitive( 0 );
			_( $self, 'alignManual' )			-> set_sensitive( 1 );
			_( $self, 'rbCfgAuthManual' )		-> set_active( $$cfg{'auth type'} eq 'manual' );
			_( $self, 'entryPassphrase' )		-> set_text( '' );
			_( $self, 'fileCfgPublicKey' )		-> unselect_all;
			_( $self, 'frameExpect' )			-> set_sensitive( 0 );
			_( $self, 'frameRemoteMacros' )		-> set_sensitive( 0 );
			_( $self, 'frameLocalMacros' )		-> set_sensitive( 0 );
			_( $self, 'frameVariables' )		-> set_sensitive( 0 );
			_( $self, 'frameTerminalOptions' )	-> set_sensitive( 0 );
			_( $self, 'labelConnOptions' )		-> set_markup( "'<b>$method</b>'" );
			_( $self, 'labelExpect' )			-> set_sensitive( 0 );
			_( $self, 'labelRemoteMacros' )		-> set_sensitive( 0 );
			_( $self, 'labelLocalMacros' )		-> set_sensitive( 0 );
			_( $self, 'labelVariables' )		-> set_sensitive( 0 );
			_( $self, 'labelTerminalOptions' )	-> set_sensitive( 0 );
			_( $self, 'labelCmdLineOptions' )	-> set_markup( " '<b>$method</b>' command line options: " );
			_( $self, 'cbAutossh' )				-> set_sensitive( 0 );
			_( $self, 'cbAutossh' )				-> set_active( 0 );
		},
		'icon' => Gtk2::Gdk::Pixbuf -> new_from_file_at_scale( $RES_DIR . '/pac_method_vncviewer.jpg', 16, 16, 0 ),
		'escape' => [ "\cc" ]
	};
	
	`which cu 1>/dev/null 2>&1`; my $cu = $?;
	$methods{ 'Serial (cu)' } = {
		'installed' => sub { return ! $cu ? 1 : "No 'cu' binary found.\nTo use this option, please, install 'cu'."; },
		'checkCFG' => sub {
			my $cfg = shift;
			
			my @faults;
			return @faults;
		},
		'updateGUI'	=> sub {
			my $cfg		= shift;
			
			my $method	= 'Serial (cu)';
			my $pixbuf	= $$self{_METHODS}{ $method }{'icon'};
			
			_( $self, 'imageMethod' )			-> set_from_pixbuf( $pixbuf );
			_( $self, 'imageConnOptions' )		-> set_from_pixbuf( $pixbuf );
			#_( $self, 'vboxVarious' )			-> set_sensitive( 1 );
			_( $self, 'framePort' )				-> set_sensitive( 0 );
			_( $self, 'entryPort' )				-> set_value( 0 );
			_( $self, 'labelIP' )				-> set_text( 'System / Phone / "dir": ' );
			_( $self, 'entryIP' )				-> set_property( 'tooltip-markup', "Enter string of kind: system | phone | 'dir' or\nleave empty and use the 'Line' option under the 'cu options' tab on the left" );
			_( $self, 'entryIP' )				-> set_text( $$cfg{ip} // '' );
			_( $self, 'entryUser' )				-> set_text( '' );
			_( $self, 'entryPassword' )			-> set_text( '' );
			_( $self, 'cbCfgAuthFallback' )		-> set_sensitive( 0 );
			_( $self, 'labelConnOptions' )		-> set_markup( "'<b>$method</b>'" );
			_( $self, 'labelExpect' )			-> set_sensitive( 1 );
			_( $self, 'labelRemoteMacros' )		-> set_sensitive( 1 );
			_( $self, 'labelLocalMacros' )		-> set_sensitive( 1 );
			_( $self, 'labelVariables' )		-> set_sensitive( 1 );
			_( $self, 'labelTerminalOptions' )	-> set_sensitive( 1 );
			_( $self, 'entryUser' )				-> set_sensitive( 0 );
			_( $self, 'entryPassphrase' )		-> set_text( '' );
			_( $self, 'fileCfgPublicKey' )		-> unselect_all;
			_( $self, 'rbCfgAuthManual' )		-> set_active( 1 );
			_( $self, 'alignAuthMethod' )		-> set_sensitive( 0 );
			_( $self, 'frameExpect' )			-> set_sensitive( 1 );
			_( $self, 'frameRemoteMacros' )		-> set_sensitive( 1 );
			_( $self, 'frameLocalMacros' )		-> set_sensitive( 1 );
			_( $self, 'frameVariables' )		-> set_sensitive( 1 );
			_( $self, 'frameTerminalOptions' )	-> set_sensitive( 1 );
			_( $self, 'labelCmdLineOptions' )	-> set_markup( " '<b>$method</b>' command line options: " );
			_( $self, 'cbAutossh' )				-> set_sensitive( 0 );
			_( $self, 'cbAutossh' )				-> set_active( 0 );
		},
		'icon' => Gtk2::Gdk::Pixbuf -> new_from_file_at_scale( $RES_DIR . '/pac_method_cu.jpg', 16, 16, 0 ),
		'escape' => [ '~.' ]
	};
	
	`which remote-tty 1>/dev/null 2>&1`; my $remote_tty = $?;
	$methods{ 'Serial (remote-tty)' } = {
		'installed' => sub { return ! $remote_tty ? 1 : "No 'remote-tty' binary found.\nTo use this option, please, install 'remote-tty'."; },
		'checkCFG' => sub {
			my $cfg = shift;
			
			my @faults;
			
			push( @faults, 'TTY Socket' ) if ! _( $self, 'entryIP' ) -> get_chars( 0, -1 );
			if ( _( $self, 'rbCfgAuthUserPass' ) -> get_active ) {
				push( @faults, 'User (User/Password authentication method selected)' ) if ! _( $self, 'entryUser' ) -> get_chars( 0, -1 );
				push( @faults, 'Password (User/Password authentication method selected)' ) if ! _( $self, 'entryPassword' ) -> get_chars( 0, -1 );
			}
			
			return @faults;
		},
		'updateGUI'	=> sub {
			my $cfg		= shift;
			
			my $method	= 'Serial (remote-tty)';
			my $pixbuf	= $$self{_METHODS}{ $method }{'icon'};
			
			_( $self, 'imageMethod' )			-> set_from_pixbuf( $pixbuf );
			_( $self, 'imageConnOptions' )		-> set_from_pixbuf( $pixbuf );
			#_( $self, 'vboxVarious' )			-> set_sensitive( 1 );
			_( $self, 'framePort' )				-> set_sensitive( 0 );
			_( $self, 'entryPort' )				-> set_value( 0 );
			_( $self, 'labelIP' )				-> set_text( 'TTY Socket: ' );
			_( $self, 'entryIP' )				-> set_property( 'tooltip-markup', 'Enter a TTY / Serial socket (eg: /dev/tty*)' );
			_( $self, 'entryIP' )				-> set_text( $$cfg{ip} );
			_( $self, 'entryUser' )				-> set_text( $$cfg{user} );
			_( $self, 'entryPassword' )			-> set_text( $$cfg{pass} );
			_( $self, 'cbCfgAuthFallback' )		-> set_sensitive( 0 );
			_( $self, 'labelConnOptions' )		-> set_markup( "'<b>$method</b>'" );
			_( $self, 'labelExpect' )			-> set_sensitive( 1 );
			_( $self, 'labelRemoteMacros' )		-> set_sensitive( 1 );
			_( $self, 'labelLocalMacros' )		-> set_sensitive( 1 );
			_( $self, 'labelVariables' )		-> set_sensitive( 1 );
			_( $self, 'labelTerminalOptions' )	-> set_sensitive( 1 );
			_( $self, 'alignAuthMethod' )		-> set_sensitive( 1 );
			_( $self, 'entryUser' )				-> set_sensitive( 1 );
			_( $self, 'alignUserPass' )			-> set_sensitive( 1 );
			_( $self, 'rbCfgAuthUserPass' )		-> set_active( $$cfg{'auth type'} eq 'userpass' );
			_( $self, 'framePublicKey' )		-> set_sensitive( 0 );
			_( $self, 'alignManual' )			-> set_sensitive( 1 );
			_( $self, 'rbCfgAuthManual' )		-> set_active( $$cfg{'auth type'} eq 'manual' );
			_( $self, 'entryPassphrase' )		-> set_text( '' );
			_( $self, 'fileCfgPublicKey' )		-> unselect_all;
			_( $self, 'frameExpect' )			-> set_sensitive( 1 );
			_( $self, 'frameRemoteMacros' )		-> set_sensitive( 1 );
			_( $self, 'frameLocalMacros' )		-> set_sensitive( 1 );
			_( $self, 'frameVariables' )		-> set_sensitive( 1 );
			_( $self, 'frameTerminalOptions' )	-> set_sensitive( 1 );
			_( $self, 'labelCmdLineOptions' )	-> set_markup( " '<b>$method</b>' command line options: " );
			_( $self, 'cbAutossh' )				-> set_sensitive( 0 );
			_( $self, 'cbAutossh' )				-> set_active( 0 );
		},
		'icon' => Gtk2::Gdk::Pixbuf -> new_from_file_at_scale( $RES_DIR . '/pac_method_remote-tty.jpg', 16, 16, 0 )
	};
	
	`which c3270 1>/dev/null 2>&1`; my $c3270 = $?;
	$methods{ 'IBM 3270/5250' } = {
		'installed' => sub { return ! $c3270 ? 1 : "No 'c3270' binary found.\nTo use this option, please, install 'c3270' or 'x3270-text'."; },
		'checkCFG' => sub {
			my $cfg = shift;
			
			my @faults;
			push( @faults, 'IP/Hostname' ) if ! _( $self, 'entryIP' ) -> get_chars( 0, -1 );
            
			return @faults;
		},
		'updateGUI'	 => sub {
			my $cfg		= shift;
			
			my $method	= 'IBM 3270/5250';
			my $pixbuf	= $$self{_METHODS}{ $method }{'icon'};
            
			_( $self, 'imageMethod' )			-> set_from_pixbuf( $pixbuf );
			_( $self, 'imageConnOptions' )		-> set_from_pixbuf( $pixbuf );
			#_( $self, 'vboxVarious' )			-> set_sensitive( 1 );
			_( $self, 'framePort' )				-> set_sensitive( 1 );
			_( $self, 'entryPort' )				-> set_value( 23 );
			_( $self, 'labelIP' )				-> set_text( 'Host: ' );
			_( $self, 'entryIP' )				-> set_property( 'tooltip-markup', 'IP or Hostname of the host to connect to' );
			_( $self, 'entryUser' )				-> set_text( '' );
			_( $self, 'entryPassword' )			-> set_text( '' );
			_( $self, 'cbCfgAuthFallback' )		-> set_sensitive( 0 );
			_( $self, 'alignAuthMethod' )		-> set_sensitive( 0 );
			_( $self, 'rbCfgAuthManual' )		-> set_active( 1 );
			_( $self, 'entryUser' )				-> set_sensitive( 0 );
			_( $self, 'entryPassphrase' )		-> set_text( '' );
			_( $self, 'fileCfgPublicKey' )		-> unselect_all;
			_( $self, 'labelConnOptions' )		-> set_markup( "'<b>$method</b>'" );
			_( $self, 'labelExpect' )			-> set_sensitive( 1 );
			_( $self, 'labelRemoteMacros' )		-> set_sensitive( 1 );
			_( $self, 'labelLocalMacros' )		-> set_sensitive( 1 );
			_( $self, 'labelVariables' )		-> set_sensitive( 1 );
			_( $self, 'labelTerminalOptions' )	-> set_sensitive( 1 );
			_( $self, 'labelCmdLineOptions' )	-> set_markup( " '<b>$method</b>' command line options: " );
			_( $self, 'frameExpect' )			-> set_sensitive( 1 );
			_( $self, 'frameRemoteMacros' )		-> set_sensitive( 1 );
			_( $self, 'frameLocalMacros' )		-> set_sensitive( 1 );
			_( $self, 'frameVariables' )		-> set_sensitive( 1 );
			_( $self, 'frameTerminalOptions' )	-> set_sensitive( 1 );
			_( $self, 'cbAutossh' )				-> set_sensitive( 0 );
			_( $self, 'cbAutossh' )				-> set_active( 0 );
		},
		'icon' => Gtk2::Gdk::Pixbuf -> new_from_file_at_scale( $RES_DIR . '/pac_method_3270.jpg', 16, 16, 0 )
	};
	
	`which autossh 1>/dev/null 2>&1`; my $autossh = ! $?;
	$methods{ 'SSH' } = {
		'installed' => sub { return 1; },
		'checkCFG' => sub {
			my $cfg = shift;
			
			my @faults;
			
			push( @faults, 'IP/Hostname' ) if ! _( $self, 'entryIP' ) -> get_chars( 0, -1 );
			push( @faults, 'Port' ) if ! _( $self, 'entryPort' ) -> get_chars( 0, -1 );
			if ( ( _( $self, 'rbCfgAuthUserPass' ) -> get_active ) && ( ! _( $self, 'cbInferUserPassKPX' ) -> get_active ) ) {
				push( @faults, 'User (User/Password authentication method selected)' ) if ! _( $self, 'entryUser' ) -> get_chars( 0, -1 );
			} elsif ( _( $self, 'rbCfgAuthPublicKey' ) -> get_active ) {
				push( @faults, 'Public Key File (Public Key authentication method selected)' ) if ! _( $self, 'fileCfgPublicKey' ) -> get_filename;
			}
			
			return @faults;
		},
		'updateGUI'	=> sub {
			my $cfg		= shift;
			
			my $method	= 'SSH';
			my $pixbuf	= $$self{_METHODS}{ $method }{'icon'};
			
			_( $self, 'imageMethod' )			-> set_from_pixbuf( $pixbuf );
			_( $self, 'imageConnOptions' )		-> set_from_pixbuf( $pixbuf );
			#_( $self, 'vboxVarious' )			-> set_sensitive( 1 );
			_( $self, 'framePort' )				-> set_sensitive( 1 );
			_( $self, 'entryPort' )				-> set_value( $method eq $$cfg{method} ? $$cfg{port} : 22 );
			_( $self, 'labelIP' )				-> set_text( 'Host: ' );
			_( $self, 'entryIP' )				-> set_property( 'tooltip-markup', 'IP or Hostname of the machine to connect to' );
			_( $self, 'entryUser' )				-> set_text( $$cfg{user} // '' );
			_( $self, 'entryPassword' )			-> set_text( $$cfg{pass} // '' );
			_( $self, 'cbCfgAuthFallback' )		-> set_sensitive( 1 );
			_( $self, 'labelConnOptions' )		-> set_markup( "'<b>$method</b>'" );
			_( $self, 'labelExpect' )			-> set_sensitive( 1 );
			_( $self, 'labelRemoteMacros' )		-> set_sensitive( 1 );
			_( $self, 'labelLocalMacros' )		-> set_sensitive( 1 );
			_( $self, 'labelVariables' )		-> set_sensitive( 1 );
			_( $self, 'labelTerminalOptions' )	-> set_sensitive( 1 );
			_( $self, 'alignAuthMethod' )		-> set_sensitive( 1 );
			_( $self, 'entryUser' )				-> set_sensitive( 1 );
			_( $self, 'alignUserPass' )			-> set_sensitive( 1 );
			_( $self, 'rbCfgAuthUserPass' )		-> set_active( $$cfg{'auth type'} eq 'userpass' );
			_( $self, 'framePublicKey' )		-> set_sensitive( 1 );
			_( $self, 'entryPassphrase' )		-> set_text( $$cfg{passphrase} // '' );
			_( $self, 'fileCfgPublicKey' )		-> set_filename( $$cfg{'public key'} // '' );
			_( $self, 'rbCfgAuthPublicKey' )	-> set_active( $$cfg{'auth type'} eq 'publickey' );
			_( $self, 'alignManual' )			-> set_sensitive( 1 );
			_( $self, 'rbCfgAuthUserPass' )		-> set_active( $$cfg{'auth type'} eq 'manual' );
			_( $self, 'frameExpect' )			-> set_sensitive( 1 );
			_( $self, 'frameRemoteMacros' )		-> set_sensitive( 1 );
			_( $self, 'frameLocalMacros' )		-> set_sensitive( 1 );
			_( $self, 'frameVariables' )		-> set_sensitive( 1 );
			_( $self, 'frameTerminalOptions' )	-> set_sensitive( 1 );
			_( $self, 'labelCmdLineOptions' )	-> set_markup( " '<b>$method</b>' command line options: " );
			_( $self, 'cbAutossh' )				-> set_sensitive( $autossh );
			_( $self, 'cbAutossh' )				-> set_active( $$cfg{'autossh'} );
		},
		'icon' => Gtk2::Gdk::Pixbuf -> new_from_file_at_scale( $RES_DIR . '/pac_method_ssh.jpg', 16, 16, 0 ),
		'escape' => [ '~.' ]
	};
	
	`which mosh 1>/dev/null 2>&1`; my $mosh = $?;
	$methods{ 'MOSH' } = {
		'installed' => sub { return ! $mosh ? 1 : "No 'mosh' binary found.\nTo use this option, please, install 'mosh'."; },
		'checkCFG' => sub {
			my $cfg = shift;
			
			my @faults;
			
			push( @faults, 'IP/Hostname' ) if ! _( $self, 'entryIP' ) -> get_chars( 0, -1 );
			if ( (_( $self, 'rbCfgAuthUserPass' ) -> get_active ) && ( ! _( $self, 'cbInferUserPassKPX' ) -> get_active ) ) {
				push( @faults, 'User (User/Password authentication method selected)' ) if ! _( $self, 'entryUser' ) -> get_chars( 0, -1 );
			}
			
			return @faults;
		},
		'updateGUI'	=> sub {
			my $cfg		= shift;
			
			my $method	= 'MOSH';
			my $pixbuf	= $$self{_METHODS}{ $method }{'icon'};
			
			_( $self, 'imageMethod' )			-> set_from_pixbuf( $pixbuf );
			_( $self, 'imageConnOptions' )		-> set_from_pixbuf( $pixbuf );
			#_( $self, 'vboxVarious' )			-> set_sensitive( 1 );
			_( $self, 'framePort' )				-> set_sensitive( 1 );
			_( $self, 'entryPort' )				-> set_value( $method eq $$cfg{method} ? $$cfg{port} : 22 );
			_( $self, 'labelIP' )				-> set_text( 'Host: ' );
			_( $self, 'entryIP' )				-> set_property( 'tooltip-markup', 'IP or Hostname of the machine to connect to' );
			_( $self, 'entryUser' )				-> set_text( $$cfg{user} // '' );
			_( $self, 'entryPassword' )			-> set_text( $$cfg{pass} // '' );
			_( $self, 'cbCfgAuthFallback' )		-> set_sensitive( 0 );
			_( $self, 'labelConnOptions' )		-> set_markup( "'<b>$method</b>'" );
			_( $self, 'labelExpect' )			-> set_sensitive( 1 );
			_( $self, 'labelRemoteMacros' )		-> set_sensitive( 1 );
			_( $self, 'labelLocalMacros' )		-> set_sensitive( 1 );
			_( $self, 'labelVariables' )		-> set_sensitive( 1 );
			_( $self, 'labelTerminalOptions' )	-> set_sensitive( 1 );
			_( $self, 'alignAuthMethod' )		-> set_sensitive( 1 );
			_( $self, 'entryUser' )				-> set_sensitive( 1 );
			_( $self, 'alignUserPass' )			-> set_sensitive( 1 );
			_( $self, 'rbCfgAuthUserPass' )		-> set_active( $$cfg{'auth type'} eq 'userpass' );
			_( $self, 'framePublicKey' )		-> set_sensitive( 0 );
			_( $self, 'entryPassphrase' )		-> set_text( $$cfg{passphrase} // '' );
			_( $self, 'fileCfgPublicKey' )		-> set_filename( $$cfg{'public key'} // '' );
			_( $self, 'rbCfgAuthPublicKey' )	-> set_active( $$cfg{'auth type'} eq 'publickey' );
			_( $self, 'alignManual' )			-> set_sensitive( 1 );
			_( $self, 'rbCfgAuthUserPass' )		-> set_active( $$cfg{'auth type'} eq 'manual' );
			_( $self, 'frameExpect' )			-> set_sensitive( 1 );
			_( $self, 'frameRemoteMacros' )		-> set_sensitive( 1 );
			_( $self, 'frameLocalMacros' )		-> set_sensitive( 1 );
			_( $self, 'frameVariables' )		-> set_sensitive( 1 );
			_( $self, 'frameTerminalOptions' )	-> set_sensitive( 1 );
			_( $self, 'labelCmdLineOptions' )	-> set_markup( " '<b>$method</b>' command line options: " );
			_( $self, 'cbAutossh' )				-> set_sensitive( 0 );
			_( $self, 'cbAutossh' )				-> set_active( 0 );
		},
		'icon' => Gtk2::Gdk::Pixbuf -> new_from_file_at_scale( $RES_DIR . '/pac_method_mosh.png', 16, 16, 0 ),
		'escape' => [ "\c^x." ]
	};
	
	`which cadaver 1>/dev/null 2>&1`; my $cadaver = $?;
	$methods{ 'WebDAV' } = {
		'installed' => sub { return ! $cadaver ? 1 : "No 'cadaver' binary found.\nTo use this option, please, install 'cadaver'."; },
		'checkCFG' => sub {
			my $cfg = shift;
			
			my @faults;
			
			push( @faults, 'IP/Hostname' ) if ! _( $self, 'entryIP' ) -> get_chars( 0, -1 );
			if ( (_( $self, 'rbCfgAuthUserPass' ) -> get_active ) && ( ! _( $self, 'cbInferUserPassKPX' ) -> get_active ) ) {
				push( @faults, 'User (User/Password authentication method selected)' ) if ! _( $self, 'entryUser' ) -> get_chars( 0, -1 );
			}
			
			return @faults;
		},
		'updateGUI'	=> sub {
			my $cfg		= shift;
			
			my $method	= 'WebDAV';
			my $pixbuf	= $$self{_METHODS}{ $method }{'icon'};
			
			_( $self, 'imageMethod' )			-> set_from_pixbuf( $pixbuf );
			_( $self, 'imageConnOptions' )		-> set_from_pixbuf( $pixbuf );
			#_( $self, 'vboxVarious' )			-> set_sensitive( 1 );
			_( $self, 'framePort' )				-> set_sensitive( 0 );
			_( $self, 'entryPort' )				-> set_value( $method eq $$cfg{method} ? $$cfg{port} : 80 );
			_( $self, 'labelIP' )				-> set_text( 'Host: ' );
			_( $self, 'entryIP' )				-> set_property( 'tooltip-markup', 'IP or Hostname of the machine to connect to' );
			_( $self, 'entryUser' )				-> set_text( $$cfg{user} // '' );
			_( $self, 'entryPassword' )			-> set_text( $$cfg{pass} // '' );
			_( $self, 'cbCfgAuthFallback' )		-> set_sensitive( 0 );
			_( $self, 'labelConnOptions' )		-> set_markup( "'<b>$method</b>'" );
			_( $self, 'labelExpect' )			-> set_sensitive( 1 );
			_( $self, 'labelRemoteMacros' )		-> set_sensitive( 1 );
			_( $self, 'labelLocalMacros' )		-> set_sensitive( 1 );
			_( $self, 'labelVariables' )		-> set_sensitive( 1 );
			_( $self, 'labelTerminalOptions' )	-> set_sensitive( 1 );
			_( $self, 'alignAuthMethod' )		-> set_sensitive( 1 );
			_( $self, 'entryUser' )				-> set_sensitive( 1 );
			_( $self, 'alignUserPass' )			-> set_sensitive( 1 );
			_( $self, 'rbCfgAuthUserPass' )		-> set_active( $$cfg{'auth type'} eq 'userpass' );
			_( $self, 'framePublicKey' )		-> set_sensitive( 0 );
			_( $self, 'entryPassphrase' )		-> set_text( $$cfg{passphrase} // '' );
			_( $self, 'fileCfgPublicKey' )		-> set_filename( $$cfg{'public key'} // '' );
			_( $self, 'rbCfgAuthPublicKey' )	-> set_active( $$cfg{'auth type'} eq 'publickey' );
			_( $self, 'alignManual' )			-> set_sensitive( 1 );
			_( $self, 'rbCfgAuthUserPass' )		-> set_active( $$cfg{'auth type'} eq 'manual' );
			_( $self, 'frameExpect' )			-> set_sensitive( 1 );
			_( $self, 'frameRemoteMacros' )		-> set_sensitive( 1 );
			_( $self, 'frameLocalMacros' )		-> set_sensitive( 1 );
			_( $self, 'frameVariables' )		-> set_sensitive( 1 );
			_( $self, 'frameTerminalOptions' )	-> set_sensitive( 1 );
			_( $self, 'labelCmdLineOptions' )	-> set_markup( " '<b>$method</b>' command line options: " );
			_( $self, 'cbAutossh' )				-> set_sensitive( 0 );
			_( $self, 'cbAutossh' )				-> set_active( 0 );
		},
		'icon' => Gtk2::Gdk::Pixbuf -> new_from_file_at_scale( $RES_DIR . '/pac_method_cadaver.png', 16, 16, 0 ),
		'escape' => [ "\cc", "quit\n" ]
	};
	
	`which telnet 1>/dev/null 2>&1`; my $telnet = $?;
	$methods{ 'Telnet' } = {
		'installed' => sub { return ! $telnet ? 1 : "No 'telnet' binary found.\nTo use this option, please, install 'telnet' or 'telnet-ssl'."; },
		'checkCFG' => sub {
			my $cfg = shift;
			my @faults;
			
			push( @faults, 'IP/Hostname' ) if ! _( $self, 'entryIP' ) -> get_chars( 0, -1 );
			push( @faults, 'Port' ) if ! _( $self, 'entryPort' ) -> get_chars( 0, -1 );
			if ( (_( $self, 'rbCfgAuthUserPass' ) -> get_active ) && ( ! _( $self, 'cbInferUserPassKPX' ) -> get_active ) ) {
				push( @faults, 'User (User/Password authentication method selected)' ) if ! _( $self, 'entryUser' ) -> get_chars( 0, -1 );
			}
			
			return @faults;
		},
		'updateGUI'	=> sub {
			my $cfg		= shift;
			
			my $method	= 'Telnet';
			my $pixbuf	= $$self{_METHODS}{ $method }{'icon'};
			
			_( $self, 'imageMethod' )			-> set_from_pixbuf( $pixbuf );
			_( $self, 'imageConnOptions' )		-> set_from_pixbuf( $pixbuf );
			#_( $self, 'vboxVarious' )			-> set_sensitive( 1 );
			_( $self, 'framePort' )				-> set_sensitive( 1 );
			_( $self, 'entryPort' )				-> set_value( $method eq $$cfg{method} ? $$cfg{port} : 23 );
			_( $self, 'labelIP' )				-> set_text( 'Host: ' );
			_( $self, 'entryIP' )				-> set_property( 'tooltip-markup', 'IP or Hostname of the machine to connect to' );
			_( $self, 'entryIP' )				-> set_text( $$cfg{ip} );
			_( $self, 'entryUser' )				-> set_text( $$cfg{user} // '' );
			_( $self, 'entryPassword' )			-> set_text( $$cfg{pass} // '' );
			_( $self, 'cbCfgAuthFallback' )		-> set_sensitive( 0 );
			_( $self, 'labelConnOptions' )		-> set_markup( "'<b>$method</b>'" );
			_( $self, 'labelExpect' )			-> set_sensitive( 1 );
			_( $self, 'labelRemoteMacros' )		-> set_sensitive( 1 );
			_( $self, 'labelLocalMacros' )		-> set_sensitive( 1 );
			_( $self, 'labelVariables' )		-> set_sensitive( 1 );
			_( $self, 'labelTerminalOptions' )	-> set_sensitive( 1 );
			_( $self, 'alignAuthMethod' )		-> set_sensitive( 1 );
			_( $self, 'entryUser' )				-> set_sensitive( 1 );
			_( $self, 'rbCfgAuthUserPass' )		-> set_active( 1 );
			_( $self, 'rbCfgAuthUserPass' )		-> set_active( $$cfg{'auth type'} eq 'userpass' );
			_( $self, 'framePublicKey' )		-> set_sensitive( 0 );
			_( $self, 'rbCfgAuthManual' )		-> set_sensitive( 1 );
			_( $self, 'rbCfgAuthManual' )		-> set_active( $$cfg{'auth type'} eq 'manual' );
			_( $self, 'entryPassphrase' )		-> set_text( '' );
			_( $self, 'fileCfgPublicKey' )		-> unselect_all;
			_( $self, 'frameExpect' )			-> set_sensitive( 1 );
			_( $self, 'frameRemoteMacros' )		-> set_sensitive( 1 );
			_( $self, 'frameLocalMacros' )		-> set_sensitive( 1 );
			_( $self, 'frameVariables' )		-> set_sensitive( 1 );
			_( $self, 'frameTerminalOptions' )	-> set_sensitive( 1 );
			_( $self, 'labelCmdLineOptions' )	-> set_markup( " '<b>$method</b>' command line options: " );
			_( $self, 'cbAutossh' )				-> set_sensitive( 0 );
			_( $self, 'cbAutossh' )				-> set_active( 0 );
		},
		'icon' => Gtk2::Gdk::Pixbuf -> new_from_file_at_scale( $RES_DIR . '/pac_method_telnet.jpg', 16, 16, 0 ),
		'escape' => [ "\c]", "quit\n" ]
	};
	
	$methods{ 'SFTP' } = {
		'installed' => sub { return 1; },
		'checkCFG' => sub {
			my $cfg = shift;
			my @faults;
			
			push( @faults, 'IP/Hostname' ) if ! _( $self, 'entryIP' ) -> get_chars( 0, -1 );
			push( @faults, 'Port' ) if ! _( $self, 'entryPort' ) -> get_chars( 0, -1 );
			if ( (_( $self, 'rbCfgAuthUserPass' ) -> get_active ) && ( ! _( $self, 'cbInferUserPassKPX' ) -> get_active ) ) {
				push( @faults, 'User (User/Password authentication method selected)' ) if ! _( $self, 'entryUser' ) -> get_chars( 0, -1 );
			} elsif ( _( $self, 'rbCfgAuthPublicKey' ) -> get_active ) {
				push( @faults, 'Public Key File (Public Key authentication method selected)' ) if ! _( $self, 'fileCfgPublicKey' ) -> get_filename;
			}
			
			return @faults;
		},
		'updateGUI'	=> sub {
			my $cfg		= shift;
			
			my $method	= 'SFTP';
			my $pixbuf	= $$self{_METHODS}{ $method }{'icon'};
			
			_( $self, 'imageMethod' )			-> set_from_pixbuf( $pixbuf );
			_( $self, 'imageConnOptions' )		-> set_from_pixbuf( $pixbuf );
			#_( $self, 'vboxVarious' )			-> set_sensitive( 1 );
			_( $self, 'framePort' )				-> set_sensitive( 1 );
			_( $self, 'entryPort' )				-> set_value( $method eq $$cfg{method} ? $$cfg{port} : 22 );
			_( $self, 'labelIP' )				-> set_text( 'Host: ' );
			_( $self, 'entryIP' )				-> set_property( 'tooltip-markup', 'IP or Hostname of the machine to connect to' );
			_( $self, 'entryUser' )				-> set_text( $$cfg{user} // '' );
			_( $self, 'entryPassword' )			-> set_text( $$cfg{pass} // '' );
			_( $self, 'cbCfgAuthFallback' )		-> set_sensitive( 1 );
			_( $self, 'labelConnOptions' )		-> set_markup( "'<b>$method</b>'" );
			_( $self, 'labelExpect' )			-> set_sensitive( 1 );
			_( $self, 'labelRemoteMacros' )		-> set_sensitive( 1 );
			_( $self, 'labelLocalMacros' )		-> set_sensitive( 1 );
			_( $self, 'labelVariables' )		-> set_sensitive( 1 );
			_( $self, 'labelTerminalOptions' )	-> set_sensitive( 1 );
			_( $self, 'alignAuthMethod' )		-> set_sensitive( 1 );
			_( $self, 'entryUser' )				-> set_sensitive( 1 );
			_( $self, 'alignUserPass' )			-> set_sensitive( 1 );
			_( $self, 'rbCfgAuthUserPass' )		-> set_active( $$cfg{'auth type'} eq 'userpass' );
			_( $self, 'framePublicKey' )		-> set_sensitive( 1 );
			_( $self, 'entryPassphrase' )		-> set_text( $$cfg{passphrase} // '' );
			_( $self, 'fileCfgPublicKey' )		-> set_filename( $$cfg{'public key'} // '' );
			_( $self, 'rbCfgAuthPublicKey' )	-> set_active( $$cfg{'auth type'} eq 'publickey' );
			_( $self, 'alignManual' )			-> set_sensitive( 1 );
			_( $self, 'rbCfgAuthUserPass' )		-> set_active( $$cfg{'auth type'} eq 'manual' );
			_( $self, 'frameExpect' )			-> set_sensitive( 1 );
			_( $self, 'frameRemoteMacros' )		-> set_sensitive( 1 );
			_( $self, 'frameLocalMacros' )		-> set_sensitive( 1 );
			_( $self, 'frameVariables' )		-> set_sensitive( 1 );
			_( $self, 'frameTerminalOptions' )	-> set_sensitive( 1 );
			_( $self, 'labelCmdLineOptions' )	-> set_markup( " '<b>$method</b>' command line options: " );
			_( $self, 'cbAutossh' )				-> set_sensitive( 0 );
			_( $self, 'cbAutossh' )				-> set_active( 0 );
		},
		'icon' => Gtk2::Gdk::Pixbuf -> new_from_file_at_scale( $RES_DIR . '/pac_method_sftp.jpg', 16, 16, 0 )
	};
	
	$methods{ 'FTP' } = {
		'installed' => sub { return 1; },
		'checkCFG' => sub {
			my $cfg = shift;
			
			my @faults;
			
			push( @faults, 'IP/Hostname' ) if ! _( $self, 'entryIP' ) -> get_chars( 0, -1 );
			push( @faults, 'Port' ) if ! _( $self, 'entryPort' ) -> get_chars( 0, -1 );
			if ( (_( $self, 'rbCfgAuthUserPass' ) -> get_active ) && ( ! _( $self, 'cbInferUserPassKPX' ) -> get_active ) ) {
				push( @faults, 'User (User/Password authentication method selected)' ) if ! _( $self, 'entryUser' ) -> get_chars( 0, -1 );
			}
			
			return @faults;
		},
		'updateGUI'	=> sub {
			my $cfg		= shift;
			
			my $method	= 'FTP';
			my $pixbuf	= $$self{_METHODS}{ $method }{'icon'};
			
			_( $self, 'imageMethod' )			-> set_from_pixbuf( $pixbuf );
			_( $self, 'imageConnOptions' )		-> set_from_pixbuf( $pixbuf );
			#_( $self, 'vboxVarious' )			-> set_sensitive( 1 );
			_( $self, 'framePort' )				-> set_sensitive( 1 );
			_( $self, 'entryPort' )				-> set_value( $method eq $$cfg{method} ? $$cfg{port} : 21 );
			_( $self, 'labelIP' )				-> set_text( 'Host: ' );
			_( $self, 'entryIP' )				-> set_property( 'tooltip-markup', 'IP or Hostname of the machine to connect to' );
			_( $self, 'entryUser' )				-> set_text( $$cfg{user} // '' );
			_( $self, 'entryPassword' )			-> set_text( $$cfg{pass} // '' );
			_( $self, 'cbCfgAuthFallback' )		-> set_sensitive( 0 );
			_( $self, 'labelConnOptions' )		-> set_markup( "'<b>$method</b>'" );
			_( $self, 'labelExpect' )			-> set_sensitive( 1 );
			_( $self, 'labelRemoteMacros' )		-> set_sensitive( 1 );
			_( $self, 'labelLocalMacros' )		-> set_sensitive( 1 );
			_( $self, 'labelVariables' )		-> set_sensitive( 1 );
			_( $self, 'labelTerminalOptions' )	-> set_sensitive( 1 );
			_( $self, 'alignAuthMethod' )		-> set_sensitive( 1 );
			_( $self, 'entryUser' )				-> set_sensitive( 1 );
			_( $self, 'rbCfgAuthUserPass' )		-> set_active( 1 );
			_( $self, 'rbCfgAuthUserPass' )		-> set_active( $$cfg{'auth type'} eq 'userpass' );
			_( $self, 'framePublicKey' )		-> set_sensitive( 0 );
			_( $self, 'entryPassphrase' )		-> set_text( '' );
			_( $self, 'fileCfgPublicKey' )		-> unselect_all;
			_( $self, 'rbCfgAuthManual' )		-> set_sensitive( 1 );
			_( $self, 'rbCfgAuthManual' )		-> set_active( $$cfg{'auth type'} eq 'manual' );
			_( $self, 'frameExpect' )			-> set_sensitive( 1 );
			_( $self, 'frameRemoteMacros' )		-> set_sensitive( 1 );
			_( $self, 'frameLocalMacros' )		-> set_sensitive( 1 );
			_( $self, 'frameVariables' )		-> set_sensitive( 1 );
			_( $self, 'frameTerminalOptions' )	-> set_sensitive( 1 );
			_( $self, 'labelCmdLineOptions' )	-> set_markup( " '<b>$method</b>' command line options: " );
			_( $self, 'cbAutossh' )				-> set_sensitive( 0 );
			_( $self, 'cbAutossh' )				-> set_active( 0 );
		},
		'icon' => Gtk2::Gdk::Pixbuf -> new_from_file_at_scale( $RES_DIR . '/pac_method_ftp.jpg', 16, 16, 0 )
	};
	
	$methods{ 'Generic Command' } = {
		'installed' => sub { return 1; },
		'checkCFG' => sub {
			my $cfg = shift;
			
			my @faults;
			
			push( @faults, 'Full command line' ) unless _( $self, 'entryIP' ) -> get_chars( 0, -1 ) ne '';
			
			return @faults;
		},
		'updateGUI'	=> sub {
			my $method = 'Generic Command';
			my $pixbuf = $$self{_METHODS}{ $method }{'icon'};
			
			_( $self, 'imageMethod' )			-> set_from_pixbuf( $pixbuf );
			_( $self, 'imageConnOptions' )		-> set_from_pixbuf( $pixbuf );
			#_( $self, 'vboxVarious' )			-> set_sensitive( 0 );
			_( $self, 'labelIP' )				-> set_text( 'Full command line: ' );
			_( $self, 'entryIP' )				-> set_property( 'tooltip-markup', "Full command line to execute, example:\nfirefox http://www.google.es\nor\nxdg-open \$HOME/Pictures/mounaint.jpg\nor\n/bin/bash -login\netc..." );
			_( $self, 'framePort' )				-> set_sensitive( 0 );
			_( $self, 'entryPort' )				-> set_value( 0 );
			_( $self, 'entryUser' )				-> set_text( '' );
			_( $self, 'entryPassword' )			-> set_text( '' );
			_( $self, 'cbCfgAuthFallback' )		-> set_sensitive( 0 );
			_( $self, 'frameExpect' )			-> set_sensitive( 1 );
			_( $self, 'frameRemoteMacros' )		-> set_sensitive( 1 );
			_( $self, 'frameLocalMacros' )		-> set_sensitive( 1 );
			_( $self, 'frameVariables' )		-> set_sensitive( 1 );
			_( $self, 'frameTerminalOptions' )	-> set_sensitive( 1 );
			_( $self, 'alignAuthMethod' )		-> set_sensitive( 0 );
			_( $self, 'rbCfgAuthManual' )		-> set_active( 1 );
			_( $self, 'entryUser' )				-> set_sensitive( 0 );
			_( $self, 'entryPassphrase' )		-> set_text( '' );
			_( $self, 'fileCfgPublicKey' )		-> unselect_all;
			_( $self, 'labelConnOptions' )		-> set_markup( "'<b>$method</b>'" );
			_( $self, 'labelExpect' )			-> set_sensitive( 1 );
			_( $self, 'labelRemoteMacros' )		-> set_sensitive( 1 );
			_( $self, 'labelLocalMacros' )		-> set_sensitive( 1 );
			_( $self, 'labelVariables' )		-> set_sensitive( 1 );
			_( $self, 'labelTerminalOptions' )	-> set_sensitive( 1 );
			_( $self, 'labelCmdLineOptions' )	-> set_markup( " '<b>$method</b>' command line options: " );
			_( $self, 'cbAutossh' )				-> set_sensitive( 0 );
			_( $self, 'cbAutossh' )				-> set_active( 0 );
		},
		'icon' => Gtk2::Gdk::Pixbuf -> new_from_file_at_scale( $RES_DIR . '/pac_method_generic.jpg', 16, 16, 0 )
	};
	
	return %methods;
}

sub _registerPACIcons {
	my %icons = (
		'pac-app-big'						=> $RES_DIR . '/asbru-logo-64.png',
		'pac-group-add'						=> $RES_DIR . '/pac_group_add_16x16.png',
		'pac-node-add'						=> $RES_DIR . '/pac_node_add_16x16.png',
		'pac-node-del'						=> $RES_DIR . '/pac_node_del_16x16.png',
		'pac-chain'							=> $RES_DIR . '/pac_chain.png',
		'pac-cluster-auto'					=> $RES_DIR . '/pac_cluster_auto.png',
		'pac-cluster-manager2'				=> $RES_DIR . '/pac_cluster_manager2.png',
		'pac-cluster-manager'				=> $RES_DIR . '/pac_cluster_manager.png',
		'pac-cluster-manager-off'			=> $RES_DIR . '/pac_cluster_manager_off.png',
		'pac-favourite-on'					=> $RES_DIR . '/pac_favourite_on.png',
		'pac-favourite-off'					=> $RES_DIR . '/pac_favourite_off.png',
		'pac-group-closed'					=> $RES_DIR . '/pac_group_closed_16x16.png',
		'pac-group-closed'					=> $RES_DIR . '/pac_group_closed_16x16.png',
		'pac-group-open'					=> $RES_DIR . '/pac_group_open_16x16.png',
		'pac-group'							=> $RES_DIR . '/pac_group.png',
		'pac-history'						=> $RES_DIR . '/pac_history.png',
		'pac-keepass'						=> $RES_DIR . '/pac_keepass.png',
		'pac-method-WebDAV'					=> $RES_DIR . '/pac_method_cadaver.png',
		'pac-method-MOSH'					=> $RES_DIR . '/pac_method_mosh.png',
		'pac-method-IBM 3270/5250'			=> $RES_DIR . '/pac_method_3270.jpg',
		'pac-method-Serial (cu)'			=> $RES_DIR . '/pac_method_cu.jpg',
		'pac-method-FTP'					=> $RES_DIR . '/pac_method_ftp.jpg',
		'pac-method-Generic Command'		=> $RES_DIR . '/pac_method_generic.jpg',
		'pac-method-RDP (Windows)'			=> $RES_DIR . '/pac_method_rdesktop.jpg',
		'pac-method-RDP (rdesktop)'			=> $RES_DIR . '/pac_method_rdesktop.jpg',
		'pac-method-RDP (xfreerdp)'			=> $RES_DIR . '/pac_method_rdesktop.jpg',
		'pac-method-Serial (remote-tty)'	=> $RES_DIR . '/pac_method_remote-tty.jpg',
		'pac-method-SFTP'					=> $RES_DIR . '/pac_method_sftp.jpg',
		'pac-method-SSH'					=> $RES_DIR . '/pac_method_ssh.jpg',
		'pac-method-Telnet'					=> $RES_DIR . '/pac_method_telnet.jpg',
		'pac-method-VNC'					=> $RES_DIR . '/pac_method_vncviewer.jpg',
		'pac-quick-connect'					=> $RES_DIR . '/pac_quick_connect.png',
		'pac-script'						=> $RES_DIR . '/pac_script.png',
		'pac-shell'							=> $RES_DIR . '/pac_shell.png',
		'pac-tab'							=> $RES_DIR . '/pac_tab.png',
		'pac-terminal-ok-small'				=> $RES_DIR . '/pac_terminal16x16.png',
		'pac-terminal-ok-big'				=> $RES_DIR . '/pac_terminal64x64.png',
		'pac-terminal-ko-small'				=> $RES_DIR . '/pac_terminal_x16x16.png',
		'pac-terminal-ko-big'				=> $RES_DIR . '/pac_terminal_x64x64.png',
		'pac-tray-bw'						=> $RES_DIR . '/pac_tray_bw.png',
		'pac-tray'							=> $RES_DIR . '/asbru-logo-tray.png',
		'pac-treelist'						=> $RES_DIR . '/pac_treelist.png',
		'pac-wol'							=> $RES_DIR . '/pac_wol.png',
		'pac-prompt'						=> $RES_DIR . '/pac_prompt.png',
		'pac-protected'						=> $RES_DIR . '/pac_protected.png',
		'pac-unprotected'					=> $RES_DIR . '/pac_unprotected.png',
	);
	
	my $icon_factory = Gtk2::IconFactory -> new;
   
	foreach my $icon ( keys %icons ) {
		my $icon_source = Gtk2::IconSource -> new;
		$icon_source -> set_filename( $icons{$icon} );
		
		my $icon_set = Gtk2::IconSet -> new;
		$icon_set -> add_source( $icon_source );
		
		$icon_factory -> add( $icon, $icon_set);
	}
	
	$icon_factory -> add_default; 
	
	return 1;
}

sub _sortTreeData {
	my $cfg			= $PACMain::FUNCS{_MAIN}{_CFG};
	my $groups_1st	= $$cfg{'defaults'}{'sort groups first'} // 1;
	
	my $a_name		= lc( $$a{'value'}[1] ); $a_name =~ s/<.+>(.+?)<\/.+>/$1/go;
	my $b_name		= lc( $$b{'value'}[1] ); $b_name =~ s/<.+>(.+?)<\/.+>/$1/go;
	my $a_is_group	= $$cfg{'environments'}{$$a{'value'}[2]}{'_is_group'};
	my $b_is_group	= $$cfg{'environments'}{$$b{'value'}[2]}{'_is_group'};
	
	if ( $groups_1st ) {
		( $a_is_group && ! $b_is_group )	and return -1;
		( ! $a_is_group && $b_is_group )	and return 1;
		( ! $a_is_group && ! $b_is_group )	and return $a_name cmp  $b_name;
		( $a_is_group && $b_is_group )		and return $a_name cmp  $b_name;
	} else {
		return $a_name cmp $b_name;
	}
}
	
sub _menuFavouriteConnections {
	my $terminal	= shift // 0;
	
	my $cfg			= $PACMain::FUNCS{_MAIN}{_CFG};
	my @fav;
	
	foreach my $uuid ( keys %{ $$cfg{environments} } ) {
		next if $uuid eq '__PAC__ROOT__';
		next unless $$cfg{'environments'}{$uuid}{'favourite'};
		
		my $name = $$cfg{'environments'}{$uuid}{'name'};
		
		if ( $terminal ) {
			push( @fav, {
				label		=> $name,
				stockicon	=> $PACMain::UNITY ? '' : 'pac-method-' . $$cfg{'environments'}{$uuid}{'method'},
				tooltip		=> $$cfg{'environments'}{$uuid}{'description'},
				submenu		=> [
					{	label		=> 'Start',
						stockicon	=> $PACMain::UNITY ? '' : 'gtk-media-play',
						code		=> sub { $PACMain::FUNCS{_MAIN} -> _launchTerminals( [ [ $uuid ] ] ); }
					}, {
						label		=> "Chain with '$$terminal{_NAME}'",
						stockicon	=> $PACMain::UNITY ? '' : 'pac-chain',
						sensitive	=> $$terminal{CONNECTED},
						code		=> sub { $terminal -> _wSelectChain( $uuid ); }
					}
				]
			} );
		} else {
			push( @fav, {
				label		=> $name,
				stockicon	=> $PACMain::UNITY ? '' : 'pac-method-' . $$cfg{'environments'}{$uuid}{'method'},
				tooltip		=> $$cfg{'environments'}{$uuid}{'description'},
				code		=> sub { $PACMain::FUNCS{_MAIN} -> _launchTerminals( [ [ $uuid ] ] ); }
			} );
		}
	}
	
	@fav = sort { lc( $$a{label} ) cmp lc( $$b{label} ) } @fav;
	return \@fav;
}

sub _menuClusterConnections {
	my @fav;
	
	foreach my $ac ( sort { lc( $a ) cmp lc( $b ) } keys %{ $PACMain::FUNCS{_MAIN}{_CFG}{defaults}{'auto cluster'} } ) {
		push( @fav, {
			label		=> $ac,
			stockicon	=> $PACMain::UNITY ? '' : 'pac-cluster-auto',
			code		=> sub { $PACMain::FUNCS{_MAIN} -> _startCluster( $ac ); }
		} );
	}
	
	foreach my $cluster ( sort { lc( $a ) cmp lc( $b ) } keys %{ $PACMain::FUNCS{_MAIN}{_CLUSTER} -> getCFGClusters } ) {
		push( @fav, {
			label		=> $cluster,
			stockicon	=> $PACMain::UNITY ? '' : 'pac-cluster-manager2',
			code		=> sub { $PACMain::FUNCS{_MAIN} -> _startCluster( $cluster ); }
		} );
	}
	
	return \@fav;
}
	
sub _menuAvailableConnections {
	my $tree		= shift // $PACMain::FUNCS{_MAIN}{_GUI}{treeConnections}{data};
	my $terminal	= shift // 0;
	
	my $cfg			= $PACMain::FUNCS{_MAIN}{_CFG};
	my @tray_menu_items;
	
	foreach my $elem_hash ( sort _sortTreeData @{ $tree } ) {
		my $this_icon	= $$elem_hash{'value'}[0];
		my $this_name	= $$elem_hash{'value'}[1];
		my $this_uuid	= $$elem_hash{'value'}[2];
		
		next if $this_uuid eq '__PAC__ROOT__';
		
		$this_name =~ s/<.+>(.+?)<\/.+>/$1/go;
		$this_name = __( $this_name );
		
		if ( scalar( @{ $$elem_hash{'children'} } ) ) {
			push( @tray_menu_items, {
				label		=> $this_name,
				stockicon	=> $PACMain::UNITY ? '' : 'pac-group-closed',
				tooltip		=> $$cfg{'environments'}{$this_uuid}{'description'} // '',
				submenu		=> _menuAvailableConnections( $$elem_hash{'children'}, $terminal )
			} );
		} elsif ( $terminal ) {
			push( @tray_menu_items, {
				label		=> $this_name,
				stockicon	=> $PACMain::UNITY ? '' : 'pac-method-' . $$cfg{'environments'}{$this_uuid}{'method'},
				tooltip		=> $$cfg{'environments'}{$this_uuid}{'description'},
				submenu		=> [ {
						label		=> 'Start',
						stockicon	=> $PACMain::UNITY ? '' : 'gtk-media-play',
						code		=> sub { $PACMain::FUNCS{_MAIN} -> _launchTerminals( [ [ $this_uuid ] ] ); }
					}, {
						label		=> "Chain with '$$terminal{_NAME}'",
						stockicon	=> $PACMain::UNITY ? '' : 'pac-chain',
						sensitive	=> $$terminal{CONNECTED},
						code		=> sub { $terminal -> _wSelectChain( $this_uuid ); }
					}
				]
			} );
		} else {
			push( @tray_menu_items, {
				label		=> $this_name,
				stockicon	=> $PACMain::UNITY ? '' : 'pac-method-' . $$cfg{'environments'}{$this_uuid}{'method'},
				tooltip		=> $$cfg{'environments'}{$this_uuid}{'description'},
				code		=> sub { $PACMain::FUNCS{_MAIN} -> _launchTerminals( [ [ $this_uuid ] ] ); }
			} );
		}
	}
	
	return \@tray_menu_items;
}

sub _wEnterValue {
	my $self		= shift;
	my $lblup		= shift;
	my $lbldown		= shift;
	my $default		= shift;
	my $visible		= shift // 1;
	my $stock_icon	= shift // 'gtk-edit';
	
	my @list;
	my $pos = -1;
	
	if ( ! defined $default ) {
		$default = '';
	} elsif ( ref( $default ) ) {
		@list = @{ $default };
	}
	
	my %w;
	
	# Create the dialog window,
	$w{window}{data} = Gtk2::Dialog -> new_with_buttons(
		"$APPNAME (v$APPVERSION) : Enter data",
		undef,
		'modal',
		'gtk-ok'		=> 'ok',
		'gtk-cancel'	=> 'cancel'
	);
	# and setup some dialog properties.
	$w{window}{data} -> set_default_response( 'ok' );
	$w{window}{data} -> set_position( 'center' );
	$w{window}{data} -> set_icon_name( 'pac-app-big' );
	$w{window}{data} -> set_size_request( -1, -1 );
	$w{window}{data} -> set_resizable( 0 );
	$w{window}{data} -> set_border_width( 5 );
		
		# Create an HBox to contain a picture and a label
		$w{window}{gui}{hbox} = Gtk2::HBox -> new( 0, 0 );
		$w{window}{data} -> vbox -> pack_start( $w{window}{gui}{hbox}, 1, 1, 5 );
		$w{window}{gui}{hbox} -> set_border_width( 5 );
			
			# Create image
			$w{window}{gui}{img} = Gtk2::Image -> new_from_stock( $stock_icon, 'dialog' );
			$w{window}{gui}{hbox} -> pack_start( $w{window}{gui}{img}, 0, 1, 5 );
			
			# Create 1st label
			$w{window}{gui}{lblup} = Gtk2::Label -> new;
			$w{window}{gui}{hbox} -> pack_start( $w{window}{gui}{lblup}, 1, 1, 5 );
			$w{window}{gui}{lblup} -> set_markup( $lblup );
		
		# Create 2nd label
		$w{window}{gui}{lbldwn} = Gtk2::Label -> new;
		$w{window}{data} -> vbox -> pack_start( $w{window}{gui}{lbldwn}, 1, 1, 5 );
		$w{window}{gui}{lbldwn} -> set_text( $lbldown );
		
		if ( @list ) {
			# Create combobox widget
			$w{window}{gui}{comboList} = Gtk2::ComboBox -> new_text;
			$w{window}{data} -> vbox -> pack_start( $w{window}{gui}{comboList}, 0, 1, 0 );
			$w{window}{gui}{comboList} -> set_property( 'can_focus', 0 );
			foreach my $text ( @list ) { $w{window}{gui}{comboList} -> append_text( $text ) };
			$w{window}{gui}{comboList} -> set_active( 0 );
		} else {
			# Create the entry widget
			$w{window}{gui}{entry} = Gtk2::Entry -> new;
			$w{window}{data} -> vbox -> pack_start( $w{window}{gui}{entry}, 0, 1, 5 );
			$w{window}{gui}{entry} -> set_text( $default );
			$w{window}{gui}{entry} -> set_activates_default( 1 );
			$w{window}{gui}{entry} -> set_visibility( $visible );
		}
	
	# Show the window (in a modal fashion)
	$w{window}{data} -> show_all;
	my $ok = $w{window}{data} -> run;
	
	my $val = undef;
	if ( @list ) {
		$val = $w{window}{gui}{comboList} -> get_active_text if ( $ok eq 'ok' );
		$pos = $w{window}{gui}{comboList} -> get_active;
	} else {
		$val = $w{window}{gui}{entry} -> get_chars( 0, -1 ) if ( $ok eq 'ok' );
	}
	
	$w{window}{data} -> destroy;
	Gtk2 -> main_iteration while Gtk2 -> events_pending;
	
	return wantarray ? ( $val, $pos ) : $val;
}

sub _wAddRenameNode {
	my $action	= shift;
	my $cfg		= shift;
	my $uuid	= shift;
	
	my ( $name, $parent_name, $title, $lblup );
	
	if ( $action eq 'rename' ) {
		$name			= $$cfg{'environments'}{$uuid}{'name'};
		$parent_name	= $$cfg{'environments'}{ $$cfg{'environments'}{$uuid}{'parent'} }{'name'};
		$title			= $$cfg{'environments'}{$uuid}{'title'};
		$lblup			= "<b>Renaming node '" . __( $name ) . "'</b>";
	} elsif ( $action eq 'add' ) {
		$name			= '';
		$parent_name	= $$cfg{'environments'}{ $uuid }{'name'};
		$title			= $uuid eq '__PAC__ROOT__' || ! $$cfg{defaults}{'append group name'} ? '' : ($parent_name eq '' ? '' : "$parent_name - ");
		$lblup			= "<b>Adding new node into '" . ( $uuid eq '__PAC__ROOT__' ? 'ROOT' : "$parent_name" ) . "'</b>";
	}
	
	my %w;
	my $new_name;
	my $new_title;
	
	# Create the dialog window,
	$w{window}{data} = Gtk2::Dialog -> new_with_buttons(
		"$APPNAME (v$APPVERSION) : Enter data",
		undef,
		'modal',
		'gtk-ok'		=> 'ok',
		'gtk-cancel'	=> 'cancel'
	);
	# and setup some dialog properties.
	$w{window}{data} -> set_default_response( 'ok' );
	$w{window}{data} -> set_position( 'center' );
	$w{window}{data} -> set_icon_name( 'pac-app-big' );
	$w{window}{data} -> set_size_request( -1, -1 );
	$w{window}{data} -> set_resizable( 0 );
	$w{window}{data} -> set_border_width( 5 );
		
		# Create an HBox to contain a picture and a label
		$w{window}{gui}{hbox} = Gtk2::HBox -> new( 0, 0 );
		$w{window}{data} -> vbox -> pack_start( $w{window}{gui}{hbox}, 0, 1, 0 );
		$w{window}{gui}{hbox} -> set_border_width( 5 );
			
			# Create image
			$w{window}{gui}{img} = Gtk2::Image -> new_from_stock( 'gtk-edit', 'dialog' );
			$w{window}{gui}{hbox} -> pack_start( $w{window}{gui}{img}, 0, 1, 0 );
			
			# Create 1st label
			$w{window}{gui}{lblup} = Gtk2::Label -> new;
			$w{window}{gui}{hbox} -> pack_start( $w{window}{gui}{lblup}, 1, 1, 0 );
			$w{window}{gui}{lblup} -> set_markup( $lblup );
		
		# Create an HBox to contain a label and an entry
		$w{window}{gui}{hbox1} = Gtk2::HBox -> new( 0, 0 );
		$w{window}{data} -> vbox -> pack_start( $w{window}{gui}{hbox1}, 0, 1, 0 );
		$w{window}{gui}{hbox1} -> set_border_width( 5 );
			
			# Create label
			$w{window}{gui}{lbl1} = Gtk2::Label -> new;
			$w{window}{gui}{hbox1} -> pack_start( $w{window}{gui}{lbl1}, 0, 1, 0 );
			$w{window}{gui}{lbl1} -> set_text( 'Enter new NAME: ' );
			
			# Create the entry widget
			$w{window}{gui}{entry1} = Gtk2::Entry -> new;
			$w{window}{gui}{hbox1} -> pack_start( $w{window}{gui}{entry1}, 1, 1, 0 );
			$w{window}{gui}{entry1} -> set_text( $name );
			$w{window}{gui}{entry1} -> set_activates_default( 1 );
			$w{window}{gui}{entry1} -> signal_connect( 'changed', sub {
				$w{window}{gui}{entry2} -> set_text( ( $uuid eq '__PAC__ROOT__' || ! $$cfg{defaults}{'append group name'} ? '' : ($parent_name eq '' ? '' : "$parent_name - ") ) . $w{window}{gui}{entry1} -> get_chars( 0, -1 ) );
			} );
		
		# Create an HBox to contain a label and an entry
		$w{window}{gui}{hbox2} = Gtk2::HBox -> new( 0, 0 );
		$w{window}{data} -> vbox -> pack_start( $w{window}{gui}{hbox2}, 0, 1, 0 );
		$w{window}{gui}{hbox2} -> set_border_width( 5 );
			
			# Create label
			$w{window}{gui}{lbl2} = Gtk2::Label -> new;
			$w{window}{gui}{hbox2} -> pack_start( $w{window}{gui}{lbl2}, 0, 1, 0 );
			$w{window}{gui}{lbl2} -> set_text( 'Enter new TITLE: ' );
			
			# Create the entry widget
			$w{window}{gui}{entry2} = Gtk2::Entry -> new;
			$w{window}{gui}{hbox2} -> pack_start( $w{window}{gui}{entry2}, 1, 1, 0 );
			$w{window}{gui}{entry2} -> set_text( $title );
			$w{window}{gui}{entry2} -> set_activates_default( 1 );
	
	# Show the window (in a modal fashion)
	$w{window}{data} -> show_all;
	my $ok = $w{window}{data} -> run;
	
	$new_name	= $w{window}{gui}{entry1} -> get_chars( 0, -1 ) if ( $ok eq 'ok' );
	$new_title	= $w{window}{gui}{entry2} -> get_chars( 0, -1 ) if ( $ok eq 'ok' );
	
	$w{window}{data} -> destroy;
	Gtk2 -> main_iteration while Gtk2 -> events_pending;
	
	return ( $new_name, $new_title );
}

sub _wPopUpMenu {
	my $mref	= shift;
	our $event	= shift;
	my $below	= shift // '0';
	my $ref		= shift // '0';
	
	( defined $WIDGET_POPUP && $WIDGET_POPUP -> visible ) and return 1;
	
	our $jari = -1;
	my @array;
	my %props;
	
	my $xml = "<ui>\n<popup name='Menu' accelerators='true'>\n";
	$xml .= _buildMenuData( \@array, $mref, \%props );
	$xml .= "</popup>\n</ui>";
	
	my $actions = Gtk2::ActionGroup -> new( 'Actions' );
	$actions -> add_actions( \@array, undef );
	
	my $ui = Gtk2::UIManager -> new;
	$ui -> set_add_tearoffs( 1 );
	$ui -> insert_action_group( $actions, 0 );
	
	$ui -> add_ui_from_string( $xml );
	
	foreach my $path ( keys %props ) {
		foreach my $prop ( keys %{ $props{$path} } ) {
			$ui -> get_widget( '/Menu' . $path ) -> set( $prop, $props{$path}{$prop} );
		}
	}
	
	$WIDGET_POPUP = $ui -> get_widget( '/Menu' );
	$WIDGET_POPUP -> show_all;
	$ref and return $WIDGET_POPUP;
	
	if ( defined $event )	{ $WIDGET_POPUP -> popup( undef, undef, ( $below ? \&_pos : undef ), undef, $event -> button, $event -> time ); }
	else					{ $WIDGET_POPUP -> popup( undef, undef, undef, undef, 0, 0 ); }
	
	sub _buildMenuData {
		my $menu_array	= shift;
		my $mref		= shift;
		my $props		= shift;
		my $path		= shift // '';
		
		my $xml = '';
		
		for my $m ( @{ $mref } ) {
			my $label		= $$m{label} // '';
			my $sensitive	= $$m{sensitive} // 1;
			my $tooltip		= $$m{tooltip} // '';
			
			my $label_orig	=  $label;
			$label =~ s/\//__backslash__/go;
			my $pre_path = $path;
			
			++$jari;
			if ( $$m{separator} ) {
				$xml .= "<separator/>\n";
			} elsif ( $$m{submenu} ) {
				$xml .= '<menu action="MenuParent' . __( $label ) . ":$jari:" . 'EndMenuParent">' . "\n";
				push( @{ $menu_array }, [ 'MenuParent' . $label . ":$jari:" . 'EndMenuParent', $$m{stockicon}, $label_orig ] );
				
				$path .= '/MenuParent' . $label . ":$jari:" . 'EndMenuParent';
				$$props{$path}{sensitive}		= $sensitive;
				$$props{$path}{tooltip_text}	= $tooltip;
				$$props{$path}{use_underline}	= 0;
				
				$xml .= _buildMenuData( $menu_array, $$m{submenu}, $props, $path );
				$xml .= "</menu>\n";
			} else {
				$xml .= '<menuitem action="MenuItem' . __( $label ) . ":$jari:" . 'EndMenuItem"/>' . "\n";
				push( @{ $menu_array }, [
					'MenuItem' . $label . ":$jari:" . 'EndMenuItem',
					$$m{stockicon},
					$label_orig, $$m{shortcut},
					$$m{tooltip},
					sub { &{ $$m{code} }; }
				] );
				
				$path .= '/MenuItem' . $label . ":$jari:" . 'EndMenuItem';
				$$props{$path}{sensitive}		= $sensitive;
				$$props{$path}{tooltip_text}	= $tooltip;
				$$props{$path}{use_underline}	= 0;
			}
			
			$path = $pre_path;
		}
		
		return $xml;
	}
	
	sub _pos {
	    my $h			= $_[0] -> size_request -> height;
	    my $ymax		= $event -> get_screen -> get_height;
	    my ( $x, $y )	= $event -> window -> get_origin;
	    my $dy			= ( $event -> window -> get_size )[1];
	    
		# Over the event widget
		if ( $dy + $y + $h > $ymax ) {
	        $y -= $h;
	        $y = 0 if $y < 0;
		# Below the event widget
	    } else {
			$y += $dy;
		}
	    
		return $x, $y;
	}
 }

sub _wMessage {
	my $window	= shift;
	my $msg		= shift;
	my $modal	= shift // 1;
	
	my $windowConfirm = Gtk2::MessageDialog -> new_with_markup( 
		$window,
		'GTK_DIALOG_DESTROY_WITH_PARENT',
		'GTK_MESSAGE_INFO',
		'none',
		$msg
	);   
	$windowConfirm -> set_icon_name( 'pac-app-big' );
	$windowConfirm -> set_title( "$APPNAME (v$APPVERSION) : Message" );
	
	if ( $modal ) {
		$windowConfirm -> add_buttons( 'gtk-ok' => 'ok' );
		$windowConfirm -> show_all;
		my $close = $windowConfirm -> run;
		$windowConfirm -> destroy;
	} else {
		$windowConfirm -> show_all;
		Gtk2 -> main_iteration while Gtk2 -> events_pending;
	}
	
	return $windowConfirm;
}

sub _wProgress {
	my $window		= shift;
	my $title		= shift;
	my $msg			= shift;
	my $progress	= shift;
	
	$WINDOWPROGRESS{_RET} = 1;
	
	if ( ! defined $WINDOWPROGRESS{_GUI} ) {
		$WINDOWPROGRESS{_GUI} = Gtk2::Window -> new;
			
			$WINDOWPROGRESS{_GUI} -> set_position( 'center' );
			$WINDOWPROGRESS{_GUI} -> set_icon_name( 'pac-app-big' );
			$WINDOWPROGRESS{_GUI} -> set_size_request( '400', '150' );
			$WINDOWPROGRESS{_GUI} -> set_resizable( 0 );
			$WINDOWPROGRESS{_GUI} -> set_transient_for( $window ) if defined $window;
			$WINDOWPROGRESS{_GUI} -> set_modal( 1 );
			
			$WINDOWPROGRESS{vbox} = Gtk2::VBox -> new( 0, 0 );
			$WINDOWPROGRESS{_GUI} -> add( $WINDOWPROGRESS{vbox} );
				
				$WINDOWPROGRESS{lbl1} = Gtk2::Label -> new;
				$WINDOWPROGRESS{vbox} -> pack_start( $WINDOWPROGRESS{lbl1}, 0, 1, 5 );
				
				$WINDOWPROGRESS{pb} = Gtk2::ProgressBar -> new;
				$WINDOWPROGRESS{vbox} -> pack_start( $WINDOWPROGRESS{pb}, 1, 1, 5 );
				
				$WINDOWPROGRESS{sep} = Gtk2::HSeparator -> new;
				$WINDOWPROGRESS{vbox} -> pack_start( $WINDOWPROGRESS{sep}, 0, 1, 5 );
				
				$WINDOWPROGRESS{btnCancel} = Gtk2::Button -> new_from_stock( 'gtk-cancel' );
				$WINDOWPROGRESS{vbox} -> pack_start( $WINDOWPROGRESS{btnCancel}, 0, 1, 5 );
			
			$WINDOWPROGRESS{_GUI} -> signal_connect( 'delete_event' => sub { return 1; } );
			$WINDOWPROGRESS{btnCancel} -> signal_connect( 'clicked' => sub {
				$WINDOWPROGRESS{_RET} = 0;
				$WINDOWPROGRESS{_GUI} -> hide;
				return 1;
			} );	
	}
	
	$WINDOWPROGRESS{_GUI} -> set_icon_name( 'pac-app-big' );
	$WINDOWPROGRESS{_GUI} -> set_title( "$APPNAME (v$APPVERSION) : $title" );
	
	if ( $progress ) {
		my ( $partial, $total ) = split( '/', $progress );
		
		$WINDOWPROGRESS{lbl1} -> set_markup( '<b>Please, wait...</b>' );
		$WINDOWPROGRESS{pb} -> set_text( $msg );
		$WINDOWPROGRESS{pb} -> set_fraction( $partial / $total );
		
		$WINDOWPROGRESS{_GUI} -> show_all;
		Gtk2 -> main_iteration while Gtk2 -> events_pending;
	} else {
		$WINDOWPROGRESS{_GUI} -> hide;
	}
	
	return $WINDOWPROGRESS{_RET};
}

sub _wConfirm {
	my $window	= shift;
	my $msg		= shift;
	
	my $windowConfirm = Gtk2::MessageDialog -> new_with_markup( 
		$window,
		'GTK_DIALOG_DESTROY_WITH_PARENT',
		'GTK_MESSAGE_QUESTION',
		'none',
		$msg
	);   
	$windowConfirm -> add_buttons( 'gtk-ok' => 'yes', 'gtk-cancel'=> 'no');
	$windowConfirm -> set_icon_name( 'pac-app-big' );
	$windowConfirm -> set_title( "Confirm action : $APPNAME (v$APPVERSION)" );
	
	$windowConfirm -> show_all;
	my $close = $windowConfirm -> run;
	$windowConfirm -> destroy;
	
	return ( $close eq 'yes' );
}

sub _wYesNoCancel {
	my $window	= shift;
	my $msg		= shift;
	
	my $windowConfirm = Gtk2::MessageDialog -> new_with_markup( 
		$window,
		'GTK_DIALOG_DESTROY_WITH_PARENT',
		'GTK_MESSAGE_QUESTION',
		'none',
		$msg
	);   
	$windowConfirm -> add_buttons( 'gtk-yes' => 'yes', 'gtk-no'=> 'no', 'gtk-cancel'=> 'cancel');
	$windowConfirm -> set_icon_name( 'pac-app-big' );
	$windowConfirm -> set_title( "Confirm action : $APPNAME (v$APPVERSION)" );
	
	$windowConfirm -> show_all;
	my $close = $windowConfirm -> run;
	$windowConfirm -> destroy;
	
	return ( ( $close eq 'delete-event' ) || ( $close eq 'cancel' ) ) ? 'cancel' : $close;
}

sub _wSetPACPassword {
	my $self	= shift;
	my $ask_old	= shift // 0;
	
	# Ask for old password
	if ( $ask_old ) {
		my $old_pass = _wEnterValue( $self, 'GUI Password Change', "Please, enter *OLD* GUI Password...", undef, 0, 'pac-protected' );
		return 0 unless defined $old_pass;
		
		if ( $CIPHER -> encrypt_hex( $old_pass ) ne $$self{_CFG}{'defaults'}{'gui password'} ) {
			_wMessage( $$self{_WINDOWCONFIG}, "ERROR: Wrong <b>OLD</b> password!!" );
			return 0;
		}
	}
	
	# Ask for new password
	my $new_pass1 = _wEnterValue( $self, '<b>GUI Password Change</b>', "Please, enter *NEW* GUI Password...", undef, 0, 'pac-protected' );
	return 0 unless defined $new_pass1;
	
	# Re-type new password
	my $new_pass2 = _wEnterValue( $self, '<b>GUI Password Change</b>', "Please, repeat *NEW* GUI Password...", undef, 0, 'pac-protected' );
	return 0 unless defined $new_pass2;
	
	if ( $new_pass1 ne $new_pass2 ) {
		_wMessage( $$self{_WINDOWCONFIG}, '<b>ERROR</b>: Provided <b>NEW</b> passwords <span foreground="red"><b>DO NOT MATCH</b></span>!!!' );
		return 0;
	}
	
	$$self{_CFG}{'defaults'}{'gui password'} = $CIPHER -> encrypt_hex( $new_pass1 ) ;
	$PACMain::FUNCS{_MAIN} -> _setCFGChanged( 1 );
	
	return 1;
}

sub _cfgSanityCheck {
	my $cfg = shift;
	
	defined $$cfg{'defaults'} or $$cfg{'defaults'}		= {};
	
	$$cfg{'defaults'}{'version'}						//= $APPVERSION;
	#$$cfg{'defaults'}{'config location'}				//= "$ENV{HOME}/.config/pac";
	$$cfg{'defaults'}{'auto accept key'}				//= 1;
	$$cfg{'defaults'}{'record command history'}			//= 1;
	$$cfg{'defaults'}{'show screenshots'}				//= 1;
	$$cfg{'defaults'}{'back color'}						//= '#000000000000';
	$$cfg{'defaults'}{'close terminal on disconnect'}	//= '';
	$$cfg{'defaults'}{'close to tray'}					//= 0;
	$$cfg{'defaults'}{'color black'}					//= '#000000000000';
	$$cfg{'defaults'}{'color blue'}					//=  '#34346565a4a4';
	$$cfg{'defaults'}{'color bright black'}					//=  '#555557575353';
	$$cfg{'defaults'}{'color bright blue'}					//=  '#72729f9fcfcf';
	$$cfg{'defaults'}{'color bright cyan'}					//=  '#3434e2e2e2e2';
	$$cfg{'defaults'}{'color bright green'}					//=  '#8a8ae2e23434';
	$$cfg{'defaults'}{'color bright magenta'}					//=  '#adad7f7fa8a8';
	$$cfg{'defaults'}{'color bright red'}					//=  '#efef29292929';
	$$cfg{'defaults'}{'color bright white'}					//=  '#eeeeeeeeecec';
	$$cfg{'defaults'}{'color bright yellow'}					//=  '#fcfce9e94f4f';
	$$cfg{'defaults'}{'color cyan'}					//=  '#060698209a9a';
	$$cfg{'defaults'}{'color green'}					//=  '#4e4e9a9a0606';
	$$cfg{'defaults'}{'color magenta'}					//=  '#757550507b7b';
	$$cfg{'defaults'}{'color red'}					//=  '#cccc00000000';
	$$cfg{'defaults'}{'color white'}					//=  '#d3d3d7d7cfcf';
	$$cfg{'defaults'}{'color yellow'}					//=  '#c4c4a0a00000';
	$$cfg{'defaults'}{'command prompt'}					//= '[#%\$>]|\:\/\s*$';
	$$cfg{'defaults'}{'username prompt'}				//= '([l|L]ogin|[u|U]suario|([u|U]ser-?)*[n|N]ame.*|[u|U]ser)\s*:\s*$';
	$$cfg{'defaults'}{'password prompt'}				//= '([p|P]ass|[p|P]ass[w|W]or[d|t](\s+for\s+)*|[c|C]ontrase.a|Enter passphrase for key \'.+\')\s*:\s*$';
	$$cfg{'defaults'}{'hostkey changed prompt'}			//= '^.+ontinue connecting \((.+)\/(.+)\)\?\s*$';
	$$cfg{'defaults'}{'press any key prompt'}			//= '.*(any key to continue|tecla para continuar).*';
	$$cfg{'defaults'}{'remote host changed prompt'}		//= '.*ffending .*key in (.+?)\:(\d+).*';
	$$cfg{'defaults'}{'sudo prompt'}					//= '[__PAC__SUDO__PROMPT__]';
	$$cfg{'defaults'}{'sudo password'}					//= '<<ASK_PASS>>';
	$$cfg{'defaults'}{'sudo show password'}				//= 0;
	$$cfg{'defaults'}{'cursor shape'}					//= 'block';
	$$cfg{'defaults'}{'debug'}							//= 0;
	$$cfg{'defaults'}{'tabs in main window'}			//= 1;
	$$cfg{'defaults'}{'auto hide connections list'}		//= 0;
	$$cfg{'defaults'}{'hide on connect'}				//= 0;
	$$cfg{'defaults'}{'ping port before connect'}		//= 0;
	$$cfg{'defaults'}{'ping port timeout'}				//= 1;
	$$cfg{'defaults'}{'open connections in tabs'}		//= 1;
	$$cfg{'defaults'}{'proxy ip'}						//= '';
	$$cfg{'defaults'}{'proxy pass'}						//= '';
	$$cfg{'defaults'}{'proxy port'}						//= 8080;
	$$cfg{'defaults'}{'proxy user'}						//= '';
	$$cfg{'defaults'}{'shell binary'}					//= $ENV{'SHELL'} // '/bin/bash';
	$$cfg{'defaults'}{'shell options'}					//= '-login';
	$$cfg{'defaults'}{'shell directory'}				//= $ENV{'HOME'};
	$$cfg{'defaults'}{'tabs position'}					//= 'top';
	$$cfg{'defaults'}{'auto save'}						//= 1;
	$$cfg{'defaults'}{'save on exit'}					//= 0;
	$$cfg{'defaults'}{'start iconified'}				//= 0;
	$$cfg{'defaults'}{'start maximized'}				//= 0;
	$$cfg{'defaults'}{'start main maximized'}			//= 0;
	$$cfg{'defaults'}{'start at session startup'}		//= 0;
	$$cfg{'defaults'}{'remember main size'}				//= 1;
	$$cfg{'defaults'}{'show commands box'}				= defined $$cfg{'defaults'}{'show commands box'} ? ( $$cfg{'defaults'}{'show commands box'} || '0' ) : 0;
	$$cfg{'defaults'}{'show global commands box'}		//= 0;
	$$cfg{'defaults'}{'terminal backspace'}				//= 'auto';
	$$cfg{'defaults'}{'terminal transparency'}			//= 0;
	$$cfg{'defaults'}{'terminal font'}					//= 'Monospace 9';
	$$cfg{'defaults'}{'terminal character encoding'}	//= 'UTF-8';
	$$cfg{'defaults'}{'terminal scrollback lines'}		//= 5000;
	$$cfg{'defaults'}{'terminal windows hsize'}			//= 800;
	$$cfg{'defaults'}{'terminal windows vsize'}			//= 600;
	$$cfg{'defaults'}{'terminal show status bar'}		//= 1;
	$$cfg{'defaults'}{'text color'}						//= '#cc62cc62cc62';
	$$cfg{'defaults'}{'bold color'}						//= $$cfg{'defaults'}{'text color'};
	$$cfg{'defaults'}{'bold color like text'}			//= 1;
	$$cfg{'defaults'}{'connected color'}				//= '#0CBA00'; # mid-green
	$$cfg{'defaults'}{'disconnected color'}				//= '#FF0000'; # red
	$$cfg{'defaults'}{'new data color'}					//= '#0088FF'; # blue
	$$cfg{'defaults'}{'timeout command'}				//= 60;
	$$cfg{'defaults'}{'timeout connect'}				//= 40;
	$$cfg{'defaults'}{'use bw icon'}					//= 0;
	$$cfg{'defaults'}{'confirm exit'}					//= 1;
	$$cfg{'defaults'}{'use proxy'}						//= 0;
	$$cfg{'defaults'}{'use system proxy'}				//= 1;
	$$cfg{'defaults'}{'save session logs'}				//= 0;
	$$cfg{'defaults'}{'session log pattern'}			//= '<UUID>_<NAME>_<DATE_Y><DATE_M><DATE_D>_<TIME_H><TIME_M><TIME_S>.txt';
	$$cfg{'defaults'}{'session logs folder'}			//= $CFG_DIR . '/session_logs';
	$$cfg{'defaults'}{'session logs folder'}			=~ s/\/\.pac\//\/\.config\/pac\//g;
	$$cfg{'defaults'}{'session logs amount'}			//= 10;
	$$cfg{'defaults'}{'screenshots external viewer'}	//= '/usr/bin/xdg-open';
	$$cfg{'defaults'}{'screenshots use external viewer'}//= 0;
	$$cfg{'defaults'}{'sort groups first'}				//= 1;
	$$cfg{'defaults'}{'word characters'}				//= '\.:_\/a-zA-Z0-9-';
	$$cfg{'defaults'}{'terminal emulation'}				//= 'xterm';
	$$cfg{'defaults'}{'show tray icon'}					//= 1;
	$$cfg{'defaults'}{'unsplit disconnected terminals'}	//= 0;
	$$cfg{'defaults'}{'confirm chains'}					//= 1;
	$$cfg{'defaults'}{'skip first chain expect'}		//= 1;
	$$cfg{'defaults'}{'enable tree lines'}				//= 0;
	#DevNote: option currently disabled
	$$cfg{'defaults'}{'check versions at start'}		//= 0;
	$$cfg{'defaults'}{'show statistics'}				//= 1;
	$$cfg{'defaults'}{'protected color'}				//= '#FFB022'; #orange
	$$cfg{'defaults'}{'protected set'}					//= 'background';
	if ( $$cfg{'defaults'}{'version'} lt '4.5.0.1' ) {
		$$cfg{'defaults'}{'use gui password'}			= 0;
		$$cfg{'defaults'}{'gui password'}				= '';
	} else {
		$$cfg{'defaults'}{'use gui password'}			//= 0;
		$$cfg{'defaults'}{'gui password'}				//= '';
	}
	$$cfg{'defaults'}{'use gui password tray'}			//= 0;
	$$cfg{'defaults'}{'disable CTRL key bindings'}		//= 0;
	$$cfg{'defaults'}{'disable SHIFT key bindings'}		//= 0;
	$$cfg{'defaults'}{'disable ALT key bindings'}		//= 0;
	$$cfg{'defaults'}{'prevent F11'}					//= 0;
	$$cfg{'defaults'}{'autostart shell upon start'}	//= 0;
	$$cfg{'defaults'}{'tree on right side'}				//= 0;
	$$cfg{'defaults'}{'prevent mouse over show tree'}	//= 1;
	$$cfg{'defaults'}{'start PAC tree on'}				//= 'connections';
	$$cfg{'defaults'}{'show connections tooltips'}		//= 0;
	$$cfg{'defaults'}{'hide connections submenu'}		//= 0;
	$$cfg{'defaults'}{'tree font'}						//= 'Normal';
	$$cfg{'defaults'}{'info font'}						//= 'monospace';
	$$cfg{'defaults'}{'use login shell to connect'}		//= 0;
	$$cfg{'defaults'}{'audible bell'}					//= 0;
	$$cfg{'defaults'}{'visible bell'}					//= 0;
	$$cfg{'defaults'}{'ctrl tab'}						//= 'last';
	$$cfg{'defaults'}{'append group name'}				//= 1;
	$$cfg{'defaults'}{'when no more tabs'}				//= 0;
	$$cfg{'defaults'}{'selection to clipboard'}			//= 1;
	$$cfg{'defaults'}{'how to switch tabs'}				//= 0;
	$$cfg{'defaults'}{'remove control chars'}			//= 0;
	$$cfg{'defaults'}{'allow more instances'}			//= 0;
	$$cfg{'defaults'}{'show favourites in unity'}		//= 0;

	$$cfg{'defaults'}{'global variables'}				//= {};
	$$cfg{'defaults'}{'local commands'}					//= [];
	$$cfg{'defaults'}{'remote commands'}				//= [];
	$$cfg{'defaults'}{'auto cluster'}					//= {};
	
	if ( ! defined $$cfg{'defaults'}{'keepass'} && -f $ENV{'HOME'} . '/.config/keepassx/config.ini' ) {
		open F, $ENV{'HOME'} . '/.config/keepassx/config.ini';
		my @conf = <F>;
		close F;
		my ( $lastfile ) = grep( /^LastFile\=(.+)/, @conf );
		if ( defined $lastfile ) {
			$lastfile =~ s/^LastFile\=\.+\/+(.+)$/$1/gio; chomp $lastfile;
			$$cfg{'defaults'}{'keepass'}{'database'}		= $ENV{'HOME'} . '/' . $lastfile;
			$$cfg{'defaults'}{'keepass'}{'password'}		= '';
			$$cfg{'defaults'}{'keepass'}{'use_keepass'}		= 0;
			$$cfg{'defaults'}{'keepass'}{'ask_user'}		= 1;
		}
	} elsif ( ! defined $$cfg{'defaults'}{'keepass'} ) {
		$$cfg{'defaults'}{'keepass'}{'database'}		= '';
		$$cfg{'defaults'}{'keepass'}{'password'}		= '';
		$$cfg{'defaults'}{'keepass'}{'use_keepass'}		= 0;
		$$cfg{'defaults'}{'keepass'}{'ask_user'}		= 1;
	} else {
		$$cfg{'defaults'}{'keepass'}{'database'}		//= '';
		$$cfg{'defaults'}{'keepass'}{'password'}		//= '';
		$$cfg{'defaults'}{'keepass'}{'use_keepass'}		//= 0;
		$$cfg{'defaults'}{'keepass'}{'ask_user'}		//= 1;
	}
	
	$$cfg{'tmp'}{'changed'}								= 0;
	
	$$cfg{'environments'}{'__PAC_SHELL__'}{'_protected'}			= 0;
	$$cfg{'environments'}{'__PAC_SHELL__'}{'parent'}				= '__PAC__ROOT__';
	$$cfg{'environments'}{'__PAC_SHELL__'}{'name'}					= "PACShell";
	$$cfg{'environments'}{'__PAC_SHELL__'}{'description'}			= "A shell on the local machine";
	$$cfg{'environments'}{'__PAC_SHELL__'}{'title'}					= 'Local';
	$$cfg{'environments'}{'__PAC_SHELL__'}{'ip'}					= 'bash';
	$$cfg{'environments'}{'__PAC_SHELL__'}{'port'}					= 22;
	$$cfg{'environments'}{'__PAC_SHELL__'}{'user'}					= '';
	$$cfg{'environments'}{'__PAC_SHELL__'}{'pass'}					= '';
	$$cfg{'environments'}{'__PAC_SHELL__'}{'search pass on KPX'}	= 0;
	$$cfg{'environments'}{'__PAC_SHELL__'}{'send slow'}				= 0;
	$$cfg{'environments'}{'__PAC_SHELL__'}{'method'}				= 'PACShell';
	$$cfg{'environments'}{'__PAC_SHELL__'}{'auth fallback'}			= 1;
	$$cfg{'environments'}{'__PAC_SHELL__'}{'options'}				= '';
	$$cfg{'environments'}{'__PAC_SHELL__'}{'auth type'}				= 'manual';
	$$cfg{'environments'}{'__PAC_SHELL__'}{'public key'}			= '';
	$$cfg{'environments'}{'__PAC_SHELL__'}{'passphrase user'}		= '';
	$$cfg{'environments'}{'__PAC_SHELL__'}{'passphrase'}			= '';
	$$cfg{'environments'}{'__PAC_SHELL__'}{'use proxy'}				= 0;
	$$cfg{'environments'}{'__PAC_SHELL__'}{'use proxy'}				= '0';
	$$cfg{'environments'}{'__PAC_SHELL__'}{'save session logs'}		= 0;
	$$cfg{'environments'}{'__PAC_SHELL__'}{'session log pattern'}	= 'PACShell_<DATE_Y><DATE_M><DATE_D>_<TIME_H><TIME_M><TIME_S>.txt';
	$$cfg{'environments'}{'__PAC_SHELL__'}{'session logs folder'}	= $CFG_DIR . '/session_logs';
	$$cfg{'environments'}{'__PAC_SHELL__'}{'session logs amount'}	= 10;
	$$cfg{'environments'}{'__PAC_SHELL__'}{'use prepend command'}	= 0;
	$$cfg{'environments'}{'__PAC_SHELL__'}{'prepend command'}		= '';
	$$cfg{'environments'}{'__PAC_SHELL__'}{'quote command'}			= 0;
	$$cfg{'environments'}{'__PAC_SHELL__'}{'send string active'}	= 0;
	$$cfg{'environments'}{'__PAC_SHELL__'}{'send string txt'}		= '';
	$$cfg{'environments'}{'__PAC_SHELL__'}{'send string intro'}		= 1;
	$$cfg{'environments'}{'__PAC_SHELL__'}{'send string every'}		= 60;
	$$cfg{'environments'}{'__PAC_SHELL__'}{'embed'}					= 0;
	$$cfg{'environments'}{'__PAC_SHELL__'}{'mac'}					= '';
	$$cfg{'environments'}{'__PAC_SHELL__'}{'autoreconnect'}			= 0;
	$$cfg{'environments'}{'__PAC_SHELL__'}{'remove control chars'}	= 0;
	$$cfg{'environments'}{'__PAC_SHELL__'}{'startup launch'}		= 0;
	$$cfg{'environments'}{'__PAC_SHELL__'}{'startup script'}		= 0;
	$$cfg{'environments'}{'__PAC_SHELL__'}{'startup script name'}	= '';
	$$cfg{'environments'}{'__PAC_SHELL__'}{'favourite'}				= 0;
	$$cfg{'environments'}{'__PAC_SHELL__'}{'autossh'}				= 0;
	$$cfg{'environments'}{'__PAC_SHELL__'}{'cluster'}				= [];
	$$cfg{'environments'}{'__PAC_SHELL__'}{'variables'}				= [];
	$$cfg{'environments'}{'__PAC_SHELL__'}{'screenshots'}			= [];
	$$cfg{'environments'}{'__PAC_SHELL__'}{'local before'}			= [];
	$$cfg{'environments'}{'__PAC_SHELL__'}{'expect'}				= [];
	$$cfg{'environments'}{'__PAC_SHELL__'}{'local connected'}		= [];
	$$cfg{'environments'}{'__PAC_SHELL__'}{'macros'}				= [];
	$$cfg{'environments'}{'__PAC_SHELL__'}{'local after'}			= [];
	$$cfg{'environments'}{'__PAC_SHELL__'}{'terminal options'}{'use tab back color'}			//= 0;
	$$cfg{'environments'}{'__PAC_SHELL__'}{'terminal options'}{'tab back color'}				//= '#000000000000'; # Black
	$$cfg{'environments'}{'__PAC_SHELL__'}{'terminal options'}{'back color'}					//= '#000000000000'; # Black
	$$cfg{'environments'}{'__PAC_SHELL__'}{'terminal options'}{'command prompt'}				//= '(\]\#|\$\s)+';
	$$cfg{'environments'}{'__PAC_SHELL__'}{'terminal options'}{'username prompt'}				//= '([l|L]ogin|[u|u]suario|[u|U]ser-?[n|N]ame|[u|U]ser):\s*$';
	$$cfg{'environments'}{'__PAC_SHELL__'}{'terminal options'}{'password prompt'}				//= '([p|P]ass|[p|P]ass[w|W]or[d|t]|ontrase.a|Enter passphrase for key \'.+\'):\s*$';
	$$cfg{'environments'}{'__PAC_SHELL__'}{'terminal options'}{'cursor shape'}					//= 'block';
	$$cfg{'environments'}{'__PAC_SHELL__'}{'terminal options'}{'open in tab'}					//= 1;
	$$cfg{'environments'}{'__PAC_SHELL__'}{'terminal options'}{'terminal font'}					//= 'Monospace 9';
	$$cfg{'environments'}{'__PAC_SHELL__'}{'terminal options'}{'terminal emulation'}			//= 'xterm';
	$$cfg{'environments'}{'__PAC_SHELL__'}{'terminal options'}{'terminal backspace'}			//= 'auto';
	$$cfg{'environments'}{'__PAC_SHELL__'}{'terminal options'}{'terminal select words'}			//= '\.:_\/-A-Za-z0-9';
	$$cfg{'environments'}{'__PAC_SHELL__'}{'terminal options'}{'terminal character encoding'}	//= 'UTF-8';
	$$cfg{'environments'}{'__PAC_SHELL__'}{'terminal options'}{'terminal scrollback lines'}		//= 5000;
	$$cfg{'environments'}{'__PAC_SHELL__'}{'terminal options'}{'terminal transparency'}			//= 0;
	$$cfg{'environments'}{'__PAC_SHELL__'}{'terminal options'}{'terminal window hsize'}			//= 800;
	$$cfg{'environments'}{'__PAC_SHELL__'}{'terminal options'}{'terminal window vsize'}			//= 600;
	$$cfg{'environments'}{'__PAC_SHELL__'}{'terminal options'}{'text color'}					//= '#cc62cc62cc62';
	$$cfg{'environments'}{'__PAC_SHELL__'}{'terminal options'}{'bold color'}					//= $$cfg{'environments'}{'__PAC_SHELL__'}{'terminal options'}{'text color'};
	$$cfg{'environments'}{'__PAC_SHELL__'}{'terminal options'}{'bold color like text'}			//= 1;
	$$cfg{'environments'}{'__PAC_SHELL__'}{'terminal options'}{'timeout command'}				//= 40;
	$$cfg{'environments'}{'__PAC_SHELL__'}{'terminal options'}{'timeout connect'}				//= 40;
	$$cfg{'environments'}{'__PAC_SHELL__'}{'terminal options'}{'use personal settings'}			//= 0;
	$$cfg{'environments'}{'__PAC_SHELL__'}{'terminal options'}{'disable CTRL key bindings'}		//= 0;
	$$cfg{'environments'}{'__PAC_SHELL__'}{'terminal options'}{'disable ALT key bindings'}		//= 0;
	$$cfg{'environments'}{'__PAC_SHELL__'}{'terminal options'}{'disable SHIFT key bindings'}	//= 0;
	$$cfg{'environments'}{'__PAC_SHELL__'}{'terminal options'}{'audible bell'}					//= 0;
	$$cfg{'environments'}{'__PAC_SHELL__'}{'terminal options'}{'visible bell'}					//= 0;
	
	foreach my $uuid ( keys %{ $$cfg{'environments'} } ) {
		if ( $uuid =~ /^HASH/go ) {
			delete $$cfg{'environments'}{$uuid};
			next;
		} elsif( $uuid =~ /^_tmp_/go ) {
			delete $$cfg{'environments'}{$uuid};
			next;
		} elsif ( $uuid =~ /^pacshell_PID/go ) {
			delete $$cfg{'environments'}{$uuid};
			next;
		} elsif ( ! $uuid ) {
			delete $$cfg{'environments'}{$uuid};
			next;
		} elsif ( ! defined $$cfg{'environments'}{$uuid}{'name'} && $uuid ne '__PAC__ROOT__' ) {
			delete $$cfg{'environments'}{$uuid};
			next;
		} elsif ( $$cfg{'environments'}{$uuid}{'_is_group'} ) {
			my $name		= $$cfg{'environments'}{$uuid}{'name'};
			my $description	= $$cfg{'environments'}{$uuid}{'description'};
			my $children	= dclone( $$cfg{'environments'}{$uuid}{'children'} );
			my $parent		= $$cfg{'environments'}{$uuid}{'parent'};
			my @screenshots = @{ $$cfg{'environments'}{$uuid}{'screenshots'} // [] };
			my $protected	= $$cfg{'environments'}{$uuid}{'_protected'} // 0;
			delete $$cfg{'environments'}{$uuid};
			$$cfg{'environments'}{$uuid}{'_is_group'}			= 1;
			$$cfg{'environments'}{$uuid}{'name'}				= $name;
			$$cfg{'environments'}{$uuid}{'description'}			= $description;
			$$cfg{'environments'}{$uuid}{'parent'}				= $parent;
			$$cfg{'environments'}{$uuid}{'children'} 			= $children;
			@{ $$cfg{'environments'}{$uuid}{'screenshots'} }	= @screenshots;
			$$cfg{'environments'}{$uuid}{'_protected'} 			= $protected;
			
			foreach ( @{ $$cfg{'environments'}{$uuid}{'screenshots'} } ) { $_ =~ s/\/\.pac\//\/\.config\/pac\//g; }
			
			next;
		}
		
		next unless defined $$cfg{'environments'}{$uuid}{'name'};
		
		$$cfg{'environments'}{$uuid}{'_protected'}			//= 0;
		$$cfg{'environments'}{$uuid}{'parent'}				//= '__PAC__ROOT__';
		$$cfg{'environments'}{$uuid}{'description'}			//= "Connection with '$$cfg{'environments'}{$uuid}{'name'}'";
		$$cfg{'environments'}{$uuid}{'title'}				//= $$cfg{'environments'}{$uuid}{'name'};
		$$cfg{'environments'}{$uuid}{'ip'}					//= '';
		$$cfg{'environments'}{$uuid}{'port'}				= defined $$cfg{'environments'}{$uuid}{'port'} ? $$cfg{'environments'}{$uuid}{'port'} || '0' : 22;
		$$cfg{'environments'}{$uuid}{'user'}				//= '';
		$$cfg{'environments'}{$uuid}{'pass'}				//= '';
		$$cfg{'environments'}{$uuid}{'search pass on KPX'}	//= 0;
		$$cfg{'environments'}{$uuid}{'KPX title regexp'}	//= ".*$$cfg{'environments'}{$uuid}{'title'}.*";
		$$cfg{'environments'}{$uuid}{'send slow'}			//= 0;
		$$cfg{'environments'}{$uuid}{'method'}				//= 'SSH';
		$$cfg{'environments'}{$uuid}{'method'}				= 'SSH'					if $$cfg{'environments'}{$uuid}{'method'} =~ /^.*ssh.*$/go;
		$$cfg{'environments'}{$uuid}{'method'}				= 'SFTP'				if $$cfg{'environments'}{$uuid}{'method'} =~ /^.*sftp.*$/go;
		$$cfg{'environments'}{$uuid}{'method'}				= 'Telnet'				if $$cfg{'environments'}{$uuid}{'method'} =~ /^.*telnet.*$/go;
		$$cfg{'environments'}{$uuid}{'method'}				= 'FTP'					if $$cfg{'environments'}{$uuid}{'method'} =~ /^.*ftp.*$/go;
		$$cfg{'environments'}{$uuid}{'method'}				= 'Serial (cu)'			if $$cfg{'environments'}{$uuid}{'method'} =~ /^.*cu$/go;
		$$cfg{'environments'}{$uuid}{'method'}				= 'Serial (remote-tty)'	if $$cfg{'environments'}{$uuid}{'method'} =~ /^.*remote-tty.*$/go;
		$$cfg{'environments'}{$uuid}{'method'}				= 'IBM 3270/5250'		if $$cfg{'environments'}{$uuid}{'method'} =~ /^.*3270.*$/go;
		$$cfg{'environments'}{$uuid}{'method'}				= 'RDP (rdesktop)'		if $$cfg{'environments'}{$uuid}{'method'} eq 'RDP (Windows)';
		$$cfg{'environments'}{$uuid}{'method'}				= 'VNC'					if $$cfg{'environments'}{$uuid}{'method'} =~ /^.*vncviewer.*$/go;
		$$cfg{'environments'}{$uuid}{'method'}				= 'Generic Command'		if $$cfg{'environments'}{$uuid}{'method'} =~ /^.*generic.*$/go;
		$$cfg{'environments'}{$uuid}{'auth fallback'}		//= 1;
		$$cfg{'environments'}{$uuid}{'options'}				//= '';
		if ( $$cfg{'environments'}{$uuid}{'method'} eq 'SSH' ) {
			$$cfg{'environments'}{$uuid}{'options'} =~ s/(-[DLR])\s+(.*?)\/(.*?)\/(.*?)\/(.*?)/$1 $2:$3:$4:$5/go;
		}
		if ( $$cfg{'environments'}{$uuid}{'options'} =~ s/\s+\-o\s+\"IdentityFile(\s+|\s*=\s*)(.+)\"//gio ) {
			my $idfile = $2;
			$$cfg{'environments'}{$uuid}{'auth type'}		= 'publickey';
			$$cfg{'environments'}{$uuid}{'passphrase user'}	//= $$cfg{'environments'}{$uuid}{'user'} // '';
			$$cfg{'environments'}{$uuid}{'passphrase'}		//= $$cfg{'environments'}{$uuid}{'pass'} // '';
			$$cfg{'environments'}{$uuid}{'public key'}		= $idfile;
		}
		$$cfg{'environments'}{$uuid}{'auth type'}			//= $$cfg{'environments'}{$uuid}{'manual'} // '0' ? 'manual' : 'userpass';
		$$cfg{'environments'}{$uuid}{'public key'}			//= '';
		$$cfg{'environments'}{$uuid}{'passphrase user'}		//= '';
		$$cfg{'environments'}{$uuid}{'passphrase'}			//= '';
		$$cfg{'environments'}{$uuid}{'use proxy'}			//= 0;
		$$cfg{'environments'}{$uuid}{'use proxy'}			||= '0';
		$$cfg{'environments'}{$uuid}{'proxy ip'}			//= '';
		$$cfg{'environments'}{$uuid}{'proxy port'}			//= 8080;
		$$cfg{'environments'}{$uuid}{'proxy user'}			//= '';
		$$cfg{'environments'}{$uuid}{'proxy pass'}			//= '';
		$$cfg{'environments'}{$uuid}{'save session logs'}	//= 0;
		$$cfg{'environments'}{$uuid}{'session log pattern'}	//= '<UUID>_<NAME>_<DATE_Y><DATE_M><DATE_D>_<TIME_H><TIME_M><TIME_S>.txt';
		$$cfg{'environments'}{$uuid}{'session logs folder'}	//= $CFG_DIR . '/session_logs';
		$$cfg{'environments'}{$uuid}{'session logs folder'}	=~ s/\/\.pac\//\/\.config\/pac\//g;
		$$cfg{'environments'}{$uuid}{'session logs amount'}	//= 10;
		$$cfg{'environments'}{$uuid}{'use prepend command'}	//= 0;
		$$cfg{'environments'}{$uuid}{'prepend command'}		//= '';
		$$cfg{'environments'}{$uuid}{'quote command'}		//= 0;
		$$cfg{'environments'}{$uuid}{'send string active'}	//= 0;
		$$cfg{'environments'}{$uuid}{'send string txt'}		//= '';
		$$cfg{'environments'}{$uuid}{'send string intro'}	//= 1;
		$$cfg{'environments'}{$uuid}{'send string every'}	//= 60;
		$$cfg{'environments'}{$uuid}{'embed'}				//= 0;
		$$cfg{'environments'}{$uuid}{'mac'}					//= '';
		$$cfg{'environments'}{$uuid}{'autoreconnect'}		//= 0;
		$$cfg{'environments'}{$uuid}{'startup launch'}		//= 0;
		$$cfg{'environments'}{$uuid}{'startup script'}		//= 0;
		$$cfg{'environments'}{$uuid}{'startup script name'}	//= '';
		$$cfg{'environments'}{$uuid}{'favourite'}			//= 0;
		$$cfg{'environments'}{$uuid}{'remove control chars'}//= 0;
		$$cfg{'environments'}{$uuid}{'autossh'}				//= 0;
		$$cfg{'environments'}{$uuid}{'cluster'}				//= [];
		$$cfg{'environments'}{$uuid}{'use sudo'}			//= 0;
		
		if ( ! defined $$cfg{'environments'}{$uuid}{'variables'} ) {
			$$cfg{'environments'}{$uuid}{'variables'}		=[];
		} else {
			my $i = 0;
			foreach my $hash ( @{ $$cfg{'environments'}{$uuid}{'variables'} } ) {
				if ( ! ref( $hash ) ) {
					delete $$cfg{'environments'}{$uuid}{'variables'}[$i];
					$$cfg{'environments'}{$uuid}{'variables'}[$i]{'hide'} = 0;
					$$cfg{'environments'}{$uuid}{'variables'}[$i]{'txt'} = $hash // '';
				} else {
					$$hash{'hide'}	//= 0;
					$$hash{'txt'}	//= '';
				}
				++$i;
			}
		}
		
		if ( ! defined $$cfg{'environments'}{$uuid}{'screenshots'} ) {
			$$cfg{'environments'}{$uuid}{'screenshots'} = [];
			if ( defined $$cfg{'environments'}{$uuid}{'screenshot'} ) {
				push( @{ $$cfg{'environments'}{$uuid}{'screenshots'} }, $$cfg{'environments'}{$uuid}{'screenshot'} ) unless ! -f $$cfg{'environments'}{$uuid}{'screenshot'};
			}
			delete $$cfg{'environments'}{$uuid}{'screenshot'};
		} else {
			foreach ( @{ $$cfg{'environments'}{$uuid}{'screenshots'} } ) { $_ =~ s/\/\.pac\//\/\.config\/pac\//g; }
			defined $$cfg{'environments'}{$uuid}{'screenshot'} and delete $$cfg{'environments'}{$uuid}{'screenshot'};
		}
		
		if ( ! defined $$cfg{'environments'}{$uuid}{'local before'} ) {
			$$cfg{'environments'}{$uuid}{'local before'} = [];
		} else {
			my $i = 0;
			foreach my $hash ( @{ $$cfg{'environments'}{$uuid}{'local before'} } ) {
				if ( ! ref( $hash ) ) {
					delete $$cfg{'environments'}{$uuid}{'local before'}[$i];
					$$cfg{'environments'}{$uuid}{'local before'}[$i]{'default'} //= 1;
					$$cfg{'environments'}{$uuid}{'local before'}[$i]{'ask'} = 1;
					$$cfg{'environments'}{$uuid}{'local before'}[$i]{'command'} = $hash // '';
				} else {
					$$hash{'ask'}		//= 1;
					$$hash{'default'}	//= 1;
					$$hash{'command'}	//= '';
				}
				++$i;
			}
		}
		
		if ( ! defined $$cfg{'environments'}{$uuid}{'expect'} ) {
			$$cfg{'environments'}{$uuid}{'expect'} = [];
		} else {
			my $i = 0;
			foreach my $hash ( @{ $$cfg{'environments'}{$uuid}{'expect'} } ) {
				if ( ! ref( $hash ) ) {
					delete $$cfg{'environments'}{$uuid}{'expect'}[$i];
					$$cfg{'environments'}{$uuid}{'expect'}[$i]{'active'} = 1;
					$$cfg{'environments'}{$uuid}{'expect'}[$i]{'expect'} = '';
					$$cfg{'environments'}{$uuid}{'expect'}[$i]{'send'} = '';
					$$cfg{'environments'}{$uuid}{'expect'}[$i]{'hidden'} = 0;
					$$cfg{'environments'}{$uuid}{'expect'}[$i]{'return'} = 1;
					$$cfg{'environments'}{$uuid}{'expect'}[$i]{'on_match'} = -1;
					$$cfg{'environments'}{$uuid}{'expect'}[$i]{'on_fail'} = -1;
					$$cfg{'environments'}{$uuid}{'expect'}[$i]{'time_out'} = -1;
				} else {
					$$hash{'active'}	//= 1;
					$$hash{'expect'}	//= '';
					$$hash{'hidden'}	//= 0;
					$$hash{'send'}		//= '';
					$$hash{'return'}	//= 1;
					$$hash{'on_match'}	//= -1;
					$$hash{'on_fail'}	//= -1;
					$$hash{'time_out'}	//= -1;
				}
				++$i;
			}
		}
		
		if ( ! defined $$cfg{'environments'}{$uuid}{'local connected'} ) {
			$$cfg{'environments'}{$uuid}{'local connected'} = [];
		} else {
			my $i = 0;
			foreach my $hash ( @{ $$cfg{'environments'}{$uuid}{'local connected'} } ) {
				if ( ! ref( $hash ) ) {
					delete $$cfg{'environments'}{$uuid}{'local connected'}[$i];
					$$cfg{'environments'}{$uuid}{'local connected'}[$i]{'confirm'} = 0;
					$$cfg{'environments'}{$uuid}{'local connected'}[$i]{'txt'} = $hash // '';
				} else {
					$$hash{'confirm'} //= 0;
					$$hash{'txt'} //= '';
				}
				++$i;
			}
		}
		
		if ( ! defined $$cfg{'environments'}{$uuid}{'macros'} ) {
			$$cfg{'environments'}{$uuid}{'macros'} = [];
		} else {
			my $i = 0;
			foreach my $hash ( @{ $$cfg{'environments'}{$uuid}{'macros'} } ) {
				if ( ! ref( $hash ) ) {
					delete $$cfg{'environments'}{$uuid}{'macros'}[$i];
					$$cfg{'environments'}{$uuid}{'macros'}[$i]{'confirm'} = 0;
					$$cfg{'environments'}{$uuid}{'macros'}[$i]{'intro'} = 1;
					$$cfg{'environments'}{$uuid}{'macros'}[$i]{'txt'} = $hash // '';
				} else {
					$$hash{'confirm'} //= 0;
					$$hash{'intro'} //= 1;
					$$hash{'txt'} //= '';
				}
				++$i;
			}
		}
		
		if ( ! defined $$cfg{'environments'}{$uuid}{'local after'} ) {
			$$cfg{'environments'}{$uuid}{'local after'} = [];
		} else {
			my $i = 0;
			foreach my $hash ( @{ $$cfg{'environments'}{$uuid}{'local after'} } ) {
				if ( ! ref( $hash ) ) {
					delete $$cfg{'environments'}{$uuid}{'local after'}[$i];
					$$cfg{'environments'}{$uuid}{'local after'}[$i]{'default'} = 1;
					$$cfg{'environments'}{$uuid}{'local after'}[$i]{'ask'} = 1;
					$$cfg{'environments'}{$uuid}{'local after'}[$i]{'command'} = $hash // '';
				} else {
					$$hash{'ask'}		//= 1;
					$$hash{'default'}	//= 1;
					$$hash{'command'}	//= '';
				}
				++$i;
			}
		}
		if ( ! defined $$cfg{'environments'}{$uuid}{'terminal options'} ) {
			$$cfg{'environments'}{$uuid}{'terminal options'}{'use tab back color'}			= 0;
			$$cfg{'environments'}{$uuid}{'terminal options'}{'tab back color'}				= '#000000000000'; # Black
			$$cfg{'environments'}{$uuid}{'terminal options'}{'back color'}					= '#000000000000'; # Black
			$$cfg{'environments'}{$uuid}{'terminal options'}{'command prompt'}				= '[#%\$>]|\:\/\s*$';
			$$cfg{'environments'}{$uuid}{'terminal options'}{'username prompt'}				= '([l|L]ogin|[u|u]suario|[u|U]ser-?[n|N]ame|[u|U]ser):\s*$';
			$$cfg{'environments'}{$uuid}{'terminal options'}{'password prompt'}				= '([p|P]ass|[p|P]ass[w|W]or[d|t]|ontrase.a|Enter passphrase for key \'.+\'):\s*$';
			$$cfg{'environments'}{$uuid}{'terminal options'}{'cursor shape'} 				= 'block';
			$$cfg{'environments'}{$uuid}{'terminal options'}{'open in tab'}					= 1;
			$$cfg{'environments'}{$uuid}{'terminal options'}{'terminal font'}				= 'Monospace 9';
			$$cfg{'environments'}{$uuid}{'terminal options'}{'terminal select words'}		= '\.:_\/-A-Za-z0-9';
			$$cfg{'environments'}{$uuid}{'terminal options'}{'terminal emulation'}			= 'xterm';
			$$cfg{'environments'}{$uuid}{'terminal options'}{'terminal backspace'}			= 'auto';
			$$cfg{'environments'}{$uuid}{'terminal options'}{'terminal character encoding'}	= 'UTF-8';
			$$cfg{'environments'}{$uuid}{'terminal options'}{'terminal scrollback lines'}	= 5000;
			$$cfg{'environments'}{$uuid}{'terminal options'}{'terminal transparency'}		= 0;
			$$cfg{'environments'}{$uuid}{'terminal options'}{'terminal window hsize'}		= 800;
			$$cfg{'environments'}{$uuid}{'terminal options'}{'terminal window vsize'}		= 600;
			$$cfg{'environments'}{$uuid}{'terminal options'}{'text color'}					= '#cc62cc62cc62';
			$$cfg{'environments'}{$uuid}{'terminal options'}{'bold color'}					= $$cfg{'environments'}{$uuid}{'terminal options'}{'text color'};
			$$cfg{'environments'}{$uuid}{'terminal options'}{'bold color like text'}		= 1;
			$$cfg{'environments'}{$uuid}{'terminal options'}{'timeout command'}				= 40;
			$$cfg{'environments'}{$uuid}{'terminal options'}{'timeout connect'}				= 40;
			$$cfg{'environments'}{$uuid}{'terminal options'}{'use personal settings'}		= 0;
			$$cfg{'environments'}{$uuid}{'terminal options'}{'disable CTRL key bindings'}	= 0;
			$$cfg{'environments'}{$uuid}{'terminal options'}{'disable ALT key bindings'}	= 0;
			$$cfg{'environments'}{$uuid}{'terminal options'}{'disable SHIFT key bindings'}	= 0;
		} else {
			$$cfg{'environments'}{$uuid}{'terminal options'}{'use tab back color'}			//= 0;
			$$cfg{'environments'}{$uuid}{'terminal options'}{'tab back color'}				//= '#000000000000'; # Black
			$$cfg{'environments'}{$uuid}{'terminal options'}{'back color'}					//= '#000000000000'; # Black
			$$cfg{'environments'}{$uuid}{'terminal options'}{'command prompt'}				//= '(\]\#|\$\s)+';
			$$cfg{'environments'}{$uuid}{'terminal options'}{'username prompt'}				//= '([l|L]ogin|[u|u]suario|[u|U]ser-?[n|N]ame|[u|U]ser):\s*$';
			$$cfg{'environments'}{$uuid}{'terminal options'}{'password prompt'}				//= '([p|P]ass|[p|P]ass[w|W]or[d|t]|ontrase.a|Enter passphrase for key \'.+\'):\s*$';
			$$cfg{'environments'}{$uuid}{'terminal options'}{'cursor shape'}				//= 'block';
			$$cfg{'environments'}{$uuid}{'terminal options'}{'open in tab'}					//= 1;
			$$cfg{'environments'}{$uuid}{'terminal options'}{'terminal font'}				//= 'Monospace 9';
			$$cfg{'environments'}{$uuid}{'terminal options'}{'terminal select words'}		//= '\.:_\/-A-Za-z0-9';
			$$cfg{'environments'}{$uuid}{'terminal options'}{'terminal emulation'}			//= 'xterm';
			$$cfg{'environments'}{$uuid}{'terminal options'}{'terminal backspace'}			//= 'auto';
			$$cfg{'environments'}{$uuid}{'terminal options'}{'terminal character encoding'}	//= 'UTF-8';
			$$cfg{'environments'}{$uuid}{'terminal options'}{'terminal scrollback lines'}	//= 5000;
			$$cfg{'environments'}{$uuid}{'terminal options'}{'terminal transparency'}		//= 0;
			$$cfg{'environments'}{$uuid}{'terminal options'}{'terminal window hsize'}		//= 800;
			$$cfg{'environments'}{$uuid}{'terminal options'}{'terminal window vsize'}		//= 600;
			$$cfg{'environments'}{$uuid}{'terminal options'}{'text color'}					//= '#cc62cc62cc62';
			$$cfg{'environments'}{$uuid}{'terminal options'}{'bold color'}					//= $$cfg{'environments'}{$uuid}{'terminal options'}{'text color'};
			$$cfg{'environments'}{$uuid}{'terminal options'}{'bold color like text'}		//= 1;
			$$cfg{'environments'}{$uuid}{'terminal options'}{'timeout command'}				//= 40;
			$$cfg{'environments'}{$uuid}{'terminal options'}{'timeout connect'}				//= 40;
			$$cfg{'environments'}{$uuid}{'terminal options'}{'use personal settings'}		//= 0;
			$$cfg{'environments'}{$uuid}{'terminal options'}{'disable CTRL key bindings'}	//= 0;
			$$cfg{'environments'}{$uuid}{'terminal options'}{'disable ALT key bindings'}	//= 0;
			$$cfg{'environments'}{$uuid}{'terminal options'}{'disable SHIFT key bindings'}	//= 0;
			$$cfg{'environments'}{$uuid}{'terminal options'}{'audible bell'}				//= 0;
			$$cfg{'environments'}{$uuid}{'terminal options'}{'visible bell'}				//= 0;
		}
	}
	
	return 1;
}

sub _updateSSHToIPv6 {
	my $cmd_line = shift // '';
	
	my %hash;
	$hash{sshVersion}				= 'any';
	$hash{ipVersion}				= 'any';
	$hash{forwardX}					= 1;
	$hash{useCompression}			= 0;
	$hash{allowRemoteConnection}	= 0;
	$hash{forwardAgent}				= 0;
	$hash{otherOptions}				= '';
	@{ $hash{dynamicForward} }		= ();
	@{ $hash{forwardPort} }			= ();
	@{ $hash{remotePort} }			= ();
	
	while ( $cmd_line =~ s/\s*\-o\s+\"(.+)\"//go )	{ $hash{otherOptions} .= ' -o "' . $1 . '"'}
	my @opts = split( /\s+-/, $cmd_line );
	foreach my $opt ( @opts ) {
		next unless $opt ne '';
		$opt =~ s/\s+$//go;
		
		$opt =~ /^([1|2]$)/go				and	$hash{sshVersion}							= $1;
		$opt =~ /^([4|6]$)/go				and	$hash{ipVersion}							= $1;
		$opt =~ /^([X|x]$)/go				and	$hash{forwardX}								= $1 eq 'X' ? 1 : 0;
		$opt eq 'C'							and	$hash{useCompression}						= 1;
		$opt eq 'g'							and	$hash{allowRemoteConnection}				= 1;
		$opt eq 'A'							and	$hash{forwardAgent}							= 1;
		
		while ( $opt =~ /^D\s+([^\s]*:)*(\d+)$/go ) {
			my %dynamic;
			( $dynamic{dynamicIP}, $dynamic{dynamicPort} ) = ( $1 // '', $2 );
			$dynamic{dynamicIP} =~ s/:+//go;
			push( @{ $hash{dynamicForward} }, \%dynamic );
		}
		while ( $opt =~ /^L\s+(.+)$/go ) {
			my @fields = split( ':', $1 );
			my %forward;
			$forward{remotePort}	= pop( @fields );
			$forward{remoteIP}		= pop( @fields );
			$forward{localPort}		= pop( @fields );
			$forward{localIP}		= pop( @fields ) // '';
			push( @{ $hash{forwardPort} }, \%forward );
		}
		while ( $opt =~ /^R\s+(.+)$/go ) {
			my @fields = split( ':', $1 );
			my %remote;
			$remote{remotePort}	= pop( @fields );
			$remote{remoteIP}	= pop( @fields );
			$remote{localPort}	= pop( @fields );
			$remote{localIP}	= pop( @fields ) // '';
			push( @{ $hash{remotePort} }, \%remote );
		}
	}
	
	my $txt = '';
	
	$txt .= ' -' . $hash{sshVersion} unless $hash{sshVersion} eq 'any';
	$txt .= ' -' . $hash{ipVersion} unless $hash{ipVersion} eq 'any';
	$txt .= ' -' . ( $hash{forwardX} ? 'X' : 'x' );
	$txt .= ' -C' if $hash{useCompression} ;
	$txt .= ' -g' if $hash{allowRemoteConnection};
	$txt .= ' -A' if $hash{forwardAgent};
	$txt .= ' ' . $hash{otherOptions} if $hash{otherOptions};
	foreach my $dynamic ( @{ $hash{dynamicForward} } ) {
		$txt .= ' -D ' . ( $$dynamic{dynamicIP} ? "$$dynamic{dynamicIP}/" : '' ) . $$dynamic{dynamicPort};
	}
	foreach my $forward ( @{ $hash{forwardPort} } ) {
		$txt .= ' -L ' . ( $$forward{localIP} ? "$$forward{localIP}/" : '' ) . $$forward{localPort} . '/' . $$forward{remoteIP} . '/' . $$forward{remotePort};
	}
	foreach my $remote ( @{ $hash{remotePort} } ) {
		$txt .= ' -R ' . ( $$remote{localIP} ? "$$remote{localIP}/" : '' ) . $$remote{localPort} . '/' . $$remote{remoteIP} . '/' . $$remote{remotePort};
	}
	
	return $txt;
}

sub _cipherCFG {
	my $cfg = shift;
	
	foreach my $var ( keys %{ $$cfg{'defaults'}{'global variables'} } ) {
		( $$cfg{'defaults'}{'global variables'}{$var}{'hidden'} eq '1' ) and $$cfg{'defaults'}{'global variables'}{$var}{'value'} = $CIPHER -> encrypt_hex( encode( 'utf8', $$cfg{'defaults'}{'global variables'}{$var}{'value'} ) );
	}
	
	defined $$cfg{'defaults'}{'keepass'} and $$cfg{'defaults'}{'keepass'}{'password'} = $CIPHER -> encrypt_hex( encode( 'utf8', $$cfg{'defaults'}{'keepass'}{'password'} ) );
	$$cfg{'defaults'}{'sudo password'} = $CIPHER -> encrypt_hex( encode( 'utf8', $$cfg{'defaults'}{'sudo password'} ) );
	
	foreach my $uuid ( keys %{ $$cfg{'environments'} } ) {
		if ( $uuid =~ /^HASH/go ) {
			delete $$cfg{'environments'}{$uuid};
			next
		}
		elsif ( $$cfg{'environments'}{$uuid}{'_is_group'} ) {
			delete $$cfg{'environments'}{$uuid}{'pass'};
			next;
		}
		$$cfg{'environments'}{$uuid}{'pass'}		= $CIPHER -> encrypt_hex( encode( 'utf8', $$cfg{'environments'}{$uuid}{'pass'} ) );
		$$cfg{'environments'}{$uuid}{'passphrase'}	= $CIPHER -> encrypt_hex( encode( 'utf8', $$cfg{'environments'}{$uuid}{'passphrase'} ) );
		
		foreach my $hash ( @{ $$cfg{'environments'}{$uuid}{'expect'} } ) {
			( $$hash{'hidden'} eq '1' ) and $$hash{'send'} = $CIPHER -> encrypt_hex( encode( 'utf8', $$hash{'send'} ) );
		}
	
		foreach my $hash ( @{ $$cfg{'environments'}{$uuid}{'variables'} } ) {
			( $$hash{'hide'} eq '1' ) and $$hash{'txt'} = $CIPHER -> encrypt_hex( encode( 'utf8', $$hash{'txt'} ) );
		}
	}
	
	return 1;
}

sub _decipherCFG {
	my $cfg			= shift;
	my $single_uuid	= shift // 0;
	
	if ( ! $single_uuid ) {
		foreach my $var ( keys %{ $$cfg{'defaults'}{'global variables'} } ) {
			( $$cfg{'defaults'}{'global variables'}{$var}{'hidden'} eq '1' ) and eval { $$cfg{'defaults'}{'global variables'}{$var}{'value'} = decode( 'utf8', $CIPHER -> decrypt_hex( $$cfg{'defaults'}{'global variables'}{$var}{'value'} ) ); };
		}
	}
	
	defined $$cfg{'defaults'}{'keepass'} and eval { $$cfg{'defaults'}{'keepass'}{'password'} = decode( 'utf8', $CIPHER -> decrypt_hex( $$cfg{'defaults'}{'keepass'}{'password'} ) ); };
	eval { $$cfg{'defaults'}{'sudo password'} = decode( 'utf8', $CIPHER -> decrypt_hex( $$cfg{'defaults'}{'sudo password'} ) ); };
	
	foreach my $uuid ( keys %{ $$cfg{'environments'} } ) {
		$single_uuid and next unless $single_uuid eq $uuid;
		
		if ( $$cfg{'environments'}{$uuid}{'_is_group'} ) {
			delete $$cfg{'environments'}{$uuid}{'pass'};
			next;
		}
		eval { $$cfg{'environments'}{$uuid}{'pass'}			= decode( 'utf8', $CIPHER -> decrypt_hex( $$cfg{'environments'}{$uuid}{'pass'} ) ); };
		eval { $$cfg{'environments'}{$uuid}{'passphrase'}	= decode( 'utf8', $CIPHER -> decrypt_hex( $$cfg{'environments'}{$uuid}{'passphrase'} ) ); };
		
		foreach my $hash ( @{ $$cfg{'environments'}{$uuid}{'expect'} } ) {
			( $$hash{'hidden'} eq '1' ) and eval { $$hash{'send'} = decode( 'utf8', $CIPHER -> decrypt_hex( $$hash{'send'} ) ); };
		}
		
		foreach my $hash ( @{ $$cfg{'environments'}{$uuid}{'variables'} } ) {
			( $$hash{'hide'} eq '1' ) and eval { $$hash{'txt'} = decode( 'utf8', $CIPHER -> decrypt_hex( $$hash{'txt'} ) ); };
		}
	}
	
	return 1;
}

sub _substCFG {
	my $cfg		= shift;
	my $list	= shift;
	
	foreach my $key ( keys %{ $cfg } ) {
		next if ( $key =~ /^(variables|screenshots|local before|local connected|local after|expect|macros|terminal options)$/go );
		next unless defined $$list{$key};
		next unless $$list{$key}{'change'};
		
		if ( $$list{$key}{'regexp'} // 0 ) {
			$$cfg{$key} =~ s/$$list{$key}{'match'}/"'\"$$list{$key}{value}\"'"/eeeg;
		} else {
			$$cfg{$key} = $$list{$key}{'value'};
		}
	}
	
	if ( ( defined $$list{'EXPECT:expect'} ) && ( $$list{'EXPECT:expect'}{'change'} ) ){
		foreach my $exp ( @{ $$cfg{'expect'} } ) {
			if ( $$list{'EXPECT:expect'}{'regexp'} // 0 ) {
				$$exp{'expect'} =~ s/$$list{'EXPECT:expect'}{'match'}/"'\"$$list{'EXPECT:expect'}{value}\"'"/eeeg;
			} else {
				$$exp{'expect'} = $$list{'EXPECT:expect'}{'value'};
			}
		}
	}
	
	if ( ( defined $$list{'EXPECT:send'} ) && ( $$list{'EXPECT:send'}{'change'} ) ){
		foreach my $exp ( @{ $$cfg{'expect'} } ) {
			if ( $$list{'EXPECT:send'}{'regexp'} // 0 ) {
				$$exp{'send'} =~ s/$$list{'EXPECT:send'}{'match'}/"'\"$$list{'EXPECT:send'}{value}\"'"/eeeg;
			} else {
				$$exp{'send'} = $$list{'EXPECT:send'}{'value'};
			}
		}
	}
	
	if ( $$list{'__delete_hidden_fields__'} // 0 ) { foreach my $hash ( @{ $$cfg{'expect'} } ) { $$hash{'hidden'} and $$hash{'send'} = ''; } }
	
	return 1;
}

sub _subst {
	my $string	= shift;
	my $CFG		= shift;
	my $uuid	= shift;
	
	my $ret = $string;
	my %out;
	my $pos = -1;
	
	my $tstamp = time;
	my ( $dy, $dm, $dd, $th, $tm, $ts ) = split( '_', strftime( "%Y_%m_%d_%H_%M_%S", localtime ) );
	my ( $name, $title, $ip, $user, $pass );
	if ( defined $uuid ) {
		return unless defined $$CFG{'environments'}{$uuid};
		
		$name	= $$CFG{'environments'}{$uuid}{name};
		$title	= $$CFG{'environments'}{$uuid}{title};
		$ip		= $$CFG{'environments'}{$uuid}{ip};
		$user	= $$CFG{'environments'}{$uuid}{user};
		$pass	= $$CFG{'environments'}{$uuid}{pass};
	}
	
	if ( defined $uuid ) {
		while ( $string =~ /<UUID>/go )		{ $string =~ s/<UUID>/$uuid/g; $ret = $string;			}
	}
	while ( $string =~ /<TIMESTAMP>/go )	{ $string =~ s/<TIMESTAMP>/$tstamp/g; $ret = $string;	}
	while ( $string =~ /<DATE_Y>/go )		{ $string =~ s/<DATE_Y>/$dy/g; $ret = $string;			}
	while ( $string =~ /<DATE_M>/go )		{ $string =~ s/<DATE_M>/$dm/g; $ret = $string;			}
	while ( $string =~ /<DATE_D>/go )		{ $string =~ s/<DATE_D>/$dd/g; $ret = $string;			}
	while ( $string =~ /<TIME_H>/go )		{ $string =~ s/<TIME_H>/$th/g; $ret = $string;			}
	while ( $string =~ /<TIME_M>/go )		{ $string =~ s/<TIME_M>/$tm/g; $ret = $string;			}
	while ( $string =~ /<TIME_S>/go )		{ $string =~ s/<TIME_S>/$ts/g; $ret = $string;			}
	if ( defined $uuid ) {
		while ( $string =~ /<NAME>/go )		{ $string =~ s/<NAME>/$name/g; $ret = $string;			}
		while ( $string =~ /<TITLE>/go )	{ $string =~ s/<TITLE>/$title/g; $ret = $string;		}
		while ( $string =~ /<IP>/go )		{ $string =~ s/<IP>/$ip/g; $ret = $string;				}
		while ( $string =~ /<USER>/go )		{ $string =~ s/<USER>/$ip/g; $ret = $string;			}
		while ( $string =~ /<PASS>/go )		{ $string =~ s/<PASS>/$pass/g; $ret = $string;			}
	}
	
	# Replace <KPXRE_GET_(title|username|password|url)_WHERE_(title|username|password|url)==(.+?)==> with KeePassX value
	while ( $string =~ /<KPXRE_GET_(title|username|password|url)_WHERE_(title|username|password|url)==(.+?)==>/go ) {
		my $what	= $1;
		my $where	= $2;
		my $var		= $3;
		my $regexp	= qr/$var/;
		
		if ( ! $$CFG{'defaults'}{'keepass'}{'use_keepass'} ) {
			msg( "ERROR: KeePassX variable '$var' can not be used because 'KeePassX' is not enabled under 'Preferences -> KeePass Options'" );
			exit 1;
		}
		
		my @found = $PACMain::FUNCS{_KEEPASS} -> find( $where, $regexp );
		if ( ! scalar @found)			{ msg( "ERROR: No entry '$where' found on KeePassX matching '$var'" ); exit 1; }
		elsif ( ( ( scalar @found ) > 1 ) && $$CFG{'defaults'}{'keepass'}{'ask_user'} )	{
			msg( "INFO: Found more than one entry for '$where' with value '$var'. Asking user..." );
			my $tmp = "<ASK:KeePass Passwords matching '$where' like '$var':"; foreach my $hash ( @found ) { $tmp .= '|' . $$hash{$what}; } $tmp .= '>';
			$string =~ s/<KPXRE_GET_${what}_WHERE_${where}==\Q$var\E==>/$tmp/g;
		} else {
			msg( "INFO: Found " . ( scalar( @found ) ) ." entries for '$where' with value '$var'. Selected first entry..." ) if ( scalar( @found ) > 1 ) && ! $$CFG{'defaults'}{'keepass'}{'ask_user'};
			$string =~ s/<KPXRE_GET_${what}_WHERE_${where}==\Q$var\E==>/$found[0]{$what}/g;
		}
		$ret = $string;
	}
	
	# Replace <KPX_*:*> with KeePassX 'password' value
	while ( $string =~ /<KPX_(title|username|url):(.+?)>/go ) {
		my $type	= $1;
		my $var		= $2;
		
		if ( ! $$CFG{'defaults'}{'keepass'}{'use_keepass'} ) {
			_wMessage( undef, "ERROR: KeePassX variable '<b>" . __( $var ) . "</b>' can not be used.\n'KeePassX' is not enabled under '<b>Preferences -> KeePass Options</b>'" );
			return undef;
		}
		
		my @found = $PACMain::FUNCS{_KEEPASS} -> find( $type, $var );
		if ( ! scalar @found) { _wMessage( undef, "ERROR: No entry '<b>$type</b>' found on KeePassX matching '<b>" . __( $var ) . "</b>'" ); return undef; }
		elsif ( ( ( scalar @found ) > 1 ) && $$CFG{defaults}{keepass}{ask_user} )	{
			my $tmp = "<ASK:KeePass Passwords matching '$type' like '$var':"; foreach my $hash ( @found ) { $tmp .= '|' . $$hash{password}; } $tmp .= '>';
			$string =~ s/<KPX_$type:\Q$var\E>/$tmp/g;
		} else {
			$string =~ s/<KPX_$type:\Q$var\E>/$found[0]{password}/g;
		}
		$ret = $string;
	}
	
	# Replace '<GV:.+>' with user saved global variables for '$connection_cmd' execution
	while ( $string =~ /<GV:(.+?)>/go ) {
		my $var = $1;
		if ( defined $$CFG{'defaults'}{'global variables'}{ $var } ) {
			my $val = $$CFG{'defaults'}{'global variables'}{ $var }{'value'} // '';
			$string =~ s/<GV:$var>/$val/g;
			$ret = $string;
		}
	}
	
	# Replace '<V:#>' with user saved variables for '$connection_cmd'
	if ( defined $uuid ) {
		while ( $string =~ /<V:(\d+?)>/go ) {
			my $var = $1;
			if ( defined $$CFG{'environments'}{$uuid}{'variables'}[ $var ] ) {
				my $val = $$CFG{'environments'}{$uuid}{'variables'}[ $var ]{txt} // '';
				$string =~ s/<V:$var>/$val/g;
				$ret = $string;
			}
		}
	}
	
	# Replace '<ENV:#>' with environment variables for '$connection_cmd'
	while ( $string =~ /<ENV:(.+?)>/go ) {
		my $var = $1;
		if ( defined $ENV{$var} ) {
			my $val = $ENV{$var} // '';
			$string =~ s/<ENV:$var>/$val/g;
			$ret = $string;
		}
	}
	
	# Replace '<ASK:#>' with user provided data for 'cmd' execution
	while ( $string =~ /<ASK:(\d+?)>/go ) {
		my $var = $1;
		my $val = _wEnterValue( undef, "<b>Variable substitution '$var'</b>" , $string ) // return undef;
		$string =~ s/<ASK:$var>/$val/g;
		$ret = $string;
	}
	
	# Replace '<ASK:description|opt1|opt2|...|optN>' with user provided data for 'cmd' execution
	#while ( $string =~ /<ASK:(.+\|.+?)>/go ) {
	while ( $string =~ /<ASK:(.+?)\|(.+?)>/go ) {
		my $desc = $1;
		my $var = $2;
		my @list = split( '\|', $var );
		( $ret, $pos ) = _wEnterValue( undef, "<b>Choose variable value:</b>" , $desc, \@list );
		$string =~ s/<ASK:(.+?)\|(.+?)>/$ret/;
		$ret = $string;
	}
	
	# Replace '<ASK:*>' with user provided data for 'cmd' execution
	while ( $string =~ /<ASK:(.+?)>/go ) {
		my $var = $1;
		my $val = _wEnterValue( undef, "<b>Variable substitution</b>" , "Please, enter a value for:'$var'" ) // return undef;
		$string =~ s/<ASK:$var>/$val/g;
		$ret = $string;
	}
	
	# Replace '<CMD:.+>' with the result of executing 'cmd'
	while ( $string =~ /<CMD:(.+?)>/go ) {
		my $var = $1;
		my $output = `$var`;
		chomp $output;
		if ( $output =~ /\R/go ) {
			$string =~ s/<CMD:\Q$var\E>/echo "$output"/g;
		} else {
			$string =~ s/<CMD:\Q$var\E>/$output/g;
		}
		$ret = $string;
	}
	
	# Delete '<CTRL_.+:.+>' and save it's value (output)
	while ( $string =~ /<CTRL_(.+?):(.+?)>/go ) {
		my $ctrl = $1;
		my $cmd = $2;
		$out{'ctrl'}{'ctrl'} = $ctrl;
		$out{'ctrl'}{'cmd'} = $cmd;
		$string =~ s/<CTRL_$ctrl:$cmd>//g;
		$ret = $string;
	}
	
	# Delete '<TEE:.+>' and save it's value (output)
	while ( $string =~ /<TEE:(.+)>/go ) {
		my $var = $1;
		$out{'tee'} = $var;
		$string =~ s/<TEE:$var>//g;
		$ret = $string;
	}
	
	# Delete '<PIPE:.+:.+>' and save it's value (command to pipe the result through)
	while ( $string =~ /<PIPE:(.+?):(.+?)>/go ) {
		my $pipe = $1;
		my $prompt = $2;
		push( @{ $out{'pipe'} }, $pipe );
		$out{'prompt'} = $prompt;
		$string =~ s/<PIPE:\Q$pipe\E:\Q$prompt>\E//g;
		$ret = $string;
	}
	# Delete '<PIPE:.+>' and save it's value (command to pipe the result through)
	while ( $string =~ /<PIPE:(.+?)>/go ) {
		my $var = $1;
		push( @{ $out{'pipe'} }, $var );
		$string =~ s/<PIPE:$var>//g;
		$ret = $string;
	}
	
	$out{'pos'} = $pos;
	return wantarray ? ( $ret, \%out ) : $ret;
}

sub _wakeOnLan {
	my $cfg		= shift;
	my $uuid	= shift;
	
	my $port		= 9;
	my $ping_port	= 7;
	
	my $ip			= $$cfg{ip} // '';
	my $mac			= ( $$cfg{mac} // '00:00:00:00:00:00' ) || '00:00:00:00:00:00';
	
	defined $uuid and $ip = _subst( $ip, $PACMain::FUNCS{_MAIN}{_CFG}, $uuid );
	my $packed_ip = gethostbyname( $ip );
	defined $packed_ip and $ip = inet_ntoa( $packed_ip );
	
	my %w;
	
	# Create the dialog window,
	$w{window}{data} = Gtk2::Dialog -> new_with_buttons(
		"$APPNAME (v$APPVERSION) : Wake On LAN",
		undef,
		'modal',
		'gtk-ok'		=> 'ok',
		'gtk-cancel'	=> 'cancel'
	);
	# and setup some dialog properties.
	$w{window}{data} -> set_default_response( 'ok' );
	$w{window}{data} -> set_position( 'center' );
	$w{window}{data} -> set_icon_name( 'pac-app-big' );
	$w{window}{data} -> set_size_request( -1, -1 );
	$w{window}{data} -> set_resizable( 0 );
		
		$w{window}{data} -> vbox -> pack_start( Gtk2::Image -> new_from_file( $RES_DIR . '/pac_banner_wol.png' ), 0, 1, 0 );
		
		# Create an HBox to contain a picture and a label
		$w{window}{gui}{hbox} = Gtk2::HBox -> new( 0, 0 );
		$w{window}{data} -> vbox -> pack_start( $w{window}{gui}{hbox}, 1, 1, 0 );
			
			# Create image
			$w{window}{gui}{img} = Gtk2::Image -> new_from_icon_name( 'computer', 'dialog' );
			$w{window}{gui}{hbox} -> pack_start( $w{window}{gui}{img}, 0, 1, 0 );
			
			# Create 1st label
			$w{window}{gui}{lblup} = Gtk2::Label -> new;
			$w{window}{gui}{hbox} -> pack_start( $w{window}{gui}{lblup}, 1, 1, 0 );
			$w{window}{gui}{lblup} -> set_markup( "<b>Enter the following data\nand press 'Ok' to send Magic Packet:</b>" );
		
		$w{window}{gui}{table} = Gtk2::Table -> new( 3, 3, 0 );
		$w{window}{data} -> vbox -> pack_start( $w{window}{gui}{table}, 1, 1, 0 );
			
			# Create MAC label
			$w{window}{gui}{lblmac} = Gtk2::Label -> new;
			$w{window}{gui}{table} -> attach_defaults( $w{window}{gui}{lblmac}, 0, 1, 0, 1 );
			$w{window}{gui}{lblmac} -> set_text( 'MAC Address: ' );
			
			# Create MAC entry widget
			$w{window}{gui}{entrymac} = Gtk2::Entry -> new;
			$w{window}{gui}{table} -> attach_defaults( $w{window}{gui}{entrymac}, 1, 2, 0, 1 );
			$w{window}{gui}{entrymac} -> set_text( $mac );
			$w{window}{gui}{entrymac} -> set_activates_default( 1 );
			$w{window}{gui}{entrymac} -> grab_focus;
			
			# Create MAC icon widget
			$w{window}{gui}{iconmac} = Gtk2::Image -> new_from_stock( 'gtk-no', 'menu' );
			$w{window}{gui}{table} -> attach_defaults( $w{window}{gui}{iconmac}, 2, 3, 0, 1 );
			
			# Create HOST label
			$w{window}{gui}{lblip} = Gtk2::Label -> new;
			$w{window}{gui}{table} -> attach_defaults( $w{window}{gui}{lblip}, 0, 1, 1, 2 );
			$w{window}{gui}{lblip} -> set_text( 'Host: ' );
			
			# Create HOST entry widget
			$w{window}{gui}{entryip} = Gtk2::Entry -> new;
			$w{window}{gui}{table} -> attach_defaults( $w{window}{gui}{entryip}, 1, 2, 1, 2 );
			$w{window}{gui}{entryip} -> set_text( $ip );
			$w{window}{gui}{entryip} -> set_sensitive( 0 );
			$w{window}{gui}{entryip} -> set_activates_default( 0 );
			
			# Create IP icon widget
			$w{window}{gui}{iconip} = Gtk2::Image -> new_from_stock( 'gtk-yes', 'menu' );
			$w{window}{gui}{table} -> attach_defaults( $w{window}{gui}{iconip}, 2, 3, 1, 2 );
			
			# Create PORT label
			$w{window}{gui}{lblport} = Gtk2::Label -> new;
			$w{window}{gui}{table} -> attach_defaults( $w{window}{gui}{lblport}, 0, 1, 2, 3 );
			$w{window}{gui}{lblport} -> set_text( 'Port Number: ' );
			
			# Create PORT entry widget
			$w{window}{gui}{entryport} = Gtk2::SpinButton -> new_with_range( 1, 65535, 1 );
			$w{window}{gui}{table} -> attach_defaults( $w{window}{gui}{entryport}, 1, 2, 2, 3 );
			$w{window}{gui}{entryport} -> set_value( $port );
			$w{window}{gui}{entryport} -> set_activates_default( 1 );
		
		$w{window}{gui}{separator} = Gtk2::HSeparator -> new;
		$w{window}{data} -> vbox -> pack_start( $w{window}{gui}{separator}, 0, 1, 0 );
		
		$w{window}{gui}{cbbroadcast} = Gtk2::CheckButton -> new_with_label( 'Send to broadcast' );
		$w{window}{data} -> vbox -> pack_start( $w{window}{gui}{cbbroadcast}, 0, 1, 0 );
		$w{window}{gui}{cbbroadcast} -> set_active( 1 );
		$w{window}{gui}{cbbroadcast} -> set_sensitive( $ip );
		
		$w{window}{gui}{separator} = Gtk2::HSeparator -> new;
		$w{window}{data} -> vbox -> pack_start( $w{window}{gui}{separator}, 0, 1, 0 );
		
		$w{window}{gui}{lblstatus} = Gtk2::Label -> new;
		$w{window}{data} -> vbox -> pack_start( $w{window}{gui}{lblstatus}, 0, 1, 0 );
		$w{window}{gui}{lblstatus} -> set_text( "Checking MAC for '$ip' ..." );
	
	# Show the window
	$w{window}{data} -> show_all;
	
	# Setup some callbacks...
	$w{window}{gui}{cbbroadcast} -> signal_connect( 'toggled' => sub { $w{window}{gui}{entryport} -> set_sensitive( ! $w{window}{gui}{cbbroadcast} -> get_active ); return 0; } );
	
	$w{window}{gui}{entrymac} -> signal_connect( 'event' => sub {
		$w{window}{data} -> get_action_area -> foreach( sub {
			return 1 unless $_[0] -> get_label eq 'gtk-ok';
			$w{window}{gui}{iconmac} -> set_from_stock( $w{window}{gui}{entrymac} -> get_chars( 0, -1 ) =~ /^[\da-fA-F]{2}[:-][\da-fA-F]{2}[:-][\da-fA-F]{2}[:-][\da-fA-F]{2}[:-][\da-fA-F]{2}[:-][\da-fA-F]{2}$/go ? 'gtk-yes' : 'gtk-no', 'menu' );
			$_[0] -> set_sensitive( $w{window}{gui}{entrymac} -> get_chars( 0, -1 ) =~ /^[\da-fA-F]{2}[:-][\da-fA-F]{2}[:-][\da-fA-F]{2}[:-][\da-fA-F]{2}[:-][\da-fA-F]{2}[:-][\da-fA-F]{2}$/go ? 1 : 0 );
		} );
		return 0;
	} );
	
	##########################################################
	# Try some net movement to resolve remote host's MAC address
	if ( $ip && ( $mac eq '00:00:00:00:00:00' ) ) {
		$w{window}{gui}{table} -> set_sensitive( 0 );
		Gtk2 -> main_iteration while Gtk2 -> events_pending;
		my $PING = Net::Ping -> new( 'tcp' );
		$PING -> tcp_service_check( 1 );
		$PING -> port_number( $ping_port );
		my $up = $PING -> ping( $ip, '1' );
		$mac = Net::ARP::arp_lookup( '', $ip );
		if ( ! $mac || ( $mac eq 'unknown' ) || ( $mac eq '00:00:00:00:00:00' ) ) {
			$up = $PING -> ping( $ip, '1' );
			$mac = Net::ARP::arp_lookup( '', $ip );
			$mac = $mac eq 'unknown' ? '00:00:00:00:00:00' : $mac;
		}
		$w{window}{gui}{iconip} -> set_from_stock( $up ? 'gtk-connect' : 'gtk-disconnect', 'menu' );
		$w{window}{gui}{entrymac} -> set_text( $mac );
		$w{window}{gui}{entrymac} -> select_region( 0, length( $mac ) );
		$w{window}{gui}{lblstatus} -> set_text( "'$ip' TCP port $ping_port seems to be " . ( $up ? 'REACHABLE' : 'UNREACHABLE' ) );
		$w{window}{gui}{table} -> set_sensitive( 1 );
		$w{window}{gui}{entrymac} -> grab_focus;
		$w{window}{data} -> get_action_area -> foreach( sub {
			return 1 unless $_[0] -> get_label eq 'gtk-ok';
			$_[0] -> set_sensitive( $w{window}{gui}{entrymac} -> get_chars( 0, -1 ) =~ /^[\da-fA-F]{2}[:-][\da-fA-F]{2}[:-][\da-fA-F]{2}[:-][\da-fA-F]{2}[:-][\da-fA-F]{2}[:-][\da-fA-F]{2}$/go ? 1 : 0 );
		} );
		Gtk2 -> main_iteration while Gtk2 -> events_pending;
	}
	elsif ( ! $ip ) {
		$w{window}{gui}{entrymac} -> set_text( $mac );
		$w{window}{gui}{entrymac} -> select_region( 0, length( $mac ) );
		$w{window}{gui}{lblstatus} -> set_text( 'No IP/hostname to test reachability' );
	} else {
		$w{window}{gui}{entrymac} -> set_text( $mac );
		$w{window}{gui}{entrymac} -> select_region( 0, length( $mac ) );
		$w{window}{gui}{lblstatus} -> set_text( "Selected saved MAC" );
	}

	##########################################################
	
	$w{window}{gui}{entryport} -> set_sensitive( ! $w{window}{gui}{cbbroadcast} -> get_active );
	
	my $ok = $w{window}{data} -> run;
	$mac = $w{window}{gui}{entrymac} -> get_chars( 0, -1 );
	
	$w{window}{data} -> destroy;
	
	return 0 if $ok ne 'ok';
	
	$$cfg{mac} = $mac;
	
	my $broadcast = $w{window}{gui}{cbbroadcast} -> get_active;
	
	# Prepare UDP socket
	socket( S, PF_INET, SOCK_DGRAM, getprotobyname( 'udp' ) ) || die "ERROR: Can't create socket ($!)";
	$broadcast and setsockopt(S, SOL_SOCKET, SO_BROADCAST, 1) || die "ERROR: Can't change socket properties ($!)";
	
	# Prepare the magic packet ( 6 times the hex 'ff' and 16 times the 'clean' MAC addresss)
	my $new_mac = $mac;
	$new_mac =~ s/[:-]//g;
	my $MAGIC = ( "\xff" x 6 ) . ( pack( 'H12', $new_mac ) x 16 );
	
	my $SIZE;
	my $paddr;
	my $ipaddr;
	if ( $broadcast ) {
		$SIZE = 0;
		$paddr = sockaddr_in( 0x2fff, INADDR_BROADCAST );
	} else {
		$SIZE = length( $MAGIC );
		$ip and $ipaddr = inet_aton( $ip ) || die "ERROR: Unknown host: $ip";
		$paddr = sockaddr_in( $port, $ipaddr ) || die "ERROR: Sockaddr_in failed ($!)";
	}
	
	if ( ! send( S, $MAGIC, $SIZE, $paddr ) ) {
		_wMessage( undef, "ERROR: Sending magic packet to $ip (MAC: $mac) failed:\n$!" );
		return $mac;
	} else {
		send( S, $MAGIC, $SIZE, $paddr );
		send( S, $MAGIC, $SIZE, $paddr );
		send( S, $MAGIC, $SIZE, $paddr );
		
		if ( defined $ipaddr ) {
			# Try sending some packets to standard WoL ports of provided host ip...
			send( S, $MAGIC, $SIZE, sockaddr_in( 7, $ipaddr ) );
			send( S, $MAGIC, $SIZE, sockaddr_in( 7, $ipaddr ) );
			send( S, $MAGIC, $SIZE, sockaddr_in( 7, $ipaddr ) );
			send( S, $MAGIC, $SIZE, sockaddr_in( 9, $ipaddr ) );
			send( S, $MAGIC, $SIZE, sockaddr_in( 9, $ipaddr ) );
			send( S, $MAGIC, $SIZE, sockaddr_in( 9, $ipaddr ) );
		}
		
		_wMessage( undef, "Wake On Lan 'Magic Packet'\nCORRECTLY sent to " . ( $broadcast ? 'BROADCAST' : "IP: $ip" ) . "\n(MAC: $mac)" );
	}
	
	return $mac;
}

sub _deleteOldestSessionLog {
	my $uuid	= shift;
	my $folder	= shift;
	my $max		= shift;
	
	# If MAX is 0, then keep ALL the logs.
	return 1 unless $max;
	
	opendir( my $F, $folder ) or die "ERROR: Could not open folder '$folder' for reading: $!";
	
	my @total;
	foreach my $file ( readdir $F ) {
		next unless $file =~ /^PAC_\[(.+)_Name_(.+)\]_\[(\d{8})_(\d{6})\]\.txt$/g;
		my ( $fenv, $fconn, $fdate, $ftime ) = ( $1, $2, $3, $4 );
		push( @total, "$folder/$file" );
	}
	
	close $F;
	
	return 1 unless scalar( @total ) ge $max;
	
	my $i = 0;
	foreach my $file ( sort { $a cmp $b } @total ) {
		unlink $file or die "ERROR: Could not delete oldest log file '$file': $!";
		last if ( ( scalar( @total ) - $max ) <= $i++ );
	}
	
	return 1;
}

sub _replaceBadChars {
	my $string = shift // '';
	
	$string =~ s/\x0/'NUL (null)'/go;
	$string =~ s/\x1/'SOH(start of heading)'/go;
	$string =~ s/\x2/'STX (start of text)'/go;
	$string =~ s/\x3/'ETX (end of text)'/go;
	$string =~ s/\x4/'EOT (end of trans.)'/go;
	$string =~ s/\x5/'ENQ (enquiry)'/go;
	$string =~ s/\x6/'ACK (acknowledge)'/go;
	$string =~ s/\x7/'BEL (bell)'/go;
	$string =~ s/\x8/'BS (backspace)'/go;
	$string =~ s/\x9/'AB (horizontal tab)'/go;
	$string =~ s/\xA/'LF (NL New Line)'/go;
	$string =~ s/\xB/'VT (vertical tab)'/go;
	$string =~ s/\xC/'FF (NP new page)'/go;
	$string =~ s/\xD/'CR (carriage return)'/go;
	$string =~ s/\xE/'SO (shift out)'/go;
	$string =~ s/\xF/'SI (shift in)'/go;
	$string =~ s/\x10/'DLE (data link escape)'/go;
	$string =~ s/\x11/'DC1 (device control 1)'/go;
	$string =~ s/\x12/'DC2 (device control 2)'/go;
	$string =~ s/\x13/'DC3 (device control 3)'/go;
	$string =~ s/\x14/'DC4 (device control 4)'/go;
	$string =~ s/\x15/'NAK (negative acknow.)'/go;
	$string =~ s/\x16/'SYN (synchronous idle)'/go;
	$string =~ s/\x17/'ETB (end of trans.blow)'/go;
	$string =~ s/\x18/'CAN (cancel)'/go;
	$string =~ s/\x19/'EM (end of medium)'/go;
	$string =~ s/\x1A/'SUB (substitute)'/go;
	$string =~ s/\x1B/'ESC (escape)'/go;
	$string =~ s/\x1C/'FS (file separator)'/go;
	$string =~ s/\x1D/'GS (group separator)'/go;
	$string =~ s/\x1E/'RS (record separator)'/go;
	$string =~ s/\x1F/'US (unit separator)'/go;
	$string =~ s/\x7f/\(BACKSPACE\)/go;
	
	return $string;
}

sub _removeEscapeSeqs {
	my $string = shift // '';
	
	$string =~ s/(\x1B\[\d+(;\d+)?m)|(\cM)//go;
	$string =~ s/(\x1B|\x08)\[.//go;
	$string =~ s/\x1B|\x08//go;
	
	return $string;
}

sub _purgeUnusedOrMissingScreenshots {
	my $cfg = shift;
	
	my %screenshots;
	
	foreach my $uuid ( keys %{ $$cfg{'environments'} } ) {
		my $i = 0;
		foreach my $screenshot ( @{ $$cfg{'environments'}{$uuid}{'screenshots'} } ) {
			if ( ! -f $screenshot ) {
				splice( @{ $$cfg{'environments'}{$uuid}{'screenshots'} }, $i, 1 );
			} else {
				++$i;
				$screenshots{$screenshot} = 1;
			}
		}
	}
	
	opendir( my $dir, "$CFG_DIR/screenshots" ) or die "ERROR: Could not open dir '$CFG_DIR/screenshots' for reading: $!";
	while ( my $file = readdir( $dir ) ) {
		next if $file =~ /^\.|\.\.$/go;
		defined $screenshots{"$CFG_DIR/screenshots/$file"} or unlink "$CFG_DIR/screenshots/$file";
	}
	closedir $dir;
	
	return 1;
}

sub _getXWindowsList {
	my %list;
	
	my $s = Gtk2::Gdk::Screen -> get_default or die print $!;
	my $display = $s -> get_display;
	
	foreach my $w ( $s -> get_window_stack ) {
		my $xid = $w -> get_xid or next;
		
		my $win = Gtk2::Gdk::Window -> foreign_new_for_display( $display, $xid );
		my ( $type_atom_name, $format_name, $data_name )			= $win -> property_get ( Gtk2::Gdk::Atom -> intern('WM_NAME'), Gtk2::Gdk::Atom -> intern('STRING'), 0, 9999, 0 );
		my ( $type_atom_pid, $format_pid, $data_pid )				= $win -> property_get ( Gtk2::Gdk::Atom -> intern('_NET_WM_PID'), Gtk2::Gdk::Atom -> intern('CARDINAL'), 0, 9999, 0 );
		my ( $type_atom_command, $format_command, $data_command )	= $win -> property_get ( Gtk2::Gdk::Atom -> intern('WM_COMMAND'), Gtk2::Gdk::Atom -> intern('STRING'), 0, 9999, 0 );
		
		$list{'by_xid'}{$xid}{'title'}			= $data_name;
		$list{'by_xid'}{$xid}{'window'}			= $w;
		$list{'by_xid'}{$xid}{'pid'}			= $data_pid;
		$list{'by_xid'}{$xid}{'command'}		= $data_command;
		
		if ( defined $data_name ) {
			$list{'by_name'}{$data_name}{'xid'}		= $xid;
			$list{'by_name'}{$data_name}{'window'}	= $w;
			$list{'by_name'}{$data_name}{'pid'}		= $data_pid;
			$list{'by_name'}{$data_name}{'command'}	= $data_command;
		}
		
		if ( defined $data_pid ) {
			$list{'by_pid'}{$data_pid}{'title'}		= $data_name;
			$list{'by_pid'}{$data_pid}{'window'}	= $w;
			$list{'by_pid'}{$data_pid}{'xid'}		= $xid;
			$list{'by_pid'}{$data_pid}{'command'}	= $data_command;
		}
	}
	
	#my $tw = Gtk2::Window -> new;
	#my $vb = Gtk2::VBox -> new( 0, 0 );
	#$tw -> add( $vb );
	#$tw -> show_all;
	#
	##$list{'by_xid'}{102760451}{'window'} -> reparent( $vb -> window, 0, 0 );
	#
	## ...or better:
	#
	#my $sock = Gtk2::Socket -> new;
	#$vb -> add( $sock );
	#$tw -> show_all;
	#$sock -> add_id( $list{'by_name'}{'Calculator'}{'xid'} );

	return \%list;
}

sub _getREADME {
	my $pid	= shift // 0;
	
	my $readme_file = "$CFG_DIR/tmp/latest_README";
	system( "( /usr/bin/wget http://sourceforge.net/projects/pacmanager/files/README -O $readme_file 1>&2 2>/dev/null; kill -10 $pid ) &" );
	return 1;
}

sub _checkREADME {
	my $readme_file = "$CFG_DIR/tmp/latest_README";
	open F, $readme_file or return 0;
	my @readme;
	while( my $line = <F> ) { chomp $line; push( @readme, $line ); }
	close F;
	
	my $version = $readme[56] // 0;
	$version =~ s/^\s+-\s+(.+):/$1/go;
	$version or return 0;
	
	my $i = 54;
	my @changes = splice( @readme, 54 );
	unlink $readme_file;
	
	return $version, \@changes;
}

sub _showUpdate {
	my $NEW_VERSION			= shift;
	my $NEW_CHANGES			= shift;
	my $notify_no_updates	= shift // 0;
	
	return 0 if ( ( ( ! $NEW_VERSION ) || ( $APPVERSION ge $NEW_VERSION ) ) && ( ! $notify_no_updates ) );
	my $windowConfirm = Gtk2::Dialog -> new_with_buttons(
		"$APPNAME (v$APPVERSION) : Check new version availability",
		undef,
		'modal',
		'gtk-ok' => 'ok',
	);
	
	my $lbl = Gtk2::Label -> new;
	$windowConfirm -> vbox -> pack_start( $lbl, 0, 0, 5 );
	
	my $lbl2 = Gtk2::LinkButton -> new_with_label( 'http://sourceforge.net/projects/pacmanager' );
	$windowConfirm -> vbox -> pack_start( $lbl2, 0, 0, 5 );
	$lbl2 -> set( 'relief', 'none' );
	
	if ( ( ! $NEW_VERSION ) || ( $APPVERSION ge $NEW_VERSION ) ) {
		$lbl -> set_markup( "There is <b>NO</b> new version available" );
		$windowConfirm -> signal_connect( 'response', sub { $windowConfirm -> destroy; } );
	} else {
		$lbl -> set_markup( "There is a <b><big>NEW</big></b> version available: <b><big>$NEW_VERSION</big></b>" );
		
		# Create a scrolled window to contain the textview
		my $scrollDescription = Gtk2::ScrolledWindow -> new;
		$windowConfirm -> vbox -> pack_start( $scrollDescription, 1, 1, 0 );
		$scrollDescription -> set_policy( 'automatic', 'automatic' );
		my $tb = Gtk2::TextBuffer -> new;
		$tb -> set_text( join( "\n", @{ $NEW_CHANGES } ) );
		my $tv = Gtk2::TextView -> new_with_buffer( $tb );
		$tv -> set_editable( 0 );
		$scrollDescription -> add( $tv );
		my $cb = Gtk2::CheckButton -> new( 'Do not check for updates anymore (also configurable under "Preferences")' );
		$cb -> set_active( ! $PACMain::FUNCS{_MAIN}{_CFG}{'defaults'}{'check versions at start'} );
		$windowConfirm -> vbox -> pack_start( $cb, 0, 0, 5 );
		
		$windowConfirm -> signal_connect( 'response', sub { $PACMain::FUNCS{_MAIN}{_CFG}{defaults}{'check versions at start'} = ! $cb -> get_active; $PACMain::FUNCS{_MAIN} -> _saveConfiguration; $windowConfirm -> destroy; } );
		$windowConfirm -> set_size_request( 640, 480 );
		$windowConfirm -> set_resizable( 1 );
	}
	
	$windowConfirm -> set_position( 'center_always' );
	$windowConfirm -> set_icon_name( 'pac-app-big' );
	$windowConfirm -> set_border_width( 5 );
	$windowConfirm -> show_all;
	
	return 1;
}

sub _getEncodings {
	return {
		"Adobe-Standard-Encoding" => "PostScript Language Reference Manual",
		"Adobe-Symbol-Encoding" => "PostScript Language Reference Manual",
		"Amiga-1251" => "See (http://www.amiga.ultranet.ru/Amiga-1251.html)",
		"ANSI_X3.110-1983" => "ECMA registry",
		"ANSI_X3.4-1968" => "ECMA registry",
		"ASMO_449" => "ECMA registry",
		"Big5" => "Chinese for Taiwan Multi-byte set.",
		"Big5-HKSCS" => "See (http://www.iana.org/assignments/charset-reg/Big5-HKSCS)",
		"BOCU-1" => "http://www.unicode.org/notes/tn6/",
		"BRF" => "See <http://www.iana.org/assignments/charset-reg/BRF>",
		"BS_4730" => "ECMA registry",
		"BS_viewdata" => "ECMA registry",
		"CESU-8" => "<http://www.unicode.org/unicode/reports/tr26>",
		"CP51932" => "See <http://www.iana.org/assignments/charset-reg/CP51932>",
		"CSA_Z243.4-1985-1" => "ECMA registry",
		"CSA_Z243.4-1985-2" => "ECMA registry",
		"CSA_Z243.4-1985-gr" => "ECMA registry",
		"CSN_369103" => "ECMA registry",
		"DEC-MCS" => "VAX/VMS User's Manual,",
		"DIN_66003" => "ECMA registry",
		"dk-us" => "",
		"DS_2089" => "Danish Standard, DS 2089, February 1974",
		"EBCDIC-AT-DE-A" => "IBM 3270 Char Set Ref Ch 10, GA27-2837-9, April 1987",
		"EBCDIC-AT-DE" => "IBM 3270 Char Set Ref Ch 10, GA27-2837-9, April 1987",
		"EBCDIC-CA-FR" => "IBM 3270 Char Set Ref Ch 10, GA27-2837-9, April 1987",
		"EBCDIC-DK-NO-A" => "IBM 3270 Char Set Ref Ch 10, GA27-2837-9, April 1987",
		"EBCDIC-DK-NO" => "IBM 3270 Char Set Ref Ch 10, GA27-2837-9, April 1987",
		"EBCDIC-ES-A" => "IBM 3270 Char Set Ref Ch 10, GA27-2837-9, April 1987",
		"EBCDIC-ES" => "IBM 3270 Char Set Ref Ch 10, GA27-2837-9, April 1987",
		"EBCDIC-ES-S" => "IBM 3270 Char Set Ref Ch 10, GA27-2837-9, April 1987",
		"EBCDIC-FI-SE-A" => "IBM 3270 Char Set Ref Ch 10, GA27-2837-9, April 1987",
		"EBCDIC-FI-SE" => "IBM 3270 Char Set Ref Ch 10, GA27-2837-9, April 1987",
		"EBCDIC-FR" => "IBM 3270 Char Set Ref Ch 10, GA27-2837-9, April 1987",
		"EBCDIC-IT" => "IBM 3270 Char Set Ref Ch 10, GA27-2837-9, April 1987",
		"EBCDIC-PT" => "IBM 3270 Char Set Ref Ch 10, GA27-2837-9, April 1987",
		"EBCDIC-UK" => "IBM 3270 Char Set Ref Ch 10, GA27-2837-9, April 1987",
		"EBCDIC-US" => "IBM 3270 Char Set Ref Ch 10, GA27-2837-9, April 1987",
		"ECMA-cyrillic" => "ISO registry (formerly ECMA registry)",
		"ES2" => "ECMA registry",
		"ES" => "ECMA registry",
		"EUC-KR" => "RFC-1557 (see also KS_C_5861-1992)",
		"Extended_UNIX_Code_Fixed_Width_for_Japanese" => "Used in Japan.  Each character is 2 octets.",
		"Extended_UNIX_Code_Packed_Format_for_Japanese" => "Standardized by OSF, UNIX International, and UNIX Systems",
		"GB18030" => "Chinese IT Standardization Technical Committee",
		"GB_1988-80" => "ECMA registry",
		"GB_2312-80" => "ECMA registry",
		"GB2312" => "Chinese for People's Republic of China (PRC) mixed one byte,",
		"GBK" => "Chinese IT Standardization Technical Committee",
		"GOST_19768-74" => "ECMA registry",
		"greek7" => "ECMA registry",
		"greek7-old" => "ECMA registry",
		"greek-ccitt" => "ECMA registry",
		"HP-DeskTop" => "PCL 5 Comparison Guide, Hewlett-Packard,",
		"HP-Legal" => "PCL 5 Comparison Guide, Hewlett-Packard,",
		"HP-Math8" => "PCL 5 Comparison Guide, Hewlett-Packard,",
		"HP-Pi-font" => "PCL 5 Comparison Guide, Hewlett-Packard,",
		"hp-roman8" => "LaserJet IIP Printer User's Manual,",
		"HZ-GB-2312" => "RFC 1842, RFC 1843",
		"IBM00858" => "IBM See (http://www.iana.org/assignments/charset-reg/IBM00858)",
		"IBM00924" => "IBM See (http://www.iana.org/assignments/charset-reg/IBM00924)",
		"IBM01140" => "IBM See (http://www.iana.org/assignments/charset-reg/IBM01140)",
		"IBM01141" => "IBM See (http://www.iana.org/assignments/charset-reg/IBM01141)",
		"IBM01142" => "IBM See (http://www.iana.org/assignments/charset-reg/IBM01142)",
		"IBM01143" => "IBM See (http://www.iana.org/assignments/charset-reg/IBM01143)",
		"IBM01144" => "IBM See (http://www.iana.org/assignments/charset-reg/IBM01144)",
		"IBM01145" => "IBM See (http://www.iana.org/assignments/charset-reg/IBM01145)",
		"IBM01146" => "IBM See (http://www.iana.org/assignments/charset-reg/IBM01146)",
		"IBM01147" => "IBM See (http://www.iana.org/assignments/charset-reg/IBM01147)",
		"IBM01148" => "IBM See (http://www.iana.org/assignments/charset-reg/IBM01148)",
		"IBM01149" => "IBM See (http://www.iana.org/assignments/charset-reg/IBM01149)",
		"IBM037" => "IBM NLS RM Vol2 SE09-8002-01, March 1990",
		"IBM038" => "IBM 3174 Character Set Ref, GA27-3831-02, March 1990",
		"IBM1026" => "IBM NLS RM Vol2 SE09-8002-01, March 1990",
		"IBM1047" => "IBM1047 (EBCDIC Latin 1/Open Systems)",
		"IBM273" => "IBM NLS RM Vol2 SE09-8002-01, March 1990",
		"IBM274" => "IBM 3174 Character Set Ref, GA27-3831-02, March 1990",
		"IBM275" => "IBM NLS RM Vol2 SE09-8002-01, March 1990",
		"IBM277" => "IBM NLS RM Vol2 SE09-8002-01, March 1990",
		"IBM278" => "IBM NLS RM Vol2 SE09-8002-01, March 1990",
		"IBM280" => "IBM NLS RM Vol2 SE09-8002-01, March 1990",
		"IBM281" => "IBM 3174 Character Set Ref, GA27-3831-02, March 1990",
		"IBM284" => "IBM NLS RM Vol2 SE09-8002-01, March 1990",
		"IBM285" => "IBM NLS RM Vol2 SE09-8002-01, March 1990",
		"IBM290" => "IBM 3174 Character Set Ref, GA27-3831-02, March 1990",
		"IBM297" => "IBM NLS RM Vol2 SE09-8002-01, March 1990",
		"IBM420" => "IBM NLS RM Vol2 SE09-8002-01, March 1990,",
		"IBM423" => "IBM NLS RM Vol2 SE09-8002-01, March 1990",
		"IBM424" => "IBM NLS RM Vol2 SE09-8002-01, March 1990",
		"IBM437" => "IBM NLS RM Vol2 SE09-8002-01, March 1990",
		"IBM500" => "IBM NLS RM Vol2 SE09-8002-01, March 1990",
		"IBM775" => "HP PCL 5 Comparison Guide (P/N 5021-0329) pp B-13, 1996",
		"IBM850" => "IBM NLS RM Vol2 SE09-8002-01, March 1990",
		"IBM851" => "IBM NLS RM Vol2 SE09-8002-01, March 1990",
		"IBM852" => "IBM NLS RM Vol2 SE09-8002-01, March 1990",
		"IBM855" => "IBM NLS RM Vol2 SE09-8002-01, March 1990",
		"IBM857" => "IBM NLS RM Vol2 SE09-8002-01, March 1990",
		"IBM860" => "IBM NLS RM Vol2 SE09-8002-01, March 1990",
		"IBM861" => "IBM NLS RM Vol2 SE09-8002-01, March 1990",
		"IBM862" => "IBM NLS RM Vol2 SE09-8002-01, March 1990",
		"IBM863" => "IBM Keyboard layouts and code pages, PN 07G4586 June 1991",
		"IBM864" => "IBM Keyboard layouts and code pages, PN 07G4586 June 1991",
		"IBM865" => "IBM DOS 3.3 Ref (Abridged), 94X9575 (Feb 1987)",
		"IBM866" => "IBM NLDG Volume 2 (SE09-8002-03) August 1994",
		"IBM868" => "IBM NLS RM Vol2 SE09-8002-01, March 1990",
		"IBM869" => "IBM Keyboard layouts and code pages, PN 07G4586 June 1991",
		"IBM870" => "IBM NLS RM Vol2 SE09-8002-01, March 1990",
		"IBM871" => "IBM NLS RM Vol2 SE09-8002-01, March 1990",
		"IBM880" => "IBM NLS RM Vol2 SE09-8002-01, March 1990",
		"IBM891" => "IBM NLS RM Vol2 SE09-8002-01, March 1990",
		"IBM903" => "IBM NLS RM Vol2 SE09-8002-01, March 1990",
		"IBM904" => "IBM NLS RM Vol2 SE09-8002-01, March 1990",
		"IBM905" => "IBM 3174 Character Set Ref, GA27-3831-02, March 1990",
		"IBM918" => "IBM NLS RM Vol2 SE09-8002-01, March 1990",
		"IBM-Symbols" => "Presentation Set, CPGID: 259",
		"IBM-Thai" => "Presentation Set, CPGID: 838",
		"IEC_P27-1" => "ECMA registry",
		"INIS-8" => "ECMA registry",
		"INIS-cyrillic" => "ECMA registry",
		"INIS" => "ECMA registry",
		"INVARIANT" => "",
		"ISO_10367-box" => "ECMA registry",
		"ISO-10646-J-1" => "ISO 10646 Japanese, see RFC 1815.",
		"ISO-10646-UCS-2" => "the 2-octet Basic Multilingual Plane, aka Unicode",
		"ISO-10646-UCS-4" => "the full code space. (same comment about byte order,",
		"ISO-10646-UCS-Basic" => "ASCII subset of Unicode.  Basic Latin = collection 1",
		"ISO-10646-Unicode-Latin1" => "ISO Latin-1 subset of Unicode. Basic Latin and Latin-1",
		"ISO-10646-UTF-1" => "Universal Transfer Format (1), this is the multibyte",
		"ISO-11548-1" => "See <http://www.iana.org/assignments/charset-reg/ISO-11548-1>",
		"ISO-2022-CN-EXT" => "RFC-1922",
		"ISO-2022-CN" => "RFC-1922",
		"ISO-2022-JP-2" => "RFC-1554",
		"ISO-2022-JP" => "RFC-1468 (see also RFC-2237)",
		"ISO-2022-KR" => "RFC-1557 (see also KS_C_5601-1987)",
		"ISO_2033-1983" => "ECMA registry",
		"ISO_5427:1981" => "ECMA registry",
		"ISO_5427" => "ECMA registry",
		"ISO_5428:1980" => "ECMA registry",
		"ISO_646.basic:1983" => "ECMA registry",
		"ISO_646.irv:1983" => "ECMA registry",
		"ISO_6937-2-25" => "ECMA registry",
		"ISO_6937-2-add" => "ECMA registry and ISO 6937-2:1983",
		"ISO-8859-10" => "ECMA registry",
		"ISO_8859-1:1987" => "ECMA registry",
		"ISO-8859-13" => "ISO See (http://www.iana.org/assignments/charset-reg/ISO-8859-13)",
		"ISO-8859-14" => "ISO See (http://www.iana.org/assignments/charset-reg/ISO-8859-14)",
		"ISO-8859-15" => "ISO",
		"ISO-8859-16" => "ISO",
		"ISO-8859-1-Windows-3.0-Latin-1" => "Extended ISO 8859-1 Latin-1 for Windows 3.0.",
		"ISO-8859-1-Windows-3.1-Latin-1" => "Extended ISO 8859-1 Latin-1 for Windows 3.1.",
		"ISO_8859-2:1987" => "ECMA registry",
		"ISO-8859-2-Windows-Latin-2" => "Extended ISO 8859-2.  Latin-2 for Windows 3.1.",
		"ISO_8859-3:1988" => "ECMA registry",
		"ISO_8859-4:1988" => "ECMA registry",
		"ISO_8859-5:1988" => "ECMA registry",
		"ISO_8859-6:1987" => "ECMA registry",
		"ISO_8859-6-E" => "RFC1556",
		"ISO_8859-6-I" => "RFC1556",
		"ISO_8859-7:1987" => "ECMA registry",
		"ISO_8859-8:1988" => "ECMA registry",
		"ISO_8859-8-E" => "RFC1556",
		"ISO_8859-8-I" => "RFC1556",
		"ISO_8859-9:1989" => "ECMA registry",
		"ISO-8859-9-Windows-Latin-5" => "Extended ISO 8859-9.  Latin-5 for Windows 3.1",
		"ISO_8859-supp" => "ECMA registry",
		"iso-ir-90" => "ECMA registry",
		"ISO-Unicode-IBM-1261" => "IBM Latin-2, -3, -5, Extended Presentation Set, GCSGID: 1261",
		"ISO-Unicode-IBM-1264" => "IBM Arabic Presentation Set, GCSGID: 1264",
		"ISO-Unicode-IBM-1265" => "IBM Hebrew Presentation Set, GCSGID: 1265",
		"ISO-Unicode-IBM-1268" => "IBM Latin-4 Extended Presentation Set, GCSGID: 1268",
		"ISO-Unicode-IBM-1276" => "IBM Cyrillic Greek Extended Presentation Set, GCSGID: 1276",
		"IT" => "ECMA registry",
		"JIS_C6220-1969-jp" => "ECMA registry",
		"JIS_C6220-1969-ro" => "ECMA registry",
		"JIS_C6226-1978" => "ECMA registry",
		"JIS_C6226-1983" => "ECMA registry",
		"JIS_C6229-1984-a" => "ECMA registry",
		"JIS_C6229-1984-b-add" => "ECMA registry",
		"JIS_C6229-1984-b" => "ECMA registry",
		"JIS_C6229-1984-hand-add" => "ECMA registry",
		"JIS_C6229-1984-hand" => "ECMA registry",
		"JIS_C6229-1984-kana" => "ECMA registry",
		"JIS_Encoding" => "JIS X 0202-1991",
		"JIS_X0201" => "JIS X 0201-1976. One byte only",
		"JIS_X0212-1990" => "ECMA registry",
		"JUS_I.B1.002" => "ECMA registry",
		"JUS_I.B1.003-mac" => "ECMA registry",
		"JUS_I.B1.003-serb" => "ECMA registry",
		"KOI7-switched" => "See <http://www.iana.org/assignments/charset-reg/KOI7-switched>",
		"KOI8-R" => "RFC 1489, based on GOST-19768-74, ISO-6937/8,",
		"KOI8-U" => "RFC 2319",
		"KS_C_5601-1987" => "ECMA registry",
		"KSC5636" => "",
		"KZ-1048" => "See <http://www.iana.org/assignments/charset-reg/KZ-1048>",
		"Latin-greek-1" => "ECMA registry",
		"latin-greek" => "ECMA registry",
		"latin-lap" => "ECMA registry",
		"macintosh" => "The Unicode Standard ver1.0, ISBN 0-201-56788-1, Oct 1991",
		"Microsoft-Publishing" => "PCL 5 Comparison Guide, Hewlett-Packard,",
		"MNEMONIC" => "RFC 1345, also known as 'mnemonic+ascii+38'",
		"MNEM" => "RFC 1345, also known as 'mnemonic+ascii+8200'",
		"MSZ_7795.3" => "ECMA registry",
		"NATS-DANO-ADD" => "ECMA registry",
		"NATS-DANO" => "ECMA registry",
		"NATS-SEFI-ADD" => "ECMA registry",
		"NATS-SEFI" => "ECMA registry",
		"NC_NC00-10:81" => "ECMA registry",
		"NF_Z_62-010_(1973)" => "ECMA registry",
		"NF_Z_62-010" => "ECMA registry",
		"NS_4551-1" => "ECMA registry",
		"NS_4551-2" => "ECMA registry",
		"OSD_EBCDIC_DF03_IRV" => "Fujitsu-Siemens standard mainframe EBCDIC encoding",
		"OSD_EBCDIC_DF04_15" => "Fujitsu-Siemens standard mainframe EBCDIC encoding",
		"OSD_EBCDIC_DF04_1" => "Fujitsu-Siemens standard mainframe EBCDIC encoding",
		"PC8-Danish-Norwegian" => "PC Danish Norwegian",
		"PC8-Turkish" => "PC Latin Turkish.  PCL Symbol Set id: 9T",
		"PT2" => "ECMA registry",
		"PTCP154" => "See (http://www.iana.org/assignments/charset-reg/PTCP154)",
		"PT" => "ECMA registry",
		"SCSU" => "SCSU See (http://www.iana.org/assignments/charset-reg/SCSU)",
		"SEN_850200_B" => "ECMA registry",
		"SEN_850200_C" => "ECMA registry",
		"Shift_JIS" => "This charset is an extension of csHalfWidthKatakana",
		"T.101-G2" => "ECMA registry",
		"T.61-7bit" => "ECMA registry",
		"T.61-8bit" => "ECMA registry",
		"TIS-620" => "Thai Industrial Standards Institute (TISI)",
		"TSCII" => "See <http://www.iana.org/assignments/charset-reg/TSCII>",
		"UNICODE-1-1" => "RFC 1641",
		"UNICODE-1-1-UTF-7" => "RFC 1642",
		"UNKNOWN-8BIT" => "",
		"us-dk" => "",
		"UTF-16BE" => "RFC 2781",
		"UTF-16LE" => "RFC 2781",
		"UTF-16" => "RFC 2781",
		"UTF-32BE" => "<http://www.unicode.org/unicode/reports/tr19/>",
		"UTF-32" => "<http://www.unicode.org/unicode/reports/tr19/>",
		"UTF-32LE" => "<http://www.unicode.org/unicode/reports/tr19/>",
		"UTF-7" => "RFC 2152",
		"UTF-8" => "RFC 3629",
		"Ventura-International" => "Ventura International.  ASCII plus coded characters similar",
		"Ventura-Math" => "PCL 5 Comparison Guide, Hewlett-Packard,",
		"Ventura-US" => "Ventura US.  ASCII plus characters typically used in",
		"videotex-suppl" => "ECMA registry",
		"VIQR" => "RFC 1456",
		"VISCII" => "RFC 1456",
		"windows-1250" => "Microsoft  (http://www.iana.org/assignments/charset-reg/windows-1250)",
		"windows-1251" => "Microsoft  (http://www.iana.org/assignments/charset-reg/windows-1251)",
		"windows-1252" => "Microsoft  (http://www.iana.org/assignments/charset-reg/windows-1252)",
		"windows-1253" => "Microsoft  (http://www.iana.org/assignments/charset-reg/windows-1253)",
		"windows-1254" => "Microsoft  (http://www.iana.org/assignments/charset-reg/windows-1254)",
		"windows-1255" => "Microsoft  (http://www.iana.org/assignments/charset-reg/windows-1255)",
		"windows-1256" => "Microsoft  (http://www.iana.org/assignments/charset-reg/windows-1256)",
		"windows-1257" => "Microsoft  (http://www.iana.org/assignments/charset-reg/windows-1257)",
		"windows-1258" => "Microsoft  (http://www.iana.org/assignments/charset-reg/windows-1258)",
		"Windows-31J" => "Windows Japanese.  A further extension of Shift_JIS",
		"windows-874" => "See <http://www.iana.org/assignments/charset-reg/windows-874>",
	};
}

sub _makeDesktopFile {
	my $cfg = shift;
	
	if ( ! $$cfg{'defaults'}{'show favourites in unity'} ) {
		unlink "$ENV{HOME}/.local/share/applications/pac.desktop";
		system( '/usr/bin/xdg-desktop-menu forceupdate &' );
		return 1;
	}
	
	my $d	= "[Desktop Entry]\n";
	$d		.= "Name=PAC\n";
	$d		.= "Comment=Perl Auto Connector (auto start)\n";
	$d		.= "Terminal=false\n";
	$d		.= "Icon=pac\n";
	$d		.= "Type=Application\n";
	$d		.= "Exec=/usr/bin/pac\n";
	$d		.= "StartupNotify=true\n";
	$d		.= "Name[en_US]=PAC\n";
	$d		.= "Comment[en_US]=Perl Auto Connector\n";
	$d		.= "Categories=Applications;Network;\n";
	$d		.= "X-GNOME-Autostart-enabled=false\n";
	my $dal	= 'Actions=Shell;Quick;';
	my $da	= "\n[Desktop Action Shell]\n";
	$da		.= "Name=<Start local shell>\n";
	$da		.= "Exec=asbru --start-shell\n";
	$da		.= "\n[Desktop Action Quick]\n";
	$da		.= "Name=<Quick connect...>\n";
	$da		.= "Exec=asbru --quick-conn\n";
	my $action = 0;
	foreach my $uuid ( keys %{ $$cfg{environments} } ) {
		next if ( ( $uuid eq '__PAC__ROOT__' ) || ( ! $$cfg{'environments'}{$uuid}{'favourite'} ) );
		
		$dal .= $action . ';';
		$da .= "\n" . '[Desktop Action ' . $action++ . "]\n";
		$da .= "Name=" . ( $$cfg{'environments'}{$uuid}{'name'} =~ s/_/__/go ) . "\n";
		$da .= "Exec=asbru --start-uuid=$uuid\n";
	}
	
	open F, ">$ENV{HOME}/.local/share/applications/pac.desktop" or return 0;
	print F "$d\n$dal\n$da\n";
	close F;
	system( '/usr/bin/xdg-desktop-menu forceupdate &' );
	
	return 1;
}

1;
