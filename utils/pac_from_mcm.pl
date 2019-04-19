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

my $in_file = shift or die "ERROR: You must provide an input file!!";
my $out_file = shift or die "ERROR: You must provide an outpout file!!";

open( F_IN, $in_file ) or die "ERROR: Could not open input file '$in_file' for reading ($!)";
my @lines = <F_IN>;
close F_IN;

my $header = shift( @lines );

_cfgSanityCheck( \%CFG );

$CFG{'defaults'}{'version'} = '1';

foreach my $line ( @lines )
{
	chomp $line;
	$line =~ s/^\"|\"$//go;
	my @fields = split( /\"*,\"*/o, $line );
	$CFG{'environments'}{$fields[8]}{$fields[0]}{'description'}	= $fields[9];
	$CFG{'environments'}{$fields[8]}{$fields[0]}{'title'}		= $fields[0];
	$CFG{'environments'}{$fields[8]}{$fields[0]}{'ip'}			= $fields[3];
	$CFG{'environments'}{$fields[8]}{$fields[0]}{'port'}		= $fields[4];
	$CFG{'environments'}{$fields[8]}{$fields[0]}{'user'}		= $fields[5];
	$CFG{'environments'}{$fields[8]}{$fields[0]}{'pass'}		= $fields[6];
	$CFG{'environments'}{$fields[8]}{$fields[0]}{'method'}		= lc( $fields[1] );
}

_cfgSanityCheck( \%CFG );

_cipherCFG( \%CFG );

DumpFile( $out_file, \%CFG );

exit 0;
