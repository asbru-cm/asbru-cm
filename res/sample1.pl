# PAC Script 'sample1.pl'
#
# This PAC Script sample will show you how to:
# - Ask the user *ONCE* for an input (you do that by writting code OUT of both SESSION and CONNECTION
#   subroutines
# - Start some connections (or die if they don't exists)
# - Start some connection forcing it to not use saved data to login
#  . Decide which command prompt matches better, depending on which connection we are currently executing
#  . Depending on the connection, do a manual login, asking user for password input if necessary
#  . Exec some command
#  . Retrieve previous' command output (with 'expect')
#  . Use command output as input for a Perl standard code

our ( %COMMON, %PAC, %TERMINAL, %SHARED );

sub SESSION
{
	# Use the %SHARED hash to ask for user input, in order to use that info in CONNECTIONS subroutine
	$SHARED{cmd} = $COMMON{subst}( "<ASK:Command to send|ls -lF|df -h|uptime|date>" );
	
	# We're going to start some sessions, so, make some GUI advice to the user
	$PAC{msg}( "Starting connections\nPlease, wait..." );
	
	# Start 'connection1'
	my ( $uuid1, $tmp_uuid1 ) = $PAC{start_manual}( 'localhost' );
	if ( ! $uuid1 ) {
		# If that connection does not exist, show a message and finish
		$PAC{msg}( "'localhost' not found!", 1 );
		return 0;
	}
	
	# Start 'connection2'
	my ( $uuid2, $tmp_uuid2 ) = $PAC{start}( 'connection2' );
	if ( ! $uuid2 ) {
		# If that connection does not exist, show a message
		$PAC{msg}( "'connection2' not found!", 1 );
	}
	
	# Alse, start 'connection3', but do not attempt an automatic login
	my ( $uuid3, $tmp_uuid3 ) = $PAC{start_manual}( 'connection3' );
	if ( ! $uuid3 ) {
		# If that connection does not exist, show a message
		$PAC{msg}( "'connection3' not found!", 1 );
	}
	
	# Sessions have been established, finish the advice (close the GUI dialog)
	$PAC{msg}();
	
	return 1;
}

sub CONNECTION
{
	# Prepare a good prompt pattern (Perl Regular Expresion, see 'perldoc perlre') depending on every connection where we get executed
	my $prompt;
	if ( $TERMINAL{name} eq 'connection1' ) {
		$prompt = '\[david@connection1 ~\]';
	}
	elsif ( $TERMINAL{name} eq 'connection2' ) {
		$prompt = '\[root@connection2 .+\]';
	}
	elsif ( $TERMINAL{name} eq 'localhost' ) {
		$prompt = '\[david@david-laptop ~\]';
	}
	
	# Remember the '$PAC{start_manual}( 'connection3' )' command? Now we have to deal with 'connection3' login
	if ( $TERMINAL{name} eq 'localhost' ) {
		$TERMINAL{send}( "password3\n" );
		if ( ! $TERMINAL{expect}( $prompt, 2 ) )
		{
			$TERMINAL{msg}( "Wrong password provided. Asking for one..." );
			$TERMINAL{send}( $TERMINAL{ask}( "Enter Password for $TERMINAL{name}...", 0 ) . "\n" );
		}
		if ( ! $TERMINAL{expect}( $prompt, 2 ) )
		{
			$TERMINAL{msg}( "2nd Wrong password provided. Finishing..." );
			return 0;
		}
	}
	
	# Send user defined '$SHARED{cmd}' (retrieved in SESSION) command to check for used/available space on all 3 connections
	# If we wanted to ask for different user input for *every* connection, we would simply do:
	# my $cmd = $COMMON{subst}( "<ASK:Command to send|ls -laF|df -h|uptime|date>" );
	# $TERMINAL{send}( "$cmd\n" );
	$TERMINAL{send}( "$SHARED{cmd}\n" );
	
	# Now, wait for command prompt, in order to retrive the user defined '$cmd' command output
	$TERMINAL{expect}( $prompt, 2 ) or $TERMINAL{msg}( "Error3: $TERMINAL{error}" );
	
	# Check to see if we got any output from the previous command ($cmd)
	if ( ! defined $TERMINAL{out1} ) {
		$TERMINAL{msg}( "Could not capture command output (check if '\$prompt' variable ($prompt) matches real prompt)" );
		return 0;
	}
	
	# Finally, save all 3 connections output to a file
	if ( ! open( F, '>>/tmp/sample1.txt' ) ) {
		$TERMINAL{msg}( "Could not open file '/tmp/sample1.txt' for writting: $!" );
	}
	print F "**** CONNECTION '$TERMINAL{name}' OUTPUT:\n";
	print F $TERMINAL{out1} . "\n";
	close F;
	
	return 1;
}

return 1;