package PACMethod_vncviewer;

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
use FindBin qw ( $RealBin $Bin $Script );

# GTK
use Gtk3 '-init';

# END: Import Modules
###################################################################

###################################################################
# Define GLOBAL CLASS variables

my $ENCODINGS = "Tight Zlib Hextile CoRRE RRE CopyRect Raw";
my %DEPTH = ( 8 => 0, 15 => 1, 16 => 2, 24 => 3, 32 => 4, 'default' => 5 );
my $RES_DIR = $RealBin . '/res';

# END: Define GLOBAL CLASS variables
###################################################################

###################################################################
# START: Public class methods

sub new {
	my $class	= shift;
	my $self	= {};
	
	$self -> {container}	= shift;
	
	$self -> {cfg}			= undef;
	$self -> {gui}			= undef;
	$self -> {frame}		= {};
	
	_buildGUI( $self );
	
	bless( $self, $class );
	return $self;
}

sub update {
	my $self	= shift;
	my $cfg		= shift;
	my $method	= shift;
	
	defined $cfg and $$self{cfg} = $cfg;
	
	my $options = _parseCfgToOptions( $$self{cfg});
	
	$$self{gui}{chNaturalSize}		-> set_active( ! ( $$options{fullScreen} || $$options{embed} ) );
	$$self{gui}{chFullScreen}		-> set_active( $$options{fullScreen} );
	$$self{gui}{chEmbed}			-> set_active( $$options{embed} );
	$$self{gui}{chListen}			-> set_active( $$options{listen} );
	$$self{gui}{chViewOnly}			-> set_active( $$options{viewOnly} );
	$$self{gui}{spQuality}			-> set_value( $$options{quality} );
	$$self{gui}{spCompressLevel}	-> set_value( $$options{compressLevel} );
	$$self{gui}{entryVia}			-> set_text( $$options{via} );
	$$self{gui}{cbDepth}			-> set_active( $DEPTH{ $$options{depth} // 'default' } );

	return 1;
}

sub get_cfg {
	my $self = shift;
	
	my %options;
	
	$options{fullScreen}	= $$self{gui}{chFullScreen}		-> get_active;
	$options{embed}			= $$self{gui}{chEmbed}			-> get_active;
	$options{listen}		= $$self{gui}{chListen}			-> get_active;
	$options{viewOnly}		= $$self{gui}{chViewOnly}		-> get_active;
	$options{quality}		= $$self{gui}{spQuality}		-> get_value;
	$options{compressLevel}	= $$self{gui}{spCompressLevel}	-> get_value;
	$options{via}			= $$self{gui}{entryVia}			-> get_chars( 0, -1 );
	$options{depth}			= $$self{gui}{cbDepth}			-> get_active_text;
	
	return _parseOptionsToCfg( \%options );
}

# END: Public class methods
###################################################################

###################################################################
# START: Private functions definitions

sub _parseCfgToOptions {
	my $cmd_line = shift;
	
	my %hash;
	$hash{fullScreen}		= 0;
	$hash{embed}			= 0;
	$hash{nsize}			= 1;
	$hash{quality}			= 5;
	$hash{compressLevel}	= 8;
	$hash{depth}			= 'default';
	$hash{via}				= '';
	
	my @opts = split( /\s+-/, $cmd_line );
	foreach my $opt ( @opts )
	{
		next unless $opt ne '';
		$opt =~ s/\s+$//go;
		
		if ( $opt eq 'fullscreen' )			{	$hash{fullScreen}		= 1; $hash{embed} = 0; $hash{nsize} = 0; }
		if ( $opt eq 'embed' )				{	$hash{fullScreen}		= 0; $hash{embed} = 1; $hash{nsize} = 0; }
		$opt eq 'listen'					and	$hash{listen}			= 1;
		$opt eq 'viewonly'					and	$hash{viewOnly}			= 1;
		$opt =~ /^compresslevel\s+(\d+)$/go	and	$hash{compressLevel}	= $1;
		$opt =~ /^quality\s+(\d+)$/go		and	$hash{quality}			= $1;
		$opt =~ /^depth\s+(\d+)$/go			and	$hash{depth}			= $1;
		$opt =~ /^via\s+(.+)$/go			and	$hash{via}				= $1;
	}
	
	return \%hash;
}

sub _parseOptionsToCfg {
	my $hash = shift;
	
	my $txt = '';
	
	$txt .= ' -fullscreen'		if $$hash{fullScreen};
	$txt .= ' -embed'			if $$hash{embed};
	$txt .= ' -listen'			if $$hash{listen};
	$txt .= ' -viewonly'		if $$hash{viewOnly};
	$txt .= ' -depth '			. $$hash{depth} if ( $$hash{depth} ne 'default' );
	$txt .= ' -compresslevel '	. $$hash{compressLevel};
	$txt .= ' -quality '		. $$hash{quality};
	$txt .= " -encodings \"$ENCODINGS\"";
	$txt .= ' -autopass';
	$txt .= " -via $$hash{via}" if $$hash{via};
	
	return $txt;
}

sub embed {
	my $self = shift;
	return $$self{gui}{chEmbed} -> get_active;
}

sub _buildGUI {
	my $self		= shift;
	
	my $container	= $$self{container};
	my $cfg			= $$self{cfg};
	
	my %w;
	
	$w{vbox} = $container;
		
		$w{hbox1} = Gtk3::HBox -> new( 0, 5 );
		$w{vbox} -> pack_start( $w{hbox1}, 0, 1, 5 );
			
			$w{frCompressLevel} = Gtk3::Frame -> new( 'Compression level (1: min, 10: max) :' );
			$w{hbox1} -> pack_start( $w{frCompressLevel}, 1, 1, 0 );
			$w{frCompressLevel} -> set_tooltip_text( '[-g] : Percentage of the whole screen to use' );
				
				$w{spCompressLevel} = Gtk3::HScale -> new( Gtk3::Adjustment -> new( 8, 1, 11, 1.0, 1.0, 1.0 ) );
				$w{frCompressLevel} -> add( $w{spCompressLevel} );
			
			$w{frQuality} = Gtk3::Frame -> new( 'Picture quality (1: min, 10: max) :' );
			$w{hbox1} -> pack_start( $w{frQuality}, 1, 1, 0 );
			$w{frQuality} -> set_tooltip_text( '[-g] : Percentage of the whole screen to use' );
				
				$w{spQuality} = Gtk3::HScale -> new( Gtk3::Adjustment -> new( 5, 1, 11, 1.0, 1.0, 1.0 ) );
				$w{frQuality} -> add( $w{spQuality} );
			
		$w{hbox2} = Gtk3::HBox -> new( 0, 5 );
		$w{vbox} -> pack_start( $w{hbox2}, 0, 1, 5 );
			
			$w{chFullScreen} = Gtk3::RadioButton -> new_with_label( undef, 'Fullscreen' );
			$w{hbox2} -> pack_start( $w{chFullScreen}, 0, 1, 0 );
			$w{chFullScreen} -> set_tooltip_text( '[-fullscreen] : Fullscreen window' );
			
			$w{chNaturalSize} = Gtk3::RadioButton -> new_with_label( $w{chFullScreen}, 'Natural Size' );
			$w{hbox2} -> pack_start( $w{chNaturalSize}, 0, 1, 0 );
			
			$w{chEmbed} = Gtk3::RadioButton -> new_with_label( $w{chFullScreen}, 'Embed' );
			$w{hbox2} -> pack_start( $w{chEmbed}, 0, 1, 0 );
			$w{chEmbed} -> set_tooltip_text( "Embed VNC window into Àsbrú Connection Manager tab\nWARNING: Highly experimental!\nIt may not work at all\nOn failure, please, change this setting." );
			
			$w{chListen} = Gtk3::CheckButton -> new_with_label( 'Listen' );
			$w{hbox2} -> pack_start( $w{chListen}, 0, 1, 0 );
			$w{chListen} -> set_tooltip_text( '[-listen] : Listen for incoming connections' );
			
			$w{chViewOnly} = Gtk3::CheckButton -> new_with_label( 'View Only' );
			$w{hbox2} -> pack_start( $w{chViewOnly}, 0, 1, 0 );
			$w{chViewOnly} -> set_tooltip_text( '[-viewonly] : View only mode' );
			
			$w{frDepth} = Gtk3::Frame -> new( 'Colour depth (bpp):' );
			$w{hbox2} -> pack_start( $w{frDepth}, 0, 1, 0 );
			$w{frDepth} -> set_shadow_type( 'GTK_SHADOW_NONE' );
			$w{frDepth} -> set_tooltip_text( '[-depth bits_per_pixel] : Attempt to use the specified colour depth (in bits per pixel)' );
				
				$w{cbDepth} = Gtk3::ComboBoxText -> new;
				$w{frDepth}  -> add( $w{cbDepth} );
				foreach my $depth ( 8, 15, 16, 24, 32, 'default' ) { $w{cbDepth} -> append_text( $depth ); };
			
			$w{lblVia} = Gtk3::Label -> new( 'Via:' );
			$w{hbox2} -> pack_start( $w{lblVia}, 0, 0, 0 );
			$w{lblVia} -> set_tooltip_text( '[-via gateway] : Starts an SSH to tunnel the connection' );
			
			$w{entryVia} = Gtk3::Entry -> new;
			$w{hbox2} -> pack_start( $w{entryVia}, 0, 1, 0 );
			$w{entryVia} -> set_tooltip_text( '[-via gateway] : Starts an SSH to tunnel the connection' );
	
	$$self{gui} = \%w;
	
	return 1;
}

# END: Private functions definitions
###################################################################

1;
