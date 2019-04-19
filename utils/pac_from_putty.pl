#!/usr/bin/perl

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
# START: Import Modules

BEGIN
{
	use FindBin qw ( $RealBin $Bin $Script );
	push( @INC, $RealBin . '/../lib' );
}

# Standard
use strict;
use warnings;
use YAML qw ( LoadFile DumpFile );

# PAC modules
use PACUtils;

# END: Import Modules
###################################################################

###################################################################
# START: Define GLOBAL variables

my %CFG;

# END: Define GLOBAL variables
###################################################################

my $in_dir = "$ENV{'HOME'}/.putty/sessions";
my $out_file = shift or die "ERROR: You must provide an outpout file!!";

opendir( my $D_IN, $in_dir ) or die "ERROR: Could not open input directory '$in_dir' for reading ($!)";

_cfgSanityCheck( \%CFG );

$CFG{'defaults'}{'version'} = '1';

foreach my $file ( readdir( $D_IN ) )
{
	next if -d $file;
	next if $file =~ /^\./go;
	my %conn;
	
	open( F_IN, $in_dir . '/' . $file ) or die "ERROR: Coul not open file '$file' for reading ($!)";
	while ( my $line = <F_IN> )
	{
		chomp $line;
		my ( $key, $value ) = split( '=', $line );
		$conn{$key} = $value;
	}
	close F_IN;
	
	next unless $conn{'Protocol'} eq 'ssh';
	
	$CFG{'environments'}{'Putty_Imported'}{$file}{'description'}	= "Connection with 'Putty_Imported' -> '$file'";
	$CFG{'environments'}{'Putty_Imported'}{$file}{'title'}			= "Putty_Imported - $file";
	$CFG{'environments'}{'Putty_Imported'}{$file}{'ip'}				= $conn{HostName};
	$CFG{'environments'}{'Putty_Imported'}{$file}{'port'}			= $conn{PortNumber};
	$CFG{'environments'}{'Putty_Imported'}{$file}{'user'}			= $conn{UserName};
	$CFG{'environments'}{'Putty_Imported'}{$file}{'pass'}			= '';
	$CFG{'environments'}{'Putty_Imported'}{$file}{'method'}			= 'ssh';
	$CFG{'environments'}{'Putty_Imported'}{$file}{'options'}		= '';
	$CFG{'environments'}{'Putty_Imported'}{$file}{'options'}		.= ' -X' if $conn{X11Forward};
	#$CFG{'environments'}{'Putty_Imported'}{$file}{'options'}		.= ' -X' if $conn{};
	#$CFG{'environments'}{'Putty_Imported'}{$file}{'options'}		.= ' -X' if $conn{};
	#$CFG{'environments'}{'Putty_Imported'}{$file}{'options'}		.= ' -X' if $conn{};
	#$CFG{'environments'}{'Putty_Imported'}{$file}{'options'}		.= ' -X' if $conn{};
	#$CFG{'environments'}{'Putty_Imported'}{$file}{'options'}		.= ' -X' if $conn{};
	#$CFG{'environments'}{'Putty_Imported'}{$file}{'options'}		.= ' -X' if $conn{};
	#$CFG{'environments'}{'Putty_Imported'}{$file}{'options'}		.= ' -X' if $conn{};
}

closedir $D_IN;

_cfgSanityCheck( \%CFG );

_cipherCFG( \%CFG );

DumpFile( $out_file, \%CFG );

exit 0;
