# PAC Script 'sample2.pl'
#
# This PAC Script sample will show you how to:
# - Mark every opened connection to execute this script
# - Foreach connection (&CONNECTION is executed on *every* previously selected connection):
#  . Decide which command prompt matches better, depending on which connection we are currently executing
#  . Show a GUI popup for the user to choose a command to execute; and execute it.
#  . Retrieve previous' command output (with 'expect')
#  . Use command output as input for a local command

use strict;		# I like it... and you should like it! :P
use warnings;	# Even better

# We *mandatory* declare (as 'our' or 'local') next three PAC inherited vars
our ( %COMMON, %PAC, %TERMINAL, %SHARED );

sub SESSION
{
	# Select every user-started connection (we're not going to open any by ourselves, but use EVERY already opened)
	my $list = $PAC{select}( '*ALL*' );
	if ( ! scalar( keys %{ $list } ) ) {
		$PAC{msg}( "ERROR: There are no open connections to launch 'sample2.pl'", 1 );
		return 0;
	}
	
	# Detach from TABs every selected connection (if not already windowed)
	foreach my $tmp_uuid ( keys %{ $list } ) { $PAC{to_window}( $tmp_uuid ); }
	
	return 1;
}

sub CONNECTION
{
	# Prepare a good prompt pattern (Perl Regular Expresion, see 'perldoc perlre') depending on every connection where we get executed
	my $prompt;
	if ( $TERMINAL{name} eq 'connection1' ) {
		$prompt = '\[david@localhost .+\]';
	}
	else {
		$prompt = 'manager@webservices';
	}
	
	# Ask the user for some command to execute, and finish script if no option is selected
	my $cmd = $COMMON{subst}( "<ASK:Command to send to '$TERMINAL{name}'|ls -laF|df -h|uptime|date>" ) // return 0;
	
	# Send same command to every selected connections
	$TERMINAL{send}( "$cmd\n" );
	
	# Now, wait for command prompt, in order to retrive the 'uptime' command output
	$TERMINAL{expect}( $prompt, 2 ) or $TERMINAL{msg}( "Error: $TERMINAL{error}" );
	
	# Check to see if we got any output from the previous command (uptime)
	if ( ! defined $TERMINAL{out1} ) {
		$TERMINAL{msg}( $TERMINAL{error} );
		$TERMINAL{msg}( "Could not capture command output (check if '\$prompt' variable ($prompt) matches real prompt)" );
		return 0;
	}
	
	# Remove ESCape sequences (mainly used for colouring output)
	my $out = $COMMON{del_esc}( $TERMINAL{out1} );
	
	# Use local system 'echo' to write output to a file (this system call is *blocking*)
	system( "echo \"$out\" > $TERMINAL{name}.uptime" );
	
	# Finally, start a program in OUR PC with captured output (in background '&', so it is non-blocking)
	system( "gedit --new-document $TERMINAL{name}.uptime &" );
	
	return 1;
}

return 1;