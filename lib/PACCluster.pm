package PACCluster;

###################################################################
# This file is part of PAC( Perl Auto Connector)
#
# Copyright (C) 2010-2014  David Torrejon Vaquerizas
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

use FindBin qw ( $RealBin $Bin $Script );
use lib $RealBin . '/lib', $RealBin . '/lib/ex';

# Standard
use strict;
use warnings;
use Storable qw ( dclone );
use Encode;

# GTK2
use Gtk2 '-init';
use Gtk2::Ex::Simple::List;

# PAC modules
use PACUtils;
use PACPCC;

# END: Import Modules
###################################################################

###################################################################
# Define GLOBAL CLASS variables

my $APPNAME			= $PACUtils::APPNAME;
my $APPVERSION		= $PACUtils::APPVERSION;

my $CFG_DIR			= $ENV{'HOME'} . '/.config/pac';
my $CLUSTERS_FILE	= $CFG_DIR . '/pac_clusters.nfreeze';
my $GROUPICONCLOSED	= _pixBufFromFile( $RealBin . '/res/pac_group_closed_16x16.png' );
my $GROUPICON_ROOT	= _pixBufFromFile( $RealBin . '/res/pac_group.png' );
my $AUTOCLUSTERICON	= _pixBufFromFile( $RealBin . '/res/pac_cluster_auto.png' );
my $ICON_ON			= Gtk2::Gdk::Pixbuf -> new_from_file_at_scale( $RealBin . '/res/pac_terminal16x16.png', 16, 16, 0 );
my $ICON_OFF		= Gtk2::Gdk::Pixbuf -> new_from_file_at_scale( $RealBin . '/res/pac_terminal_x16x16.png', 16, 16, 0 );
my $BANNER			= Gtk2::Image -> new_from_file( $RealBin . '/res/pac_banner_cluster.png' );
# END: Define GLOBAL CLASS variables
###################################################################

###################################################################
# START: Define PUBLIC CLASS methods

sub new {
	my $class	= shift;
	my $self	= {};
	
	$self	-> {_RUNNING}		= shift;
	
	$self	-> {_CLUSTERS}		= undef;
	$self	-> {CLUSTERS}		= undef;
	$self	-> {_WINDOWCLUSTER}	= undef;
	$self	-> {_UPDATING}		= 0;
	
	# Build the GUI
	_initGUI( $self ) or return 0;

	# Setup callbacks
	_setupCallbacks( $self );
	
	bless( $self, $class );
	return $self;
}

# DESTRUCTOR
sub DESTROY {
	my $self = shift;
	undef $self;
	return 1;
}

# Show GUI
sub show {
	my $self	= shift;
	my $cluster	= shift // 0;
	
	$$self{_WINDOWCLUSTER}{main} -> set_title( "Cluster Administration : $APPNAME (v$APPVERSION)" );
	$$self{_WINDOWCLUSTER}{main} -> set_position( 'center' );
	$$self{_WINDOWCLUSTER}{main} -> show_all;
	$$self{_WINDOWCLUSTER}{main} -> present;
	
	$$self{_WINDOWCLUSTER}{treeTerminals} -> grab_focus;
	$$self{_WINDOWCLUSTER}{treeTerminals} -> select( 0 );
	
	$self -> _updateGUI;
	$self -> _updateGUI1( $cluster );
	$self -> _updateGUIAC( $cluster );
	my $page = 0;
	if		( ! $cluster )																	{ $page = 0; }
	elsif	( defined $PACMain::FUNCS{_MAIN}{_CFG}{defaults}{'auto cluster'}{$cluster} )	{ $page = 2 }
	else																					{ $page = 1; }
	$$self{_WINDOWCLUSTER}{nb} -> set_current_page( $page );
	
	return 1;
}

# END: Define PUBLIC CLASS methods
###################################################################

###################################################################
# START: Define PRIVATE CLASS functions

sub _loadTreeConfiguration {
	my $self	= shift;
	my $tree	= shift // $$self{_WINDOWCLUSTER}{treeConnections};
	
	@{ $$self{_WINDOWCLUSTER}{treeConnections}{'data'} } = ( {
		value		=> [ $GROUPICON_ROOT, '<b>AVAILABLE CONNECTIONS</b>', '__PAC__ROOT__' ],
		children	=> []
	} );
	foreach my $child ( keys %{ $PACMain::{FUNCS}{_MAIN}{_CFG}{environments}{'__PAC__ROOT__'}{children} } ) { push( @{ $$tree{data} }, $self -> __recurLoadTree( $child ) );}
	
	# Select the root path
	$tree -> set_cursor( Gtk2::TreePath -> new_from_string( '0' ) );
	
	return 1;
}

sub __recurLoadTree {
	my $self = shift;
	my $uuid = shift;
	
	my $node_name = $PACMain::{FUNCS}{_MAIN} -> __treeBuildNodeName( $uuid );
	my @list;
	
	if ( ! $PACMain::{FUNCS}{_MAIN}{_CFG}{environments}{$uuid}{'_is_group'} ) {
		push( @list, {
			value		=> [ $PACMain::{FUNCS}{_MAIN}{_METHODS}{ $PACMain::{FUNCS}{_MAIN}{_CFG}{'environments'}{$uuid}{'method'} }{'icon'}, $node_name, $uuid ],
			children	=> []
		} );
	} else {
		my @clist;
		foreach my $child ( keys %{ $PACMain::{FUNCS}{_MAIN}{_CFG}{environments}{$uuid}{children} } ) {
			push( @clist, $self -> __recurLoadTree( $child ) );
		}
		push( @list, {
			value		=> [ $GROUPICONCLOSED, $node_name, $uuid ],
			children	=> \@clist
		} );
	}
	return @list;
}	

sub __treeSort {
	my ( $treestore, $a_iter, $b_iter ) = @_;
	my $cfg = $PACMain::{FUNCS}{_MAIN}{_CFG};
	my $groups_1st	= $$cfg{'defaults'}{'sort groups first'} // 1;
	
	my $b_uuid		= $treestore -> get_value( $b_iter, 2 );
	return 0 unless defined $b_uuid;
	# __PAC__ROOT__ must always be the first node!!
	$b_uuid eq '__PAC__ROOT__' and return 1;
	
	my $a_uuid		= $treestore -> get_value( $a_iter, 2 );
	return 1 unless defined $a_uuid;
	# __PAC__ROOT__ must always be the first node!!
	$a_uuid eq '__PAC__ROOT__' and return -1;
	
	# Groups first...
	if ( $groups_1st ) {
		my $a_is_group	= $$cfg{'environments'}{ $a_uuid }{'_is_group'};
		my $b_is_group	= $$cfg{'environments'}{ $b_uuid }{'_is_group'};
		
		( $a_is_group && ! $b_is_group ) and return -1;
		( ! $a_is_group && $b_is_group ) and return 1;
	}
	
	# ... then alphabetically
	return lc( $$cfg{'environments'}{$a_uuid}{name} ) cmp lc( $$cfg{'environments'}{$b_uuid}{name} );
}

sub _initGUI {
	my $self = shift;
	
	$$self{_WINDOWCLUSTER}{main} = Gtk2::Window -> new;
	$$self{_WINDOWCLUSTER}{main} -> set_position( 'center' );
	$$self{_WINDOWCLUSTER}{main} -> set_icon_name( 'pac-app-big' );
	$$self{_WINDOWCLUSTER}{main} -> set_size_request( 650, 500 );
	$$self{_WINDOWCLUSTER}{main} -> set_default_size( 650, 500 );
	$$self{_WINDOWCLUSTER}{main} -> set_resizable( 1 );
	$$self{_WINDOWCLUSTER}{main} -> set_transient_for( $PACMain::FUNCS{_MAIN}{_GUI}{main} );
	$$self{_WINDOWCLUSTER}{main} -> set_modal( 1 );
		
		my $vbox0 = Gtk2::VBox -> new( 0, 0 );
		$$self{_WINDOWCLUSTER}{main} -> add( $vbox0 );
			
			$vbox0 -> pack_start( $BANNER , 0, 1, 0 );
			
			# Create a notebook widget
			$$self{_WINDOWCLUSTER}{nb} = Gtk2::Notebook -> new;
			$$self{_WINDOWCLUSTER}{nb} -> set_scrollable( 1 );
			$$self{_WINDOWCLUSTER}{nb} -> set_tab_pos( 'right' );
			$$self{_WINDOWCLUSTER}{nb} -> set( 'homogeneous', 1 );
			$vbox0 -> pack_start( $$self{_WINDOWCLUSTER}{nb}, 1, 1, 0 );
				
				my $tablbl1 = Gtk2::HBox -> new( 0, 0 );
					my $lbl1 = Gtk2::Label -> new;
					$lbl1 -> set_markup( '<b>RUNNING CLUSTERS </b>' );
					$tablbl1 -> pack_start( $lbl1, 0, 1, 0 );
					$tablbl1 -> pack_start( Gtk2::Image -> new_from_stock( 'pac-terminal-ok-small', 'menu' ), 0, 1, 0 );
				$tablbl1 -> show_all;
				
				my $vbox1 = Gtk2::VBox -> new( 0, 0 );
				$$self{_WINDOWCLUSTER}{nb} -> append_page( $vbox1, $tablbl1 );
				
				my $hbox1 = Gtk2::HBox -> new( 0, 0 );
				$vbox1 -> pack_start( $hbox1, 1, 1, 0 );
					
					my $frame0 = Gtk2::Frame -> new( ' UNCLUSTERED TERMINALS: ' );
					$hbox1 -> pack_start( $frame0, 1, 1, 0 );
					my $frame0lbl = Gtk2::Label -> new;
					$frame0lbl -> set_markup( ' <b>UNCLUSTERED TERMINALS:</b> ' );
					$frame0 -> set_label_widget( $frame0lbl );
						
						# Terminals list
						my $scroll1 = Gtk2::ScrolledWindow -> new;
						$frame0 -> add( $scroll1 );
						$scroll1 -> set_policy( 'automatic', 'automatic' );
							
							$$self{_WINDOWCLUSTER}{treeTerminals} = Gtk2::Ex::Simple::List -> new_from_treeview (
								Gtk2::TreeView -> new,
								'Opened Terminal(s):'	=> 'text',
								'UUID:'					=> 'hidden',
								'Status'				=> 'pixbuf'
							);
								
								$scroll1 -> add( $$self{_WINDOWCLUSTER}{treeTerminals} );
								$$self{_WINDOWCLUSTER}{treeTerminals} -> set_tooltip_text( 'List of available-unclustered connections' );
								$$self{_WINDOWCLUSTER}{treeTerminals} -> set_headers_visible( 0 );
								$$self{_WINDOWCLUSTER}{treeTerminals} -> get_selection -> set_mode( 'GTK_SELECTION_MULTIPLE' );
								my @col_terminals = $$self{_WINDOWCLUSTER}{treeTerminals} -> get_columns;
								$col_terminals[0] -> set_expand( 1 );
								$col_terminals[1] -> set_expand( 0 );
					
					# Buttons to Add/Del to/from Clusters
					my $vbox2 = Gtk2::VBox -> new( 0, 0 );
					$hbox1 -> pack_start( $vbox2, 0, 1, 0 );
						
						$$self{_WINDOWCLUSTER}{btnadd} = Gtk2::Button -> new_with_label( "Add to\nCluster" );
						$vbox2 -> pack_start( $$self{_WINDOWCLUSTER}{btnadd}, 1, 1, 0 );
						$$self{_WINDOWCLUSTER}{btnadd} -> set_image( Gtk2::Image -> new_from_stock( 'gtk-go-forward', 'GTK_ICON_SIZE_BUTTON' ) );
						$$self{_WINDOWCLUSTER}{btnadd} -> set_image_position( 'GTK_POS_BOTTOM' );
						$$self{_WINDOWCLUSTER}{btnadd} -> set_relief( 'GTK_RELIEF_NONE' );
						$$self{_WINDOWCLUSTER}{btnadd} -> set_sensitive( 0 );
						
						$$self{_WINDOWCLUSTER}{btndel} = Gtk2::Button -> new_with_label( "Del from\nCluster" );
						$vbox2 -> pack_start( $$self{_WINDOWCLUSTER}{btndel}, 1, 1, 0 );
						$$self{_WINDOWCLUSTER}{btndel} -> set_image( Gtk2::Image -> new_from_stock( 'gtk-go-back', 'GTK_ICON_SIZE_BUTTON' ) );
						$$self{_WINDOWCLUSTER}{btndel} -> set_image_position( 'GTK_POS_TOP' );
						$$self{_WINDOWCLUSTER}{btndel} -> set_relief( 'GTK_RELIEF_NONE' );
						$$self{_WINDOWCLUSTER}{btndel} -> set_sensitive( 0 );
					
					# Clusters list
					my $vbox3 = Gtk2::VBox -> new( 0, 0 );
					$hbox1 -> pack_start( $vbox3, 1, 1, 0 );
						
						my $frame1 = Gtk2::Frame -> new( ' ACTIVE CLUSTERS: ' );
						$vbox3 -> pack_start( $frame1, 0, 1, 0 );
						my $frame1lbl = Gtk2::Label -> new();
						$frame1lbl -> set_markup( ' <b>ACTIVE CLUSTERS:</b> ' );
						$frame1 -> set_label_widget( $frame1lbl );
							
							my $vbox4 = Gtk2::VBox -> new( 0, 0 );
							$frame1 -> add( $vbox4 );
								
								$$self{_WINDOWCLUSTER}{comboClusters} = Gtk2::ComboBox -> new_text();
								$vbox4 -> pack_start( $$self{_WINDOWCLUSTER}{comboClusters}, 0, 1, 0 );
								
								my $sep1 = Gtk2::HSeparator -> new;
								$vbox4 -> pack_start( $sep1, 0, 1, 5 );
								
								my $hbuttonbox1 = Gtk2::HButtonBox -> new();
								$vbox4 -> pack_start( $hbuttonbox1, 0, 1, 0 );
								$hbuttonbox1 -> set_layout( 'GTK_BUTTONBOX_EDGE' );
								$hbuttonbox1 -> set_homogeneous( 1 );
									
									$$self{_WINDOWCLUSTER}{addCluster} = Gtk2::Button -> new_from_stock( 'gtk-add' );
									$hbuttonbox1 -> add( $$self{_WINDOWCLUSTER}{addCluster} );
									$$self{_WINDOWCLUSTER}{addCluster} -> set( 'can-focus' => 0 );
									
									$$self{_WINDOWCLUSTER}{delCluster} = Gtk2::Button -> new_from_stock( 'gtk-delete' );
									$hbuttonbox1 -> add( $$self{_WINDOWCLUSTER}{delCluster} );
									$$self{_WINDOWCLUSTER}{delCluster} -> set( 'can-focus' => 0 );
									$$self{_WINDOWCLUSTER}{delCluster} -> set_sensitive( 0 );
									
						my $frame2 = Gtk2::Frame -> new( ' TERMINALS: ' );
						$vbox3 -> pack_start( $frame2, 1, 1, 0 );
						my $frame2lbl = Gtk2::Label -> new();
						$frame2lbl -> set_markup( ' <b>TERMINALS IN SELECTED CLUSTER:</b> ' );
						$frame2 -> set_label_widget( $frame2lbl );
							
							my $vbox5 = Gtk2::VBox -> new( 0, 0 );
							$frame2 -> add( $vbox5 );
								
								my $scroll2 = Gtk2::ScrolledWindow -> new;
								$vbox5 -> pack_start( $scroll2, 1, 1, 0 );
								$scroll2 -> set_policy( 'automatic', 'automatic' );
									
									$$self{_WINDOWCLUSTER}{treeClustered} = Gtk2::Ex::Simple::List -> new_from_treeview (
										Gtk2::TreeView -> new,
										'Terminal(s) in cluster:'	=> 'text',
										'UUID:'						=> 'hidden',
										'Status'					=> 'pixbuf'
									);
									$scroll2 -> add( $$self{_WINDOWCLUSTER}{treeClustered} );
									$$self{_WINDOWCLUSTER}{treeClustered} -> set_headers_visible( 0 );
									$$self{_WINDOWCLUSTER}{treeClustered} -> set_tooltip_text( 'List of connections included in the selected cluster above' );
									$$self{_WINDOWCLUSTER}{treeClustered} -> get_selection -> set_mode( 'GTK_SELECTION_MULTIPLE' );
									$$self{_WINDOWCLUSTER}{treeClustered} -> get_selection -> set_mode( 'GTK_SELECTION_MULTIPLE' );
									my @col_cluster = $$self{_WINDOWCLUSTER}{treeClustered} -> get_columns;
									$col_cluster[0] -> set_expand( 1 );
									$col_cluster[1] -> set_expand( 0 );
				
				my $tablbl2 = Gtk2::HBox -> new( 0, 0 );
					my $lbl2 = Gtk2::Label -> new;
					$lbl2 -> set_markup( '<b>SAVED CLUSTERS </b>' );
					$tablbl2 -> pack_start( $lbl2, 0, 1, 0 );
					$tablbl2 -> pack_start( Gtk2::Image -> new_from_stock( 'pac-cluster-manager', 'menu' ), 0, 1, 0 );
				$tablbl2 -> show_all;
				
				my $hboxclu = Gtk2::HBox -> new( 0, 0 );
				$$self{_WINDOWCLUSTER}{nb} -> append_page( $hboxclu, $tablbl2 );
					
					# Create a scrolled1 scrolled window to contain the connections tree
					$$self{_WINDOWCLUSTER}{scrollclu} = Gtk2::ScrolledWindow -> new;
					$$self{_WINDOWCLUSTER}{scrollclu} -> set_policy( 'automatic', 'automatic' );
					$hboxclu -> pack_start( $$self{_WINDOWCLUSTER}{scrollclu}, 1, 1, 0 );
					
					# Create a treeConnections treeview for connections
					$$self{_WINDOWCLUSTER}{treeConnections} = PACTree -> new (
						'Icon:'		=> 'pixbuf',
						'Name:'		=> 'markup',
						'UUID:'		=> 'hidden',
					);
					$$self{_WINDOWCLUSTER}{scrollclu} -> add( $$self{_WINDOWCLUSTER}{treeConnections} );
					$$self{_WINDOWCLUSTER}{treeConnections} -> set_headers_visible( 0 );
					$$self{_WINDOWCLUSTER}{treeConnections} -> set_enable_search( 0 );
						
						# Implement a "TreeModelSort" to auto-sort the data
						my $sort_model_conn = Gtk2::TreeModelSort -> new_with_model( $$self{_WINDOWCLUSTER}{treeConnections} -> get_model );
						$$self{_WINDOWCLUSTER}{treeConnections} -> set_model( $sort_model_conn );
						$sort_model_conn -> set_default_sort_func( \&__treeSort );
						$$self{_WINDOWCLUSTER}{treeConnections} -> get_selection -> set_mode( 'GTK_SELECTION_MULTIPLE' );
						
						@{ $$self{_WINDOWCLUSTER}{treeConnections}{'data'} } = ( {
							value		=> [ $GROUPICON_ROOT, '<b>AVAILABLE CONNECTIONS</b>', '__PAC__ROOT__' ],
							children	=> []
						} );
					
					
					# Buttons to Add/Del to/from Clusters
					my $vboxclu1 = Gtk2::VBox -> new( 0, 0 );
					$hboxclu -> pack_start( $vboxclu1, 0, 1, 0 );
						
						$$self{_WINDOWCLUSTER}{btnadd1} = Gtk2::Button -> new_with_label( "Add to\nCluster" );
						$vboxclu1 -> pack_start( $$self{_WINDOWCLUSTER}{btnadd1}, 1, 1, 0 );
						$$self{_WINDOWCLUSTER}{btnadd1} -> set_image( Gtk2::Image -> new_from_stock( 'gtk-go-forward', 'GTK_ICON_SIZE_BUTTON' ) );
						$$self{_WINDOWCLUSTER}{btnadd1} -> set_image_position( 'GTK_POS_BOTTOM' );
						$$self{_WINDOWCLUSTER}{btnadd1} -> set_relief( 'GTK_RELIEF_NONE' );
						$$self{_WINDOWCLUSTER}{btnadd1} -> set_sensitive( 0 );
						
						$$self{_WINDOWCLUSTER}{btndel1} = Gtk2::Button -> new_with_label( "Del from\nCluster" );
						$vboxclu1 -> pack_start( $$self{_WINDOWCLUSTER}{btndel1}, 1, 1, 0 );
						$$self{_WINDOWCLUSTER}{btndel1} -> set_image( Gtk2::Image -> new_from_stock( 'gtk-go-back', 'GTK_ICON_SIZE_BUTTON' ) );
						$$self{_WINDOWCLUSTER}{btndel1} -> set_image_position( 'GTK_POS_TOP' );
						$$self{_WINDOWCLUSTER}{btndel1} -> set_relief( 'GTK_RELIEF_NONE' );
						$$self{_WINDOWCLUSTER}{btndel1} -> set_sensitive( 0 );
					
					# Clusters list
					my $vbox3clu = Gtk2::VBox -> new( 0, 0 );
					$hboxclu -> pack_start( $vbox3clu, 0, 1, 0 );
						
						my $frame1clu = Gtk2::Frame -> new( ' CONFIGURED CLUSTERS: ' );
						$vbox3clu -> pack_start( $frame1clu, 0, 1, 0 );
						my $frame1lblclu = Gtk2::Label -> new;
						$frame1lblclu -> set_markup( ' <b>CONFIGURED CLUSTERS:</b> ' );
						$frame1clu -> set_label_widget( $frame1lblclu );
							
							my $vbox4clu = Gtk2::VBox -> new( 0, 0 );
							$frame1clu -> add( $vbox4clu );
								
								$$self{_WINDOWCLUSTER}{comboClusters1} = Gtk2::ComboBox -> new_text;
								$vbox4clu -> pack_start( $$self{_WINDOWCLUSTER}{comboClusters1}, 0, 1, 0 );
								
								$vbox4clu -> pack_start( Gtk2::HSeparator -> new, 0, 1, 5 );
								
								my $hbuttonbox1clu = Gtk2::HButtonBox -> new;
								$vbox4clu -> pack_start( $hbuttonbox1clu, 0, 1, 0 );
								$hbuttonbox1clu -> set_layout( 'GTK_BUTTONBOX_EDGE' );
								$hbuttonbox1clu -> set_homogeneous( 1 );
									
									$$self{_WINDOWCLUSTER}{addCluster1} = Gtk2::Button -> new_from_stock( 'gtk-add' );
									$hbuttonbox1clu -> add( $$self{_WINDOWCLUSTER}{addCluster1} );
									$$self{_WINDOWCLUSTER}{addCluster1} -> set( 'can-focus' => 0 );
									
									$$self{_WINDOWCLUSTER}{renCluster1} = Gtk2::Button -> new;
									$hbuttonbox1clu -> add( $$self{_WINDOWCLUSTER}{renCluster1} );
									$$self{_WINDOWCLUSTER}{renCluster1} -> set_image( Gtk2::Image -> new_from_stock( 'gtk-edit', 'button' ) );
									$$self{_WINDOWCLUSTER}{renCluster1} -> set_label( 'Rename' );
									$$self{_WINDOWCLUSTER}{renCluster1} -> set( 'can-focus' => 0 );
									
									$$self{_WINDOWCLUSTER}{delCluster1} = Gtk2::Button -> new_from_stock( 'gtk-delete' );
									$hbuttonbox1clu -> add( $$self{_WINDOWCLUSTER}{delCluster1} );
									$$self{_WINDOWCLUSTER}{delCluster1} -> set( 'can-focus' => 0 );
									$$self{_WINDOWCLUSTER}{delCluster1} -> set_sensitive( 0 );
						
						my $frame2clu = Gtk2::Frame -> new( ' TERMINALS: ' );
						$vbox3clu -> pack_start( $frame2clu, 1, 1, 0 );
						my $frame2lblclu = Gtk2::Label -> new;
						$frame2lblclu -> set_markup( ' <b>TERMINALS IN SELECTED CLUSTER:</b> ' );
						$frame2clu -> set_label_widget( $frame2lblclu );
							
							my $vbox5clu = Gtk2::VBox -> new( 0, 0 );
							$frame2clu -> add( $vbox5clu );
								
								my $scroll2clu = Gtk2::ScrolledWindow -> new;
								$vbox5clu -> pack_start( $scroll2clu, 1, 1, 0 );
								$scroll2clu -> set_policy( 'automatic', 'automatic' );
									
									$$self{_WINDOWCLUSTER}{treeClustered1} = Gtk2::Ex::Simple::List -> new_from_treeview (
										Gtk2::TreeView -> new,
										'Terminal(s) in cluster:'	=> 'text',
										'UUID:'						=> 'hidden'
									);
									$scroll2clu -> add( $$self{_WINDOWCLUSTER}{treeClustered1} );
									$$self{_WINDOWCLUSTER}{treeClustered1} -> set_headers_visible( 0 );
									$$self{_WINDOWCLUSTER}{treeClustered1} -> set_tooltip_text( 'List of connections included in the selected cluster above' );
									$$self{_WINDOWCLUSTER}{treeClustered1} -> get_selection -> set_mode( 'GTK_SELECTION_MULTIPLE' );
									$$self{_WINDOWCLUSTER}{treeClustered1} -> get_selection -> set_mode( 'GTK_SELECTION_MULTIPLE' );
				
				# Add an "autocluster" tab
				my $tablbl3 = Gtk2::HBox -> new( 0, 0 );
					my $lbl3 = Gtk2::Label -> new;
					$lbl3 -> set_markup( '<b>AUTO CLUSTERS </b>' );
					$tablbl3 -> pack_start( $lbl3, 0, 1, 0 );
					$tablbl3 -> pack_start( Gtk2::Image -> new_from_stock( 'pac-cluster-manager2', 'menu' ), 0, 1, 0 );
				$tablbl3 -> show_all;
				
				my $hboxautoclu = Gtk2::HBox -> new( 0, 0 );
				$$self{_WINDOWCLUSTER}{nb} -> append_page( $hboxautoclu, $tablbl3 );
					
					my $vboxaclist = Gtk2::VBox -> new;
					$hboxautoclu -> pack_start( $vboxaclist, 1, 1, 0 );
						
						my $hboxaclistbtns = Gtk2::HBox -> new;
						$vboxaclist -> pack_start( $hboxaclistbtns, 0, 1, 0 );
							
							$$self{_WINDOWCLUSTER}{addAC} = Gtk2::Button -> new_from_stock( 'gtk-add' );
							$hboxaclistbtns -> add( $$self{_WINDOWCLUSTER}{addAC} );
							$$self{_WINDOWCLUSTER}{addAC} -> set( 'can-focus' => 0 );
							
							$$self{_WINDOWCLUSTER}{renAC} = Gtk2::Button -> new;
							$hboxaclistbtns -> add( $$self{_WINDOWCLUSTER}{renAC} );
							$$self{_WINDOWCLUSTER}{renAC} -> set_image( Gtk2::Image -> new_from_stock( 'gtk-edit', 'button' ) );
							$$self{_WINDOWCLUSTER}{renAC} -> set_label( 'Rename' );
							$$self{_WINDOWCLUSTER}{renAC} -> set( 'can-focus' => 0 );
							
							$$self{_WINDOWCLUSTER}{delAC} = Gtk2::Button -> new_from_stock( 'gtk-delete' );
							$hboxaclistbtns -> add( $$self{_WINDOWCLUSTER}{delAC} );
							$$self{_WINDOWCLUSTER}{delAC} -> set( 'can-focus' => 0 );
						
						# Create a scrollautoclu scrolled window to contain the connections tree
						my $scrollaclist = Gtk2::ScrolledWindow -> new;
						$scrollaclist -> set_policy( 'automatic', 'automatic' );
						$vboxaclist -> pack_start( $scrollaclist, 1, 1, 0 );
						$$self{_WINDOWCLUSTER}{treeAutocluster} = Gtk2::Ex::Simple::List -> new_from_treeview (
							Gtk2::TreeView -> new,
							'AUTOCLUSTER'	=> 'text',
						);
						$scrollaclist -> add( $$self{_WINDOWCLUSTER}{treeAutocluster} );
						$$self{_WINDOWCLUSTER}{treeAutocluster} -> set_headers_visible( 1 );
						$$self{_WINDOWCLUSTER}{treeAutocluster} -> get_selection -> set_mode( 'GTK_SELECTION_SINGLE' );
					
					$hboxautoclu -> pack_start( Gtk2::VSeparator -> new, 0, 1, 5 );
					
					my $frameac = Gtk2::Frame -> new;
					$hboxautoclu -> pack_start( $frameac, 1, 1, 0 );
					my $frameaclbl = Gtk2::Label -> new;
					$frameaclbl -> set_markup( ' <b>AUTOCLUSTER MATCHING PROPERTIES:</b> ' );
					$frameac -> set_label_widget( $frameaclbl );
					$frameac -> set_tooltip_text( "These entries accept Regular Expressions,like:\n^server\\d+\nor\nconn.*\\d{1,3}\$\nor any other Perl RegExp" );
						
						my $vboxacprops = Gtk2::VBox -> new;
						$frameac -> add( $vboxacprops );
							
							my $hboxacpname = Gtk2::HBox -> new; $vboxacprops -> pack_start( $hboxacpname, 0, 1, 0);
							$hboxacpname -> pack_start( Gtk2::Label -> new( 'Name:' ) , 0, 1, 0 );
							$hboxacpname -> pack_start( $$self{_WINDOWCLUSTER}{entryname} = Gtk2::Entry -> new, 1, 1, 0 );
							
							my $hboxacptitle = Gtk2::HBox -> new; $vboxacprops -> pack_start( $hboxacptitle, 0, 1, 0);
							$hboxacptitle -> pack_start( Gtk2::Label -> new( 'Title:' ) , 0, 1, 0 );
							$hboxacptitle -> pack_start( $$self{_WINDOWCLUSTER}{entrytitle} = Gtk2::Entry -> new, 1, 1, 0 );
							
							my $hboxacphost = Gtk2::HBox -> new; $vboxacprops -> pack_start( $hboxacphost, 0, 1, 0);
							$hboxacphost -> pack_start( Gtk2::Label -> new( 'IP/Host:' ) , 0, 1, 0 );
							$hboxacphost -> pack_start( $$self{_WINDOWCLUSTER}{entryhost} = Gtk2::Entry -> new, 1, 1, 0 );
							
							my $hboxacpdesc = Gtk2::HBox -> new; $vboxacprops -> pack_start( $hboxacpdesc, 0, 1, 0);
							$hboxacpdesc -> pack_start( Gtk2::Label -> new( 'Description:' ) , 0, 1, 0 );
							$hboxacpdesc -> pack_start( $$self{_WINDOWCLUSTER}{entrydesc} = Gtk2::Entry -> new, 1, 1, 0 );
							
							$$self{_WINDOWCLUSTER}{btnCheckAC} = Gtk2::Button -> new;
							$$self{_WINDOWCLUSTER}{btnCheckAC} -> set_image( Gtk2::Image -> new_from_stock( 'gtk-find', 'button' ) );
							$$self{_WINDOWCLUSTER}{btnCheckAC} -> set_label( 'Check Auto Cluster conditions' );
							$$self{_WINDOWCLUSTER}{btnCheckAC} -> set( 'can-focus', 0);
							$vboxacprops -> pack_start( $$self{_WINDOWCLUSTER}{btnCheckAC} , 1, 1, 5 );
			
			$$self{_WINDOWCLUSTER}{buttonPCC} = Gtk2::Button -> new_with_mnemonic( '_Power Cluster Controller' );
			$$self{_WINDOWCLUSTER}{buttonPCC} -> set_image( Gtk2::Image -> new_from_stock( 'gtk-justify-fill', 'button' ) );
			$vbox0 -> pack_start( $$self{_WINDOWCLUSTER}{buttonPCC}, 0, 1, 5 );
			
			$vbox0 -> pack_start( Gtk2::HSeparator -> new, 0, 1, 0 );
			
			my $hbbox1 = Gtk2::HButtonBox -> new;
			$vbox0 -> pack_start( $hbbox1, 0, 1, 5 );
				
				$$self{_WINDOWCLUSTER}{btnOK} = Gtk2::Button -> new_from_stock( 'gtk-ok' );
				$hbbox1 -> set_layout( 'GTK_BUTTONBOX_END' );
				$hbbox1 -> add( $$self{_WINDOWCLUSTER}{btnOK} );
	
	return 1;
}

sub _setupCallbacks {
	my $self = shift;
	
	###############################
	# CLUSTERS RELATED CALLBACKS
	###############################

	$$self{_WINDOWCLUSTER}{treeClustered} -> drag_dest_set( 'GTK_DEST_DEFAULT_ALL', [ 'copy', 'move' ], { target => 'PAC Connect', flags => [] } );
	$$self{_WINDOWCLUSTER}{treeClustered} -> signal_connect( 'drag_motion' => sub { $_[0] -> get_parent_window -> raise; return 1; } );
	$$self{_WINDOWCLUSTER}{treeClustered} -> signal_connect( 'drag_drop' => sub {
		my ( $me, $context, $x, $y, $data, $info, $time ) = @_;
		
		my $cluster = $$self{_WINDOWCLUSTER}{comboClusters} -> get_active_text;
		if ( ! $cluster )
		{
			_wMessage( $$self{_WINDOWCLUSTER}{main}, "Before Adding a Terminal to a Cluster, you MUST either:\n - Select an existing CLUSTER\n...or...\n - Create a NEW Cluster" );
			return 0;
		}
		
		my @idx;
		my %tmp;
		foreach my $uuid ( @{ $PACMain::FUNCS{_MAIN}{'DND'}{'selection'} } ) {
			if ( ( $PACMain::FUNCS{_MAIN}{_CFG}{'environments'}{$uuid}{'_is_group'} ) || ( $uuid eq '__PAC__ROOT__' ) )
			{
				my @children = $PACMain::FUNCS{_MAIN}{_GUI}{treeConnections} -> _getChildren( $uuid, 0, 1 );
				foreach my $child ( @children ) { $tmp{$child} = 1; }
			} else {
				$tmp{$uuid} = 1;
			}
		}
		foreach my $uuid ( keys %tmp ) { push( @idx, [ $uuid, undef, $cluster ] ); }
		$PACMain::FUNCS{_MAIN} -> _launchTerminals( \@idx );
		
		delete $$self{'DND'}{'selection'};
		
		return 1;
	} );
	
	# Capture 'add cluster' button clicked
	$$self{_WINDOWCLUSTER}{buttonPCC} -> signal_connect( 'clicked' => sub {
		$$self{_WINDOWCLUSTER}{main} -> hide;
		$PACMain::FUNCS{_PCC} -> show;
	} );
	
	# Capture 'comboClusters' change
	$$self{_WINDOWCLUSTER}{comboClusters} -> signal_connect( 'changed' => sub { $self -> _comboClustersChanged; } );
	
	$$self{_WINDOWCLUSTER}{comboClusters1} -> signal_connect( 'changed' => sub { $self -> _comboClustersChanged1; $self -> _updateButtons1; } );
	$$self{_WINDOWCLUSTER}{treeConnections} -> get_selection -> signal_connect( 'changed' => sub { $self -> _updateButtons1; } );
	
	$$self{_WINDOWCLUSTER}{treeClustered1} -> get_selection -> signal_connect( 'changed' => sub { $self -> _updateButtons1; } );
	$$self{_WINDOWCLUSTER}{treeClustered1} -> signal_connect( 'row_activated' => sub { $$self{_WINDOWCLUSTER}{btndel1} -> activate; } );
	$$self{_WINDOWCLUSTER}{btnadd1}	-> signal_connect( 'clicked' => sub {
		my @sel_uuids	= $$self{_WINDOWCLUSTER}{treeConnections} -> _getSelectedUUIDs;
		my $total		= scalar( @sel_uuids);
		
		my $is_root		= 0;
		my $uuid		= $sel_uuids[0];
		my $cluster		= $$self{_WINDOWCLUSTER}{comboClusters1} -> get_active_text;
		
		my $envs		= $PACMain::{FUNCS}{_MAIN}{_CFG}{environments};
		
		foreach my $uuid ( @sel_uuids ) { $uuid eq '__PAC__ROOT__' and $is_root = 1 and last; }
		
		if ( ! ( $total && ( defined $cluster ) && ( $cluster ne '' ) ) ) {
			_wMessage( $$self{_WINDOWCLUSTER}{main}, "Before Adding a Terminal to a Cluster, you MUST either:\n - Select an existing CLUSTER\n...or...\n - Create a NEW Cluster" );
			return 1;
		}
		
		foreach my $uuid ( @sel_uuids ) {
			if ( ! $$envs{$uuid}{_is_group} )
			{
				next if defined $$self{CLUSTERS}{$cluster}{$uuid};
				$$self{CLUSTERS}{$cluster}{$uuid} = 1;
				push( @{ $$envs{$uuid}{cluster} }, $cluster );
			} else {
				foreach my $subuuid ( $$self{_WINDOWCLUSTER}{treeConnections} -> _getChildren( $uuid, 0, 1 ) ) {
					next if $$envs{$subuuid}{_is_group} || defined $$self{CLUSTERS}{$cluster}{$subuuid};
					$$self{CLUSTERS}{$cluster}{$subuuid} = 1;
					push( @{ $$envs{$subuuid}{cluster} }, $cluster );
				}
			}
		}
		
		$self -> _comboClustersChanged1;
		my $i = -1;
		foreach my $aux_cluster ( sort { uc($a) cmp uc($b) } keys %{ $$self{CLUSTERS} } ) {
			++$i;
			next unless $cluster eq $aux_cluster;
			$cluster eq $aux_cluster and $$self{_WINDOWCLUSTER}{comboClusters1} -> set_active( $i );
			last;
		}
		
		$self -> _updateButtons1;
		
		#$PACMain::{FUNCS}{_MAIN}{_CFG}{tmp}{changed} = 1;
		$PACMain::FUNCS{_MAIN} -> _setCFGChanged( 1 );
		$PACMain::{FUNCS}{_MAIN}{_GUI}{nbTree} -> get_nth_page( $PACMain::{FUNCS}{_MAIN}{_GUI}{nbTree} -> get_current_page ) eq $PACMain::{FUNCS}{_MAIN}{_GUI}{vboxclu} and $PACMain::{FUNCS}{_MAIN} -> _updateClustersList;
		
		return 1;
	} );
	
	$$self{_WINDOWCLUSTER}{btndel1}	-> signal_connect( 'clicked' => sub {
		my $cluster	= $$self{_WINDOWCLUSTER}{comboClusters1}	-> get_active_text;
		my $total	= $$self{_WINDOWCLUSTER}{treeClustered1}	-> get_selected_indices;
		my @select	= $$self{_WINDOWCLUSTER}{treeClustered1}	-> get_selected_indices;
		return 1 unless ( $total && ( defined $cluster ) && ( $cluster ne '' ) );
		
		foreach my $sel ( sort { $a > $b } @select ) {
			my $uuid = $$self{_WINDOWCLUSTER}{treeClustered1} -> {data}[$sel][1];
			my $i = -1;
			foreach my $clu ( @{ $PACMain::{FUNCS}{_MAIN}{_CFG}{environments}{$uuid}{cluster} } ) {
				++$i;
				next unless $clu eq $cluster;
				splice( @{ $PACMain::{FUNCS}{_MAIN}{_CFG}{environments}{$uuid}{cluster} }, $i, 1 );
				last;
			}
		}
		
		$self -> _updateButtons1;
		$self -> _updateGUI1;
		
		#$PACMain::{FUNCS}{_MAIN}{_CFG}{tmp}{changed} = 1;
		$PACMain::FUNCS{_MAIN} -> _setCFGChanged( 1 );
		$PACMain::{FUNCS}{_MAIN}{_GUI}{nbTree} -> get_nth_page( $PACMain::{FUNCS}{_MAIN}{_GUI}{nbTree} -> get_current_page ) eq $PACMain::{FUNCS}{_MAIN}{_GUI}{vboxclu} and $PACMain::{FUNCS}{_MAIN} -> _updateClustersList;
		
		return 1;
	} );	
	
	# Capture 'add cluster' button clicked
	$$self{_WINDOWCLUSTER}{addCluster} -> signal_connect( 'clicked' => sub {
		my $new_cluster = _wEnterValue( $self, 'Enter a name for the <b>New Cluster</b>' );
		
		if ( ( ! defined $new_cluster ) || ( $new_cluster =~ /^\s*$/go ) ) {
			return 1;
		} elsif ( defined $$self{_CLUSTERS}{$new_cluster} ) {
			_wMessage( $$self{_WINDOWCLUSTER}{main}, "Cluster '$new_cluster' already exists!!" );
		}
		
		# Empty the environments combobox
		foreach my $cluster ( keys %{ $$self{_CLUSTERS} } ) { $$self{_WINDOWCLUSTER}{comboClusters} -> remove_text( 0 ); }
		
		$$self{_CLUSTERS}{$new_cluster}{1} = undef;
		
		# Re-populate the clusters combobox
		my $i = 0;
		my $j = 0;
		foreach my $cluster ( sort { uc($a) cmp uc($b) } keys %{ $$self{_CLUSTERS} } ) {
			$j = $i;
			$$self{_WINDOWCLUSTER}{comboClusters} -> append_text( $cluster );
			$cluster eq $new_cluster and $$self{_WINDOWCLUSTER}{comboClusters} -> set_active( $j );
			++$i;
		}
		
		$$self{_WINDOWCLUSTER}{delCluster}	-> set_sensitive( 1 );
		
		return 1;
	} );
	
	# Capture 'add cluster 1' button clicked
	$$self{_WINDOWCLUSTER}{addCluster1} -> signal_connect( 'clicked' => sub {
		my $new_cluster = _wEnterValue( $self, 'Enter a name for the <b>New Cluster</b>' );
		
		return 1 if ( ( ! defined $new_cluster ) || ( $new_cluster =~ /^\s*$/go ) );
		if ( defined $$self{CLUSTERS}{$new_cluster} ) { _wMessage( $$self{_WINDOWCLUSTER}{main}, "Cluster '$new_cluster' already exists!!" ); return 1; }
		if ( defined $PACMain::{FUNCS}{_MAIN}{_CFG}{defaults}{'auto cluster'}{$new_cluster} ) { _wMessage( $$self{_WINDOWCLUSTER}{main}, "Auto Cluster name '$new_cluster' already exists!!" ); return 1; }
		
		# Empty the environments combobox
		foreach my $uuid ( keys %{ $$self{CLUSTERS} } ) { $$self{_WINDOWCLUSTER}{comboClusters1} -> remove_text( 0 ); }
		
		$$self{CLUSTERS}{$new_cluster} = undef;
		
		# Re-populate the clusters combobox
		my $i = 0;
		my $j = 0;
		foreach my $cluster ( sort { uc($a) cmp uc($b) } keys %{ $$self{CLUSTERS} } ) {
			$j = $i;
			$$self{_WINDOWCLUSTER}{comboClusters1} -> append_text( $cluster );
			$cluster eq $new_cluster and $$self{_WINDOWCLUSTER}{comboClusters1} -> set_active( $j );
			++$i;
		}
		
		$self -> _updateButtons1;
		$PACMain::{FUNCS}{_MAIN}{_GUI}{nbTree} -> get_nth_page( $PACMain::{FUNCS}{_MAIN}{_GUI}{nbTree} -> get_current_page ) eq $PACMain::{FUNCS}{_MAIN}{_GUI}{vboxclu} and $PACMain::{FUNCS}{_MAIN} -> _updateClustersList;
		#$PACMain::{FUNCS}{_MAIN}{_CFG}{tmp}{changed} = 1;
		$PACMain::FUNCS{_MAIN} -> _setCFGChanged( 1 );
		return 1;
	} );
	
	# Capture 'rename cluster 1' button clicked
	$$self{_WINDOWCLUSTER}{renCluster1} -> signal_connect( 'clicked' => sub {
		my $old_cluster	= $$self{_WINDOWCLUSTER}{comboClusters1} -> get_active_text;
		my $new_cluster = _wEnterValue( $self, "Enter a <b>NEW</b> name for cluster <b>$old_cluster</b>", undef, $old_cluster );
		
		return 1 if ( ( ! defined $new_cluster ) || ( $new_cluster =~ /^\s*$/go ) );
		if ( defined $$self{CLUSTERS}{$new_cluster} ) { _wMessage( $$self{_WINDOWCLUSTER}{main}, "Cluster name '$new_cluster' already exists!!" ); return 1; }
		
		# Remove this cluster's reference from every connection
		foreach my $uuid ( keys %{ $PACMain::{FUNCS}{_MAIN}{_CFG}{environments} } ) {
			next if $PACMain::{FUNCS}{_MAIN}{_CFG}{environments}{$uuid}{_is_group} || $uuid eq '__PAC__ROOT__';
			my $i = -1;
			foreach my $clu ( @{ $PACMain::{FUNCS}{_MAIN}{_CFG}{environments}{$uuid}{cluster} } ) {
				++$i;
				next unless $clu eq $old_cluster;
				splice( @{ $PACMain::{FUNCS}{_MAIN}{_CFG}{environments}{$uuid}{cluster} }, $i, 1, $new_cluster );
				last;
			}
		}
		
		$self -> _updateGUI1( $new_cluster );
		$self -> _updateButtons1;
		$PACMain::{FUNCS}{_MAIN}{_GUI}{nbTree} -> get_nth_page( $PACMain::{FUNCS}{_MAIN}{_GUI}{nbTree} -> get_current_page ) eq $PACMain::{FUNCS}{_MAIN}{_GUI}{vboxclu} and $PACMain::{FUNCS}{_MAIN} -> _updateClustersList;
		#$PACMain::{FUNCS}{_MAIN}{_CFG}{tmp}{changed} = 1;
		$PACMain::FUNCS{_MAIN} -> _setCFGChanged( 1 );
		return 1;
	} );
	
	# Capture 'delete cluster' button clicked
	$$self{_WINDOWCLUSTER}{delCluster} -> signal_connect( 'clicked' => sub {
		# Get the string of the active cluster
		my $cluster = $$self{_WINDOWCLUSTER}{comboClusters} -> get_active_text();
		
		_wConfirm( $$self{_WINDOWCLUSTER}{main}, "Delete cluster <b>'$cluster'</b>?" ) or return 1;
		
		$$self{_WINDOWCLUSTER}{treeClustered} -> select( 0..1000 );	# Select every terminal in this cluster...
		$$self{_WINDOWCLUSTER}{btndel} -> clicked;					# ... and click the "delete" button
		# Remove this cluster's reference from every connection
		foreach my $uuid ( keys %{ $$self{_RUNNING} } ) {
			#$$self{_RUNNING}{$uuid}{'terminal'}{_CLUSTER} = '' if $$self{_RUNNING}{$uuid}{'terminal'}{_CLUSTER} eq $cluster;
			next unless $$self{_RUNNING}{$uuid}{'terminal'}{_CLUSTER} eq $cluster;
			$self -> delFromCluster( $uuid, $cluster );
		}
		
		# Empty the clusters combobox
		foreach my $del_cluster ( keys %{ $$self{_CLUSTERS} } ) { $$self{_WINDOWCLUSTER}{comboClusters} -> remove_text( 0 ); }
		
		# Delete selected cluster
		delete $$self{_CLUSTERS}{$cluster};
		
		# Re-populate the clusters combobox
		foreach my $new_cluster ( sort { uc($a) cmp uc($b) } keys %{ $$self{_CLUSTERS} } ) { $$self{_WINDOWCLUSTER}{comboClusters} -> append_text( $new_cluster ); }
		
		$$self{_WINDOWCLUSTER}{comboClusters} -> set_active( 0 );
		$self -> _updateGUI;
		
		return 1;
	} );
	
	# Capture 'delete cluster' button clicked
	$$self{_WINDOWCLUSTER}{delCluster1} -> signal_connect( 'clicked' => sub {
		# Get the string of the active cluster
		my $cluster = $$self{_WINDOWCLUSTER}{comboClusters1} -> get_active_text // '';
		
		_wConfirm( $$self{_WINDOWCLUSTER}{main}, "Delete cluster <b>'$cluster'</b>?" ) or return 1;
		
		# Remove this cluster's reference from every connection
		foreach my $uuid ( keys %{ $PACMain::{FUNCS}{_MAIN}{_CFG}{environments} } ) {
			next if $PACMain::{FUNCS}{_MAIN}{_CFG}{environments}{$uuid}{_is_group} || $uuid eq '__PAC__ROOT__';
			my $i = -1;
			foreach my $clu ( @{ $PACMain::{FUNCS}{_MAIN}{_CFG}{environments}{$uuid}{cluster} } ) {
				++$i;
				next unless $clu eq $cluster;
				splice( @{ $PACMain::{FUNCS}{_MAIN}{_CFG}{environments}{$uuid}{cluster} }, $i, 1 );
				last;
			}
		}
		
		# Check if user want to take running terminals from deleted cluster
		my $i = 0;
		foreach my $uuid ( keys %{ $$self{_RUNNING} } ) { $i++ if $$self{_RUNNING}{$uuid}{terminal}{_CLUSTER} eq $cluster; }
		if ( $i && _wConfirm( $$self{_WINDOWCLUSTER}{main}, "Remove running terminals from deleted cluster <b>'$cluster'</b>?" ) )
		{
			foreach my $uuid ( keys %{ $$self{_RUNNING} } ) {
				next unless $$self{_RUNNING}{$uuid}{terminal}{_CLUSTER} eq $cluster;
				$$self{_RUNNING}{$uuid}{terminal}{_CLUSTER} = '';
				$$self{_RUNNING}{$uuid}{'terminal'} -> _updateStatus;
				$self -> _updateGUI;
			}
		}
		
		$self -> _updateButtons1;
		$self -> _updateGUI1;
		$PACMain::{FUNCS}{_MAIN}{_GUI}{nbTree} -> get_nth_page( $PACMain::{FUNCS}{_MAIN}{_GUI}{nbTree} -> get_current_page ) eq $PACMain::{FUNCS}{_MAIN}{_GUI}{vboxclu} and $PACMain::{FUNCS}{_MAIN} -> _updateClustersList;
		#$PACMain::{FUNCS}{_MAIN}{_CFG}{tmp}{changed} = 1;
		$PACMain::FUNCS{_MAIN} -> _setCFGChanged( 1 );
		
		return 1;
	} );
	
	$$self{_WINDOWCLUSTER}{treeClustered} -> signal_connect( 'cursor_changed' => sub {
		$$self{_WINDOWCLUSTER}{btndel} -> set_sensitive( scalar( @{ $$self{_WINDOWCLUSTER}{treeClustered} -> {data} } ) );
	} );
	
	# Capture 'treeTerminals' row activated
	$$self{_WINDOWCLUSTER}{treeClustered} -> signal_connect( 'row_activated' => sub {
		my ( $index ) = $$self{_WINDOWCLUSTER}{treeClustered} -> get_selected_indices;
		return unless defined $index;
		
		$$self{_WINDOWCLUSTER}{btndel} -> clicked;
		return 1;
	} );
	
	# Add terminal to selected cluster
	$$self{_WINDOWCLUSTER}{btnadd}	-> signal_connect( 'clicked' => sub {
		my $cluster	= $$self{_WINDOWCLUSTER}{comboClusters}	-> get_active_text;
		my $total	= $$self{_WINDOWCLUSTER}{treeTerminals}	-> get_selected_indices;
		my @select	= $$self{_WINDOWCLUSTER}{treeTerminals}	-> get_selected_indices;
		if ( ! ( $total && ( defined $cluster ) && ( $cluster ne '' ) ) ) {
			_wMessage( $$self{_WINDOWCLUSTER}{main}, "Before Adding a Terminal to a Cluster, you MUST either:\n - Select an existing CLUSTER\n...or...\n - Create a NEW Cluster" );
			
			$cluster = _wEnterValue( $self, 'Enter a name for the <b>New Cluster</b>' );
			
			if ( ( ! defined $cluster ) || ( $cluster =~ /^\s*$/go ) ) {
				return 1;
			} elsif ( defined $$self{_CLUSTERS}{$cluster} ) {
				_wMessage( $$self{_WINDOWCLUSTER}{main}, "Cluster '$cluster' already exists!!" );
				return 1;
			}
			
			# Empty the environments combobox
			foreach my $clt ( keys %{ $$self{_CLUSTERS} } ) { $$self{_WINDOWCLUSTER}{comboClusters} -> remove_text( 0 ); }
			
			$$self{_CLUSTERS}{$cluster}{1} = undef;
			
			# Re-populate the clusters combobox
			my $i = 0;
			my $j = 0;
			foreach my $clt ( sort { uc($a) cmp uc($b) } keys %{ $$self{_CLUSTERS} } ) {
				$j = $i;
				$$self{_WINDOWCLUSTER}{comboClusters} -> append_text( $clt );
				$clt eq $cluster and $$self{_WINDOWCLUSTER}{comboClusters} -> set_active( $j );
				++$i;
			}
			
			$$self{_WINDOWCLUSTER}{delCluster}	-> set_sensitive( 1 );
		}
		
		foreach my $sel ( sort { $a < $b } @select ) {
			my $uuid = $$self{_WINDOWCLUSTER}{treeTerminals} -> {data}[$sel][1];
			$self -> addToCluster( $uuid, $cluster );
		}
		
		return 1;
	} );
	
	# Remove selected terminal from current cluster
	$$self{_WINDOWCLUSTER}{btndel}	-> signal_connect( 'clicked' => sub {
		my $cluster	= $$self{_WINDOWCLUSTER}{comboClusters}	-> get_active_text;
		my $total	= $$self{_WINDOWCLUSTER}{treeClustered}	-> get_selected_indices;
		my @select	= $$self{_WINDOWCLUSTER}{treeClustered}	-> get_selected_indices;
		return 1 unless ( $total && ( defined $cluster ) && ( $cluster ne '' ) );
		
		foreach my $sel ( sort { $a < $b } @select ) {
			my $uuid = $$self{_WINDOWCLUSTER}{treeClustered} -> {data}[$sel][1];
			$self -> delFromCluster( $uuid, $cluster );
		}
		
		$$self{_WINDOWCLUSTER}{btndel} -> set_sensitive( scalar( @{ $$self{_WINDOWCLUSTER}{treeClustered} -> {data} } ) );
		
		return 1;
	} );
	
	
	$$self{_WINDOWCLUSTER}{treeConnections} -> signal_connect( 'row_activated' => sub {
		my @sel = $$self{_WINDOWCLUSTER}{treeConnections} -> _getSelectedUUIDs;
		
		my $is_group = 0;
		my $is_root = 0;
		foreach my $uuid ( @sel ) {
			$uuid eq '__PAC__ROOT__' and $is_root = 1;
			$PACMain::{FUNCS}{_MAIN}{_CFG}{'environments'}{$uuid}{'_is_group'} and $is_group = 1;
		}
		
		my @idx;
		foreach my $uuid ( @sel ) { push( @idx, [ $uuid ] ); }
		return 0 unless scalar @idx == 1;
		
		my $tree		= $$self{_WINDOWCLUSTER}{treeConnections};
		
		my $selection	= $tree -> get_selection;
		my $model		= $tree -> get_model;
		my @paths		= $selection -> get_selected_rows;
		
		my $uuid		= $model -> get_value( $model -> get_iter( $paths[0] ), 2 );
		
		$$self{_WINDOWCLUSTER}{btnadd1} -> activate unless ( ( $uuid eq '__PAC__ROOT__' ) || ( $PACMain::{FUNCS}{_MAIN}{_CFG}{'environments'}{$uuid}{'_is_group'} ) );
		return 0 unless ( ( $uuid eq '__PAC__ROOT__' ) || ( $PACMain::{FUNCS}{_MAIN}{_CFG}{'environments'}{$uuid}{'_is_group'} ) );
		if ( $tree -> row_expanded( $$self{_WINDOWCLUSTER}{treeConnections} -> _getPath( $uuid ) ) )
		{
			$tree -> collapse_row( $$self{_WINDOWCLUSTER}{treeConnections} -> _getPath( $uuid ) );
		} elsif ( $uuid ne '__PAC__ROOT__' ) {
			$tree -> expand_row( $paths[0], 0 );
		}
	} );
	
	$$self{_WINDOWCLUSTER}{treeConnections} -> signal_connect( 'key_press_event' => sub {
		my ( $widget, $event ) = @_;
		
		my $keyval	= '' . ( $event -> keyval );
		my $state	= '' . ( $event -> state );
		#print "KEY MASK:" . ( $event -> state ) . "\n";
		#print "KEY PRESSED:" . $event -> keyval . ":" . ( chr( $event -> keyval ) ) . "\n";
		
		my @sel = $$self{_WINDOWCLUSTER}{treeConnections} -> _getSelectedUUIDs;
		
		my $is_group = 0;
		my $is_root = 0;
		foreach my $uuid ( @sel ) {
			$uuid eq '__PAC__ROOT__' and $is_root = 1;
			$PACMain::{FUNCS}{_MAIN}{_CFG}{'environments'}{$uuid}{'_is_group'} and $is_group = 1;
		}
		
		# Capture 'left arrow'  keypress to collapse row
		if ( $event -> keyval == 65361 )
		{
			my @idx;
			foreach my $uuid ( @sel ) { push( @idx, [ $uuid ] ); }
			return 0 unless scalar @idx == 1;
			
			my $tree		= $$self{_WINDOWCLUSTER}{treeConnections};
			
			my $selection	= $tree -> get_selection;
			my $model		= $tree -> get_model;
			my @paths		= $selection -> get_selected_rows;
			
			my $uuid		= $model -> get_value( $model -> get_iter( $paths[0] ), 2 );
			
			if ( ( $uuid eq '__PAC__ROOT__' ) || ( $PACMain::{FUNCS}{_MAIN}{_CFG}{'environments'}{$uuid}{'_is_group'} ) )
			{
				if ( $tree -> row_expanded( $$self{_WINDOWCLUSTER}{treeConnections} -> _getPath( $uuid ) ) )
				{
					$tree -> collapse_row( $$self{_WINDOWCLUSTER}{treeConnections} -> _getPath( $uuid ) );
				} elsif ( $uuid ne '__PAC__ROOT__' ) {
					$tree -> set_cursor( $$self{_WINDOWCLUSTER}{treeConnections} -> _getPath( $PACMain::{FUNCS}{_MAIN}{_CFG}{'environments'}{$uuid}{'parent'} ) );
				}
			} else {
				$tree -> set_cursor( $$self{_WINDOWCLUSTER}{treeConnections} -> _getPath( $PACMain::{FUNCS}{_MAIN}{_CFG}{'environments'}{$uuid}{'parent'} ) );
			}
		}
		# Capture 'right arrow' or 'intro' keypress to expand row
		elsif ( $event -> keyval == 65363 )#|| $event -> keyval == 65293 )
		{
			my @idx;
			foreach my $uuid ( @sel ) { push( @idx, [ $uuid ] ); }
			return 0 unless scalar @idx == 1;
			
			my $tree		= $$self{_WINDOWCLUSTER}{treeConnections};
			
			my $selection	= $tree -> get_selection;
			my $model		= $tree -> get_model;
			my @paths		= $selection -> get_selected_rows;
			
			my $uuid		= $model -> get_value( $model -> get_iter( $paths[0] ), 2 );
			
			return 0 unless ( ( $uuid eq '__PAC__ROOT__' ) || ( $PACMain::{FUNCS}{_MAIN}{_CFG}{'environments'}{$uuid}{'_is_group'} ) );
			$tree -> expand_row( $paths[0], 0 );
		}
		
	} );
	
	
	$$self{_WINDOWCLUSTER}{treeAutocluster} -> get_selection -> signal_connect( 'changed' => sub {
		my @selection = $$self{_WINDOWCLUSTER}{treeAutocluster} -> get_selected_indices;
		return 1 unless scalar( @selection ) == 1;
		$$self{_UPDATING} = 1;
		my $sel		= $selection[0];
		my $ac		= $$self{_WINDOWCLUSTER}{treeAutocluster}{data}[$sel][0];
		my $name	= $PACMain::FUNCS{_MAIN}{_CFG}{defaults}{'auto cluster'}{$ac}{name}		// '';
		my $host	= $PACMain::FUNCS{_MAIN}{_CFG}{defaults}{'auto cluster'}{$ac}{host}		// '';
		my $title	= $PACMain::FUNCS{_MAIN}{_CFG}{defaults}{'auto cluster'}{$ac}{title}	// '';
		my $desc	= $PACMain::FUNCS{_MAIN}{_CFG}{defaults}{'auto cluster'}{$ac}{desc}		// '';
		
		$$self{_WINDOWCLUSTER}{entryname}	-> set_text( $name );
		$$self{_WINDOWCLUSTER}{entryhost}	-> set_text( $host );
		$$self{_WINDOWCLUSTER}{entrytitle}	-> set_text( $title );
		$$self{_WINDOWCLUSTER}{entrydesc}	-> set_text( $desc );
		
		$self -> _updateButtonsAC;
		$$self{_UPDATING} = 0;
		
		return 1;
	} );
	
	$$self{_WINDOWCLUSTER}{addAC} -> signal_connect( 'clicked' => sub {
		my $new_ac = _wEnterValue( $self, 'Enter new <b>AUTO CLUSTER</b> name'  );
		return 1 if ( ( ! defined $new_ac ) || ( $new_ac =~ /^\s*$/go ) );
		if ( defined $PACMain::FUNCS{_MAIN}{_CFG}{defaults}{'auto cluster'}{$new_ac} ) { _wMessage( $$self{_WINDOWCLUSTER}{main}, "AutoCluster name '$new_ac' already exists!!" ); return 1; }
		my $clusters = $self -> getCFGClusters;
		if ( defined $$clusters{$new_ac} ) { _wMessage( $$self{_WINDOWCLUSTER}{main}, "Cluster name '$new_ac' already exists!!" ); return 1; }
		
		$PACMain::FUNCS{_MAIN}{_CFG}{defaults}{'auto cluster'}{$new_ac}{name}		= '';
		$PACMain::FUNCS{_MAIN}{_CFG}{defaults}{'auto cluster'}{$new_ac}{title}	= '';
		$PACMain::FUNCS{_MAIN}{_CFG}{defaults}{'auto cluster'}{$new_ac}{host}		= '';
		$PACMain::FUNCS{_MAIN}{_CFG}{defaults}{'auto cluster'}{$new_ac}{desc}		= '';
		
		$self -> _updateGUIAC( $new_ac );
		$$self{_WINDOWCLUSTER}{entryname} -> grab_focus;
		
		$PACMain::{FUNCS}{_MAIN}{_GUI}{nbTree} -> get_nth_page( $PACMain::{FUNCS}{_MAIN}{_GUI}{nbTree} -> get_current_page ) eq $PACMain::{FUNCS}{_MAIN}{_GUI}{vboxclu} and $PACMain::{FUNCS}{_MAIN} -> _updateClustersList;
		#$PACMain::{FUNCS}{_MAIN}{_CFG}{tmp}{changed} = 1;
		$PACMain::FUNCS{_MAIN} -> _setCFGChanged( 1 );
		return 1;
	} );
	$$self{_WINDOWCLUSTER}{renAC} -> signal_connect( 'clicked' => sub {
		my @selected = $$self{_WINDOWCLUSTER}{treeAutocluster} -> get_selected_indices;
		return 1 unless @selected;
		my $sel = $selected[0];
		my $old_cluster = $$self{_WINDOWCLUSTER}{treeAutocluster}{data}[$sel][0];
		
		my $new_cluster = _wEnterValue( $self, "Enter a <b>NEW</b> name for Auto Cluster <b>$old_cluster</b>", undef, $old_cluster );
		return 1 if ( ( ! defined $new_cluster ) || ( $new_cluster =~ /^\s*$/go ) );
		my $clusters = $self -> getCFGClusters;
		if ( defined $$clusters{$new_cluster} ) { _wMessage( $$self{_WINDOWCLUSTER}{main}, "Cluster name '$new_cluster' already exists!!" ); return 1; }
		if ( defined $PACMain::{FUNCS}{_MAIN}{_CFG}{defaults}{'auto cluster'}{$new_cluster} ) { _wMessage( $$self{_WINDOWCLUSTER}{main}, "Auto Cluster name '$new_cluster' already exists!!" ); return 1; }
		
		$PACMain::{FUNCS}{_MAIN}{_CFG}{defaults}{'auto cluster'}{$new_cluster} = dclone( $PACMain::{FUNCS}{_MAIN}{_CFG}{defaults}{'auto cluster'}{$old_cluster} );
		delete $PACMain::{FUNCS}{_MAIN}{_CFG}{defaults}{'auto cluster'}{$old_cluster};
		$self -> _updateGUIAC( $new_cluster );
		
		$PACMain::{FUNCS}{_MAIN}{_GUI}{nbTree} -> get_nth_page( $PACMain::{FUNCS}{_MAIN}{_GUI}{nbTree} -> get_current_page ) eq $PACMain::{FUNCS}{_MAIN}{_GUI}{vboxclu} and $PACMain::{FUNCS}{_MAIN} -> _updateClustersList;
		#$PACMain::{FUNCS}{_MAIN}{_CFG}{tmp}{changed} = 1;
		$PACMain::FUNCS{_MAIN} -> _setCFGChanged( 1 );
		return 1;
	} );
	$$self{_WINDOWCLUSTER}{delAC} -> signal_connect( 'clicked' => sub {
		my @selected = $$self{_WINDOWCLUSTER}{treeAutocluster} -> get_selected_indices;
		return 1 unless @selected;
		my $sel = $selected[0];
		my $cluster = $$self{_WINDOWCLUSTER}{treeAutocluster}{data}[$sel][0];
		return 1 unless _wConfirm( $$self{_WINDOWCLUSTER}{main}, "Are you sure you want to delete Auto Cluster <b>$cluster</b>?"  );
		
		delete $PACMain::FUNCS{_MAIN}{_CFG}{defaults}{'auto cluster'}{$cluster};
		
		$self -> _updateGUIAC;
		
		# Check if user want to take running terminals from deleted cluster
		my $i = 0;
		foreach my $uuid ( keys %{ $$self{_RUNNING} } ) { $i++ if $$self{_RUNNING}{$uuid}{terminal}{_CLUSTER} eq $cluster; }
		if ( $i && _wConfirm( $$self{_WINDOWCLUSTER}{main}, "Remove running terminals from deleted cluster <b>'$cluster'</b>?" ) )
		{
			foreach my $uuid ( keys %{ $$self{_RUNNING} } ) {
				next unless $$self{_RUNNING}{$uuid}{terminal}{_CLUSTER} eq $cluster;
				$$self{_RUNNING}{$uuid}{terminal}{_CLUSTER} = '';
				$$self{_RUNNING}{$uuid}{'terminal'} -> _updateStatus;
				$self -> _updateGUI;
			}
		}
		
		$PACMain::{FUNCS}{_MAIN}{_GUI}{nbTree} -> get_nth_page( $PACMain::{FUNCS}{_MAIN}{_GUI}{nbTree} -> get_current_page ) eq $PACMain::{FUNCS}{_MAIN}{_GUI}{vboxclu} and $PACMain::{FUNCS}{_MAIN} -> _updateClustersList;
		#$PACMain::{FUNCS}{_MAIN}{_CFG}{tmp}{changed} = 1;
		$PACMain::FUNCS{_MAIN} -> _setCFGChanged( 1 );
		return 1;
	} );
	
	foreach my $entry ( 'name', 'host', 'title', 'desc' ) {
		$$self{_WINDOWCLUSTER}{"entry${entry}"} -> signal_connect( 'changed' => sub {
			my @selected = $$self{_WINDOWCLUSTER}{treeAutocluster} -> get_selected_indices;
			return 1 unless @selected;
			return 1 if $$self{_CHANGING};
			my $sel = $selected[0];
			my $cluster = $$self{_WINDOWCLUSTER}{treeAutocluster}{data}[$sel][0];
			my $text = $$self{_WINDOWCLUSTER}{"entry${entry}"} -> get_chars( 0, -1 );
			$PACMain::FUNCS{_MAIN}{_CFG}{defaults}{'auto cluster'}{$cluster}{$entry} = $text;
			#$PACMain::FUNCS{_MAIN}{_CFG}{tmp}{changed} = 1 unless $$self{_UPDATING};
			$PACMain::FUNCS{_MAIN} -> _setCFGChanged( 1 ) unless $$self{_UPDATING};
		} );
	}
	$$self{_WINDOWCLUSTER}{btnCheckAC} -> signal_connect( 'clicked' => sub {
		my @selected = $$self{_WINDOWCLUSTER}{treeAutocluster} -> get_selected_indices;
		return 1 unless @selected;
		my $sel = $selected[0];
		my $cluster = $$self{_WINDOWCLUSTER}{treeAutocluster}{data}[$sel][0];
		
		my $cond = '';
		$PACMain::FUNCS{_MAIN}{_CFG}{defaults}{'auto cluster'}{$cluster}{name}	ne '' and $cond .= "\nname =~ /$PACMain::FUNCS{_MAIN}{_CFG}{defaults}{'auto cluster'}{$cluster}{name}/";
		$PACMain::FUNCS{_MAIN}{_CFG}{defaults}{'auto cluster'}{$cluster}{host}	ne '' and $cond .= "\nhost =~ /$PACMain::FUNCS{_MAIN}{_CFG}{defaults}{'auto cluster'}{$cluster}{host}/";
		$PACMain::FUNCS{_MAIN}{_CFG}{defaults}{'auto cluster'}{$cluster}{title}	ne '' and $cond .= "\ntitle =~ /$PACMain::FUNCS{_MAIN}{_CFG}{defaults}{'auto cluster'}{$cluster}{title}/";
		$PACMain::FUNCS{_MAIN}{_CFG}{defaults}{'auto cluster'}{$cluster}{desc}	ne '' and $cond .= "\ndescription =~ /$PACMain::FUNCS{_MAIN}{_CFG}{defaults}{'auto cluster'}{$cluster}{desc}/";
		
		my $windowConfirm = Gtk2::MessageDialog -> new_with_markup( 
			$$self{_WINDOWCLUSTER}{main},
			'GTK_DIALOG_DESTROY_WITH_PARENT',
			'GTK_MESSAGE_INFO',
			'none',
			"Terminals matching Auto Cluster <b>$cluster</b> conditions:" . $cond
		);
		
		$windowConfirm -> set_icon_name( 'pac-app-big' );
		$windowConfirm -> set_title( "$APPNAME (v$APPVERSION) : Auto Cluster matching" );
		$windowConfirm -> add_buttons( 'gtk-ok' => 'ok' );
		$windowConfirm -> set_size_request( 640, 400 );
			
			my $hboxjarl = Gtk2::HBox -> new( 0, 0 );
			$windowConfirm -> vbox -> pack_start( $hboxjarl, 1, 1, 0 );
				
				my $scroll = Gtk2::ScrolledWindow -> new;
				$hboxjarl -> pack_start( $scroll, 0, 1, 0 );
				$scroll -> set_policy( 'never', 'automatic' );
				
				my $tree = Gtk2::Ex::Simple::List -> new_from_treeview ( Gtk2::TreeView -> new, 'Icon' => 'pixbuf', 'Terminal(s) matching' => 'text', 'UUID' => 'hidden' );
				$scroll -> add( $tree );
				$tree -> set_headers_visible( 0 );
				$tree -> get_selection -> set_mode( 'GTK_SELECTION_SINGLE' );
				
				my $name	= qr/$PACMain::FUNCS{_MAIN}{_CFG}{defaults}{'auto cluster'}{$cluster}{name}/;
				my $host	= qr/$PACMain::FUNCS{_MAIN}{_CFG}{defaults}{'auto cluster'}{$cluster}{host}/;
				my $title	= qr/$PACMain::FUNCS{_MAIN}{_CFG}{defaults}{'auto cluster'}{$cluster}{title}/;
				my $desc	= qr/$PACMain::FUNCS{_MAIN}{_CFG}{defaults}{'auto cluster'}{$cluster}{desc}/;
				foreach my $uuid ( keys %{ $PACMain::FUNCS{_MAIN}{_CFG}{environments} } ) {
					next if $uuid eq '__PAC__ROOT__' || $PACMain::FUNCS{_MAIN}{_CFG}{environments}{$uuid}{_is_group};
					if ( $name	ne '' ) { next unless $PACMain::FUNCS{_MAIN}{_CFG}{environments}{$uuid}{name}			=~ $name;	}
					if ( $host	ne '' ) { next unless $PACMain::FUNCS{_MAIN}{_CFG}{environments}{$uuid}{ip}				=~ $host;	}
					if ( $title	ne '' ) { next unless $PACMain::FUNCS{_MAIN}{_CFG}{environments}{$uuid}{title}			=~ $title;	}
					if ( $desc	ne '' ) { next unless $PACMain::FUNCS{_MAIN}{_CFG}{environments}{$uuid}{description}	=~ $desc;	}
					push( @{ $$tree{data} }, [ $PACMain::FUNCS{_METHODS}{ $PACMain::FUNCS{_MAIN}{_CFG}{'environments'}{$uuid}{'method'} }{'icon'}, $PACMain::FUNCS{_MAIN}{_CFG}{environments}{$uuid}{name}, $uuid ] );
				}
				
				# Create a scrolled2 scrolled window to contain the description textview
				my $scrollDescription = Gtk2::ScrolledWindow -> new;
				$hboxjarl -> pack_start( $scrollDescription, 1, 1, 0 );
				$scrollDescription -> set_policy( 'automatic', 'automatic' );
					
					# Create descView as a gtktextview with descBuffer
					my $descBuffer = Gtk2::TextBuffer -> new;
					my $descView = Gtk2::TextView -> new_with_buffer( $descBuffer );
					$descView -> set_border_width( 5 );
					$scrollDescription -> add( $descView );
					$descView -> set_wrap_mode( 'GTK_WRAP_WORD' );
					$descView -> set_sensitive( 0 );
					$descView -> drag_dest_unset;
					$descView -> modify_font( Pango::FontDescription -> from_string( 'monospace' ) );
		
		$tree -> get_selection -> signal_connect( 'changed' => sub {
			my @selection = $tree -> get_selected_indices;
			return 1 unless scalar( @selection ) == 1;
			my $sel		= $selection[0];
			my $name	= $$tree{data}[$sel][1];
			my $uuid	= $$tree{data}[$sel][2];
			$descBuffer -> set_text( encode( 'unicode', $PACMain::FUNCS{_MAIN}{_CFG}{'environments'}{$uuid}{'description'} // '' ) );
		} );
		
		my $lbltotal = Gtk2::Label -> new;
		$lbltotal -> set_markup( "Conditions for Auto Cluster <b>$cluster</b> match <b>" . ( scalar( @{ $$tree{data} } ) ) . '</b> connections' );
		$windowConfirm -> vbox -> pack_start( $lbltotal, 0, 1, 0 );
		
		$windowConfirm -> show_all;
		my $close = $windowConfirm -> run;
		$windowConfirm -> destroy;
		
		return 1;
	} );
	#######################################
	# CONNECTED TERMINALS RELATED CALLBACKS
	#######################################
	
	# Capture 'treeTerminals' row activated
	$$self{_WINDOWCLUSTER}{treeTerminals} -> signal_connect( 'row_activated' => sub {
		my ( $index ) = $$self{_WINDOWCLUSTER}{treeTerminals} -> get_selected_indices;
		return unless defined $index;
		
		$$self{_WINDOWCLUSTER}{btnadd} -> clicked;
		return 1;
	} );
	
	$$self{_WINDOWCLUSTER}{treeTerminals} -> signal_connect( 'cursor_changed' => sub {
		$$self{_WINDOWCLUSTER}{btnadd} -> set_sensitive( scalar( @{ $$self{_WINDOWCLUSTER}{treeTerminals} -> {data} } ) );
	} );
	
	###############################
	# OTHER CALLBACKS
	###############################
	
	# Capture 'Close' button clicked
	$$self{_WINDOWCLUSTER}{btnOK} -> signal_connect( 'clicked' => sub {
		$PACMain::{FUNCS}{_MAIN}{_GUI}{nbTree} -> get_nth_page( $PACMain::{FUNCS}{_MAIN}{_GUI}{nbTree} -> get_current_page ) eq $PACMain::{FUNCS}{_MAIN}{_GUI}{vboxclu} and $PACMain::{FUNCS}{_MAIN} -> _updateClustersList;
		$$self{_WINDOWCLUSTER}{main} -> hide;
	} );
	# Capture window closing
	$$self{_WINDOWCLUSTER}{main} -> signal_connect( 'delete_event' => sub { $$self{_WINDOWCLUSTER}{btnOK} -> activate; } );
	# Capture 'Esc' keypress to close window
	$$self{_WINDOWCLUSTER}{main} -> signal_connect( 'key_press_event' => sub { $_[1] -> keyval == 65307 and $$self{_WINDOWCLUSTER}{btnOK} -> activate; } );
	return 1;	
}

sub addToCluster {
	my $self	= shift;
	my $uuid	= shift;
	my $cluster	= shift;
	
	$$self{_RUNNING}{$uuid}{'terminal'}{_CLUSTER} = $cluster;
	$$self{_RUNNING}{$uuid}{'terminal'}{_GUI}{statusCluster} -> set_from_stock( 'pac-cluster-manager', 'button' ) if defined $$self{_RUNNING}{$uuid}{'terminal'}{_GUI}{statusCluster};
	$$self{_RUNNING}{$uuid}{'terminal'}{_GUI}{statusCluster} -> set_tooltip_text( "In CLUSTER: $cluster" ) if defined $$self{_RUNNING}{$uuid}{'terminal'}{_GUI}{statusCluster};
	$$self{_RUNNING}{$uuid}{'terminal'} -> _updateStatus;
	
	$self -> _updateGUI;
	
	return 1;
}

sub delFromCluster {
	my $self	= shift;
	my $uuid	= shift;
	my $cluster	= shift;
	
	$$self{_RUNNING}{$uuid}{'terminal'}{_CLUSTER} = '';
	$$self{_RUNNING}{$uuid}{'terminal'}{_GUI}{statusCluster} -> set_from_stock( 'pac-cluster-manager-off', 'button' ) if defined $$self{_RUNNING}{$uuid}{'terminal'}{_GUI}{statusCluster};
	$$self{_RUNNING}{$uuid}{'terminal'}{_GUI}{statusCluster} -> set_tooltip_text( "Unclustered" ) if defined $$self{_RUNNING}{$uuid}{'terminal'}{_GUI}{statusCluster};
	$$self{_RUNNING}{$uuid}{'terminal'} -> _updateStatus;
	
	$self -> _updateGUI;
	
	return 1;
}

sub _updateGUI {
	my $self = shift;
	
	$$self{_WINDOWCLUSTER}{delCluster}	-> set_sensitive( 0 );
	$$self{_WINDOWCLUSTER}{btnadd}		-> set_sensitive( 0 );
	$$self{_WINDOWCLUSTER}{btndel}		-> set_sensitive( 0 );
	
	# Empty the clusters combobox
	foreach my $cluster ( keys %{ $$self{_CLUSTERS} } ) { $$self{_WINDOWCLUSTER}{comboClusters} -> remove_text( 0 ); }
	# Empty the terminals tree
	@{ $$self{_WINDOWCLUSTER}{treeTerminals} -> {data} } = ();
	# Empty the clustered tree
	@{ $$self{_WINDOWCLUSTER}{treeClustered} -> {data} } = ();
	
	$$self{_CLUSTERS} = undef;
	
	# Look into every startes terminal, and add it to the 'clusteres' or 'unclustered' tree...
	foreach my $uuid ( keys %{ $$self{_RUNNING} } ) {
		my $name	= $$self{_RUNNING}{$uuid}{'terminal'}{'_NAME'};
		my $icon	= $$self{_RUNNING}{$uuid}{'terminal'}{CONNECTED} ? $ICON_ON : $ICON_OFF;
		
		next unless defined $name && defined $icon;
		
		if ( my $cluster = $$self{_RUNNING}{$uuid}{'terminal'}{_CLUSTER} )
		{
			# Populate the CLUSTER variable
			$$self{_CLUSTERS}{ $cluster }{$uuid} = 1;
			
			# Populate the clustered terminals tree
			push( @{ $$self{_WINDOWCLUSTER}{treeClustered} -> {data} }, [ $name, $uuid, $icon ] );
		} else {
			# Populate the terminals tree
			push( @{ $$self{_WINDOWCLUSTER}{treeTerminals} -> {data} }, [ $name, $uuid, $icon ] );
		}
	}
	
	# Now, populate the cluters combobox with the configured clusters...
	foreach my $cluster ( keys %{ $$self{_CLUSTERS} } ) {
		$$self{_WINDOWCLUSTER}{comboClusters}	-> append_text( $cluster );
		$$self{_WINDOWCLUSTER}{comboClusters}	-> set_active( 0 );
		$$self{_WINDOWCLUSTER}{delCluster}		-> set_sensitive( 1 );
	}
	
	$$self{_WINDOWCLUSTER}{addCluster}	-> set_sensitive( 1 );
	my $cluster	= $$self{_WINDOWCLUSTER}{comboClusters}	-> get_active_text();
	$$self{_WINDOWCLUSTER}{btnadd}		-> set_sensitive( scalar( @{ $$self{_WINDOWCLUSTER}{treeTerminals} -> {data} } ) && $cluster );
	$$self{_WINDOWCLUSTER}{btndel}		-> set_sensitive( scalar( @{ $$self{_WINDOWCLUSTER}{treeClustered} -> {data} } ) && $cluster );
	
	$PACMain::FUNCS{_PCC} -> _updateGUI;
	
	return 1;
}

sub _updateGUI1 {
	my $self	= shift;
	my $selclu	= shift // '';
	
	my $envs = $PACMain::{FUNCS}{_MAIN}{_CFG}{environments};
	
	$$self{CLUSTERS} = $self -> getCFGClusters;
	
	# Empty the clusters combobox
	for( my $i = 0; $i < 1000; ++$i ) { $$self{_WINDOWCLUSTER}{comboClusters1} -> remove_text( 0 ); }
	
	# Empty the clustered connections tree
	@{ $$self{_WINDOWCLUSTER}{treeClustered1}{data} } = ();
	
	# Now, populate the clusters combobox with the configured clusters...
	foreach my $cluster ( sort { lc( $a ) cmp lc( $b ) } keys %{ $$self{CLUSTERS} } ) {
		$$self{_WINDOWCLUSTER}{comboClusters1}	-> append_text( $cluster );
		$$self{_WINDOWCLUSTER}{comboClusters1}	-> set_active( 0 );
		$$self{_WINDOWCLUSTER}{delCluster1}		-> set_sensitive( 1 );
	}
	
	# Reload the connections tree
	$self -> _loadTreeConfiguration;
	
	my $i = 0;
	foreach my $cluster ( sort { lc($a) cmp lc($b) } keys %{ $$self{CLUSTERS} } ) {
		$cluster eq $selclu and $$self{_WINDOWCLUSTER}{comboClusters1} -> set_active( $i );
		++$i;
	}
	
	$self -> _updateButtons1;
	
	return 1;
}

sub _updateGUIAC {
	my $self	= shift;
	my $cluster	= shift // '';
	
	# Empty the AC table
	@{ $$self{_WINDOWCLUSTER}{treeAutocluster}{data} } = ();
	# and reload it
	
	my $i = 0;
	my $j = 0;
	foreach my $ac ( sort { $a cmp $b } keys %{ $PACMain::FUNCS{_MAIN}{_CFG}{defaults}{'auto cluster'} } ) {
		$j = $i if $ac eq $cluster;
		++$i;
		push( @{ $$self{_WINDOWCLUSTER}{treeAutocluster}{data} }, $ac );
	}
	$$self{_WINDOWCLUSTER}{treeAutocluster} -> set_cursor( Gtk2::TreePath -> new_from_string( $j ) );
	
	$self -> _updateButtonsAC;
	
	return 1;
}

sub _updateButtonsAC {
	my $self = shift;
	
	my $sel = $$self{_WINDOWCLUSTER}{treeAutocluster} -> get_selected_indices;
	
	$$self{_WINDOWCLUSTER}{addAC}		-> set_sensitive( 1 );
	$$self{_WINDOWCLUSTER}{renAC}		-> set_sensitive( $sel );
	$$self{_WINDOWCLUSTER}{delAC}		-> set_sensitive( $sel );
	$$self{_WINDOWCLUSTER}{btnCheckAC}	-> set_sensitive( $sel );
	
	$$self{_WINDOWCLUSTER}{entryname}	-> set_sensitive( $sel );
	$$self{_WINDOWCLUSTER}{entryhost}	-> set_sensitive( $sel );
	$$self{_WINDOWCLUSTER}{entrytitle}	-> set_sensitive( $sel );
	$$self{_WINDOWCLUSTER}{entrydesc}	-> set_sensitive( $sel );
	
	return 1;
}

sub getCFGClusters {
	my $self = shift;
	
	my $envs = $PACMain::{FUNCS}{_MAIN}{_CFG}{environments};
	my %clusters;
	
	foreach my $uuid ( keys %{ $envs } ) { foreach my $cluster ( @{ $$envs{$uuid}{cluster} } ) { $clusters{ $cluster }{ $uuid } = 1; } }
	
	return \%clusters;
}

sub _comboClustersChanged {
	my $self = shift;
	
	my $cluster = $$self{_WINDOWCLUSTER}{comboClusters} -> get_active_text;
	
	$$self{_WINDOWCLUSTER}{addCluster}	-> set_sensitive( 1 );
	$$self{_WINDOWCLUSTER}{delCluster}	-> set_sensitive( 0 );
	$$self{_WINDOWCLUSTER}{btnadd}		-> set_sensitive( 0 );
	$$self{_WINDOWCLUSTER}{btndel}		-> set_sensitive( 0 );
	
	return 1 unless $cluster;
	
	$$self{_WINDOWCLUSTER}{delCluster}	-> set_sensitive( 1 );
	$$self{_WINDOWCLUSTER}{btnadd}		-> set_sensitive( scalar( @{ $$self{_WINDOWCLUSTER}{treeTerminals} -> {data} } ) );
	$$self{_WINDOWCLUSTER}{btndel}		-> set_sensitive( scalar( @{ $$self{_WINDOWCLUSTER}{treeClustered} -> {data} } ) );
	
	# Empty the clustered terminals tree...
	@{ $$self{_WINDOWCLUSTER}{treeClustered} -> {data} } = ();
	
	# ... and repopulate it
	foreach my $uuid ( keys %{ $$self{_CLUSTERS}{$cluster} } ) {
		next if $uuid eq 1;
		my $name	= $$self{_RUNNING}{$uuid}{'terminal'}{'_NAME'};
		my $icon	= $$self{_RUNNING}{$uuid}{'terminal'}{'CONNECTED'} ? $ICON_ON : $ICON_OFF;
		push( @{ $$self{_WINDOWCLUSTER}{treeClustered} -> {data} }, [ $name, $uuid, $icon ] );
	}
	
	return 1;
}

sub _comboClustersChanged1 {
	my $self = shift;
	
	my $cluster = $$self{_WINDOWCLUSTER}{comboClusters1} -> get_active_text // '';
	return 1 unless $cluster ne '';
	
	# Empty the clustered terminals tree...
	@{ $$self{_WINDOWCLUSTER}{treeClustered1} -> {data} } = ();
	
	# ... and repopulate it
	my $cfg = $PACMain::{FUNCS}{_MAIN}{_CFG}{environments};
	foreach my $uuid ( sort { lc( $$cfg{$a}{name} ) cmp lc( $$cfg{$b}{name} ) } keys %{ $$self{CLUSTERS}{$cluster} } ) { push( @{ $$self{_WINDOWCLUSTER}{treeClustered1} -> {data} }, [ $PACMain::{FUNCS}{_MAIN}{_CFG}{'environments'}{$uuid}{name}, $uuid ] ); }
	
	return 1;
}

sub _updateButtons1 {
	my $self		= shift;
	
	my @sel_uuids	= $$self{_WINDOWCLUSTER}{treeConnections} -> _getSelectedUUIDs;
	my $total		= scalar( @sel_uuids);
	my $totalc		= $$self{_WINDOWCLUSTER}{treeClustered1} -> get_selected_indices;
	
	my $is_root		= 0;
	my $uuid		= $sel_uuids[0];
	my $cluster		= $$self{_WINDOWCLUSTER}{comboClusters1} -> get_active_text // '';
	
	foreach my $uuid ( @sel_uuids ) { $uuid // '' eq '__PAC__ROOT__' and $is_root = 1 and last; }
	
	$$self{_WINDOWCLUSTER}{addCluster1}	-> set_sensitive( 1 );
	$$self{_WINDOWCLUSTER}{renCluster1}	-> set_sensitive( $cluster ne '' );
	$$self{_WINDOWCLUSTER}{delCluster1}	-> set_sensitive( $cluster ne '' );
	$$self{_WINDOWCLUSTER}{btnadd1}		-> set_sensitive( $total );
	$$self{_WINDOWCLUSTER}{btndel1}		-> set_sensitive( $totalc );
	
	return 1;
}

# END: Define PRIVATE CLASS functions
###################################################################

1;
