package PACTerminal;

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
use lib $RealBin . '/lib', $RealBin . '/lib/ex';
use Storable qw ( dclone nstore nstore_fd fd_retrieve );
use POSIX qw ( strftime );
use File::Copy;
use Encode qw ( encode decode );
use IO::Socket::INET;
use Time::HiRes qw ( gettimeofday );
use KeePass;

# GTK2
use Gtk2 '-init';
use Gtk2::Ex::Simple::List;
eval { require Gtk2::SourceView2; };
my $SOURCEVIEW = ! $@;

# PAC modules
use PACUtils;

# END: Import Modules
###################################################################

###################################################################
# Define GLOBAL CLASS variables

my $APPNAME		= $PACUtils::APPNAME;
my $APPVERSION	= $PACUtils::APPVERSION;
my $APPICON		= $RealBin . '/res/asbru-logo-64.png';
my $CFG_DIR		= $ENV{'HOME'} . '/.config/pac';

my $PERL_BIN	= '/usr/bin/perl';
my $PAC_CONN	= $RealBin . '/lib/pac_conn';

my $SHELL_BIN	= -x '/bin/sh' ? '/bin/sh' : '/bin/bash';
my $SHELL_NAME	= -x '/bin/sh' ? 'sh' : 'bash';

my $_C			= 1;
my $EXEC_STORM_TIME	= 0.2;

my @KPX;

# END: Define GLOBAL CLASS variables
###################################################################

###################################################################
# START: Define CLASS methods

# CONSTRUCTOR: build GUI and setup callbacks
sub new {
	my $class = shift;
	my $self = {};
	
	$self -> {_CFG}				= shift;
	$self -> {_UUID}			= shift;
	$self -> {_NOTEBOOK}		= shift;
	$self -> {_NOTEBOOKWINDOW}	= shift;
	$self -> {_CLUSTER}			= shift // '';
	$self -> {_MANUAL}			= shift;
	
	$self -> {_TABBED}			= $self -> {_CFG}{'environments'}{ $$self{'_UUID' } }{'terminal options'}{'use personal settings'} ? $self -> {_CFG}{'environments'}{ $$self{'_UUID'} }{'terminal options'}{'open in tab'} // 1 : $self -> {_CFG}{'defaults'}{'open connections in tabs'} // 1;
	$self -> {_NAME}			= $self -> {_CFG}{'environments'}{ $$self{'_UUID' } }{'name'};
	$self -> {_SPLIT}			= 0;
	$self -> {_SPLIT_VPANE}		= 0;
	$self -> {_SPLIT_VERTICAL}	= 0;
	$self -> {_POST_SPLIT}		= 0;
	$self -> {_PROPAGATE}		= 1;
	$self -> {_NO_UPDATE_CFG}	= 0;
	$self -> {_LAST_STATUS}		= 'DISCONNECTED';
	$self -> {_STATUS_UPDATER}	= 0;
	$self -> {_STATUS_COUNT}	= 0;
	$self -> {_LISTEN_COMMIT}	= 1;
	$self -> {_RESTART}			= 0;
	$self -> {_GUI}				= undef;
	$self -> {_KEYS_BUFFER}		= '';
	$self -> {_SAVE_KEYS}		= 1;
	$self -> {_HAVE_PROMPT}		= 0;
	$self -> {_INTRO_PRESS}		= 0;
	
	$self -> {_SCRIPT_STATUS}	= 'STOP';
	$self -> {_SCRIPT_NAME}		= '';
	
	$self -> {_EXEC}			= {};
	$self -> {_EXEC_LAST}		= join( '.', gettimeofday );
	
	$self -> {_BADEXIT}			= 1;
	$self -> {_GUILOCKED}		= 0;
	$self -> {CONNECTED}		= 0;
	$self -> {CONNECTING}		= 0;
	$self -> {ERROR}			= '';
	$self -> {_FULLSCREEN}		= 0;
	$self -> {_FSTOTAB}			= 0;
	$self -> {_NEW_DATA}		= 0;
	$self -> {_FOCUSED}			= 0;
	$self -> {FOCUS}			= 0;
	$self -> {EMBED}			= $self -> {_CFG}{'environments'}{ $$self{_UUID} }{'embed'};
	
	$self -> {_UUID_TMP}		= 'pac_PID' . $$ . '_n' . ++$_C;
	
	if ( $self -> {_CFG}{'environments'}{ $$self{_UUID} }{'save session logs'} ) {
		$self -> {_LOGFILE}	= $self -> {_CFG}{'environments'}{ $$self{_UUID} }{'session logs folder'} . '/';
		$self -> {_LOGFILE}	.= _subst( $self -> {_CFG}{'environments'}{ $$self{_UUID} }{'session log pattern'}, $$self{_CFG}, $$self{_UUID} );
	} elsif ( $self -> {_CFG}{'defaults'}{'save session logs'} ) {
		$self -> {_LOGFILE}	= $self -> {_CFG}{'defaults'}{'session logs folder'} . '/';
		$self -> {_LOGFILE}	.= _subst( $self -> {_CFG}{'defaults'}{'session log pattern'}, $$self{_CFG}, $$self{_UUID} );
	} else {
		$self -> {_LOGFILE}	= $CFG_DIR . '/tmp/' . $$self{_UUID_TMP} . '.txt';
	}
	$self -> {_TMPCFG}		= $CFG_DIR . '/tmp/' . $$self{_UUID_TMP} . '.freeze';
	
	$self -> {_TMPPIPE}		= $CFG_DIR . '/tmp/pac_PID' . $$ . '_n' . $_C . '.pipe';
	while ( -f $$self{_TMPPIPE} ) { $$self{_TMPPIPE} = $CFG_DIR . '/tmp/pac_PID' . $$ . '_n' . ++$_C . '.pipe'; }
	unlink $$self{_TMPPIPE};
	
	$self -> {_TMPSOCKET}	= $CFG_DIR . '/sockets/pac_PID' . $$ . '_n' . $_C . '.socket';
	while ( -f $$self{_TMPSOCKET} ) { $$self{_TMPSOCKET} = $CFG_DIR . '/sockets/pac_PID' . $$ . '_n' . ++$_C . '.socket'; }
	unlink $$self{_TMPSOCKET};
	
	$self -> {_TMPSOCKETEXEC}	= $CFG_DIR . '/sockets/pac_PID' . $$ . '_n' . $_C . '.exec.socket';
	while ( -f $$self{_TMPSOCKETEXEC} ) { $$self{_TMPSOCKETEXEC} = $CFG_DIR . '/sockets/pac_PID' . $$ . '_n' . ++$_C . '.exec.socket'; }
	unlink $$self{_TMPSOCKETEXEC};
	
	$self -> {_CMD}			= '';
	$self -> {_PID}			= 0;
	$self -> {_HISTORY}		= ();
	$self -> {_TEXT}		= ();
	
	# Prepare the title
	my $name	= $$self{_CFG}{'environments'}{ $$self{_UUID} }{'name'};
	my $title	= $$self{_CFG}{'environments'}{ $$self{_UUID} }{'title'};
	$$self{_TITLE} = $title || $name;
	$$self{_TITLE} = _subst( $$self{_TITLE}, $$self{_CFG}, $$self{_UUID} );
	
	# Build the GUI
	_initGUI( $self )								or return 0;
	# Setup callbacks
	_setupCallbacks( $self )						or return 0;
	# Load connection methods
	%{ $$self{_METHODS} } = _getMethods( $self )	or return 0;
	
	$PACMain::RUNNING{$$self{'_UUID_TMP'}}{'uuid'}		= $$self{'_UUID'};
	$PACMain::RUNNING{$$self{'_UUID_TMP'}}{'terminal'}	= $self;
	$PACMain::RUNNING{$$self{'_UUID_TMP'}}{'is_shell'}	= 0;
	
	$self -> {_EXPECTED}	= 0;
	$self -> {_PULSE}		= 1;
	$self -> {_TOTAL}		= 0;
	
	$self -> {_SOCKET_CONN}		= undef;
	$self -> {_SOCKET_CLIENT}	= undef;
	
	$self -> {_SOCKET_CONN} = IO::Socket::UNIX -> new(
		Type	=> SOCK_STREAM,
		Listen	=> 1,
		Local	=> $$self{_TMPSOCKET}
	) or die "ERROR:$!";
	
	$self -> {_SOCKET_CONN_EXEC} = IO::Socket::UNIX -> new(
		Type	=> SOCK_STREAM,
		Listen	=> 1,
		Local	=> $$self{_TMPSOCKETEXEC}
	) or die "ERROR:$!";
	
	
	# Add a Glib watcher to listen to new connections (in a non-blocking fashion)
	$self -> {_SOCKET_WATCH_EXEC} = Glib::IO -> add_watch( fileno( $self -> {_SOCKET_CONN_EXEC} ), [ 'in', 'hup', 'err' ], sub {
		my ( $fd, $cond, $self ) = @_;
		
		my $tmp_client;
		do { $tmp_client = $self -> {_SOCKET_CONN_EXEC} -> accept } until defined $tmp_client;
		
		$self -> {_SOCKET_CLIENT_EXEC} = $tmp_client;
		$self -> {_SOCKET_CLIENT_EXEC} -> blocking( 0 );
		
		return 1;
		
	}, $self );
	
	# Add a Glib watcher to listen to new connections (in a non-blocking fashion)
	$self -> {_SOCKET_WATCH} = Glib::IO -> add_watch( fileno( $self -> {_SOCKET_CONN} ), [ 'in', 'hup', 'err' ], sub {
		my ( $fd, $cond, $self ) = @_;
		
		if ( ( $cond >= 'hup' ) || ( $cond >= 'err' ) ) {
			$self -> {_SOCKET_CONN} -> close if defined $self -> {_SOCKET_CONN};
			_wMessage( undef, 'Master socket at port ' . $self -> {_SOCKET_PORT} . ' was closed !!' );
			return 0;
		}
		
		my $tmp_client;
		do { $tmp_client = $self -> {_SOCKET_CONN} -> accept } until defined $tmp_client;
		
		# Make sure that this client is a PAC client:
		return 1 unless $self -> _authClient( $tmp_client );
		
		$self -> {_SOCKET_CLIENT} = $tmp_client;
		$self -> {_SOCKET_CLIENT} -> blocking( 0 );
		
		# Once we got the client, add a new Glib watcher to listen to incoming data from that client
		$self -> {_SOCKET_CLIENT_WATCH} = Glib::IO -> add_watch( fileno( $self -> {_SOCKET_CLIENT} ), [ 'in', 'hup', 'err' ], \&_watchConnectionData, $self );
		
		return 1;
		
	}, $self );
	
	# If KeePass is selected, load it's database and prepare submenu for VTE right-click
	if ( $$self{_CFG}{'defaults'}{'keepass'}{'use_keepass'} ) {
		foreach my $hash ( $PACMain::FUNCS{_KEEPASS} -> find ) {
			push( @KPX,
			{
				label => "Title: '$$hash{title}', Username: '$$hash{username}'",
				tooltip => "$$hash{password}",
				code => sub { $$self{_GUI}{_VTE} -> feed_child( $$hash{password} ); }
			} );
		}
	}
	#Accessability shortcuts
	$$self{variables}=$$self{_CFG}{environments}{$$self{_UUID}}{variables};
	
	bless( $self, $class );
	return $self;
}

# DESTRUCTOR
sub DESTROY {
	my $self = shift;
	$self -> {_SOCKET_CONN} -> close if defined $self -> {_SOCKET_CONN};
	$self -> {_SOCKET_CLIENT} -> close if defined $self -> {_SOCKET_CLIENT};
	undef $self;
	return 1;
}

# Launch connection
sub start {
	my $self = shift;
	$$self{_KEYS_RECEIVE} = shift // undef;
	
	return 1 if $$self{CONNECTED} || $$self{CONNECTING};
	
	my $name	= $$self{_CFG}{'environments'}{ $$self{_UUID} }{'name'};
	my $title	= $$self{_CFG}{'environments'}{ $$self{_UUID} }{'title'};
	my $method	= $$self{_CFG}{'environments'}{ $$self{_UUID} }{'method'};

	my $string = $method eq 'generic' ? "LAUNCHING '$title'" : "CONNECTING WITH '$title'";
	$$self{_GUI}{_VTE} -> feed( "\e[1;32m\r\n $string (" . ( localtime( time ) ) . ") =->\e[0m\r\n\n" );
	
	$$self{_PULSE} = 1;
	
	# Check for pre-connection commands execution
	$self -> _wPrePostExec( 'local before');
	
	# Prepare a timer to "pulse" the progress bar while connecting
	$$self{_PULSE_TIMER} = Glib::Timeout -> add ( 100, sub {
		if ( $$self{_PULSE} && defined $$self{_GUI}{pb} && $$self{_GUI}{pb} -> get_property( 'visible' ) ) {
			$$self{_GUI}{pb} -> pulse;
			return 1;
		} else {
			delete $$self{_PULSE_TIMER};
			return 0;
		}
	} );
	
	$$self{_CFG}{'tmp'}{'log file'}		= $$self{_LOGFILE};
	$$self{_CFG}{'tmp'}{'socket'}		= $$self{_TMPSOCKET};
	$$self{_CFG}{'tmp'}{'socket exec'}	= $$self{_TMPSOCKETEXEC};
	$$self{_CFG}{'tmp'}{'uuid'}			= $$self{_UUID_TMP};
	
	if ( $$self{'EMBED'} ) {
		$$self{_CFG}{'tmp'}{'xid'} = $$self{_GUI}{_SOCKET} -> window -> get_xid;
		
		my $req = $$self{_GUI}{_SOCKET} -> allocation;
		$$self{_CFG}{'tmp'}{'width'}	= $req -> width;
		$$self{_CFG}{'tmp'}{'height'}	= $req -> height;
		if ( $$self{_CFG}{'tmp'}{'width'} <= 1 ) {
			$req = $$self{_NOTEBOOK} -> allocation;
			$$self{_CFG}{'tmp'}{'width'}	= $req -> width - 10;
			$$self{_CFG}{'tmp'}{'height'}	= $req -> height - 85;
		}
		eval { $PACMain::FUNCS{_MAIN}{_GUI}{vbox3} -> get_visible or $$self{_CFG}{'tmp'}{'width'} += $PACMain::FUNCS{_MAIN}{_GUI}{vbox3} -> allocation -> width; };
	} else {
		delete $$self{_CFG}{'tmp'}{'xid'};
		delete $$self{_CFG}{'tmp'}{'width'};
		delete $$self{_CFG}{'tmp'}{'height'};
	}
	
	# Duplicate and dump non-persistent configuration into temporal file for 'pac_conn'
	my %new_cfg;
	$new_cfg{'defaults'}						= dclone( $$self{_CFG}{'defaults'} );
	$new_cfg{'environments'}{ $$self{_UUID} }	= dclone( $$self{_CFG}{'environments'}{ $$self{_UUID} } );
	$new_cfg{'tmp'}								= dclone( $$self{_CFG}{'tmp'} );
	@{ $new_cfg{'keepass'} }					= $PACMain::FUNCS{_KEEPASS} -> find;
	$new_cfg{'environments'}{ $$self{_UUID} }{'auth type'} = $$self{_MANUAL} if defined $$self{_MANUAL};
	nstore( \%new_cfg, $$self{_TMPCFG} ) or die"ERROR: Could not save PAC config file '$$self{_TMPCFG}': $!";
	undef %new_cfg;
	
	# Delete the oldest auto-saved session log
	if ( $$self{_CFG}{'environments'}{ $$self{_UUID} }{'save session logs'} ) {
		_deleteOldestSessionLog( $$self{_UUID}, $$self{_CFG}{'environments'}{ $$self{_UUID} }{'session logs folder'}, $$self{_CFG}{'environments'}{ $$self{_UUID} }{'session logs amount'} );
	} elsif( $$self{_CFG}{'defaults'}{'save session logs'} ) {
		_deleteOldestSessionLog( $$self{_UUID}, $$self{_CFG}{'defaults'}{'session logs folder'},  $$self{_CFG}{'defaults'}{'session logs amount'} );
	}
	
	$$self{CONNECTING} = 1;
	$PACMain::FUNCS{_STATS} -> start( $$self{_UUID} );
	# Start and fork our connector
	my @fork_cmd;
	if ( $$self{_CFG}{'defaults'}{'use login shell to connect'} ) { @fork_cmd = ( $SHELL_BIN, [ $SHELL_NAME, '-l', '-c', "($PERL_BIN $PAC_CONN $$self{_TMPCFG} $$self{_UUID}; exit)" ], undef, '', 0, 0, 0 ); }
	else { @fork_cmd = ( $PERL_BIN, [ 'perl', $PAC_CONN, $$self{_TMPCFG}, $$self{_UUID} ], undef, '', 0, 0, 0 ); }
	if ( ! $$self{_GUI}{_VTE} -> fork_command( @fork_cmd ) ) {
		$$self{ERROR} = "ERROR: VTE could not fork command '$PAC_CONN $$self{_TMPCFG} $$self{_UUID}'!!";
		$$self{CONNECTING} = 0;
		return 0;
	}
	
	# ... and save its data
	$PACMain::RUNNING{ $$self{'_UUID_TMP'} }{'uuid'} = $$self{_UUID};
	$PACMain::RUNNING{ $$self{'_UUID_TMP'} }{'start_time'} = time;

	foreach my $exp ( @{ $$self{_CFG}{'environments'}{ $$self{_UUID} }{'expect'} } ) { next unless ( $$exp{'active'} // 0 ); ++$$self{_TOTAL}; }
	
	# Create a progressbar and add it to GUI's bottombox
	$$self{_GUI}{pb} = Gtk2::ProgressBar -> new;
	$$self{_GUI}{bottombox} -> pack_start( $$self{_GUI}{pb}, 0, 1, 0 );
	$$self{_GUI}{pb} -> show;
	
	$$self{_CLUSTER} and $PACMain::FUNCS{_CLUSTER} -> addToCluster( $$self{_UUID_TMP}, $$self{_CLUSTER} );
	
	# Create a Glib timeout to programatically send a given string to the connected terminal (if so is configured!)
	defined $$self{_SEND_STRING} and Glib::Source -> remove( $$self{_SEND_STRING} );
	$$self{_CFG}{environments}{ $$self{_UUID} }{'send string active'} and $$self{_SEND_STRING} = Glib::Timeout -> add_seconds(
		$$self{_CFG}{environments}{ $$self{_UUID} }{'send string every'},
		sub {
			return 1 unless $$self{CONNECTED} && $$self{_CFG}{environments}{ $$self{_UUID} }{'send string active'};
			
			my $txt		= $$self{_CFG}{environments}{ $$self{_UUID} }{'send string txt'};
			my $intro	= $$self{_CFG}{environments}{ $$self{_UUID} }{'send string intro'};
			$txt		= _subst( $txt, $$self{_CFG}, $$self{_UUID} );
			$$self{_GUI}{_VTE} -> feed_child( $txt . ( $intro ? "\n" : '' ) );
			
			return 1;
		}
	);
	
	$$self{_CFG}{'environments'}{$$self{_UUID}}{'startup script'} and $PACMain::FUNCS{_SCRIPTS} -> _execScript( $$self{_CFG}{'environments'}{$$self{_UUID}}{'startup script name'}, $$self{_UUID_TMP} );
	
	return 1;
}

# Stop and close GUI
sub stop {
	my $self	= shift;
	my $force	= shift // 0;
	my $deep	= shift // 0;
	
	my $name	= $self -> {_CFG}{'environments'}{ $$self{_UUID} }{'name'};
	my $title	= $self -> {_CFG}{'environments'}{ $$self{_UUID} }{'title'};
	
	# First of all, save THIS page's widget (to prevent closing a not selected tab)
	my $p_widget = $$self{_GUI}{_VBOX};
	
	# May be user wants to close without confirmation...
	if ( ( ! $force ) && ( $self -> {CONNECTED} ) ) {
		# Ask for confirmation
		return 1 unless _wConfirm( $$self{GUI}{_VBOX}, "Are you sure you want to close '" . ( $$self{_SPLIT} ? 'this split tab' : $$self{_TITLE} ) . "'?" );
		
		# Check for post-connection commands execution
		$$self{CONNECTED} and $self -> _wPrePostExec( 'local after');
	} elsif ( ! $force ) {
		# Check for post-connection commands execution
		$$self{CONNECTED} and $self -> _wPrePostExec( 'local after');
	}
	
	# Send any configured keypress to close the forked binary
	if ( $$self{CONNECTED} && defined $$self{_METHODS}{ $$self{_CFG}{'environments'}{ $$self{_UUID} }{'method'} }{'escape'} ) {
		foreach my $esc ( @{ $$self{_METHODS}{ $$self{_CFG}{'environments'}{ $$self{_UUID} }{'method'} }{'escape'} } ) {
			$$self{_GUI}{_VTE} -> feed_child( $esc );
		}
	}
	
	$$self{_GUI}{_VTE} -> feed_child( "__PAC__STOP__$$self{_UUID}__$$self{_PID}__" );
	
	$$self{CONNECTED} = 0;
	
	( $$self{_SPLIT} && $PACMain::RUNNING{$$self{_SPLIT}}{terminal}{CONNECTED} ) and return 1;
	( $$self{_SPLIT} && $deep ) and $PACMain::RUNNING{$$self{_SPLIT}}{terminal} -> stop( 1, 0 );
	
	
	# Finish the GUI
	if ( $$self{_TABBED} ) {
		my $p_num = -1;
		if ( $$self{_SPLIT} ) {
			$p_num = $$self{_NOTEBOOK} -> page_num( $p_widget -> get_parent );
		} else {
			$p_num = $$self{_NOTEBOOK} -> page_num( $p_widget );
		}
		
		# Skip destruction if this tab does not exists after having answered to _wConfirm
		$$self{_NOTEBOOK} -> remove_page( $p_num ) if $p_num >= 0;
	} else {
		$$self{_WINDOWTERMINAL} -> destroy;
	}
	
	# Try to ensure we leave no background "pac_conn" processes running after closing the terminal
	$$self{_PID} and kill( 15, $$self{_PID} );
	$$self{_PID} and $PACMain::FUNCS{_STATS} -> stop( $$self{_UUID} );
	
	# Delete me from the running terminals list
	delete $PACMain::RUNNING{$$self{_UUID_TMP}};
	$PACMain::FUNCS{_CLUSTER} -> _updateGUI;
	
	defined $$self{_SOCKET_CLIENT} and $$self{_SOCKET_CLIENT} -> close;
	defined $$self{_SOCKET_CLIENT_WATCH}	and eval { Glib::Source -> remove( $$self{_SOCKET_CLIENT_WATCH} ); };
	defined $$self{_SEND_STRING}			and eval { Glib::Source -> remove( $$self{_SEND_STRING} ); };
	defined $$self{_EMBED_KIDNAP}			and eval { Glib::Source -> remove( $$self{_EMBED_KIDNAP} ); };
	
	unlink( $$self{_TMPCFG} );
	unlink( $$self{_TMPPIPE} );
	unlink( $$self{_TMPSOCKET} );
	unlink( $$self{_LOGFILE} ) unless ( $self -> {_CFG}{'defaults'}{'save session logs'} || $self -> {_CFG}{'environments'}{ $$self{_UUID} }{'save session logs'} );
	
	# If I was a temporal UUID, delete me
	$$self{_UUID} =~ /^_tmp_/go and delete $$self{_CFG}{environments}{ $$self{_UUID} };
	
	# And delete ourselves
	$$self{_GUI} = undef;
	undef $self;
	
	return 1;
}

sub lock {
	my $self = shift;
	$$self{_TABBED} and $$self{_GUI}{_TABLBL} -> set_sensitive( 0 );
	$$self{_GUI}{_VBOX} -> set_sensitive( 0 );
	$$self{_GUI}{_VTE} -> set_background_transparent( 1 );
	$$self{_GUI}{_VTE} -> set_background_saturation( 1 );
	$$self{_GUILOCKED} = 1;
	return 1;
}

sub unlock {
	my $self = shift;
	$$self{_TABBED} and $$self{_GUI}{_TABLBL} -> set_sensitive( 1 );
	$$self{_GUI}{_VBOX} -> set_sensitive( 1 );
	$self -> _updateCFG;
	$$self{_GUILOCKED} = 0;
	return 1;
}

# END: Define CLASS methods
###################################################################

###################################################################
# START: Private functions definitions

sub _initGUI {
	my $self	= shift;
	
	my $tabs	= $$self{_NOTEBOOK};

	# Create a GtkVBox and its child widgets:
	$$self{_GUI}{_VBOX} = Gtk2::VBox -> new( 0, 0 );
		
		$$self{_GUI}{_HBOX} = Gtk2::HPaned -> new;	
		
		#### $vbox 1st row: this will contain an HBOX with Gnome's VTE and keypresses list
		
		# Create a GtkScrolledWindow,
		my $sc = Gtk2::ScrolledWindow -> new;
		$sc -> set_shadow_type( 'none' );
		$sc -> set_policy( 'automatic', 'automatic' );
		
		# , build a Gnome VTE Terminal,
		$$self{_GUI}{_VTE} = Gnome2::Vte::Terminal -> new;
		$$self{_GUI}{_VTE} -> set_size_request( 200, 100 );
		
		# , add VTE to the scrolled window and...
		$sc -> add( $$self{_GUI}{_VTE} );
		
		$$self{_GUI}{hbHist} = Gtk2::VBox -> new( 0, 0 );
			
			# Create a scrolled window for the keypress list
			$$self{_GUI}{sk} = Gtk2::ScrolledWindow -> new;
			$$self{_GUI}{hbHist} -> pack_start( $$self{_GUI}{sk}, 1, 1, 0 );
			$$self{_GUI}{sk} -> set_policy( 'automatic', 'automatic' );
			$$self{_GUI}{sk} -> set_size_request( 120, 100 );
			$$self{_GUI}{treeKeys} = Gtk2::Ex::Simple::List -> new( ' HISTORY' => 'text', 'TIME' => 'hidden' );
			$$self{_GUI}{treeKeys} -> get_selection -> set_mode( 'single' );
			$$self{_GUI}{sk} -> add( $$self{_GUI}{treeKeys} );
			$$self{_GUI}{treeKeys} -> set_headers_visible( 1 );
			$$self{_GUI}{treeKeys} -> set_enable_search( 0 );
			eval { $$self{_GUI}{treeKeys} -> set_can_focus( 0 ); };
			
			# Create a button to remove history
			$$self{_GUI}{btnDelHist} = Gtk2::Button -> new( 'Forget history' );
			$$self{_GUI}{hbHist} -> pack_start( $$self{_GUI}{btnDelHist}, 0, 0, 0 );
			$$self{_GUI}{btnDelHist} -> set_image( Gtk2::Image -> new_from_stock( 'gtk-delete', 'button' ) );
			eval { $$self{_GUI}{btnDelHist} -> set_can_focus( 0 ); };
		
		if ( ! $$self{'EMBED'} ) {
			$$self{_GUI}{_VBOX} -> pack_start( $$self{_GUI}{_HBOX}, 1, 1, 0 );
			
			# ... put this scrolled vte in $vbox
			$$self{_GUI}{_HBOX} -> pack1( $sc, 1, 0 );
			$$self{_GUI}{_HBOX} -> pack2( $$self{_GUI}{hbHist}, 1, 0 );
			$$self{_GUI}{_HBOX} -> set_position( 3000 );
			
			$$self{FOCUS} = $$self{_GUI}{_VTE};
		} else {
			my $sc2 = Gtk2::ScrolledWindow -> new;
			$sc2 -> set_shadow_type( 'none' );
			$sc2 -> set_policy( 'automatic', 'automatic' );
			$$self{_GUI}{_VBOX} -> pack_start( $sc2, 1, 1, 0 );
				
				$$self{_GUI}{_SOCKET} = Gtk2::Socket -> new;
				$sc2 -> add_with_viewport( $$self{_GUI}{_SOCKET} );
			
			$$self{_GUI}{_BTNFOCUS} = Gtk2::Button -> new_with_mnemonic( 'Set _keyboard focus' );
			$$self{_GUI}{_BTNFOCUS} -> set_image( Gtk2::Image -> new_from_icon_name( 'input-keyboard', 'GTK_ICON_SIZE_SMALL_TOOLBAR' ) );
			$$self{_GUI}{_BTNFOCUS} -> set( 'can_focus', 0 );
			$$self{_GUI}{_VBOX} -> pack_start( $$self{_GUI}{_BTNFOCUS}, 0, 1, 0 );
			
			$$self{FOCUS} = $$self{_GUI}{_SOCKET};
		}
		
		#### $vbox 2nd row: this will contain local/remote macros
		
		# MACROS Combobox??
		if ( $$self{_CFG}{'defaults'}{'show commands box'} == 1 ) {
			$$self{_GUI}{_MACROSBOX} = Gtk2::HBox -> new( 0, 0 );
			$$self{_GUI}{_VBOX} -> pack_start( $$self{_GUI}{_MACROSBOX}, 0, 1, 0 );
			
			# Create a GtkButton and add it to $macrosbox
			$$self{_GUI}{_BTNLOCALTERMINALEXEC} = Gtk2::Button -> new_with_mnemonic( '_Local' );
			$$self{_GUI}{_BTNLOCALTERMINALEXEC} -> set_property( 'can_focus', 0 );
			$$self{_GUI}{_BTNLOCALTERMINALEXEC} -> set_sensitive( 0 );
			$$self{_GUI}{_BTNLOCALTERMINALEXEC} -> set_image( Gtk2::Image -> new_from_stock( 'gtk-execute', 'GTK_ICON_SIZE_SMALL_TOOLBAR' ) );
			$$self{_GUI}{_BTNLOCALTERMINALEXEC} -> set_size_request( 60, 25 );
			$$self{_GUI}{_BTNLOCALTERMINALEXEC} -> set( 'can_focus', 0 );
			$$self{_GUI}{_MACROSBOX} -> pack_start( $$self{_GUI}{_BTNLOCALTERMINALEXEC}, 0, 1, 0 );
			
			# Create a GtkComboBox and add it to $macrosbox
			$$self{_GUI}{_CBLOCALEXECTERMINAL} = Gtk2::ComboBox -> new_text;
			$$self{_GUI}{_CBLOCALEXECTERMINAL} -> set_property( 'can_focus', 0 );
			$$self{_GUI}{_CBLOCALEXECTERMINAL} -> set_size_request( 200, -1 ); # Limit combobox hsize!!
			$$self{_GUI}{_CBLOCALEXECTERMINAL} -> set_sensitive( 0 );
			$$self{_GUI}{_CBLOCALEXECTERMINAL} -> set_size_request( 30, 25 );
			$$self{_GUI}{_CBLOCALEXECTERMINAL} -> set( 'can_focus', 0 );
			$$self{_GUI}{_MACROSBOX} -> pack_start( $$self{_GUI}{_CBLOCALEXECTERMINAL}, 1, 1, 0 );
			
			# Checkbutton to send or not to all terminals in cluster
			$$self{_GUI}{_MACROSCLUSTER} = Gtk2::CheckButton -> new_with_label( 'Sending THIS: ' );
			$$self{_GUI}{_MACROSCLUSTER} -> set( 'can-focus', 0 );
			$$self{_GUI}{_MACROSCLUSTER} -> signal_connect( 'toggled', sub { $$self{_GUI}{_MACROSCLUSTER} -> set_label( $$self{_GUI}{_MACROSCLUSTER} -> get_active ? 'Sending CLUSTER: ' : 'Sending THIS: ' ); } );
			$$self{_GUI}{_MACROSBOX} -> pack_start( $$self{_GUI}{_MACROSCLUSTER}, 0, 1, 0 );
			
			# Create a GtkComboBox and add it to $macrosbox
			$$self{_GUI}{_CBMACROSTERMINAL} = Gtk2::ComboBox -> new_text;
			$$self{_GUI}{_CBMACROSTERMINAL} -> set_property( 'can_focus', 0 );
			$$self{_GUI}{_CBMACROSTERMINAL} -> set_size_request( 200, -1 ); # Limit combobox hsize!!
			$$self{_GUI}{_CBMACROSTERMINAL} -> set_sensitive( 0 );
			$$self{_GUI}{_CBMACROSTERMINAL} -> set_size_request( 60, 25 );
			$$self{_GUI}{_CBMACROSTERMINAL}	-> set( 'can_focus', 0 );
			$$self{_GUI}{_MACROSBOX} -> pack_start( $$self{_GUI}{_CBMACROSTERMINAL}, 1, 1, 0 );
			
			# Create a GtkButton and add it to $macrosbox
			$$self{_GUI}{_BTNMACROSTERMINALEXEC} = Gtk2::Button -> new_with_mnemonic( '_Remote' );
			$$self{_GUI}{_BTNMACROSTERMINALEXEC} -> set_property( 'can_focus', 0 );
			$$self{_GUI}{_BTNMACROSTERMINALEXEC} -> set_sensitive( 0 );
			$$self{_GUI}{_BTNMACROSTERMINALEXEC} -> set_image( Gtk2::Image -> new_from_stock( 'gtk-execute', 'GTK_ICON_SIZE_SMALL_TOOLBAR' ) );
			$$self{_GUI}{_BTNMACROSTERMINALEXEC} -> set_size_request( 70, 25 );
			$$self{_GUI}{_BTNMACROSTERMINALEXEC} -> set( 'can_focus', 0 );
			$$self{_GUI}{_MACROSBOX} -> pack_start( $$self{_GUI}{_BTNMACROSTERMINALEXEC}, 0, 1, 0 );
		}
		# MACROS Buttonbox??
		elsif ( $$self{_CFG}{'defaults'}{'show commands box'} == 2 )
		{
			$$self{_GUI}{_SCROLLMACROS} = Gtk2::ScrolledWindow -> new;
			$$self{_GUI}{_SCROLLMACROS} -> set_policy( 'automatic', 'never' );
			$$self{_GUI}{_MACROSBOX} = Gtk2::HBox -> new( 0, 0 );
			$$self{_GUI}{_SCROLLMACROS} -> add_with_viewport( $$self{_GUI}{_MACROSBOX} );
			
			$$self{_GUI}{_VBOX} -> pack_start( $$self{_GUI}{_SCROLLMACROS}, 0, 1, 0 );
		}
		
		$$self{_GUI}{_MACROSBOX} -> hide_all if defined $$self{_GUI}{_MACROSBOX};
		
		# bottombox will contain both progress and status bar
		$$self{_GUI}{bottombox} = Gtk2::HBox -> new( 0, 0 );
		$$self{_GUI}{_VBOX} -> pack_end( $$self{_GUI}{bottombox}, 0, 1, 0 ) if $$self{_CFG}{defaults}{'terminal show status bar'};
			
			# Create a checkbox to show or not commands history tree
			$$self{_GUI}{cbShowHist} = Gtk2::CheckButton -> new( 'Show command history' );
			eval { $$self{_GUI}{cbShowHist} -> set_can_focus( 0 ); };
			$$self{_GUI}{bottombox} -> pack_end( $$self{_GUI}{cbShowHist}, 0, 1, 0 );
			
			# Create gtkstatusbar
			$$self{_GUI}{status} = Gtk2::Statusbar -> new;
			$$self{_GUI}{bottombox} -> pack_end( $$self{_GUI}{status}, 1, 1, 0 );
			$$self{_GUI}{status} -> set_has_resize_grip( ! $$self{_CFG}{defaults}{'tabs in main window'} );
			
			# Create a status icon
			$$self{_GUI}{statusIcon} = Gtk2::Image -> new_from_stock( 'pac-terminal-ko-small', 'button' );
			$$self{_GUI}{statusIcon} -> set_tooltip_text( 'DISCONNECTED' );
			$$self{_GUI}{bottombox} -> pack_start( $$self{_GUI}{statusIcon}, 0, 0, 0 );
			
			# Create an Expect execute icon
			$$self{_GUI}{statusExpect} = Gtk2::Image -> new_from_stock( 'none', 'button' );
			$$self{_GUI}{statusExpect} -> set_tooltip_text( 'DISCONNECTED' );
			$$self{_GUI}{bottombox} -> pack_start( $$self{_GUI}{statusExpect}, 0, 0, 0 );
			
			# Create a cluster icon
			$$self{_GUI}{statusCluster} = Gtk2::Image -> new_from_stock( 'pac-cluster-manager-off', 'button' );
			$$self{_GUI}{statusCluster} -> set_tooltip_text( 'Unclustered' );
			$$self{_GUI}{bottombox} -> pack_start( $$self{_GUI}{statusCluster}, 0, 0, 0 );
	
	# Set the number of scrollback lines
	$$self{_GUI}{_VTE} -> set_scrollback_lines( $$self{_CFG}{'defaults'}{'terminal scrollback lines'} );
	
	############################################################################
	# Check if this terminal should start in a new window or in a new tab/window
	############################################################################
	
	# New TAB:
	if ( $$self{_TABBED} ) {
		# Append this GUI to a new TAB (with an associated label && event_box -> image(close) button)
		$$self{_GUI}{_TABLBL} = Gtk2::HBox -> new( 0, 0 );
			$$self{_GUI}{_TABLBL}{_EBLBL} = Gtk2::EventBox -> new;
				$$self{_GUI}{_TABLBL}{_LABEL} = Gtk2::Label -> new( $$self{_TITLE} );
				$$self{_GUI}{_TABLBL}{_EBLBL} -> add( $$self{_GUI}{_TABLBL}{_LABEL} );
				$$self{_GUI}{_TABLBL} -> pack_start( $$self{_GUI}{_TABLBL}{_EBLBL}, 1, 1, 0 );
			my $eblbl1 = Gtk2::EventBox -> new;
				$eblbl1 -> add( Gtk2::Image -> new_from_stock( 'gtk-close', 'menu' ) );
				$eblbl1 -> signal_connect( 'button_release_event' => sub { $_[1] -> button != 1 and return 0; $self -> stop( undef, 1 ); } );
			$$self{_GUI}{_TABLBL} -> pack_start( $eblbl1, 0, 1, 0 );
		
		$$self{_GUI}{_TABLBL}{_EBLBL} -> signal_connect( 'button_press_event' => sub {
			if ( $_[1] -> button eq 2 )		{ $self -> stop( undef, 1 ); return 1; }	# Mid-button
			elsif ( $_[1] -> button eq 3 )	{ $self -> _tabMenu( $_[1] ); return 1; }	# Right-button
			return 0;
		} );
		
		$$self{_GUI}{_TABLBL} -> show_all;
		
		_setupTabDND( $self );
		
		$tabs -> append_page( $$self{_GUI}{_VBOX}, $$self{_GUI}{_TABLBL} );
		$tabs -> show_all;
		$$self{_GUI}{_VBOX} -> show_all;
		$tabs -> set_tab_reorderable( $$self{_GUI}{_VBOX}, 1 );
		$tabs -> set_current_page( -1 );
		if ( ! $$self{_CFG}{'environments'}{ $$self{_UUID} }{'embed'} ) {
			$$self{FOCUS} -> child_focus( 'GTK_DIR_TAB_FORWARD' ) if $$self{_FOCUSED};
			defined $$self{FOCUS} && defined $$self{FOCUS} -> window and $$self{FOCUS} -> window -> show;
		}
		$$self{_NOTEBOOKWINDOW} -> maximize if $$self{_CFG}{'defaults'}{'start maximized'};
		
	}
	# New WINDOW:
	else
	{
		# Build a new window,
		$$self{_WINDOWTERMINAL} = Gtk2::Window -> new;
		$$self{_WINDOWTERMINAL} -> set_title( $$self{_TITLE} . " : $APPNAME (v$APPVERSION)" );
		$$self{_WINDOWTERMINAL} -> set_position( 'center' );
		$$self{_WINDOWTERMINAL} -> set_size_request( 200, 100 );
		my $hsize = $$self{_CFG}{environments}{ $$self{_UUID} }{'terminal options'}{'use personal settings'} ? $$self{_CFG}{environments}{ $$self{_UUID} }{'terminal options'}{'terminal window hsize'} : $$self{_CFG}{'defaults'}{'terminal windows hsize'};
		my $vsize = $$self{_CFG}{environments}{ $$self{_UUID} }{'terminal options'}{'use personal settings'} ? $$self{_CFG}{environments}{ $$self{_UUID} }{'terminal options'}{'terminal window vsize'} : $$self{_CFG}{'defaults'}{'terminal windows vsize'};
		$$self{_WINDOWTERMINAL} -> set_default_size( $hsize, $vsize );
		$$self{_WINDOWTERMINAL} -> maximize if $$self{_CFG}{'defaults'}{'start maximized'};
		$$self{_WINDOWTERMINAL} -> set_icon_name( 'gtk-disconnect' );
		$$self{_WINDOWTERMINAL} -> add( $$self{_GUI}{_VBOX} );
		$$self{_WINDOWTERMINAL} -> show_all;
		$$self{_WINDOWTERMINAL} -> present;
	}
	
	_updateCFG( $self );
	
	return 1;
}

sub _setupCallbacks {
	my $self	= shift;
	
	$$self{_GUI}{btnDelHist} -> signal_connect( 'clicked', sub {
		@{ $$self{_GUI}{treeKeys}{data} } = () if _wConfirm( $$self{GUI}{_VBOX}, "Are you sure you want to <b>DELETE ALL</b> commands history?" );
	} );
	
	$$self{_GUI}{treeKeys} -> signal_connect( 'row_activated' => sub {
		my $tree			= shift;
		my ( $selected )	= $tree -> get_selected_indices;
		return 1 unless ( defined $selected && $$self{CONNECTED} );
		my $cmd = $$tree{data}[$selected][0];
		
		$$self{_SAVE_KEYS} = 0;
		$self -> _execute( 'remote', $cmd, 0 );
		$$self{_SAVE_KEYS} = 1;
	} );
	
	$$self{_GUI}{cbShowHist} -> signal_connect( 'toggled', sub {
		if ( $$self{_GUI}{cbShowHist} -> get_active )	{ $$self{_GUI}{hbHist} -> show_all; }
		else											{ $$self{_GUI}{hbHist} -> hide; }
	} );
	
	$$self{_CFG}{defaults}{'tabs in main window'} and $$self{_GUI}{_VTE} -> signal_connect( 'motion_notify_event', sub {
		return 0 if $$self{_CFG}{'defaults'}{'prevent mouse over show tree'};
		my @geo = $$self{_GUI}{_VTE} -> window -> get_geometry;
		if ( $$self{_CFG}{defaults}{'tree on right side'} ) {
			return 0 if ( $$self{_SPLIT_VPANE} && ( ( $$self{_SPLIT_VPANE} -> get_child1 ) eq $$self{_GUI}{_VBOX} ) && ! $$self{_SPLIT_VERTICAL} );
			$PACMain::FUNCS{_MAIN}{_GUI}{showConnBtn} -> set_active( $_[1] -> x >= ( $geo[2] - 30 ) );
		} else {
			return 0 if ( $$self{_SPLIT_VPANE} && ( ( $$self{_SPLIT_VPANE} -> get_child2 ) eq $$self{_GUI}{_VBOX} ) && ! $$self{_SPLIT_VERTICAL} );
			$PACMain::FUNCS{_MAIN}{_GUI}{showConnBtn} -> set_active( $_[1] -> x <= 10 );
		}
		return 0;
	} );
	
	# Capture focus-out of VTE when it shouldn't get out!!!
	$$self{_GUI}{_VTE} -> signal_connect( 'focus_out_event' => sub {
		if ( ( $PACMain::FUNCS{_MAIN}{_HAS_FOCUS} // '' ) eq $$self{_GUI}{_VTE} ) {
			$$self{_GUI}{_VTE} -> grab_focus;
			$PACMain::FUNCS{_MAIN}{_HAS_FOCUS} = '';
			1;
		}
	} );
	# Capture keypresses on VTE
	$$self{_GUI}{_VTE} -> signal_connect( 'key_press_event' => sub {
		my ( $widget, $event ) = @_;
		
		my $keyval	= Gtk2::Gdk -> keyval_name( $event -> keyval );
		my $unicode	= Gtk2::Gdk -> keyval_to_unicode( $event -> keyval); # 0 if not a character
		my $state	= $event -> get_state;
		my $shift	= $state * ['shift-mask'];
		my $ctrl	= $state * ['control-mask'];
		my $alt		= $state * ['mod1-mask'];
		my $alt2	= $state * ['mod2-mask'];
		my $alt5	= $state * ['mod5-mask'];
		
		#print "TERMINAL KEYPRESS:*$state*$keyval*" . chr($keyval) . "*$unicode*\n";
		#print "*$shift*$ctrl*$alt*$alt2*$alt5*\n";
		
		return 1 if defined $$self{_KEYS_RECEIVE};
		
		# ENTER --> reconnect if disconnected
		if ( ( ( $keyval eq 'Return' ) || ( $keyval eq 'KP_Enter' ) ) && ( ! $$self{CONNECTED} && ! $$self{CONNECTING} ) ) {
			$self -> start;
			return 1;
		} elsif ( ( $keyval eq 'Return' ) || ( $keyval eq 'KP_Enter' ) ) {
			$$self{_INTRO_PRESS} = 1;
		}
		
		# F11 --> [un]fullscreen window
		if ( ( $keyval eq 'F11' ) && ( ! $$self{_CFG}{defaults}{'prevent F11'} ) ) {
			if ( $$self{_FULLSCREEN} ) {
				$$self{_FSTOTAB} and $self -> _winToTab;
				$$self{_GUI}{_VBOX} -> window -> unfullscreen;
				$$self{_FULLSCREEN} = 0;
			} else {
				$$self{_FSTOTAB} = $$self{_TABBED};
				$$self{_TABBED} and $self -> _tabToWin;
				$$self{_GUI}{_VBOX} -> window -> fullscreen;
				$$self{_FULLSCREEN} = 1;
			}
			return 1;
		}
		
		# Capture only keypresses with modifiers (ctrl, alt, etc.)
		
		############################################
		# Generic VTE keystrokes
		
		# <Shift><Ctrl><Alt>
		if ( ( $ctrl && $alt && $shift ) && ( ! $$self{_CFG}{environments}{ $$self{_UUID} }{'terminal options'}{'disable CTRL key bindings'} )  && ( ! $$self{_CFG}{environments}{ $$self{_UUID} }{'terminal options'}{'disable ALT key bindings'} ) && ( ! $$self{_CFG}{environments}{ $$self{_UUID} }{'terminal options'}{'disable SHIFT key bindings'} ) ) {
			# d --> FULL uplicate connection
			if ( lc $keyval eq 'd' ) {
				$self -> _wSelectKeypress;
				return 1;
			}
			# X --> Reset terminal
			elsif ( lc $keyval eq 'x' )	{
				$$self{_GUI}{_VTE} -> reset( 1, 1 );
				return 1;
			}   
		}
		# <Ctrl><Alt>
		elsif ( ( $ctrl && $alt ) && ( ! $$self{_CFG}{environments}{ $$self{_UUID} }{'terminal options'}{'disable CTRL key bindings'} )  && ( ! $$self{_CFG}{environments}{ $$self{_UUID} }{'terminal options'}{'disable ALT key bindings'} ) ) {
			# r --> remove from cluster
			if ( lc $keyval eq 'r' ) {
				$PACMain::FUNCS{_CLUSTER} -> delFromCluster( $$self{_UUID_TMP}, $$self{_CLUSTER} );
				return 1;
			}
			if ( lc $keyval eq 'h' ) {
				$$self{_GUI}{cbShowHist} -> set_active( ! $$self{_GUI}{cbShowHist} -> get_active );
				return 1;
			}
		}
		# <Ctrl><Shift>
		if ( ( $ctrl && $shift ) && ( ! $$self{_CFG}{environments}{ $$self{_UUID} }{'terminal options'}{'disable CTRL key bindings'} )  && ( ! $$self{_CFG}{environments}{ $$self{_UUID} }{'terminal options'}{'disable SHIFT key bindings'} ) ) {
			# C --> COPY
			if ( lc $keyval eq 'c' ) {
				$$self{_GUI}{_VTE} -> copy_clipboard;
				return 1;
			}   
			# V --> PASTE
			elsif ( lc $keyval eq 'v' )	{
				my $txt = $$self{_GUI}{_VTE} -> get_clipboard( Gtk2::Gdk -> SELECTION_CLIPBOARD ) -> wait_for_text;
				$self -> _pasteToVte( $txt, $$self{_CFG}{'environments'}{ $$self{_UUID} }{'send slow'} );
				return 1;
			}
			# B --> PASTE AND DELETE
			elsif ( lc $keyval eq 'b' )
			{
				my $text = $$self{_GUI}{_VTE} -> get_clipboard( Gtk2::Gdk -> SELECTION_CLIPBOARD ) -> wait_for_text;
				my $delete = _wEnterValue(
					$$self{_GUI},
					"Enter the String/RegExp of text to be *deleted* when pasting.\nUseful for, for example, deleting 'carriage return' from the text before pasting it.",
					'Use string or Perl RegExps (ex: \n means "carriage return")',
					'\n|\f|\r'
				) or return 1;
				$text =~ s/$delete//g;
				$self -> _pasteToVte( $text, $$self{_CFG}{'environments'}{ $$self{_UUID} }{'send slow'} || 1 );
				return 1;
			}
			# X --> Reset terminal
			elsif ( lc $keyval eq 'x' ) {
				$$self{_GUI}{_VTE} -> reset( 1, 0 );
				return 1;
			}   
			# g --> Guess hostname and set as title
			elsif ( lc $keyval eq 'g' )	{
				( $$self{CONNECTED} && ! $$self{CONNECTING} ) and $self -> _execute( 'remote', '<CTRL_TITLE:hostname>', undef, undef, undef );
				return 1;
			}   
			# w --> Close terminal
			elsif ( lc $keyval eq 'w' )	{
				$self -> stop( undef, 1 );
				return 1;
			}   
			# q --> Close PAC
			elsif ( lc $keyval eq 'q' )	{
				$PACMain::FUNCS{_MAIN} -> _quitProgram;
				return 1;
			}   
			# f --> FIND in treeView
			elsif ( lc $keyval eq 'f' )
			{
				$PACMain::FUNCS{_MAIN} -> _showConnectionsList;
				$PACMain::FUNCS{_MAIN}{_GUI}{_vboxSearch} -> show;
				$PACMain::FUNCS{_MAIN}{_GUI}{_entrySearch} -> grab_focus;
				return 1;
			}
			# 6 --> Send a Cisco interrupt keypress
			elsif ( $unicode eq 38 )
			{
				$$self{_GUI}{_VTE} -> feed_child_binary( "\c^x" );
				#$$self{_GUI}{_VTE} -> feed_child_binary( "\c^" );
				#$$self{_GUI}{_VTE} -> feed_child_binary( "\c]" );
				$$self{_GUI}{_VTE} -> feed_child_binary( chr( 30 ) . 'x' );
				return 1;
			}
			# F4 --> CLOSE *ALL* opened tabs
			elsif ( ( $self -> {_TABBED} ) and ( $keyval eq 'F4' ) )
			{
				$self -> _closeAllTerminals();
				return 1;
			}
			# n --> Close disconnected sessions
			elsif ( lc $keyval eq 'n' ) {
				$self -> _closeDisconnectedTerminals();
				return 1;
			}
			# d --> duplicate connection
			elsif ( lc $keyval eq 'd' ) {
				$PACMain::FUNCS{_MAIN} -> _launchTerminals( [ [ $$self{_UUID} ] ] );
				return 1;
			}
			# f --> Find in history
			elsif ( lc $keyval eq 'f' ) {
				$self -> _wHistory if $$self{_CFG}{'defaults'}{'record command history'};
				return 1;
			}
			# r --> Disconnect and Restart session
			elsif ( lc $keyval eq 'r' ) {
				$self -> _disconnectAndRestartTerminal();
				return 1;
			}
		}
		# <Ctrl>
		elsif ( $ctrl && ( ! $$self{_CFG}{environments}{ $$self{_UUID} }{'terminal options'}{'disable CTRL key bindings'} ) ) {
			# F4 --> CLOSE current tab
			if ( ( $self -> {_TABBED} ) and ( $keyval eq 'F4' ) ) {
				$self -> stop( undef, 1 );
				return 1;
			}
			
			# F3 --> FIND in text buffer
			if ( $keyval eq 'F3' ) {
				_wFindInTerminal( $self );
				return 1;
			}
			
			# <ins> --> COPY
			if ( $keyval eq 'Insert' ) {
				$$self{_GUI}{_VTE} -> copy_clipboard;
				return 1;
			}
		}
		# <Shift>
		elsif ( $shift && ( ! $$self{_CFG}{environments}{ $$self{_UUID} }{'terminal options'}{'disable SHIFT key bindings'} ) )	{
			# <ins> --> PASTE
			if ( $keyval eq 'Insert' ) {
				$$self{_GUI}{_VTE} -> paste_clipboard;
				return 1;
			}   
		}
		# <Alt>
		elsif ( $alt && ( ! $$self{_CFG}{environments}{ $$self{_UUID} }{'terminal options'}{'disable ALT key bindings'} ) )	{
			# c | n --> Show main connections window
			if ( ( lc $keyval eq 'c' ) || ( lc $keyval eq 'n' ) ) {
				if ( ! $$self{_TABBED} || ! $$self{_CFG}{defaults}{'tabs in main window'} )	{
					$PACMain::FUNCS{_MAIN} -> _showConnectionsList;
				} else {
					$PACMain::FUNCS{_MAIN} -> _toggleConnectionsList;
				}
				return 1;
			}
			# e --> Show main edit connection window
			if ( lc $keyval eq 'e' ) {
				$PACMain::FUNCS{_EDIT} -> show( $$self{_UUID} ) unless $$self{_UUID} eq '__PAC_SHELL__';
				return 1;
			}
			# h --> Show command history window
			if ( lc $keyval eq 'h' ) {
				$self -> _wHistory if $$self{_CFG}{'defaults'}{'record command history'};
				return 1;
			}
		}
		return 0;
	} );
	
	# Right mouse mouse on VTE
	$$self{_GUI}{_VTE} -> signal_connect( 'button_press_event' => sub {
		my ( $widget, $event ) = @_;
		if ( $event -> button eq 2 ) {
			return 0 unless $$self{_CFG}{'environments'}{ $$self{_UUID} }{'send slow'};
			my $txt = $$self{_GUI}{_VTE} -> get_clipboard( Gtk2::Gdk -> SELECTION_PRIMARY ) -> wait_for_text;
			$self -> _pasteToVte( $txt, $$self{_CFG}{'environments'}{ $$self{_UUID} }{'send slow'} );
			$$self{FOCUS} -> child_focus( 'GTK_DIR_TAB_FORWARD' );
			return 1;
		} elsif ( $event -> button eq 3 ) {
			$self -> _vteMenu( $event );
			return 1;
		}
		
		return 0;
	} );
	
	# Capture mouse selection on VTE
	$$self{_GUI}{_VTE} -> signal_connect( 'selection_changed' => sub { $$self{_GUI}{_VTE} -> copy_clipboard if $$self{_CFG}{defaults}{'selection to clipboard'}; return 0; } );
	$$self{_GUI}{_VTE} -> signal_connect( 'commit' => sub { $$self{_CFG}{'defaults'}{'record command history'} and $self -> _saveHistory( $_[1] ); $self -> _clusterCommit( @_ ); } );
	$$self{_GUI}{_VTE} -> signal_connect( 'cursor_moved' => sub { $$self{_NEW_DATA} = 1; $self -> _setTabColour; } );
	
	# Capture Drag and Drop events
	$$self{_GUI}{_VTE} -> drag_dest_set( 'GTK_DEST_DEFAULT_ALL', [ 'move' ], { 'target' => 'PAC Connect', 'flags' => [], 'info' => 0 } );
	$$self{_GUI}{_VTE} -> signal_connect( 'drag_drop' => sub {
		if ( ! $$self{CONNECTED} ) {
			_wMessage( $$self{GUI}{_VBOX}, "This terminal is <b>DISCONNECTED</b>.\nPlease, start the connection before trying to <b>chain</b>.", 1 );
			return 0;
		} elsif ( $$self{CONNECTING} ) {
			_wMessage( $$self{GUI}{_VBOX}, "Please, <b>WAIT for current chain to finish</b> before starting a new one.", 1 );
			return 0;
		} elsif ( $$self{CONNECTED} && ( scalar @{ $PACMain::{FUNCS}{_MAIN}{'DND'}{'selection'} } == 1 ) ) {
			my $sel = shift @{ $PACMain::{FUNCS}{_MAIN}{'DND'}{'selection'} };
			my $name = $$self{_CFG}{environments}{$sel}{name};
			my $title = $$self{_CFG}{environments}{$sel}{title};
			$self -> _wSelectChain( $sel ) or _wMessage( undef, "No '<b>Expect/Send</b>' data available in:\n<b>$name ($title)</b>\nSo, there are <b>no commands to chain</b>" );
			$$self{FOCUS} -> child_focus( 'GTK_DIR_TAB_FORWARD' ) if $$self{_FOCUSED};
			return 1;
		} else {
			$$self{FOCUS} -> child_focus( 'GTK_DIR_TAB_FORWARD' ) if $$self{_FOCUSED};
			return 0;
		}
	} );
	$$self{_GUI}{_VTE} -> signal_connect( 'drag_motion' => sub { $_[0] -> get_parent_window -> raise; return 1; } );
	
	# Depending on terminal creation (window/tab), process connection closing differently
	if ( ! $$self{_TABBED} ) {
		# Capture window close
		$$self{_WINDOWTERMINAL} -> signal_connect( 'delete_event' => sub {
			$self -> stop( undef, 1 ) unless $$self{_GUILOCKED};
			return 1;
		} );
	}
	
	# If embedded, add a callback for the 'get focus' button
	$$self{EMBED} and $$self{_GUI}{_BTNFOCUS} -> signal_connect ( 'clicked' => sub { $$self{FOCUS} -> child_focus( 'GTK_DIR_TAB_FORWARD' ); } );
	
	# Connect to the "map" signal of macrosbox widget to avoid showing it if so is configured
	defined $$self{_GUI}{_MACROSBOX} and $$self{_GUI}{_MACROSBOX} -> signal_connect( 'map' => sub { $self -> _updateCFG unless $$self{_NO_UPDATE_CFG}; } );
	$$self{_GUI}{hbHist} -> signal_connect( 'map' => sub { $self -> _updateCFG unless $$self{_NO_UPDATE_CFG}; } );
	
	# Append VTE's connection finalization with CLOSE event
	$$self{_GUI}{_VTE} -> signal_connect ( 'child_exited' => sub {
		defined $$self{_GUI}{statusIcon}	and $$self{_GUI}{statusIcon} -> set_from_stock( 'pac-terminal-ko-small', 'button' );
		defined $$self{_GUI}{statusIcon}	and $$self{_GUI}{statusIcon} -> set_tooltip_text( 'DISCONNECTED' );
		defined $$self{_GUI}{pb}			and $$self{_GUI}{pb} -> destroy;
		
		$PACMain::RUNNING{ $$self{'_UUID_TMP'} }{'stop_time'} = time();
		$PACMain::FUNCS{_STATS} -> stop( $$self{_UUID} );
		
		# Update 'CONNECTED' status
		$$self{_LAST_STATUS}	= 'DISCONNECTED';
		$$self{CONNECTED}		= 0;
		$$self{CONNECTING}		= 0;
		
		my $string = $$self{_CFG}{'environments'}{ $$self{_UUID} }{'method'} eq 'generic' ? "EXECUTION FINISHED (PRESS <ENTER> TO EXECUTE AGAIN)" : "DISCONNECTED (PRESS <ENTER> TO RECONNECT)";
		$$self{_GUI}{_VTE} -> feed( "\e[1;31m\r\n <-= $string (" . ( localtime( time ) ) . ")\e[0m\r\n\n" ) if defined $$self{_GUI}{_VTE};
		
		defined $$self{_SOCKET_CLIENT}		and $$self{_SOCKET_CLIENT}		-> close;
		defined $$self{_SOCKET_CLIENT_EXEC}	and $$self{_SOCKET_CLIENT_EXEC} -> close;
		defined $$self{_SEND_STRING}		and eval { Glib::Source -> remove( $$self{_SEND_STRING} );  };
		defined $$self{_EMBED_KIDNAP}		and eval { Glib::Source -> remove( $$self{_EMBED_KIDNAP} ); };
		
		# _SOCKET_CLIENT is close so no more watch to expect
		undef $$self{_SOCKET_CLIENT_WATCH};
		
		$self -> _setTabColour;
		$self -> _updateStatus;
		
		# Update Cluster GUI
		$PACMain::FUNCS{_CLUSTER} -> _updateGUI;
		
		$self -> _unsplit if ( $$self{_SPLIT} && $$self{_CFG}{'defaults'}{'unsplit disconnected terminals'} );
		
		$$self{_PID} = 0;
		
		if ( $$self{_RESTART} ) {
			$self -> start;
		} else {
			# Check for post-connection commands execution
			$self -> _wPrePostExec( 'local after' );
			
			# And close if so is configured
			$self -> stop( undef, 1 ) if $$self{_CFG}{'defaults'}{'close terminal on disconnect'} && ! $$self{_BADEXIT};
		}
		
		$self -> _updateCFG;
		
		return 1;
	} );
	
	return 1;
}

sub _watchConnectionData {
	my ( $fd, $cond, $self ) = @_;
	
	return 0 if ( ( $cond >= 'hup' ) || ( $cond >= 'err' ) );
	
	# This should be as fast as possible, since we are called from a 'data-in' callback from the client socket
	$self -> _receiveData;
	
	while ( my $data = shift( @{ $self -> {_SOCKET_BUFFER} } ) ) {
		$data = decode( 'UTF-16', $data );
		
		if ( $data eq 'CONNECTED' ) {
			$$self{_GUI}{statusIcon} -> set_from_stock( 'pac-terminal-ok-small', 'button' );
			$$self{_GUI}{statusIcon} -> set_tooltip_text( 'CONNECTED' );
			$$self{_GUI}{statusExpect} -> clear;
			$$self{CONNECTED}		= 1;
			$$self{CONNECTING}		= 0;
			$$self{_BADEXIT}		= 0;
			$$self{_GUI}{pb}		-> destroy if defined $$self{_GUI}{pb};
			$$self{_GUI}{pb}		= undef;
			$$self{_SCRIPT_STATUS}	= 'STOP';
			$PACMain::FUNCS{_CLUSTER} -> _updateGUI;
			$self -> _updateCFG;
			$data = $self -> _checkSendKeystrokes( $data );
			
			defined $$self{_EMBED_KIDNAP} and eval { Glib::Source -> remove( $$self{_EMBED_KIDNAP} ); };
			$$self{_EMBED_KIDNAP} = Glib::Timeout -> add( 500, sub {
				my $title = 'FreeRDP: ' . $$self{_CFG}{environments}{$$self{_UUID}}{ip} . ( $$self{_CFG}{environments}{$$self{_UUID}}{port} == 3389 ? '' : ":$$self{_CFG}{environments}{$$self{_UUID}}{port}" );
				$title = $$self{_CFG}{environments}{$$self{_UUID}}{method} eq 'RDP (xfreerdp)' ?
					"FreeRDP: $$self{_CFG}{environments}{$$self{_UUID}}{ip}" . ( $$self{_CFG}{environments}{$$self{_UUID}}{port} == 3389 ? '' : ":$$self{_CFG}{environments}{$$self{_UUID}}{port}" ) :
					"TightVNC: $$self{_CFG}{environments}{$$self{_UUID}}{user}";
				my $list = _getXWindowsList;
				return 1 unless grep( { $_ =~ /$title/ and $title = $_; } keys %{ $$list{'by_name'} } );
				$$self{_GUI}{_SOCKET} -> add_id( $$list{'by_name'}{$title}{'xid'} );
				return 0;
			} ) if $$self{EMBED} && $$self{_CFG}{environments}{$$self{_UUID}}{method} eq 'RDP (xfreerdp)' || $$self{_CFG}{environments}{$$self{_UUID}}{method} eq 'VNC';
		}
		elsif ( $data =~ /^EXPLORER:(.+)/go ) {
			system( "xdg-open '$1' &" );
		}
		elsif ( $data =~ /^PIPE_WAIT\[(.+?)\]\[(.+)\]/go ) {
			my $time	= $1;
			my $prompt	= $2;
			
			if ( ! defined $$self{_GUI}{pb} ) {
				$$self{_GUI}{pb} = Gtk2::ProgressBar -> new;
				$$self{_GUI}{bottombox} -> pack_start( $$self{_GUI}{pb}, 0, 1, 0 );
				$$self{_GUI}{pb} -> show;
			}
			$$self{CONNECTING} = 1;
			$$self{_PULSE} = 1;
			
			# Prepare a timer to "pulse" the progress bar while executing script
			$$self{_PULSE_TIMER} = Glib::Timeout -> add ( 100, sub { defined $$self{_GUI}{pb} and $$self{_GUI}{pb} -> pulse; return $$self{_PULSE}; } );
		}
		elsif ( $data =~ /^SCRIPT_(START|STOP)\[NAME:(.+)\]/go ) {
			my ( $status, $name ) = ( $1, $2 );
			$$self{_SCRIPT_STATUS}	= $status;
			$$self{_SCRIPT_NAME}	= $name;
			
			if ( $$self{CONNECTING} = $status eq 'START' ) {
				if ( ! defined $$self{_GUI}{pb} ) {
					$$self{_GUI}{pb} = Gtk2::ProgressBar -> new;
					$$self{_GUI}{bottombox} -> pack_start( $$self{_GUI}{pb}, 0, 1, 0 );
					$$self{_GUI}{pb} -> show;
				}
				$$self{_PULSE} = 1;
				
				# Prepare a timer to "pulse" the progress bar while executing script
				$$self{_PULSE_TIMER} = Glib::Timeout -> add ( 100, sub { defined $$self{_GUI}{pb} and $$self{_GUI}{pb} -> pulse; return $$self{_PULSE}; } );
			} else {
				$$self{_PULSE} = 0;
				$$self{_GUI}{pb}	-> destroy if defined $$self{_GUI}{pb};
				$$self{_GUI}{pb}	= undef;
				$PACMain::FUNCS{_CLUSTER} -> _updateGUI;
			}
		}
		elsif ( $data =~ /^SCRIPT_SUB_(.+)\[NAME:(.+)\]\[PARAMS:(.*)\]/go ) {
			my ( $func, $name, $params ) = ( $1, $2, $3 );
			$data = "PAC Script '$name' --> $func( $params )";
		}
		elsif ( $data =~ /^TITLE:(.+)/go ) {
			$$self{_TITLE} = $1;
			$self -> _updateCFG;
		}
		elsif ( $data =~ /^PAC_CONN_MSG:(.+)/go ) {
			_wMessage( undef, $1, 1 );
			next;
		}
		elsif ( $data eq 'RESTART' ) {
			$$self{_RESTART} = 1;
		}
		elsif ( $data =~ /^CHAIN:(.+):(.+):(.+):(.+)/go ) {
			my ( $chain_name, $chain_uuid, $exp_partial, $exp_total ) = ( $1, $2, $3, $4 );
			$$self{_GUI}{statusExpect} -> set_from_stock( 'gtk-media-play', 'button' );
			$$self{_GUI}{statusExpect} -> set_tooltip_text( "Expect / Execute: $1 / $2" );
			$$self{_PULSE} = 0;
			if ( ! defined $$self{_GUI}{pb} ) {
				$$self{_GUI}{pb} = Gtk2::ProgressBar -> new;
				$$self{_GUI}{bottombox} -> pack_start( $$self{_GUI}{pb}, 0, 1, 0 );
				$$self{_GUI}{pb} -> show;
			}
			$$self{_GUI}{pb} -> set_fraction( $exp_partial / $exp_total );
			$$self{CONNECTING} = 1;
		}
		elsif ( $data eq 'EXEC:RECEIVE_OUT' ) {
			my $rin = '';
			vec( $rin, fileno( $$self{_SOCKET_CLIENT_EXEC} ), 1 ) = 1;
			select( $rin, undef, undef, 2 ) or return 1;
			$$self{_EXEC}{RECEIVED} = undef;
			eval { $$self{_EXEC}{RECEIVED} = ${ fd_retrieve( $$self{_SOCKET_CLIENT_EXEC} ) }; };
			if ( $@ ) { _wMessage( undef, "ERROR: Could not retrieve output from command execution:\n$@" ); return 1; }
			defined $$self{_EXEC}{RECEIVED} and $$self{_EXEC_PROCESS} = Glib::Timeout -> add( 100, sub { $self -> _pipeExecOutput; return 0; } );
		}
		elsif ( $data =~ /^SENDSLOW:(.+)/go ) {
			my $txt = $1;
			$$self{_PULSE} = 1;
			if ( ! defined $$self{_GUI}{pb} ) {
				$$self{_GUI}{pb} = Gtk2::ProgressBar -> new;
				$$self{_GUI}{bottombox} -> pack_start( $$self{_GUI}{pb}, 0, 1, 0 );
				$$self{_GUI}{pb} -> show;
			}
			# Prepare a timer to "pulse" the progress bar while connecting
			$$self{_PULSE_TIMER} = Glib::Timeout -> add ( 100, sub {
				if ( $$self{_PULSE} && defined $$self{_GUI}{pb} && $$self{_GUI}{pb} -> get_property( 'visible' ) ) {
					$$self{_GUI}{pb} -> pulse;
					return 1;
				} else {
					delete $$self{_PULSE_TIMER};
					return 0;
				}
			} );
		}
		elsif ( ( $data eq 'DISCONNECTED' ) || ( $data =~ /^CLOSE:.+/go ) || ( $data =~ /^TIMEOUT:.+/go ) || ( $data =~ /^connect\(\) failed with error '.+'$/go ) ) {
			Glib::Source -> remove( $$self{_EMBED_KIDNAP} ) if defined $$self{_EMBED_KIDNAP};
			$$self{_GUI}{statusExpect} -> clear;
			$$self{_BADEXIT} = $$self{CONNECTING};
			$$self{_PID} and kill( 15, $$self{_PID} );
		}
		elsif ( $data =~ /^EXPECT:WAITING:(.+)/go ) {
			$$self{_GUI}{statusExpect} -> set_from_stock( 'gtk-media-play', 'button' );
			$$self{_GUI}{statusExpect} -> set_tooltip_text( "Expecting '$1'" );
			$$self{_PULSE} = 0;
			$$self{_GUI}{pb} -> set_fraction( ++$$self{_EXPECTED} / $$self{_TOTAL} );
			$$self{CONNECTING} = 1;
		}
		elsif ( $data =~ /^SPAWNED:'(.+)'\s*\(PID:(\d+)\)$/go ) {
			$$self{_CMD} = $1;
			$$self{_PID} = $2;
			$$self{CONNECTING} = 1;
			$$self{_RESTART} = 0;
		}
		
		$$self{_LAST_STATUS} = $data;
	}
	
	$self -> _setTabColour;
	$self -> _updateStatus;
	
	return 1;
}

sub _receiveData {
	my $self	= shift;
	my $socket	= shift // $$self{_SOCKET_CLIENT};
	
	my $buffer = '';
	$$self{_SOCKET_BUFFER} = ();
	
	my $data = '';
	my $bytes;
	
	# At least one read should be done
	do {
		$bytes = sysread( $socket, $data, 1024 ) // 0;
		last unless defined $bytes;
		
		$buffer .= $data;
		chomp $buffer;
		
		$buffer =~ s/\R/ /go;
		
		my $empty_buffer = 0;
		while ( $buffer =~ s/PAC_MSG_START\[(.+?)\]PAC_MSG_END/$1/o ) {
			my $buffer = $1;
			next unless $buffer;
			push( @{ $$self{_SOCKET_BUFFER} }, $buffer );
			$empty_buffer = 1;
		}
		$empty_buffer and $buffer = '';
		
	} until $bytes < 1024;
	
	return 1;
}

sub _authClient {
	my $self	= shift;
	my $socket	= shift;
	
	# Make sure that this client is a PAC client:
	$self -> _receiveData( $socket );
	my $data = shift( @{ $self -> {_SOCKET_BUFFER} } );
	$data = decode( 'UTF-16', $data );
	
	return 0 unless $data eq "!!_PAC_AUTH_[$$self{_UUID_TMP}]!!";
	
	$socket -> send( "!!_PAC_AUTH_[$$self{_UUID_TMP}]!!" );
	
	return 1;
}

sub _vteMenu {
	my $self	= shift;
	my $event	= shift;
	
	my @vte_menu_items;
	
	# If PAC Script running, show a STOP script menuitem
	if ( $$self{_SCRIPT_STATUS} ne 'STOP' ) {
		push( @vte_menu_items,
		{
			label		=> "Stop script '$$self{_SCRIPT_NAME}'",
			stockicon	=> 'gtk-media-stop',
			sensitive	=> 1,
			code		=> sub { kill( 15, $$self{_PID} ); }
		} );
		
		_wPopUpMenu( \@vte_menu_items, $event );
		return 1,
	}
	
	# Add a submenu with available connections (including: LOCAL SHELL) and chaining connections
	push( @vte_menu_items, {
		label => 'Connection',
		stockicon => 'pac-group',
		submenu =>
			[
				{
					label		=> 'Favourites',
					stockicon	=> 'pac-favourite-on',
					submenu		=> _menuFavouriteConnections( $self )
				},
				{
					label		=> 'All',
					stockicon	=> 'pac-treelist',
					submenu		=>
						[
							{ label => 'Local Shell', stockicon => 'gtk-home', code => sub { $PACMain::FUNCS{_MAIN}{_GUI}{shellBtn} -> clicked; } },
							{ separator => 1 },
							@{ _menuAvailableConnections( $PACMain::FUNCS{_MAIN}{_GUI}{treeConnections}{data}, $self ) }
						]
				},
			]
	} ) unless $$self{_CFG}{'defaults'}{'hide connections submenu'};
	
	# Show a popup with the opened tabs (if tabbed!!)
	if ( $$self{_TABBED} ) {
		my @submenu_split_v;
		my @submenu_split_h;
		foreach my $uuid_tmp ( keys %PACMain::RUNNING ) {
			next unless defined $PACMain::RUNNING{$uuid_tmp}{terminal}{_SPLIT};
			my $i = $$self{_NOTEBOOK} -> page_num( $PACMain::RUNNING{$uuid_tmp}{terminal}{_SPLIT} ? $PACMain::RUNNING{$uuid_tmp}{terminal}{_SPLIT_VPANE} : $PACMain::RUNNING{$uuid_tmp}{terminal}{_GUI}{_VBOX} );
			next if ( $uuid_tmp eq $$self{_UUID_TMP} || $PACMain::RUNNING{$uuid_tmp}{terminal}{_TITLE} eq 'Info ' || $i < 0 );
			next if ( $$self{_SPLIT} || $PACMain::RUNNING{$uuid_tmp}{terminal}{_SPLIT} ) || ( ! $PACMain::RUNNING{$uuid_tmp}{terminal}{_TABBED} );
			push( @submenu_split_v,
			{
				label	=> "$i: $PACMain::RUNNING{$uuid_tmp}{terminal}{_TITLE}",
				tooltip	=> "Arrange both connections ($$self{_TITLE}) and ($PACMain::RUNNING{$uuid_tmp}{terminal}{_TITLE}) into the same vertically split window.",
				code	=> sub { $self -> _split( $uuid_tmp ); }
			} );
			push( @submenu_split_h,
			{
				label	=> "$i: $PACMain::RUNNING{$uuid_tmp}{terminal}{_TITLE}",
				tooltip	=> "Arrange both connections ($$self{_TITLE}) and ($PACMain::RUNNING{$uuid_tmp}{terminal}{_TITLE}) into the same horizontally split window .",
				code	=> sub { $self -> _split( $uuid_tmp, 1 ); }
			} );
		}
		@submenu_split_v = sort { $$a{label} cmp $$b{label} } @submenu_split_v;
		@submenu_split_h = sort { $$a{label} cmp $$b{label} } @submenu_split_h;
		
		push( @vte_menu_items,
		{
			sensitive	=> 1,
			label		=> 'Detach tab to a new Window',
			stockicon	=> 'gtk-fullscreen',
			tooltip		=> 'Separate this connection window from the tabbed view, and put it in a separate window',
			code		=> sub { $self -> _tabToWin; }
		} );
		
		if ( $$self{_SPLIT} ) {
			push( @vte_menu_items,
			{
				label		=> 'Unsplit',
				stockicon	=> 'gtk-zoom-fit',
				tooltip		=> "Remove the split view and put each connection into its own tab",
				code		=> sub { $self -> _unsplit; }
			} );
		} else {
			push( @vte_menu_items,
			{
				label		=> 'Split',
				stockicon	=> 'gtk-zoom-fit',
				sensitive	=> scalar( @submenu_split_v ) && scalar( @submenu_split_h ),
				submenu		=> 
				[
					{
						label		=> 'Vertically',
						stockicon	=> 'gtk-zoom-fit',
						submenu		=> \@submenu_split_v,
						sensitive	=> scalar( @submenu_split_v )
					},
					{
						label		=> 'Horizontally',
						stockicon	=> 'gtk-zoom-fit',
						submenu		=> \@submenu_split_h,
						sensitive	=> scalar( @submenu_split_h )
					}
				]
			} );
		}
		push( @vte_menu_items, { separator => 1 } );
	} else {
		push( @vte_menu_items,
		{
			label		=> 'Attach Window to main tab bar',
			stockicon	=> 'gtk-leave-fullscreen',
			tooltip		=> 'Put this connection window into main tabbed window',
			code		=> sub { _winToTab( $self ); }
		} );
		push( @vte_menu_items, { separator => 1 } );
	}
	
	# Prepare the "Add to Cluster" submenu...
	my @submenu_cluster;
	my %clusters;
	push( @submenu_cluster,
	{
		label		=> 'New Cluster...',
		stockicon	=> 'gtk-new',
		tooltip		=> 'Create a new cluster and put this connection in it',
		code		=> sub {
			my $cluster = _wEnterValue( $self, 'Enter a name for the <b>New Cluster</b>' );
			( ( ! defined $cluster ) || ( $cluster =~ /^\s*$/go ) ) and return 1;
			$PACMain::FUNCS{_CLUSTER} -> addToCluster( $$self{_UUID_TMP}, $cluster );
		}
	} );
	foreach my $uuid_tmp ( keys %PACMain::RUNNING ) {
		next if ( $PACMain::RUNNING{$uuid_tmp}{terminal}{_CLUSTER} eq '' );
		
		$clusters{$PACMain::RUNNING{$uuid_tmp}{terminal}{_CLUSTER}}{total}++;
		$clusters{$PACMain::RUNNING{$uuid_tmp}{terminal}{_CLUSTER}}{connections} .= "$PACMain::RUNNING{$uuid_tmp}{terminal}{_NAME}\n";
	}
	foreach my $cluster ( sort { $a cmp $b } keys %clusters ) {
		my $tmp = $cluster;
		push( @submenu_cluster,
		{
			label		=> "$cluster ( $clusters{$cluster}{total} terminals connected )",
			tooltip		=> "Add to selected cluster, with connections:\n" . $clusters{$cluster}{connections},
			sensitive	=> $cluster ne $$self{_CLUSTER},
			code		=> sub { $PACMain::FUNCS{_CLUSTER} -> addToCluster( $$self{_UUID_TMP}, $tmp ); }
		} );
	}
	# Add to cluster
	push( @vte_menu_items,
	{
		label		=> ( $$self{_CLUSTER} eq '' ? 'Add' : 'Change' ) . ' to Cluster',
		stockicon	=> 'gtk-add',
		sensitive	=> 1,
		submenu		=> \@submenu_cluster
	} );
	# Remove from cluster
	push( @vte_menu_items,
	{
		label		=> 'Remove from Cluster',
		shortcut	=> '<control><alt>r',
		stockicon	=> 'gtk-delete',
		tooltip		=> $$self{_CLUSTER} ne '' ? "Remove this connection from cluster '$$self{_CLUSTER}'" : '',
		sensitive	=> $$self{_CLUSTER} ne '',
		code		=> sub { $PACMain::FUNCS{_CLUSTER} -> delFromCluster( $$self{_UUID_TMP}, $$self{_CLUSTER} ); }
	} );
	# Show the PCC
	push( @vte_menu_items,
	{
		label		=> 'Power Cluster Controller',
		stockicon	=> 'gtk-justify-fill',
		sensitive	=> 1,
		tooltip		=> 'Bring up the Power Cluster Controller GUI',
		code		=> sub { $PACMain::FUNCS{_PCC} -> show; }
	} );
	push( @vte_menu_items, { separator => 1 } );
	
	# Show the list of available PAC Scripts to execute
	my @scripts_sub_menu;
	my $sl = $PACMain::FUNCS{_SCRIPTS} -> scriptsList;
	foreach my $name ( sort { $a cmp $b } keys %{ $sl } ) {
		my $file = $$sl{$name};
		push( @scripts_sub_menu,
		{
			label		=> $name,
			stockicon	=> 'gtk-execute',
			sensitive	=> $$self{CONNECTED},
			tooltip		=> "Exec the CONNECTIONS part of '$name' in this connection",
			code		=> sub { $PACMain::FUNCS{_SCRIPTS} -> _execScript( $name, $$self{_UUID_TMP} ); }
		} );
	}
	push( @vte_menu_items,
	{
		label		=> 'Execute Script',
		stockicon	=> 'pac-script',
		tooltip		=> 'Execute selected PAC Script in this connection',
		submenu		=> \@scripts_sub_menu,
	} );
	
	# Show the list of REMOTE commands to execute
	my @cmd_remote_sub_menu;
	foreach my $hash ( @{ $self -> {_CFG}{'environments'}{ $$self{_UUID} }{'macros'} } ) {
		my $cmd		= ref( $hash ) ? $$hash{txt} : $hash;
		my $desc	= ref( $hash ) ? $$hash{description} : $hash;
		my $confirm	= ref( $hash ) ? $$hash{confirm} : 0;
		next unless $cmd ne '';
		push( @cmd_remote_sub_menu,
		{
			label		=> ( $confirm ? 'CONFIRM: ' : '' ) . ( $desc ? $desc : $cmd ),
			tooltip		=> $desc ? $cmd : $desc,
			sensitive	=> $$self{CONNECTED},
			stockicon	=> $confirm ? 'gtk-dialog-question' : '',
			code		=> sub { $self -> _execute( 'remote', $cmd, $confirm ) }
		} );
	}
	foreach my $hash ( @{ $$self{_CFG}{'defaults'}{'remote commands'} } ) {
		my $cmd		= ref( $hash ) ? $$hash{txt} : $hash;
		my $desc	= ref( $hash ) ? $$hash{description} : $hash;
		my $confirm	= ref( $hash ) ? $$hash{confirm} : 0;
		next unless $cmd ne '';
		push( @cmd_remote_sub_menu,
		{
			label		=> ( $confirm ? 'CONFIRM: ' : '' ) . ( $desc ? $desc : $cmd ),
			tooltip		=> $desc ? $cmd : $desc,
			sensitive	=> $$self{CONNECTED},
			stockicon	=> $confirm ? 'gtk-dialog-question' : '',
			code		=> sub { $self -> _execute( 'remote', $cmd, $confirm ) }
		} );
	}
	push( @vte_menu_items,
	{
		label		=> 'Remote commands',
		stockicon	=> 'gtk-execute',
		tooltip		=> 'Send to this connection the selected command (keypresses)',
		submenu		=> \@cmd_remote_sub_menu,
	} );
	
	# Show the list of LOCAL commands to execute
	my @cmd_local_sub_menu;
	foreach my $hash ( @{ $self -> {_CFG}{'environments'}{ $$self{_UUID} }{'local connected'} } ) {
		my $cmd		= ref( $hash ) ? $$hash{txt} : $hash;
		my $desc	= ref( $hash ) ? $$hash{description} : $hash;
		my $confirm	= ref( $hash ) ? $$hash{confirm} : 0;
		next unless $cmd ne '';
		push( @cmd_local_sub_menu,
		{
			label		=> ( $confirm ? 'CONFIRM: ' : '' ) . ( $desc ? $desc : $cmd ),
			tooltip		=> $desc ? $cmd : $desc,
			stockicon	=> $confirm ? 'gtk-dialog-question' : '',
			code		=> sub { $self -> _execute( 'local', $cmd, $confirm ) }
		} );
	}
	foreach my $hash ( @{ $$self{_CFG}{'defaults'}{'local commands'} } ) {
		my $cmd		= ref( $hash ) ? $$hash{txt} : $hash;
		my $desc	= ref( $hash ) ? $$hash{description} : $hash;
		my $confirm	= ref( $hash ) ? $$hash{confirm} : 0;
		next unless $cmd ne '';
		push( @cmd_local_sub_menu,
		{
			label		=> ( $confirm ? 'CONFIRM: ' : '' ) . ( $desc ? $desc : $cmd ),
			tooltip		=> $desc ? $cmd : $desc,
			sensitive	=> $$self{CONNECTED},
			stockicon	=> $confirm ? 'gtk-dialog-question' : '',
			code		=> sub { $self -> _execute( 'local', $cmd, $confirm ) }
		} );
	}
	push( @vte_menu_items,
	{
		label		=> 'Local commands',
		stockicon	=> 'gtk-execute',
		tooltip		=> 'Execute LOCALLY (in YOUR computer) the selected command',
		submenu		=> \@cmd_local_sub_menu,
	} );
	
	my @insert_menu_items;
	
	# Populate with user defined variables
	my @variables_menu;
	my $i = 0;
	foreach my $value ( map{ $_->{txt} // '' } @{ $$self{variables} } ) {
		my $j = $i;
		push( @variables_menu,
		{
			#label => "<V:$j> ($value)",
			#code => sub { $$self{_GUI}{_VTE} -> feed_child( _subst( "<V:$j>", $$self{_CFG}, $$self{_UUID} ) ); }
			label => __( $j ),
			tooltip => "$j=$value",
			code => sub { my $t = _subst( "<V:$j>", $$self{_CFG}, $$self{_UUID} ); $$self{_GUI}{_VTE} -> feed_child( $t ); }
		} );
		++$i;
	}
	push( @insert_menu_items,
	{
		label => 'User variables...',
		sensitive => scalar @{ $$self{variables} },
		submenu => \@variables_menu
	} );
	
	# Populate with global defined variables
	my @global_variables_menu;
	foreach my $var ( sort { $a cmp $b } keys %{ $PACMain::FUNCS{_MAIN}{_CFG}{'defaults'}{'global variables'} } ) {
		my $val = $PACMain::FUNCS{_MAIN}{_CFG}{'defaults'}{'global variables'}{$var}{'value'};
		push( @global_variables_menu,
		{
			label => __( $var ),
			tooltip => "$var=$val",
			code => sub { my $t = _subst( "<GV:$var>", $$self{_CFG}, $$self{_UUID} ); $$self{_GUI}{_VTE} -> feed_child( $t ); }
		} );
	}
	push( @insert_menu_items,
	{
		label => 'Global variables...',
		sensitive => scalar( @global_variables_menu ),
		submenu => \@global_variables_menu
	} );
	
	# Populate with environment variables
	my @environment_menu;
	foreach my $key ( sort { $a cmp $b } keys %ENV ) {
		my $value = $ENV{$key};
		push( @environment_menu,
		{
			label => __( $key ),
			tooltip => "$key=$value",
			code => sub { my $t = _subst( "<ENV:$key>", $$self{_CFG}, $$self{_UUID} ); $$self{_GUI}{_VTE} -> feed_child( $t ); }
		} );
	}
	push( @insert_menu_items,
	{
		label => 'Environment variables...',
		submenu => \@environment_menu
	} );
	
	# Populate with KeePass entries
	if ( $$self{_CFG}{'defaults'}{'keepass'}{'use_keepass'} ) {
		my @kpx;
		foreach my $entry ( $PACMain::FUNCS{_KEEPASS} -> find ) {
			push( @kpx,
			{
				label	=> "Title:$$entry{title},User:$$entry{username}",
				tooltip	=> "Password:$$entry{password}",
				code	=> sub { $$self{_GUI}{_VTE} -> feed_child( $$entry{password} ); }
			} );
		}
		push( @insert_menu_items,
		{
			label => 'KeePassX',
			stockicon => 'pac-keepass',
			submenu => \@kpx
		} );
	}
	push( @vte_menu_items,
	{
		label		=> 'Insert value',
		stockicon	=> 'gtk-edit',
		tooltip		=> 'Send selected local/global/environment value to terminal',
		submenu		=> \@insert_menu_items,
	} );
	
	push( @vte_menu_items, { separator => 1 } );
	
	# Copy
	push( @vte_menu_items,
	{
		label		=> 'Copy',
		stockicon	=> 'gtk-copy',
		shortcut	=> '<control><shift>c',
		code		=> sub { $$self{_GUI}{_VTE} -> copy_clipboard; }
	} );
	# Paste
	push( @vte_menu_items,
	{
		label		=> 'Paste',
		stockicon	=> 'gtk-paste',
		shortcut	=> '<control><shift>v',
		sensitive	=> $$self{CONNECTED} && $$self{_GUI}{_VTE} -> get_clipboard( Gtk2::Gdk -> SELECTION_CLIPBOARD ) -> wait_is_text_available,
		code		=> sub {
			my $txt = $$self{_GUI}{_VTE} -> get_clipboard( Gtk2::Gdk -> SELECTION_CLIPBOARD ) -> wait_for_text;
			$self -> _pasteToVte( $txt, $$self{_CFG}{environments}{ $$self{_UUID} }{'send slow'} );
		}
	} );
	# Paste Special
	push( @vte_menu_items,
	{
		label		=> 'Paste and Delete...',
		stockicon	=> 'gtk-paste',
		shortcut	=> '<control><shift>b',
		tooltip		=> 'Paste clipboard contents, but remove any Perl RegExp matching string from the appearing prompt GUI',
		sensitive	=> $$self{CONNECTED} && $$self{_GUI}{_VTE} -> get_clipboard( Gtk2::Gdk -> SELECTION_CLIPBOARD ) -> wait_is_text_available,
		code		=> sub {
			my $text = $$self{_GUI}{_VTE} -> get_clipboard( Gtk2::Gdk -> SELECTION_CLIPBOARD ) -> wait_for_text;
			my $delete = _wEnterValue(
				$$self{_GUI},
				"Enter the String/RegExp of text to be *deleted* when pasting.\nUseful for, for example, deleting 'carriage return' from the text before pasting it.",
				'Use string or Perl RegExps (ex: \n means "carriage return")',
				'\n|\f|\r'
			) or return 1;
			$text =~ s/$delete//g;
			$self -> _pasteToVte( $text, $$self{_CFG}{environments}{ $$self{_UUID} }{'send slow'} || 1 );
		}
	} );
	
	# Add find string
	push( @vte_menu_items, { separator => 1 } );
	push( @vte_menu_items, { label => 'Find...', stockicon => 'gtk-find', shortcut => '<control>F3', code => sub { $self -> _wFindInTerminal; return 1; } } );
	
	# Add show command history
	push( @vte_menu_items, { label => 'Command History...', shortcut => '<alt>h', stockicon => 'gtk-orientation-landscape', sensitive => $$self{_CFG}{'defaults'}{'record command history'}, code => sub{ $self -> _wHistory; } } );
	
	# Add save session log
	push( @vte_menu_items, { label => 'Save session log...', stockicon => 'gtk-save', code => sub{ $self -> _saveSessionLog; } } );
	
	# Add edit session
	push( @vte_menu_items, { label => 'Edit session...', stockicon => 'gtk-edit', shortcut => '<alt>e', sensitive => $$self{_UUID} ne '__PAC_SHELL__', code => sub{ $PACMain::FUNCS{_EDIT} -> show( $$self{_UUID} ); } } );
	
	# Add change temporary tab label
	push( @vte_menu_items, { label => 'Temporary TAB Label change...', stockicon => 'gtk-edit', code => sub {
		# Prepare the input window
		my $new_label = _wEnterValue(
			$PACMain::FUNCS{_MAIN}{_GUI}{main},
			"<b>Temporaly renaming label '" . __( $$self{_TITLE} ) . "'</b>",
			'Enter the new temporal label:',
			$$self{_TITLE}
		);
		
		$$self{_TITLE} = $new_label if ( ( defined $new_label ) && ( $new_label !~ /^\s*$/go ) );
		$self -> _setTabColour;
	} } );
	
	# Change title with guessed hostname
	push( @vte_menu_items, { label => 'Set title with guessed hostname', sensitive => ( $$self{CONNECTED} && ! $$self{CONNECTING} ), shortcut => '<control><shift>g', code => sub { $self -> _execute( 'remote', '<CTRL_TITLE:hostname>', undef, undef, undef ); } } );
	
	# Open file explorer on current directory (for PAC Shells only)
	$$self{_UUID} eq '__PAC_SHELL__' and push( @vte_menu_items, { label => 'Open file manager on current dir', stockicon => 'gtk-open', sensitive => ( $$self{CONNECTED} && ! $$self{CONNECTING} ), code => sub { $self -> _execute( 'remote', 'xdg-open .', undef, undef, undef ); } } );
	
	# Add take screenshot
	push( @vte_menu_items, { label => 'Take Screenshot', stockicon => 'gtk-media-record', sensitive => $$self{_UUID} ne '__PAC_SHELL__', code => sub {
		my $screenshot_file = '';
		$screenshot_file = '/tmp/pac_screenshot_' . rand( 123456789 ). '.jpg';
		while( -f $screenshot_file ) { $screenshot_file = '/tmp/pac_screenshot_' . rand( 123456789 ). '.jpg'; }
		select( undef, undef, undef, 0.5 );
		_screenshot( $$self{_GUI}{_VBOX}, $screenshot_file );
		$PACMain::FUNCS{_MAIN}{_GUI}{screenshots} -> add( $screenshot_file, $self -> {_CFG}{'environments'}{ $$self{_UUID} } );
		$PACMain::FUNCS{_MAIN} -> _updateGUIPreferences;
	} } );
	
	push( @vte_menu_items, { separator => 1 } );
	
	# Open SFTP to this connection if it is SSH
	push( @vte_menu_items,
	{
		label		=> 'Open new SFTP window',
		stockicon	=> 'pac-method-SFTP',
		sensitive	=> 1,
		code		=> sub {
			my @idx;
			my $newuuid = '_tmp_' . rand;
			push( @idx, [ $newuuid ] );
			$$self{_CFG}{environments}{$newuuid} = dclone( $$self{_CFG}{environments}{ $$self{_UUID} } );
			$$self{_CFG}{environments}{$newuuid}{method} = 'SFTP';
			$$self{_CFG}{environments}{$newuuid}{expect} = [];
			$$self{_CFG}{environments}{$newuuid}{options} = '';
			$$self{_CFG}{environments}{$newuuid}{_protected} = 1;
			$PACMain::{FUNCS}{_MAIN} -> _launchTerminals( \@idx );
		}
	} ) if ( ( $$self{_CFG}{environments}{$$self{_UUID}}{method} =~ /^.*ssh.*$/ ) || ( $$self{_CFG}{environments}{$$self{_UUID}}{method} eq 'SSH' ) );
	
	# Terminal reset options
	push( @vte_menu_items,
	{
		label		=> 'Terminal',
		stockicon	=> 'pac-shell',
		sensitive	=> 1,
		submenu		=> 
		[
			{
				label		=> 'Reset',
				stockicon	=> 'gtk-refresh',
				sensitive	=> 1,
				shortcut	=> '<control><shift>x',
				code => sub{ $$self{_GUI}{_VTE} -> reset( 1, 0 ); }
			},
			{
				label		=> 'Reset and clear',
				stockicon	=> 'gtk-refresh',
				sensitive	=> 1,
				shortcut	=> '<control><alt><shift>x',
				code => sub{ $$self{_GUI}{_VTE} -> reset( 1, 1 ); }
			}
		]
	} );
	
	# Session options
	push( @vte_menu_items,
	{
		label		=> 'Session',
		stockicon	=> 'pac-method-' . $$self{_CFG}{environments}{$$self{_UUID}}{method},
		sensitive	=> 1,
		submenu		=> 
		[
			# Start/stop automatic string sending
			{
				label		=> ( defined $$self{_SEND_STRING} ? 'Stop' : 'Start' ) . ' programatically string sending',
				tooltip		=> $$self{_CFG}{environments}{ $$self{_UUID} }{'send string txt'} ne '' ? ( $$self{_CFG}{environments}{ $$self{_UUID} }{'send string txt'} . "\nEvery: " . ( $$self{_CFG}{environments}{ $$self{_UUID} }{'send string every'} ) . ' seconds' ) : '',
				sensitive	=> $$self{_CFG}{environments}{ $$self{_UUID} }{'send string txt'} ne '',
				stockicon	=> defined $$self{_SEND_STRING} ? 'gtk-stop' : 'gtk-media-play',
				code		=> sub {
					if ( defined $$self{_SEND_STRING} ) {
						Glib::Source -> remove( $$self{_SEND_STRING} );
						undef $$self{_SEND_STRING};
					} else {
						defined $$self{_SEND_STRING} and Glib::Source -> remove( $$self{_SEND_STRING} );
						$$self{_SEND_STRING} = Glib::Timeout -> add_seconds( $$self{_CFG}{environments}{ $$self{_UUID} }{'send string every'}, sub {
							return 1 unless $$self{CONNECTED};
							
							my $txt = $$self{_CFG}{environments}{ $$self{_UUID} }{'send string txt'};
							my $intro = $$self{_CFG}{environments}{ $$self{_UUID} }{'send string intro'};
							$txt = _subst( $txt, $$self{_CFG}, $$self{_UUID} );
							$$self{_GUI}{_VTE} -> feed_child( $txt . ( $intro ? "\n" : '' ) );
							
							return 1;
						} );
					}
				}
			},
			# Duplicate connection
			{
				label		=> 'Duplicate connection',
				shortcut	=> '<control><shift>d',
				stockicon	=> 'gtk-copy',
				code		=> sub { $PACMain::FUNCS{_MAIN} -> _launchTerminals( [ [ $$self{_UUID} ] ] ) }
			},
			# Full Duplicate connection
			{
				label		=> 'FULL Duplicate connection',
				stockicon	=> 'gtk-copy',
				shortcut	=> '<control><shift><alt>d',
				sensitive	=> $$self{_SAVE_KEYS},
				tooltip		=> 'This option lets you choose which recorded commands do you want to reproduce in the Duplicated connection (use with caution!!)',
				code		=> sub { $self -> _wSelectKeypress; }
			},
			# Restart session
			{
				label		=> 'Restart session',
				stockicon	=> 'gtk-execute',
				sensitive	=> ! $$self{CONNECTED} || ! $$self{_PID},
				code		=> sub{ $self -> start; }
			},
			# Disconnect
			{
				label		=> 'Disconnect',
				stockicon	=> 'gtk-stop',
				sensitive	=> $$self{_PID},
				code		=> sub { kill( 15, $$self{_PID} ); }
			},
			# Disconnect and restart session
			{
				label		=> 'Disconnect and Restart session',
				stockicon	=> 'gtk-refresh',
				shortcut	=> '<control><shift>r',
				sensitive	=> $$self{CONNECTED} && $$self{_PID},
				code		=> sub { $self -> _disconnectAndRestartTerminal(); }
			},
			# Close terminal
			{
				label		=> 'Close Terminal',
				shortcut	=> '<control>F4',
				stockicon	=> 'gtk-close',
				code		=> sub { $self -> stop( 0, 1 ); }
			},
			# Close all terminals
			{
				label		=> 'Close All Terminals',
				shortcut	=> '<control><shift>F4',
				stockicon	=> 'gtk-close',
				sensitive	=> $self -> _hasOtherTerminals(),
				code		=> sub { $self -> _closeAllTerminals(); }
			},
			# Close disconnected terminals
			{
				label		=> 'Close Disconnected Terminals',
				shortcut	=> '<control><shift>n',
				stockicon	=> 'gtk-close',
				sensitive	=> $self -> _hasDisconnectedTerminals(),
				code		=> sub { $self -> _closeDisconnectedTerminals(); }
			}
		]
	} );
	
	_wPopUpMenu( \@vte_menu_items, $event );
	return 1;
}

sub _pasteToVte {
	my $self	= shift;
	my $txt		= shift // '';
	my $slow	= shift // 0;
	
	return 1 unless $txt;
	
	if ( ! $slow ) {
		$$self{_GUI}{_VTE} -> paste_clipboard;
	} else {
		foreach my $char ( split( '', $txt ) ) {
			$$self{_GUI}{_VTE} -> feed_child( $char );
			Gtk2 -> main_iteration while Gtk2 -> events_pending;
			select( undef, undef, undef, $slow / 1000 );
		}
	}
}

sub _setTabColour {
	my $self	= shift;
	my $i		= shift // 1;
	
	# Auto take screenshots of connections without any of them
	( ( $$self{_UUID} ne '__PAC__QUICK__CONNECT__' ) && ( $$self{_UUID} ne '__PAC_SHELL__' ) && $$self{'_CFG'}{'defaults'}{'show screenshots'} ) and $$self{_TAKE_SCREENSHOT} = Glib::Timeout -> add_seconds( $$self{_CFG}{environments}{ $$self{_UUID} }{method} =~ /rdesktop|RDP/go ? 10 : 2, sub {
		return 1 if ( ! $$self{CONNECTED} ) || ( ! $$self{_FOCUSED} );
		
		my $screenshot_file = '';
		$screenshot_file = '/tmp/pac_screenshot_' . rand( 123456789 ). '.jpg';
		while( -f $screenshot_file ) { $screenshot_file = '/tmp/pac_screenshot_' . rand( 123456789 ). '.jpg'; }
		_screenshot( $$self{EMBED} ? $$self{FOCUS} : $$self{_GUI}{_VBOX}, $screenshot_file );
		$PACMain::FUNCS{_MAIN}{_GUI}{screenshots} -> add( $screenshot_file, $$self{_CFG}{'environments'}{ $$self{_UUID} } );
		$PACMain::FUNCS{_MAIN} -> _updateGUIPreferences;
		
		return 0;
		
	} ) unless defined $$self{_TAKE_SCREENSHOT} || scalar( @{ $$self{_CFG}{environments}{ $$self{_UUID} }{screenshots} } );
	
	# On TABS, choose correct colour depending on connection status
	if ( $$self{_TABBED} ) {
		my $check_gui = $PACMain::RUNNING{ $$self{_UUID_TMP} }{terminal}{_SPLIT} ? $PACMain::RUNNING{ $$self{_UUID_TMP} }{terminal}{_SPLIT_VPANE} : $PACMain::RUNNING{ $$self{_UUID_TMP} }{terminal}{_GUI}{_VBOX};
		return 1 unless defined $check_gui;
		$$self{_FOCUSED} = $check_gui -> get_child_visible;
		
		$$self{_NEW_DATA} &&= ! $$self{_FOCUSED};
		$PACMain::RUNNING{ $PACMain::RUNNING{ $$self{_UUID_TMP} }{terminal}{_SPLIT} }{terminal}{_FOCUSED}	= $check_gui -> get_child_visible if $PACMain::RUNNING{ $$self{_UUID_TMP} }{terminal}{_SPLIT};
		$PACMain::RUNNING{ $PACMain::RUNNING{ $$self{_UUID_TMP} }{terminal}{_SPLIT} }{terminal}{_NEW_DATA}	&&= ! $PACMain::RUNNING{ $PACMain::RUNNING{ $$self{_UUID_TMP} }{terminal}{_SPLIT} }{terminal}{_FOCUSED} if $PACMain::RUNNING{ $$self{_UUID_TMP} }{terminal}{_SPLIT};
		
		my $conn_color		= $$self{_NEW_DATA} ? $$self{_CFG}{defaults}{'new data color'} : $$self{_CFG}{defaults}{'connected color'};
		my $disconn_color	= $$self{_CFG}{defaults}{'disconnected color'};
		my $rem_conn_color	= $PACMain::RUNNING{ $$self{_SPLIT} }{terminal}{_NEW_DATA} ? $$self{_CFG}{defaults}{'new data color'} : $$self{_CFG}{defaults}{'connected color'} if $$self{_SPLIT};
		
		if ( $$self{_SPLIT} ) {
			my $back1	= $$self{_CFG}{'environments'}{$$self{_UUID}}{'terminal options'}{'use personal settings'} && $$self{_CFG}{'environments'}{$$self{_UUID}}{'terminal options'}{'use tab back color'} ? "background=\"$$self{_CFG}{'environments'}{$$self{_UUID}}{'terminal options'}{'tab back color'}\"" : '';
			my $fore1	= 'foreground="' . ( $$self{CONNECTED} ? $conn_color : $disconn_color ) . '"';
			my $back2	= $$self{_CFG}{'environments'}{ $PACMain::RUNNING{ $$self{_SPLIT} }{terminal}{_UUID} }{'terminal options'}{'use personal settings'} && $$self{_CFG}{'environments'}{ $PACMain::RUNNING{ $$self{_SPLIT} }{terminal}{_UUID} }{'terminal options'}{'use tab back color'} ? "background=\"$$self{_CFG}{'environments'}{ $PACMain::RUNNING{ $$self{_SPLIT} }{terminal}{_UUID} }{'terminal options'}{'tab back color'}\"" : '';
			my $fore2	= 'foreground="' . ( $PACMain::RUNNING{ $$self{_SPLIT} }{terminal}{CONNECTED} ? $rem_conn_color : $disconn_color ) . '"';
			$$self{_GUI}{_TABLBL}{_LABEL} -> set_markup(
				'<span ' . $back1 . ' ' . $fore1 . '>' . __( $$self{_TITLE} ) . '</span>' .
				' + ' .
				'<span ' . $back2 . ' ' . $fore2 . '>' . __( $PACMain::RUNNING{ $$self{_SPLIT} }{terminal}{_TITLE} ) . '</span>'
			);
			$i and $PACMain::RUNNING{ $$self{_SPLIT} }{terminal} -> _setTabColour( --$i );
		} else {
			my $back	= $$self{_CFG}{'environments'}{$$self{_UUID}}{'terminal options'}{'use personal settings'} && $$self{_CFG}{'environments'}{$$self{_UUID}}{'terminal options'}{'use tab back color'} ? "background=\"$$self{_CFG}{'environments'}{$$self{_UUID}}{'terminal options'}{'tab back color'}\"" : '';
			my $fore	= 'foreground="' . ( $$self{CONNECTED} ? $conn_color : $disconn_color ) . '"';
			$$self{_GUI}{_TABLBL}{_LABEL} -> set_markup(
				'<span ' . $back . ' ' . $fore . '>' . __( $$self{_TITLE} ) . '</span>'
			);
		}
	} else {
		defined $$self{_WINDOWTERMINAL} and $$self{_WINDOWTERMINAL} -> set_icon_from_file( $$self{CONNECTED} ? $RealBin . '/res/pac_terminal64x64.png' : $RealBin . '/res/pac_terminal_x64x64.png' );
	}
	
	# Once checked the availability of new data, reset its value
	$$self{_NEW_DATA} = 0;
	
	return 1;
}

sub _updateStatus {
	my $self = shift;
	
	return 1 unless defined $$self{_GUI}{status};
	splice( @{ $$self{_HISTORY} }, 0, 2, ( '(... older status skipped...)' ) ) unless $$self{_STATUS_COUNT}++ < 15;
	push( @{ $$self{_HISTORY} }, $$self{_LAST_STATUS} );
	
	# Control CLUSTER status
	if ( $$self{_CLUSTER} ne '' ) {
		$$self{_GUI}{status} -> push( 0, "[ IN CLUSTER: $$self{_CLUSTER} ]" . ' - Status: ' . $$self{_LAST_STATUS} );
	} else {
		$$self{_GUI}{status} -> push( 0, ' - Status: ' . $$self{_LAST_STATUS} );
	}
	
	defined $$self{_GUI}{status} and $$self{_GUI}{status}	-> set_property( 'tooltip-text', join( "\n", @{ $$self{_HISTORY} } ) );
	defined $$self{_GUI}{pb} and $$self{_GUI}{pb}			-> set_property( 'tooltip-text', join( "\n", @{ $$self{_HISTORY} } ) );
	
	return 1;
}

sub _clusterCommit {
	my ( $self, $terminal, $string, $int ) = @_;
	
	return 1 unless $$self{_LISTEN_COMMIT} && ( $$self{_CLUSTER} ne '' ) && $$self{CONNECTED} && $$self{_PROPAGATE};
	
	$$self{_LISTEN_COMMIT} = 0;
	foreach my $uuid_tmp ( keys %PACMain::RUNNING ) {
		next if ( ! $PACMain::RUNNING{$uuid_tmp}{terminal}{CONNECTED} ) || ( $PACMain::RUNNING{$uuid_tmp}{terminal}{_CLUSTER} ne $$self{_CLUSTER} ) || ( $PACMain::RUNNING{$uuid_tmp}{terminal}{_UUID_TMP} eq $$self{_UUID_TMP} );
		$PACMain::RUNNING{$uuid_tmp}{terminal}{_LISTEN_COMMIT} = 0;
		$PACMain::RUNNING{$uuid_tmp}{terminal}{_GUI}{_VTE} -> feed_child( $string );
		$PACMain::RUNNING{$uuid_tmp}{terminal}{_LISTEN_COMMIT} = 1;
	}
	$$self{_LISTEN_COMMIT} = 1;
	
	return 1;
}

sub _saveHistory {
	my ( $self, $string ) = @_;
	$string //= '';
	return 1 unless $$self{_SAVE_KEYS};
	
	my ( $col, $row ) = $$self{_GUI}{_VTE} -> get_cursor_position;
	my ( $txt ) = $$self{_GUI}{_VTE} -> get_text_range( $row, 0, $row, $$self{_GUI}{_VTE} -> get_column_count, sub { 1; } );
	$txt =~ s/^(?:(?:\s+)|(?:\s+))$//go;
	if ( ( ! $$self{_HAVE_PROMPT} ) && ( $txt !~ /^\s*$/go ) ) {
		chomp $txt;
		$$self{_HAVE_PROMPT} = $txt;
	} elsif ( $$self{_INTRO_PRESS} ) {
		chomp $txt;
		$txt =~ s/^\Q$$self{_HAVE_PROMPT}\E//g;
		if ( $txt eq '' ) {
			$$self{_INTRO_PRESS} = 0;
			return 1;
		}
		$$self{_HAVE_PROMPT} = 0;
		$$self{_INTRO_PRESS} = 0;
		push( @{ $$self{_GUI}{treeKeys}{'data'} }, [ $txt, time ] );
		my $last = $#{ $$self{_GUI}{treeKeys}{'data'} };
		$$self{_GUI}{treeKeys} -> set_cursor( Gtk2::TreePath -> new_from_string( $last ) );
	}
}

sub _tabToWin {
	my $self	= shift;
	my $explode	= shift;
	
	my $tabs	= $self -> {_NOTEBOOK};
	
	my $i = $$self{_SPLIT} ? $$self{_GUI}{_SPLIT_VPANE} : $$self{_NOTEBOOK} -> page_num( $$self{_GUI}{_VBOX} );
	
	$self -> {_WINDOWTERMINAL} = Gtk2::Window -> new;
	if ( $$self{_SPLIT_VPANE} ) {
		$$self{_SPLIT_VPANE} -> reparent( $self -> {_WINDOWTERMINAL} );
		$PACMain::RUNNING{$$self{_SPLIT}}{terminal}{_TABBED} = 0;
	} else {
		if ( $$self{EMBED} ) {
			my $vbox = Gtk2::VBox-> new( 0, 0 );
			$$self{_WINDOWTERMINAL} -> add( $vbox);
				
				my $sc2 = Gtk2::ScrolledWindow -> new();
				$sc2 -> set_shadow_type( 'none' );
				$sc2 -> set_policy( 'automatic', 'automatic' );
				$vbox -> pack_start( $sc2, 1, 1, 0 );
					
					my $vp = Gtk2::Viewport -> new;
					$sc2 -> add( $vp );
				
				my $btnfocus = Gtk2::Button -> new_with_mnemonic( 'Set _keyboard focus' );
				$btnfocus -> set_image( Gtk2::Image -> new_from_icon_name( 'input-keyboard', 'GTK_ICON_SIZE_SMALL_TOOLBAR' ) );
				$btnfocus -> set( 'can_focus', 0 );
				$btnfocus -> signal_connect ( 'clicked' => sub { $$self{FOCUS} -> child_focus( 'GTK_DIR_TAB_FORWARD' ); } );
				$vbox -> pack_start( $btnfocus, 0, 1, 0 );
			
			$$self{_WINDOWTERMINAL} -> set_default_size( $$self{_GUI}{_VBOX} -> allocation -> width, $$self{_GUI}{_VBOX} -> allocation -> height - $$self{_GUI}{status} -> allocation -> height );
			$$self{_WINDOWTERMINAL} -> show_all;
			$$self{_GUI}{_SOCKET} -> reparent( $vp );
			$$self{_GUI}{_VBOX} -> destroy;
		} else {
			$$self{_GUI}{_VBOX} -> reparent( $self -> {_WINDOWTERMINAL} );
		}
	}
	
	$$self{_TABBED} = 0;
	
	$$self{_WINDOWTERMINAL} -> set_title( "$APPNAME (v$APPVERSION) : $$self{_TITLE}" );
	$$self{_WINDOWTERMINAL} -> set_icon_name( $$self{CONNECTED} ? 'gtk-connect' : 'gtk-disconnect' );
	$$self{_WINDOWTERMINAL} -> set_size_request( 200, 100 );
	
	my $hsize = $$self{_CFG}{environments}{ $$self{_UUID} }{'terminal options'}{'use personal settings'} ? $$self{_CFG}{environments}{ $$self{_UUID} }{'terminal options'}{'terminal window hsize'} : $$self{_CFG}{'defaults'}{'terminal windows hsize'};
	my $vsize = $$self{_CFG}{environments}{ $$self{_UUID} }{'terminal options'}{'use personal settings'} ? $$self{_CFG}{environments}{ $$self{_UUID} }{'terminal options'}{'terminal window vsize'} : $$self{_CFG}{'defaults'}{'terminal windows vsize'};
	$$self{_WINDOWTERMINAL} -> set_default_size( defined $explode ? ( $$explode{'width'}, $$explode{'height'} ) : ( $hsize, $vsize ) );
	
	$$self{_WINDOWTERMINAL} -> show;
	$$self{_WINDOWTERMINAL} -> present;
	
	# Capture window close
	$$self{_WINDOWTERMINAL} -> signal_connect( 'delete_event' => sub {
		$self -> stop( undef, 1 ) unless $$self{_GUILOCKED};
		return Gtk2::EVENT_STOP; # stop propagation
	} );
	
	$self -> _updateCFG;
	
	$$self{_SPLIT} and $PACMain::RUNNING{$$self{_SPLIT}}{terminal}{_WINDOWTERMINAL} = $$self{_WINDOWTERMINAL};
	$$self{_POST_SPLIT} and $self -> {_NOTEBOOK} -> remove_page( $i );
	
	return 1;
}

sub _winToTab {
	my $self = shift;
	
	my $tabs = $$self{_NOTEBOOK};
	
	# Append this GUI to a new TAB (with an associated label && event_box -> image(close) button)
	$$self{_GUI}{_TABLBL} = Gtk2::HBox -> new( 0, 0 );
		
		$$self{_GUI}{_TABLBL}{_EBLBL} = Gtk2::EventBox -> new;
			$$self{_GUI}{_TABLBL} -> pack_start( $$self{_GUI}{_TABLBL}{_EBLBL}, 1, 1, 0 );
			$$self{_GUI}{_TABLBL}{_LABEL} = Gtk2::Label -> new( $$self{_TITLE} );
			$$self{_GUI}{_TABLBL}{_EBLBL} -> add( $$self{_GUI}{_TABLBL}{_LABEL} );
		
		my $eblbl1 = Gtk2::EventBox -> new;
			$eblbl1 -> add( Gtk2::Image -> new_from_stock( 'gtk-close', 'menu' ) );
			$eblbl1 -> signal_connect( 'button_release_event' => sub { $_[1] -> button != 1 and return 0; $self -> stop( undef, 1 ); } );
			$$self{_GUI}{_TABLBL} -> pack_start( $eblbl1, 0, 1, 0 );
	
		$$self{_GUI}{_TABLBL}{_EBLBL} -> signal_connect( 'button_press_event' => sub {
			my ( $widget, $event ) = @_;
			
			if ( $event -> button eq 2 ) { $self -> stop( undef, 1 ); return 1; }
			if ( $event -> button ne 3 ) { return 0; }
			
			$self -> _tabMenu( $event );
	} );
	
	$$self{_GUI}{_TABLBL} -> show_all;
	
	$self -> _setupTabDND;
	
	$tabs -> show;
	
	if ( $$self{_SPLIT_VPANE} ) {
		$$self{_SPLIT_VPANE} -> reparent( $tabs );
		$tabs -> set_tab_label( $$self{_SPLIT_VPANE}, $$self{_GUI}{_TABLBL} );
		$tabs -> set_tab_reorderable( $$self{_SPLIT_VPANE}, 1 );
		$PACMain::RUNNING{$$self{_SPLIT}}{terminal}{_TABBED} = 1;
		$PACMain::RUNNING{$$self{_SPLIT}}{terminal}{_WINDOWTERMINAL} -> destroy;
		$PACMain::RUNNING{$$self{_SPLIT}}{terminal} -> _updateCFG unless $PACMain::RUNNING{$$self{_SPLIT}}{'is_shell'};
	} else {
		$$self{_GUI}{_VBOX} -> reparent( $tabs );
		$tabs -> set_tab_label( $$self{_GUI}{_VBOX}, $$self{_GUI}{_TABLBL} );
		$tabs -> set_tab_reorderable( $$self{_GUI}{_VBOX}, 1 );
		$$self{_WINDOWTERMINAL} -> destroy;
	}

	$$self{_TABBED} = 1;
	$self -> _updateCFG;
	
	$tabs -> set_current_page( -1 );
	if ( $$self{EMBED} )	{ $$self{FOCUS} -> child_focus( 'GTK_DIR_TAB_FORWARD' ); }
	else					{ $$self{FOCUS} -> grab_focus; }
	
	return 1;
}

sub _tabMenu {
	my $self	= shift;
	my $event	= shift;
	
	my @vte_menu_items;
	
	# Show a popup with the opened tabs (if tabbed!!)
	my @submenu_goto;
	foreach my $uuid ( keys %PACMain::RUNNING ) {
		my $i = $$self{_NOTEBOOK} -> page_num( $PACMain::RUNNING{$uuid}{terminal}{_SPLIT} ? $PACMain::RUNNING{$uuid}{terminal}{_SPLIT_VPANE} : $PACMain::RUNNING{$uuid}{terminal}{_GUI}{_VBOX} );
		next if ( $uuid eq $$self{_UUID} || $i < 0 );
		push( @submenu_goto,
		{
			label	=> "$i: $PACMain::RUNNING{$uuid}{terminal}{_TITLE}",
			code	=> sub { $$self{_NOTEBOOK} -> set_current_page( $i ); }
		} );
	}
	@submenu_goto = sort { $$a{label} cmp $$b{label} } @submenu_goto;
	push( @vte_menu_items,
	{
		label		=> 'Goto TAB',
		stockicon	=> 'gtk-jump-to',
		submenu		=> \@submenu_goto,
		sensitive	=> scalar( @submenu_goto )
	} );
	
	# If PAC Script running, show a STOP script menuitem
	if ( $$self{_SCRIPT_STATUS} ne 'STOP' ) {
		push( @vte_menu_items,
		{
			label		=> "Stop script '$$self{_SCRIPT_NAME}'",
			stockicon	=> 'gtk-media-stop',
			sensitive	=> 1,
			code		=> sub { kill( 15, $$self{_PID} ); }
		} );
		
		_wPopUpMenu( \@vte_menu_items, $event );
		return 1,
	}
	
	# Show a popup with the opened tabs (if tabbed!!)
	if ( ! $$self{EMBED} ) {
		if ( $$self{_TABBED} ) {
			my @submenu_split_v;
			my @submenu_split_h;
			foreach my $uuid_tmp ( keys %PACMain::RUNNING ) {
				my $i = $$self{_NOTEBOOK} -> page_num( $PACMain::RUNNING{$uuid_tmp}{terminal}{_SPLIT} ? $PACMain::RUNNING{$uuid_tmp}{terminal}{_SPLIT_VPANE} : $PACMain::RUNNING{$uuid_tmp}{terminal}{_GUI}{_VBOX} );
				next if ( $uuid_tmp eq $$self{_UUID_TMP} || $PACMain::RUNNING{$uuid_tmp}{terminal}{_TITLE} eq 'Info ' || $i < 0 );
				next if ( $$self{_SPLIT} || $PACMain::RUNNING{$uuid_tmp}{terminal}{_SPLIT} ) || ( ! $PACMain::RUNNING{$uuid_tmp}{terminal}{_TABBED} );
				push( @submenu_split_v,
				{
					label	=> "$i: $PACMain::RUNNING{$uuid_tmp}{terminal}{_TITLE}",
					code	=> sub { $self -> _split( $uuid_tmp ); }
				} );
				push( @submenu_split_h,
				{
					label	=> "$i: $PACMain::RUNNING{$uuid_tmp}{terminal}{_TITLE}",
					code	=> sub { $self -> _split( $uuid_tmp, 1 ); }
				} );
			}
			@submenu_split_v = sort { $$a{label} cmp $$b{label} } @submenu_split_v;
			@submenu_split_h = sort { $$a{label} cmp $$b{label} } @submenu_split_h;
			
			push( @vte_menu_items, { label => 'Detach TAB to a new Window', stockicon => 'gtk-fullscreen', code => sub { _tabToWin( $self ); return 1; } } );
			
			if ( $$self{_SPLIT} ) {
				push( @vte_menu_items,
				{
					label		=> 'Unsplit',
					stockicon	=> 'gtk-zoom-fit',
					code		=> sub { $self -> _unsplit; }
				} );
			} else {
				push( @vte_menu_items,
				{
					label		=> 'Split',
					stockicon	=> 'gtk-zoom-fit',
					sensitive	=> scalar( @submenu_split_v ) && scalar( @submenu_split_h ),
					submenu		=> 
					[
						{
							label		=> 'Vertically ',
							stockicon	=> 'gtk-zoom-fit',
							submenu		=> \@submenu_split_v,
							sensitive	=> scalar( @submenu_split_v )
						},
						{
							label		=> 'Horizontally',
							stockicon	=> 'gtk-zoom-fit',
							submenu		=> \@submenu_split_h,
							sensitive	=> scalar( @submenu_split_h )
						}
					]
				} );
			}
			push( @vte_menu_items, { separator => 1 } );
		} else {
			push( @vte_menu_items, { label => 'Attach Window to main TAB bar', stockicon => 'gtk-leave-fullscreen', code => sub { _winToTab( $self ); return 1; } } );
			push( @vte_menu_items, { separator => 1 } );
		}
	}
	
	# Prepare the "Add to Cluster" submenu...
	my @submenu_cluster;
	my %clusters;
	push( @submenu_cluster,
	{
		label		=> 'New Cluster...',
		stockicon	=> 'gtk-new',
		code		=> sub {
			my $cluster = _wEnterValue( $self, 'Enter a name for the <b>New Cluster</b>' );
			( ( ! defined $cluster ) || ( $cluster =~ /^\s*$/go ) ) and return 1;
			$PACMain::FUNCS{_CLUSTER} -> addToCluster( $$self{_UUID_TMP}, $cluster );
		}
	} );
	foreach my $uuid_tmp ( keys %PACMain::RUNNING ) {
		next unless ( $PACMain::RUNNING{$uuid_tmp}{terminal}{_CLUSTER} ne '' );
		
		$clusters{$PACMain::RUNNING{$uuid_tmp}{terminal}{_CLUSTER}}{total}++;
		$clusters{$PACMain::RUNNING{$uuid_tmp}{terminal}{_CLUSTER}}{connections} .= "$PACMain::RUNNING{$uuid_tmp}{terminal}{_NAME}\n";
	}
	foreach my $cluster ( sort { $a cmp $b } keys %clusters ) {
		my $tmp = $cluster;
		push( @submenu_cluster,
		{
			label		=> "$cluster ( $clusters{$cluster}{total} terminals connected )",
			tooltip		=> $clusters{$cluster}{connections},
			sensitive	=> $cluster ne $$self{_CLUSTER},
			code		=> sub { $PACMain::FUNCS{_CLUSTER} -> addToCluster( $$self{_UUID_TMP}, $tmp ); }
		} );
	}
	push( @vte_menu_items,
	{
		label		=> ( $$self{_CLUSTER} eq '' ? 'Add' : 'Change' ) . ' to Cluster',
		stockicon	=> 'gtk-add',
		sensitive	=> 1,
		submenu		=> \@submenu_cluster
	} );
	push( @vte_menu_items,
	{
		label		=> 'Remove from Cluster',
		stockicon	=> 'gtk-delete',
		sensitive	=> $$self{_CLUSTER} ne '',
		code		=> sub { $PACMain::FUNCS{_CLUSTER} -> delFromCluster( $$self{_UUID_TMP}, $$self{_CLUSTER} ); }
	} );
	push( @vte_menu_items,
	{
		label		=> 'Cluster Admin...',
		stockicon	=> 'gtk-justify-fill',
		sensitive	=> 1,
		code		=> sub { $PACMain::FUNCS{_CLUSTER} -> show; }
	} );
	push( @vte_menu_items, { separator => 1 } );
	
	push( @vte_menu_items, { label => 'Find...', stockicon => 'gtk-find', code => sub { $self -> _wFindInTerminal; return 1; } } );
	
	# Add show command history
	push( @vte_menu_items, { label => 'Command History...', stockicon => 'gtk-orientation-landscape', sensitive => $$self{_CFG}{'defaults'}{'record command history'}, code => sub{ $self -> _wHistory; } } );
	
	# Add save session log
	push( @vte_menu_items, { label => 'Save session log...', stockicon => 'gtk-save', code => sub{ $self -> _saveSessionLog; } } );
	
	# Add edit session
	push( @vte_menu_items, { label => 'Edit session...', stockicon => 'gtk-edit', sensitive => $$self{_UUID} ne '__PAC_SHELL__', code => sub{ $PACMain::FUNCS{_EDIT} -> show( $$self{_UUID} ); } } );
	
	# Add change temporary tab label
	push( @vte_menu_items, { label => 'Temporary TAB Label change...', stockicon => 'gtk-edit', code => sub {
		# Prepare the input window
		my $new_label = _wEnterValue(
			$PACMain::FUNCS{_MAIN}{_GUI}{main},
			"<b>Temporaly renaming label '" . __( $$self{_TITLE} ) . "'</b>",
			'Enter the new temporal label:',
			$$self{_TITLE}
		);
		
		$$self{_TITLE} = $new_label if ( ( defined $new_label ) && ( $new_label !~ /^\s*$/go ) );
		$self -> _setTabColour;
	} } );
	
	# Add a submenu with available connections
	push( @vte_menu_items, { separator => 1 } );
	push( @vte_menu_items, { label => 'New connection', stockicon => 'gtk-connect', submenu => &_menuAvailableConnections( $PACMain::FUNCS{_MAIN}{_GUI}{treeConnections}{data} ) } );
	
	# Add a 'duplicate connection' button
	push( @vte_menu_items, { label => 'Duplicate connection', stockicon => 'gtk-copy', sensitive => 1, code => sub{ $PACMain::FUNCS{_MAIN} -> _launchTerminals( [ [ $$self{_UUID} ] ] ); } } );
	
	# Add close terminal
	push( @vte_menu_items, { separator => 1 } );
	# Add a 'disconnect' button to disconnect without closing the terminal
	push( @vte_menu_items, { label => 'Disconnect session', stockicon => 'gtk-stop', sensitive => $$self{_PID}, code => sub { kill( 15, $$self{_PID} ); } } );
	push( @vte_menu_items, { label => 'Close terminal', stockicon => 'gtk-close', code => sub { $self -> stop( undef, 1 ); } } );
	push( @vte_menu_items, { label => 'Close ALL terminals', stockicon => 'gtk-close', code => sub {
		my @list = keys %PACMain::RUNNING;
		return 1 unless scalar( @list ) && _wConfirm( $$self{GUI}{_VBOX}, "Are you sure you want to CLOSE <b>every</b> terminal?" );
		foreach my $uuid ( @list ) { $PACMain::RUNNING{$uuid}{'terminal'} -> stop( 'force', 'deep' ); }
		return 1;
	} } );

	_wPopUpMenu( \@vte_menu_items, $event );
	
	return 1;
}

sub _split {
	my $self		= shift;
	my $uuid_tmp	= shift;
	my $vertical	= shift // '0';
	
	my $tabs = $self -> {_NOTEBOOK};
	$$self{_SPLIT_VERTICAL} = $vertical;
	
	my $new_vpane = $vertical ? Gtk2::VPaned -> new : Gtk2::HPaned -> new;
	
	$$self{_SPLIT_VPANE}									= $new_vpane; # Assign new parent pane to both terminals
	$PACMain::RUNNING{$uuid_tmp}{terminal}{_SPLIT_VPANE}	= $new_vpane; # Assign new parent pane to both terminals
	
	$$self{_GUI}{_VBOX}									-> reparent( $new_vpane ); # Move ME into new created PANE
	$PACMain::RUNNING{$uuid_tmp}{terminal}{_GUI}{_VBOX}	-> reparent( $new_vpane ); # Move THE OTHER TERMINAL into new created PANE
	
	# Append this GUI to a new TAB (with an associated label && event_box -> image(close) button)
	$$self{_GUI}{_TABLBL} = Gtk2::HBox -> new( 0, 0 );
		
		$$self{_GUI}{_TABLBL}{_EBLBL} = Gtk2::EventBox -> new;
			$$self{_GUI}{_TABLBL} -> pack_start( $$self{_GUI}{_TABLBL}{_EBLBL}, 1, 1, 0 );
			$$self{_GUI}{_TABLBL}{_LABEL} = Gtk2::Label -> new( $$self{_TITLE} . ' + ' . $PACMain::RUNNING{$uuid_tmp}{terminal}{_TITLE} );
			$$self{_GUI}{_TABLBL}{_EBLBL} -> add( $$self{_GUI}{_TABLBL}{_LABEL} );
		
		my $eblbl1 = Gtk2::EventBox -> new;
			$eblbl1 -> add( Gtk2::Image -> new_from_stock( 'gtk-close', 'menu' ) );
			$eblbl1 -> signal_connect( 'button_release_event' => sub { $_[1] -> button != 1 and return 0; $self -> stop( undef, 1 ); } );
			$$self{_GUI}{_TABLBL} -> pack_start( $eblbl1, 0, 1, 0 );
		
		$$self{_GUI}{_TABLBL}{_EBLBL} -> signal_connect( 'button_press_event' => sub {
			my ( $widget, $event ) = @_;
			if ( $event -> button eq 2 )	{ $self -> stop( undef, 1 ); return 1; }
			elsif ( $event -> button ne 3 )	{ return 0; }
			$self -> _tabMenu( $event );
			return 1;
		} );
		
	$$self{_GUI}{_TABLBL} -> show_all;
	
	$tabs -> append_page( $new_vpane, $$self{_GUI}{_TABLBL} );
	
	$tabs -> show_all;
	$tabs -> set_tab_reorderable( $new_vpane, 1 );
	$tabs -> set_current_page( -1 );
	
	$self -> _setupTabDND( $$self{_NOTEBOOK} );
	
	$$self{_SPLIT} = $uuid_tmp;
	$$self{_POST_SPLIT} = 0;
	$PACMain::RUNNING{$uuid_tmp}{terminal}{_SPLIT} = $$self{_UUID_TMP};
	$PACMain::RUNNING{$uuid_tmp}{terminal}{_POST_SPLIT} = 0;
	
	$self -> _updateCFG;
	$self -> _setTabColour;
	$PACMain::RUNNING{$uuid_tmp}{terminal} -> _updateCFG;
	
	my $req = $$self{_GUI}{_VBOX} -> get_parent -> size_request;
	my ( $x, $y ) = ( $req -> width, $req -> height );
	$$self{_SPLIT_VPANE} -> set_position( ( $vertical ? $y : $x ) / 1.3 );
	
	return 1;
}

sub _unsplit {
	my $self = shift;
	
	my $uuid_tmp	= $$self{_SPLIT};
	my $tabs		= $$self{_NOTEBOOK};
	my $page		= $$self{_NOTEBOOK} -> page_num( $$self{_SPLIT_VPANE} );
	
	my $new_vbox_1 = Gtk2::VBox -> new( 0, 0 );
	my $new_vbox_2 = Gtk2::VBox -> new( 0, 0 );
	
	$$self{_GUI}{_VBOX} -> reparent( $new_vbox_1 );
	$$self{_GUI}{_VBOX} = $new_vbox_1;
	$$self{_TABBED} = 1;
	$PACMain::RUNNING{$uuid_tmp}{terminal}{_GUI}{_VBOX} -> reparent( $new_vbox_2 );
	$PACMain::RUNNING{$uuid_tmp}{terminal}{_GUI}{_VBOX} = $new_vbox_2;
	$PACMain::RUNNING{$uuid_tmp}{terminal}{_TABBED} = 1;
	
	# Append this GUI to a new TAB (with an associated label && event_box -> image(close) button)
	$$self{_GUI}{_TABLBL} = Gtk2::HBox -> new( 0, 0 );
		
		$$self{_GUI}{_TABLBL}{_EBLBL} = Gtk2::EventBox -> new();
			$$self{_GUI}{_TABLBL} -> pack_start( $$self{_GUI}{_TABLBL}{_EBLBL}, 1, 1, 0 );
			$$self{_GUI}{_TABLBL}{_LABEL} = Gtk2::Label -> new( $$self{_TITLE} );
			$$self{_GUI}{_TABLBL}{_EBLBL} -> add( $$self{_GUI}{_TABLBL}{_LABEL} );
		
		my $eblbl1 = Gtk2::EventBox -> new();
			$eblbl1 -> add( Gtk2::Image -> new_from_stock( 'gtk-close', 'menu' ) );
			$eblbl1 -> signal_connect( 'button_release_event' => sub { $_[1] -> button != 1 and return 0; $self -> stop( undef, 1 ); } );
			$$self{_GUI}{_TABLBL} -> pack_start( $eblbl1, 0, 1, 0 );
		
		$$self{_GUI}{_TABLBL}{_EBLBL} -> signal_connect( 'button_press_event' => sub {
			my ( $widget, $event ) = @_;
			
			if ( $event -> button eq 2 )	{ $self -> stop( undef, 1 ); return 1; }
			elsif ( $event -> button ne 3 )	{ return 0; }
			
			$self -> _tabMenu( $event );
			return 1;
		} );
	
	$$self{_GUI}{_TABLBL} -> show_all;
	$tabs -> append_page( $new_vbox_1, $$self{_GUI}{_TABLBL} );
	
	$tabs -> show_all;
	$tabs -> set_tab_reorderable( $new_vbox_1, 1 );

	$self -> _setupTabDND;
	
	# Append this GUI to a new TAB (with an associated label && event_box -> image(close) button)
	$PACMain::RUNNING{$uuid_tmp}{terminal}{_GUI}{_TABLBL} = Gtk2::HBox -> new( 0, 0 );
		
		$PACMain::RUNNING{$uuid_tmp}{terminal}{_GUI}{_TABLBL}{_EBLBL} = Gtk2::EventBox -> new();
			$PACMain::RUNNING{$uuid_tmp}{terminal}{_GUI}{_TABLBL} -> pack_start( $PACMain::RUNNING{$uuid_tmp}{terminal}{_GUI}{_TABLBL}{_EBLBL}, 1, 1, 0 );
			$PACMain::RUNNING{$uuid_tmp}{terminal}{_GUI}{_TABLBL}{_LABEL} = Gtk2::Label -> new( $PACMain::RUNNING{$uuid_tmp}{terminal}{_TITLE} );
			$PACMain::RUNNING{$uuid_tmp}{terminal}{_GUI}{_TABLBL}{_EBLBL} -> add( $PACMain::RUNNING{$uuid_tmp}{terminal}{_GUI}{_TABLBL}{_LABEL} );
		
		my $eblbl3 = Gtk2::EventBox -> new();
			$eblbl3 -> add( Gtk2::Image -> new_from_stock( 'gtk-close', 'menu' ) );
			$eblbl3 -> signal_connect( 'button_release_event' => sub { $_[1] -> button != 1 and return 0; $self -> stop( undef, 1 ); } );
			$PACMain::RUNNING{$uuid_tmp}{terminal}{_GUI}{_TABLBL} -> pack_start( $eblbl3, 0, 1, 0 );
		
		$PACMain::RUNNING{$uuid_tmp}{terminal}{_GUI}{_TABLBL}{_EBLBL} -> signal_connect( 'button_press_event' => sub {
			my ( $widget, $event ) = @_;
			
			if ( $event -> button eq 2 )	{ $self -> stop( undef, 1 ); return 1; }
			elsif ( $event -> button ne 3 )	{ return 0; }
			
			$self -> _tabMenu( $event );
			return 1;
		} );
	
	$PACMain::RUNNING{$uuid_tmp}{terminal}{_GUI}{_TABLBL} -> show_all;
	$tabs -> append_page( $new_vbox_2, $PACMain::RUNNING{$uuid_tmp}{terminal}{_GUI}{_TABLBL} );
	
	$tabs -> show_all;
	$tabs -> set_tab_reorderable( $new_vbox_2, 1 );
	
	$PACMain::RUNNING{$uuid_tmp}{terminal} -> _setupTabDND;
	
	$$self{_SPLIT} = 0;
	$PACMain::RUNNING{$uuid_tmp}{terminal}{_SPLIT} = 0;
	$$self{_POST_SPLIT} = $new_vbox_1;
	$PACMain::RUNNING{$uuid_tmp}{terminal}{_POST_SPLIT} = $new_vbox_1;

	$$self{_SPLIT_VPANE} = 0;
	$PACMain::RUNNING{$uuid_tmp}{terminal}{_SPLIT_VPANE} = 0;
	
	$$self{_NOTEBOOK} -> remove_page( $page );
	
	$tabs -> set_current_page( -1 );
	
	$self -> _updateCFG;
	$PACMain::RUNNING{$uuid_tmp}{terminal} -> _updateCFG;
	
	return 1;
}

sub _setupTabDND {
	my $self	= shift;
	my $widget	= shift // $$self{_GUI}{_VBOX};
	
	$$self{_GUI}{_TABLBL} -> drag_source_set( 'GDK_BUTTON1_MASK', [ 'move' ], { 'target' => 'PAC Tabbed', 'flags' => [], 'info' => 0 } );
	$$self{_GUI}{_TABLBL} -> signal_connect( 'drag_begin' => sub {
		$_[1] -> set_icon_pixbuf( _scale( _screenshot( $widget ), 128, 128, 1), 0, 0 );
		my $i = $$self{_NOTEBOOK} -> page_num( $$self{_GUI}{_VBOX} );
		$PACMain::FUNCS{_MAIN}{DND}{source_tab} = $$self{_NOTEBOOK} -> get_nth_page( $i );
	} );
	$$self{_GUI}{_TABLBL} -> signal_connect( 'drag_end' => sub { $PACMain::FUNCS{_MAIN}{DND} = undef; return 1; } );
	$$self{_GUI}{_TABLBL} -> signal_connect( 'drag_failed' => sub { return 0 if $_[2] eq 'user-cancelled'; $self -> _tabToWin; } );
	
	$$self{_GUI}{_TABLBL} -> drag_dest_set( 'GTK_DEST_DEFAULT_ALL', [ 'move' ], { 'target' => 'PAC Tabbed', 'flags' => [], 'info' => 0 } );
	$$self{_GUI}{_TABLBL} -> signal_connect( 'drag_drop' => sub {
		my $i = $$self{_NOTEBOOK} -> page_num( $$self{_GUI}{_VBOX} );
		$$self{_NOTEBOOK} -> reorder_child( $PACMain::FUNCS{_MAIN}{DND}{source_tab}, $i );
		$$self{_NOTEBOOK} -> set_current_page( $i );
	} );
	
	return 1;
}

sub _saveSessionLog {
	my $self = shift;
	
	my $new_file = $$self{_LOGFILE};
	$new_file =~ s/\s/_/go;
	
	my $dialog = Gtk2::FileChooserDialog -> new (
		'Select file to save session log',
		undef,
		'select-folder',
		'gtk-ok'     => 'GTK_RESPONSE_OK',
		'gtk-cancel' => 'GTK_RESPONSE_CANCEL'
	);
	$dialog -> set_action( 'GTK_FILE_CHOOSER_ACTION_SAVE' );
	$dialog -> set_do_overwrite_confirmation( 1 );
	$dialog -> set_current_folder( $ENV{'HOME'} );
	$dialog -> set_current_name( $new_file );
	
	if ( $dialog -> run ne 'ok' ) { $dialog -> destroy; return 1; }
	$new_file = $dialog -> get_filename;
	$dialog -> destroy;
	
	my $confirm = _wYesNoCancel( undef, 'Do you want to remove escape sequences from the saved log?' );
	
	if ( $confirm eq 'yes' ) {
		if ( ! open( F, "$$self{_LOGFILE}" ) ) {
			_wMessage( undef, "ERROR: Could not open file '$$self{_LOGFILE}' for reading!! ($!)" );
			return 1;
		}
		my @lines = <F>;
		close F;
		
		if ( ! open( F, ">$new_file" ) ) {
			_wMessage( undef, "ERROR: Could not open file '$new_file' for writting!! ($!)" );
			return 1;
		}
		print F _removeEscapeSeqs( join( '', @lines ) );
		close F;
	} elsif ( $confirm eq 'no' ) {
		# Copy temporal log file to selected path
		copy( $$self{_LOGFILE}, $new_file );
	}
	
	return 1;
}

sub _execute {
	my $self	= shift;
	my $where	= shift;
	my $comm	= shift;
	my $confirm	= shift // 0;
	my $subst	= shift // 1;
	my $chain	= shift // 0;
	my $intro	= shift // 1;
	
	# Ask for confirmation
	$confirm and ( _wConfirm( $$self{GUI}{_VBOX}, "Execute <b>'" . __( $comm ) . "'</b> " . ( $where ne 'remote' ? 'LOCALLY' : 'REMOTELY' ) ) or return 1 );
	
	my ( $cmd, $data ) = _subst( $comm, $$self{_CFG}, $$self{_UUID} );
	if ( ! defined $cmd ) {
		_wMessage( $PACMain::FUNCS{_MAIN}{_GUI}{main}, "Canceled '<b>$where</b>' execution of '<b>" . __( $comm ) . "</b>'" );
		return 0;
	 }
	
	# Finally, execute 'remote' or 'local'
	if ( $where eq 'remote' ) {
		# Save last executed command
		$$self{_EXEC}{CMD}		= $cmd;
		$$self{_EXEC}{PIPE}		= $$data{pipe};
		$$self{_EXEC}{PROMPT}	= $$data{prompt};
		$$self{_EXEC}{FULL_CMD}	= $comm;
		
		# Prevent "Remote Executions storms" (half a second between interruptions to spawned processes)
		my $time = join( '.', gettimeofday );
		if ( ( $time - $$self{_EXEC_LAST} ) <= $EXEC_STORM_TIME ) {
			_wMessage( $$self{GUI}{_VBOX}, "Please, wait at least <b>$EXEC_STORM_TIME</b> seconds between Remote Commands Executions", 1 );
			return 1;
		}
		$$self{_EXEC_LAST} = $time;
		
		if ( ! kill( 'USR1', $$self{_PID} ) ) {
			_wMessage( $$self{GUI}{_VBOX}, "ERROR: Could not signal process '$$self{_PID}'\nInconsistent state!\nPlease, restart PAC!!", 1 );
			return 0;
		}
		my %tmp;
		$tmp{pipe}		= defined $$data{pipe} ? 1 : 0;
		$tmp{tee}		= $$data{tee} // 0;
		$tmp{prompt}	= $$data{prompt};
		$tmp{ctrl}		= $$data{ctrl};
		$tmp{intro}		= $intro // 1;
		$tmp{cmd}		= $cmd;
		nstore_fd( \%tmp, $$self{_SOCKET_CLIENT} ) or die "ERROR:$!";
	} elsif ( $where eq 'local' ) {
		system( $cmd . ' &' );
	}
	
	return 1;
}

sub _pipeExecOutput {
	my $self = shift;
	
	my $out		= $$self{_EXEC}{RECEIVED};
	my $pipe	= $$self{_EXEC}{PIPE};
	
	return 1 unless defined $out and defined $pipe;
	
	foreach my $cmd ( @{ $pipe } ) {
		open F, ">$$self{_TMPPIPE}"; print F $out; close F;
		$out = `cat $$self{_TMPPIPE} | $cmd 2>&1`;
	}
	$$self{_EXEC}{OUT} = $out;
	$PACMain::FUNCS{_PIPE} -> show;
	
	return 1;
}

sub _wPrePostExec {
	my $self = shift;
	my $when = shift;
	
	return 1 unless ( defined $$self{_CFG}{'environments'}{ $$self{_UUID} }{$when} && scalar( @{ $$self{_CFG}{'environments'}{ $$self{_UUID} }{$when} } ) );
	
	# Build window
	my %ppe = _ppeGUI( $self );
	
    # Empty the connections tree
	@{ $ppe{window}{gui}{treeview}{data} } = ();

	# Populate the local executions tree
	my $total		= 0;
	my $total_noask	= 0;
	my $total_ask	= 0;
	foreach my $hash ( @{ $$self{_CFG}{'environments'}{ $$self{_UUID} }{$when} } ) {
		my $ask		= $$hash{'ask'} || 0;
		my $default	= $$hash{'default'} || 0;
		my $command	= $$hash{'command'};
		next if $command eq '';
		
		$total_noask	+= ! $ask;
		$total_ask		+= $ask;
		
		push( @{ $ppe{window}{gui}{treeview}{data} }, [ $default, $command ] );
		++$total;
	}
	return 1 unless $total;

	# Change mouse cursor (to busy) in VTE window
	$$self{_GUI}{_VBOX} -> window -> set_cursor( Gtk2::Gdk::Cursor -> new( 'watch' ) );

	# Now, prepare the local executions window, show it, AND stop until something clicked
	$ppe{window}{data} -> show_all;
	
	if ( ( $total_noask ) && ! $total_ask ) { $ppe{window}{btnOk} -> activate; return 1; }
	
	$when eq 'local before' and my $ok = $ppe{window}{data} -> run;
	
	return 1;
	
	sub _execLocalPPE {
		my $self	= shift;
		my %ppe		= %{ shift() };
		
		# Get total # of commands checked to be executed (for the progress bar)
		my $t = 0;
		foreach my $line ( @{ $ppe{window}{gui}{treeview}{data} } ) { my ( $def, $cmd ) = @{ $line }; $t += $def; }
		
		# Change mouse cursor (to busy)
		$ppe{window}{data} -> window -> set_cursor( Gtk2::Gdk::Cursor -> new( 'watch' ) );
		$ppe{window}{data} -> set_sensitive( 0 );
		
		my $i = 0;
		foreach my $line ( @{ $ppe{window}{gui}{treeview}{data} } ) {
			my ( $def, $cmd ) = @{ $line };
			
			# Skip unchecked commands
			next unless $def;
			
			# Replace PAC variables with their corresponding values
			$cmd = _subst( $cmd, $$self{_CFG}, $$self{_UUID} );
			
			# Make some update to progress bar
			$ppe{window}{gui}{pb} -> set_text( 'Executing: ' . $cmd );
			$ppe{window}{gui}{pb} -> set_fraction( ++$i / $t );
			Gtk2 -> main_iteration while Gtk2 -> events_pending;
			
			# Launch the local command
			system( $cmd );
		}
		
		# Change mouse cursor (to normal)
		$ppe{window}{data} -> window -> set_cursor( Gtk2::Gdk::Cursor -> new( 'left-ptr' ) );
		$ppe{window}{data} -> set_sensitive( 1 );
		
		return 1;
	}
	
	sub _ppeGUI {
		my $self = shift;
		
		my %w;
		
		# Create the dialog window,
		$w{window}{data} = Gtk2::Dialog -> new_with_buttons(
			$self -> {_NAME} . " : $APPNAME : Local execution",
			undef,
			'modal',
		);
		# and setup some dialog properties.
		$w{window}{data} -> set_default_response( 'ok' );
		$w{window}{data} -> set_position( 'center' );
		$w{window}{data} -> set_icon_from_file( $APPICON );
		$w{window}{data} -> set_size_request( 400, 300 );
		$w{window}{data} -> set_resizable( 1 );
		$w{window}{btnOk} = $w{window}{data} -> add_button( '_Ok' , 1 );
		$w{window}{btnCancel} = $w{window}{data} -> add_button( '_Cancel' , 0 );
			
			# Create frame
			$w{window}{gui}{frame} = Gtk2::Frame -> new;
			$w{window}{data} -> vbox -> pack_start( $w{window}{gui}{frame}, 1, 1, 0 );
			$w{window}{gui}{frame} -> set_label( 'Select local command(s) to execute:' );
			$w{window}{gui}{frame} -> set_border_width( 5 );
				
				# Create a GtkScrolledWindow,
				my $sct = Gtk2::ScrolledWindow -> new;
				$w{window}{gui}{frame} -> add( $sct );
				
				$sct -> set_shadow_type( 'none' );
				$sct -> set_policy( 'automatic', 'automatic' );
				
				# Create treeview
				$w{window}{gui}{treeview} = Gtk2::Ex::Simple::List -> new_from_treeview (
					Gtk2::TreeView -> new,
					' EXECUTE?'			=> 'bool',
					' LOCAL COMMAND'	=> 'text'
				);
				$sct -> add( $w{window}{gui}{treeview} );
				
			# Create progress bar
			$w{window}{gui}{pb} = Gtk2::ProgressBar -> new;
			$w{window}{data} -> vbox -> pack_start( $w{window}{gui}{pb}, 0, 1, 5 );
		
		$w{window}{data} -> signal_connect( 'response' => sub {
			my ( $me, $response ) = @_;
			$response eq '1' and _execLocalPPE( $self, \%w );
			$w{window}{data} -> destroy;
			$$self{_GUI}{_VBOX} -> window -> set_cursor( Gtk2::Gdk::Cursor -> new( 'left-ptr' ) );
			undef %w;
		} );
		
		return %w;
	}

}

sub _wSelectChain {
	my $self		= shift;
	my $drop_uuid	= shift;
	
	# Build window
	my %ppe = _chainGUI( $self, $drop_uuid );
	
    # Empty the connections tree
	@{ $ppe{window}{gui}{treeview}{data} } = ();

	# Populate the local executions tree
	my $total = 0;
	my $sfce = $$self{_CFG}{'defaults'}{'skip first chain expect'};
	foreach my $hash ( @{ $$self{_CFG}{'environments'}{ $drop_uuid }{'expect'} } ) {
		my $pattern		= $$hash{'expect'}		// '';
		my $command		= $$hash{'send'}		// '';
		my $hide		= $$hash{'hidden'}		// 0;
		my $active		= $$hash{'active'}		// 0;
		my $return		= $$hash{'return'}		// 1;
		my $on_match	= $$hash{'on_match'}	// -1;
		my $on_fail		= $$hash{'on_fail'}		// -1;
		my $time_out	= $$hash{'time_out'}	// -1;
		
			push( @{ $ppe{window}{gui}{treeview}{data} },
		[
			$total,
			$active,
			$total ? $pattern : $sfce ? '<no-expect!>' : $pattern,
			$command,
			$return ? 'yes' : 'no',
			$on_match	== -1 ? '' : ( $on_match == -2 ? 'stop' : $on_match ),
			$on_fail	== -1 ? '' : ( $on_fail == -2 ? 'stop' : $on_fail ),
			$time_out	== -1 ? '' : $time_out
		] );
		++$total;
	}
	return 0 unless $total;
	
	if ( $$self{_CFG}{'defaults'}{'confirm chains'} ) {
		# Now, prepare the chains window, show it, AND stop until something clicked
		$ppe{window}{data} -> show_all;
		$ppe{window}{data} -> action_area -> child_focus( 'GTK_DIR_TAB_FORWARD' );
		$ppe{window}{data} -> signal_connect( 'response' => sub {
			my ( $me, $response ) = @_;
			$response eq 'ok' and _chain( $self, $drop_uuid, \%ppe );
			$ppe{window}{data} -> destroy;
			undef %ppe;
		} );
		my $ok = $ppe{window}{data} -> run;
	} else {
		_chain( $self, $drop_uuid, \%ppe );
	}
	
	return 1;
	
	sub _chain
	{
		my $self		= shift;
		my $drop_uuid	= shift;
		my %ppe			= %{ shift() };
		
		# Prepare configuration to be chained with current connection
		my %new_cfg;
		$new_cfg{'defaults'}								= dclone( $$self{_CFG}{'defaults'} );
		$new_cfg{'environments'}{ $drop_uuid }				= dclone( $$self{_CFG}{'environments'}{$drop_uuid} );
		$new_cfg{'tmp'}										= dclone( $$self{_CFG}{'tmp'} );
		$new_cfg{'tmp'}{'set title'}						= $ppe{window}{gui}{cbChangeTitle} -> get_active;
		$new_cfg{'tmp'}{'title'}							= $ppe{window}{gui}{entrytitle} -> get_chars( 0, -1 );
		$new_cfg{'environments'}{ $drop_uuid }{'expect'}	= ();
		
		my $total = 0;
		my $sfce = $$self{_CFG}{'defaults'}{'skip first chain expect'};
		foreach my $line ( @{ $ppe{window}{gui}{treeview}{data} } ) {
			my ( $num, $active, $pattern, $command, $return, $on_match, $on_fail, $time_out ) = @{ $line };
			
			push( @{ $new_cfg{'environments'}{ $drop_uuid }{'expect'} }, {
				'expect'	=> $total ? $pattern : $sfce ? '' : $pattern,
				'send'		=> $command,
				'hidden'	=> 0,
				'active'	=> $active,
				'return'	=> $return eq '1',
				'on_match'	=> $on_match	eq '' ? -1 : ( $on_match eq 'stop' ? -2 : $on_match ),
				'on_fail'	=> $on_fail		eq '' ? -1 : ( $on_fail eq 'stop' ? -2 : $on_fail ),
				'time_out'	=> $time_out	ne '' ? $time_out : -1,
			} );
			++$total;
		}
		
		if ( $ppe{window}{gui}{cbExecInCluster} -> get_active ) {
			foreach my $cluster_uuid ( keys %PACMain::RUNNING ) {
				if ( ! kill( 'HUP', $PACMain::RUNNING{$cluster_uuid}{terminal}{_PID} ) ) {
					_wMessage( $$self{GUI}{_VBOX}, "ERROR: Could not signal process '$PACMain::RUNNING{$cluster_uuid}{terminal}{_PID}'\nInconsistent state!\nPlease, restart PAC!!", 1 );
					return 0;
				}
				
				# Send the UUID to chain with
				$PACMain::RUNNING{$cluster_uuid}{terminal}{_SOCKET_CLIENT} -> send( "!!_PAC_CHAIN_[$drop_uuid]!!" );
				# And send the configuration for that UUID
				nstore_fd( \%new_cfg, $PACMain::RUNNING{$cluster_uuid}{terminal}{_SOCKET_CLIENT} ) or die "ERROR:$!";
			}
		} else {
			if ( ! kill( 'HUP', $$self{_PID} ) ) {
				_wMessage( $$self{GUI}{_VBOX}, "ERROR: Could not signal process '$$self{_PID}'\nInconsistent state!\nPlease, restart PAC!!", 1 );
				return 0;
			}
			
			# Send the UUID to chain with
			$$self{_SOCKET_CLIENT} -> send( "!!_PAC_CHAIN_[$drop_uuid]!!" );
			# And send the configuration for that UUID
			nstore_fd( \%new_cfg, $$self{_SOCKET_CLIENT} ) or die "ERROR:$!";
		}
		
		undef %new_cfg;
		
		return 1;
	}
	
	sub _chainGUI
	{
		my $self		= shift;
		my $drop_uuid	= shift;
		
		my $select_all	= 0;
		
		my %w;
		
		# Create the dialog window,
		$w{window}{data} = Gtk2::Dialog -> new_with_buttons(
			$self -> {_NAME} . " : $APPNAME : Chain connections",
			$PACMain::FUNCS{_MAIN}{_GUI}{main},
			'modal',
			'gtk-ok'		=> 'ok',
			'gtk-cancel'	=> 'cancel'
		);
		# and setup some dialog properties.
		$w{window}{data} -> set_default_response( 'ok' );
		$w{window}{data} -> set_position( 'center' );
		$w{window}{data} -> set_icon_from_file( $APPICON );
		$w{window}{data} -> set_size_request( 600, 300 );
		$w{window}{data} -> set_resizable( 1 );
			
			# Create frame
			$w{window}{gui}{frame} = Gtk2::Frame -> new;
			$w{window}{data} -> vbox -> pack_start( $w{window}{gui}{frame}, 1, 1, 0 );
			$w{window}{gui}{frame} -> set_label( " Select 'expect/command' pairs from '$$self{_CFG}{'environments'}{$drop_uuid}{'name'}' to be executed into '$$self{_CFG}{'environments'}{$$self{_UUID}}{'name'}': " );
			$w{window}{gui}{frame} -> set_border_width( 5 );
				
				# Create a GtkScrolledWindow,
				my $sct = Gtk2::ScrolledWindow -> new;
				$w{window}{gui}{frame} -> add( $sct );
				
				$sct -> set_shadow_type( 'none' );
				$sct -> set_policy( 'automatic', 'automatic' );
				
				# Create treeview
				$w{window}{gui}{treeview} = Gtk2::Ex::Simple::List -> new_from_treeview (
					Gtk2::TreeView -> new,
					' # '			=> 'int',
					' ACTIVE '		=> 'bool',
					' PATTERN '		=> 'text',
					' COMMAND '		=> 'text',
					' RETURN '		=> 'bool',
					' ON MATCH '	=> 'text',
					' ON FAIL '		=> 'text',
					' TIME OUT '	=> 'text'
				);
				$sct -> add( $w{window}{gui}{treeview}  );
			
			$w{window}{gui}{hboxtitle} = Gtk2::HBox -> new( 0, 0 ),
			$w{window}{data} -> vbox -> pack_start( $w{window}{gui}{hboxtitle}, 0, 1, 0 );
				
				$w{window}{gui}{btnSelectAll} = Gtk2::Button -> new( "Select All/None" );
				$w{window}{gui}{hboxtitle} -> pack_start( $w{window}{gui}{btnSelectAll}, 0, 1, 5 );
				$w{window}{gui}{btnSelectAll} -> signal_connect( 'clicked' => sub {
					$$_[0] = $select_all foreach ( @{ $w{window}{gui}{treeview}{data} } );
					$select_all = ! $select_all;
				} );
				
				$w{window}{gui}{cbChangeTitle} = Gtk2::CheckButton -> new_with_label( "Change TAB/Window title to: " );
				$w{window}{gui}{cbChangeTitle} -> set_active( 1 );
				$w{window}{gui}{hboxtitle} -> pack_start( $w{window}{gui}{cbChangeTitle}, 0, 1, 0 );
				
				$w{window}{gui}{entrytitle} = Gtk2::Entry -> new;
				$w{window}{gui}{hboxtitle} -> pack_start( $w{window}{gui}{entrytitle}, 1, 1, 0 );
				$w{window}{gui}{entrytitle} -> set_text(  $$self{_CFG}{'environments'}{ $drop_uuid }{'title'} );
		
			$w{window}{gui}{cbExecInCluster} = Gtk2::CheckButton -> new_with_label( 'Send Chain to all connections in cluster' . ( $$self{_CLUSTER} ne '' ? " '$$self{_CLUSTER}'" : '' ) );
			$w{window}{data} -> vbox  -> pack_start( $w{window}{gui}{cbExecInCluster}, 0, 1, 0 );
			$w{window}{gui}{cbExecInCluster} -> set_active( 0 );
			$w{window}{gui}{cbExecInCluster} -> set_sensitive( $$self{_CLUSTER} ne '' );
		
		return %w;
	}

}

sub _wSelectKeypress {
	my $self	= shift;
	
	our %w;
	
	defined $w{window} and return $w{window}{data} -> present;
	
	# Create the dialog window,
	$w{window}{data} = Gtk2::Window -> new;
	
	$w{window}{data} -> signal_connect( 'delete_event' => sub {
		$w{window}{data} -> destroy;
		undef %w;
		return 1;
	} );
	
	$w{window}{data} -> signal_connect( 'key_press_event' => sub {
		my ( $widget, $event ) = @_; 
		my $keyval	= '' . ( $event -> keyval );
		return 0 unless $keyval == 65307;
		$w{window}{gui}{btnclose} -> activate();
		return 1;
	} );	
	
	# and setup some dialog properties.
	$w{window}{data} -> set_title( $self -> {_TITLE} . " : $APPNAME : Select keypresses to propagate to Duplicated Connection" );
	$w{window}{data} -> set_position( 'center' );
	$w{window}{data} -> set_icon_from_file( $APPICON );
	$w{window}{data} -> set_default_size( 600, 480 );
	$w{window}{data} -> set_resizable( 1 );
	$w{window}{data} -> set_modal( 1 );
	$w{window}{data} -> set_transient_for( $PACMain::FUNCS{_MAIN}{_GUI}{main} );
		
		# Create a vbox
		$w{window}{gui}{vbox} = Gtk2::VBox -> new( 0, 0 );
		$w{window}{data} -> add( $w{window}{gui}{vbox} );
			
			$w{window}{gui}{label0} = Gtk2::Label -> new;
			$w{window}{gui}{vbox} -> pack_start( $w{window}{gui}{label0}, 0, 1, 0 );
			$w{window}{gui}{label0} -> set_justify( 'center' );
			$w{window}{gui}{label0} -> set_markup( "<big><b><span foreground=\"#FF0000\">***************** ATTENTION *****************</span></b></big>\nAre you sure you want to duplicate this connection, including <b>every kestroke</b> registered until now?\nThat can be *very dangerous*, specially if you do not remember your keyboard activity in this terminal.\nIf unsure, click 'Cancel' and take a look at this terminals's history" );
			
			# Create frame 1
			$w{window}{gui}{frame1} = Gtk2::Frame -> new;
			$w{window}{gui}{vbox} -> pack_start( $w{window}{gui}{frame1}, 1, 1, 0 );
			$w{window}{gui}{frame1} -> set_label( ' Command History: ' );
			$w{window}{gui}{frame1} -> set_border_width( 5 );
				
				# Create a GtkScrolledWindow,
				my $sctxt = Gtk2::ScrolledWindow -> new;
				$w{window}{gui}{frame1} -> add( $sctxt );
				$sctxt -> set_shadow_type( 'none' );
				$sctxt -> set_policy( 'automatic', 'automatic' );
				$sctxt -> set_border_width( 5 );
				
				# Create treefound
				$w{window}{gui}{treefound} = Gtk2::Ex::Simple::List -> new_from_treeview (
					Gtk2::TreeView -> new,
					' Execute '			=> 'bool',
					' Last Execution '	=> 'text',
					' Command '			=> 'text',
					' cmd '				=> 'hidden'
				);
				$w{window}{gui}{treefound} -> set_headers_visible( 1 );
				$w{window}{gui}{treefound} -> set_grid_lines( 'both' );
				$w{window}{gui}{treefound} -> get_selection -> set_mode( 'single' );
				foreach my $array ( @{ $$self{_GUI}{treeKeys}{data} } ) {
					my $cmd		= $$array[0];
					my $cmdt	= $$array[1];
					
					push( @{ $w{window}{gui}{treefound}{data} },
					[
						1,
						strftime( "%Y-%m-%d %H:%M:%S", localtime( $cmdt ) ),
						_replaceBadChars( $cmd ),
						$cmd
					] );
				}
				
				# Put treefound into scrolledwindow
				$sctxt -> add( $w{window}{gui}{treefound} );
		
		# Put a separator
		$w{window}{gui}{sep} = Gtk2::HSeparator -> new;
		$w{window}{gui}{vbox} -> pack_start( $w{window}{gui}{sep}, 0, 1, 5 );
		
		$w{window}{gui}{hbox1} = Gtk2::HBox -> new( 0, 0 );
		$w{window}{gui}{vbox} -> pack_start( $w{window}{gui}{hbox1}, 0, 1, 0 );
			
			$w{window}{gui}{lblSleep} = Gtk2::Label -> new( 'Time between commands to replicate: ' );
			$w{window}{gui}{hbox1} -> pack_start( $w{window}{gui}{lblSleep}, 0, 1, 0 );
			
			$w{window}{gui}{spSleep} = Gtk2::SpinButton -> new_with_range( 0, 86400, 1/2 );
			$w{window}{gui}{hbox1} -> pack_start( $w{window}{gui}{spSleep}, 0, 1, 0 );
			$w{window}{gui}{spSleep} -> set_value( 1/2 );
		
		# Put a separator
		$w{window}{gui}{sep2} = Gtk2::HSeparator -> new;
		$w{window}{gui}{vbox} -> pack_start( $w{window}{gui}{sep2}, 0, 1, 5 );
		
		# Put a hbox to add exec/close buttons
		$w{window}{gui}{hbtnbox} = Gtk2::HBox -> new;
		$w{window}{gui}{vbox} -> pack_start( $w{window}{gui}{hbtnbox}, 0, 1, 0 );
		$w{window}{gui}{hbtnbox} -> set_border_width( 5 );
			
			# Put a 'select all' button
			$w{window}{gui}{btnselectall} = Gtk2::Button -> new_from_stock( 'gtk-yes' );
			$w{window}{gui}{btnselectall} -> set_label( 'Select all' );
			$w{window}{gui}{hbtnbox} -> pack_start( $w{window}{gui}{btnselectall}, 0, 1, 0 );
			$w{window}{gui}{btnselectall} -> signal_connect( 'clicked' => sub { foreach my $line ( @{ $w{window}{gui}{treefound}{data} } ) { $$line[0] = 1; }; } );
			
			# Put a 'select all' button
			$w{window}{gui}{btnselectnone} = Gtk2::Button -> new_from_stock( 'gtk-no' );
			$w{window}{gui}{btnselectnone} -> set_label( 'Select none' );
			$w{window}{gui}{hbtnbox} -> pack_start( $w{window}{gui}{btnselectnone}, 0, 1, 0 );
			$w{window}{gui}{btnselectnone} -> signal_connect( 'clicked' => sub { foreach my $line ( @{ $w{window}{gui}{treefound}{data} } ) { $$line[0] = 0; }; } );
			
			# Put a button to execute
			$w{window}{gui}{btnExec} = Gtk2::Button -> new_from_stock( 'gtk-execute' );
			$w{window}{gui}{hbtnbox} -> pack_start( $w{window}{gui}{btnExec}, 1, 1, 0 );
			$w{window}{gui}{btnExec} -> set_label( 'Go _FULL Duplicate' );
			$w{window}{gui}{btnExec} -> signal_connect( 'clicked' => sub {
				my %keys;
				foreach my $line ( @{ $w{window}{gui}{treefound}{data} } ) { next unless $$line[0]; push( @{ $keys{cmd} }, $$line[3] ); }
				$keys{sleep} = $w{window}{gui}{spSleep} -> get_chars( 0, -1 ) // 1/2;
				
				my $new_terminal = $PACMain::FUNCS{_MAIN} -> _launchTerminals( [ [ $$self{_UUID} ] ], \%keys );
				
				$w{window}{data} -> destroy;
				undef %w;
			} );
			
			# Put a 'close' button
			$w{window}{gui}{btnclose} = Gtk2::Button -> new_from_stock( 'gtk-cancel' );
			$w{window}{gui}{hbtnbox} -> pack_start( $w{window}{gui}{btnclose}, 0, 1, 0 );
			$w{window}{gui}{btnclose} -> signal_connect( 'clicked' => sub { $w{window}{data} -> destroy; undef %w; return 1; } );

	$w{window}{data} -> show_all;
	
	return 1;
}

sub _updateCFG {
	my $self = shift;
	
	$$self{_NO_UPDATE_CFG} = 1;
	
	if ( ( $$self{_GUI}{cbShowHist} -> get_active ) && ( $$self{_CFG}{'defaults'}{'record command history'} ) )	{ $$self{_GUI}{hbHist} -> show_all; }
	else																										{ $$self{_GUI}{hbHist} -> hide_all; }
	
	if ( defined $$self{_GUI}{_MACROSBOX} ) {
		$$self{_GUI}{_MACROSBOX} -> hide_all;
		$$self{_GUI}{_MACROSBOX} -> set_sensitive( $$self{CONNECTED} );
	}
	
	# Build ComboBoxes for macros
	if ( $$self{_CFG}{'defaults'}{'show commands box'} == 1 && defined $$self{_GUI}{_MACROSBOX} ) {
		$$self{_GUI}{_MACROSBOX} -> show_all;
		# Empty every 'remote' and 'local' command
		for( my $i = 0; $i < 50; $i++ ) { $$self{_GUI}{_CBMACROSTERMINAL}		-> remove_text( 0 ); }
		for( my $i = 0; $i < 50; $i++ ) { $$self{_GUI}{_CBLOCALEXECTERMINAL}	-> remove_text( 0 ); }
		$$self{_GUI}{_BTNMACROSTERMINALEXEC}	-> set( 'can_focus', 0 );
		$$self{_GUI}{_BTNLOCALTERMINALEXEC}		-> set( 'can_focus', 0 );
		$$self{_GUI}{_BTNMACROSTERMINALEXEC}	-> set_sensitive( $$self{CONNECTED} );
		$$self{_GUI}{_CBMACROSTERMINAL}			-> set_sensitive( $$self{CONNECTED} );
		$$self{_GUI}{_BTNLOCALTERMINALEXEC}		-> set_sensitive( 0 );
		$$self{_GUI}{_CBLOCALEXECTERMINAL}		-> set_sensitive( 0 );
		
		###################################################################
		# Populate the macros (remote executions) combobox
		foreach my $hash ( sort { lc( $$a{description} ) cmp lc( $$b{description} ) } @{ $self -> {_CFG}{'environments'}{ $$self{_UUID} }{'macros'} } ) {
			my $cmd		= $$hash{txt};
			my $desc	= $$hash{description} // '';
			my $confirm	= $$hash{confirm};
			next unless $cmd ne '';
			
			$$self{_GUI}{_BTNMACROSTERMINALEXEC}	-> set_sensitive( 1 );
			$$self{_GUI}{_CBMACROSTERMINAL}			-> set_sensitive( 1 );
			
			$$self{_GUI}{_CBMACROSTERMINAL}			-> append_text( ( $confirm ? 'CONFIRM: ' : '' ) . ( $desc ? $desc : $cmd ) );
			
			$$self{_GUI}{_MACROSCLUSTER}			-> show;
			$$self{_GUI}{_MACROSBOX}				-> show;
			$$self{_GUI}{_BTNMACROSTERMINALEXEC}	-> show_all;
			$$self{_GUI}{_CBMACROSTERMINAL}			-> show_all;
		}
		foreach my $hash ( sort { lc( $$a{description} ) cmp lc( $$b{description} ) } @{ $self -> {_CFG}{'defaults'}{'remote commands'} } ) {
			my $cmd		= ref( $hash ) ? $$hash{txt} : $hash;
			my $desc	= ref( $hash ) ? $$hash{description} : $hash;
			my $confirm	= ref( $hash ) ? $$hash{confirm} : 0;
			next unless $cmd ne '';
			
			$$self{_GUI}{_BTNMACROSTERMINALEXEC}	-> set_sensitive( 1 );
			$$self{_GUI}{_CBMACROSTERMINAL}			-> set_sensitive( 1 );
			
			$$self{_GUI}{_MACROSCLUSTER}			-> show;
			$$self{_GUI}{_CBMACROSTERMINAL}			-> append_text( ( $confirm ? 'CONFIRM: ' : '' ) . ( $desc ? $desc : $cmd ) );
			$$self{_GUI}{_MACROSBOX}				-> show;
			$$self{_GUI}{_BTNMACROSTERMINALEXEC}	-> show_all;
			$$self{_GUI}{_CBMACROSTERMINAL}			-> show_all;
		}
		$$self{_GUI}{_CBMACROSTERMINAL} -> set_active( $$self{_BTNREMOTESEL} // 0 );
		$$self{_GUI}{_BTNMACROSTERMINALEXEC} -> signal_handler_disconnect( $$self{_SIGNALS}{_BTNMACROSTERMINALEXEC} ) if $$self{_SIGNALS}{_BTNMACROSTERMINALEXEC};
		$$self{_SIGNALS}{_BTNMACROSTERMINALEXEC} = $$self{_GUI}{_BTNMACROSTERMINALEXEC}	-> signal_connect( 'clicked' => sub {
			my $active		= $$self{_GUI}{_CBMACROSTERMINAL} -> get_active;
			my $conn_cmds	= scalar( @{ $$self{_CFG}{'environments'}{ $$self{_UUID} }{'macros'} } );
			return 1 if $$self{_GUI}{_CBMACROSTERMINAL} -> get_active == -1;
			$$self{_BTNREMOTESEL} = $active;
			
			my $hash	= $active >= $conn_cmds ?
				$$self{_CFG}{'defaults'}{'remote commands'}[ $active - $conn_cmds ]
				:
				$$self{_CFG}{'environments'}{ $$self{_UUID} }{'macros'}[ $active ];
			my $cmd		= $$hash{txt};
			my $desc	= $$hash{description};
			my $confirm	= $$hash{confirm};
			my $intro	= $$hash{intro};
			
			$self -> _execute( 'remote', $cmd, $confirm, undef, undef, $intro );
			$$self{_GUI}{_MACROSCLUSTER} -> get_active and $self -> _clusterCommit( undef, $cmd . "\n", undef );
			return 1;
		} );
		###################################################################
		
		###################################################################
		# Populate the local executions combobox
		foreach my $hash ( sort { lc( $$a{description} ) cmp lc( $$b{description} ) } @{ $self -> {_CFG}{'environments'}{ $$self{_UUID} }{'local connected'} } ) {
			my $cmd		= $$hash{txt};
			my $desc	= $$hash{description} // '';
			my $confirm	= $$hash{confirm};
			next unless $cmd ne '';
			
			$$self{_GUI}{_BTNLOCALTERMINALEXEC}	-> set_sensitive( 1 );
			$$self{_GUI}{_CBLOCALEXECTERMINAL}	-> set_sensitive( 1 );
			
			$$self{_GUI}{_CBLOCALEXECTERMINAL}	-> append_text( ( $confirm ? 'CONFIRM: ' : '' ) . ( $desc ? $desc : $cmd ) );
			
			$$self{_GUI}{_MACROSBOX}			-> show;
			$$self{_GUI}{_BTNLOCALTERMINALEXEC}	-> show_all;
			$$self{_GUI}{_CBLOCALEXECTERMINAL}	-> show_all;
		}
		foreach my $hash ( sort { lc( $$a{description} ) cmp lc( $$b{description} ) } @{ $self -> {_CFG}{'defaults'}{'local commands'} } ) {
			my $cmd		= ref( $hash ) ? $$hash{txt} : $hash;
			my $desc	= ref( $hash ) ? $$hash{description} : $hash;
			my $confirm	= ref( $hash ) ? $$hash{confirm} : 0;
			next unless $cmd ne '';
			
			$$self{_GUI}{_BTNLOCALTERMINALEXEC}	-> set_sensitive( 1 );
			$$self{_GUI}{_CBLOCALEXECTERMINAL}	-> set_sensitive( 1 );
			
			$$self{_GUI}{_CBLOCALEXECTERMINAL} -> append_text( ( $confirm ? 'CONFIRM: ' : '' ) . ( $desc ? $desc : $cmd ) );
			$$self{_GUI}{_MACROSBOX}			-> show;
			$$self{_GUI}{_BTNLOCALTERMINALEXEC}	-> show_all;
			$$self{_GUI}{_CBLOCALEXECTERMINAL}	-> show_all;
		}
		$$self{_GUI}{_CBLOCALEXECTERMINAL} -> set_active( $$self{_BTNLOCALSEL} // 0 );
		$$self{_GUI}{_BTNLOCALTERMINALEXEC}	-> signal_handler_disconnect( $$self{_SIGNALS}{_BTNLOCALTERMINALEXEC} ) if $$self{_SIGNALS}{_BTNLOCALTERMINALEXEC};
		$$self{_SIGNALS}{_BTNLOCALTERMINALEXEC} = $$self{_GUI}{_BTNLOCALTERMINALEXEC}	-> signal_connect( 'clicked' => sub {
			my $active		= $$self{_GUI}{_CBLOCALEXECTERMINAL} -> get_active;
			my $conn_cmds	= scalar( @{ $$self{_CFG}{'environments'}{ $$self{_UUID} }{'local connected'} } );
			return 1 if $active == -1;
			$$self{_BTNLOCALSEL} = $active;
			
			my $hash	= $active >= $conn_cmds ?
				$$self{_CFG}{'defaults'}{'local commands'}[ $active - $conn_cmds ]
				:
				$$self{_CFG}{'environments'}{ $$self{_UUID} }{'local connected'}[ $active ];
			my $cmd		= $$hash{txt};
			my $desc	= $$hash{description};
			my $confirm	= $$hash{confirm};
			
			$self -> _execute( 'local', $cmd, $confirm );
			return 1;
		} );
		###################################################################
	}
	# Build Buttons for macros
	elsif ( $$self{_CFG}{'defaults'}{'show commands box'} == 2 && defined $$self{_GUI}{_MACROSBOX} )
	{
		$$self{_GUI}{_MACROSBOX} -> set_sensitive( $$self{CONNECTED} );
		$$self{_GUI}{_MACROSBOX} -> foreach( sub { $_[0] -> destroy; } );
		$$self{_GUI}{_MACROSCLUSTER} = Gtk2::CheckButton -> new_with_label( 'Sending THIS: ' );
		$$self{_GUI}{_MACROSCLUSTER} -> set( 'can-focus', 0 );
		$$self{_GUI}{_MACROSCLUSTER} -> signal_connect( 'toggled', sub { $$self{_GUI}{_MACROSCLUSTER} -> set_label( $$self{_GUI}{_MACROSCLUSTER} -> get_active ? 'Sending CLUSTER: ' : 'Sending THIS: ' ); } );
		$$self{_GUI}{_MACROSBOX} -> pack_start( $$self{_GUI}{_MACROSCLUSTER}, 0, 1, 0 );
		
		###################################################################
		# Populate the macros (remote executions) buttons box
		my $i = 0;
		foreach my $hash ( sort { lc( $$a{description} ) cmp lc( $$b{description} ) } @{ $self -> {_CFG}{'environments'}{ $$self{_UUID} }{'macros'} } ) {
			my $cmd		= $$hash{txt};
			my $desc	= $$hash{description} // '';
			my $confirm	= $$hash{confirm};
			my $intro	= $$hash{intro};
			next unless $cmd ne '';
			
			$$self{_GUI}{"_BTNMACRO_$i"} = Gtk2::Button -> new;
			$$self{_GUI}{"_BTNMACRO_$i"} -> set( 'can-focus', 0 );
			$$self{_GUI}{"_BTNMACRO_$i"} -> set_tooltip_text( $cmd );
			my $btn1 = Gtk2::Label -> new( $desc ? $desc : $cmd );
			$btn1 -> set_ellipsize( 'PANGO_ELLIPSIZE_END' );
			$$self{_GUI}{"_BTNMACRO_$i"} -> add( $btn1 );
			$$self{_GUI}{"_BTNMACRO_$i"} -> set_size_request( 60, 20 );
			$$self{_GUI}{_MACROSBOX} -> pack_start( $$self{_GUI}{"_BTNMACRO_$i"}, 1, 1, 0 );
			$$self{_GUI}{_MACROSBOX} -> show_all;
			
			$$self{_GUI}{"_BTNMACRO_$i"} -> signal_connect( 'clicked' => sub {
				$self -> _execute( 'remote', $cmd, $confirm, undef, undef, $intro );
				$$self{_GUI}{_MACROSCLUSTER} -> get_active and $self -> _clusterCommit( undef, $cmd . "\n", undef );
			} );
			
			++$i;
		}
		if ( $$self{_CFG}{'defaults'}{'show global commands box'} ) {
			foreach my $hash ( sort { lc( $$a{description} ) cmp lc( $$b{description} ) } @{ $self -> {_CFG}{'defaults'}{'remote commands'} } ) {
				my $cmd		= ref( $hash ) ? $$hash{txt} : $hash;
				my $desc	= ref( $hash ) ? $$hash{description} : $hash;
				my $confirm	= ref( $hash ) ? $$hash{confirm} : 0;
				my $intro	= ref( $hash ) ? $$hash{intro} : 0;
				next unless $cmd ne '';
				
				$$self{_GUI}{"_BTNMACRO_GLOB_$i"} = Gtk2::Button -> new;
				$$self{_GUI}{"_BTNMACRO_GLOB_$i"} -> set( 'can-focus', 0 );
				$$self{_GUI}{"_BTNMACRO_GLOB_$i"} -> set_tooltip_text( $cmd );
				my $btn2 = Gtk2::Label -> new( $desc ? $desc : $cmd );
				$btn2 -> set_ellipsize( 'PANGO_ELLIPSIZE_END' );
				$$self{_GUI}{"_BTNMACRO_GLOB_$i"} -> add( $btn2 );
				$$self{_GUI}{"_BTNMACRO_GLOB_$i"} -> set_size_request( 60, 20 );
				$$self{_GUI}{_MACROSBOX} -> pack_start( $$self{_GUI}{"_BTNMACRO_GLOB_$i"}, 1, 1, 0 );
				$$self{_GUI}{_MACROSBOX} -> show_all;
				
				$$self{_GUI}{"_BTNMACRO_GLOB_$i"} -> signal_connect( 'clicked' => sub { $self -> _execute( 'remote', $cmd, $confirm, undef, undef, $intro ); } );
				
				++$i;
			}
		}
	}
	
	_setTabColour( $self );
	
	my $colors = [Gtk2::Gdk::Color -> parse( $$self{_CFG}{'defaults'}{'color black'} // '#000000000000' ),		# black
	Gtk2::Gdk::Color -> parse($$self{_CFG}{'defaults'}{'color red'}),				# red
	Gtk2::Gdk::Color -> parse($$self{_CFG}{'defaults'}{'color green'}),				# green
	Gtk2::Gdk::Color -> parse($$self{_CFG}{'defaults'}{'color yellow'}),				# yellow (=brown)
	Gtk2::Gdk::Color -> parse($$self{_CFG}{'defaults'}{'color blue'}),				# blue
	Gtk2::Gdk::Color -> parse($$self{_CFG}{'defaults'}{'color magenta'}),				# magenta
	Gtk2::Gdk::Color -> parse($$self{_CFG}{'defaults'}{'color cyan'}),				# cyan
	Gtk2::Gdk::Color -> parse($$self{_CFG}{'defaults'}{'color white'}),				# white (=light grey)
	Gtk2::Gdk::Color -> parse($$self{_CFG}{'defaults'}{'color bright black'}),			# light black (=dark grey)
	Gtk2::Gdk::Color -> parse($$self{_CFG}{'defaults'}{'color bright red'}),			# light red
	Gtk2::Gdk::Color -> parse($$self{_CFG}{'defaults'}{'color bright green'}),			# light green
	Gtk2::Gdk::Color -> parse($$self{_CFG}{'defaults'}{'color bright yellow'}),			# light yellow
	Gtk2::Gdk::Color -> parse($$self{_CFG}{'defaults'}{'color bright blue'}),			# light blue
	Gtk2::Gdk::Color -> parse($$self{_CFG}{'defaults'}{'color bright magenta'}),			# light magenta
	Gtk2::Gdk::Color -> parse($$self{_CFG}{'defaults'}{'color bright cyan'}),			# light cyan
	Gtk2::Gdk::Color -> parse($$self{_CFG}{'defaults'}{'color bright white'})];			# light white
	# Update some VTE options
	if ( ( $$self{_CFG}{environments}{ $$self{_UUID} }{'terminal options'}{'use personal settings'} ) && ( defined $$self{_GUI}{_VTE} ) ) {
		$$self{_GUI}{_VTE} -> set_background_transparent( $$self{_CFG}{environments}{ $$self{_UUID} }{'terminal options'}{'terminal transparency'} > 0 );
		$$self{_GUI}{_VTE} -> set_background_saturation( $$self{_CFG}{environments}{ $$self{_UUID} }{'terminal options'}{'terminal transparency'} );
		$$self{_GUI}{_VTE} -> set_colors( Gtk2::Gdk::Color -> parse( $$self{_CFG}{environments}{ $$self{_UUID} }{'terminal options'}{'text color'} ), Gtk2::Gdk::Color -> parse( $$self{_CFG}{environments}{ $$self{_UUID} }{'terminal options'}{'back color'} ), $colors);
		$$self{_GUI}{_VTE} -> set_color_foreground( Gtk2::Gdk::Color -> parse( $$self{_CFG}{environments}{ $$self{_UUID} }{'terminal options'}{'text color'} ) );
		$$self{_GUI}{_VTE} -> set_color_background( Gtk2::Gdk::Color -> parse( $$self{_CFG}{environments}{ $$self{_UUID} }{'terminal options'}{'back color'} ) );
		$$self{_GUI}{_VTE} -> set_color_bold( Gtk2::Gdk::Color -> parse( $$self{_CFG}{environments}{ $$self{_UUID} }{'terminal options'}{'bold color like text'} ? $$self{_CFG}{environments}{ $$self{_UUID} }{'terminal options'}{'text color'} : $$self{_CFG}{environments}{ $$self{_UUID} }{'terminal options'}{'bold color'} ) );
		$$self{_GUI}{_VTE} -> set_font_from_string( $$self{_CFG}{environments}{ $$self{_UUID} }{'terminal options'}{'terminal font'} );
		$$self{_GUI}{_VTE} -> set_property( 'cursor-shape', $$self{_CFG}{environments}{ $$self{_UUID} }{'terminal options'}{'cursor shape'} );
		$$self{_GUI}{_VTE} -> set_encoding( $$self{_CFG}{environments}{ $$self{_UUID} }{'terminal options'}{'terminal character encoding'} // 'UTF-8' );
		$$self{_GUI}{_VTE} -> set_backspace_binding( $$self{_CFG}{environments}{ $$self{_UUID} }{'terminal options'}{'terminal backspace'} );
		$$self{_GUI}{_VTE} -> set_emulation( $$self{_CFG}{environments}{ $$self{_UUID} }{'terminal options'}{'terminal emulation'} );
		$$self{_GUI}{_VTE} -> set_word_chars( $$self{_CFG}{environments}{ $$self{_UUID} }{'terminal options'}{'terminal select words'} );
		$$self{_GUI}{_VTE} -> set_audible_bell( $$self{_CFG}{environments}{ $$self{_UUID} }{'terminal options'}{'audible bell'} );
		$$self{_GUI}{_VTE} -> set_visible_bell( $$self{_CFG}{environments}{ $$self{_UUID} }{'terminal options'}{'visible bell'} );
	} elsif ( defined $$self{_GUI}{_VTE} ) {
		$$self{_GUI}{_VTE} -> set_background_transparent( $$self{_CFG}{'defaults'}{'terminal transparency'} > 0 );
		$$self{_GUI}{_VTE} -> set_background_saturation( $$self{_CFG}{'defaults'}{'terminal transparency'} );
		$$self{_GUI}{_VTE} -> set_colors( Gtk2::Gdk::Color -> parse( $$self{_CFG}{environments}{ $$self{_UUID} }{'terminal options'}{'text color'} ), Gtk2::Gdk::Color -> parse( $$self{_CFG}{environments}{ $$self{_UUID} }{'terminal options'}{'back color'} ), $colors);
		$$self{_GUI}{_VTE} -> set_color_foreground( Gtk2::Gdk::Color -> parse( $$self{_CFG}{'defaults'}{'text color'} ) );
		$$self{_GUI}{_VTE} -> set_color_background( Gtk2::Gdk::Color -> parse( $$self{_CFG}{'defaults'}{'back color'} ) );
		$$self{_GUI}{_VTE} -> set_color_bold( Gtk2::Gdk::Color -> parse( $$self{_CFG}{'defaults'}{'bold color like text'} ? $$self{_CFG}{'defaults'}{'text color'} : $$self{_CFG}{'defaults'}{'bold color'} ) );
		$$self{_GUI}{_VTE} -> set_font_from_string( $$self{_CFG}{'defaults'}{'terminal font'} );
		$$self{_GUI}{_VTE} -> set_property( 'cursor-shape', $$self{_CFG}{'defaults'}{'cursor shape'} );
		$$self{_GUI}{_VTE} -> set_encoding( $$self{_CFG}{'defaults'}{'terminal character encoding'} // 'UTF-8' );
		$$self{_GUI}{_VTE} -> set_backspace_binding( $$self{_CFG}{'defaults'}{'terminal backspace'} );
		$$self{_GUI}{_VTE} -> set_emulation( $$self{_CFG}{'defaults'}{'terminal emulation'} );
		$$self{_GUI}{_VTE} -> set_word_chars( $$self{_CFG}{'defaults'}{'word characters'} );
		$$self{_GUI}{_VTE} -> set_audible_bell( $$self{_CFG}{'defaults'}{'audible bell'} );
		$$self{_GUI}{_VTE} -> set_visible_bell( $$self{_CFG}{'defaults'}{'visible bell'} );
	}
	
	$$self{FOCUS} -> child_focus( 'GTK_DIR_TAB_FORWARD' ) if $$self{_FOCUSED};
	$$self{_NO_UPDATE_CFG} = 0;
	
	return 1;
}

sub _wFindInTerminal {
	my $self = shift;
	
	our $searching = 0;
	our $stop = 0;
	our %w;
	
	if ( defined $w{window} ) {
		# Load the contents of the textbuffer with the corresponding log file
		open( F, $$self{_LOGFILE} ) or die( "ERROR: Could not open file '$$self{_LOGFILE}': $!" );
		@{ $$self{_TEXT} } = <F>;
		my $text = join( '', @{ $$self{_TEXT} } );
		$text =~ s/\x1b\[\d*;?\d*m//go; # Delete the Escape sequences
		$text =~ s/\cM//go; # Delete any Ctrl-M ( ^M ) character
		close F;
		$w{window}{buffer} -> set_text( encode( 'iso-8859-1', $text ) );
		
		return $w{window}{data} -> present;
	}
	
	# Create the 'windowFind' dialog window,
	$w{window}{data} = Gtk2::Window -> new;
	
	$w{window}{data} -> signal_connect( 'delete_event' => sub {
		$searching = 0;
		$stop = 0;
		$w{window}{data} -> destroy;
		undef %w;
		return 1;
	} );
	
	$w{window}{data} -> signal_connect( 'key_press_event' => sub {
		my ( $widget, $event ) = @_; 
		my $keyval	= '' . ( $event -> keyval );
		return 0 unless $keyval == 65307;
		$w{window}{gui}{btnclose} -> activate();
		return 1;
	} );	
	
	# and setup some dialog properties.
	$w{window}{data} -> set_title( $$self{_TITLE} . " : $APPNAME : Find in Terminal" );
	$w{window}{data} -> set_position( 'center' );
	$w{window}{data} -> set_icon_from_file( $APPICON );
	$w{window}{data} -> set_default_size( 600, 400 );
	$w{window}{data} -> maximize;
	$w{window}{data} -> set_resizable( 1 );
		
		# Create an hbox
		$w{window}{gui}{hboxmain} = Gtk2::HPaned -> new;
		$w{window}{data} -> add( $w{window}{gui}{hboxmain} );
			
			# Create a vbox
			$w{window}{gui}{vbox} = Gtk2::VBox -> new( 0, 0 );
			$w{window}{gui}{vbox} -> set_size_request( 300, 200 );
			$w{window}{gui}{hboxmain} -> pack1( $w{window}{gui}{vbox}, 1, 0 );
				
				# Create frame 1
				$w{window}{gui}{frame1} = Gtk2::Frame -> new;
				$w{window}{gui}{vbox} -> pack_start( $w{window}{gui}{frame1}, 0, 1, 0 );
				$w{window}{gui}{frame1} -> set_label( ' Enter Regular Expression to look for: ' );
				$w{window}{gui}{frame1} -> set_border_width( 5 );
					
					$w{window}{gui}{hbox} = Gtk2::HBox -> new( 0, 0 );
					$w{window}{gui}{frame1} -> add( $w{window}{gui}{hbox} );
					$w{window}{gui}{hbox} -> set_border_width( 5 );
						
						# Create 'find' image
						$w{window}{gui}{img} = Gtk2::Image -> new_from_stock( 'gtk-find', 'dialog' );
						$w{window}{gui}{hbox} -> pack_start( $w{window}{gui}{img}, 0, 1, 5 );
						
						# Create search entry
						$w{window}{gui}{entry} = Gtk2::Entry -> new;
						$w{window}{gui}{hbox} -> pack_start( $w{window}{gui}{entry}, 1, 1, 0 );
						$w{window}{gui}{entry} -> set_activates_default( 1 );
						$w{window}{gui}{entry} -> has_focus( 1 );
						
						# Create 'case sensitive search' checkbutton
						$w{window}{gui}{cbCaseSensitive} = Gtk2::CheckButton -> new_with_label( 'Case sensitive' );
						$w{window}{gui}{hbox} -> pack_start( $w{window}{gui}{cbCaseSensitive}, 0, 1, 0 );
						$w{window}{gui}{cbCaseSensitive} -> set_active( 0 );
						
						# Create "Search" button
						$w{window}{gui}{btnfind} = Gtk2::Button -> new_from_stock( 'gtk-find' );
						$w{window}{gui}{hbox} -> pack_start( $w{window}{gui}{btnfind}, 0, 1, 0 );
						$w{window}{gui}{btnfind} -> signal_connect( 'clicked' => sub {
							if ( ! $searching ) {
								$searching = 1;
								$self -> _find;
								$searching = 0;
							} else {
								$stop = 1;
							}
						} );
						$w{window}{gui}{btnfind} -> can_default( 1 );
						$w{window}{gui}{btnfind} -> grab_default;
				
				# Create frame 2
				$w{window}{gui}{frame2} = Gtk2::Frame -> new;
				$w{window}{gui}{vbox} -> pack_start( $w{window}{gui}{frame2}, 1, 1, 0 );
				$w{window}{gui}{frame2} -> set_label( ' Lines matching string: ' );
				$w{window}{gui}{frame2} -> set_border_width( 5 );
					
					# Create a GtkScrolledWindow,
					my $sctxt = Gtk2::ScrolledWindow -> new;
					$w{window}{gui}{frame2} -> add( $sctxt );
					$sctxt -> set_shadow_type( 'none' );
					$sctxt -> set_policy( 'automatic', 'automatic' );
					$sctxt -> set_border_width( 5 );
					
					# Create treefound
					$w{window}{gui}{treefound} = Gtk2::Ex::Simple::List -> new_from_treeview (
						Gtk2::TreeView -> new,
						' Line # '			=> 'text',
						' Line contents '	=> 'text'
					);
					$w{window}{gui}{treefound} -> set_headers_visible( 1 );
					$w{window}{gui}{treefound} -> set_grid_lines( 'both' );
					$w{window}{gui}{treefound} -> get_selection -> set_mode( 'multiple' );
					
					$w{window}{gui}{treefound} -> signal_connect( 'row_activated' => sub {
						my @index = $w{window}{gui}{treefound} -> get_selected_indices;
						return unless scalar( @index ) == 1;
						my $id = pop( @index );
						$self -> _showLine( $w{window}{gui}{treefound}{data}[$id][0] );
						return 1;
					} );
					
					# Put treefound into scrolledwindow
					$sctxt -> add( $w{window}{gui}{treefound} );
				
				# Put a separator
				$w{window}{gui}{sep} = Gtk2::HSeparator -> new;
				$w{window}{gui}{vbox} -> pack_start( $w{window}{gui}{sep}, 0, 1, 5 );
				
				# Put a hbox to add copy/close buttons
				$w{window}{gui}{hbtnbox} = Gtk2::HBox -> new;
				$w{window}{gui}{vbox} -> pack_start( $w{window}{gui}{hbtnbox}, 0, 1, 0 );
				$w{window}{gui}{hbtnbox} -> set_border_width( 5 );
					
					# Put a button to copy selected rows to clipboard
					$w{window}{gui}{btnCopy} = Gtk2::Button -> new_from_stock( 'gtk-copy' );
					$w{window}{gui}{hbtnbox} -> pack_start( $w{window}{gui}{btnCopy}, 1, 1, 0 );
					$w{window}{gui}{btnCopy} -> signal_connect( 'clicked' => sub {
						$$self{_GUI}{_VTE} -> get_clipboard( Gtk2::Gdk-> SELECTION_CLIPBOARD ) -> set_text (
							join(
								"\n",
								map $w{window}{gui}{treefound}{data}[$_][1],
									$w{window}{gui}{treefound} -> get_selected_indices
							)
						),
					} );
					
					# Put a 'close' button
					$w{window}{gui}{btnclose} = Gtk2::Button -> new_from_stock( 'gtk-close' );
					$w{window}{gui}{hbtnbox} -> pack_start( $w{window}{gui}{btnclose}, 0, 1, 0 );
					$w{window}{gui}{btnclose} -> signal_connect( 'clicked' => sub { $w{window}{data} -> destroy; undef %w; return 1; } );
			
			# Create frame 3
			$w{window}{gui}{frame3} = Gtk2::Frame -> new;
			$w{window}{gui}{frame3} -> set_size_request( 200, 200 );
			$w{window}{gui}{hboxmain} -> pack2( $w{window}{gui}{frame3}, 1, 0 );
			$w{window}{gui}{frame3} -> set_label( ' Contents of current log: ' );
			$w{window}{gui}{frame3} -> set_border_width( 5 );
				
				$w{window}{gui}{scroll} = Gtk2::ScrolledWindow -> new;
				$w{window}{gui}{frame3} -> add( $w{window}{gui}{scroll} );
				$w{window}{gui}{scroll} -> set_policy( 'automatic', 'automatic' );
				$w{window}{gui}{scroll} -> set_border_width( 5 );
					
					if ( $SOURCEVIEW ) {
						$w{window}{buffer} = Gtk2::SourceView2::Buffer -> new( undef );
						$w{window}{gui}{text} = Gtk2::SourceView2::View -> new_with_buffer( $w{window}{buffer} );
						$w{window}{gui}{text} ->set_show_line_numbers( 1 );
						$w{window}{gui}{text} ->set_highlight_current_line( 1 );
					} else {
						$w{window}{buffer} = Gtk2::TextBuffer -> new;
						$w{window}{gui}{text} = Gtk2::TextView -> new_with_buffer( $w{window}{buffer} );
					}
					
					$w{window}{gui}{text} -> set_editable( 0 );
					$w{window}{gui}{text} -> modify_font( Pango::FontDescription -> from_string( 'monospace' ) );
					$w{window}{gui}{scroll} -> add( $w{window}{gui}{text} );

	$w{window}{data} -> show_all;
	$w{window}{gui}{hboxmain} -> set_position( ( $w{window}{data} -> get_size ) / 2 );
	
	# Load the contents of the textbuffer with the corresponding log file
	open( F, $$self{_LOGFILE} ) or die( "ERROR: Could not open file '$$self{_LOGFILE}': $!" );
	@{ $$self{_TEXT} } = <F>;
	my $text = join( '', @{ $$self{_TEXT} } );
	$text =~ s/\x1b\[\d*;?\d*m//go; # Delete the Escape sequences
	$text =~ s/\cM//go; # Delete any Ctrl-M ( ^M ) character
	close F;
	$w{window}{buffer} -> set_text( encode( 'iso-8859-1', $text ) );
	
	sub _showLine {
		my $self	= shift;
		my $line	= shift;
		
		--$line;
		
		my $siter = $w{window}{buffer} -> get_iter_at_line( $line );
		my $eiter = $w{window}{buffer} -> get_iter_at_line( $line );
		$eiter -> forward_to_line_end;
		$w{window}{buffer} -> select_range( $siter, $eiter );
		$w{window}{gui}{text} -> scroll_to_iter( $siter, 0, 1, 0, 0.5 );
		
		return 1;
	}
	
	sub _find {
		my $self = shift;
		
		my $val = $w{window}{gui}{entry} -> get_chars( 0, -1 );
		
		$w{window}{gui}{vbox}		-> window -> set_cursor( Gtk2::Gdk::Cursor -> new( 'watch' ) );
		$w{window}{gui}{hbtnbox}	-> set_sensitive( 0 );
		$w{window}{gui}{frame2}		-> set_label( ' PLEASE, WAIT. SEARCHING... ' );
		$w{window}{gui}{btnfind}	-> set_label( 'STOP SEARCH' );
		$w{window}{gui}{btnfind}	-> set_image( Gtk2::Image -> new_from_stock( 'gtk-close', 'GTK_ICON_SIZE_BUTTON' ) );
		
		# Empty previous found lines
		@{ $w{window}{gui}{'treefound'}{data} } = ();
		
		Gtk2 -> main_iteration while Gtk2 -> events_pending;
		
		my %found;
		my $i = 0;
		my $l = 0;
		my $regexp = $w{window}{gui}{cbCaseSensitive} -> get_active ? qr/$val/m : qr/$val/im;
		foreach my $line ( @{ $$self{_TEXT} } ) {
			++$l;
			last if $stop;
			if ( ++$i >= 1000 ) {
				$i = 0;
				$w{window}{gui}{frame2} -> set_label( ' PLEASE, WAIT. Searching... (' . scalar( keys %found ) . " lines matching '$val' so far in $l processed lines) " );
				Gtk2 -> main_iteration;
			}
			chomp $line;
			next unless $line =~ /$regexp/g;
			$found{$l} = $line;
			$found{$l} =~ s/\x1b\[\d*;?\d*m//go; # Delete the Escape sequences
			$found{$l} =~ s/\n|\r|\f|\cM//go; # Delete the ctrl-M, new-line and similar sequences
		}
		
		if ( $stop ) {
			# Update label text to announce that search was stopped
			$w{window}{gui}{frame2} -> set_label( ' SEARCH WAS STOPPED WITH ' . scalar( keys %found ) . " LINES MATCHING '$val' SO FAR!! " );
			Gtk2 -> main_iteration;
			$stop = 0;
		} else {
			# Update label text with number of matches found
			$w{window}{gui}{frame2} -> set_label( ' PLEASE, WAIT. Updating... (' . scalar( keys %found ) . " lines matching '$val') " );
			Gtk2 -> main_iteration while Gtk2 -> events_pending;
			# Update tree with the list of found lines
			foreach my $line_num ( sort { $a <=> $b } keys %found ) { push( @{ $w{window}{gui}{treefound}{data} }, [ $line_num, $found{$line_num} ] ); }
		}
		
		$w{window}{gui}{vbox}		-> window -> set_cursor( Gtk2::Gdk::Cursor -> new( 'left-ptr' ) );
		$w{window}{gui}{hbtnbox}	-> set_sensitive( 1 );
		$w{window}{gui}{frame2}		-> set_label( ' ' . scalar( keys %found ) . " lines matching '$val': " );
		$w{window}{gui}{btnfind}	-> set_label( 'Find' );
		$w{window}{gui}{btnfind}	-> set_image( Gtk2::Image -> new_from_stock( 'gtk-find', 'GTK_ICON_SIZE_BUTTON' ) );
		
		$w{window}{gui}{entry} -> has_focus( 1 );
		$w{window}{gui}{entry} -> grab_focus;
		
		return 1;
	}
	
	return 1;
}

sub _wHistory {
	my $self	= shift;
	
	our %w;
	
	defined $w{window} and return $w{window}{data} -> present;
	
	# Create the 'windowFind' dialog window,
	$w{window}{data} = Gtk2::Window -> new;
	
	$w{window}{data} -> signal_connect( 'delete_event' => sub {
		$w{window}{data} -> destroy;
		undef %w;
		return 1;
	} );
	
	$w{window}{data} -> signal_connect( 'key_press_event' => sub {
		my ( $widget, $event ) = @_; 
		my $keyval	= '' . ( $event -> keyval );
		return 0 unless $keyval == 65307;
		$w{window}{gui}{btnclose} -> activate();
		return 1;
	} );	
	
	# and setup some dialog properties.
	$w{window}{data} -> set_title( $self -> {_TITLE} . " : $APPNAME : Command History" );
	$w{window}{data} -> set_position( 'center' );
	$w{window}{data} -> set_icon_from_file( $APPICON );
	$w{window}{data} -> set_default_size( 600, 480 );
	$w{window}{data} -> set_resizable( 1 );
	$w{window}{data} -> set_modal( 1 );
	$w{window}{data} -> set_transient_for( $PACMain::FUNCS{_MAIN}{_GUI}{main} );
		
		# Create a vbox
		$w{window}{gui}{vbox} = Gtk2::VBox -> new( 0, 0 );
		$w{window}{data} -> add( $w{window}{gui}{vbox} );
			
			# Create frame 1
			$w{window}{gui}{frame1} = Gtk2::Frame -> new;
			$w{window}{gui}{vbox} -> pack_start( $w{window}{gui}{frame1}, 1, 1, 0 );
			$w{window}{gui}{frame1} -> set_label( ' Command History: ' );
			$w{window}{gui}{frame1} -> set_border_width( 5 );
				
				# Create a GtkScrolledWindow,
				my $sctxt = Gtk2::ScrolledWindow -> new;
				$w{window}{gui}{frame1} -> add( $sctxt );
				$sctxt -> set_shadow_type( 'none' );
				$sctxt -> set_policy( 'automatic', 'automatic' );
				$sctxt -> set_border_width( 5 );
				
				# Create treefound
				$w{window}{gui}{treefound} = Gtk2::Ex::Simple::List -> new_from_treeview (
					Gtk2::TreeView -> new(),
					' Execution time '	=> 'text',
					' Command '			=> 'text',
					'cmd'				=> 'hidden'
				);
				$w{window}{gui}{treefound} -> set_headers_visible( 1 );
				$w{window}{gui}{treefound} -> set_grid_lines( 'both' );
				$w{window}{gui}{treefound} -> get_selection -> set_mode( 'single' );
				foreach my $array ( @{ $$self{_GUI}{treeKeys}{data} } ) {
					my $cmd = $$array[0];
					my $cmdt = $$array[1];
					my $pretty_cmd = _replaceBadChars( $cmd );
					
					push( @{ $w{window}{gui}{treefound}{data} },
					[
						strftime( "%Y-%m-%d %H:%M:%S", localtime( $cmdt ) ),
						$pretty_cmd,
						$cmd
					] );
				}
				
				$w{window}{gui}{treefound} -> signal_connect( 'row_activated' => sub { $w{window}{gui}{btnExec} -> clicked } );
				
				# Put treefound into scrolledwindow
				$sctxt -> add( $w{window}{gui}{treefound} );
				
		# Put a separator
		$w{window}{gui}{sep} = Gtk2::HSeparator -> new;
		$w{window}{gui}{vbox} -> pack_start( $w{window}{gui}{sep}, 0, 1, 5 );
		
		# Put a hbox to add exec/close buttons
		$w{window}{gui}{hbtnbox} = Gtk2::HBox -> new;
		$w{window}{gui}{vbox} -> pack_start( $w{window}{gui}{hbtnbox}, 0, 1, 0 );
		$w{window}{gui}{hbtnbox} -> set_border_width( 5 );
			
			# Put a button to execute selected row
			$w{window}{gui}{btnExec} = Gtk2::Button -> new_from_stock( 'gtk-execute' );
			$w{window}{gui}{hbtnbox} -> pack_start( $w{window}{gui}{btnExec}, 1, 1, 0 );
			$w{window}{gui}{btnExec} -> signal_connect( 'clicked' => sub {
				my ( $selected ) = $w{window}{gui}{treefound} -> get_selected_indices;
				return 1 unless ( defined $selected && $$self{CONNECTED} );
				my $cmd = $w{window}{gui}{treefound}{data}[$selected][2];
				
				$$self{_SAVE_KEYS} = 0;
				foreach my $cmd ( map $w{window}{gui}{treefound}{data}[$_][2], $w{window}{gui}{treefound} -> get_selected_indices ) { $self -> _execute( 'remote', $cmd, 0 ); }
				$$self{_SAVE_KEYS} = 1;
			} );
			
			# Put a button to copy selected rows to clipboard
			$w{window}{gui}{btnCopy} = Gtk2::Button -> new_from_stock( 'gtk-copy' );
			$w{window}{gui}{hbtnbox} -> pack_start( $w{window}{gui}{btnCopy}, 1, 1, 0 );
			$w{window}{gui}{btnCopy} -> signal_connect( 'clicked' => sub {
				$$self{_GUI}{_VTE} -> get_clipboard( Gtk2::Gdk-> SELECTION_CLIPBOARD ) -> set_text (
					join( "\n", map $w{window}{gui}{treefound}{data}[$_][2], $w{window}{gui}{treefound} -> get_selected_indices )
				);
			} );
			
			# Put a button to empty the history
			$w{window}{gui}{btnEmpty} = Gtk2::Button -> new( 'Forget history' );
			$w{window}{gui}{hbtnbox} -> pack_start( $w{window}{gui}{btnEmpty}, 1, 1, 0 );
			$w{window}{gui}{btnEmpty} -> set_image( Gtk2::Image -> new_from_stock( 'gtk-delete', 'button' ) );
			$w{window}{gui}{btnEmpty} -> signal_connect( 'clicked' => sub {
				return 1 unless _wConfirm( $$self{GUI}{_VBOX}, "Are you sure you want to <b>DELETE ALL</b> commands history?" );
				@{ $w{window}{gui}{treefound}{data} } = ();
				@{ $$self{_GUI}{treeKeys}{data} } = ();
			} );
			
			# Put a 'close' button
			$w{window}{gui}{btnclose} = Gtk2::Button -> new_from_stock( 'gtk-close' );
			$w{window}{gui}{hbtnbox} -> pack_start( $w{window}{gui}{btnclose}, 0, 1, 0 );
			$w{window}{gui}{btnclose} -> signal_connect( 'clicked' => sub { $w{window}{data} -> destroy; undef %w; return 1; } );

	$w{window}{data} -> show_all;
	
	return 1;
}

sub _checkSendKeystrokes {
	my $self = shift;
	my $data = shift // '';
	
	if ( ! defined $$self{_KEYS_RECEIVE}{cmd} ) {
		delete $$self{_KEYS_RECEIVE};
		return $data;
	}
	
	my $prev_data = $data;
	$data = "CONNECTED: Sending keystrokes for FULL Duplication ($$self{_KEYS_RECEIVE}{sleep} seconds interval)...";
	
	my $keys		= $$self{_KEYS_RECEIVE};
	my $accum		= 0;
	my $i			= 0;
	$$self{_PULSE}	= 0;
	
	if ( ! defined $$self{_GUI}{pb} ) {
		$$self{_GUI}{pb} = Gtk2::ProgressBar -> new;
		$$self{_GUI}{bottombox} -> pack_start( $$self{_GUI}{pb}, 0, 1, 0 );
		$$self{_GUI}{pb} -> show;
	}
	
	foreach my $cmd ( @{ $$keys{cmd} } ) {
		my $j = $i++;
		Glib::Timeout -> add_seconds( $accum += ( $$keys{sleep} ), sub {
			return 0 unless defined $$self{_GUI}{pb};
			
			$$self{_GUI}{pb} -> set_fraction( $j / ( $#{ $$keys{cmd} } || $#{ $$keys{cmd} } + 1 ) );
			$$self{_GUI}{_VTE} -> feed_child( $cmd . "\n" );
			return 0 unless $j >= $#{ $$keys{cmd} }; # Continue, unless finish reached
			
			$$self{_GUI}{pb} -> destroy;
			$$self{_GUI}{pb} = undef;
			delete $$self{_KEYS_RECEIVE};
			$data = $prev_data;
			$$self{_LAST_STATUS} = $data;
			$self -> _updateCFG;
			$self -> _updateStatus;
			
			return 0; # Finish
		} );
	}
	
	return $data;
}

sub _disconnectAndRestartTerminal {
	my $self = shift;

	kill( 15, $$self{_PID} ) and Glib::Timeout -> add_seconds( 1, sub { $self -> start; return 0; } )
}

sub _closeAllTerminals {
	my $self = shift;
	my @list = keys %PACMain::RUNNING;

	return 1 unless scalar( @list ) && _wConfirm( $$self{GUI}{_VBOX}, "Are you sure you want to close <b>all</b> terminals?" );
	foreach my $uuid ( @list ) { $PACMain::RUNNING{$uuid}{'terminal'} -> stop( 'force', 'deep' ); }
	return 1;
}

sub _hasOtherTerminals {
	my $self = shift;
	my $list_count = keys %PACMain::RUNNING;

	return $list_count > 1;
}

sub _closeDisconnectedTerminals {
	my $self = shift;
	my @list = keys %PACMain::RUNNING;

	foreach my $uuid ( @list ) {
		if ($PACMain::RUNNING{$uuid}{'terminal'}{_LAST_STATUS} eq 'DISCONNECTED') {
			$PACMain::RUNNING{$uuid}{'terminal'} -> stop( 'force', 'deep' );
		}
	}
	return 1;
}

sub _hasDisconnectedTerminals {
	my $self = shift;
	my @list = keys %PACMain::RUNNING;

	foreach my $uuid ( @list ) {
		if ($PACMain::RUNNING{$uuid}{'terminal'}{_LAST_STATUS} eq 'DISCONNECTED') {
			return 1;
		}
	}
	return 0;
}

# END: Private functions definitions
###################################################################

1;
