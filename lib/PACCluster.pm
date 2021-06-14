package PACCluster;

###############################################################################
# This file is part of Ásbrú Connection Manager
#
# Copyright (C) 2017-2021 Ásbrú Connection Manager team (https://asbru-cm.net)
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

use utf8;
binmode STDOUT,':utf8';
binmode STDERR,':utf8';

$|++;

###################################################################
# Import Modules

use FindBin qw ($RealBin $Bin $Script);
use lib "$RealBin/lib", "$RealBin/lib/ex";

# Standard
use strict;
use warnings;
use Storable qw (dclone);
use Encode;

# GTK
use Gtk3 '-init';
use Gtk3::SimpleList;

# PAC modules
use PACUtils;
use PACPCC;

# END: Import Modules
###################################################################

###################################################################
# Define GLOBAL CLASS variables

my $APPNAME = $PACUtils::APPNAME;
my $APPVERSION = $PACUtils::APPVERSION;

my $CFG_DIR = $ENV{"ASBRU_CFG"};
my $CLUSTERS_FILE = "$CFG_DIR/asbru_clusters.nfreeze";
my $RES_DIR = "$RealBin/res";
my $THEME_DIR;
my $GROUPICONOPEN;
my $GROUPICONCLOSED;
my $GROUPICON_ROOT;
my $AUTOCLUSTERICON;
my $ICON_ON;
my $ICON_OFF;
# END: Define GLOBAL CLASS variables
###################################################################

###################################################################
# START: Define PUBLIC CLASS methods

sub new {
    my $class = shift;
    my $self = {};

    $self->{_RUNNING} = shift;

    $self->{_CLUSTERS} = undef;
    $self->{CLUSTERS} = undef;
    $self->{_WINDOWCLUSTER} = undef;
    $self->{_UPDATING} = 0;

    # Build the GUI
    if (!_initGUI($self)) {
        return 0;
    }

    # Setup callbacks
    _setupCallbacks($self);

    bless($self, $class);
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
    my $self = shift;
    my $cluster = shift // 0;

    $THEME_DIR = $PACMain::FUNCS{_MAIN}{_THEME};
    $GROUPICONCLOSED = _pixBufFromFile("$THEME_DIR/asbru_group_closed_16x16.svg");
    $GROUPICONOPEN = _pixBufFromFile("$THEME_DIR/asbru_group_open_16x16.svg");
    $GROUPICON_ROOT = _pixBufFromFile("$THEME_DIR/asbru_group.svg");
    $AUTOCLUSTERICON = _pixBufFromFile("$THEME_DIR/asbru_cluster_auto.png");
    $ICON_ON = Gtk3::Gdk::Pixbuf->new_from_file_at_scale("$RES_DIR/asbru_terminal16x16.png", 16, 16, 0);
    $ICON_OFF = Gtk3::Gdk::Pixbuf->new_from_file_at_scale("$RES_DIR/asbru_terminal_x16x16.png", 16, 16, 0);

    $$self{_WINDOWCLUSTER}{main}->set_title("Cluster Administration : $APPNAME (v$APPVERSION)");
    $$self{_WINDOWCLUSTER}{main}->set_position('center');
    $$self{_WINDOWCLUSTER}{main}->show_all;
    $$self{_WINDOWCLUSTER}{main}->present;

    $$self{_WINDOWCLUSTER}{treeTerminals}->grab_focus;
    $$self{_WINDOWCLUSTER}{treeTerminals}->select(0);

    $self->_updateGUI;
    $self->_updateGUI1($cluster);
    $self->_updateGUIAC($cluster);
    my $page = 1;
    if (!$cluster) {
        $page = 1;
    } elsif (defined $PACMain::FUNCS{_MAIN}{_CFG}{defaults}{'auto cluster'}{$cluster}) {
        $page = 2
    } else {
        $page = 1;
    }
    $$self{_WINDOWCLUSTER}{nb}->set_current_page($page);
    $$self{_WINDOWCLUSTER}{nb}->get_nth_page(0)->hide();
    #$$self{_WINDOWCLUSTER}{nb}->get_nth_page(2)->hide();
    $$self{_WINDOWCLUSTER}{buttonPCC}->hide();

    return 1;
}

# END: Define PUBLIC CLASS methods
###################################################################

###################################################################
# START: Define PRIVATE CLASS functions

sub _loadTreeConfiguration {
    my $self = shift;
    my $tree = shift // $$self{_WINDOWCLUSTER}{treeConnections};

    @{$$self{_WINDOWCLUSTER}{treeConnections}{'data'}} = ({
        value => [$GROUPICON_ROOT, '<b>My Connections</b>', '__PAC__ROOT__'],
        children => []
    });
    foreach my $child (keys %{$PACMain::{FUNCS}{_MAIN}{_CFG}{environments}{'__PAC__ROOT__'}{children}}) {
        push(@{$$tree{data}}, $self->__recurLoadTree($child) );
    }

    # Select the root path
    $tree->set_cursor(Gtk3::TreePath->new_from_string('0'), undef, 0);

    return 1;
}

sub __recurLoadTree {
    my $self = shift;
    my $uuid = shift;

    my $node_name = $PACMain::{FUNCS}{_MAIN}->__treeBuildNodeName($uuid);
    my @list;

    if (! $PACMain::{FUNCS}{_MAIN}{_CFG}{environments}{$uuid}{'_is_group'}) {
        push(@list, {
            value => [$PACMain::{FUNCS}{_MAIN}{_METHODS}{$PACMain::{FUNCS}{_MAIN}{_CFG}{'environments'}{$uuid}{'method'}}{'icon'}, $node_name, $uuid],
            children => []
        });
    } else {
        my @clist;
        foreach my $child (keys %{$PACMain::{FUNCS}{_MAIN}{_CFG}{environments}{$uuid}{children}}) {
            push(@clist, $self->__recurLoadTree($child) );
        }
        push(@list, {
            value => [$GROUPICONCLOSED, $node_name, $uuid],
            children => \@clist
        });
    }
    return @list;
}

sub __treeSort {
    my ($treestore, $a_iter, $b_iter) = @_;
    my $cfg = $PACMain::{FUNCS}{_MAIN}{_CFG};
    my $groups_1st = $$cfg{'defaults'}{'sort groups first'} // 1;

    my $b_uuid = $treestore->get_value($b_iter, 2);
    if (!defined $b_uuid) {
        return 0;
    }
    # __PAC__ROOT__ must always be the first node!!
    if ($b_uuid eq '__PAC__ROOT__') {
        return 1;
    }

    my $a_uuid = $treestore->get_value($a_iter, 2);
    if (!defined $a_uuid) {
        return 1;
    }
    # __PAC__ROOT__ must always be the first node!!
    if ($a_uuid eq '__PAC__ROOT__') {
        return -1;
    }

    # Groups first...
    if ($groups_1st) {
        my $a_is_group = $$cfg{'environments'}{$a_uuid}{'_is_group'};
        my $b_is_group = $$cfg{'environments'}{$b_uuid}{'_is_group'};

        if ($a_is_group && ! $b_is_group) {
            return -1;
        }
        if (! $a_is_group && $b_is_group) {
            return 1;
        }
    }

    # ... then alphabetically
    return lc($$cfg{'environments'}{$a_uuid}{name}) cmp lc($$cfg{'environments'}{$b_uuid}{name});
}

sub _initGUI {
    my $self = shift;

    $$self{_WINDOWCLUSTER}{main} = Gtk3::Window->new;
    $$self{_WINDOWCLUSTER}{main}->set_position('center');
    $$self{_WINDOWCLUSTER}{main}->set_icon_name('asbru-app-big');
    $$self{_WINDOWCLUSTER}{main}->set_size_request(650, 500);
    $$self{_WINDOWCLUSTER}{main}->set_default_size(650, 500);
    $$self{_WINDOWCLUSTER}{main}->set_resizable(1);
    $$self{_WINDOWCLUSTER}{main}->set_transient_for($PACMain::FUNCS{_MAIN}{_GUI}{main});
    $$self{_WINDOWCLUSTER}{main}->set_modal(1);

    my $vbox0 = Gtk3::VBox->new(0, 0);
    $$self{_WINDOWCLUSTER}{main}->add($vbox0);

    $vbox0->pack_start(PACUtils::_createBanner('asbru-cluster.svg', 'Cluster Management') , 0, 1, 0);

    # Create a notebook widget
    $$self{_WINDOWCLUSTER}{nb} = Gtk3::Notebook->new;
    $$self{_WINDOWCLUSTER}{nb}->set_scrollable(1);
    $$self{_WINDOWCLUSTER}{nb}->set_tab_pos('top');
    # FIXME-HOMOGENEOUS            $$self{_WINDOWCLUSTER}{nb}->set('homogeneous', 1);
    $vbox0->pack_start($$self{_WINDOWCLUSTER}{nb}, 1, 1, 0);

    my $tablbl1 = Gtk3::HBox->new(0, 0);
    my $lbl1 = Gtk3::Label->new;
    $lbl1->set_markup('<b>RUNNING CLUSTERS </b>');
    $tablbl1->pack_start($lbl1, 0, 1, 0);
    $tablbl1->pack_start(Gtk3::Image->new_from_stock('asbru-terminal-ok-small', 'menu'), 0, 1, 0);
    $tablbl1->show_all;

    my $vbox1 = Gtk3::VBox->new(0, 0);
    $$self{_WINDOWCLUSTER}{nb}->append_page($vbox1, $tablbl1);

    my $hbox1 = Gtk3::HBox->new(0, 0);
    $vbox1->pack_start($hbox1, 1, 1, 0);

    my $frame0 = Gtk3::Frame->new(' Unclustered Terminals');
    $hbox1->pack_start($frame0, 1, 1, 0);
    my $frame0lbl = Gtk3::Label->new;
    $frame0lbl->set_markup(' <b>Clustered Terminals</b> ');
    $frame0->set_label_widget($frame0lbl);

    # Terminals list
    my $scroll1 = Gtk3::ScrolledWindow->new;
    $frame0->add($scroll1);
    $scroll1->set_policy('automatic', 'automatic');

    $$self{_WINDOWCLUSTER}{treeTerminals} = Gtk3::SimpleList->new_from_treeview (
        Gtk3::TreeView->new,
        'Opened Terminal(s):' => 'text',
        'UUID:' => 'hidden',
        'Status' => 'pixbuf'
    );

    $scroll1->add($$self{_WINDOWCLUSTER}{treeTerminals});
    $$self{_WINDOWCLUSTER}{treeTerminals}->set_tooltip_text('List of available-unclustered connections');
    $$self{_WINDOWCLUSTER}{treeTerminals}->set_headers_visible(0);
    $$self{_WINDOWCLUSTER}{treeTerminals}->get_selection->set_mode('GTK_SELECTION_MULTIPLE');
    my @col_terminals = $$self{_WINDOWCLUSTER}{treeTerminals}->get_columns;
    $col_terminals[0]->set_expand(1);
    $col_terminals[1]->set_expand(0);

    # Buttons to Add/Del to/from Clusters
    my $vbox2 = Gtk3::VBox->new(0, 0);
    $hbox1->pack_start($vbox2, 0, 1, 0);

    $$self{_WINDOWCLUSTER}{btnadd} = Gtk3::Button->new_with_label("Add to\nCluster");
    $vbox2->pack_start($$self{_WINDOWCLUSTER}{btnadd}, 1, 1, 0);
    $$self{_WINDOWCLUSTER}{btnadd}->set_image(Gtk3::Image->new_from_stock('gtk-go-forward', 'GTK_ICON_SIZE_BUTTON') );
    $$self{_WINDOWCLUSTER}{btnadd}->set_image_position('GTK_POS_BOTTOM');
    $$self{_WINDOWCLUSTER}{btnadd}->set_relief('GTK_RELIEF_NONE');
    $$self{_WINDOWCLUSTER}{btnadd}->set_sensitive(0);

    $$self{_WINDOWCLUSTER}{btndel} = Gtk3::Button->new_with_label("Del from\nCluster");
    $vbox2->pack_start($$self{_WINDOWCLUSTER}{btndel}, 1, 1, 0);
    $$self{_WINDOWCLUSTER}{btndel}->set_image(Gtk3::Image->new_from_stock('gtk-go-back', 'GTK_ICON_SIZE_BUTTON') );
    $$self{_WINDOWCLUSTER}{btndel}->set_image_position('GTK_POS_TOP');
    $$self{_WINDOWCLUSTER}{btndel}->set_relief('GTK_RELIEF_NONE');
    $$self{_WINDOWCLUSTER}{btndel}->set_sensitive(0);

    # Clusters list
    my $vbox3 = Gtk3::VBox->new(0, 0);
    $hbox1->pack_start($vbox3, 1, 1, 0);

    my $frame1 = Gtk3::Frame->new(' Active Clusters');
    $vbox3->pack_start($frame1, 0, 1, 0);
    my $frame1lbl = Gtk3::Label->new();
    $frame1lbl->set_markup(' <b>Active Clusters</b> ');
    $frame1->set_label_widget($frame1lbl);

    my $vbox4 = Gtk3::VBox->new(0, 0);
    $frame1->add($vbox4);

    $$self{_WINDOWCLUSTER}{comboClusters} = Gtk3::ComboBoxText->new();
    $vbox4->pack_start($$self{_WINDOWCLUSTER}{comboClusters}, 0, 1, 0);

    my $sep1 = Gtk3::HSeparator->new;
    $vbox4->pack_start($sep1, 0, 1, 5);

    my $hbuttonbox1 = Gtk3::HButtonBox->new();
    $vbox4->pack_start($hbuttonbox1, 0, 1, 0);
    $hbuttonbox1->set_layout('GTK_BUTTONBOX_EDGE');
    $hbuttonbox1->set_homogeneous(1);

    $$self{_WINDOWCLUSTER}{addCluster} = Gtk3::Button->new_from_stock('gtk-add');
    $hbuttonbox1->add($$self{_WINDOWCLUSTER}{addCluster});
    $$self{_WINDOWCLUSTER}{addCluster}->set('can-focus' => 0);

    $$self{_WINDOWCLUSTER}{delCluster} = Gtk3::Button->new_from_stock('gtk-delete');
    $hbuttonbox1->add($$self{_WINDOWCLUSTER}{delCluster});
    $$self{_WINDOWCLUSTER}{delCluster}->set('can-focus' => 0);
    $$self{_WINDOWCLUSTER}{delCluster}->set_sensitive(0);

    my $frame2 = Gtk3::Frame->new(' Terminals');
    $vbox3->pack_start($frame2, 1, 1, 0);
    my $frame2lbl = Gtk3::Label->new();
    $frame2lbl->set_markup(' <b>Terminals in selected Cluster</b> ');
    $frame2->set_label_widget($frame2lbl);

    my $vbox5 = Gtk3::VBox->new(0, 0);
    $frame2->add($vbox5);

    my $scroll2 = Gtk3::ScrolledWindow->new;
    $vbox5->pack_start($scroll2, 1, 1, 0);
    $scroll2->set_policy('automatic', 'automatic');

    $$self{_WINDOWCLUSTER}{treeClustered} = Gtk3::SimpleList->new_from_treeview (
        Gtk3::TreeView->new,
        'Terminal(s) in cluster:' => 'text',
        'UUID:' => 'hidden',
        'Status' => 'pixbuf'
    );
    $scroll2->add($$self{_WINDOWCLUSTER}{treeClustered});
    $$self{_WINDOWCLUSTER}{treeClustered}->set_headers_visible(0);
    $$self{_WINDOWCLUSTER}{treeClustered}->set_tooltip_text('List of connections included in the selected cluster above');
    $$self{_WINDOWCLUSTER}{treeClustered}->get_selection->set_mode('GTK_SELECTION_MULTIPLE');
    $$self{_WINDOWCLUSTER}{treeClustered}->get_selection->set_mode('GTK_SELECTION_MULTIPLE');
    my @col_cluster = $$self{_WINDOWCLUSTER}{treeClustered}->get_columns;
    $col_cluster[0]->set_expand(1);
    $col_cluster[1]->set_expand(0);

    my $tablbl2 = Gtk3::HBox->new(0, 0);
    my $lbl2 = Gtk3::Label->new;
    $lbl2->set_markup('<b>Saved Clusters </b>');
    $tablbl2->pack_start($lbl2, 0, 1, 0);
    $tablbl2->pack_start(Gtk3::Image->new_from_stock('asbru-cluster-manager', 'menu'), 0, 1, 0);
    $tablbl2->show_all;

    my $hboxclu = Gtk3::HBox->new(0, 0);
    $$self{_WINDOWCLUSTER}{nb}->append_page($hboxclu, $tablbl2);

    # Create a scrolled1 scrolled window to contain the connections tree
    $$self{_WINDOWCLUSTER}{scrollclu} = Gtk3::ScrolledWindow->new;
    $$self{_WINDOWCLUSTER}{scrollclu}->set_policy('automatic', 'automatic');
    $hboxclu->pack_start($$self{_WINDOWCLUSTER}{scrollclu}, 1, 1, 0);

    # Create a treeConnections treeview for connections
    $$self{_WINDOWCLUSTER}{treeConnections} = PACTree->new (
        'Icon:' => 'pixbuf',
        'Name:' => 'hidden',
        'UUID:' => 'hidden',
        'List:' => 'image_text',
    );
    $$self{_WINDOWCLUSTER}{scrollclu}->add($$self{_WINDOWCLUSTER}{treeConnections});
    $$self{_WINDOWCLUSTER}{treeConnections}->set_headers_visible(0);
    $$self{_WINDOWCLUSTER}{treeConnections}->set_enable_search(0);

    # Implement a "TreeModelSort" to auto-sort the data
    my $sort_model_conn = Gtk3::TreeModelSort->new_with_model($$self{_WINDOWCLUSTER}{treeConnections}->get_model);
    $$self{_WINDOWCLUSTER}{treeConnections}->set_model($sort_model_conn);
    $sort_model_conn->set_default_sort_func(\&__treeSort);
    $$self{_WINDOWCLUSTER}{treeConnections}->get_selection->set_mode('GTK_SELECTION_MULTIPLE');

    @{$$self{_WINDOWCLUSTER}{treeConnections}{'data'}} = ({
        value => [$GROUPICON_ROOT, '<b>My Connections</b>', '__PAC__ROOT__'],
        children => []
    });
    my @col = $$self{_WINDOWCLUSTER}{treeConnections}->get_columns;
    $col[0]->set_visible(0);

    # Buttons to Add/Del to/from Clusters
    my $vboxclu1 = Gtk3::VBox->new(0, 0);
    $hboxclu->pack_start($vboxclu1, 0, 1, 0);

    $$self{_WINDOWCLUSTER}{btnadd1} = Gtk3::Button->new_with_label("Add to\nCluster");
    $vboxclu1->pack_start($$self{_WINDOWCLUSTER}{btnadd1}, 1, 1, 0);
    $$self{_WINDOWCLUSTER}{btnadd1}->set_image(Gtk3::Image->new_from_stock('gtk-go-forward', 'GTK_ICON_SIZE_BUTTON') );
    $$self{_WINDOWCLUSTER}{btnadd1}->set_image_position('GTK_POS_BOTTOM');
    $$self{_WINDOWCLUSTER}{btnadd1}->set_relief('GTK_RELIEF_NONE');
    $$self{_WINDOWCLUSTER}{btnadd1}->set_sensitive(0);

    $$self{_WINDOWCLUSTER}{btndel1} = Gtk3::Button->new_with_label("Del from\nCluster");
    $vboxclu1->pack_start($$self{_WINDOWCLUSTER}{btndel1}, 1, 1, 0);
    $$self{_WINDOWCLUSTER}{btndel1}->set_image(Gtk3::Image->new_from_stock('gtk-go-back', 'GTK_ICON_SIZE_BUTTON') );
    $$self{_WINDOWCLUSTER}{btndel1}->set_image_position('GTK_POS_TOP');
    $$self{_WINDOWCLUSTER}{btndel1}->set_relief('GTK_RELIEF_NONE');
    $$self{_WINDOWCLUSTER}{btndel1}->set_sensitive(0);

    # Clusters list
    my $vbox3clu = Gtk3::VBox->new(0, 0);
    $hboxclu->pack_start($vbox3clu, 0, 1, 0);

    my $frame1clu = Gtk3::Frame->new(' Configured Clusters');
    $vbox3clu->pack_start($frame1clu, 0, 1, 0);
    my $frame1lblclu = Gtk3::Label->new;
    $frame1lblclu->set_markup(' <b>Configured Clusters</b> ');
    $frame1clu->set_label_widget($frame1lblclu);

    my $vbox4clu = Gtk3::VBox->new(0, 0);
    $frame1clu->add($vbox4clu);

    $$self{_WINDOWCLUSTER}{comboClusters1} = Gtk3::ComboBoxText->new;
    $vbox4clu->pack_start($$self{_WINDOWCLUSTER}{comboClusters1}, 0, 1, 0);

    $vbox4clu->pack_start(Gtk3::HSeparator->new, 0, 1, 5);

    my $hbuttonbox1clu = Gtk3::HButtonBox->new;
    $vbox4clu->pack_start($hbuttonbox1clu, 0, 1, 0);
    $hbuttonbox1clu->set_layout('GTK_BUTTONBOX_EDGE');
    $hbuttonbox1clu->set_homogeneous(1);

    $$self{_WINDOWCLUSTER}{addCluster1} = Gtk3::Button->new_from_stock('gtk-add');
    $hbuttonbox1clu->add($$self{_WINDOWCLUSTER}{addCluster1});
    $$self{_WINDOWCLUSTER}{addCluster1}->set('can-focus' => 0);

    $$self{_WINDOWCLUSTER}{renCluster1} = Gtk3::Button->new;
    $hbuttonbox1clu->add($$self{_WINDOWCLUSTER}{renCluster1});
    $$self{_WINDOWCLUSTER}{renCluster1}->set_image(Gtk3::Image->new_from_stock('gtk-edit', 'button') );
    $$self{_WINDOWCLUSTER}{renCluster1}->set_label('Rename');
    $$self{_WINDOWCLUSTER}{renCluster1}->set('can-focus' => 0);

    $$self{_WINDOWCLUSTER}{delCluster1} = Gtk3::Button->new_from_stock('gtk-delete');
    $hbuttonbox1clu->add($$self{_WINDOWCLUSTER}{delCluster1});
    $$self{_WINDOWCLUSTER}{delCluster1}->set('can-focus' => 0);
    $$self{_WINDOWCLUSTER}{delCluster1}->set_sensitive(0);

    my $frame2clu = Gtk3::Frame->new(' Terminals');
    $vbox3clu->pack_start($frame2clu, 1, 1, 0);
    my $frame2lblclu = Gtk3::Label->new;
    $frame2lblclu->set_markup(' <b>Terminals in selected cluster</b> ');
    $frame2clu->set_label_widget($frame2lblclu);

    my $vbox5clu = Gtk3::VBox->new(0, 0);
    $frame2clu->add($vbox5clu);

    my $scroll2clu = Gtk3::ScrolledWindow->new;
    $vbox5clu->pack_start($scroll2clu, 1, 1, 0);
    $scroll2clu->set_policy('automatic', 'automatic');

    $$self{_WINDOWCLUSTER}{treeClustered1} = Gtk3::SimpleList->new_from_treeview (
        Gtk3::TreeView->new,
        'Terminal(s) in cluster:' => 'text',
        'UUID:' => 'hidden'
    );
    $scroll2clu->add($$self{_WINDOWCLUSTER}{treeClustered1});
    $$self{_WINDOWCLUSTER}{treeClustered1}->set_headers_visible(0);
    $$self{_WINDOWCLUSTER}{treeClustered1}->set_tooltip_text('List of connections included in the selected cluster above');
    $$self{_WINDOWCLUSTER}{treeClustered1}->get_selection->set_mode('GTK_SELECTION_MULTIPLE');
    $$self{_WINDOWCLUSTER}{treeClustered1}->get_selection->set_mode('GTK_SELECTION_MULTIPLE');

    # Add an "autocluster" tab
    my $tablbl3 = Gtk3::HBox->new(0, 0);
    my $lbl3 = Gtk3::Label->new;
    $lbl3->set_markup('<b>Auto Clusters </b>');
    $tablbl3->pack_start($lbl3, 0, 1, 0);
    $tablbl3->pack_start(Gtk3::Image->new_from_stock('asbru-cluster-manager2', 'menu'), 0, 1, 0);
    $tablbl3->show_all;

    my $hboxautoclu = Gtk3::HBox->new(0, 0);
    $$self{_WINDOWCLUSTER}{nb}->append_page($hboxautoclu, $tablbl3);

    my $vboxaclist = Gtk3::VBox->new;
    $hboxautoclu->pack_start($vboxaclist, 1, 1, 0);

    my $hboxaclistbtns = Gtk3::HBox->new;
    $vboxaclist->pack_start($hboxaclistbtns, 0, 1, 0);

    $$self{_WINDOWCLUSTER}{addAC} = Gtk3::Button->new_from_stock('gtk-add');
    $hboxaclistbtns->add($$self{_WINDOWCLUSTER}{addAC});
    $$self{_WINDOWCLUSTER}{addAC}->set('can-focus' => 0);

    $$self{_WINDOWCLUSTER}{renAC} = Gtk3::Button->new;
    $hboxaclistbtns->add($$self{_WINDOWCLUSTER}{renAC});
    $$self{_WINDOWCLUSTER}{renAC}->set_image(Gtk3::Image->new_from_stock('gtk-edit', 'button') );
    $$self{_WINDOWCLUSTER}{renAC}->set_label('Rename');
    $$self{_WINDOWCLUSTER}{renAC}->set('can-focus' => 0);

    $$self{_WINDOWCLUSTER}{delAC} = Gtk3::Button->new_from_stock('gtk-delete');
    $hboxaclistbtns->add($$self{_WINDOWCLUSTER}{delAC});
    $$self{_WINDOWCLUSTER}{delAC}->set('can-focus' => 0);

    # Create a scrollautoclu scrolled window to contain the connections tree
    my $scrollaclist = Gtk3::ScrolledWindow->new;
    $scrollaclist->set_policy('automatic', 'automatic');
    $vboxaclist->pack_start($scrollaclist, 1, 1, 0);
    $$self{_WINDOWCLUSTER}{treeAutocluster} = Gtk3::SimpleList->new_from_treeview (
        Gtk3::TreeView->new,
        'AUTOCLUSTER' => 'text',
    );
    $scrollaclist->add($$self{_WINDOWCLUSTER}{treeAutocluster});
    $$self{_WINDOWCLUSTER}{treeAutocluster}->set_headers_visible(1);
    $$self{_WINDOWCLUSTER}{treeAutocluster}->get_selection->set_mode('GTK_SELECTION_SINGLE');

    $hboxautoclu->pack_start(Gtk3::VSeparator->new, 0, 1, 5);

    my $frameac = Gtk3::Frame->new;
    $hboxautoclu->pack_start($frameac, 1, 1, 0);
    my $frameaclbl = Gtk3::Label->new;
    $frameaclbl->set_markup(' <b>Auto Matching Properties</b> ');
    $frameac->set_label_widget($frameaclbl);
    $frameac->set_tooltip_text("These entries accept Regular Expressions,like:\n^server\\d+\nor\nconn.*\\d{1,3}\$\nor any other Perl RegExp");

    my $vboxacprops = Gtk3::VBox->new;
    $frameac->add($vboxacprops);

    my $hboxacpname = Gtk3::HBox->new; $vboxacprops->pack_start($hboxacpname, 0, 1, 0);
    $hboxacpname->pack_start(Gtk3::Label->new('Name') , 0, 1, 0);
    $hboxacpname->pack_start($$self{_WINDOWCLUSTER}{entryname} = Gtk3::Entry->new, 1, 1, 0);

    my $hboxacptitle = Gtk3::HBox->new; $vboxacprops->pack_start($hboxacptitle, 0, 1, 0);
    $hboxacptitle->pack_start(Gtk3::Label->new('Title') , 0, 1, 0);
    $hboxacptitle->pack_start($$self{_WINDOWCLUSTER}{entrytitle} = Gtk3::Entry->new, 1, 1, 0);

    my $hboxacphost = Gtk3::HBox->new; $vboxacprops->pack_start($hboxacphost, 0, 1, 0);
    $hboxacphost->pack_start(Gtk3::Label->new('IP/Host') , 0, 1, 0);
    $hboxacphost->pack_start($$self{_WINDOWCLUSTER}{entryhost} = Gtk3::Entry->new, 1, 1, 0);

    my $hboxacpdesc = Gtk3::HBox->new; $vboxacprops->pack_start($hboxacpdesc, 0, 1, 0);
    $hboxacpdesc->pack_start(Gtk3::Label->new('Description') , 0, 1, 0);
    $hboxacpdesc->pack_start($$self{_WINDOWCLUSTER}{entrydesc} = Gtk3::Entry->new, 1, 1, 0);

    $$self{_WINDOWCLUSTER}{btnCheckAC} = Gtk3::Button->new;
    $$self{_WINDOWCLUSTER}{btnCheckAC}->set_image(Gtk3::Image->new_from_stock('gtk-find', 'button') );
    $$self{_WINDOWCLUSTER}{btnCheckAC}->set_label('Check Auto Cluster conditions');
    $$self{_WINDOWCLUSTER}{btnCheckAC}->set('can-focus', 0);
    $vboxacprops->pack_start($$self{_WINDOWCLUSTER}{btnCheckAC} , 1, 1, 5);

    $$self{_WINDOWCLUSTER}{buttonPCC} = Gtk3::Button->new_with_mnemonic('_Power Cluster Controller');
    $$self{_WINDOWCLUSTER}{buttonPCC}->set_image(Gtk3::Image->new_from_stock('gtk-justify-fill', 'button') );
    $vbox0->pack_start($$self{_WINDOWCLUSTER}{buttonPCC}, 0, 1, 5);

    $vbox0->pack_start(Gtk3::HSeparator->new, 0, 1, 0);

    my $hbbox1 = Gtk3::HButtonBox->new;
    $vbox0->pack_start($hbbox1, 0, 1, 5);

    $$self{_WINDOWCLUSTER}{btnOK} = Gtk3::Button->new_from_stock('gtk-ok');
    $hbbox1->set_layout('GTK_BUTTONBOX_END');
    $hbbox1->add($$self{_WINDOWCLUSTER}{btnOK});

    return 1;
}

sub _setupCallbacks {
    my $self = shift;

    ###############################
    # CLUSTERS RELATED CALLBACKS
    ###############################

    my @targets = (Gtk3::TargetEntry->new('PAC Connect', [], 0));
    $$self{_WINDOWCLUSTER}{treeClustered}->drag_dest_set('GTK_DEST_DEFAULT_ALL', \@targets, ['copy', 'move']);
    $$self{_WINDOWCLUSTER}{treeClustered}->signal_connect('drag_motion' => sub {
        $_[0]->get_parent_window->raise;
        return 1;
    });
    $$self{_WINDOWCLUSTER}{treeClustered}->signal_connect('drag_drop' => sub {
        my ($me, $context, $x, $y, $data, $info, $time) = @_;

        my $cluster = $$self{_WINDOWCLUSTER}{comboClusters}->get_active_text;
        if (! $cluster) {
            _wMessage($$self{_WINDOWCLUSTER}{main}, "Before Adding a Terminal to a Cluster, you MUST either:\n - Select an existing CLUSTER\n...or...\n - Create a NEW Cluster");
            return 0;
        }

        my @idx;
        my %tmp;
        foreach my $uuid (@{$PACMain::FUNCS{_MAIN}{'DND'}{'selection'}}) {
            if (($PACMain::FUNCS{_MAIN}{_CFG}{'environments'}{$uuid}{'_is_group'}) || ($uuid eq '__PAC__ROOT__') ) {
                my @children = $PACMain::FUNCS{_MAIN}{_GUI}{treeConnections}->_getChildren($uuid, 0, 1);
                foreach my $child (@children) {
                    $tmp{$child} = 1;
                }
            } else {
                $tmp{$uuid} = 1;
            }
        }
        foreach my $uuid (keys %tmp) {
            push(@idx, [$uuid, undef, $cluster]);
        }
        $PACMain::FUNCS{_MAIN}->_launchTerminals(\@idx);

        delete $$self{'DND'}{'selection'};

        return 1;
    });

    # Capture 'add cluster' button clicked
    $$self{_WINDOWCLUSTER}{buttonPCC}->signal_connect('clicked' => sub {
        $$self{_WINDOWCLUSTER}{main}->hide;
        $PACMain::FUNCS{_PCC}->show;
    });

    # Capture 'comboClusters' change
    # Combo from running clusters
    $$self{_WINDOWCLUSTER}{comboClusters}->signal_connect('changed' => sub {
        $self->_comboClustersChanged;
    });

    # Combo from Saved Clusters
    $$self{_WINDOWCLUSTER}{comboClusters1}->signal_connect('changed' => sub {
        $self->_comboClustersChanged1;
        $self->_updateButtons1;
    });
    # Tree connections
    $$self{_WINDOWCLUSTER}{treeConnections}->get_selection->signal_connect('changed' => sub {
        $self->_updateButtons1;
    });

    $$self{_WINDOWCLUSTER}{treeConnections}->signal_connect('row_expanded' => sub {
        my ($tree, $iter, $path) = @_;

        my $selection = $$self{_WINDOWCLUSTER}{treeConnections}->get_selection;
        my $modelsort = $$self{_WINDOWCLUSTER}{treeConnections}->get_model;
        my $model = $modelsort->get_model;
        my $group_uuid = $model->get_value($modelsort->convert_iter_to_child_iter($modelsort->get_iter($path)), 2);
        if ($group_uuid eq '__PAC__ROOT__') {
            return 0;
        }
        $model->set($modelsort->convert_iter_to_child_iter($modelsort->get_iter($path)), 0, $GROUPICONOPEN);
        foreach my $child ($$self{_WINDOWCLUSTER}{treeConnections}->_getChildren($group_uuid, 1, 0)) {
            $model->set($modelsort->convert_iter_to_child_iter($modelsort->get_iter($$self{_WINDOWCLUSTER}{treeConnections}->_getPath($child))), 0, $GROUPICONCLOSED);
        }
        return 1;
    });

    $$self{_WINDOWCLUSTER}{treeClustered1}->get_selection->signal_connect('changed' => sub {
        $self->_updateButtons1;
    });
    $$self{_WINDOWCLUSTER}{treeClustered1}->signal_connect('row_activated' => sub {
        $$self{_WINDOWCLUSTER}{btndel1}->activate;
    });
    $$self{_WINDOWCLUSTER}{btnadd1}->signal_connect('clicked' => sub {
        my @sel_uuids = $$self{_WINDOWCLUSTER}{treeConnections}->_getSelectedUUIDs;
        my $total = scalar(@sel_uuids);
        my $is_root = 0;
        my $uuid = $sel_uuids[0];
        my $cluster = $$self{_WINDOWCLUSTER}{comboClusters1}->get_active_text;
        my $envs = $PACMain::{FUNCS}{_MAIN}{_CFG}{environments};

        foreach my $uuid (@sel_uuids) {
            if ($uuid eq '__PAC__ROOT__') {
                $is_root = 1;
                last;
            }
        }

        if (! ($total && (defined $cluster) && ($cluster ne '') )) {
            _wMessage($$self{_WINDOWCLUSTER}{main}, "Before Adding a Terminal to a Cluster, you MUST either:\n - Select an existing CLUSTER\n...or...\n - Create a NEW Cluster");
            return 1;
        }

        foreach my $uuid (@sel_uuids) {
            if (! $$envs{$uuid}{_is_group}) {
                if (defined $$self{CLUSTERS}{$cluster}{$uuid}) {
                    next;
                }
                $$self{CLUSTERS}{$cluster}{$uuid} = 1;
                push(@{$$envs{$uuid}{cluster}}, $cluster);
            } else {
                foreach my $subuuid ($$self{_WINDOWCLUSTER}{treeConnections}->_getChildren($uuid, 0, 1)) {
                    if ($$envs{$subuuid}{_is_group} || defined $$self{CLUSTERS}{$cluster}{$subuuid}) {
                        next;
                    }
                    $$self{CLUSTERS}{$cluster}{$subuuid} = 1;
                    push(@{$$envs{$subuuid}{cluster}}, $cluster);
                }
            }
        }

        $self->_comboClustersChanged1;
        my $i = -1;
        foreach my $aux_cluster (sort {uc($a) cmp uc($b)} keys %{$$self{CLUSTERS}}) {
            ++$i;
            if ($cluster ne $aux_cluster) {
                next;
            }
            if ($cluster eq $aux_cluster) {
                $$self{_WINDOWCLUSTER}{comboClusters1}->set_active($i);
            }
            last;
        }

        $self->_updateButtons1;

        #$PACMain::{FUNCS}{_MAIN}{_CFG}{tmp}{changed} = 1;
        $PACMain::FUNCS{_MAIN}->_setCFGChanged(1);
        if ($PACMain::{FUNCS}{_MAIN}{_GUI}{nbTree}->get_nth_page($PACMain::{FUNCS}{_MAIN}{_GUI}{nbTree}->get_current_page) eq $PACMain::{FUNCS}{_MAIN}{_GUI}{vboxclu}) {
            $PACMain::{FUNCS}{_MAIN}->_updateClustersList;
        }

        return 1;
    });

    $$self{_WINDOWCLUSTER}{btndel1}->signal_connect('clicked' => sub {
        my $cluster = $$self{_WINDOWCLUSTER}{comboClusters1}->get_active_text;
        my $total = $$self{_WINDOWCLUSTER}{treeClustered1}->get_selected_indices;
        my @select = $$self{_WINDOWCLUSTER}{treeClustered1}->get_selected_indices;
        if (!($total && (defined $cluster) && ($cluster ne ''))) {
            return 1;
        }
        foreach my $sel (sort {$a > $b} @select) {
            my $uuid = $$self{_WINDOWCLUSTER}{treeClustered1}->{data}[$sel][1];
            my $i = -1;
            foreach my $clu (@{$PACMain::{FUNCS}{_MAIN}{_CFG}{environments}{$uuid}{cluster}}) {
                ++$i;
                if ($clu ne $cluster) {
                    next;
                }
                splice(@{$PACMain::{FUNCS}{_MAIN}{_CFG}{environments}{$uuid}{cluster}}, $i, 1);
                last;
            }
        }

        $self->_updateButtons1;
        $self->_updateGUI1;

        #$PACMain::{FUNCS}{_MAIN}{_CFG}{tmp}{changed} = 1;
        $PACMain::FUNCS{_MAIN}->_setCFGChanged(1);
        if ($PACMain::{FUNCS}{_MAIN}{_GUI}{nbTree}->get_nth_page($PACMain::{FUNCS}{_MAIN}{_GUI}{nbTree}->get_current_page) eq $PACMain::{FUNCS}{_MAIN}{_GUI}{vboxclu}) {
            $PACMain::{FUNCS}{_MAIN}->_updateClustersList;
        }

        return 1;
    });

    # Capture 'add cluster' button clicked
    $$self{_WINDOWCLUSTER}{addCluster}->signal_connect('clicked' => sub {
        my $new_cluster = _wEnterValue($$self{_WINDOWCLUSTER}{main}, 'Enter a name for the <b>New Cluster</b>');

        if ((! defined $new_cluster) || ($new_cluster =~ /^\s*$/go)) {
            return 1;
        } elsif (defined $$self{_CLUSTERS}{$new_cluster}) {
            _wMessage($$self{_WINDOWCLUSTER}{main}, "Cluster '$new_cluster' already exists!!");
        }

        # Empty the environments combobox
        $$self{_WINDOWCLUSTER}{comboClusters}->remove_all();
        $$self{_CLUSTERS}{$new_cluster}{1} = undef;

        # Re-populate the clusters combobox
        my $i = 0;
        my $j = 0;
        foreach my $cluster (sort {uc($a) cmp uc($b)} keys %{$$self{_CLUSTERS}}) {
            $j = $i;
            $$self{_WINDOWCLUSTER}{comboClusters}->append_text($cluster);
            if ($cluster eq $new_cluster) {
                $$self{_WINDOWCLUSTER}{comboClusters}->set_active($j);
            }
            ++$i;
        }
        $$self{_WINDOWCLUSTER}{delCluster}->set_sensitive(1);
        return 1;
    });

    # Capture 'add cluster 1' button clicked
    $$self{_WINDOWCLUSTER}{addCluster1}->signal_connect('clicked' => sub {
        my $new_cluster = _wEnterValue($$self{_WINDOWCLUSTER}{main}, 'Enter a name for the <b>New Cluster</b>');

        if ((!defined $new_cluster)||($new_cluster =~ /^\s*$/go)) {
            return 1;
        }
        if (defined $$self{CLUSTERS}{$new_cluster}) {
            _wMessage($$self{_WINDOWCLUSTER}{main}, "Cluster '$new_cluster' already exists!!");
            return 1;
        }
        if (defined $PACMain::{FUNCS}{_MAIN}{_CFG}{defaults}{'auto cluster'}{$new_cluster}) {
            _wMessage($$self{_WINDOWCLUSTER}{main}, "Auto Cluster name '$new_cluster' already exists!!");
            return 1;
        }

        # Empty the environments combobox
        $$self{_WINDOWCLUSTER}{comboClusters1}->remove_all();
        $$self{CLUSTERS}{$new_cluster} = undef;

        # Re-populate the clusters combobox
        my $i = 0;
        my $j = 0;
        foreach my $cluster (sort {uc($a) cmp uc($b)} keys %{$$self{CLUSTERS}}) {
            $j = $i;
            $$self{_WINDOWCLUSTER}{comboClusters1}->append_text($cluster);
            if ($cluster eq $new_cluster) {
                $$self{_WINDOWCLUSTER}{comboClusters1}->set_active($j);
            }
            ++$i;
        }

        $self->_updateButtons1;
        if ($PACMain::{FUNCS}{_MAIN}{_GUI}{nbTree}->get_nth_page($PACMain::{FUNCS}{_MAIN}{_GUI}{nbTree}->get_current_page) eq $PACMain::{FUNCS}{_MAIN}{_GUI}{vboxclu}) {
            $PACMain::{FUNCS}{_MAIN}->_updateClustersList;
        }
        #$PACMain::{FUNCS}{_MAIN}{_CFG}{tmp}{changed} = 1;
        $PACMain::FUNCS{_MAIN}->_setCFGChanged(1);
        return 1;
    });

    # Capture 'rename cluster 1' button clicked
    $$self{_WINDOWCLUSTER}{renCluster1}->signal_connect('clicked' => sub {
        my $old_cluster = $$self{_WINDOWCLUSTER}{comboClusters1}->get_active_text;
        my $new_cluster = _wEnterValue($$self{_WINDOWCLUSTER}{main}, "Enter a <b>NEW</b> name for cluster <b>$old_cluster</b>", undef, $old_cluster);

        if ((! defined $new_cluster) || ($new_cluster =~ /^\s*$/go)) {
            return 1;
        }
        if (defined $$self{CLUSTERS}{$new_cluster}) {
            _wMessage($$self{_WINDOWCLUSTER}{main}, "Cluster name '$new_cluster' already exists!!");
            return 1;
        }

        # Remove this cluster's reference from every connection
        foreach my $uuid (keys %{$PACMain::{FUNCS}{_MAIN}{_CFG}{environments}}) {
            if ($PACMain::{FUNCS}{_MAIN}{_CFG}{environments}{$uuid}{_is_group} || $uuid eq '__PAC__ROOT__') {
                next;
            }
            my $i = -1;
            foreach my $clu (@{$PACMain::{FUNCS}{_MAIN}{_CFG}{environments}{$uuid}{cluster}}) {
                ++$i;
                if ($clu ne $old_cluster) {
                    next;
                }
                splice(@{$PACMain::{FUNCS}{_MAIN}{_CFG}{environments}{$uuid}{cluster}}, $i, 1, $new_cluster);
                last;
            }
        }

        $self->_updateGUI1($new_cluster);
        $self->_updateButtons1;
        if ($PACMain::{FUNCS}{_MAIN}{_GUI}{nbTree}->get_nth_page($PACMain::{FUNCS}{_MAIN}{_GUI}{nbTree}->get_current_page) eq $PACMain::{FUNCS}{_MAIN}{_GUI}{vboxclu}) {
            $PACMain::{FUNCS}{_MAIN}->_updateClustersList;
        }
        #$PACMain::{FUNCS}{_MAIN}{_CFG}{tmp}{changed} = 1;
        $PACMain::FUNCS{_MAIN}->_setCFGChanged(1);
        return 1;
    });

    # Capture 'delete cluster' button clicked
    $$self{_WINDOWCLUSTER}{delCluster}->signal_connect('clicked' => sub {
        # Get the string of the active cluster
        my $cluster = $$self{_WINDOWCLUSTER}{comboClusters}->get_active_text();

        if (!_wConfirm($$self{_WINDOWCLUSTER}{main}, "Delete cluster <b>'$cluster'</b>?")) {
            return 1;
        }

        $$self{_WINDOWCLUSTER}{treeClustered}->select(0..1000);    # Select every terminal in this cluster...
        $$self{_WINDOWCLUSTER}{btndel}->clicked;                    # ... and click the "delete" button
        # Remove this cluster's reference from every connection
        foreach my $uuid (keys %{$$self{_RUNNING}}) {
            #$$self{_RUNNING}{$uuid}{'terminal'}{_CLUSTER} = '' if $$self{_RUNNING}{$uuid}{'terminal'}{_CLUSTER} eq $cluster;
            if ($$self{_RUNNING}{$uuid}{'terminal'}{_CLUSTER} ne $cluster) {
                next;
            }
            $self->delFromCluster($uuid, $cluster);
        }

        # Empty the clusters combobox
        $$self{_WINDOWCLUSTER}{comboClusters}->remove_all();

        # Delete selected cluster
        delete $$self{_CLUSTERS}{$cluster};

        # Re-populate the clusters combobox
        foreach my $new_cluster (sort {uc($a) cmp uc($b)} keys %{$$self{_CLUSTERS}}) {
            $$self{_WINDOWCLUSTER}{comboClusters}->append_text($new_cluster);
        }

        $$self{_WINDOWCLUSTER}{comboClusters}->set_active(0);
        $self->_updateGUI;

        return 1;
    });

    # Capture 'delete cluster' button clicked
    $$self{_WINDOWCLUSTER}{delCluster1}->signal_connect('clicked' => sub {
        # Get the string of the active cluster
        my $cluster = $$self{_WINDOWCLUSTER}{comboClusters1}->get_active_text // '';

        if (!_wConfirm($$self{_WINDOWCLUSTER}{main}, "Delete cluster <b>'$cluster'</b>?")) {
            return 1;
        }

        # Remove this cluster's reference from every connection
        foreach my $uuid (keys %{$PACMain::{FUNCS}{_MAIN}{_CFG}{environments}}) {
            if ($PACMain::{FUNCS}{_MAIN}{_CFG}{environments}{$uuid}{_is_group} || $uuid eq '__PAC__ROOT__') {
                next;
            }
            my $i = -1;
            foreach my $clu (@{$PACMain::{FUNCS}{_MAIN}{_CFG}{environments}{$uuid}{cluster}}) {
                ++$i;
                if ($clu ne $cluster) {
                    next;
                }
                splice(@{$PACMain::{FUNCS}{_MAIN}{_CFG}{environments}{$uuid}{cluster}}, $i, 1);
                last;
            }
        }

        # Check if user want to take running terminals from deleted cluster
        my $i = 0;
        foreach my $uuid (keys %{$$self{_RUNNING}}) {
            if ($$self{_RUNNING}{$uuid}{terminal}{_CLUSTER} eq $cluster) {
                $i++;
            }
        }
        if ($i && _wConfirm($$self{_WINDOWCLUSTER}{main}, "Remove running terminals from deleted cluster <b>'$cluster'</b>?")) {
            foreach my $uuid (keys %{$$self{_RUNNING}}) {
                if ($$self{_RUNNING}{$uuid}{terminal}{_CLUSTER} ne $cluster) {
                    next;
                }
                $$self{_RUNNING}{$uuid}{terminal}{_CLUSTER} = '';
                $$self{_RUNNING}{$uuid}{'terminal'}->_updateStatus;
                $self->_updateGUI;
            }
        }
        $self->_updateButtons1;
        $self->_updateGUI1;
        if ($PACMain::{FUNCS}{_MAIN}{_GUI}{nbTree}->get_nth_page($PACMain::{FUNCS}{_MAIN}{_GUI}{nbTree}->get_current_page) eq $PACMain::{FUNCS}{_MAIN}{_GUI}{vboxclu}) {
            $PACMain::{FUNCS}{_MAIN}->_updateClustersList;
        }
        #$PACMain::{FUNCS}{_MAIN}{_CFG}{tmp}{changed} = 1;
        $PACMain::FUNCS{_MAIN}->_setCFGChanged(1);

        return 1;
    });

    $$self{_WINDOWCLUSTER}{treeClustered}->signal_connect('cursor_changed' => sub {
        $$self{_WINDOWCLUSTER}{btndel}->set_sensitive(scalar(@{$$self{_WINDOWCLUSTER}{treeClustered}->{data}}));
    });

    # Capture 'treeTerminals' row activated
    $$self{_WINDOWCLUSTER}{treeClustered}->signal_connect('row_activated' => sub {
        my ($index) = $$self{_WINDOWCLUSTER}{treeClustered}->get_selected_indices;
        if (!defined $index) {
            return;
        }
        $$self{_WINDOWCLUSTER}{btndel}->clicked;
        return 1;
    });

    # Add terminal to selected cluster
    $$self{_WINDOWCLUSTER}{btnadd}->signal_connect('clicked' => sub {
        my $cluster = $$self{_WINDOWCLUSTER}{comboClusters}->get_active_text;
        my $total = $$self{_WINDOWCLUSTER}{treeTerminals}->get_selected_indices;
        my @select = $$self{_WINDOWCLUSTER}{treeTerminals}->get_selected_indices;
        if (!($total && (defined $cluster) && ($cluster ne ''))) {
            _wMessage($$self{_WINDOWCLUSTER}{main}, "Before Adding a Terminal to a Cluster, you MUST either:\n - Select an existing CLUSTER\n...or...\n - Create a NEW Cluster");

            $cluster = _wEnterValue($$self{_WINDOWCLUSTER}{main}, 'Enter a name for the <b>New Cluster</b>');

            if ((!defined $cluster) || ($cluster =~ /^\s*$/go) ) {
                return 1;
            } elsif (defined $$self{_CLUSTERS}{$cluster}) {
                _wMessage($$self{_WINDOWCLUSTER}{main}, "Cluster '$cluster' already exists!!");
                return 1;
            }

            # Empty the environments combobox
            $$self{_WINDOWCLUSTER}{comboClusters}->remove_all();
            $$self{_CLUSTERS}{$cluster}{1} = undef;

            # Re-populate the clusters combobox
            my $i = 0;
            my $j = 0;
            foreach my $clt (sort {uc($a) cmp uc($b)} keys %{$$self{_CLUSTERS}}) {
                $j = $i;
                $$self{_WINDOWCLUSTER}{comboClusters}->append_text($clt);
                if ($clt eq $cluster) {
                    $$self{_WINDOWCLUSTER}{comboClusters}->set_active($j);
                }
                ++$i;
            }
            $$self{_WINDOWCLUSTER}{delCluster}->set_sensitive(1);
        }
        foreach my $sel (sort {$a < $b} @select) {
            my $uuid = $$self{_WINDOWCLUSTER}{treeTerminals}->{data}[$sel][1];
            $self->addToCluster($uuid, $cluster);
        }
        return 1;
    });

    # Remove selected terminal from current cluster
    $$self{_WINDOWCLUSTER}{btndel}->signal_connect('clicked' => sub {
        my $cluster = $$self{_WINDOWCLUSTER}{comboClusters}->get_active_text;
        my $total = $$self{_WINDOWCLUSTER}{treeClustered}->get_selected_indices;
        my @select = $$self{_WINDOWCLUSTER}{treeClustered}->get_selected_indices;
        if (!($total && (defined $cluster) && ($cluster ne ''))) {
            return 1;
        }

        foreach my $sel (sort {$a < $b} @select) {
            my $uuid = $$self{_WINDOWCLUSTER}{treeClustered}->{data}[$sel][1];
            $self->delFromCluster($uuid, $cluster);
        }
        $$self{_WINDOWCLUSTER}{btndel}->set_sensitive(scalar(@{$$self{_WINDOWCLUSTER}{treeClustered}->{data}}) );
        return 1;
    });


    $$self{_WINDOWCLUSTER}{treeConnections}->signal_connect('row_activated' => sub {
        my @sel = $$self{_WINDOWCLUSTER}{treeConnections}->_getSelectedUUIDs;

        my $is_group = 0;
        my $is_root = 0;
        foreach my $uuid (@sel) {
            if ($uuid eq '__PAC__ROOT__') {
                $is_root = 1;
            }
            if ($PACMain::{FUNCS}{_MAIN}{_CFG}{'environments'}{$uuid}{'_is_group'}) {
                $is_group = 1;
            }
        }

        my @idx;
        foreach my $uuid (@sel) {push(@idx, [$uuid]);}
        if (scalar @idx != 1) {
            return 0;
        }

        my $tree = $$self{_WINDOWCLUSTER}{treeConnections};
        my $selection = $tree->get_selection;
        my $model = $tree->get_model;
        my @paths = _getSelectedRows($selection);
        my $uuid = $model->get_value($model->get_iter($paths[0]), 2);

        if (!(($uuid eq '__PAC__ROOT__') || ($PACMain::{FUNCS}{_MAIN}{_CFG}{'environments'}{$uuid}{'_is_group'}))) {
            $$self{_WINDOWCLUSTER}{btnadd1}->activate;
        }
        if (!(($uuid eq '__PAC__ROOT__') || ($PACMain::{FUNCS}{_MAIN}{_CFG}{'environments'}{$uuid}{'_is_group'}))) {
            return 0;
        }
        if ($tree->row_expanded($$self{_WINDOWCLUSTER}{treeConnections}->_getPath($uuid))) {
            $tree->collapse_row($$self{_WINDOWCLUSTER}{treeConnections}->_getPath($uuid));
        } elsif ($uuid ne '__PAC__ROOT__') {
            $tree->expand_row($paths[0], 0);
        }
    });

    $$self{_WINDOWCLUSTER}{treeConnections}->signal_connect('row_collapsed' => sub {
        my ($tree, $iter, $path) = @_;

        my $selection = $$self{_WINDOWCLUSTER}{treeConnections}->get_selection;
        my $modelsort = $$self{_WINDOWCLUSTER}{treeConnections}->get_model;
        my $model = $modelsort->get_model;
        my $group_uuid = $model->get_value($modelsort->convert_iter_to_child_iter($modelsort->get_iter($path)), 2);
        $$self{_WINDOWCLUSTER}{treeConnections}->columns_autosize;
        if ($group_uuid eq '__PAC__ROOT__') {
            return 0;
        }
        $model->set($modelsort->convert_iter_to_child_iter($modelsort->get_iter($path)), 0, $GROUPICONCLOSED);
        return 1;
    });

    $$self{_WINDOWCLUSTER}{treeConnections}->signal_connect('key_press_event' => sub {
        my ($widget, $event) = @_;

        my $keyval = '' . ($event->keyval);
        my $state = '' . ($event->state);
        #print "KEY MASK:" . ($event->state) . "\n";
        #print "KEY PRESSED:" . $event->keyval . ":" . (chr($event->keyval) ) . "\n";

        my @sel = $$self{_WINDOWCLUSTER}{treeConnections}->_getSelectedUUIDs;

        my $is_group = 0;
        my $is_root = 0;
        foreach my $uuid (@sel) {
            if ($uuid eq '__PAC__ROOT__') {
                $is_root = 1;
            }
            if ($PACMain::{FUNCS}{_MAIN}{_CFG}{'environments'}{$uuid}{'_is_group'}) {
                $is_group = 1;
            }
        }

        # Capture 'left arrow'  keypress to collapse row
        if ($event->keyval == 65361) {
            my @idx;
            foreach my $uuid (@sel) {
                push(@idx, [$uuid]);
            }
            if (scalar @idx != 1) {
                return 0;
            }

            my $tree = $$self{_WINDOWCLUSTER}{treeConnections};
            my $selection = $tree->get_selection;
            my $model = $tree->get_model;
            my @paths = _getSelectedRows($selection);
            my $uuid = $model->get_value($model->get_iter($paths[0]), 2);

            if (($uuid eq '__PAC__ROOT__') || ($PACMain::{FUNCS}{_MAIN}{_CFG}{'environments'}{$uuid}{'_is_group'})) {
                if ($tree->row_expanded($$self{_WINDOWCLUSTER}{treeConnections}->_getPath($uuid))) {
                    $tree->collapse_row($$self{_WINDOWCLUSTER}{treeConnections}->_getPath($uuid));
                } elsif ($uuid ne '__PAC__ROOT__') {
                    $tree->set_cursor($$self{_WINDOWCLUSTER}{treeConnections}->_getPath($PACMain::{FUNCS}{_MAIN}{_CFG}{'environments'}{$uuid}{'parent'}), undef, 0);
                }
            } else {
                $tree->set_cursor($$self{_WINDOWCLUSTER}{treeConnections}->_getPath($PACMain::{FUNCS}{_MAIN}{_CFG}{'environments'}{$uuid}{'parent'}), undef, 0);
            }
        }
        # Capture 'right arrow' or 'intro' keypress to expand row
        elsif ($event->keyval == 65363)#|| $event->keyval == 65293)
        {
            my @idx;
            foreach my $uuid (@sel) {
                push(@idx, [$uuid]);
            }
            if (scalar @idx != 1) {
                return 0;
            }

            my $tree = $$self{_WINDOWCLUSTER}{treeConnections};
            my $selection = $tree->get_selection;
            my $model = $tree->get_model;
            my @paths = _getSelectedRows($selection);
            my $uuid = $model->get_value($model->get_iter($paths[0]), 2);

            if (!(($uuid eq '__PAC__ROOT__') || ($PACMain::{FUNCS}{_MAIN}{_CFG}{'environments'}{$uuid}{'_is_group'}))) {
                return 0;
            }
            $tree->expand_row($paths[0], 0);
        }
    });

    $$self{_WINDOWCLUSTER}{treeAutocluster}->get_selection->signal_connect('changed' => sub {
        my @selection = $$self{_WINDOWCLUSTER}{treeAutocluster}->get_selected_indices;
        if (scalar(@selection) != 1) {
            return 1;
        }
        $$self{_UPDATING} = 1;
        my $sel = $selection[0];
        my $ac = $$self{_WINDOWCLUSTER}{treeAutocluster}{data}[$sel][0];
        my $name = $PACMain::FUNCS{_MAIN}{_CFG}{defaults}{'auto cluster'}{$ac}{name} // '';
        my $host = $PACMain::FUNCS{_MAIN}{_CFG}{defaults}{'auto cluster'}{$ac}{host} // '';
        my $title = $PACMain::FUNCS{_MAIN}{_CFG}{defaults}{'auto cluster'}{$ac}{title} // '';
        my $desc = $PACMain::FUNCS{_MAIN}{_CFG}{defaults}{'auto cluster'}{$ac}{desc} // '';

        $$self{_WINDOWCLUSTER}{entryname}->set_text($name);
        $$self{_WINDOWCLUSTER}{entryhost}->set_text($host);
        $$self{_WINDOWCLUSTER}{entrytitle}->set_text($title);
        $$self{_WINDOWCLUSTER}{entrydesc}->set_text($desc);
        $self->_updateButtonsAC;
        $$self{_UPDATING} = 0;

        return 1;
    });

    $$self{_WINDOWCLUSTER}{addAC}->signal_connect('clicked' => sub {
        my $new_ac = _wEnterValue($$self{_WINDOWCLUSTER}{main}, 'Enter new <b>AUTO CLUSTER</b> name');
        if ((! defined $new_ac) || ($new_ac =~ /^\s*$/go)) {
            return 1;
        }
        if (defined $PACMain::FUNCS{_MAIN}{_CFG}{defaults}{'auto cluster'}{$new_ac}) {
            _wMessage($$self{_WINDOWCLUSTER}{main}, "AutoCluster name '$new_ac' already exists!!");
            return 1;
        }
        my $clusters = $self->getCFGClusters;
        if (defined $$clusters{$new_ac}) {
            _wMessage($$self{_WINDOWCLUSTER}{main}, "Cluster name '$new_ac' already exists!!");
            return 1;
        }

        $PACMain::FUNCS{_MAIN}{_CFG}{defaults}{'auto cluster'}{$new_ac}{name} = '';
        $PACMain::FUNCS{_MAIN}{_CFG}{defaults}{'auto cluster'}{$new_ac}{title} = '';
        $PACMain::FUNCS{_MAIN}{_CFG}{defaults}{'auto cluster'}{$new_ac}{host} = '';
        $PACMain::FUNCS{_MAIN}{_CFG}{defaults}{'auto cluster'}{$new_ac}{desc} = '';

        $self->_updateGUIAC($new_ac);
        $$self{_WINDOWCLUSTER}{entryname}->grab_focus;

        if ($PACMain::{FUNCS}{_MAIN}{_GUI}{nbTree}->get_nth_page($PACMain::{FUNCS}{_MAIN}{_GUI}{nbTree}->get_current_page) eq $PACMain::{FUNCS}{_MAIN}{_GUI}{vboxclu}) {
            $PACMain::{FUNCS}{_MAIN}->_updateClustersList;
        }
        #$PACMain::{FUNCS}{_MAIN}{_CFG}{tmp}{changed} = 1;
        $PACMain::FUNCS{_MAIN}->_setCFGChanged(1);
        return 1;
    });
    $$self{_WINDOWCLUSTER}{renAC}->signal_connect('clicked' => sub {
        my @selected = $$self{_WINDOWCLUSTER}{treeAutocluster}->get_selected_indices;
        if (!@selected) {
            return 1;
        }
        my $sel = $selected[0];
        my $old_cluster = $$self{_WINDOWCLUSTER}{treeAutocluster}{data}[$sel][0];
        my $new_cluster = _wEnterValue($$self{_WINDOWCLUSTER}{main}, "Enter a <b>NEW</b> name for Auto Cluster <b>$old_cluster</b>", undef, $old_cluster);
        if ((! defined $new_cluster) || ($new_cluster =~ /^\s*$/go)) {
            return 1;
        }
        my $clusters = $self->getCFGClusters;
        if (defined $$clusters{$new_cluster}) {
            _wMessage($$self{_WINDOWCLUSTER}{main}, "Cluster name '$new_cluster' already exists!!");
            return 1;
        }
        if (defined $PACMain::{FUNCS}{_MAIN}{_CFG}{defaults}{'auto cluster'}{$new_cluster}) {
            _wMessage($$self{_WINDOWCLUSTER}{main}, "Auto Cluster name '$new_cluster' already exists!!");
            return 1;
        }

        $PACMain::{FUNCS}{_MAIN}{_CFG}{defaults}{'auto cluster'}{$new_cluster} = dclone($PACMain::{FUNCS}{_MAIN}{_CFG}{defaults}{'auto cluster'}{$old_cluster});
        delete $PACMain::{FUNCS}{_MAIN}{_CFG}{defaults}{'auto cluster'}{$old_cluster};
        $self->_updateGUIAC($new_cluster);

        if ($PACMain::{FUNCS}{_MAIN}{_GUI}{nbTree}->get_nth_page($PACMain::{FUNCS}{_MAIN}{_GUI}{nbTree}->get_current_page) eq $PACMain::{FUNCS}{_MAIN}{_GUI}{vboxclu}) {
            $PACMain::{FUNCS}{_MAIN}->_updateClustersList;
        }
        #$PACMain::{FUNCS}{_MAIN}{_CFG}{tmp}{changed} = 1;
        $PACMain::FUNCS{_MAIN}->_setCFGChanged(1);
        return 1;
    });
    $$self{_WINDOWCLUSTER}{delAC}->signal_connect('clicked' => sub {
        my @selected = $$self{_WINDOWCLUSTER}{treeAutocluster}->get_selected_indices;
        if (!@selected) {
            return 1;
        }
        my $sel = $selected[0];
        my $cluster = $$self{_WINDOWCLUSTER}{treeAutocluster}{data}[$sel][0];
        if (!_wConfirm($$self{_WINDOWCLUSTER}{main}, "Are you sure you want to delete Auto Cluster <b>$cluster</b>?")) {
            return 1;
        }
        delete $PACMain::FUNCS{_MAIN}{_CFG}{defaults}{'auto cluster'}{$cluster};

        $self->_updateGUIAC;
        # Check if user want to take running terminals from deleted cluster
        my $i = 0;
        foreach my $uuid (keys %{$$self{_RUNNING}}) {
            if ($$self{_RUNNING}{$uuid}{terminal}{_CLUSTER} eq $cluster) {
                $i++;
            }
        }
        if ($i && _wConfirm($$self{_WINDOWCLUSTER}{main}, "Remove running terminals from deleted cluster <b>'$cluster'</b>?")) {
            foreach my $uuid (keys %{$$self{_RUNNING}}) {
                if ($$self{_RUNNING}{$uuid}{terminal}{_CLUSTER} ne $cluster) {
                    next;
                }
                $$self{_RUNNING}{$uuid}{terminal}{_CLUSTER} = '';
                $$self{_RUNNING}{$uuid}{'terminal'}->_updateStatus;
                $self->_updateGUI;
            }
        }
        if ($PACMain::{FUNCS}{_MAIN}{_GUI}{nbTree}->get_nth_page($PACMain::{FUNCS}{_MAIN}{_GUI}{nbTree}->get_current_page) eq $PACMain::{FUNCS}{_MAIN}{_GUI}{vboxclu}) {
            $PACMain::{FUNCS}{_MAIN}->_updateClustersList;
        }
        #$PACMain::{FUNCS}{_MAIN}{_CFG}{tmp}{changed} = 1;
        $PACMain::FUNCS{_MAIN}->_setCFGChanged(1);
        return 1;
    });

    foreach my $entry ('name', 'host', 'title', 'desc') {
        $$self{_WINDOWCLUSTER}{"entry${entry}"}->signal_connect('changed' => sub {
            my @selected = $$self{_WINDOWCLUSTER}{treeAutocluster}->get_selected_indices;
            if (!@selected) {
                return 1;
            }
            if ($$self{_CHANGING}) {
                return 1;
            }
            my $sel = $selected[0];
            my $cluster = $$self{_WINDOWCLUSTER}{treeAutocluster}{data}[$sel][0];
            my $text = $$self{_WINDOWCLUSTER}{"entry${entry}"}->get_chars(0, -1);
            $PACMain::FUNCS{_MAIN}{_CFG}{defaults}{'auto cluster'}{$cluster}{$entry} = $text;
            #$PACMain::FUNCS{_MAIN}{_CFG}{tmp}{changed} = 1 unless $$self{_UPDATING};
            if ($$self{_UPDATING}) {
                $PACMain::FUNCS{_MAIN}->_setCFGChanged(1);
            }
        });
    }
    $$self{_WINDOWCLUSTER}{btnCheckAC}->signal_connect('clicked' => sub {
        my @selected = $$self{_WINDOWCLUSTER}{treeAutocluster}->get_selected_indices;
        if (!@selected) {
            return 1;
        }
        my $sel = $selected[0];
        my $cluster = $$self{_WINDOWCLUSTER}{treeAutocluster}{data}[$sel][0];

        my $cond = '';
        if ($PACMain::FUNCS{_MAIN}{_CFG}{defaults}{'auto cluster'}{$cluster}{name} ne '') {
            $cond .= "\nname =~ /$PACMain::FUNCS{_MAIN}{_CFG}{defaults}{'auto cluster'}{$cluster}{name}/";
        }
        if ($PACMain::FUNCS{_MAIN}{_CFG}{defaults}{'auto cluster'}{$cluster}{host} ne '') {
            $cond .= "\nhost =~ /$PACMain::FUNCS{_MAIN}{_CFG}{defaults}{'auto cluster'}{$cluster}{host}/";
        }
        if ($PACMain::FUNCS{_MAIN}{_CFG}{defaults}{'auto cluster'}{$cluster}{title} ne '') {
            $cond .= "\ntitle =~ /$PACMain::FUNCS{_MAIN}{_CFG}{defaults}{'auto cluster'}{$cluster}{title}/";
        }
        if ($PACMain::FUNCS{_MAIN}{_CFG}{defaults}{'auto cluster'}{$cluster}{desc} ne '') {
            $cond .= "\ndescription =~ /$PACMain::FUNCS{_MAIN}{_CFG}{defaults}{'auto cluster'}{$cluster}{desc}/";
        }

        # Why no Gtk3::MessageDialog->new_with_markup() available??
        my $windowConfirm = Gtk3::MessageDialog->new(
            $$self{_WINDOWCLUSTER}{main},
            'GTK_DIALOG_DESTROY_WITH_PARENT',
            'GTK_MESSAGE_INFO',
            'none',
            ''
        );
        $windowConfirm->set_markup("Terminals matching Auto Cluster <b>$cluster</b> conditions:$cond");
        $windowConfirm->set_icon_name('asbru-app-big');
        $windowConfirm->set_title("$APPNAME (v$APPVERSION) : Auto Cluster matching");
        $windowConfirm->add_buttons('gtk-ok' => 'ok');
        $windowConfirm->set_size_request(640, 400);

        my $hboxjarl = Gtk3::HBox->new(0, 0);
        $windowConfirm->get_content_area->pack_start($hboxjarl, 1, 1, 0);

        my $scroll = Gtk3::ScrolledWindow->new;
        $hboxjarl->pack_start($scroll, 0, 1, 0);
        $scroll->set_policy('never', 'automatic');

        my $tree = Gtk3::SimpleList->new_from_treeview (Gtk3::TreeView->new, 'Icon' => 'pixbuf', 'Terminal(s) matching' => 'text', 'UUID' => 'hidden');
        $scroll->add($tree);
        $tree->set_headers_visible(0);
        $tree->get_selection->set_mode('GTK_SELECTION_SINGLE');

        my $name = qr/$PACMain::FUNCS{_MAIN}{_CFG}{defaults}{'auto cluster'}{$cluster}{name}/;
        my $host = qr/$PACMain::FUNCS{_MAIN}{_CFG}{defaults}{'auto cluster'}{$cluster}{host}/;
        my $title = qr/$PACMain::FUNCS{_MAIN}{_CFG}{defaults}{'auto cluster'}{$cluster}{title}/;
        my $desc = qr/$PACMain::FUNCS{_MAIN}{_CFG}{defaults}{'auto cluster'}{$cluster}{desc}/;
        foreach my $uuid (keys %{$PACMain::FUNCS{_MAIN}{_CFG}{environments}}) {
            if ($uuid eq '__PAC__ROOT__' || $PACMain::FUNCS{_MAIN}{_CFG}{environments}{$uuid}{_is_group}) {
                next;
            }
            if (($name)&&($PACMain::FUNCS{_MAIN}{_CFG}{environments}{$uuid}{name} !~ /$name/)) {
                next;
            }
            if (($host)&&($PACMain::FUNCS{_MAIN}{_CFG}{environments}{$uuid}{ip} !~ /$host/)) {
                next;
            }
            if (($title)&&($PACMain::FUNCS{_MAIN}{_CFG}{environments}{$uuid}{title} !~ /$title/)) {
                next;
            }
            if (($desc)&&($PACMain::FUNCS{_MAIN}{_CFG}{environments}{$uuid}{description} !~ /$desc/)) {
                next;
            }
            push(@{$$tree{data}}, [$PACMain::FUNCS{_METHODS}{$PACMain::FUNCS{_MAIN}{_CFG}{'environments'}{$uuid}{'method'}}{'icon'}, $PACMain::FUNCS{_MAIN}{_CFG}{environments}{$uuid}{name}, $uuid]);
        }

        # Create a scrolled2 scrolled window to contain the description textview
        my $scrollDescription = Gtk3::ScrolledWindow->new;
        $hboxjarl->pack_start($scrollDescription, 1, 1, 0);
        $scrollDescription->set_policy('automatic', 'automatic');

        # Create descView as a gtktextview with descBuffer
        my $descBuffer = Gtk3::TextBuffer->new;
        my $descView = Gtk3::TextView->new_with_buffer($descBuffer);
        $descView->set_border_width(5);
        $scrollDescription->add($descView);
        $descView->set_wrap_mode('GTK_WRAP_WORD');
        $descView->set_sensitive(0);
        $descView->drag_dest_unset;
        $descView->modify_font(Pango::FontDescription::from_string('monospace') );

        $tree->get_selection->signal_connect('changed' => sub {
            my @selection = $tree->get_selected_indices;
            if (scalar(@selection) != 1) {
                return 1;
            }
            my $sel = $selection[0];
            my $name = $$tree{data}[$sel][1];
            my $uuid = $$tree{data}[$sel][2];
            $descBuffer->set_text($PACMain::FUNCS{_MAIN}{_CFG}{'environments'}{$uuid}{'description'} // '');
        });

        my $lbltotal = Gtk3::Label->new;
        $lbltotal->set_markup("Conditions for Auto Cluster <b>$cluster</b> match <b>" . (scalar(@{$$tree{data}}) ) . '</b> connections');
        $windowConfirm->get_content_area->pack_start($lbltotal, 0, 1, 0);

        $windowConfirm->show_all;
        my $close = $windowConfirm->run;
        $windowConfirm->destroy;

        return 1;
    });
    #######################################
    # CONNECTED TERMINALS RELATED CALLBACKS
    #######################################

    # Capture 'treeTerminals' row activated
    $$self{_WINDOWCLUSTER}{treeTerminals}->signal_connect('row_activated' => sub {
        my ($index) = $$self{_WINDOWCLUSTER}{treeTerminals}->get_selected_indices;
        if (!defined $index) {
            return;
        }
        $$self{_WINDOWCLUSTER}{btnadd}->clicked;
        return 1;
    });

    $$self{_WINDOWCLUSTER}{treeTerminals}->signal_connect('cursor_changed' => sub {
        $$self{_WINDOWCLUSTER}{btnadd}->set_sensitive(scalar(@{$$self{_WINDOWCLUSTER}{treeTerminals}->{data}}) );
    });

    ###############################
    # OTHER CALLBACKS
    ###############################

    # Capture 'Close' button clicked
    $$self{_WINDOWCLUSTER}{btnOK}->signal_connect('clicked' => sub {
        if ($PACMain::{FUNCS}{_MAIN}{_GUI}{nbTree}->get_nth_page($PACMain::{FUNCS}{_MAIN}{_GUI}{nbTree}->get_current_page) eq $PACMain::{FUNCS}{_MAIN}{_GUI}{vboxclu}) {
            $PACMain::{FUNCS}{_MAIN}->_updateClustersList;
        }
        $$self{_WINDOWCLUSTER}{main}->hide;
    });
    # Capture window closing
    $$self{_WINDOWCLUSTER}{main}->signal_connect('delete_event' => sub {$$self{_WINDOWCLUSTER}{btnOK}->activate;});
    # Capture 'Esc' keypress to close window
    $$self{_WINDOWCLUSTER}{main}->signal_connect('key_press_event' => sub {
        if ($_[1]->keyval == 65307) {
            $$self{_WINDOWCLUSTER}{btnOK}->activate;
        }
    });
    return 1;
}

sub addToCluster {
    my $self = shift;
    my $uuid = shift;
    my $cluster = shift;

    $$self{_RUNNING}{$uuid}{'terminal'}{_CLUSTER} = $cluster;
    if (defined $$self{_RUNNING}{$uuid}{'terminal'}{_GUI}{statusCluster}) {
        $$self{_RUNNING}{$uuid}{'terminal'}{_GUI}{statusCluster}->set_from_stock('asbru-cluster-manager', 'button');
    }
    if (defined $$self{_RUNNING}{$uuid}{'terminal'}{_GUI}{statusCluster}) {
        $$self{_RUNNING}{$uuid}{'terminal'}{_GUI}{statusCluster}->set_tooltip_text("In CLUSTER: $cluster");
    }
    $$self{_RUNNING}{$uuid}{'terminal'}->_updateStatus;
    $self->_updateGUI;
    return 1;
}

sub delFromCluster {
    my $self = shift;
    my $uuid = shift;
    my $cluster = shift;

    $$self{_RUNNING}{$uuid}{'terminal'}{_CLUSTER} = '';
    if (defined $$self{_RUNNING}{$uuid}{'terminal'}{_GUI}{statusCluster}) {
        $$self{_RUNNING}{$uuid}{'terminal'}{_GUI}{statusCluster}->set_from_stock('asbru-cluster-manager-off', 'button');
    }
    if (defined $$self{_RUNNING}{$uuid}{'terminal'}{_GUI}{statusCluster}) {
        $$self{_RUNNING}{$uuid}{'terminal'}{_GUI}{statusCluster}->set_tooltip_text("Unclustered");
    }
    $$self{_RUNNING}{$uuid}{'terminal'}->_updateStatus;
    $self->_updateGUI;
    return 1;
}

sub _updateGUI {
    my $self = shift;

    $$self{_WINDOWCLUSTER}{delCluster}->set_sensitive(0);
    $$self{_WINDOWCLUSTER}{btnadd}->set_sensitive(0);
    $$self{_WINDOWCLUSTER}{btndel}->set_sensitive(0);
    # Empty the clusters combobox
    $$self{_WINDOWCLUSTER}{comboClusters}->remove_all();
    # Empty the terminals tree
    @{$$self{_WINDOWCLUSTER}{treeTerminals}->{data}} = ();
    # Empty the clustered tree
    @{$$self{_WINDOWCLUSTER}{treeClustered}->{data}} = ();
    $$self{_CLUSTERS} = undef;

    # Look into every started terminal, and add it to the 'clustered' or 'unclustered' tree...
    foreach my $uuid (keys %{$$self{_RUNNING}}) {
        my $name = $$self{_RUNNING}{$uuid}{'terminal'}{'_NAME'};
        my $icon = $$self{_RUNNING}{$uuid}{'terminal'}{CONNECTED} ? $ICON_ON : $ICON_OFF;

        if ((!defined $name) || !(defined $icon)) {
            next;
        }

        if (my $cluster = $$self{_RUNNING}{$uuid}{'terminal'}{_CLUSTER}) {
            # Populate the CLUSTER variable
            $$self{_CLUSTERS}{$cluster}{$uuid} = 1;
            # Populate the clustered terminals tree
            push(@{$$self{_WINDOWCLUSTER}{treeClustered}->{data}}, [$name, $uuid, $icon]);
        } else {
            # Populate the terminals tree
            push(@{$$self{_WINDOWCLUSTER}{treeTerminals}->{data}}, [$name, $uuid, $icon]);
        }
    }

    # Now, populate the cluters combobox with the configured clusters...
    foreach my $cluster (keys %{$$self{_CLUSTERS}}) {
        $$self{_WINDOWCLUSTER}{comboClusters}->append_text($cluster);
        $$self{_WINDOWCLUSTER}{comboClusters}->set_active(0);
        $$self{_WINDOWCLUSTER}{delCluster}->set_sensitive(1);
    }

    $$self{_WINDOWCLUSTER}{addCluster}->set_sensitive(1);
    my $cluster = $$self{_WINDOWCLUSTER}{comboClusters}->get_active_text();
    $$self{_WINDOWCLUSTER}{btnadd}->set_sensitive(scalar(@{$$self{_WINDOWCLUSTER}{treeTerminals}->{data}}) && $cluster);
    $$self{_WINDOWCLUSTER}{btndel}->set_sensitive(scalar(@{$$self{_WINDOWCLUSTER}{treeClustered}->{data}}) && $cluster);
    $PACMain::FUNCS{_PCC}->_updateGUI;

    return 1;
}

sub _updateGUI1 {
    my $self = shift;
    my $selclu = shift // '';

    my $envs = $PACMain::{FUNCS}{_MAIN}{_CFG}{environments};

    $$self{CLUSTERS} = $self->getCFGClusters;

    # Empty the clusters combobox
    $$self{_WINDOWCLUSTER}{comboClusters1}->remove_all();

    # Empty the clustered connections tree
    @{$$self{_WINDOWCLUSTER}{treeClustered1}{data}} = ();

    # Now, populate the clusters combobox with the configured clusters...
    foreach my $cluster (sort {lc($a) cmp lc($b)} keys %{$$self{CLUSTERS}}) {
        $$self{_WINDOWCLUSTER}{comboClusters1}->append_text($cluster);
        $$self{_WINDOWCLUSTER}{comboClusters1}->set_active(0);
        $$self{_WINDOWCLUSTER}{delCluster1}->set_sensitive(1);
    }

    # Reload the connections tree
    $self->_loadTreeConfiguration;

    my $i = 0;
    foreach my $cluster (sort {lc($a) cmp lc($b)} keys %{$$self{CLUSTERS}}) {
        if ($cluster eq $selclu) {
            $$self{_WINDOWCLUSTER}{comboClusters1}->set_active($i);
        }
        ++$i;
    }
    $self->_updateButtons1;

    return 1;
}

sub _updateGUIAC {
    my $self = shift;
    my $cluster = shift // '';

    # Empty the AC table
    @{$$self{_WINDOWCLUSTER}{treeAutocluster}{data}} = ();
    # and reload it

    my $i = 0;
    my $j = 0;
    foreach my $ac (sort {$a cmp $b} keys %{$PACMain::FUNCS{_MAIN}{_CFG}{defaults}{'auto cluster'}}) {
        if ($ac eq $cluster) {
            $j = $i;
        }
        ++$i;
        push(@{$$self{_WINDOWCLUSTER}{treeAutocluster}{data}}, $ac);
    }
    $$self{_WINDOWCLUSTER}{treeAutocluster}->set_cursor(Gtk3::TreePath->new_from_string($j), undef, 0);
    $self->_updateButtonsAC;

    return 1;
}

sub _updateButtonsAC {
    my $self = shift;

    my $sel = $$self{_WINDOWCLUSTER}{treeAutocluster}->get_selected_indices;

    $$self{_WINDOWCLUSTER}{addAC}->set_sensitive(1);
    $$self{_WINDOWCLUSTER}{renAC}->set_sensitive($sel);
    $$self{_WINDOWCLUSTER}{delAC}->set_sensitive($sel);
    $$self{_WINDOWCLUSTER}{btnCheckAC}->set_sensitive($sel);

    $$self{_WINDOWCLUSTER}{entryname}->set_sensitive($sel);
    $$self{_WINDOWCLUSTER}{entryhost}->set_sensitive($sel);
    $$self{_WINDOWCLUSTER}{entrytitle}->set_sensitive($sel);
    $$self{_WINDOWCLUSTER}{entrydesc}->set_sensitive($sel);

    return 1;
}

sub getCFGClusters {
    my $self = shift;

    my $envs = $PACMain::{FUNCS}{_MAIN}{_CFG}{environments};
    my %clusters;

    foreach my $uuid (keys %{$envs}) {
        foreach my $cluster (@{$$envs{$uuid}{cluster}}) {
            $clusters{$cluster}{$uuid} = 1;
        }
    }

    return \%clusters;
}

sub _comboClustersChanged {
    my $self = shift;

    my $cluster = $$self{_WINDOWCLUSTER}{comboClusters}->get_active_text;

    $$self{_WINDOWCLUSTER}{addCluster}->set_sensitive(1);
    $$self{_WINDOWCLUSTER}{delCluster}->set_sensitive(0);
    $$self{_WINDOWCLUSTER}{btnadd}->set_sensitive(0);
    $$self{_WINDOWCLUSTER}{btndel}->set_sensitive(0);

    if (!$cluster) {
        return 1;
    }

    $$self{_WINDOWCLUSTER}{delCluster}->set_sensitive(1);
    $$self{_WINDOWCLUSTER}{btnadd}->set_sensitive(scalar(@{$$self{_WINDOWCLUSTER}{treeTerminals}->{data}}) );
    $$self{_WINDOWCLUSTER}{btndel}->set_sensitive(scalar(@{$$self{_WINDOWCLUSTER}{treeClustered}->{data}}) );

    # Empty the clustered terminals tree...
    @{$$self{_WINDOWCLUSTER}{treeClustered}->{data}} = ();

    # ... and repopulate it
    foreach my $uuid (keys %{$$self{_CLUSTERS}{$cluster}}) {
        if ($uuid eq 1) {
            next;
        }
        my $name = $$self{_RUNNING}{$uuid}{'terminal'}{'_NAME'};
        my $icon = $$self{_RUNNING}{$uuid}{'terminal'}{'CONNECTED'} ? $ICON_ON : $ICON_OFF;
        push(@{$$self{_WINDOWCLUSTER}{treeClustered}->{data}}, [$name, $uuid, $icon]);
    }
    return 1;
}

sub _comboClustersChanged1 {
    my $self = shift;

    my $cluster = $$self{_WINDOWCLUSTER}{comboClusters1}->get_active_text // '';
    if ($cluster eq '') {
        return 1;
    }

    # Empty the clustered terminals tree...
    @{$$self{_WINDOWCLUSTER}{treeClustered1}->{data}} = ();

    # ... and repopulate it
    my $cfg = $PACMain::{FUNCS}{_MAIN}{_CFG}{environments};
    foreach my $uuid (sort {lc($$cfg{$a}{name}) cmp lc($$cfg{$b}{name})} keys %{$$self{CLUSTERS}{$cluster}}) {
        push(@{$$self{_WINDOWCLUSTER}{treeClustered1}->{data}}, [$PACMain::{FUNCS}{_MAIN}{_CFG}{'environments'}{$uuid}{name}, $uuid]);
    }

    return 1;
}

sub _updateButtons1 {
    my $self = shift;

    my @sel_uuids = $$self{_WINDOWCLUSTER}{treeConnections}->_getSelectedUUIDs;
    my $total = scalar(@sel_uuids);
    my $totalc = $$self{_WINDOWCLUSTER}{treeClustered1}->get_selected_indices;

    my $is_root = 0;
    my $uuid = $sel_uuids[0];
    my $cluster = $$self{_WINDOWCLUSTER}{comboClusters1}->get_active_text // '';

    foreach my $uuid (@sel_uuids) {
        if ($uuid // '' eq '__PAC__ROOT__') {
            $is_root = 1;
            last;
        }
    }

    $$self{_WINDOWCLUSTER}{addCluster1}->set_sensitive(1);
    $$self{_WINDOWCLUSTER}{renCluster1}->set_sensitive($cluster ne '');
    $$self{_WINDOWCLUSTER}{delCluster1}->set_sensitive($cluster ne '');
    $$self{_WINDOWCLUSTER}{btnadd1}->set_sensitive($total);
    $$self{_WINDOWCLUSTER}{btndel1}->set_sensitive($totalc);

    return 1;
}

# END: Define PRIVATE CLASS functions
###################################################################

1;

__END__

=encoding utf8

=head1 NAME
