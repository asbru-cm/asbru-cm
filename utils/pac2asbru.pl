#!/usr/bin/perl

use strict;
use utf8;
binmode STDOUT,":utf8";
binmode STDERR,':utf8';

use FindBin qw ($RealBin $Bin $Script);
use lib "$RealBin/lib", "$RealBin/lib/ex", "$RealBin/lib/edit";

our $VERBOSE        = $ARGV[2];
our $CFG_DIR        = $ENV{"ASBRU_CFG"};
our $BACKUP_DIR     = "bak";
our $CFG_FILE_NAME  = "asbru.yml";

if ($VERBOSE) {
	print STDERR "INFO: Executing migration from PAC to Ásbrú\n";
	print STDERR "INFO: $ARGV[0] , $ARGV[1]\n";
	print STDERR "INFO: RealBin = $RealBin\n";
}

if (!$ARGV[0] || !$ARGV[1]) {
	print STDERR "INFO: Migration aborted missing directories\n";
	exit 1;
}

migrate($ARGV[0],$ARGV[1]);

exit 0;

sub migrate {
	my ($old_dir,$new_dir) = @_;
	my ($ss);

	if ($VERBOSE) {print "INFO:MIGRATION Messages\n";}
	my $resp = _wPopUP('Confirm',setMessage("$old_dir.old"));
	if ($resp ne 'OK') {
		if ($resp eq 'NOT AVAILABLE') {
			print "WARN: Continue without gtk3 warning\n";
		} else {
			print "WARN: Ásbru migration aborted\n";
			if ($old_dir =~ /\.migration/) {
				# Fix non standard config dir back to how it was
				if ($VERBOSE) {print "  - Recover none standard directory $old_dir -> $new_dir\n";}
				system "mv -f $old_dir $new_dir";
			}
			exit 1;
		}
	}
	if (-e $new_dir) {
		if ($VERBOSE) {print "  - $new_dir exists, we should not be here\n";}
		# Migrate only once
		return 0;
	}
	if (!-e "$old_dir.old") {
		# Write only once to avoid a disaster if user has moved things manually and this is rerun
		if ($VERBOSE) {print "  - Creating back up directory : $old_dir.old\n";}
		system "cp -rfp $old_dir $old_dir.old";
	}
	if ($VERBOSE) {print "  - Create $new_dir\n";}
	system "mv $old_dir $new_dir";
	foreach my $f ('pac.yml','pac_notray.notified','pac.pcc',,'pac.yml.gui','pac.yml.tree','pac_start.desktop','pac.dumper') {
		my $n = $f;
		$n =~ s/pac/asbru/;
		if (-e "$new_dir/$f") {
			if ($VERBOSE) {print "  - move $f -> $n\n";}
			system "mv -f $new_dir/$f $new_dir/$n";
		}
	}
	foreach my $f ('pac_start.desktop') {
		my $n = $f;
		$n =~ s/pac/asbru/;
		if (-e "$new_dir/autostart/$f") {
			if ($VERBOSE) {print "  - mv $f -> $n\n";}
			system "mv -f $new_dir/autostart/$f $new_dir/autostart/$n";
		}
	}
	# Rename BackUps
	my $BACKUP_CFG_FILE  = "$CFG_DIR/$BACKUP_DIR/pac.yml";
	if ($VERBOSE) {print "  - Move backups\n";}
	for (my $n=0; $n < 10; $n++) {
		if (-e "$BACKUP_CFG_FILE.$n") {
			system "mv -f $BACKUP_CFG_FILE.$n $CFG_DIR/$BACKUP_DIR/$CFG_FILE_NAME.$n";
		}
	}
	# Rename screenshost
	if ($VERBOSE) {print "  - Rename screenshots\n";}
	opendir($ss,"$new_dir/screenshots");
	while (my $f = readdir($ss)) {
		if ($f =~ /\.png/) {
			my $n = $f;
			$n =~ s/pac/asbru/;
			system "mv -f $new_dir/screenshots/$f $new_dir/screenshots/$n";
		}
	}
	# Process pac.yml
	if ($VERBOSE) {print "  - Fix paths in asbru.yml\n";}
	open(YMLO,"<:utf8","$new_dir/asbru.yml");
	open(YMLN,">:utf8","$new_dir/asbru.yml.new");
	while (my $l = <YMLO>) {
		if ($l =~ m|$old_dir|) {
			$l =~ s|$old_dir|$new_dir|;
		} elsif ($l =~ /pac_/) {
			$l =~ s|pac_|asbru_|g;
		}
		print YMLN $l;
	}
	close YMLO;
	close YMLN;
	system "mv -f $new_dir/asbru.yml.new $new_dir/asbru.yml";
	# Remove nfreeze
	if ($VERBOSE) {print "  - Remove nfreeze files to be recreated\n";}
	system "rm -f $new_dir/*.nfreeze";
	return 0;

	# Set warning message, do not worrie about tabs, spaces at the beggining
	# Pango markup is OK
	sub setMessage {
		my $dir = shift;
		my $msg = qq”This Version will migrate your configuration file.

		A backup copy of your original configuration will be created at : <b>$dir</b>

		You can downgrade from your package manager if the migration fails.

		You may <b>Cancel</b> now, and run in terminal : <b><i>asbru-cm --verbose</i></b>
		To see detailed messages of the migration process.

		Or <b>Continue</b> to start Ásbrú now.
		”;
	}
}

sub _wPopUP {
	my ($type,$msg) = @_;
	my $PATH = "$RealBin/";

	$msg =~ s/\t//mg;
	$msg =~ s/^ +//mg;
	$msg =~ s/\n/&cr;/g;
	$msg =~ s/\"/&dquot;/g;
	$msg =~ s/\'/&squot;/g;
	return `$PATH/asbru_confirm.pl '$type' '$msg' `;
}

