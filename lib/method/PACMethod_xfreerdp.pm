package PACMethod_xfreerdp;

##################################################################
# This file is part of PAC( Perl Auto Connector)
#
# Copyright (C) 2010-2015  David Torrejon Vaquerizas
# 
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
# 
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
# 
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.
###################################################################

$|++;

###################################################################
# Import Modules

# Standard
use strict;
use warnings;
use FindBin qw ( $RealBin $Bin $Script );

# GTK2
use Gtk2 '-init';

# END: Import Modules
###################################################################

###################################################################
# Define GLOBAL CLASS variables

my %BPP 		= ( 8 => 0, 15 => 1, 16 => 2, 24 => 3 );

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
	
	$$self{gui}{cbBPP}					-> set_active( $BPP{ $$options{bpp} // 8 } );
	$$self{gui}{chAttachToConsole}		-> set_active( $$options{attachToConsole} );
	$$self{gui}{chUseCompression}		-> set_active( $$options{useCompression} );
	$$self{gui}{chFullscreen}			-> set_active( $$options{fullScreen} );
	$$self{gui}{chEmbed}				-> set_active( $$options{embed} );
	$$self{gui}{chPercentage}			-> set_active( $$options{percent} );
	$$self{gui}{chWidthHeight}			-> set_active( $$options{wh} );
	$$self{gui}{spGeometry}				-> set_value( $$options{geometry} ) if $$options{percent};
	$$self{gui}{spWidth}				-> set_value( $$options{width} // 640 );
	$$self{gui}{spHeight}				-> set_value( $$options{height} // 480 );
	$$self{gui}{spGeometry}				-> set_sensitive( $$options{percent} );
	$$self{gui}{hboxWidthHeight}		-> set_sensitive( $$options{wh} );
	$$self{gui}{entryKeyboard}			-> set_text( $$options{keyboardLocale} );
	$$self{gui}{cbRedirSound}			-> set_active( $$options{redirSound} // 1 );
	$$self{gui}{cbRedirClipboard}		-> set_active( $$options{redirClipboard} // 0 );
	$$self{gui}{entryDomain}			-> set_text( $$options{domain} // '' );
	$$self{gui}{chIgnoreCert}			-> set_active( $$options{ignoreCert} // 0 );
	$$self{gui}{chNoAuth}				-> set_active( $$options{noAuth} // 0 );
	$$self{gui}{chNoFastPath}			-> set_active( $$options{nofastPath} // 0 );
	$$self{gui}{chRFX}					-> set_active( $$options{rfx} // 0 );
	$$self{gui}{chNSCodec}				-> set_active( $$options{nsCodec} // 0 );
	$$self{gui}{chNoRDP}				-> set_active( $$options{noRDP} // 0 );
	$$self{gui}{chNoTLS}				-> set_active( $$options{noTLS} // 0 );
	$$self{gui}{chNoNLA}				-> set_active( $$options{noNLA} // 0 );
	$$self{gui}{chFontSmooth}			-> set_active( $$options{fontSmooth} // 0 );
	$$self{gui}{entryStartupShell}		-> set_text( $$options{startupshell} // '' );

	# Destroy previuos widgets
	$$self{gui}{vbRedirect} -> foreach( sub { $_[0] -> destroy(); } );
	
	# Empty disk redirect widgets' list
	$$self{listRedir}		= [];
	
	# Now, add the -new?- local forwarded disk shares widgets
	foreach my $hash ( @{ $$options{redirDisk} } ) { $self -> _buildRedir( $hash ); }
	
	return 1;
}

sub get_cfg {
	my $self = shift;
	
	my %options;
	
	$options{bpp}				= $$self{gui}{cbBPP}				-> get_active_text;
	$options{attachToConsole}	= $$self{gui}{chAttachToConsole}	-> get_active;
	$options{useCompression}	= $$self{gui}{chUseCompression}		-> get_active;
	$options{fullScreen}		= $$self{gui}{chFullscreen}			-> get_active;
	$options{geometry}			= $$self{gui}{spGeometry}			-> get_value;
	$options{percent}			= $$self{gui}{chPercentage}			-> get_active;
	$options{width}				= $$self{gui}{spWidth}				-> get_chars( 0, -1 );
	$options{height}			= $$self{gui}{spHeight}				-> get_chars( 0, -1 );
	$options{wh}				= $$self{gui}{chWidthHeight}		-> get_active;
	$options{embed}				= ! ( $$self{gui}{chFullscreen} -> get_active || $$self{gui}{chPercentage} -> get_active || $$self{gui}{chWidthHeight} -> get_active );
	$options{keyboardLocale}	= $$self{gui}{entryKeyboard}		-> get_chars( 0, -1 );
	$options{redirSound}		= $$self{gui}{cbRedirSound}			-> get_active;
	$options{redirClipboard}	= $$self{gui}{cbRedirClipboard}		-> get_active;
	$options{domain}			= $$self{gui}{entryDomain}			-> get_chars( 0, -1 );
	$options{ignoreCert}        = $$self{gui}{chIgnoreCert}			-> get_active;
	$options{noAuth}            = $$self{gui}{chNoAuth}				-> get_active;
	$options{nofastPath}        = $$self{gui}{chNoFastPath}			-> get_active;
	$options{rfx}               = $$self{gui}{chRFX}				-> get_active;
	$options{nsCodec}           = $$self{gui}{chNSCodec}			-> get_active;
	$options{noRDP}             = $$self{gui}{chNoRDP}				-> get_active;
	$options{noTLS}             = $$self{gui}{chNoTLS}				-> get_active;
	$options{noNLA}             = $$self{gui}{chNoNLA}				-> get_active;
	$options{fontSmooth}		= $$self{gui}{chFontSmooth}			-> get_active;
	$options{startupshell}		= $$self{gui}{entryStartupShell}	-> get_chars( 0, -1 );

	foreach my $w ( @{ $$self{listRedir} } ) {
		my %hash;
		$hash{'redirDiskShare'}	= $$w{entryRedirShare}	-> get_chars( 0, -1 ) || '';
		$hash{'redirDiskPath'}	= $$w{fcForwardPath}	-> get_uri;
		$hash{'redirDiskPath'}	=~ s/^(.+?\/\/)(.+)$/$2/go;
		next unless $hash{'redirDiskShare'} && $hash{'redirDiskPath'};
		push( @{ $options{redirDisk} }, \%hash );
	}
	
	return _parseOptionsToCfg( \%options );
}

# END: Public class methods
###################################################################

###################################################################
# START: Private functions definitions

sub _parseCfgToOptions {
	my $cmd_line = shift;
	
	my %hash;
	$hash{bpp}				= 8;
	$hash{attachToConsole}	= 0;
	$hash{useCompression}	= 0;
	$hash{fullScreen}		= 0;
	$hash{embed}			= 1;
	$hash{percent}			= 0;
	$hash{geometry}			= 90;
	$hash{wh}				= 0;
	$hash{width}			= 640;
	$hash{height}			= 480;
	$hash{keyboardLocale}	= '';
	$hash{redirDiskShare}	= '';
	$hash{redirDiskPath}	= $ENV{'HOME'};
	$hash{redirSound}		= 0;
	$hash{redirClipboard}	= 0;
	$hash{domain}			= '';
	$hash{ignoreCert}       = 0;
	$hash{noAuth}           = 0;
	$hash{nofastPath}       = 0;
	$hash{rfx}              = 0;
	$hash{nsCodec}          = 0;
	$hash{noRDP}            = 0;
	$hash{noTLS}            = 0;
	$hash{noNLA}            = 0;
	$hash{fontSmooth}		= 0;
	$hash{startupshell}		= '';
	
	my @opts = split( /\s+-/, $cmd_line );
	foreach my $opt ( @opts ) {
		next unless $opt ne '';
		$opt =~ s/\s+$//go;
		
		$opt =~ /^a\s+(8|15|16|24)$/go		and	$hash{bpp}				= $1;
		$opt eq '0'							and	$hash{attachToConsole}	= 1;
		$opt eq 'z'							and	$hash{useCompression}	= 1;
		if ( $opt =~ /^s\s+'(.+?)'$/go )	 {	$hash{startupshell} = $1; }
		if ( $opt eq 'f' ) {					$hash{fullScreen} = 1; $hash{percent} = 0; $hash{wh} = 0; $hash{'embed'} = 0; }
		if ( $opt =~ /^g\s+(\d+)\%$/go ) {		$hash{geometry} = $1; $hash{percent} = 1; $hash{wh} = 0; $hash{'embed'} = 0; }
		if ( $opt =~ /^g\s+(\d+)x(\d+)$/go ) {	$hash{width} = $1; $hash{height} = $2; $hash{wh} = 1; $hash{percent} = 0; $hash{'embed'} = 0; }
		$opt =~ /^k\s+(.+)$/go				and	$hash{keyboardLocale}	= $1;
		$opt =~ /^-plugin\s+rdpsnd$/go		and	$hash{redirSound}		= 1;
		$opt =~ /^-plugin\s+cliprdr$/go		and	$hash{redirClipboard}	= 1;
		$opt =~ /^d\s+(.+)$/go				and	$hash{domain}			= $1;
		$opt =~ /^-ignore-certificate$/go	and	$hash{ignoreCert}		= 1;
		$opt =~ /^-no-auth$/go				and	$hash{noAuth}			= 1;
		$opt =~ /^-no-fastpath$/go			and	$hash{nofastPath}		= 1;
		$opt =~ /^-rfx$/go					and	$hash{rfx}				= 1;
		$opt =~ /^-nsc$/go					and	$hash{nsCodec}			= 1;
		$opt =~ /^-no-rdp$/go				and	$hash{noRDP}			= 1;
		$opt =~ /^-no-tls$/go				and	$hash{noTLS}			= 1;
		$opt =~ /^-no-nla$/go				and	$hash{noNLA}			= 1;
		$opt =~ /^x\s+80$/go				and	$hash{fontSmooth}		= 1;
		
		while ( $opt =~ /^-data\s+disk:(.+):\"(.+)\"/go )
		{
			my %redir;
			$redir{redirDiskShare}	= $1;
			$redir{redirDiskPath}	= $2;
			push( @{ $hash{redirDisk} }, \%redir );
		}
	}
	
	return \%hash;
}

sub _parseOptionsToCfg {
	my $hash = shift;
	
	my $txt = '';
	
	$txt .= ' -a ' . $$hash{bpp};
	$txt .= ' -0' if $$hash{attachToConsole};
	$txt .= ' -z' if $$hash{useCompression};
	$txt .= ' -f' if $$hash{fullScreen};
	if ( $$hash{percent} )
	{
		$txt .= ' -g ' . $$hash{geometry} . '%';
	}
	elsif ( $$hash{wh} )
	{
		$txt .= ' -g ' . $$hash{width} . 'x' . $$hash{height};
	}
	$txt .= ' -k ' . $$hash{keyboardLocale} if $$hash{keyboardLocale} ne '';
	$txt .= " -s '$$hash{startupshell}'" if $$hash{startupshell} ne '';
	$txt .= " -d $$hash{domain}" if $$hash{domain} ne '';
	$txt .= ' --plugin cliprdr' if $$hash{redirClipboard};
	$txt .= ' --plugin rdpsnd' if $$hash{redirSound};
	
	$txt .= ' --ignore-certificate' if $$hash{ignoreCert};
	$txt .= ' --no-auth' if $$hash{noAuth};
	$txt .= ' --no-fastpath' if $$hash{nofastPath};
	$txt .= ' --rfx' if $$hash{rfx};
	$txt .= ' --nsc' if $$hash{nsCodec};
	$txt .= ' --no-rdp' if $$hash{noRDP};
	$txt .= ' --no-tls' if $$hash{noTLS};
	$txt .= ' --no-nla' if $$hash{noNLA};
	$txt .= ' -x 80' if $$hash{fontSmooth};
	
	foreach my $redir ( @{ $$hash{redirDisk} } ) { $txt .= " --plugin rdpdr --data disk:$$redir{redirDiskShare}:\"$$redir{redirDiskPath}\" --"; }
	
	return $txt;
}

sub embed {
	my $self = shift;
	return ! ( $$self{gui}{chFullscreen} -> get_active || $$self{gui}{chPercentage} -> get_active || $$self{gui}{chWidthHeight} -> get_active );
}

sub _buildGUI {
	my $self		= shift;
	
	my $container	= $self -> {container};
	my $cfg			= $self -> {cfg};
	
	my %w;
	
	$w{vbox} = $container;
		
		$w{hbox1} = Gtk2::HBox -> new( 0, 5 );
		$w{vbox} -> pack_start( $w{hbox1}, 0, 1, 5 );
			
			$w{frBPP} = Gtk2::Frame -> new( 'BPP:' );
			$w{hbox1} -> pack_start( $w{frBPP}, 0, 1, 0 );
			$w{frBPP} -> set_shadow_type( 'GTK_SHADOW_NONE' );
			$w{frBPP} -> set_tooltip_text( '[-a] : Sets the colour depth for the connection (8, 15, 16 or 24)' );
				
				$w{cbBPP} = Gtk2::ComboBox -> new_text;
				$w{frBPP} -> add( $w{cbBPP} );
				foreach my $bpp ( 8, 15, 16, 24 ) { $w{cbBPP} -> append_text( $bpp ); };
			
			$w{chAttachToConsole} = Gtk2::CheckButton -> new_with_label( 'Attach to console' );
			$w{hbox1} -> pack_start( $w{chAttachToConsole}, 0, 1, 0 );
			$w{chAttachToConsole} -> set_tooltip_text( '[-0] : Attach to console of server (requires Windows Server 2003 or newer)' );
			
			$w{chUseCompression} = Gtk2::CheckButton -> new_with_label( 'Compression' );
			$w{hbox1} -> pack_start( $w{chUseCompression}, 0, 1, 0 );
			$w{chUseCompression} -> set_tooltip_text( '[-z] : Enable compression of the RDP datastream' );
			
			$w{chIgnoreCert} = Gtk2::CheckButton -> new_with_label( 'Ignore verification of logon certificate' );
			$w{hbox1} -> pack_start( $w{chIgnoreCert}, 0, 1, 0 );
			$w{chIgnoreCert} -> set_tooltip_text( "--ignore-certificate: ignore verification of logon certificate" );
			
			$w{chFontSmooth} = Gtk2::CheckButton -> new_with_label( 'Font Smooth' );
			$w{hbox1} -> pack_start( $w{chFontSmooth}, 0, 1, 0 );
			$w{chFontSmooth} -> set_tooltip_text( "-x 80: enable font smoothing" );
		
		$w{hbox3} = Gtk2::HBox -> new( 0, 5 );
		$w{vbox} -> pack_start( $w{hbox3}, 0, 1, 5 );
			
			$w{chNoAuth} = Gtk2::CheckButton -> new_with_label( 'No Authentication' );
			$w{hbox3} -> pack_start( $w{chNoAuth}, 0, 1, 0 );
			$w{chNoAuth} -> set_tooltip_text( "--no-auth: disable authentication" );
			
			$w{chNoFastPath} = Gtk2::CheckButton -> new_with_label( 'No Fast Path' );
			$w{hbox3} -> pack_start( $w{chNoFastPath}, 0, 1, 0 );
			$w{chNoFastPath} -> set_tooltip_text( "--no-fastpath: disable fast-path" );
			
			$w{chRFX} = Gtk2::CheckButton -> new_with_label( 'Enable RemoteFX' );
			$w{hbox3} -> pack_start( $w{chRFX}, 0, 1, 0 );
			$w{chRFX} -> set_tooltip_text( "--rfx: enable RemoteFX" );
			
			$w{chNSCodec} = Gtk2::CheckButton -> new_with_label( 'Enable NSCodec' );
			$w{hbox3} -> pack_start( $w{chNSCodec}, 0, 1, 0 );
			$w{chNSCodec} -> set_tooltip_text( "--nsc: enable NSCodec (experimental)" );
			
		$w{hbox4} = Gtk2::HBox -> new( 0, 5 );
		$w{vbox} -> pack_start( $w{hbox4}, 0, 1, 5 );
			
			$w{chNoRDP} = Gtk2::CheckButton -> new_with_label( 'Disable RDP encryption' );
			$w{hbox4} -> pack_start( $w{chNoRDP}, 0, 1, 0 );
			$w{chNoRDP} -> set_tooltip_text( "--no-rdp: disable Standard RDP encryption" );
			
			$w{chNoTLS} = Gtk2::CheckButton -> new_with_label( 'Disable TLS encryption' );
			$w{hbox4} -> pack_start( $w{chNoTLS}, 0, 1, 0 );
			$w{chNoTLS} -> set_tooltip_text( "--no-tls: disable TLS encryption" );
			
			$w{chNoNLA} = Gtk2::CheckButton -> new_with_label( 'Disable Network Level Authentication' );
			$w{hbox4} -> pack_start( $w{chNoNLA}, 0, 1, 0 );
			$w{chNoNLA} -> set_tooltip_text( "--no-nla: disable network level authentication" );
		
		$w{hboxss} = Gtk2::HBox -> new( 0, 5 );
		$w{vbox} -> pack_start( $w{hboxss}, 0, 1, 5 );
			
			$w{lblStartupShell} = Gtk2::Label -> new( 'Startup shell: ' );
			$w{hboxss} -> pack_start( $w{lblStartupShell}, 0, 1, 0 );
			
			$w{entryStartupShell} = Gtk2::Entry -> new;
			$w{entryStartupShell} -> set_tooltip_text( "[-s 'startupshell command'] : start given startupshell/command instead of explorer" );
			$w{hboxss} -> pack_start( $w{entryStartupShell}, 1, 1, 5 );
		
		$w{hbox2} = Gtk2::HBox -> new( 0, 5 );
		$w{vbox} -> pack_start( $w{hbox2}, 0, 1, 5 );
			
			$w{frGeometry} = Gtk2::Frame -> new( ' RDP Window size: ' );
			$w{hbox2} -> pack_start( $w{frGeometry}, 1, 1, 0 );
			$w{frGeometry} -> set_tooltip_text( '[-g] : Amount of screen to use' );
				
				$w{hboxsize} = Gtk2::VBox -> new( 0, 5 );
				$w{frGeometry} -> add( $w{hboxsize} );
					
					$w{hboxfsebpc} = Gtk2::HBox -> new( 0, 5 );
					$w{hboxsize} -> pack_start( $w{hboxfsebpc}, 1, 1, 0 );
					
					$w{chFullscreen} = Gtk2::RadioButton -> new_with_label( undef, 'Fullscreen' );
					$w{hboxfsebpc} -> pack_start( $w{chFullscreen}, 1, 1, 0 );
					$w{chFullscreen} -> set_tooltip_text( '[-f] : Enable fullscreen mode (toggled at any time using Ctrl-Alt-Enter)' );
					
					$w{chEmbed} = Gtk2::RadioButton -> new_with_label( $w{chFullscreen}, 'Embed in TAB(*)' );
					$w{hboxfsebpc} -> pack_start( $w{chEmbed}, 1, 1, 0 );
					$w{chEmbed} -> set_tooltip_text( "[-X:xid] : Embed RDP window in a PAC TAB\n*WARNING*: this may not work on your system with 'xfreerdp'.\nTry to select another option if your connections does not work correctly" );
					$w{chEmbed} -> set_sensitive( 1 );
					$w{chEmbed} -> set_active( 0 );
					
					$w{hbox69} = Gtk2::HBox -> new( 0, 5 );
					$w{hboxfsebpc} -> pack_start( $w{hbox69}, 1, 1, 0 );
						
						$w{chWidthHeight} = Gtk2::RadioButton -> new_with_label( $w{chFullscreen}, 'Width x Height:' );
						$w{chWidthHeight} -> set_tooltip_text( '[-g WIDTHxHEIGHT] : Define a fixed WIDTH x HEIGHT geometry window' );
						$w{hbox69} -> pack_start( $w{chWidthHeight}, 0, 1, 0 );
						
						$w{hboxWidthHeight} = Gtk2::HBox -> new( 0, 5 );
						$w{hbox69} -> pack_start( $w{hboxWidthHeight}, 0, 1, 0 );
							
							$w{spWidth} = Gtk2::SpinButton -> new_with_range( 1, 4096, 10 );
							$w{hboxWidthHeight} -> pack_start( $w{spWidth}, 0, 1, 0 );
							$w{spHeight} = Gtk2::SpinButton -> new_with_range( 1, 4096, 10 );
							$w{hboxWidthHeight} -> pack_start( $w{spHeight}, 0, 1, 0 );
							$w{hboxWidthHeight} -> set_sensitive( 0 );
					
					$w{hboxPercentage} = Gtk2::HBox -> new( 0, 5 );
					$w{hboxsize} -> pack_start( $w{hboxPercentage}, 0, 1, 0 );
						
						$w{chPercentage} = Gtk2::RadioButton -> new_with_label( $w{chFullscreen}, 'Screen percentage:' );
						$w{chPercentage} -> set_tooltip_text( '[-g percentage%] : Amount of screen to use' );
						$w{chPercentage} -> set_active( 1 );
						$w{hboxPercentage} -> pack_start( $w{chPercentage}, 0, 1, 0 );
						
						$w{spGeometry} = Gtk2::HScale -> new( Gtk2::Adjustment -> new( 90, 10, 100, 1.0, 1.0, 1.0 ) );
						$w{hboxPercentage} -> pack_start( $w{spGeometry}, 1, 1, 0 );
			
			$w{frKeyboard} = Gtk2::Frame -> new( 'Keyboard layout:' );
			$w{hbox2} -> pack_start( $w{frKeyboard}, 0, 1, 0 );
			$w{frKeyboard} -> set_tooltip_text( '[-k] : Keyboard layout' );
				
				$w{entryKeyboard} = Gtk2::Entry -> new;
				$w{frKeyboard} -> add( $w{entryKeyboard} );
		
		$w{hboxDomain} = Gtk2::HBox -> new( 0, 5 );
		$w{vbox} -> pack_start( $w{hboxDomain}, 0, 1, 5 );
			
			$w{hboxDomain} -> pack_start( Gtk2::Label -> new( 'Windows Domain: ' ), 0, 1, 0 );
			$w{entryDomain} = Gtk2::Entry -> new;
			$w{hboxDomain} -> pack_start( $w{entryDomain}, 1, 1, 0 );
			
			$w{cbRedirClipboard} = Gtk2::CheckButton -> new_with_label( 'Clipboard redirect' );
			$w{hboxDomain} -> pack_start( $w{cbRedirClipboard}, 0, 1, 0 );
			
			$w{cbRedirSound} = Gtk2::CheckButton -> new_with_label( 'Sound redirect' );
			$w{hboxDomain} -> pack_start( $w{cbRedirSound}, 0, 1, 0 );
		
		$w{frameRedirDisk} = Gtk2::Frame -> new( ' Disk redirects: ' );
		$w{vbox} -> pack_start( $w{frameRedirDisk}, 1, 1, 0 );
		$w{frameRedirDisk} -> set_tooltip_text( '[-r disk:<8_chars_sharename>=<path>] : Redirects a <path> to the share \\tsclient\<8_chars_sharename> on the server' );
			
			$w{vbox_enesimo} = Gtk2::VBox -> new( 0, 0);
			$w{frameRedirDisk} -> add( $w{vbox_enesimo}, );
				
				# Build 'add' button
				$w{btnadd} = Gtk2::Button -> new_from_stock( 'gtk-add' );
				$w{vbox_enesimo} -> pack_start( $w{btnadd}, 0, 1, 0 );
				
				# Build a scrolled window
				$w{sw} = Gtk2::ScrolledWindow -> new();
				$w{vbox_enesimo} -> pack_start( $w{sw}, 1, 1, 0 );
				$w{sw} -> set_policy( 'automatic', 'automatic' );
				$w{sw} -> set_shadow_type( 'none' );
					
					$w{vp} = Gtk2::Viewport -> new();
					$w{sw} -> add( $w{vp} );
					$w{vp} -> set_shadow_type( 'GTK_SHADOW_NONE' );
						
						# Build and add the vbox that will contain the redirect widgets
						$w{vbRedirect} = Gtk2::VBox -> new( 0, 0 );
						$w{vp} -> add( $w{vbRedirect} );
	
	# Capture 'Full Screen' checkbox toggled state
	$w{chFullscreen}	-> signal_connect( 'toggled' => sub { $w{hboxWidthHeight} -> set_sensitive( $w{chWidthHeight} -> get_active ); $w{spGeometry} -> set_sensitive( ! $w{chFullscreen} -> get_active ); } );
	$w{chPercentage}	-> signal_connect( 'toggled' => sub { $w{hboxWidthHeight} -> set_sensitive( $w{chWidthHeight} -> get_active ); $w{spGeometry} -> set_sensitive( ! $w{chFullscreen} -> get_active ); } );
	$w{chWidthHeight}	-> signal_connect( 'toggled' => sub { $w{hboxWidthHeight} -> set_sensitive( $w{chWidthHeight} -> get_active ); $w{spGeometry} -> set_sensitive( ! $w{chFullscreen} -> get_active ); } );
	
	$$self{gui} = \%w;
	
	$w{btnadd} -> signal_connect( 'clicked', sub {
		$$self{cfg} = $self -> get_cfg;
		my $opt_hash = _parseCfgToOptions( $$self{cfg} );
		push( @{ $$opt_hash{redirDisk} }, { 'redirDiskShare' => $ENV{'USER'}, 'redirDiskPath' => $ENV{'HOME'} } );
		$$self{cfg} = _parseOptionsToCfg( $opt_hash );
		$self -> update( $$self{cfg} );
		return 1;
	} );
	
	return 1;
}

sub _buildRedir {
	my $self	= shift;
	my $hash	= shift;
	
	my $redirDiskShare	= $$hash{'redirDiskShare'}	// $ENV{'USER'};
	my $redirDiskPath	= $$hash{'redirDiskPath'}	// $ENV{'HOME'};
	
	my @undo;
	my $undoing = 0;
	
	my %w;
	
	$w{position} = scalar @{ $$self{listRedir} };
	
	# Make an HBox to contain local address, local port, remote address, remote port and delete
	$w{hbox} = Gtk2::HBox -> new( 0, 0 );
		
		$w{hbox} -> pack_start( Gtk2::Label -> new( 'Share Name (8 chars max.!):' ), 0, 1, 0 );
		$w{entryRedirShare} = Gtk2::Entry -> new;
		$w{hbox} -> pack_start( $w{entryRedirShare}, 0, 1, 0 );
		$w{entryRedirShare} -> set_text( $redirDiskShare );
		
		$w{fcForwardPath} = Gtk2::FileChooserButton -> new( 'Select a path to share', 'GTK_FILE_CHOOSER_ACTION_SELECT_FOLDER' );
		$redirDiskPath =~ s/(.+)/file:\/\/$1/g;
		$w{fcForwardPath} -> set_uri( $redirDiskPath );
		$w{hbox} -> pack_start( $w{fcForwardPath}, 1, 1, 0 );
		
		# Build delete button
		$w{btn} = Gtk2::Button -> new_from_stock( 'gtk-delete' );
		$w{hbox} -> pack_start( $w{btn}, 0, 1, 0 );
	
	# Add built control to main container
	$$self{gui}{vbRedirect} -> pack_start( $w{hbox}, 0, 1, 0 );
	$$self{gui}{vbRedirect} -> show_all;
	
	$$self{listRedir}[$w{position}] = \%w;
	
	# Setup some callbacks
	
	# Asign a callback for deleting entry
	$w{btn} -> signal_connect( 'clicked' => sub
	{
		$$self{cfg} = $self -> get_cfg();
		splice( @{ $$self{listRedir} }, $w{position}, 1 );
		$$self{cfg} = $self -> get_cfg();
		$self -> update( $$self{cfg} );
		return 1;
	} );
	
	return %w;
}

# END: Private functions definitions
###################################################################

1;
