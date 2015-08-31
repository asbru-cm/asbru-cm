# PAC Script 'sample3.pl'
#
# This PAC Script sample will show you how to:
# - retrieve PAC's configuration (both a copy and a reference!)
# - lookup/modify config values
# - save a copy of PAC's config
# ... imagine the potential!!
# (may be.. *someone* could create something like a configuration importer... or something like that... ;)

our ( %COMMON, %PAC, %TERMINAL, %SHARED );

sub SESSION
{
	# We're going to start some sessions, so, make some GUI advice to the user
	$PAC{msg}( "Modifying PAC configuration.\nPlease, wait..." );
	
	# Retrieve a COPY of PAC's configuration
	my $copy_cfg = $COMMON{cfg}();
	# Retrieve a REFERENCE (CAUTION!! VERY DANGEROUS!!) to PAC's configuration
	# This allows you to change PAC config in REAL-TIME
	my $cfg = $COMMON{cfg}( 1 );
	
	#use Data::Dumper;
	#print Dumper( $$copy_cfg{defaults} );
	#print Dumper( $$copy_cfg{environments} );
	
	# Now, modifying $cfg, will result in a modification of PAC's configuration! (non persistent, unles you press "Save"
	# on PAC's main GUI)
	$$copy_cfg{defaults}{'tree on right side'} = 1;
	
	# Export current modified PAC configuration to file /tmp/my_pac_config_file.yml (YAML format is mandatory)
	$PAC{msg}( "Saving PAC configuration.\nPlease, wait..." );
	my $file = $PAC{cfg_export}( '/tmp/my_pac_config_file.yml' );
	
	# Now, restore PAC's original configuration
	$cfg = $copy_cfg;
	
	# Sessions have been established, finish the advice (close the GUI dialog)
	$PAC{msg}( "PAC Script finished (saved file '$file')", 1 );
	
	return 1;
}

return 1;