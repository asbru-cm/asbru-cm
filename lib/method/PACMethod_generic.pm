package PACMethod_generic;

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

my $RES_DIR = $RealBin . '/res';

# END: Define GLOBAL CLASS variables
###################################################################

###################################################################
# START: Public class methods

sub new
{
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

sub update
{
	my $self	= shift;
	my $cfg		= shift;
	my $method	= shift;
	
	defined $cfg and $$self{cfg} = $cfg;
	
	my $options = _parseCfgToOptions( $$self{cfg} );
	
	return 1;
}

sub get_cfg
{
	my $self = shift;
	
	my %options;
	
	return _parseOptionsToCfg( \%options );
}

# END: Public class methods
###################################################################

###################################################################
# START: Private functions definitions

sub _parseCfgToOptions
{
	my $cmd_line = shift;
	
	my %hash;
	
	return \%hash;
}

sub _parseOptionsToCfg
{
	my $hash = shift;
	
	my $txt = '';
	
	return $txt;
}

sub embed
{
	my $self = shift;
	return 0;
}

sub _buildGUI
{
	my $self		= shift;
	
	my $container	= $self -> {container};
	my $cfg			= $self -> {cfg};
	
	my %w;
	
	$w{vbox} = $container;
		
		$w{vbox} -> pack_start( Gtk2::Label -> new( 'No option to configure here.' ), 1, 1, 0 );
	
	$$self{gui} = \%w;
	
	return 1;
}

# END: Private functions definitions
###################################################################

1;
