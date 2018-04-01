package PACConfig;

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
use YAML qw ( LoadFile DumpFile );
use Storable;
use Gnome2::GConf;
use Crypt::CBC;

# GTK2
use Gtk2 '-init';
use Gtk2::GladeXML;
use Gtk2::Ex::Simple::List;

# PAC modules
use PACUtils;
use PACTermOpts;
use PACGlobalVarEntry;
use PACExecEntry;
use PACKeePass;

# END: Import Modules
###################################################################

###################################################################
# Define GLOBAL CLASS variables

my $APPNAME			= $PACUtils::APPNAME;
my $APPVERSION		= $PACUtils::APPVERSION;
my $AUTOSTART_FILE	= $RealBin . '/res/pac_start.desktop';

my $GLADE_FILE		= $RealBin . '/res/pac.glade';
my $CFG_DIR			= $ENV{'HOME'} . '/.config/pac';
my $RES_DIR			= $RealBin . '/res';

# Connect to Gnome's GConf
my $GCONF			= Gnome2::GConf::Client -> get_default;

my $CIPHER			= Crypt::CBC -> new( -key => 'Àsbrù Connection Manager (https://www.asbru-cm.net/)', -cipher => 
'Blowfish', -salt => '12345678' ) or die "ERROR: $!";

# END: Define GLOBAL CLASS variables
###################################################################

###################################################################
# START: Define PUBLIC CLASS methods

sub new {
	my $class	= shift;
	my $self	= {};
	
	$self	-> {_CFG}			= shift;
	
	$self	-> {_WINDOWCONFIG}	= undef;
	$self	-> {_TXTOPTSBUFFER}	= undef;
	$self	-> { _GLADE}		= undef;
	
	%{ $self	-> {_CURSOR} } = (
		'block'		=> 0,
		'ibeam'		=> 1,
		'underline'	=> 2
	);
	
	$self	-> {_ENCODINGS_HASH}	= _getEncodings;
	$self	-> {_ENCODINGS_ARRAY}	= [];
	$self	-> {_ENCODINGS_MAP}		= {};
	$self	-> {_CFGTOGGLEPASS}		= 1;
	
	%{ $self	-> {_BACKSPACE_BINDING}	} = (
		'auto'				=> 0,
		'ascii-backspace'	=> 1,
		'ascii-delete'		=> 2,
		'delete-sequence'	=> 3,
		'tty'				=> 4
	);
	
	# Build the GUI
	_initGUI( $self ) or return 0;

	# Setup callbacks
	_setupCallbacks( $self );
	
	bless( $self, $class );
	return $self;
}

# DESTRUCTOR
sub DESTROY {
	my $self = shift;
	undef $self;
	return 1;
}

# Start GUI
sub show {
	my $self = shift;
	my $update = shift // 1;
	$update and _updateGUIPreferences( $self );
	$self -> {_WINDOWCONFIG} -> set_title( "Default Global Options : $APPNAME (v$APPVERSION)" );
	$$self{_WINDOWCONFIG} -> present;
	return 1;
}

# END: Define PUBLIC CLASS methods
###################################################################

###################################################################
# START: Define PRIVATE CLASS functions

sub _initGUI {
	my $self = shift;
	my $opt = shift;
	
	# Load XML Glade file
	defined $$self{_GLADE} or $$self{_GLADE} = Gtk2::GladeXML -> new( $GLADE_FILE ) or die "ERROR: Could not load GLADE file '$GLADE_FILE' ($!)";
	
	# Save main, about and add windows
	$$self{_WINDOWCONFIG} = $$self{_GLADE} -> get_widget ('windowConfig');
	$$self{_WINDOWCONFIG} -> set_size_request( -1, -1 );

	_( $self, 'imgBannerPref' ) -> set_from_file( $RES_DIR . '/pac_banner_preferences.png' );
	
	# Setup the check-button that defined whether PAC is auto-started on session init
	_( $self, 'cbCfgAutoStart' ) -> set_active( -f $ENV{'HOME'} . '/.config/autostart/pac_start.desktop' );
	
	# Initialize main window
	$$self{_WINDOWCONFIG} -> set_icon_name( 'pac-app-big' );

	_( $self, 'btnResetDefaults' )	-> set_image( Gtk2::Image -> new_from_stock( 'gtk-undo', 'button' ) );
	_( $self, 'btnResetDefaults' )	-> set_label( '_Reset to DEFAULT values' );
	
	# Option currently disabled
	#_( $self, 'btnCheckVersion' )	-> set_image( Gtk2::Image -> new_from_stock( 'gtk-refresh', 'button' ) );
	#_( $self, 'btnCheckVersion' )	-> set_label( 'Check _now' );
	
	_( $self, 'rbCfgStartTreeConn' )	-> set_image( Gtk2::Image -> new_from_stock( 'pac-treelist', 'button' ) );
	_( $self, 'rbCfgStartTreeFavs' )	-> set_image( Gtk2::Image -> new_from_stock( 'pac-favourite-on', 'button' ) );
	_( $self, 'rbCfgStartTreeHist' )	-> set_image( Gtk2::Image -> new_from_stock( 'pac-history', 'button' ) );
	_( $self, 'rbCfgStartTreeCluster' )	-> set_image( Gtk2::Image -> new_from_stock( 'pac-cluster-manager', 'button' ) );
	
	_( $self, 'imgKeePassOpts' )	-> set_from_stock( 'pac-keepass', 'button' );
	
	_( $self, 'btnCfgSetGUIPassword' )	-> set_image( Gtk2::Image -> new_from_stock( 'pac-protected', 'button' ) );
	_( $self, 'btnCfgSetGUIPassword' )	-> set_label( 'Set...' );
	
	_( $self, 'btnExportYAML' )		-> set_image( Gtk2::Image -> new_from_stock( 'gtk-save-as', 'button' ) );
	_( $self, 'btnExportYAML' )		-> set_label( 'Export config...' );
	
	_( $self, 'alignShellOpts' )	-> add( ( $$self{_SHELL}		= PACTermOpts		-> new ) -> {container} );
	_( $self, 'alignGlobalVar' )	-> add( ( $$self{_VARIABLES}	= PACGlobalVarEntry	-> new ) -> {container} );
	_( $self, 'alignCmdRemote' )	-> add( ( $$self{_CMD_REMOTE}	= PACExecEntry		-> new ) -> {container} );
	_( $self, 'alignCmdLocal' )		-> add( ( $$self{_CMD_LOCAL}	= PACExecEntry		-> new ) -> {container} );
	_( $self, 'alignKeePass' )		-> add( ( $$self{_KEEPASS}		= PACKeePass		-> new ) -> {container} );
	_( $self, 'nbPreferences' )		-> show_all;
	
	$$self{cbShowHidden} = Gtk2::CheckButton -> new_with_mnemonic( 'Show _hidden files' );
	_( $self, 'btnCfgSaveSessionLogs' ) -> set_extra_widget( $$self{cbShowHidden} );
	
	# Populate the Encodings combobox
	my $i = -1;
	$$self{_ENCODINGS_ARRAY} = _getEncodings;
	foreach my $enc ( sort { uc( $a ) cmp uc( $b ) } keys %{ $$self{_ENCODINGS_ARRAY} } ) {
		_( $self, 'cfgComboCharEncode' ) -> append_text( $enc );
		$$self{_SHELL}{gui}{'comboEncoding'} -> append_text( $enc );
		$$self{_ENCODINGS_MAP}{ $enc } = ++$i;
	}
	
	_updateGUIPreferences( $self );
	
	return 1;
}

sub _setupCallbacks {
	my $self = shift;
	
	# Capture 'autostart' checkbox toggled state
	_( $self, 'cbCfgAutoStart' ) -> signal_connect( 'toggled' => sub {
		if ( ( _( $self, 'cbCfgAutoStart' ) -> get_active ) && ( ! -f "$ENV{'HOME'}/.config/autostart/pac_start.desktop" ) ) {
			$$self{_CFG}{'defaults'}{'start at session startup'} = eval { symlink( $AUTOSTART_FILE, $ENV{'HOME'} . '/.config/autostart/pac_start.desktop' ); 1 };
		} elsif ( ! _( $self, 'cbCfgAutoStart' ) -> get_active ) {
			unlink( $ENV{'HOME'} . '/.config/autostart/pac_start.desktop' );
			$$self{_CFG}{'defaults'}{'start at session startup'} = 0;
		}
		return 1;
	} );

	# Capture 'Show hidden files' checkbox for session log files
	$$self{cbShowHidden} -> signal_connect( 'toggled' => sub { _( $self, 'btnCfgSaveSessionLogs' ) -> set_show_hidden( $$self{cbShowHidden} -> get_active ); } );
	
	_( $self, 'cbCfgProxyToggle' )		-> signal_connect( 'toggled' => sub { _( $self, 'aCfgProxy' ) -> set_sensitive( _( $self, 'cbCfgProxyToggle' ) -> get_active ); } );
	_( $self, 'cbConnShowPass' )		-> signal_connect( 'toggled' => sub { _( $self, 'entryPassword' ) -> set_visibility( _( $self, 'cbConnShowPass' ) -> get_active ); } );
	_( $self, 'cbCfgPreConnPingPort' )	-> signal_connect( 'toggled' => sub { _( $self, 'spCfgPingTimeout' ) -> set_sensitive( _( $self, 'cbCfgPreConnPingPort' ) -> get_active ); } );
	_( $self, 'cbCfgSaveSessionLogs' )	-> signal_connect( 'toggled' => sub { _( $self, 'hboxCfgSaveSessionLogs' ) -> set_sensitive( _( $self, 'cbCfgSaveSessionLogs' ) -> get_active ); } );
	_( $self, 'rbCfgInternalViewer' )	-> signal_connect( 'toggled' => sub { _( $self, 'entryCfgExternalViewer' ) -> set_sensitive( ! _( $self, 'rbCfgInternalViewer' ) -> get_active ); } );
	_( $self, 'btnSaveConfig' )			-> signal_connect( 'clicked' => sub { $self -> _saveConfiguration; _( $self, 'btnCloseConfig' ) -> activate } );
	_( $self, 'cbBoldAsText' )			-> signal_connect( 'toggled' => sub { _( $self, 'colorBold' ) -> set_sensitive( ! _( $self, 'cbBoldAsText' ) -> get_active ); } );
	_( $self, 'cbCfgTabsInMain' )		-> signal_connect( 'toggled' => sub { _( $self, 'cbCfgConnectionsAutoHide' ) -> set_sensitive( _( $self, 'cbCfgTabsInMain' ) -> get_active ); } );
	_( $self, 'cbCfgNewInTab' )			-> signal_connect( 'toggled' => sub { _( $self, 'vboxCfgTabsOptions' ) -> set_sensitive( _( $self, 'cbCfgNewInTab' ) -> get_active ); } );
	_( $self, 'cbCfgNewInWindow' )		-> signal_connect( 'toggled' => sub { _( $self, 'hboxWidthHeight' ) -> set_sensitive( _( $self, 'cbCfgNewInWindow' ) -> get_active ); } );
	_( $self, 'btnCfgOpenSessionLogs' ) -> signal_connect( 'clicked' => sub { system( '/usr/bin/xdg-open ' . ( _( $self, 'btnCfgSaveSessionLogs' ) -> get_current_folder ) ); } );
	_( $self, 'btnCloseConfig' )		-> signal_connect( 'clicked' => sub { $$self{_WINDOWCONFIG} -> hide; } );
	_( $self, 'btnResetDefaults' )		-> signal_connect( 'clicked' => sub { $self -> _resetDefaults; } );
	_( $self, 'btnCfgSetGUIPassword' )	-> signal_connect( 'clicked' => sub { _wSetPACPassword( $self, 1 ) ;return 1; } );
	_( $self, 'cfgComboCharEncode' )	-> signal_connect( 'changed' => sub { _( $self, 'cfgLblCharEncode' ) -> set_text( $self -> {_ENCODINGS_HASH}{ _( $self, 'cfgComboCharEncode' ) -> get_active_text } // '' ); } );
	_( $self, 'cbCfgBWTrayIcon' )		-> signal_connect( 'toggled' => sub { _( $self, 'imgTrayIcon' ) -> set_from_stock( _( $self, 'cbCfgBWTrayIcon' ) -> get_active ? 'pac-tray-bw' : 'pac-tray', 'menu' ); } );
	_( $self, 'cbCfgShowSudoPassword' )	-> signal_connect( 'toggled' => sub { _( $self, 'entryCfgSudoPassword' ) -> set_visibility( _( $self, 'cbCfgShowSudoPassword' ) -> get_active ); } );
	
	#DevNote: option currently disabled
	#_( $self, 'btnCheckVersion' ) -> signal_connect( 'clicked' => sub {
	#	$PACMain::FUNCS{_MAIN}{_UPDATING} = 1;
	#	$self -> _updateGUIPreferences;
	#	PACUtils::_getREADME( $$ );
	#	
	#	return 1;
	#} );
	
	# Capture 'export' button clicked
	_( $self, 'btnExportYAML' ) -> signal_connect( 'button_press_event' => sub {
		my ( $widget, $event ) = @_;
		my $format = 'yaml';
		my @type;
		push( @type, { label => 'as YAML data', code => sub { $self -> _exporter( 'yaml' ); } } );
		push( @type, { label => 'as Perl Data', code => sub { $self -> _exporter( 'perl' ); } } );
		_wPopUpMenu( \@type, $event, 1 );
		return 1;
	} );
	
	# Capture the "Protect PAC with startup password" checkbutton
	_( $self, 'cbCfgUseGUIPassword' ) -> signal_connect( 'toggled' => sub {
		$$self{_CFGTOGGLEPASS} or return $$self{_CFGTOGGLEPASS} = 1;
		
		if ( _( $self, 'cbCfgUseGUIPassword' ) -> get_active ) {
			my $pass_ok = _wSetPACPassword( $self, 0 );
			! $pass_ok and $$self{_CFGTOGGLEPASS} = 0;
			_( $self, 'cbCfgUseGUIPassword' ) -> set_active( $pass_ok );
			_( $self, 'hboxCfgPACPassword' ) -> set_sensitive( $pass_ok );
			$pass_ok and $PACMain::FUNCS{_MAIN} -> _setCFGChanged( 1 );
		} else {
			my $pass = _wEnterValue( $self, 'PAC GUI Password Removal', 'Enter current PAC GUI Password to remove protection...', undef, 0, 'pac-protected' );
			if ( ( ! defined $pass ) || ( $CIPHER -> encrypt_hex( $pass ) ne $$self{_CFG}{'defaults'}{'gui password'} ) ) {
				$$self{_CFGTOGGLEPASS} = 0;
				_( $self, 'cbCfgUseGUIPassword' ) -> set_active( 1 );
				_( $self, 'hboxCfgPACPassword' ) -> set_sensitive( 1 );
				_wMessage( $$self{_WINDOWCONFIG}, 'ERROR: Wrong password!!' );
				return 1;
			}
			
			$$self{_CFG}{'defaults'}{'gui password'} = $CIPHER -> encrypt_hex( '' );
			_( $self, 'hboxCfgPACPassword' ) -> set_sensitive( 0 );
			$PACMain::FUNCS{_MAIN} -> _setCFGChanged( 1 );
		}
		
		return 0;
	} );
	
	_( $self, 'entryCfgSudoPassword' ) -> signal_connect( 'button_press_event' => sub {
			my ( $widget, $event ) = @_;
			
			return 0 unless $event -> button eq 3;
			
			my @menu_items;
			
			# Populate with <<ASK_PASS>> special string
			push( @menu_items, {
				label => 'Interactive Password input',
				code => sub { _( $self, 'entryCfgSudoPassword' ) -> delete_text( 0, -1 ); _( $self, 'entryCfgSudoPassword' ) -> insert_text( '<<ASK_PASS>>', -1, 0 ); }
			} );
			
			# Populate with user defined variables
			my @variables_menu;
			my $i = 0;
			foreach my $value ( map{ $_->{txt} // '' } @{ $$self{variables} } ) {
				my $j = $i;
				push( @variables_menu, {
					label => "<V:$j> ($value)",
					code => sub { _( $self, 'entryCfgSudoPassword' ) -> insert_text( "<V:$j>", -1, _( $self, 'entryCfgSudoPassword' ) -> get_position ); }
				} );
				++$i;
			}
			push( @menu_items, {
				label => 'User variables...',
				sensitive => scalar @{ $$self{variables} },
				submenu => \@variables_menu
			} );
			
			# Populate with global defined variables
			my @global_variables_menu;
			foreach my $var ( sort { $a cmp $b } keys %{ $PACMain::FUNCS{_MAIN}{_CFG}{'defaults'}{'global variables'} } ) {
				my $val = $PACMain::FUNCS{_MAIN}{_CFG}{'defaults'}{'global variables'}{$var}{'value'};
				push( @global_variables_menu, {
					label => "<GV:$var> ($val)",
					code => sub { _( $self, 'entryCfgSudoPassword' ) -> insert_text( "<GV:$var>", -1, _( $self, 'entryCfgSudoPassword' ) -> get_position ); }
				} );
			}
			push( @menu_items, {
				label => 'Global variables...',
				sensitive => scalar( @global_variables_menu ),
				submenu => \@global_variables_menu
			} );
			
			# Populate with environment variables
			my @environment_menu;
			foreach my $key ( sort { $a cmp $b } keys %ENV ) {
				my $value = $ENV{$key};
				push( @environment_menu, {
					label => "<ENV:" . __( $key ) . ">",
					tooltip => "$key=$value",
					code => sub { _( $self, 'entryCfgSudoPassword' ) -> insert_text( "<ENV:$key>", -1, _( $self, 'entryCfgSudoPassword' ) -> get_position ); }
				} );
			}
			
			push( @menu_items, {
				label => 'Environment variables...',
				submenu => \@environment_menu
			} );
			
			# Populate with <ASK:#> special string
			push( @menu_items, {
				label => 'Interactive user input',
				tooltip => 'User will be prompted to provide a value with a text box (free data type)',
				code => sub {
					my $pos = _( $self, 'entryCfgSudoPassword' ) -> get_property( 'cursor_position' );
					_( $self, 'entryCfgSudoPassword' ) -> insert_text( '<ASK:number>', -1, _( $self, 'entryCfgSudoPassword' ) -> get_position );
					_( $self, 'entryCfgSudoPassword' ) -> select_region( $pos + 5, $pos + 11 );
				}
			} );
			
			# Populate with <ASK:*|> special string
			push( @menu_items, {
				label => 'Interactive user choose from list',
				tooltip => 'User will be prompted to choose a value form a user defined list separated with "|" (pipes without quotes)',
				code => sub {
					my $pos = _( $self, 'entryCfgSudoPassword' ) -> get_property( 'cursor_position' );
					_( $self, 'entryCfgSudoPassword' ) -> insert_text( '<ASK:descriptive line|opt1|opt2|...|optN>', -1, _( $self, 'entryCfgSudoPassword' ) -> get_position );
					_( $self, 'entryCfgSudoPassword' ) -> select_region( $pos + 5, $pos + 40 );
				}
			} );
			
			# Populate with <CMD:*> special string
			push( @menu_items, {
				label => 'Use a command output as value',
				tooltip => 'The given command line will be locally executed, and its output (both STDOUT and STDERR) will be used to replace this value',
				code => sub {
					my $pos = _( $self, 'entryCfgSudoPassword' ) -> get_property( 'cursor_position' );
					_( $self, 'entryCfgSudoPassword' ) -> insert_text( '<CMD:command to launch>', -1, _( $self, 'entryCfgSudoPassword' ) -> get_position );
					_( $self, 'entryCfgSudoPassword' ) -> select_region( $pos + 5, $pos + 22 );
				}
			} );
			
			# Populate with KeePass special strings
			if ( $$self{_CFG}{'defaults'}{'keepass'}{'use_keepass'} ) {
				my ( @titles, @usernames, @urls, @query );
				foreach my $hash ( $PACMain::FUNCS{_KEEPASS} ->find ) {
					push( @titles, {
						label => "<KPX_title:$$hash{title}>",
						tooltip => "$$hash{password}",
						code => sub { _( $self, 'entryCfgSudoPassword' ) -> set_text( "<KPX_title:$$hash{title}>" ); }
					} );
					push( @usernames, {
						label => "<KPX_username:$$hash{username}>",
						tooltip => "$$hash{password}",
						code => sub { _( $self, 'entryCfgSudoPassword' ) -> set_text( "<KPX_username:$$hash{username}>" ); }
					} );
					push( @urls, {
						label => "<KPX_url:$$hash{url}>",
						tooltip => "$$hash{password}",
						code => sub { _( $self, 'entryCfgSudoPassword' ) -> set_text( "<KPX_url:$$hash{url}>" ); }
					} );
				}
				
				push( @menu_items, {
					label => 'KeePassX',
					stockicon => 'pac-keepass',
					submenu =>
					[ {
							label => 'KeePassX title values',
							submenu => \@titles
						}, {
							label => 'KeePassX username values',
							submenu => \@usernames
						}, {
							label => 'KeePassX URL values',
							submenu => \@urls
						}, {
							label => "KeePass Extended Query",
							tooltip => "This allows you to select the value to be returned, based on another value's match againt a Perl Regular Expression",
							code => sub { _( $self, 'entryCfgSudoPassword' ) -> set_text( "<KPXRE_GET_(title|username|password|url)_WHERE_(title|username|password|url)==Your_RegExp_here==>" ); }
						}
					]
				} );
			}
			
			_wPopUpMenu( \@menu_items, $event );
			
			return 1;
	} );
	
	$$self{_WINDOWCONFIG} -> signal_connect( 'delete_event' => sub { _( $self, 'btnCloseConfig' ) -> clicked; return 1; } );
	$$self{_WINDOWCONFIG} -> signal_connect( 'key_press_event' => sub { my ( $widget, $event ) = @_; $event -> keyval == 65307 and $$self{_WINDOWCONFIG} -> hide; return 0; } );
	
	return 1;	
}

sub _exporter {
	my $self	= shift;
	my $format	= shift // 'dumper';
	my $file	= shift // '';
	
	my $suffix	= '';
	my $func	= '';
	
	if ( $format eq 'yaml' ) {
		$suffix = '.yml';
		$func = 'require YAML; YAML::DumpFile( $file, $$self{_CFG} ) or die "ERROR: Could not save file \'$file\' ($!)";';
	}
	elsif ( $format eq 'perl' ) {
		$suffix = '.dumper';
		$func = 'use Data::Dumper; $Data::Dumper::Indent = 1; $Data::Dumper::Purity = 1; open F, ">$file" or die "ERROR: Could not open file \'$file\' for writting ($!)"; print F Dumper( $$self{_CFG} ); close F;';
	}
	
	my $w;
	if ( ! $file ) {
		my $choose = Gtk2::FileChooserDialog -> new(
			"$APPNAME (v.$APPVERSION) Choose file to Export configuration as '$format'",
			$$self{_WINDOWCONFIG},
			'GTK_FILE_CHOOSER_ACTION_SAVE',
			'Export' , 'GTK_RESPONSE_ACCEPT',
			'Cancel' , 'GTK_RESPONSE_CANCEL',
		);
		$choose -> set_do_overwrite_confirmation( 1 );
		$choose -> set_current_folder( $ENV{'HOME'} // '/tmp' );
		$choose -> set_current_name( 'pac' . $suffix );
		
		my $out = $choose -> run;
		$file = $choose -> get_filename;
		$choose -> destroy;
		return 1 unless $out eq 'accept';
		
		$$self{_WINDOWCONFIG} -> window -> set_cursor( Gtk2::Gdk::Cursor -> new( 'watch' ) );
		$w = _wMessage( $$self{_WINDOWCONFIG}, "Please, wait while file '$file' is being created...", 0 );
		Gtk2 -> main_iteration while Gtk2 -> events_pending;
	}
	
	_cfgSanityCheck( $$self{_CFG} );
	_cipherCFG( $$self{_CFG} );
	
	$$self{_CFG}{'__PAC__EXPORTED__FULL__'} = 1;
	eval "$func";
	if ( ( ! $@ ) && ( defined $w ) ) {
		$w -> destroy;
		_wMessage( $$self{_WINDOWCONFIG}, "'$format' file succesfully saved to:\n\n$file" );
	} elsif ( defined $w ) {
		$w -> destroy;
		_wMessage( $$self{_WINDOWCONFIG}, "ERROR: Could not save PAC Config file '$file':\n\n$@" );
	}
	delete $$self{_CFG}{'__PAC__EXPORTED__'};
	delete $$self{_CFG}{'__PAC__EXPORTED__FULL__'};
	
	_decipherCFG( $$self{_CFG} );
	defined $$self{_WINDOWCONFIG} -> window and $$self{_WINDOWCONFIG} -> window -> set_cursor( Gtk2::Gdk::Cursor -> new( 'left-ptr' ) );
	
	return $file;
}

sub _resetDefaults {
	my $self = shift;
	
	my %default_cfg;
	defined $default_cfg{'defaults'}{1} or 1;
	
	PACUtils::_cfgSanityCheck( \%default_cfg );
	$self -> _updateGUIPreferences( \%default_cfg );
	
	return 1;
}

sub _updateGUIPreferences {
	my $self = shift;
	my $cfg = shift // $$self{_CFG};
	
	# Get PROXY from environment
	my $proxy_ip		= $GCONF -> get_string( '/system/http_proxy/host' ) || $GCONF -> get_string( '/system/proxy/http/host' );
	my $proxy_port		= $GCONF -> get_int( '/system/http_proxy/port' ) || $GCONF -> get_string( '/system/proxy/http/port' );
	my $proxy_user		= $GCONF -> get_string( '/system/http_proxy/authentication_user' ) || $GCONF -> get_string( '/system/proxy/http/host/authentication-user' );
	my $proxy_pass		= $GCONF -> get_string( '/system/http_proxy/authentication_password' ) || $GCONF -> get_string( '/system/proxy/http/host/authentication-password' );
	my $proxy_string	= 'no proxy configured';
	$proxy_ip		and $proxy_string = "$proxy_ip:$proxy_port";
	$proxy_user		and $proxy_string .= "; User: $proxy_user, Pass: <password hidden!>";
	
	# Main options
	#_( $self, 'btnCfgLocation' )			-> set_uri( 'file://' . $$self{_CFG}{'defaults'}{'config location'} );
	_( $self, 'cbCfgAutoAcceptKeys' )		-> set_active( $$cfg{'defaults'}{'auto accept key'} );
	_( $self, 'cbCfgHideOnConnect' )		-> set_active( $$cfg{'defaults'}{'hide on connect'} );
	_( $self, 'cbCfgCloseToTray' )			-> set_active( $$cfg{'defaults'}{'close to tray'} );
	_( $self, 'cbCfgStartMainMaximized' )	-> set_active( $$cfg{'defaults'}{'start main maximized'} );
	_( $self, 'cbCfgRememberSize' )			-> set_active( $$cfg{'defaults'}{'remember main size'} );
	_( $self, 'cbCfgStartIconified' )		-> set_active( $$cfg{'defaults'}{'start iconified'} );
	_( $self, 'cbCfgAutoSave' )				-> set_active( $$cfg{'defaults'}{'auto save'} );
	_( $self, 'cbCfgSaveOnExit' )			-> set_active( $$cfg{'defaults'}{'save on exit'} );
	_( $self, 'cbCfgBWTrayIcon' )			-> set_active( $$cfg{'defaults'}{'use bw icon'} );
	_( $self, 'cbCfgPreConnPingPort' )		-> set_active( $$cfg{'defaults'}{'ping port before connect'} );
	_( $self, 'spCfgPingTimeout' )			-> set_value( $$cfg{'defaults'}{'ping port timeout'} );
	_( $self, 'spCfgPingTimeout' )			-> set_sensitive( _( $self, 'cbCfgPreConnPingPort' ) -> get_active );
	_( $self, 'cbCfgSaveShowScreenshots' )	-> set_active( $$cfg{'defaults'}{'show screenshots'} );
	_( $self, 'cbCfgConfirmExit' )			-> set_active( $$cfg{'defaults'}{'confirm exit'} );
	_( $self, 'rbCfgInternalViewer' )		-> set_active( ! $$cfg{'defaults'}{'screenshots use external viewer'} );
	_( $self, 'rbCfgExternalViewer' )		-> set_active( $$cfg{'defaults'}{'screenshots use external viewer'} );
	_( $self, 'entryCfgExternalViewer' )	-> set_text( $$cfg{'defaults'}{'screenshots external viewer'} );
	_( $self, 'entryCfgExternalViewer' )	-> set_sensitive( $$cfg{'defaults'}{'screenshots use external viewer'} );
	_( $self, 'cbCfgTabsInMain' )			-> set_active( $$cfg{'defaults'}{'tabs in main window'} );
	_( $self, 'cbCfgConnectionsAutoHide' )	-> set_active( $$cfg{'defaults'}{'auto hide connections list'} );
	_( $self, 'cbCfgConnectionsAutoHide' )	-> set_sensitive( _( $self, 'cbCfgTabsInMain' ) -> get_active );
	_( $self, 'entryCfgPrompt' )			-> set_text( $$cfg{'defaults'}{'command prompt'} );
	_( $self, 'entryCfgUserPrompt' )		-> set_text( $$cfg{'defaults'}{'username prompt'} );
	_( $self, 'entryCfgPasswordPrompt' )	-> set_text( $$cfg{'defaults'}{'password prompt'} );
	_( $self, 'entryCfgHostKeyVerification' )	-> set_text( $$cfg{'defaults'}{'hostkey changed prompt'} );
	_( $self, 'entryCfgPressAnyKey' )		-> set_text( $$cfg{'defaults'}{'press any key prompt'} );
	_( $self, 'entryCfgRemoteHostChanged' )	-> set_text( $$cfg{'defaults'}{'remote host changed prompt'} );
	_( $self, 'entryCfgSudoPrompt' )		-> set_text( $$cfg{'defaults'}{'sudo prompt'} );
	_( $self, 'entryCfgSudoPassword' )		-> set_text( $$cfg{'defaults'}{'sudo password'} );
	_( $self, 'cbCfgShowSudoPassword' )		-> set_active( $$cfg{'defaults'}{'sudo show password'} );
	_( $self, 'entryCfgSudoPassword' )		-> set_visibility( _( $self, 'cbCfgShowSudoPassword' ) -> get_active );
	_( $self, 'entryCfgSelectByWordChars' )	-> set_text( $$cfg{'defaults'}{'word characters'} );
	_( $self, 'cbCfgShowTrayIcon' )			-> set_active( $$cfg{'defaults'}{'show tray icon'} );
	_( $self, 'cbCfgAutoStart' )			-> set_active( -f "$ENV{'HOME'}/.config/autostart/pac_start.desktop" );
	#DevNote: option currently disabled
	#_( $self, 'cbCfgCheckVersions' )		-> set_active( $$cfg{'defaults'}{'check versions at start'} );
	#_( $self, 'btnCheckVersion' ) -> set_sensitive( ! $PACMain::FUNCS{_MAIN}{_UPDATING} );
	_( $self, 'cbCfgShowStatistics' )		-> set_active( $$cfg{'defaults'}{'show statistics'} );
	_( $self, 'rbCfgForeground' )			-> set_active( $$cfg{'defaults'}{'protected set'} eq 'foreground' );
	_( $self, 'rbCfgBackground' )			-> set_active( $$cfg{'defaults'}{'protected set'} eq 'background' );
	_( $self, 'colorCfgProtected' )			-> set_color( _( $self, 'colorCfgProtected' ) -> get_color -> parse( $$cfg{'defaults'}{'protected color'} // _( $self, 'colorCfgProtected' ) -> get_color -> to_string ) );
	_( $self, 'cbCfgUseGUIPassword' )		-> set_active( $$cfg{'defaults'}{'use gui password'} );
	_( $self, 'hboxCfgPACPassword' )		-> set_sensitive( $$cfg{'defaults'}{'use gui password'} );
	_( $self, 'cbCfgUseGUIPasswordTray' )	-> set_active( $$cfg{'defaults'}{'use gui password tray'} );
	_( $self, 'cbCfgCTRLDisable' )			-> set_active( $$cfg{'defaults'}{'disable CTRL key bindings'} );
	_( $self, 'cbCfgALTDisable' )			-> set_active( $$cfg{'defaults'}{'disable ALT key bindings'} );
	_( $self, 'cbCfgSHIFTDisable' )			-> set_active( $$cfg{'defaults'}{'disable SHIFT key bindings'} );
	_( $self, 'cbCfgAutoStartShell' )		-> set_active( $$cfg{'defaults'}{'autostart shell upon PAC start'} );
	_( $self, 'cbCfgTreeOnRight' )			-> set_active( $$cfg{'defaults'}{'tree on right side'} );
	_( $self, 'cbCfgTreeOnLeft' )			-> set_active( ! $$cfg{'defaults'}{'tree on right side'} );
	_( $self, 'cbCfgPreventMOShowTree' )	-> set_active( ! $$cfg{'defaults'}{'prevent mouse over show tree'} );
	_( $self, 'rbCfgStartTreeConn' )		-> set_active( $$cfg{'defaults'}{'start PAC tree on'} eq 'connections' );
	_( $self, 'rbCfgStartTreeFavs' )		-> set_active( $$cfg{'defaults'}{'start PAC tree on'} eq 'favourites' );
	_( $self, 'rbCfgStartTreeHist' )		-> set_active( $$cfg{'defaults'}{'start PAC tree on'} eq 'history' );
	_( $self, 'rbCfgStartTreeCluster' )		-> set_active( $$cfg{'defaults'}{'start PAC tree on'} eq 'clusters' );
	_( $self, 'cbCfgShowTreeTooltips' )		-> set_active( $$cfg{'defaults'}{'show connections tooltips'} );
	_( $self, 'cbCfgUseShellToConnect' )	-> set_active( $$cfg{'defaults'}{'use login shell to connect'} );
	_( $self, 'rbCfgCtrlTabLast' )			-> set_active( $$cfg{'defaults'}{'ctrl tab'} eq 'last' );
	_( $self, 'rbCfgCtrlTabNext' )			-> set_active( $$cfg{'defaults'}{'ctrl tab'} ne 'last' );
	_( $self, 'cbCfgAutoAppendGroupName' )	-> set_active( $$cfg{'defaults'}{'append group name'} );
	_( $self, 'imgTrayIcon' )				-> set_from_stock( $$cfg{'defaults'}{'use bw icon'} ? 'pac-tray-bw' : 'pac-tray', 'menu' );
	_( $self, 'rbOnNoTabsNothing' )			-> set_active( $$cfg{'defaults'}{'when no more tabs'} == 0 );
	_( $self, 'rbOnNoTabsClose' )			-> set_active( $$cfg{'defaults'}{'when no more tabs'} == 1 );
	_( $self, 'rbOnNoTabsHide' )			-> set_active( $$cfg{'defaults'}{'when no more tabs'} == 2 );
	_( $self, 'cbCfgSelectionToClipboard' )	-> set_active( $$cfg{'defaults'}{'selection to clipboard'} );
	_( $self, 'cbCfgRemoveCtrlCharsConf' )	-> set_active( $$cfg{'defaults'}{'remove control chars'} );
	_( $self, 'cbCfgAllowMoreInstances' )	-> set_active( $$cfg{'defaults'}{'allow more instances'} );
	_( $self, 'cbCfgShowFavOnUnity' )		-> set_active( $$cfg{'defaults'}{'show favourites in unity'} );
	
	# Terminal Options
	_( $self, 'spCfgTmoutConnect' )			-> set_value( $$cfg{'defaults'}{'timeout connect'} );
	_( $self, 'spCfgTmoutCommand' )			-> set_value( $$cfg{'defaults'}{'timeout command'} );
	_( $self, 'spCfgNewWindowWidth' )		-> set_value( $$cfg{'defaults'}{'terminal windows hsize'} // 800 );
	_( $self, 'spCfgNewWindowHeight' )		-> set_value( $$cfg{'defaults'}{'terminal windows vsize'} // 600 );
	_( $self, 'vboxCfgTabsOptions' ) 		-> set_sensitive( _( $self, 'cbCfgNewInTab' ) -> get_active );
	_( $self, 'hboxWidthHeight' ) 			-> set_sensitive( _( $self, 'cbCfgNewInWindow' ) -> get_active );
	#_( $self, 'hboxOnNoMoreTabs' ) 			-> set_sensitive( _( $self, 'cbCfgNewInTab' ) -> get_active );
	_( $self, 'spCfgTerminalScrollback' )	-> set_value( $$cfg{'defaults'}{'terminal scrollback lines'} // 5000 );
	_( $self, 'spCfgTerminalTransparency' )	-> set_value( $$cfg{'defaults'}{'terminal transparency'} );
	_( $self, 'cbCfgRecordHistory' )		-> set_active( $$cfg{'defaults'}{'record command history'} );
	_( $self, 'cbCfgExpectDebug' )			-> set_active( $$cfg{'defaults'}{'debug'} );
	_( $self, 'cbCfgStartMaximized' )		-> set_active( $$cfg{'defaults'}{'start maximized'} );
	_( $self, 'radioCfgTabsTop' )			-> set_active( $$cfg{'defaults'}{'tabs position'} eq 'top' );
	_( $self, 'radioCfgTabsBottom' )		-> set_active( $$cfg{'defaults'}{'tabs position'} eq 'bottom' );
	_( $self, 'radioCfgTabsLeft' )			-> set_active( $$cfg{'defaults'}{'tabs position'} eq 'left' );
	_( $self, 'radioCfgTabsRight' )			-> set_active( $$cfg{'defaults'}{'tabs position'} eq 'right' );
	_( $self, 'cbCfgCloseTermOnDisconn' )	-> set_active( $$cfg{'defaults'}{'close terminal on disconnect'} );
	_( $self, 'cbCfgNewInTab' )				-> set_active( $$cfg{'defaults'}{'open connections in tabs'} // 1 );
	_( $self, 'cbCfgNewInWindow' )			-> set_active( ! ( $$cfg{'defaults'}{'open connections in tabs'} // 1 ) );
	_( $self, 'rbCfgComBoxNever' )			-> set_active( ! $$cfg{'defaults'}{'show commands box'} );
	_( $self, 'rbCfgComBoxCombo' )			-> set_active( $$cfg{'defaults'}{'show commands box'} == 1 );
	_( $self, 'rbCfgComBoxButtons' )		-> set_active( $$cfg{'defaults'}{'show commands box'} == 2 );
	_( $self, 'cbCfgShowGlobalComm' )		-> set_active( $$cfg{'defaults'}{'show global commands box'} );
	_( $self, 'colorText' )					-> set_color( _( $self, 'colorText' ) -> get_color -> parse( $$cfg{'defaults'}{'text color'} // _( $self, 'colorText' ) -> get_color -> to_string ) );
	_( $self, 'colorBack' )					-> set_color( _( $self, 'colorBack' ) -> get_color -> parse( $$cfg{'defaults'}{'back color'} // _( $self, 'colorBack' ) -> get_color -> to_string ) );
	_( $self, 'colorBold' )					-> set_color( _( $self, 'colorBold' ) -> get_color -> parse( $$cfg{'defaults'}{'bold color'} // _( $self, 'colorBold' ) -> get_color -> to_string ) );
	_( $self, 'colorBold' )					-> set_sensitive( ! _( $self, 'cbBoldAsText' ) -> get_active );
	_( $self, 'cbBoldAsText' )				-> set_active( $$cfg{'defaults'}{'bold color like text'} // 1 );
	_( $self, 'colorConnected' )			-> set_color( _( $self, 'colorConnected' ) -> get_color -> parse( $$cfg{'defaults'}{'connected color'} // _( $self, 'colorText' ) -> get_color -> to_string ) );
	_( $self, 'colorDisconnected' )			-> set_color( _( $self, 'colorDisconnected' ) -> get_color -> parse( $$cfg{'defaults'}{'disconnected color'} // _( $self, 'colorBack' ) -> get_color -> to_string ) );
	_( $self, 'colorNewData' )				-> set_color( _( $self, 'colorNewData' ) -> get_color -> parse( $$cfg{'defaults'}{'new data color'} // _( $self, 'colorNewData' ) -> get_color -> to_string ) );
	_( $self, 'fontTerminal' )				-> set_font_name( $$cfg{'defaults'}{'terminal font'} // _( $self, 'fontTerminal' ) -> get_font_name );
	_( $self, 'comboCursorShape' )			-> set_active( $self -> {_CURSOR}{ $$cfg{'defaults'}{'cursor shape'} // 'block' } );
	_( $self, 'cbCfgSaveSessionLogs' )		-> set_active( $$cfg{'defaults'}{'save session logs'} );
	_( $self, 'entryCfgLogFileName' )		-> set_text( $$cfg{'defaults'}{'session log pattern'} );
	_( $self, 'hboxCfgSaveSessionLogs' )	-> set_sensitive( $$cfg{'defaults'}{'save session logs'} );
	_( $self, 'btnCfgSaveSessionLogs' )		-> set_current_folder( $$cfg{'defaults'}{'session logs folder'} );
	_( $self, 'spCfgSaveSessionLogs' )		-> set_value( $$cfg{'defaults'}{'session logs amount'} );
	_( $self, 'cfgComboCharEncode' )		-> set_active( $self -> {_ENCODINGS_MAP}{ $$cfg{'defaults'}{'terminal character encoding'} // 'UTF-8' } );
	_( $self, 'cfgLblCharEncode' )			-> set_text( $self -> {_ENCODINGS_HASH}{ $$cfg{'defaults'}{'terminal character encoding'} // 'RFC-3629' } );
	_( $self, 'cfgComboBackspace' )			-> set_active( $$self{_BACKSPACE_BINDING}{ $$cfg{'defaults'}{'terminal backspace'} // '0' } );
	_( $self, 'cfgEntryTermEmulation' )		-> set_text( $$cfg{'defaults'}{'terminal emulation'} // 'xterm' );
	_( $self, 'cbCfgUnsplitDisconnected' )	-> set_active( $$cfg{'defaults'}{'unsplit disconnected terminals'} // '0' );
	_( $self, 'cbCfgConfirmChains' )		-> set_active( $$cfg{'defaults'}{'confirm chains'} // 1 );
	_( $self, 'cbCfgSkip1stChainExpect' )	-> set_active( $$cfg{'defaults'}{'skip first chain expect'} // 1 );
	_( $self, 'cbCfgEnableTreeLines' )		-> set_active( $$cfg{'defaults'}{'enable tree lines'} // 0 );
	_( $self, 'cbCfgShowStatistics' )		-> set_active( $$cfg{'defaults'}{'show statistics'} // 1 );
	_( $self, 'cbCfgPreventF11' )			-> set_active( $$cfg{'defaults'}{'prevent F11'} );
	_( $self, 'cbCfgHideConnSubMenu' )		-> set_active( $$cfg{'defaults'}{'hide connections submenu'} );
	_( $self, 'fontTree' )					-> set_font_name( $$cfg{'defaults'}{'tree font'} );
	_( $self, 'fontInfo' )					-> set_font_name( $$cfg{'defaults'}{'info font'} );
	_( $self, 'cbCfgAudibleBell' )			-> set_active( $$cfg{'defaults'}{'audible bell'} );
	_( $self, 'cbCfgVisibleBell' )			-> set_active( $$cfg{'defaults'}{'visible bell'} );
	_( $self, 'cbCfgShowTerminalStatus' )	-> set_active( $$cfg{'defaults'}{'terminal show status bar'} );
	_( $self, 'rbCfgSwitchTabsCtrl' )		-> set_active( ! $$cfg{'defaults'}{'how to switch tabs'} );
	_( $self, 'rbCfgSwitchTabsAlt' )		-> set_active( $$cfg{'defaults'}{'how to switch tabs'} );

	# Terminal Colors
	_( $self, 'colorBlack' )                        -> set_color( _( $self, 'colorBlack' ) -> get_color -> parse( $$cfg{'defaults'}{'color black'} // _( $self, 'colorBlack' ) -> get_color -> to_string ) );
	_( $self, 'colorRed' )                          -> set_color( _( $self, 'colorRed' ) -> get_color -> parse( $$cfg{'defaults'}{'color red'} // _( $self, 'colorRed' ) -> get_color -> to_string ) );
	_( $self, 'colorGreen' )                        -> set_color( _( $self, 'colorGreen' ) -> get_color -> parse( $$cfg{'defaults'}{'color green'} // _( $self, 'colorGreen' ) -> get_color -> to_string ) );
	_( $self, 'colorYellow' )                       -> set_color( _( $self, 'colorYellow' ) -> get_color -> parse( $$cfg{'defaults'}{'color yellow'} // _( $self, 'colorYellow' ) -> get_color -> to_string ) );
	_( $self, 'colorBlue' )                         -> set_color( _( $self, 'colorBlue' ) -> get_color -> parse( $$cfg{'defaults'}{'color blue'} // _( $self, 'colorBlue' ) -> get_color -> to_string ) );
	_( $self, 'colorMagenta' )                      -> set_color( _( $self, 'colorMagenta' ) -> get_color -> parse( $$cfg{'defaults'}{'color magenta'} // _( $self, 'colorMagenta' ) -> get_color -> to_string ) );
	_( $self, 'colorCyan' )                         -> set_color( _( $self, 'colorCyan' ) -> get_color -> parse( $$cfg{'defaults'}{'color cyan'} // _( $self, 'colorCyan' ) -> get_color -> to_string ) );
	_( $self, 'colorWhite' )                        -> set_color( _( $self, 'colorWhite' ) -> get_color -> parse( $$cfg{'defaults'}{'color white'} // _( $self, 'colorWhite' ) -> get_color -> to_string ) );
	_( $self, 'colorBrightBlack' )                  -> set_color( _( $self, 'colorBrightBlack' ) -> get_color -> parse( $$cfg{'defaults'}{'color bright black'} // _( $self, 'colorBrightBlack' ) -> get_color -> to_string ) );
	_( $self, 'colorBrightRed' )                    -> set_color( _( $self, 'colorBrightRed' ) -> get_color -> parse( $$cfg{'defaults'}{'color bright red'} // _( $self, 'colorBrightRed' ) -> get_color -> to_string ) );
	_( $self, 'colorBrightGreen' )                  -> set_color( _( $self, 'colorBrightGreen' ) -> get_color -> parse( $$cfg{'defaults'}{'color bright green'} // _( $self, 'colorBrightGreen' ) -> get_color -> to_string ) );
	_( $self, 'colorBrightYellow' )                 -> set_color( _( $self, 'colorBrightYellow' ) -> get_color -> parse( $$cfg{'defaults'}{'color bright yellow'} // _( $self, 'colorBrightYellow' ) -> get_color -> to_string ) );
	_( $self, 'colorBrightBlue' )                   -> set_color( _( $self, 'colorBrightBlue' ) -> get_color -> parse( $$cfg{'defaults'}{'color bright blue'} // _( $self, 'colorBrightBlue' ) -> get_color -> to_string ) );
	_( $self, 'colorBrightMagenta' )                -> set_color( _( $self, 'colorBrightMagenta' ) -> get_color -> parse( $$cfg{'defaults'}{'color bright magenta'} // _( $self, 'colorBrightMagenta' ) -> get_color -> to_string ) );
	_( $self, 'colorBrightCyan' )                   -> set_color( _( $self, 'colorBrightCyan' ) -> get_color -> parse( $$cfg{'defaults'}{'color bright cyan'} // _( $self, 'colorBrightCyan' ) -> get_color -> to_string ) );
	_( $self, 'colorBrightWhite' )                  -> set_color( _( $self, 'colorBrightWhite' ) -> get_color -> parse( $$cfg{'defaults'}{'color bright white'} // _( $self, 'colorBrightWhite' ) -> get_color -> to_string ) );

	# Local Shell Options
	_( $self, 'entryCfgShellBinary' )		-> set_text( $$cfg{'defaults'}{'shell binary'} || '/bin/bash' );
	_( $self, 'entryCfgShellOptions' )		-> set_text( $$cfg{'defaults'}{'shell options'} );
	_( $self, 'entryCfgShellDirectory' )	-> set_text( $$cfg{'defaults'}{'shell directory'} );
	
	# Proxy Configuration
	_( $self, 'cbCfgProxyToggle' )		-> set_active( $$cfg{'defaults'}{'use proxy'} );
	_( $self, 'aCfgProxy' )				-> set_sensitive( _( $self, 'cbCfgProxyToggle' ) -> get_active );
	_( $self, 'cbCfgProxySystem' )		-> set_active( $$cfg{'defaults'}{'use system proxy'} );
	_( $self, 'cbCfgProxySystem' )		-> set( 'label', 'Use system proxy settings ( ' . $proxy_string . ' )' );
	_( $self, 'cbCfgProxyManual' )		-> set_active( ! $$cfg{'defaults'}{'use system proxy'} );
	_( $self, 'entryCfgProxyIP' )		-> set_text( $$cfg{'defaults'}{'proxy ip'} );
	_( $self, 'entryCfgProxyPort' )		-> set_value( ( $$cfg{'defaults'}{'proxy port'} // 0 ) || 8080 );
	_( $self, 'entryCfgProxyUser' )		-> set_text( $$cfg{'defaults'}{'proxy user'} );
	_( $self, 'entryCfgProxyPassword' )	-> set_text( $$cfg{'defaults'}{'proxy pass'} );
	
	# Global TABS
	$$self{_SHELL}			-> update( $$self{_CFG}{'environments'}{'__PAC_SHELL__'}{'terminal options'} );
	$$self{_VARIABLES}		-> update( $$self{_CFG}{'defaults'}{'global variables'} );
	$$self{_CMD_LOCAL}		-> update( $$self{_CFG}{'defaults'}{'local commands'}, undef, 'local' );
	$$self{_CMD_REMOTE}		-> update( $$self{_CFG}{'defaults'}{'remote commands'}, undef, 'remote' );
	if ( ! $$self{_KEEPASS}	-> update( $$self{_CFG}{'defaults'}{'keepass'} ) ) {
		show( $self, 0 );
		_( $self, 'nbPreferences' ) -> set_current_page( -1 );
		return 0;
	}
	
	if ( defined($$self{_CFG}{'tmp'}{'tray available'}) && $$self{_CFG}{'tmp'}{'tray available'} eq 'warning' ) {
		_( $self, 'lblRestartRequired' ) -> set_text( "(*) Requires restarting Àsbrù for the change(s) to take effect\n\n" . ( _( 
$self, 'cbCfgStartIconified' ) -> get_tooltip_text // '' ) );
	}
	return 1;
}

sub _saveConfiguration {
	my $self = shift;
	
	$$self{_CFG}{'defaults'}{'command prompt'}					= _( $self, 'entryCfgPrompt' ) 				-> get_chars( 0, -1 );
	$$self{_CFG}{'defaults'}{'username prompt'}					= _( $self, 'entryCfgUserPrompt' ) 			-> get_chars( 0, -1 );
	$$self{_CFG}{'defaults'}{'password prompt'}					= _( $self, 'entryCfgPasswordPrompt' ) 		-> get_chars( 0, -1 );
	$$self{_CFG}{'defaults'}{'hostkey changed prompt'}			= _( $self, 'entryCfgHostKeyVerification' )	-> get_chars( 0, -1 );
	$$self{_CFG}{'defaults'}{'press any key prompt'}			= _( $self, 'entryCfgPressAnyKey' ) 		-> get_chars( 0, -1 );
	$$self{_CFG}{'defaults'}{'sudo prompt'}						= _( $self, 'entryCfgSudoPrompt' ) 			-> get_chars( 0, -1 );
	$$self{_CFG}{'defaults'}{'sudo password'}					= _( $self, 'entryCfgSudoPassword' ) 		-> get_chars( 0, -1 );
	$$self{_CFG}{'defaults'}{'sudo show password'}				= _( $self, 'cbCfgShowSudoPassword' ) 		-> get_active;
	$$self{_CFG}{'defaults'}{'remote host changed prompt'}		= _( $self, 'entryCfgRemoteHostChanged' ) 	-> get_chars( 0, -1 );
	$$self{_CFG}{'defaults'}{'timeout connect'}					= _( $self, 'spCfgTmoutConnect' ) 			-> get_chars( 0, -1 );
	$$self{_CFG}{'defaults'}{'timeout command'}					= _( $self, 'spCfgTmoutCommand' )			-> get_chars( 0, -1 );
	$$self{_CFG}{'defaults'}{'terminal windows hsize'}			= _( $self, 'spCfgNewWindowWidth' )			-> get_chars( 0, -1 );
	$$self{_CFG}{'defaults'}{'terminal windows vsize'}			= _( $self, 'spCfgNewWindowHeight' )		-> get_chars( 0, -1 );
	$$self{_CFG}{'defaults'}{'terminal scrollback lines'}		= _( $self, 'spCfgTerminalScrollback' )		-> get_chars( 0, -1 );
	$$self{_CFG}{'defaults'}{'terminal transparency'}			= _( $self, 'spCfgTerminalTransparency' )	-> get_value;
	$$self{_CFG}{'defaults'}{'terminal transparency'}			=~ s/,/\./go;
	$$self{_CFG}{'defaults'}{'terminal backspace'}				= _( $self, 'cfgComboBackspace' )			-> get_active_text;
	$$self{_CFG}{'defaults'}{'terminal emulation'}				= _( $self, 'cfgEntryTermEmulation' )		-> get_chars( 0, -1 );
	$$self{_CFG}{'defaults'}{'auto accept key'}					= _( $self, 'cbCfgAutoAcceptKeys' )			-> get_active;
	$$self{_CFG}{'defaults'}{'record command history'}			= _( $self, 'cbCfgRecordHistory' )			-> get_active;
	$$self{_CFG}{'defaults'}{'debug'}							= _( $self, 'cbCfgExpectDebug' )			-> get_active;
	$$self{_CFG}{'defaults'}{'use bw icon'}						= _( $self, 'cbCfgBWTrayIcon' ) 			-> get_active;
	$$self{_CFG}{'defaults'}{'close to tray'}					= _( $self, 'cbCfgCloseToTray' ) 			-> get_active;
	$$self{_CFG}{'defaults'}{'show screenshots'}				= _( $self, 'cbCfgSaveShowScreenshots' )	-> get_active;
	$$self{_CFG}{'defaults'}{'tabs in main window'}				= _( $self, 'cbCfgTabsInMain' )				-> get_active;
	$$self{_CFG}{'defaults'}{'auto hide connections list'}		= _( $self, 'cbCfgConnectionsAutoHide' )	-> get_active;
	$$self{_CFG}{'defaults'}{'hide on connect'}					= _( $self, 'cbCfgHideOnConnect' ) 			-> get_active;
	$$self{_CFG}{'defaults'}{'ping port before connect'}		= _( $self, 'cbCfgPreConnPingPort' )		-> get_active;
	$$self{_CFG}{'defaults'}{'ping port timeout'}				= _( $self, 'spCfgPingTimeout' )			-> get_chars( 0, -1 );
	$$self{_CFG}{'defaults'}{'start iconified'}					= _( $self, 'cbCfgStartIconified' )			-> get_active;
	$$self{_CFG}{'defaults'}{'start maximized'}					= _( $self, 'cbCfgStartMaximized' )			-> get_active;
	$$self{_CFG}{'defaults'}{'start main maximized'}			= _( $self, 'cbCfgStartMainMaximized' )		-> get_active;
	$$self{_CFG}{'defaults'}{'remember main size'}				= _( $self, 'cbCfgRememberSize' )			-> get_active;
	$$self{_CFG}{'defaults'}{'save on exit'}					= _( $self, 'cbCfgSaveOnExit' )				-> get_active;
	$$self{_CFG}{'defaults'}{'auto save'}						= _( $self, 'cbCfgAutoSave' )				-> get_active;
	$$self{_CFG}{'defaults'}{'use proxy'}						= _( $self, 'cbCfgProxyToggle' )			-> get_active;
	$$self{_CFG}{'defaults'}{'use system proxy'}				= _( $self, 'cbCfgProxySystem' )			-> get_active;
	$$self{_CFG}{'defaults'}{'proxy ip'}						= _( $self, 'entryCfgProxyIP' )				-> get_chars( 0, -1 );
	$$self{_CFG}{'defaults'}{'proxy port'}						= _( $self, 'entryCfgProxyPort' )			-> get_chars( 0, -1 );
	$$self{_CFG}{'defaults'}{'proxy user'}						= _( $self, 'entryCfgProxyUser' )			-> get_chars( 0, -1 );
	$$self{_CFG}{'defaults'}{'proxy pass'}						= _( $self, 'entryCfgProxyPassword' )		-> get_chars( 0, -1 );
	$$self{_CFG}{'defaults'}{'shell binary'}					= _( $self, 'entryCfgShellBinary' ) 		-> get_chars( 0, -1 );
	$$self{_CFG}{'defaults'}{'shell options'}					= _( $self, 'entryCfgShellOptions' ) 		-> get_chars( 0, -1 );
	$$self{_CFG}{'defaults'}{'shell directory'}					= _( $self, 'entryCfgShellDirectory' ) 		-> get_chars( 0, -1 );
	$$self{_CFG}{'defaults'}{'tabs position'}					= 'top'		if _( $self, 'radioCfgTabsTop' )	-> get_active;
	$$self{_CFG}{'defaults'}{'tabs position'}					= 'bottom'	if _( $self, 'radioCfgTabsBottom' )	-> get_active;
	$$self{_CFG}{'defaults'}{'tabs position'}					= 'left'	if _( $self, 'radioCfgTabsLeft' )	-> get_active;
	$$self{_CFG}{'defaults'}{'tabs position'}					= 'right'	if _( $self, 'radioCfgTabsRight' )	-> get_active;
	$$self{_CFG}{'defaults'}{'close terminal on disconnect'}	= _( $self, 'cbCfgCloseTermOnDisconn' )		-> get_active;
	$$self{_CFG}{'defaults'}{'open connections in tabs'}		= _( $self, 'cbCfgNewInTab' )				-> get_active;
	$$self{_CFG}{'defaults'}{'text color'}						= _( $self, 'colorText' )					-> get_color -> to_string;
	$$self{_CFG}{'defaults'}{'back color'}						= _( $self, 'colorBack' )					-> get_color -> to_string;
	$$self{_CFG}{'defaults'}{'bold color'}						= _( $self, 'colorBold' )					-> get_color -> to_string;
	$$self{_CFG}{'defaults'}{'bold color like text'}			= _( $self, 'cbBoldAsText' )				-> get_active;
	$$self{_CFG}{'defaults'}{'connected color'}					= _( $self, 'colorConnected' )				-> get_color -> to_string;
	$$self{_CFG}{'defaults'}{'disconnected color'}				= _( $self, 'colorDisconnected' )			-> get_color -> to_string;
	$$self{_CFG}{'defaults'}{'new data color'}					= _( $self, 'colorNewData' )				-> get_color -> to_string;
	$$self{_CFG}{'defaults'}{'terminal font'}					= _( $self, 'fontTerminal' )				-> get_font_name;
	$$self{_CFG}{'defaults'}{'cursor shape'}					= _( $self, 'comboCursorShape' )			-> get_active_text;
	$$self{_CFG}{'defaults'}{'save session logs'}				= _( $self, 'cbCfgSaveSessionLogs' )		-> get_active;
	$$self{_CFG}{'defaults'}{'session log pattern'}				= _( $self, 'entryCfgLogFileName' )			-> get_chars( 0, -1 );
	$$self{_CFG}{'defaults'}{'session logs folder'}				= _( $self, 'btnCfgSaveSessionLogs' )		-> get_current_folder;
	$$self{_CFG}{'defaults'}{'session logs amount'}				= _( $self, 'spCfgSaveSessionLogs' )		-> get_chars( 0, -1 );
	$$self{_CFG}{'defaults'}{'confirm exit'}					= _( $self, 'cbCfgConfirmExit' )			-> get_active;
	$$self{_CFG}{'defaults'}{'screenshots use external viewer'}	= ! _( $self, 'rbCfgInternalViewer' )		-> get_active;
	$$self{_CFG}{'defaults'}{'screenshots external viewer'}		= _( $self, 'entryCfgExternalViewer' )		-> get_chars( 0, -1 );
	$$self{_CFG}{'defaults'}{'terminal character encoding'}		= _( $self, 'cfgComboCharEncode' )			-> get_active_text;
	$$self{_CFG}{'defaults'}{'word characters'}					= _( $self, 'entryCfgSelectByWordChars' )	-> get_chars( 0, -1 );
	if ( _( $self, 'rbCfgComBoxNever' ) -> get_active )			{ $$self{_CFG}{'defaults'}{'show commands box'}	= 0; }
	elsif ( _( $self, 'rbCfgComBoxCombo' ) -> get_active )		{ $$self{_CFG}{'defaults'}{'show commands box'}	= 1; }
	elsif ( _( $self, 'rbCfgComBoxButtons' ) -> get_active )	{ $$self{_CFG}{'defaults'}{'show commands box'}	= 2; }
	$$self{_CFG}{'defaults'}{'show global commands box'}		= _( $self, 'cbCfgShowGlobalComm' )			-> get_active;
	$$self{_CFG}{'defaults'}{'show tray icon'}					= _( $self, 'cbCfgShowTrayIcon' )			-> get_active;
	$$self{_CFG}{'defaults'}{'unsplit disconnected terminals'}	= _( $self, 'cbCfgUnsplitDisconnected' )	-> get_active;
	$$self{_CFG}{'defaults'}{'confirm chains'}					= _( $self, 'cbCfgConfirmChains' )			-> get_active;
	$$self{_CFG}{'defaults'}{'skip first chain expect'}			= _( $self, 'cbCfgSkip1stChainExpect' )		-> get_active;
	$$self{_CFG}{'defaults'}{'enable tree lines'}				= _( $self, 'cbCfgEnableTreeLines' )		-> get_active;
	#DevNote: option currently disabled
	#$$self{_CFG}{'defaults'}{'check versions at start'}			= _( $self, 'cbCfgCheckVersions' 	)		-> get_active;
	$$self{_CFG}{'defaults'}{'show statistics'}					= _( $self, 'cbCfgShowStatistics' 	)		-> get_active;
	$$self{_CFG}{'defaults'}{'protected set'}					= _( $self, 'rbCfgForeground' 	)			-> get_active ? 'foreground' : 'background' ;
	$$self{_CFG}{'defaults'}{'protected color'}					= _( $self, 'colorCfgProtected' )			-> get_color -> to_string;
	$$self{_CFG}{'defaults'}{'use gui password'}				= _( $self, 'cbCfgUseGUIPassword' 	)		-> get_active;
	$$self{_CFG}{'defaults'}{'use gui password tray'}			= _( $self, 'cbCfgUseGUIPasswordTray' 	)	-> get_active;
	$$self{_CFG}{'defaults'}{'disable CTRL key bindings'}		= _( $self, 'cbCfgCTRLDisable' )			-> get_active;
	$$self{_CFG}{'defaults'}{'disable ALT key bindings'}		= _( $self, 'cbCfgALTDisable' )				-> get_active;
	$$self{_CFG}{'defaults'}{'disable SHIFT key bindings'}		= _( $self, 'cbCfgSHIFTDisable' )			-> get_active;
	$$self{_CFG}{'defaults'}{'prevent F11'}						= _( $self, 'cbCfgPreventF11' )				-> get_active;
	$$self{_CFG}{'defaults'}{'autostart shell upon PAC start'}	= _( $self, 'cbCfgAutoStartShell' )			-> get_active;
	$$self{_CFG}{'defaults'}{'tree on right side'}				= _( $self, 'cbCfgTreeOnRight' )			-> get_active;
	$$self{_CFG}{'defaults'}{'prevent mouse over show tree'}	= ! _( $self, 'cbCfgPreventMOShowTree' )		-> get_active;
	$$self{_CFG}{'defaults'}{'show connections tooltips'}		= _( $self, 'cbCfgShowTreeTooltips' )		-> get_active;
	$$self{_CFG}{'defaults'}{'hide connections submenu'}		= _( $self, 'cbCfgHideConnSubMenu' )		-> get_active;
	$$self{_CFG}{'defaults'}{'tree font'}						= _( $self, 'fontTree' )					-> get_font_name;
	$$self{_CFG}{'defaults'}{'info font'}						= _( $self, 'fontInfo' )					-> get_font_name;
	$$self{_CFG}{'defaults'}{'use login shell to connect'}		= _( $self, 'cbCfgUseShellToConnect' )		-> get_active;
	$$self{_CFG}{'defaults'}{'audible bell'}					= _( $self, 'cbCfgAudibleBell' )			-> get_active;
	$$self{_CFG}{'defaults'}{'visible bell'}					= _( $self, 'cbCfgVisibleBell' )			-> get_active;
	$$self{_CFG}{'defaults'}{'ctrl tab'}						= _( $self, 'rbCfgCtrlTabLast' )			-> get_active ? 'last' : 'next';
	$$self{_CFG}{'defaults'}{'terminal show status bar'}		= _( $self, 'cbCfgShowTerminalStatus' )		-> get_active;
	$$self{_CFG}{'defaults'}{'append group name'}				= _( $self, 'cbCfgAutoAppendGroupName' )	-> get_active;
	$$self{_CFG}{'defaults'}{'when no more tabs'}				= _( $self, 'rbOnNoTabsNothing' )			-> get_active ? 'last' : 'next';
	$$self{_CFG}{'defaults'}{'selection to clipboard'}			= _( $self, 'cbCfgSelectionToClipboard' )	-> get_active;
	$$self{_CFG}{'defaults'}{'how to switch tabs'}				= _( $self, 'rbCfgSwitchTabsAlt' )			-> get_active;
	$$self{_CFG}{'defaults'}{'remove control chars'}			= _( $self, 'cbCfgRemoveCtrlCharsConf' )	-> get_active;
	$$self{_CFG}{'defaults'}{'allow more instances'}			= _( $self, 'cbCfgAllowMoreInstances' )		-> get_active;
	$$self{_CFG}{'defaults'}{'show favourites in unity'}		= _( $self, 'cbCfgShowFavOnUnity' )			-> get_active;
	
	# Terminal colors
	$$self{_CFG}{'defaults'}{'color black'}						= _( $self, 'colorBlack' )					-> get_color -> to_string;
	$$self{_CFG}{'defaults'}{'color red'}						= _( $self, 'colorRed' )					-> get_color -> to_string;
	$$self{_CFG}{'defaults'}{'color green'}						= _( $self, 'colorGreen' )					-> get_color -> to_string;
	$$self{_CFG}{'defaults'}{'color yellow'}					= _( $self, 'colorYellow' )					-> get_color -> to_string;
	$$self{_CFG}{'defaults'}{'color blue'}						= _( $self, 'colorBlue' )					-> get_color -> to_string;
	$$self{_CFG}{'defaults'}{'color magenta'}					= _( $self, 'colorMagenta' )					-> get_color -> to_string;
	$$self{_CFG}{'defaults'}{'color cyan'}						= _( $self, 'colorCyan' )					-> get_color -> to_string;
	$$self{_CFG}{'defaults'}{'color white'}						= _( $self, 'colorWhite' )					-> get_color -> to_string;
	$$self{_CFG}{'defaults'}{'color bright black'}					= _( $self, 'colorBrightBlack' )				-> get_color -> to_string;
	$$self{_CFG}{'defaults'}{'color bright red'}					= _( $self, 'colorBrightRed' )					-> get_color -> to_string;
	$$self{_CFG}{'defaults'}{'color bright green'}					= _( $self, 'colorBrightGreen' )				-> get_color -> to_string;
	$$self{_CFG}{'defaults'}{'color bright yellow'}					= _( $self, 'colorBrightYellow' )				-> get_color -> to_string;
	$$self{_CFG}{'defaults'}{'color bright blue'}					= _( $self, 'colorBrightBlue' )					-> get_color -> to_string;
	$$self{_CFG}{'defaults'}{'color bright magenta'}				= _( $self, 'colorBrightMagenta' )				-> get_color -> to_string;
	$$self{_CFG}{'defaults'}{'color bright cyan'}					= _( $self, 'colorBrightCyan' )					-> get_color -> to_string;
	$$self{_CFG}{'defaults'}{'color bright white'}					= _( $self, 'colorBrightWhite' )				-> get_color -> to_string;
	
	if		( _( $self, 'rbOnNoTabsNothing' ) -> get_active )	{ $$self{_CFG}{'defaults'}{'when no more tabs'} = 0; }
	elsif	( _( $self, 'rbOnNoTabsClose' ) -> get_active )		{ $$self{_CFG}{'defaults'}{'when no more tabs'} = 1; }
	else														{ $$self{_CFG}{'defaults'}{'when no more tabs'} = 2; }
	
	#my $new_cfg_location										= _( $self, 'btnCfgLocation' ) 				-> get_uri // "$ENV{HOME}/.config/pac";
	#$new_cfg_location											=~ s/^file:\/\///go;
	#if ( $new_cfg_location ne $$self{_CFG}{'defaults'}{'config location'} ) {
	#	system( "mv $$self{_CFG}{'defaults'}{'config location'} $new_cfg_location" );
	#	if ( -d $new_cfg_location ) {
	#		system( "rm -rf $ENV{HOME}/.config/pac" );
	#		system( "ln -s $new_cfg_location/pac $ENV{HOME}/.config/pac" );
	#	}
	#}
	#$$self{_CFG}{'defaults'}{'config location'} = $new_cfg_location;
	
	_( $self, 'rbCfgStartTreeConn' ) 	-> get_active and $$self{_CFG}{'defaults'}{'start PAC tree on'} = 'connections';
	_( $self, 'rbCfgStartTreeFavs' ) 	-> get_active and $$self{_CFG}{'defaults'}{'start PAC tree on'} = 'favourites';
	_( $self, 'rbCfgStartTreeHist' ) 	-> get_active and $$self{_CFG}{'defaults'}{'start PAC tree on'} = 'history';
	_( $self, 'rbCfgStartTreeCluster' ) -> get_active and $$self{_CFG}{'defaults'}{'start PAC tree on'} = 'clusters';
	
	unlink( $ENV{'HOME'} . '/.config/autostart/pac_start.desktop' );
	$$self{_CFG}{'defaults'}{'start at session startup'} = 0;
	if ( _( $self, 'cbCfgAutoStart' ) -> get_active ) {
		$PACUtils::PACDESKTOP[6] = 'Exec=/usr/bin/pac --no-splash' . ( $$self{_CFG}{'defaults'}{'start iconified'} ? ' --iconified' : '' );
		open F, ">$ENV{HOME}/.config/autostart/pac_start.desktop"; print F join( "\n", @PACUtils::PACDESKTOP ); close F;
		$$self{_CFG}{'defaults'}{'start at session startup'} = 1;
	}
	
	$$self{_CFG}{'environments'}{'__PAC_SHELL__'}{'terminal options'}	= $$self{_SHELL}		-> get_cfg;	# Save the global variables tab options
	$$self{_CFG}{'defaults'}{'global variables'}						= $$self{_VARIABLES}	-> get_cfg;	# Save the global variables tab options
	$$self{_CFG}{'defaults'}{'local commands'}							= $$self{_CMD_LOCAL}	-> get_cfg;	# Save the global local commands tab options
	$$self{_CFG}{'defaults'}{'remote commands'}							= $$self{_CMD_REMOTE}	-> get_cfg;	# Save the global remote commands tab options
	$$self{_CFG}{'defaults'}{'keepass'}									= $$self{_KEEPASS}		-> get_cfg;	# Save KeePass options
	
	$PACMain::FUNCS{_MAIN} -> _setCFGChanged( 1 );
	$self -> _updateGUIPreferences;
	
	$PACMain::FUNCS{_MAIN} -> _updateGUIPreferences;
	
	# Send a signal to every started terminal for this $uuid to realize the new global CFG
	map { eval { $$_{'terminal'} -> _updateCFG; }; } ( values %PACMain::RUNNING );
	
	return 1;
}

# END: Define PRIVATE CLASS functions
###################################################################

1;
