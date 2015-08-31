# PAC Script 'sample4.pl'
#
# This PAC Script sample will show you how to:
# - start some sessions
# - launch some commands and retrieve their output, all at once

our ( %COMMON, %PAC, %TERMINAL, %SHARED );

sub SESSION
{
	# Select every user-started connection (we're not going to open any by ourselves, but use EVERY already opened)
	my $list = $PAC{select}( '*ALL*' );
	if ( ! scalar( keys %{ $list } ) ) {
		$PAC{msg}( "ERROR: There are no open connections to launch 'sample4.pl'", 1 );
		return 0;
	}
	
	return 1;
}

sub CONNECTION
{
	# Prepare a good prompt pattern (Perl Regular Expresion, see 'perldoc perlre') depending on every connection where we get executed
	my $prompt;
	if ( $TERMINAL{name} eq 'localhost' ) {
		$prompt = '\[david@david-laptop ~\]';
	}
	else {
		$prompt = 'whatever_prompt_this_connection_may_have';
	}
	
	# It's always a *GOOD* idea to start the scripts by EXPECting a regular command prompt IF the connection was
	# started by us (the script). Other else, you should not need to make any initial expect.
	#$TERMINAL{expect}( $prompt, 5 ) or $TERMINAL{msg}( "Error: $TERMINAL{error}" );
	
	# Send same command to every selected connections, and retrieve it's output
	my $out = $TERMINAL{send_get}( "ls -laF /tmp" );
	# $out has been automatically applied the removal of ESCape sequences
	
	# Check to see if we got any output from the previous command
	if ( ! defined $out ) {
		$TERMINAL{msg}( $TERMINAL{error} );
		$TERMINAL{msg}( "Could not capture command output (check if '\$prompt' variable ($prompt) matches real prompt)" );
		return 0;
	}
	
	# Use local system 'echo' to write output to a file (this system call is *blocking*)
	system( "echo \"$out\" > /tmp/$TERMINAL{name}.command" );
	
	# Finally, start a program in OUR PC with captured output (in background '&', so it is non-blocking)
	system( "nohup gedit --new-document /tmp/$TERMINAL{name}.command &" );
	
	return 1;
}

return 1;