#!/usr/bin/perl

###################################################################
# This file is part of PAC( Perl Auto Connector)
#
# Copyright (C) 2010-2014 David Torrejon Vaquerizas
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

BEGIN {
	if ( grep( { /^-{1,2}(help|h)$/gi } @ARGV ) ) {
		print "\n";
		print "Usage: pac [options]\n";
		print "Options:\n";
		print "\t--help : this help\n";
		print "\t--no-backup : do no create alternative PAC config files as a backup (faster shutdown)\n";
		print "\t--start-shell : start a local terminal\n";
		print "\t--password=<pwd> : automatically logon with given password without prompting user\n";
		print "\t--start-uuid=<uuid>[:<cluster] : start connection in cluster (if given)\n";
		print "\t--edit-uuid=<uuid> : edit connection\n";
		print "\t--dump-uuid=<uuid> : dump data for given connection\n";
		print "\t--scripts : open scripts window\n";
		print "\t--start-script=<script> : start given script\n";
		print "\t--preferences : open global preferences dialog\n";
		print "\t--quick-conn : open the Quick Connect dialog on startup\n";
		print "\t--list-uuids : list existing connections/groups and their UUIDs\n";
		print "\t--no-splash : no splash screen on startup\n";
		print "\t--iconified : make PAC go to tray once started\n";
		print "\t--readonly : start PAC in read only mode (no config changes allowed)\n";
		print "\n";
		print "See 'man pac' for more info.\n";
		print "\n";
		exit 0;
	}
}

###################################################################
# START: Import Modules

use FindBin qw ( $RealBin $Bin $Script );
use lib $RealBin . '/lib', $RealBin . '/lib/ex', $RealBin . '/lib/edit';
use File::Copy;

# Standard
use strict;
use warnings;

use PACMain;

# END: Import Modules
###################################################################

###################################################################
# START: Define GLOBAL variables
my $INIT_CFG_FILE	= $RealBin		. '/res/pac.yml';
my $CFG_DIR			= $ENV{'HOME'}	. '/.config/pac';
my $OLD_CFG_DIR		= $ENV{'HOME'}	. '/.pac';
my $CFG_FILE		= $CFG_DIR		. '/pac.cfg';

my $PAC;

# END: Define GLOBAL variables
###################################################################

###################################################################
# START: MAIN program

print "PAC started ($Script) with PID $$\n";

# Check for Unity's systray-whitelist presence of 'pac'
my $wl = `gsettings get com.canonical.Unity.Panel systray-whitelist 2>/dev/null`;
chomp $wl;
if ( ( $? eq 0 ) && ( ! grep( /'pac'/, $wl ) ) ) {
	print " - Adding 'pac' to Unity's 'systray-whitelist'\n";
	$wl =~ s/'\s*]/', 'pac']/;
	`gsettings set com.canonical.Unity.Panel systray-whitelist "$wl"`;
}

# Check for the existance of some directories
-d $ENV{'HOME'} . '/.config'			or mkdir( $ENV{'HOME'} . '/.config' );
-d $ENV{'HOME'} . '/.config/autostart'	or mkdir( $ENV{'HOME'} . '/.config/autostart' );

# Move old $HOME/.pac/ config dir to new location $HOME/.config/pac/
( ( ! -d $CFG_DIR ) && ( -d $OLD_CFG_DIR ) ) and system( "mv $OLD_CFG_DIR $CFG_DIR" );

( -d $CFG_DIR || -l $CFG_DIR )			or mkdir( $CFG_DIR );
-d $CFG_DIR . '/screenshots'			or mkdir( $CFG_DIR . '/screenshots' );
-d $CFG_DIR . '/session_logs'			or mkdir( $CFG_DIR . '/session_logs' );
-d $CFG_DIR . '/sockets'				or mkdir( $CFG_DIR . '/sockets' );
-d $CFG_DIR . '/tmp'					or mkdir( $CFG_DIR . '/tmp' );
-d $CFG_DIR . '/scripts'				or mkdir( $CFG_DIR . '/scripts' );
-d $CFG_DIR . '/scripts/sample1.pl'		or copy( $RealBin . '/res/sample1.pl', $CFG_DIR . '/scripts/' );
-d $CFG_DIR . '/scripts/sample2.pl'		or copy( $RealBin . '/res/sample2.pl', $CFG_DIR . '/scripts/' );
-d $CFG_DIR . '/scripts/sample3.pl'		or copy( $RealBin . '/res/sample3.pl', $CFG_DIR . '/scripts/' );
-d $CFG_DIR . '/scripts/sample4.pl'		or copy( $RealBin . '/res/sample4.pl', $CFG_DIR . '/scripts/' );

# Start PAC!!
if ( ! ( $PAC = PACMain -> new( @ARGV ) ) ) {
	print STDERR "PAC not starting. PAC already running?\n";
	exit 0
}
$PAC -> start;

print "Finished $Script (PID:$$)...\n";
exit 0;

# END: MAIN program
###################################################################
