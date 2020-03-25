#!/usr/bin/perl

use utf8;
binmode STDOUT,':utf8';
binmode STDERR,':utf8';

if (!$ARGV[0]) {
	print "usage : perl anonymize.pl myfile.yml";
}

cleanUpPersonalData($ARGV[0]);

sub cleanUpPersonalData {
	my $file = shift;
	my $out = 'debug.yml';

	$SIG{__WARN__} = sub{};
	print STDERR "SAVED IN : $file\nOUT: $out\n";
	# Remove all personal information
	open(F,"<:utf8",$file);
	open(D,">:utf8",$out);
	my $C = 0;
	while (my $line = <F>) {
		my $next = 0;
		foreach my $key ('name','send','ip','user','prepend command','database','gui password','sudo password') {
			if ($line =~ /^[\t ]+$key:/) {
				$line =~ s/$key:.+/$key: 'removed'/;
				$next = 1;
			}
			if ($next) {
				next;
			}
		}
		if ($line =~ /KPX title regexp/) {
			$line =~ s/KPX title regexp:.+/KPX title regexp: ''/;
		} elsif ($line =~ /^[\t ]+(title|name):/) {
			my $p = $1;
			if ($p eq 'name') {
				$C++;
			}
			$line =~ s/$p:.+/$p: '$p $C'/;
		} elsif (($line =~ /^[\t ]+(global variables|remote commands|local commands|expect|local before|local after|local connected):/) && ($line !~ /^[\t ]+(global variables|remote commands|local commands|expect|local before|local after|local connected): \[\]/)) {
			my $global = 0;
			my $indent = '';
			if ($line =~ /global variables/) {
				$global = 1;
			}
			if ($line =~ /^([\t ]+)/) {
				$indent = $1;
			}
			print D $line;
			while (my $l = <F>) {
				if ($l =~ /^${indent}\w/) {
					print D $l;
					last;
				} elsif ($global) {
					next;
				} elsif ($l =~ /description|expect|send|txt/) {
					$l =~ s|(.+?):.+|$1: 'removed'|;
				}
				print D $l;
			}
			next;
		} elsif ($line =~ /^[\t ]+options:/) {
			$line =~ s/\/drive:.+?( |\')/\/drive: removed$1/;
			$line =~ s/ disk:.+?( |\')/ disk: removed$1/;
			$line =~ s/\/d:.+?( |\')/\/d: removed$1/;
			$line =~ s/-d .+?( |\')/-d removed$1/;
			if ($line =~ / -(D|L|R)/) {
				$line =~ s/(^[\t ]+options):.+/$1: 'removed'/;
			}
		} elsif (($line =~ /^[\t ]+proxy (ip|pass|user):/)&&($line !~ /^[\t ]+proxy (ip|pass|user): \'\'/)) {
			$line =~ s/(proxy.+?):.+/$1: 'removed'/;
		} elsif (($line =~ /^[\t ]+jump (config|ip|pass|user|key):/)&&($line !~ /^[\t ]+jump (config|ip|pass|user|key): \'\'/)) {
			$line =~ s/(jump.+?):.+/$1: 'removed'/;
		} elsif ($line =~ /^[\t ]+description:/) {
			$line =~ s/description:.+/description: 'Description'/;
		} elsif ($line =~ /^[\t ]+public key: (.+)/) {
			$line =~ s/public key:.+/public key: 'uses public key'/;
		} elsif ($line =~ /^[\t ]+pass(word|phrase)?:/) {
			$line =~ s/pass(word|phrase)?:.+/pass$1: 'removed'/;
		} elsif ($line =~ /^[\t ]+use gui password( tray)?:/) {
			$line =~ s/use gui password( tray)?:.+/use gui password$1: \'\'/;
		} elsif ($line =~ /^[\t ]+passphrase user:/) {
			$line =~ s/passphrase user:.+/passphrase user: 'removed'/;
		}
		$line =~ s|/home/.+?/|/home/PATH/|;
		$line =~ s|$ENV{USER}|USER|;
		print D $line;
	}
	# Add runtime information
	print D "\n\n#$APPNAME : $APPVERSION\n\n# ENV Data\n";
	my $user = $ENV{USER} ? $ENV{USER} : $ENV{LOGNAME};
	foreach my $k (sort keys %ENV) {
		if ($k =~ /token|hostname|startup|KPXC|AUTH/i) {
			next;
		}
		my $str = $ENV{$k};
		$str =~ s|$user|USER|g;
		print D "#$k : $str\n";
	}
	print D "\n\n";
	close F;
	close D;
	unlink $file;
	return $out;
}
