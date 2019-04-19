package PACKeePass;

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

$|++;

###################################################################
# Import Modules

# Standard
use strict;
use warnings;

use Encode;
use KeePass;
use FindBin qw ( $RealBin $Bin $Script );

# GTK2
use Gtk2 '-init';

# PAC modules
use PACUtils;

# END: Import Modules
###################################################################

###################################################################
# Define GLOBAL CLASS variables



# END: Define GLOBAL CLASS variables
###################################################################

###################################################################
# START: Public class methods

sub new {
	my $class	= shift;
	my $self	= {};
	
	$self -> {cfg}			= shift;
	
	$self -> {container}	= undef;
	$self -> {frame}		= {};
	
	$self -> {entries}		= [];
	
	_buildKeePassGUI( $self );
	
	bless( $self, $class );
	return $self;
}

sub update {
	my $self	= shift;
	my $cfg		= shift;
	
	# Destroy previous widgets
	$$self{frame}{vbKeePass} -> foreach( sub { $_[0] -> destroy; } );
	
	defined $cfg and $$self{cfg} = $cfg;
	
	my $file = $$self{cfg}{'database'};
	defined $file or return 0;
	$$self{frame}{fcbKeePassFile} -> set_filename( $file );
	
	$$self{frame}{hboxkpmain} -> set_sensitive( $$self{cfg}{use_keepass} );
	return 1 unless $$self{cfg}{use_keepass};
	
	if ( ( $$self{cfg}{password} eq '' ) && ( -f $$cfg{'database'} ) ) {
		my $pass = _wEnterValue( $self, 'KeePassX Integration', "Please, enter KeePassX MASTER password\nto unlock database file '$$self{cfg}{'database'}'", '', 0, 'pac-keepass' );
		if ( ( $pass // '' ) eq '' ) { $$self{frame}{cbUseKeePass} -> set_active( 0 ); return 0; }
		$$self{cfg}{password} = $pass;
	}
	
	my $pass = $$self{cfg}{'password'};
	
	$$self{frame}{entryKeePassPassword}	-> set_text( encode( 'unicode', $pass ) );
	$$self{frame}{cbUseKeePass}			-> set_active( $$self{cfg}{use_keepass} );
	$$self{frame}{cbKeePassAskUser}		-> set_active( $$self{cfg}{ask_user} );
	$$self{frame}{hboxkpmain}			-> set_sensitive( $$self{cfg}{use_keepass} );
	
	return 0 unless $pass ne '';
	
	# Reload DDBB if no entries are found
	$self -> reload;
	
	# Now, add the -new?- widgets
	foreach my $hash ( @{ $$self{entries} } ) { $self -> _buildVar( $$hash{title}, $$hash{url}, $$hash{username}, $$hash{password} ); }
	
	return 1;
}

sub get_cfg {
	my $self = shift;
	
	my %hash;
	$hash{use_keepass}	= $$self{frame}{'cbUseKeePass'}			-> get_active;
	$hash{ask_user}		= $$self{frame}{'cbKeePassAskUser'}		-> get_active;
	$hash{database}		= $$self{frame}{'fcbKeePassFile'}		-> get_filename;
	$hash{password}		= ( $$self{frame}{'cbUseKeePass'}		-> get_active ) ? $$self{frame}{'entryKeePassPassword'} -> get_chars( 0, -1 ) : '';
	
	return \%hash;
}

sub reload {
	my $self	= shift;
	my $force	= shift // 0;
	my $cfg		= shift // $$self{cfg};
	
	return 1 unless $force || ! scalar( @{ $$self{entries} } );
	$$self{entries} = [];
	
	my $KEEPASS = KeePass -> new;
	eval { $KEEPASS -> load_db( $$cfg{'database'}, $$cfg{'password'} ) };
	if ( $@ ) {
		_wMessage( undef, "ERROR: Could not open '$$cfg{database}' for reading as KeePass Database file:\n$@" );
		return wantarray ? undef : 0;
	}
	$KEEPASS -> unlock;
	
	foreach my $hash ( $KEEPASS -> find_entries( { 'title =~' => qr/.*/ } ) ) {
		next if ( exists $$hash{'binary'}{'bin-stream'} && $$hash{'comment'} eq 'KPX_CUSTOM_ICONS_4' );
		Encode::_utf8_on( $$hash{title} );
		Encode::_utf8_on( $$hash{url} );
		Encode::_utf8_on( $$hash{username} );
		Encode::_utf8_on( $$hash{password} );
		Encode::_utf8_on( $$hash{created} );
		Encode::_utf8_on( $$hash{comment} );
		push( @{ $$self{entries} }, {
			title		=> $$hash{title},
			url			=> $$hash{url},
			username	=> $$hash{username},
			password	=> $$hash{password},
			created		=> $$hash{created},
			comment		=> $$hash{comment}
		} );
	}
	undef $KEEPASS;
	
	return 1;
}

sub find {
	my $self	= shift;
	my $where	= shift // 'title';
	my $what	= shift // qr/.*/;
	
	my @kpx = _findKP( $$self{entries}, $where, $what );
	
	return wantarray ? @kpx : scalar( @kpx );
}

# END: Public class methods
###################################################################

###################################################################
# START: Private functions definitions

sub _buildKeePassGUI {
	my $self	= shift;
	
	my $cfg		= $self -> {cfg};
	
	my %w;
	
	# Build a vbox
	$w{vbox} = Gtk2::VBox -> new( 0, 0 );
		
		$w{cbUseKeePass} = Gtk2::CheckButton -> new( 'Use KeePassX' );
		$w{vbox} -> pack_start( $w{cbUseKeePass}, 0, 1, 0 );
		
		$w{cbKeePassAskUser} = Gtk2::CheckButton -> new( 'Ask user when multiple matches are found' );
		$w{vbox} -> pack_start( $w{cbKeePassAskUser}, 0, 1, 0 );
		
		$w{hboxkpmain} = Gtk2::HBox -> new( 0, 0 );
		$w{vbox} -> pack_start( $w{hboxkpmain}, 0, 1, 0 );
			
			$w{hboxkpmain} -> pack_start( Gtk2::Label -> new( 'KeePass Database file:' ), 0, 1, 0 );
			
			$w{fcbKeePassFile} = Gtk2::FileChooserButton -> new( '', 'GTK_FILE_CHOOSER_ACTION_OPEN' );
			$w{fcbKeePassFile} -> set_show_hidden( 1 );
			$w{hboxkpmain} -> pack_start( $w{fcbKeePassFile}, 1, 1, 0 );
			
			$w{hboxkpmain} -> pack_start( Gtk2::Label -> new( ' Master Password:' ), 0, 1, 0 );
			
			$w{entryKeePassPassword} = Gtk2::Entry -> new;
			$w{hboxkpmain} -> pack_start( $w{entryKeePassPassword}, 0, 1, 0 );
			$w{entryKeePassPassword} -> set_visibility( 0 );
	
		$w{frameKPList} = Gtk2::Frame -> new( ' Available passwords in given Database file: ' );
		$w{vbox} -> pack_start( $w{frameKPList}, 1, 1, 0 );
			
			$w{vbkpin} = Gtk2::VBox -> new( 0, 0 );
			$w{frameKPList} -> add( $w{vbkpin} );
			
				$w{btnPassRefresh} = Gtk2::Button -> new_from_stock( 'gtk-refresh' );
				$w{vbkpin} -> pack_start( $w{btnPassRefresh}, 0, 1, 0 );
				
				$w{scKeePass} = Gtk2::ScrolledWindow -> new;
				$w{scKeePass} -> set_policy( 'automatic', 'automatic' );
				$w{vbkpin} -> add( $w{scKeePass} );
					
					$w{vbKeePass} = Gtk2::VBox -> new( 0, 0 );
					$w{scKeePass} -> add_with_viewport( $w{vbKeePass} );
				
	$$self{container} = $w{vbox};
	$$self{frame} = \%w;
	
	$w{entryKeePassPassword} -> signal_connect( 'activate', sub { $w{btnPassRefresh} -> clicked; } );
	
	$w{cbUseKeePass} -> signal_connect( 'toggled', sub { $w{hboxkpmain} -> set_sensitive( $w{cbUseKeePass} -> get_active ) } );
	
	$w{btnPassRefresh} -> signal_connect( 'clicked', sub {
		return 1 unless $w{cbUseKeePass} -> get_active;
		$w{btnPassRefresh} -> set_sensitive( 0 );
		my $hash = $self -> get_cfg;
		$self -> reload( 'force', $hash ) and $self -> update( $hash );
		$w{btnPassRefresh} -> set_sensitive( 1 );
	} );
	
	return 1;
}

sub _buildVar {
	my $self	= shift;
	my $title	= shift;
	my $url		= shift;
	my $user	= shift;
	my $pass	= shift;
	
	my %w;
	
	# Make an HBox to contain label, entry and del button
	$w{hbox} = Gtk2::HBox -> new( 0, 0 );
	$w{hbox} -> set_tooltip_text( 'Use <KPX_(title|username):title or user name> anywhere to refer to given password' );
		
		# Build label
		$w{lbl0} = Gtk2::Label -> new( 'Title:' );
		$w{hbox} -> pack_start( $w{lbl0}, 0, 1, 0 );
		
		# Build entry
		$w{title} = Gtk2::Entry -> new;
		$w{hbox} -> pack_start( $w{title}, 0, 1, 0 );
		$w{title} -> set_text( encode( 'unicode', $title ) );
		$w{title} -> set_editable( 0 );
		
		# Build label
		$w{lbl01} = Gtk2::Label -> new( 'URL:' );
		$w{hbox} -> pack_start( $w{lbl01}, 0, 1, 0 );
		
		# Build entry
		$w{url} = Gtk2::Entry -> new;
		$w{hbox} -> pack_start( $w{url}, 0, 1, 0 );
		$w{url} -> set_text( encode( 'unicode', $url ) );
		$w{url} -> set_editable( 0 );
		
		# Build label
		$w{lbl1} = Gtk2::Label -> new( 'Username:' );
		$w{hbox} -> pack_start( $w{lbl1}, 0, 1, 0 );
		
		# Build entry
		$w{var} = Gtk2::Entry -> new;
		$w{hbox} -> pack_start( $w{var}, 0, 1, 0 );
		$w{var} -> set_text( encode( 'unicode', $user ) );
		$w{var} -> set_editable( 0 );
		
		# Build label
		$w{lbl2} = Gtk2::Label -> new( ' Password:' );
		$w{hbox} -> pack_start( $w{lbl2}, 0, 1, 0 );
		
		# Build entry
		$w{val} = Gtk2::Entry -> new;
		$w{hbox} -> pack_start( $w{val}, 1, 1, 0 );
		$w{val} -> set_text( encode( 'unicode', $pass ) );
		$w{val} -> set_editable( 0 );
		
		$w{hide} = Gtk2::CheckButton -> new( 'Hide' );
		$w{hbox} -> pack_start( $w{hide}, 0, 1, 0 );
		$w{hide} -> set_active( 1 );
		$w{hide} -> signal_connect( toggled => sub { $w{val} -> set_visibility( ! $w{hide} -> get_active ); } );
		
		$w{val} -> set_visibility( ! $w{hide} -> get_active );
	
	# Add built control to main container
	$$self{frame}{vbKeePass} -> pack_start( $w{hbox}, 0, 1, 0 );
	$$self{frame}{vbKeePass} -> show_all;
	
	return %w;
}

# END: Private functions definitions
###################################################################

1;
