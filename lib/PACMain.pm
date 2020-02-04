package PACMain;

###############################################################################
# This file is part of Ásbrú Connection Manager
#
# Copyright (C) 2017-2020 Ásbrú Connection Manager team (https://asbru-cm.net)
# Copyright (C) 2010-2016 David Torrejón Vaquerizas
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
my $REALBIN = $RealBin;
use lib "$RealBin/lib", "$RealBin/lib/ex";

# Standard
use strict;
use warnings;
use YAML qw (LoadFile DumpFile);
use Storable qw (thaw dclone nstore retrieve);
use Encode;
use File::Copy;
use Net::Ping;
use OSSP::uuid;
use POSIX ":sys_wait_h";
use POSIX qw (strftime);
use Crypt::CBC;

# GTK
use Gtk3 -init;

# PAC modules
use PACUtils;
our $UNITY = 1;
$@ = '';
eval {
    require 'PACTrayUnity.pm';
};
if ($@) {
    eval { require 'PACTray.pm'; };
    $UNITY = 0;
}
use PACTerminal;
use PACEdit;
use PACConfig;
use PACCluster;
use PACScreenshots;
use PACStatistics;
use PACTree;
use PACPipe;
use PACScripts;

# END: Import Modules
###################################################################

###################################################################
# Define GLOBAL CLASS variables

my $APPNAME = $PACUtils::APPNAME;
my $APPVERSION = $PACUtils::APPVERSION;
my $AUTOSTART_FILE = "$RealBin/res/pac_start.desktop";
my $RES_DIR = "$RealBin/res";

# Register icons on Gtk
&_registerPACIcons;

my $INIT_CFG_FILE = "$RealBin/res/pac.yml";
my $CFG_DIR = $ENV{"ASBRU_CFG"};
my $CFG_FILE = "$CFG_DIR/pac.yml";
our $R_CFG_FILE = '';
my $CFG_FILE_FREEZE = "$CFG_DIR/pac.freeze";
my $CFG_FILE_NFREEZE = "$CFG_DIR/pac.nfreeze";
my $CFG_FILE_DUMPER = "$CFG_DIR/pac.dumper";

my $PAC_START_PROGRESS = 0;
my $PAC_START_TOTAL = 6;

my $APPICON = "$RES_DIR/asbru-logo-64.png";
my $AUTOCLUSTERICON = _pixBufFromFile("$RealBin/res/asbru_cluster_auto.png");
my $CLUSTERICON = _pixBufFromFile("$RealBin/res/asbru_cluster_manager.png");
my $GROUPICON_ROOT = _pixBufFromFile("$RealBin/res/asbru_group.png");
my $GROUPICON = _pixBufFromFile("$RealBin/res/asbru_group_open_16x16.png");
my $GROUPICONOPEN = _pixBufFromFile("$RealBin/res/asbru_group_open_16x16.png");
my $GROUPICONCLOSED = _pixBufFromFile("$RealBin/res/asbru_group_closed_16x16.png");

my $CHECK_VERSION = 0;
my $NEW_VERSION = 0;
my $NEW_CHANGES = '';
our $_NO_SPLASH = 0;

my $CIPHER = Crypt::CBC->new(-key => 'PAC Manager (David Torrejon Vaquerizas, david.tv@gmail.com)', -cipher => 'Blowfish', -salt => '12345678') or die "ERROR: $!";

our %RUNNING;
our %FUNCS;

# END: Define GLOBAL CLASS variables
###################################################################

###################################################################
# START: Define PUBLIC CLASS methods

sub new {
    my $class = shift;
    my @argv = @_;

    my $self = {};

    print STDERR "INFO: Using config directory '$CFG_DIR'\n";
    # Setup some signal handling
    $SIG{'USR1'} = sub {
        #DevNote: option currently disabled
        #_showUpdate(&_checkREADME);
        #$$self{_UPDATING} = 0;
        #defined $$self{_CONFIG} and _($$self{_CONFIG}, 'btnCheckVersion')->set_sensitive(1);
    };
    $SIG{'TERM'} = $SIG{'STOP'} = $SIG{'QUIT'} = $SIG{'INT'} = sub {
        print STDERR "INFO: Signal '$_[0]' received. Exiting Ásbrú...\n";
        _quitProgram($self, 'force');
        exit 0;
    };

    $self->{_CFG} = {};
    @{ $self->{_OPTS} } = @argv;
    $self->{_PREVTAB} = 0;

    $self->{_GUI} = undef;
    $self->{_PACTABS} = undef;
    $self->{_TABSINWINDOW} = 0;
    $self->{_COPY}{'data'} = {};
    $self->{_COPY}{'cut'} = 0;
    $self->{_UPDATING} = 0;
    $self->{_CMDLINETRAY} = 0;
    $self->{_SHOWFINDTREE} = 0;
    $self->{_READONLY} = 0;
    $self->{_HAS_FOCUS} = '';

    @{ $self->{_UNDO} } = ();
    $$self{_GUILOCKED} = 0;

    # Create application & register it
    # This will let us know if another Ásbrú instance is running
    $self->{_APP} = Gtk3::Application->new('org.asbru-cm.main', 'handles-open');
    if (!$self->{_APP}->register()) {
        print("ERROR: Failed to register Gtk3 application.\n");
        exit 0;
    }

    $_NO_SPLASH = grep({ /^(--no-splash)|(--list-uuids)|(--dump-uuid)/go } @{ $$self{_OPTS} });
    $_NO_SPLASH ||= $$self{_APP}->get_is_remote;

    # Show splash-screen while loading
    PACUtils::_splash(1, "Starting $PACUtils::APPNAME (v$PACUtils::APPVERSION)", ++$PAC_START_PROGRESS, $PAC_START_TOTAL);

    $self->{_PING} = Net::Ping->new('tcp');
    $self->{_PING}->tcp_service_check(1);

    # Read the config/connections file...
    PACUtils::_splash(1, "Reading config...", ++$PAC_START_PROGRESS, $PAC_START_TOTAL);
    _readConfiguration($self);

    # Set conflictive layout options as early as possible
    _setSafeLayoutOptions($self,$$self{_CFG}{'defaults'}{'layout'});

    map({
    if (/^--dump-uuid=(.+)$/) {
        require Data::Dumper;
        print Data::Dumper::Dumper($$self{_CFG}{environments}{$1 });
        exit 0;
    } } @{ $$self{_OPTS} });

    # Option --list-uuids, list uuids and exit

    if (grep({ /^--list-uuids$/ } @{ $$self{_OPTS} })) {
        print '-'x36 . '|' . '-'x36 . '|' . '-'x5 . '|' . '-'x15 . '|' . '-'x21 . "\n";
        printf "%36s|%36s|%5s|%15s|%s\n", 'UUID', 'PARENT_UUID', 'TYPE', 'METHOD', 'NAME';
        print '-'x36 . '|' . '-'x36 . '|' . '-'x5 . '|' . '-'x15 . '|' . '-'x21 . "\n";
        foreach my $uuid (keys %{ $$self{_CFG}{environments} }) {
            if ((!defined $$self{_CFG}{environments}{$uuid}{name})||($uuid eq '__PAC_SHELL__')) {
                next;
            }
            print "$uuid|";
            printf "%36s|", $$self{_CFG}{environments}{$uuid}{parent};
            printf "%5s|", ($$self{_CFG}{environments}{$uuid}{_is_group} ? 'GROUP' : '');
            printf "%15s|", (defined $$self{_CFG}{environments}{$uuid}{method} ? "$$self{_CFG}{environments}{$uuid}{method}" : '');
            printf "%s\n", $$self{_CFG}{environments}{$uuid}{name};
        }
        print '-'x36 . '|' . '-'x36 . '|' . '-'x5 . '|' . '-'x15 . '|' . '-'x21 . "\n";
        exit 0;
    }

    # Start iconified is option set or command line option --iconified

    if (($$self{_CFG}{defaults}{'start iconified'}) || (grep({ /^--iconified$/ } @{ $$self{_OPTS} }))) {
        $$self{_CMDLINETRAY} = 1;
    }

    # Check if startup password is required and validate

    if ($$self{_CFG}{'defaults'}{'use gui password'}) {
        my $pass;
        grep({ if (/^--password=(.+)$/) { $pass = $1; } } @{ $$self{_OPTS} });
        if (! defined $pass) {
            PACUtils::_splash(1, "Waiting for password...", $PAC_START_PROGRESS, $PAC_START_TOTAL);
            $pass = _wEnterValue($self, 'GUI Password Protection', 'Please, enter GUI Password...', undef, 0, 'pac-protected');
        }
        if (!defined $pass) {
            exit 0;
        }
        if ($CIPHER->encrypt_hex($pass) ne $$self{_CFG}{'defaults'}{'gui password'}) {
            _wMessage($$self{_WINDOWCONFIG}, 'ERROR: Wrong password!!');
            exit 0;
        }
    }

    # Check if only one instance is allowed

    if ($$self{_APP}->get_is_remote) {
        print "INFO: Ásbrú is already running.\n";

        my $getout = 0;
        my $uuid;
        if (grep { /--start-shell/; } @{ $$self{_OPTS} }) {
            _sendAppMessage($$self{_APP}, 'start-shell');
            $getout = 1;
        } elsif (grep { /--quick-conn/; } @{ $$self{_OPTS} }) {
            _sendAppMessage($$self{_APP}, 'quick-conn');
            $getout = 1;
        } elsif (grep { /--start-uuid=(.+)/ and $uuid = $1; } @{ $$self{_OPTS} }) {
            _sendAppMessage($$self{_APP}, 'start-uuid', $uuid);
            $getout = 1;
        } elsif (grep { /--edit-uuid=(.+)/ and $uuid = $1; } @{ $$self{_OPTS} }) {
            _sendAppMessage($$self{_APP}, 'edit-uuid', $uuid);
            $getout = 1;
        } else {
            $getout = 0;
        }

        if (! $getout) {
            if ($$self{_CFG}{'defaults'}{'allow more instances'}) {
                print "INFO: Starting '$0' in READ ONLY mode!\n";
                $$self{_READONLY} = 1;
            } elsif (! $$self{_CFG}{'defaults'}{'allow more instances'}) {
                print "INFO: No more instances allowed!\n";
                _sendAppMessage($$self{_APP}, 'show-conn');
                Gtk3::Gdk::notify_startup_complete;
                return 0;
            }
        } else {
            Gtk3::Gdk::notify_startup_complete;
            return 0;
        }
    }

    if (grep(/^--readonly$/, @{ $$self{_OPTS} })) {
        print "INFO: Starting '$0' in READ ONLY mode!\n";
        $$self{_READONLY} = 1;
    }

    # Check for updates in a child process
    #DevNote: option currently disabled
    #$$self{_CFG}{'defaults'}{'check versions at start'} and $$self{_UPDATING} = 1 and PACUtils::_getREADME($$);

    # Gtk style
    my $css_provider = Gtk3::CssProvider->new;
    $css_provider->load_from_path("$RES_DIR/asbru.css");
    Gtk3::StyleContext::add_provider_for_screen(Gtk3::Gdk::Screen::get_default, $css_provider, 600);

    # Setup known connection methods
    %{ $$self{_METHODS} } = _getMethods($self);

    bless($self, $class);

    return $self;
}

# DESTRUCTOR
sub DESTROY {
    my $self = shift;
    undef $self;
    return 1;
}

# Start GUI and launch connection
sub start {
    my $self = shift;

    #_makeDesktopFile($$self{_CFG});

    # Build the GUI
    PACUtils::_splash(1, "Building GUI...", ++$PAC_START_PROGRESS, $PAC_START_TOTAL);
    if (!$self->_initGUI) {
        _splash(0);
        return 0;
    }

    # Build the Tree with the connections list
    PACUtils::_splash(1, "Loading Connections...", ++$PAC_START_PROGRESS, $PAC_START_TOTAL);
    $self->_loadTreeConfiguration('__PAC__ROOT__');

    if ($UNITY) {
        $FUNCS{_TRAY}->_setTrayMenu;
    }

    PACUtils::_splash(1, "Finalizing...", ++$PAC_START_PROGRESS, $PAC_START_TOTAL);

    # Setup callbacks
    $self->_setupCallbacks;

    # If version is lower than current, update and save the new one
    if ($APPVERSION gt $$self{_CFG}{defaults}{version}) {
        $$self{_CFG}{defaults}{version} = $APPVERSION;
        $self->_saveConfiguration;
    }

    # Load information about last expanded groups
    $self->_loadTreeExpanded;

    Gtk3::Gdk::notify_startup_complete;
    Glib::Idle->add(
        sub {
            _splash(0);
            return 0;
        }
    );

    # Show main interface
    $$self{_GUI}{main}->show_all();

    # Apply Layout as early as possible
    $self->_ApplyLayout($$self{_CFG}{'defaults'}{'layout'});

    # Autostart selected connections
    my @idx;
    grep({ $$self{_CFG}{'environments'}{$_}{'startup launch'} and push(@idx, [ $_ ]); } keys %{ $$self{_CFG}{'environments'} });
    grep({ if (/^--start-uuid=(.+)$/) { my ($uuid, $clu) = split(':', $1); push(@idx, [ $uuid, undef, $clu // undef ]); } } @{ $$self{_OPTS} });
    $self->_launchTerminals(\@idx) if scalar(@idx);

    # Autostart Shell if so is configured
    if ($$self{_CFG}{'defaults'}{'autostart shell upon PAC start'}) {
        $$self{_GUI}{shellBtn}->clicked();
    }

    $$self{_GUI}{statistics}->update('__PAC__ROOT__', $$self{_CFG});

    # Is tray available (Gnome or Unity)?
    if ($ENV{'ASBRU_DESKTOP'} eq 'gnome-shell') {
        _($$self{_CONFIG}, 'cbCfgStartIconified')->set_tooltip_text("WARNING: Tray icon may not be available: Install Unite Extension is recomended.\nhttps://extensions.gnome.org/extension/1287/unite/");
    }

    if (!$$self{_CFG}{defaults}{'start iconified'} && !$$self{_CMDLINETRAY}) {
        $$self{_GUI}{main}->present;
    } else {
        $self->_hideConnectionsList();
    }

    print "INFO: Using " . ($UNITY ? 'Unity' : 'Gnome') . " tray icon\n";

    # Auto open "Edit" dialog
    foreach my $arg (@{ $$self{_OPTS} }) {
        if ($arg =~ /^--edit-uuid=(.+)$/go) {
            my $uuid = $1;
            my $path = $$self{_GUI}{treeConnections}->_getPath($uuid);
            if (($uuid eq '__PAC__ROOT__') || (!$path)) {
                next;
            }
            $$self{_GUI}{treeConnections}->expand_to_path($path);
            $$self{_GUI}{treeConnections}->set_cursor($path, undef, 0);
            $$self{_GUI}{connEditBtn}->clicked();
        }
    }

    # Auto start scripts
    grep({ /^--start-script=(.+)$/ and $$self{_SCRIPTS}->_execScript($1); } @{ $$self{_OPTS} });

    # Auto start Shell
    grep({ /^--start-shell$/ and $$self{_GUI}{shellBtn}->clicked(); } @{ $$self{_OPTS} });

    # Auto start Quick Connect edit dialog
    grep({ /^--quick-conn$/ and $$self{_GUI}{connQuickBtn}->clicked(); } @{ $$self{_OPTS} });

    # Auto start Preferences dialog
    grep({ /^--preferences$/ and $$self{_GUI}{configBtn}->clicked(); } @{ $$self{_OPTS} });

    # Auto start Scripts window
    grep({ /^--scripts$/ and $$self{_GUI}{scriptsBtn}->clicked(); } @{ $$self{_OPTS} });

    #$self->_ApplyLayout($$self{_CFG}{'defaults'}{'layout'});

    # Goto GTK's event loop
    Gtk3->main;

    return 1;
}

# END: Define PUBLIC CLASS methods
###################################################################

###################################################################
# START: Define PRIVATE CLASS functions

sub _initGUI {
    my $self = shift;

    # Prevent from creating the main window a second time
    if (defined $$self{_GUI}{main}) {
        return 0;
    }

    ##############################################
    # Create main window
    ##############################################
    $$self{_GUI}{main} = Gtk3::Window->new;

    # Create a vbox1: main, status
    $$self{_GUI}{vbox1} = Gtk3::VBox->new(0, 0);
    $$self{_GUI}{main}->add($$self{_GUI}{vbox1});

    $$self{_GUI}{hpane} = Gtk3::HPaned->new;
    $$self{_GUI}{vbox1}->add($$self{_GUI}{hpane});

    # Create a vbox3: actions, connections and other tools
    $$self{_GUI}{vbox3} = Gtk3::VBox->new(0, 0);
    $$self{_GUI}{vbox3}->set_size_request(200, -1);
    if ($$self{_CFG}{defaults}{'tree on right side'}) {
        $$self{_GUI}{hpane}->pack2($$self{_GUI}{vbox3}, 0, 0);
    } else {
        $$self{_GUI}{hpane}->pack1($$self{_GUI}{vbox3}, 0, 0);
    }
    $$self{_GUI}{vbox3}->set_border_width(5);

    # Create a hbuttonbox1: add, rename, delete, etc...
    $$self{_GUI}{hbuttonbox1} = Gtk3::HBox->new(1, 0);
    $$self{_GUI}{vbox3}->pack_start($$self{_GUI}{hbuttonbox1}, 0, 1, 0);

    # Create groupAdd button
    $$self{_GUI}{groupAddBtn} = Gtk3::Button->new;
    $$self{_GUI}{groupAddBtn}->set_image(Gtk3::Image->new_from_stock('pac-group-add', 'button'));
    $$self{_GUI}{hbuttonbox1}->pack_start($$self{_GUI}{groupAddBtn}, 1, 1, 0);
    $$self{_GUI}{groupAddBtn}->set('can-focus' => 0);
    $$self{_GUI}{groupAddBtn}->set_tooltip_text('New GROUP');

    # Create connAdd button
    $$self{_GUI}{connAddBtn} = Gtk3::Button->new;
    $$self{_GUI}{connAddBtn}->set_image(Gtk3::Image->new_from_stock('pac-node-add', 'button'));
    $$self{_GUI}{hbuttonbox1}->pack_start($$self{_GUI}{connAddBtn}, 1, 1, 0);
    $$self{_GUI}{connAddBtn}->set('can-focus' => 0);
    $$self{_GUI}{connAddBtn}->set_tooltip_text('New CONNECTION');

    # Create connEditBtn button
    $$self{_GUI}{connEditBtn} = Gtk3::Button->new;
    $$self{_GUI}{connEditBtn}->set_image(Gtk3::Image->new_from_stock('gtk-edit', 'button'));
    $$self{_GUI}{hbuttonbox1}->pack_start($$self{_GUI}{connEditBtn}, 1, 1, 0);
    $$self{_GUI}{connEditBtn}->set('can-focus' => 0);
    $$self{_GUI}{connEditBtn}->set_tooltip_text('Edit this Connection');

    # Create nodeRen button
    $$self{_GUI}{nodeRenBtn} = Gtk3::Button->new;
    $$self{_GUI}{nodeRenBtn}->set_image(Gtk3::Image->new_from_stock('gtk-spell-check', 'button'));
    $$self{_GUI}{hbuttonbox1}->pack_start($$self{_GUI}{nodeRenBtn}, 1, 1, 0);
    $$self{_GUI}{nodeRenBtn}->set('can-focus' => 0);
    $$self{_GUI}{nodeRenBtn}->set_tooltip_text('Rename this node');

    # Create nodeDel button
    $$self{_GUI}{nodeDelBtn} = Gtk3::Button->new;
    $$self{_GUI}{nodeDelBtn}->set_image(Gtk3::Image->new_from_stock('gtk-delete', 'button'));
    $$self{_GUI}{hbuttonbox1}->pack_start($$self{_GUI}{nodeDelBtn}, 1, 1, 0);
    $$self{_GUI}{nodeDelBtn}->set('can-focus' => 0);
    $$self{_GUI}{nodeDelBtn}->set_sensitive(0);
    $$self{_GUI}{nodeDelBtn}->set_tooltip_text('Delete this node(s)');

    # Put a separator
    if ($$self{_CFG}{'defaults'}{'layout'} ne 'Compact') {
        $$self{_GUI}{vbox3}->pack_start(Gtk3::HSeparator->new, 0, 1, 5);
    }

    # Put a notebook for connections, favourites and history
    $$self{_GUI}{nbTree} = Gtk3::Notebook->new;
    $$self{_GUI}{vbox3}->pack_start($$self{_GUI}{nbTree}, 1, 1, 0);
    $$self{_GUI}{nbTree}->set_scrollable(1);
    # FIXME-HOMOGENEOUS     $$self{_GUI}{nbTree}->set('homogeneous', 0);

    # Create a scrolled1 scrolled window to contain the connections tree
    $$self{_GUI}{scroll1} = Gtk3::ScrolledWindow->new;
    $$self{_GUI}{nbTreeTab} = Gtk3::HBox->new(0, 0);
    $$self{_GUI}{nbTreeTabLabel} = Gtk3::Label->new;
    $$self{_GUI}{nbTreeTab}->pack_start(Gtk3::Image->new_from_stock('pac-treelist', 'button'), 0, 1, 0);
    if ($$self{_CFG}{'defaults'}{'layout'} ne 'Compact') {
        $$self{_GUI}{nbTreeTab}->pack_start($$self{_GUI}{nbTreeTabLabel}, 0, 1, 0);
    }
    $$self{_GUI}{nbTreeTab}->set_tooltip_text('Connection Tree');
    $$self{_GUI}{nbTreeTab}->show_all();
    $$self{_GUI}{nbTree}->append_page($$self{_GUI}{scroll1}, $$self{_GUI}{nbTreeTab});
    $$self{_GUI}{nbTree}->set_tab_reorderable($$self{_GUI}{scroll1}, 1);
    $$self{_GUI}{scroll1}->set_policy('automatic', 'automatic');
    $$self{_GUI}{vbox3}->set_border_width(5);

    # Create a treeConnections treeview for connections
    $$self{_GUI}{treeConnections} = PACTree->new (
        'Icon:' => 'pixbuf',
        'Name:' => 'hidden',
        'UUID:' => 'hidden',
        'List:' => 'image_text',
    );
    $$self{_GUI}{scroll1}->add($$self{_GUI}{treeConnections});
    $$self{_GUI}{treeConnections}->set_enable_tree_lines($$self{_CFG}{'defaults'}{'enable tree lines'});
    $$self{_GUI}{treeConnections}->set_headers_visible(0);
    $$self{_GUI}{treeConnections}->set_enable_search(0);
    $$self{_GUI}{treeConnections}->set_has_tooltip(1);
    $$self{_GUI}{treeConnections}->set_grid_lines('GTK_TREE_VIEW_GRID_LINES_NONE');

    # Implement a "TreeModelSort" to auto-sort the data
    my $sort_model_conn = Gtk3::TreeModelSort->new_with_model($$self{_GUI}{treeConnections}->get_model);
    $$self{_GUI}{treeConnections}->set_model($sort_model_conn);
    $sort_model_conn->set_default_sort_func(\&__treeSort, $$self{_CFG});
    $$self{_GUI}{treeConnections}->get_selection->set_mode('GTK_SELECTION_MULTIPLE');

    @{$$self{_GUI}{treeConnections}{'data'}}=(
        {
            value => [ $GROUPICON_ROOT, '<b>AVAILABLE CONNECTIONS</b>', '__PAC__ROOT__' ],
            children => []
        }
    );

    $$self{_GUI}{_vboxSearch} = Gtk3::VBox->new(0, 0);
    $$self{_GUI}{vbox3}->pack_start($$self{_GUI}{_vboxSearch}, 0, 1, 0);

    $$self{_GUI}{_entrySearch} = Gtk3::Entry->new;
    $$self{_GUI}{_vboxSearch}->pack_start($$self{_GUI}{_entrySearch}, 0, 1, 0);
    $$self{_GUI}{_entrySearch}->grab_focus();

    $$self{_GUI}{_hboxSearch} = Gtk3::HBox->new(1, 0);
    $$self{_GUI}{_vboxSearch}->pack_start($$self{_GUI}{_hboxSearch}, 0, 1, 0);

    $$self{_GUI}{_btnPrevSearch} = Gtk3::Button->new_with_mnemonic('Prev_ious');
    $$self{_GUI}{_btnPrevSearch}->set_image(Gtk3::Image->new_from_stock('gtk-media-previous', 'button'));
    $$self{_GUI}{_hboxSearch}->pack_start($$self{_GUI}{_btnPrevSearch}, 0, 1, 0);
    $$self{_GUI}{_btnPrevSearch}->set('can_focus', 0);
    $$self{_GUI}{_btnPrevSearch}->set_sensitive(0);

    $$self{_GUI}{_btnNextSearch} = Gtk3::Button->new_with_mnemonic('_Next');
    $$self{_GUI}{_btnNextSearch}->set_image(Gtk3::Image->new_from_stock('gtk-media-next', 'button'));
    $$self{_GUI}{_hboxSearch}->pack_start($$self{_GUI}{_btnNextSearch}, 0, 1, 0);
    $$self{_GUI}{_btnNextSearch}->set('can_focus', 0);
    $$self{_GUI}{_btnNextSearch}->set_sensitive(0);

    $$self{_GUI}{_rbSearchName} = Gtk3::RadioButton->new_with_label('incremental search', 'Name');
    $$self{_GUI}{_rbSearchName}->set('can-focus', 0);
    $$self{_GUI}{_vboxSearch}->pack_start($$self{_GUI}{_rbSearchName}, 0, 1, 0);
    $$self{_GUI}{_rbSearchHost} = Gtk3::RadioButton->new_with_label_from_widget($$self{_GUI}{_rbSearchName}, 'IP / Host');
    $$self{_GUI}{_rbSearchHost}->set('can-focus', 0);
    $$self{_GUI}{_vboxSearch}->pack_start($$self{_GUI}{_rbSearchHost}, 0, 1, 0);
    $$self{_GUI}{_rbSearchDesc} = Gtk3::RadioButton->new_with_label_from_widget($$self{_GUI}{_rbSearchName}, 'Description');
    $$self{_GUI}{_rbSearchDesc}->set('can-focus', 0);
    $$self{_GUI}{_vboxSearch}->pack_start($$self{_GUI}{_rbSearchDesc}, 0, 1, 0);

    # Create a scrolled2 scrolled window to contain the favourites tree
    $$self{_GUI}{scroll2} = Gtk3::ScrolledWindow->new;
    $$self{_GUI}{nbFavTab} = Gtk3::HBox->new(0, 0);
    $$self{_GUI}{nbFavTabLabel} = Gtk3::Label->new;
    $$self{_GUI}{nbFavTab}->pack_start(Gtk3::Image->new_from_stock('pac-favourite-on', 'button'), 0, 1, 0);
    if ($$self{_CFG}{'defaults'}{'layout'} ne 'Compact') {
        $$self{_GUI}{nbFavTab}->pack_start($$self{_GUI}{nbFavTabLabel}, 0, 1, 0);
    }
    $$self{_GUI}{nbFavTab}->set_tooltip_text('Favourites');
    $$self{_GUI}{nbFavTab}->show_all();
    $$self{_GUI}{nbTree}->append_page($$self{_GUI}{scroll2}, $$self{_GUI}{nbFavTab});
    $$self{_GUI}{nbTree}->set_tab_reorderable($$self{_GUI}{scroll2}, 1);
    $$self{_GUI}{scroll2}->set_shadow_type('none');
    $$self{_GUI}{scroll2}->set_policy('automatic', 'automatic');

    # Create treeFavourites
    $$self{_GUI}{treeFavourites} = PACTree->new (
        'Icon:' => 'pixbuf',
        'Name:' => 'markup',
        'UUID:' => 'hidden',
    );
    $$self{_GUI}{scroll2}->add($$self{_GUI}{treeFavourites});

    # Implement a "TreeModelSort" to auto-sort the data
    my $sort_modelfav = Gtk3::TreeModelSort->new_with_model($$self{_GUI}{treeFavourites}->get_model);
    $$self{_GUI}{treeFavourites}->set_model($sort_modelfav);
    $sort_modelfav->set_default_sort_func(\&__treeSort, $$self{_CFG});

    $$self{_GUI}{treeFavourites}->set_enable_tree_lines(0);
    $$self{_GUI}{treeFavourites}->set_headers_visible(0);
    $$self{_GUI}{treeFavourites}->set_enable_search(0);
    $$self{_GUI}{treeFavourites}->set_has_tooltip(1);
    $$self{_GUI}{treeFavourites}->get_selection->set_mode('GTK_SELECTION_MULTIPLE');

    # Create a scrolled3 scrolled window to contain the history tree
    $$self{_GUI}{scroll3} = Gtk3::ScrolledWindow->new;
    $$self{_GUI}{nbHistTab} = Gtk3::HBox->new(0, 0);
    $$self{_GUI}{nbHistTabLabel} = Gtk3::Label->new;
    $$self{_GUI}{nbHistTab}->pack_start(Gtk3::Image->new_from_stock('pac-history', 'button'), 0, 1, 0);
    if ($$self{_CFG}{'defaults'}{'layout'} ne 'Compact') {
        $$self{_GUI}{nbHistTab}->pack_start($$self{_GUI}{nbHistTabLabel}, 0, 1, 0);
    }
    $$self{_GUI}{nbHistTab}->set_tooltip_text('Connection History');
    $$self{_GUI}{nbHistTab}->show_all();
    $$self{_GUI}{nbTree}->append_page($$self{_GUI}{scroll3}, $$self{_GUI}{nbHistTab});
    $$self{_GUI}{nbTree}->set_tab_reorderable($$self{_GUI}{scroll3}, 1);
    $$self{_GUI}{scroll3}->set_shadow_type('none');
    $$self{_GUI}{scroll3}->set_policy('automatic', 'automatic');

    # Create treeHistory
    $$self{_GUI}{treeHistory} = PACTree->new (
        'Icon:' => 'pixbuf',
        'Name:' => 'markup',
        'UUID:' => 'hidden',
        'Last:' => 'text',
    );
    $$self{_GUI}{scroll3}->add($$self{_GUI}{treeHistory});
    $$self{_GUI}{treeHistory}->set_enable_tree_lines(0);
    $$self{_GUI}{treeHistory}->set_headers_visible(0);
    $$self{_GUI}{treeHistory}->set_enable_search(0);
    $$self{_GUI}{treeHistory}->set_has_tooltip(1);

    $$self{_GUI}{vboxclu} = Gtk3::VBox->new(0, 0);

    $$self{_GUI}{btneditclu} = Gtk3::Button->new_with_label(' Manage Clusters');
    $$self{_GUI}{vboxclu}->pack_start($$self{_GUI}{btneditclu}, 0, 1, 0);
    $$self{_GUI}{btneditclu}->set_image(Gtk3::Image->new_from_stock('pac-cluster-manager2', 'GTK_ICON_SIZE_BUTTON'));
    $$self{_GUI}{btneditclu}->set('can-focus', 0);

    # Create a scrolledclu scrolled window to contain the clusters tree
    $$self{_GUI}{scrolledclu} = Gtk3::ScrolledWindow->new;
    $$self{_GUI}{nbCluTab} = Gtk3::HBox->new(0, 0);
    $$self{_GUI}{nbCluTabLabel} = Gtk3::Label->new;
    $$self{_GUI}{nbCluTab}->pack_start(Gtk3::Image->new_from_stock('pac-cluster-manager', 'button'), 0, 1, 0);
    if ($$self{_CFG}{'defaults'}{'layout'} ne 'Compact') {
        $$self{_GUI}{nbCluTab}->pack_start($$self{_GUI}{nbCluTabLabel}, 0, 1, 0);
    }
    $$self{_GUI}{nbCluTab}->set_tooltip_text('Clusters');
    $$self{_GUI}{nbCluTab}->show_all();
    $$self{_GUI}{vboxclu}->pack_start($$self{_GUI}{scrolledclu}, 1, 1, 0);
    $$self{_GUI}{nbTree}->append_page($$self{_GUI}{vboxclu}, $$self{_GUI}{nbCluTab});
    $$self{_GUI}{nbTree}->set_tab_reorderable($$self{_GUI}{vboxclu}, 1);
    $$self{_GUI}{scrolledclu}->set_shadow_type('none');
    $$self{_GUI}{scrolledclu}->set_policy('automatic', 'automatic');

    # Create treeClusters
    $$self{_GUI}{treeClusters} = PACTree->new (
        'Icon:' => 'pixbuf',
        'Name:' => 'markup'
    );
    $$self{_GUI}{scrolledclu}->add($$self{_GUI}{treeClusters});
    $$self{_GUI}{treeClusters}->set_enable_tree_lines(0);
    $$self{_GUI}{treeClusters}->set_headers_visible(0);
    $$self{_GUI}{treeClusters}->set_enable_search(0);
    $$self{_GUI}{treeClusters}->set_has_tooltip(0);

    # Put a separator
    if ($$self{_CFG}{'defaults'}{'layout'} ne 'Compact') {
        $$self{_GUI}{vbox3}->pack_start(Gtk3::HSeparator->new, 0, 1, 5);
    }

    # Create a hbox0: exec and clusters
    $$self{_GUI}{hbox0} = Gtk3::VBox->new(0, 0);
    $$self{_GUI}{vbox3}->pack_start($$self{_GUI}{hbox0}, 0, 1, 0);

    $$self{_GUI}{hboxsearchstart} = Gtk3::HBox->new(0, 0);
    $$self{_GUI}{hbox0}->pack_start($$self{_GUI}{hboxsearchstart}, 0, 1, 0);

    # Create a connSearch button
    $$self{_GUI}{connSearch} = Gtk3::Button->new;
    $$self{_GUI}{hboxsearchstart}->pack_start($$self{_GUI}{connSearch}, 0, 1, 0);
    $$self{_GUI}{connSearch}->set_image(Gtk3::Image->new_from_stock('gtk-find', 'button'));
    $$self{_GUI}{connSearch}->set('can-focus' => 0);
    $$self{_GUI}{connSearch}->set_tooltip_text('Start interactive search for connections');

    # Create connExecBtn button
    $$self{_GUI}{connExecBtn} = Gtk3::Button->new('Connect');
    $$self{_GUI}{hboxsearchstart}->pack_start($$self{_GUI}{connExecBtn}, 1, 1, 0);
    $$self{_GUI}{connExecBtn}->set_image(Gtk3::Image->new_from_stock('gtk-connect', 'button'));
    $$self{_GUI}{connExecBtn}->set('can-focus' => 0);
    $$self{_GUI}{connExecBtn}->set_tooltip_text('Start selected terminals/groups');

    # Create connQuickBtn button
    $$self{_GUI}{connQuickBtn} = Gtk3::Button->new;
    $$self{_GUI}{hboxsearchstart}->pack_start($$self{_GUI}{connQuickBtn}, 0, 1, 0);
    $$self{_GUI}{connQuickBtn}->set_image(Gtk3::Image->new_from_stock('pac-quick-connect', 'button'));
    $$self{_GUI}{connQuickBtn}->set('can-focus' => 0);
    $$self{_GUI}{connQuickBtn}->set_tooltip_text('Start a new connection, without saving it');

    # Create connFavourite button
    $$self{_GUI}{connFavourite} = Gtk3::ToggleButton->new;
    $$self{_GUI}{hboxsearchstart}->pack_start($$self{_GUI}{connFavourite}, 1, 1, 0);
    $$self{_GUI}{connFavourite}->set_image(Gtk3::Image->new_from_stock('gtk-about', 'button'));
    $$self{_GUI}{connFavourite}->set('can-focus' => 0);
    $$self{_GUI}{connFavourite}->set_tooltip_text('Add to/remove from favourites connections list');

    $$self{_GUI}{hboxclusters} = Gtk3::HBox->new(0, 0);
    $$self{_GUI}{hbox0}->pack_start($$self{_GUI}{hboxclusters}, 0, 1, 0);

    # Create clusterBtn button
    if ($$self{_CFG}{'defaults'}{'layout'} eq 'Compact') {
        $$self{_GUI}{clusterBtn} = Gtk3::Button->new();
    } else {
        $$self{_GUI}{clusterBtn} = Gtk3::Button->new_with_mnemonic('C_lusters');
    }
    $$self{_GUI}{hboxclusters}->pack_start($$self{_GUI}{clusterBtn}, 1, 1, 0);
    $$self{_GUI}{clusterBtn}->set_image(Gtk3::Image->new_from_stock('pac-cluster-manager', 'button'));
    $$self{_GUI}{clusterBtn}->set('can-focus' => 0);
    $$self{_GUI}{clusterBtn}->set_tooltip_text('Open the Clusters Administration Console');

    # Create scriptsBtn button
    if ($$self{_CFG}{'defaults'}{'layout'} eq 'Compact') {
        $$self{_GUI}{scriptsBtn} = Gtk3::Button->new();
    } else {
        $$self{_GUI}{scriptsBtn} = Gtk3::Button->new_with_mnemonic('Scrip_ts');
    }
    $$self{_GUI}{hboxclusters}->pack_start($$self{_GUI}{scriptsBtn}, 1, 1, 0);
    $$self{_GUI}{scriptsBtn}->set_image(Gtk3::Image->new_from_stock('pac-script', 'button'));
    $$self{_GUI}{scriptsBtn}->set('can-focus' => 0);
    $$self{_GUI}{scriptsBtn}->set_tooltip_text('Open the Scripts Administration Console');

    # Create clusterBtn button
    if ($$self{_CFG}{'defaults'}{'layout'} eq 'Compact') {
        $$self{_GUI}{pccBtn} = Gtk3::Button->new();
    } else {
        $$self{_GUI}{pccBtn} = Gtk3::Button->new_with_mnemonic('PC_C');
    }
    $$self{_GUI}{hboxclusters}->pack_start($$self{_GUI}{pccBtn}, 1, 1, 0);
    $$self{_GUI}{pccBtn}->set_image(Gtk3::Image->new_from_stock('gtk-justify-fill', 'GTK_ICON_SIZE_BUTTON'));
    $$self{_GUI}{pccBtn}->set('can-focus' => 0);
    $$self{_GUI}{pccBtn}->set_tooltip_text("Open the Power Clusters Controller:\nexecute commands in every clustered terminal from this single window");

    # Create a vbox5: description
    $$self{_GUI}{vbox5} = Gtk3::VBox->new(0, 0);
    if ($$self{_CFG}{defaults}{'tabs in main window'}) {
        $$self{_GUI}{vbox5}->set_border_width(5);
    }
    $$self{_GUI}{hpane}->pack2($$self{_GUI}{vbox5}, 1, 0);
    if ($$self{_CFG}{defaults}{'tree on right side'}) {
        $$self{_GUI}{hpane}->pack1($$self{_GUI}{vbox5}, 0, 0);
    } else {
        $$self{_GUI}{hpane}->pack2($$self{_GUI}{vbox5}, 0, 0);
    }

    # Create a notebook widget
    my $nb = Gtk3::Notebook->new();
    $$self{_GUI}{vbox5}->pack_start($nb, 1, 1, 0);
    $nb->set_scrollable(1);
    $nb->set_tab_pos($$self{_CFG}{'defaults'}{'tabs position'});
# FIXME-HOMOGENEOUS     $nb->set('homogeneous', 0);

    my $tablbl = Gtk3::HBox->new(0, 0);
    my $eblbl = Gtk3::EventBox->new;
    $eblbl->add(Gtk3::Label->new('Info '));
    $tablbl->pack_start($eblbl, 0, 1, 0);
    $$self{_GUI}{_TABIMG} = Gtk3::Image->new_from_stock('gtk-info', 'menu');
    $tablbl->pack_start($$self{_GUI}{_TABIMG}, 0, 1, 0);
    $tablbl->show_all();

    # Create a vboxInfo: description
    $$self{_GUI}{vboxInfo} = Gtk3::VBox->new(0, 0);
    $nb->append_page($$self{_GUI}{vboxInfo}, $tablbl);

    # Create a scrolled2 scrolled window to contain the description textview
    $$self{_GUI}{scrollDescription} = Gtk3::ScrolledWindow->new;
    $$self{_GUI}{vboxInfo}->pack_start($$self{_GUI}{scrollDescription}, 1, 1, 0);
    $$self{_GUI}{scrollDescription}->set_policy('automatic', 'automatic');

    # Create descView as a gtktextview with descBuffer
    $$self{_GUI}{descBuffer} = Gtk3::TextBuffer->new;
    $$self{_GUI}{descView} = Gtk3::TextView->new_with_buffer($$self{_GUI}{descBuffer});
    $$self{_GUI}{descView}->set_border_width(5);
    $$self{_GUI}{scrollDescription}->add($$self{_GUI}{descView});
    $$self{_GUI}{descView}->set_wrap_mode('GTK_WRAP_WORD');
    $$self{_GUI}{descView}->set_sensitive(1);
    $$self{_GUI}{descView}->drag_dest_unset;
    $$self{_GUI}{descView}->modify_font(Pango::FontDescription::from_string('monospace'));

    # Create a frameStatistics for statistics
    $$self{_GUI}{frameStatistics} = Gtk3::Frame->new(' STATISTICS: ');
    $$self{_GUI}{vboxInfo}->pack_start($$self{_GUI}{frameStatistics}, 0, 1, 0);
    $$self{_GUI}{frameStatistics}->set_border_width(5);

    $$self{_GUI}{frameStatisticslbl} = Gtk3::Label->new;
    $$self{_GUI}{frameStatisticslbl}->set_markup(' <b>STATISTICS:</b> ');
    $$self{_GUI}{frameStatistics}->set_label_widget($$self{_GUI}{frameStatisticslbl});

    $$self{_GUI}{statistics} = $$self{_SCREENSHOTS} = PACStatistics->new;
    $$self{_GUI}{frameStatistics}->add($$self{_GUI}{statistics}->{container});

    # Create a frameScreenshot for screenshot
    $$self{_GUI}{frameScreenshots} = Gtk3::Frame->new(' SCREENSHOTS: ');
    $$self{_GUI}{vboxInfo}->pack_start($$self{_GUI}{frameScreenshots}, 0, 1, 0);
    $$self{_GUI}{frameScreenshots}->set_border_width(5);

    $$self{_GUI}{frameScreenshotslbl} = Gtk3::Label->new;
    $$self{_GUI}{frameScreenshotslbl}->set_markup(' <b>SCREENSHOTS:</b> ');
    $$self{_GUI}{frameScreenshots}->set_label_widget($$self{_GUI}{frameScreenshotslbl});

    $$self{_GUI}{screenshots} = $$self{_SCREENSHOTS} = PACScreenshots->new;
    $$self{_GUI}{frameScreenshots}->add($$self{_GUI}{screenshots}->{container});

    # Create a hbuttonbox1: show/hide, WOL, Shell, Preferences, etc...
    $$self{_GUI}{hbuttonbox1} = Gtk3::HBox->new;
    $$self{_GUI}{vbox5}->pack_start($$self{_GUI}{hbuttonbox1}, 0, 1, 0);

    # Create hideConn button
    $$self{_GUI}{showConnBtn} = Gtk3::ToggleButton->new;
    $$self{_GUI}{showConnBtn}->set_image(Gtk3::Image->new_from_stock('pac-treelist', 'GTK_ICON_SIZE_BUTTON'));
    $$self{_GUI}{showConnBtn}->set_active(1);
    $$self{_GUI}{hbuttonbox1}->pack_start($$self{_GUI}{showConnBtn}, 1, 1, 0);
    $$self{_GUI}{showConnBtn}->set('can-focus' => 0);
    $$self{_GUI}{showConnBtn}->set_tooltip_text('Show/Hide connections tree panel');

    # Create WakeOnLan button
    $$self{_GUI}{wolBtn} = Gtk3::Button->new_with_mnemonic('Wake On Lan');
    $$self{_GUI}{wolBtn}->set_image(Gtk3::Image->new_from_stock('pac-wol', 'button'));
    $$self{_GUI}{hbuttonbox1}->pack_start($$self{_GUI}{wolBtn}, 1, 1, 0);
    $$self{_GUI}{wolBtn}->set('can-focus' => 0);
    $$self{_GUI}{wolBtn}->set_tooltip_text('Start the Wake On Lan utility window');

    # Create shellBtn button
    $$self{_GUI}{shellBtn} = Gtk3::Button->new;
    if ($$self{_CFG}{'defaults'}{'layout'} eq 'Compact') {
        $$self{_GUI}{hboxclusters}->pack_start($$self{_GUI}{shellBtn}, 1, 1, 0);
    } else {
        $$self{_GUI}{hbuttonbox1}->pack_start($$self{_GUI}{shellBtn}, 1, 1, 0);
    }
    $$self{_GUI}{shellBtn}->set_image(Gtk3::Image->new_from_stock('pac-shell', 'button'));
    $$self{_GUI}{shellBtn}->set('can-focus' => 0);
    $$self{_GUI}{shellBtn}->set_tooltip_text('Launch new local shell <Ctrl><Shift>t');

    # Create configBtn button
    if ($$self{_CFG}{'defaults'}{'layout'} eq 'Compact') {
        $$self{_GUI}{configBtn} = Gtk3::Button->new();
        $$self{_GUI}{hboxclusters}->pack_start($$self{_GUI}{configBtn}, 1, 1, 0);
    } else {
        $$self{_GUI}{configBtn} = Gtk3::Button->new_with_mnemonic('_Preferences');
        $$self{_GUI}{hbuttonbox1}->pack_start($$self{_GUI}{configBtn}, 1, 1, 0);
    }
    $$self{_GUI}{configBtn}->set_image(Gtk3::Image->new_from_stock('gtk-preferences', 'button'));
    $$self{_GUI}{configBtn}->set('can-focus' => 0);
    $$self{_GUI}{configBtn}->set_tooltip_text('Open the general preferences control');

    # Create saveBtn button
    $$self{_GUI}{saveBtn} = Gtk3::Button->new_with_mnemonic('_Save');
    $$self{_GUI}{saveBtn}->set_image(Gtk3::Image->new_from_stock('gtk-save', 'button'));
    $$self{_GUI}{hbuttonbox1}->pack_start($$self{_GUI}{saveBtn}, 1, 1, 0);
    $$self{_GUI}{saveBtn}->set('can-focus' => 0);
    $$self{_GUI}{saveBtn}->set_sensitive(0);

    # Create [un]lockBtn button
    $$self{_GUI}{lockPACBtn} = Gtk3::ToggleButton->new;
    $$self{_GUI}{lockPACBtn}->set_image(Gtk3::Image->new_from_stock('pac-unprotected', 'GTK_ICON_SIZE_BUTTON'));
    $$self{_GUI}{lockPACBtn}->set_active(0);
    $$self{_GUI}{hbuttonbox1}->pack_start($$self{_GUI}{lockPACBtn}, 0, 1, 0);
    $$self{_GUI}{lockPACBtn}->set('can-focus' => 0);
    $$self{_GUI}{lockPACBtn}->set_tooltip_text('Password [un]lock GUI. In order to use this functionality, check the "Protect with password" field under "Preferences"->"Main Options"');

    # Create aboutBtn button
    $$self{_GUI}{aboutBtn} = Gtk3::Button->new;
    $$self{_GUI}{aboutBtn}->set_image(Gtk3::Image->new_from_stock('gtk-about', 'button'));
    $$self{_GUI}{hbuttonbox1}->pack_start($$self{_GUI}{aboutBtn}, 1, 1, 0);
    $$self{_GUI}{aboutBtn}->set('can-focus' => 0);
    $$self{_GUI}{aboutBtn}->set_tooltip_text('Show the *so needed* "About" dialog');

    # Create quitBtn button
    if ($$self{_CFG}{'defaults'}{'layout'} eq 'Compact') {
        $$self{_GUI}{quitBtn} = Gtk3::Button->new();
    } else {
        $$self{_GUI}{quitBtn} = Gtk3::Button->new_with_mnemonic('_Quit');
    }
    $$self{_GUI}{quitBtn}->set_image(Gtk3::Image->new_from_stock('gtk-quit', 'button'));
    if ($$self{_CFG}{'defaults'}{'layout'} eq 'Compact') {
        $$self{_GUI}{hboxclusters}->pack_start($$self{_GUI}{quitBtn}, 1, 1, 0);
    } else {
        $$self{_GUI}{hbuttonbox1}->pack_start($$self{_GUI}{quitBtn}, 1, 1, 0);
    }
    $$self{_GUI}{quitBtn}->set('can-focus' => 0);
    $$self{_GUI}{quitBtn}->set_tooltip_text('Exit');

    # Setup some window properties.
    $$self{_GUI}{main}->set_title("$APPNAME" . ($$self{_READONLY} ? ' - READ ONLY MODE' : ''));
    Gtk3::Window::set_default_icon_from_file($APPICON);
    $$self{_GUI}{main}->set_default_size($$self{_GUI}{sw} // 600, $$self{_GUI}{sh} // 480);
    $$self{_GUI}{main}->set_resizable(1);

    # Set treeviews font
    foreach my $tree ('Connections','Favourites','History') {
        my @col = $$self{_GUI}{"tree$tree"}->get_columns;
        if ($tree eq 'Connections') {
            $col[0]->set_visible(0);
        } else {
            my ($c) = $col[1]->get_cells;
            $c->set('font',$$self{_CFG}{defaults}{'tree font'});
        }
    }

    ##############################################
    # Build TABBED TERMINAL WINDOW
    ##############################################

    if ($$self{_CFG}{defaults}{'tabs in main window'}) {
        $$self{_GUI}{nb} = $nb;
        $$self{_GUI}{_PACTABS} = $$self{_GUI}{main};
    } else {
        # Create window
        $$self{_GUI}{_PACTABS} = Gtk3::Window->new;
        # Setup some window properties.
        $$self{_GUI}{_PACTABS}->set_title("Terminals Tabbed Window : $APPNAME (v$APPVERSION)");
        $$self{_GUI}{_PACTABS}->set_position('center');
        Gtk3::Window::set_default_icon_from_file($APPICON);
        $$self{_GUI}{_PACTABS}->set_size_request(200, 100);
        $$self{_GUI}{_PACTABS}->set_default_size(600, 400);
        $$self{_GUI}{_PACTABS}->set_resizable(1);
        $$self{_GUI}{_PACTABS}->maximize if $$self{_CFG}{'defaults'}{'start maximized'};

        # Create a notebook widget
        $$self{_GUI}{nb} = Gtk3::Notebook->new();
        $$self{_GUI}{_PACTABS}->add($$self{_GUI}{nb});
        $$self{_GUI}{nb}->set_scrollable(1);
        $$self{_GUI}{nb}->set_tab_pos($$self{_CFG}{'defaults'}{'tabs position'});

        $nb->set_show_tabs(0);
        $nb->set_property('show_border', 0);

        $$self{_TABSINWINDOW} = 1;
    }

    $$self{_GUI}{nb}->set('can_focus', 0);
    $$self{_GUI}{treeConnections}->grab_focus();

    # Load window size/position, and treeconnections size
    $self->_loadGUIData;
    if ($$self{_CFG}{defaults}{'start main maximized'}) {
        $$self{_GUI}{main}->set_position('center');
        $$self{_GUI}{main}->maximize;
    } else {
        if (defined $$self{_GUI}{posx} && ($$self{_GUI}{posx} eq 'maximized')) {
            $$self{_GUI}{main}->maximize;
        } else {
            $$self{_GUI}{main}->move($$self{_GUI}{posx} // 0, $$self{_GUI}{posy} // 0);
            $$self{_GUI}{main}->resize($$self{_GUI}{sw} // 1024, $$self{_GUI}{sh} // 768);
        }
    }

    # Build Config window
    $FUNCS{_CONFIG} = $$self{_CONFIG} = PACConfig->new($$self{_CFG});
    # Get the KeePass object from configuration
    $FUNCS{_KEEPASS} = $$self{_CONFIG}{_KEEPASS};

    # Build Edit window
    $$self{_EDIT} = PACEdit->new($$self{_CFG});
    $FUNCS{_EDIT} = $$self{_EDIT};

    # Build Cluster Administration window
    $$self{_CLUSTER} = PACCluster->new(\%RUNNING);
    $FUNCS{_CLUSTER} = $$self{_CLUSTER};

    # Build Power Cluster Controller window
    $FUNCS{_PCC} = $$self{_PCC} = PACPCC->new(\%RUNNING);

    # Build Tray icon
    $FUNCS{_TRAY} = $$self{_TRAY} = ! $UNITY ? PACTray->new($self) : PACTrayUnity->new($self);

    # Build PIPE object
    $FUNCS{_PIPE} = $$self{_PIPE} = PACPipe->new(\%RUNNING);

    # Build SCRIPTS object
    $FUNCS{_SCRIPTS} = $$self{_SCRIPTS} = PACScripts->new;

    # Build the STATISTICS object
    $FUNCS{_STATS} = $$self{_GUI}{statistics};

    $FUNCS{_METHODS} = $$self{_METHODS};
    $FUNCS{_MAIN} = $self;

    # To show_all, or not to show_all... that's the question!! :)
    $$self{_GUI}{main}->show_all() unless $$self{_CMDLINETRAY};
    $$self{_GUI}{hpane}->set_position($$self{_GUI}{hpanepos} // -1);
    $$self{_GUI}{_vboxSearch}->hide();

    $self->_updateGUIPreferences();
    if ($$self{_CFG}{'defaults'}{'start PAC tree on'} eq 'connections') {
        $$self{_GUI}{nbTree}->set_current_page(0);
    } elsif ($$self{_CFG}{'defaults'}{'start PAC tree on'} eq 'favourites') {
        $$self{_GUI}{nbTree}->set_current_page(1);
        $self->_updateFavouritesList();
        $self->_updateGUIFavourites();
    } elsif ($$self{_CFG}{'defaults'}{'start PAC tree on'} eq 'history') {
        $$self{_GUI}{nbTree}->set_current_page(2);
        $self->_updateGUIClusters();
    } else {
        $$self{_GUI}{nbTree}->set_current_page(3);
        $self->_updateGUIHistory();
    }

    return 1;
}

sub _setupCallbacks {
    my $self = shift;

    $$self{_APP}->signal_connect('open' , sub {
        my ($app, $files, $nfile, $hint) = @_;
        my ($command, $message) = $hint =~ /([^\|]+)\|(.*)?/;
        print "INFO: Received message : [$command]-[$message]\n";
        if ($command eq 'start-shell') {
            $$self{_GUI}{shellBtn}->clicked();
        } elsif ($command eq 'quick-conn') {
            $$self{_GUI}{connQuickBtn}->clicked();
        } elsif ($command eq 'start-uuid') {
            $self->_launchTerminals([ [ $message ] ]);
        } elsif ($command eq'show-conn') {
            $self->_showConnectionsList;
        } elsif ($command eq 'edit-uuid') {
            my $uuid = $message;
            my $path = $$self{_GUI}{treeConnections}->_getPath($uuid) or next;
            next unless ($uuid ne '__PAC__ROOT__');
            $$self{_GUI}{treeConnections}->expand_to_path($path);
            $$self{_GUI}{treeConnections}->set_cursor($path, undef, 0);
            $$self{_GUI}{connEditBtn}->clicked();
        } else {
            print "WARN: Unknown command received ($command)\n";
        }

        return 'ok';
    });

    ###################################
    # TREECONNECTIONS RELATED CALLBACKS
    ###################################

    # Setup some drag and drop operations
    my $drag_dest = ($$self{_CFG}{'defaults'}{'tabs in main window'}) ? $$self{_GUI}{vbox5} : $$self{_GUI}{nb};

    my @targets = (Gtk3::TargetEntry->new('Connect', [], 0));
    $drag_dest->drag_dest_set('GTK_DEST_DEFAULT_ALL', \@targets, [ 'copy', 'move' ]);
    $drag_dest->signal_connect('drag_motion' => sub { $_[0]->get_parent_window->raise; return 1; });
    $drag_dest->signal_connect('drag_drop' => sub {
        my ($me, $context, $x, $y, $data, $info, $time) = @_;

        my @idx;
        my %tmp;
        foreach my $uuid (@{ $$self{'DND'}{'selection'} }) {
            if (($$self{_CFG}{'environments'}{$uuid}{'_is_group'}) || ($uuid eq '__PAC__ROOT__')) {
                if (!_wConfirm($$self{_GUI}{main}, "<b>ATTENTION!!</b> You have dropped some group(s)\nAre you sure you want to start <b>ALL</b> of its child connections?")) {
                    return 1;
                }
                map $tmp{$_} = 1, $$self{_GUI}{treeConnections}->_getChildren($uuid, 0, 1);
            } else {
                $tmp{$uuid} = 1;
            }
        }
        foreach my $uuid (keys %tmp) {
            push(@idx, [ $uuid, 'tab' ]);
        }
        $self->_launchTerminals(\@idx);
        delete $$self{'DND'}{'selection'};
        return 1;
    });

    # Prepare common signalhandler for all three trees (DnD and tooltips)
    foreach my $what ('treeConnections', 'treeFavourites', 'treeHistory') {
        $$self{_GUI}{$what}->signal_connect('query_tooltip' => sub {
            my ($widget, $x, $y, $keyboard_tooltip, $tooltip_widget) = @_;

            if (!$$self{_CFG}{'defaults'}{'show connections tooltips'}) {
                return 0;
            }

            my ($bx, $by) = $$self{_GUI}{$what}->convert_widget_to_bin_window_coords($x, $y);
            my ($path, $col, $cx, $cy) = $$self{_GUI}{$what}->get_path_at_pos($bx, $by);
            if (!$path) {
                return 0;
            }
            my $model = $$self{_GUI}{$what}->get_model;
            my $uuid = $model->get_value($model->get_iter($path), 2);

            if ($$self{_CFG}{environments}{$uuid}{_is_group} || $uuid eq '__PAC__ROOT__') {
                return 0;
            }

            my $name = $$self{_CFG}{'environments'}{$uuid}{'name'};
            my $method = $$self{_CFG}{'environments'}{$uuid}{'method'};
            my $ip = $$self{_CFG}{'environments'}{$uuid}{'ip'};
            my $port = $$self{_CFG}{'environments'}{$uuid}{'port'};
            my $user = $$self{_CFG}{'environments'}{$uuid}{'user'};

            my $total_exp = 0;
            foreach my $exp (@{$$self{_CFG}{'environments'}{$uuid}{'expect'}}) {
                if (!$$exp{'active'}) {
                    next;
                }
                ++$total_exp;
            }
            my $string = "- <b>Name</b>: @{[__($name)]}\n";
            $string .= "- <b>Method</b>: $method\n";
            $string .= "- <b>IP / port</b>: $ip / $port\n";
            $string .= "- <b>User</b>: $user";
            if ($total_exp) {
                $string .= "- With $total_exp active <b>Expects</b>";
            }
            $string = _subst($string, $$self{_CFG}, $uuid);
            $tooltip_widget->set_markup($string);

            return 1;
        });
        $$self{_GUI}{$what}->drag_source_set('GDK_BUTTON1_MASK', \@targets, [ 'copy', 'move' ]);
        $$self{_GUI}{$what}->signal_connect('drag_begin' => sub {
            my ($me, $context, $x, $y, $data, $info, $time) = @_;

            my @sel = $$self{_GUI}{$what}->_getSelectedUUIDs();
            if ($sel[0] eq '__PAC__ROOT__') {
                return 0;
            }
            $$self{'DND'}{'context'} = $context;
            $$self{'DND'}{'text'} = '';
            @{ $$self{'DND'}{'selection'} } = @sel;

            $$self{'DND'}{'text'} = "<b> - Start / Chain(drop over connected Terminal):</b>";
            foreach my $uuid (@sel) {
                $$self{'DND'}{'text'} .= "\n" . ($$self{_CFG}{'environments'}{$uuid}{'_is_group'} ? '<b>Group:</b> ' : '<b>Connection:</b> ') . $$self{_CFG}{'environments'}{$uuid}{'name'};
            }
            my $icon_window = Gtk3::Window->new;
            my $icon_label = Gtk3::Label->new;
            $icon_label->set_markup($$self{'DND'}{'text'});
            $icon_label->set_margin_start(3);
            $icon_label->set_margin_end(3);
            $icon_label->set_margin_top(3);
            $icon_label->set_margin_bottom(3);
            $icon_window->get_style_context->add_class('dnd-icon');
            $icon_window->add($icon_label);
            $icon_window->show_all();
            my ($w, $h) = $icon_window->get_size();
            Gtk3::drag_set_icon_widget($context, $icon_window, $w / 2, $h);
        });

        $$self{_GUI}{$what}->signal_connect('drag_end' => sub { $$self{'DND'} = undef; return 1; });
        $$self{_GUI}{$what}->signal_connect('drag_failed' => sub {
            my ($w, $px, $py) = $$self{_GUI}{main}->get_window()->get_pointer();
            my $wsx = $$self{_GUI}{main}->get_window()->get_width();
            my $wsy = $$self{_GUI}{main}->get_window()->get_height();

            # User cancelled the drop operation: finish
            $_[2] eq 'user-cancelled' and return 0;

            # Drop happened out of window: launch terminals
            if (($px < 0) || ($py < 0) || ($px > $wsx) || ($py > $wsy)) {
                my @idx;
                my %tmp;
                foreach my $uuid (@{ $$self{'DND'}{'selection'} }) {
                    if (($$self{_CFG}{'environments'}{$uuid}{'_is_group'}) || ($uuid eq '__PAC__ROOT__')) {
                        if (!_wConfirm($$self{_GUI}{main}, "<b>ATTENTION!!</b> You have dropped some group(s)\nAre you sure you want to start <b>ALL</b> of its child connections?")) {
                            return 1;
                        }
                        map $tmp{$_} = 1, $$self{_GUI}{treeConnections}->_getChildren($uuid, 0, 1);
                    } else {
                        $tmp{$uuid} = 1;
                    }
                }
                foreach my $uuid (keys %tmp) {
                    push(@idx, [ $uuid, 'window' ]);
                }
                $self->_launchTerminals(\@idx);
                delete $$self{'DND'}{'selection'};
                return 1;
            }
            # Drop happened inside of window: finish
            return 0;
        });
    }

    # Capture 'add group' button clicked
    $$self{_GUI}{groupAddBtn}->signal_connect('clicked' => sub {
        my @groups = $$self{_GUI}{treeConnections}->_getSelectedUUIDs();
        my $group_uuid = $groups[0];
        my $parent_name = $$self{_CFG}{'environments'}{$group_uuid}{'name'} // 'AVAILABLE CONNECTIONS';
        if (!(($group_uuid eq '__PAC__ROOT__') || $$self{_CFG}{'environments'}{$group_uuid}{'_is_group'})) {
            return 1;
        }

        my $new_group = _wEnterValue($$self{_GUI}{main}, "<b>Creating new group</b>"  , "Enter a name for the new group under '$parent_name'");
        if ((! defined $new_group) || ($new_group =~ /^\s*$/go) || ($new_group eq '__PAC__ROOT__')) {
            return 1;
        }

        # Generate the UUID for the new Group
        my $uuid = OSSP::uuid->new; $uuid->make("v4");
        my $txt_uuid = $uuid->export("str");
        undef $uuid;

        # Add this new group to the list of children of it's parent
        $$self{_CFG}{'environments'}{$group_uuid}{'children'}{$txt_uuid} = 1;

        # Add the new group to the configuration
        $$self{_CFG}{'environments'}{$txt_uuid}{'_is_group'} = 1;
        $$self{_CFG}{'environments'}{$txt_uuid}{'name'} = $new_group;
        $$self{_CFG}{'environments'}{$txt_uuid}{'uuid'} = $txt_uuid;
        $$self{_CFG}{'environments'}{$txt_uuid}{'description'} = "Connection group '$new_group'";
        $$self{_CFG}{'environments'}{$txt_uuid}{'screenshots'} = [];
        $$self{_CFG}{'environments'}{$txt_uuid}{'children'} = {};
        $$self{_CFG}{'environments'}{$txt_uuid}{'parent'} = $group_uuid // '__PAC__ROOT__';

        # Add the new group to the PACTree
        $$self{_GUI}{treeConnections}->_addNode($$self{_CFG}{'environments'}{$txt_uuid}{'parent'}, $txt_uuid, $self->__treeBuildNodeName($txt_uuid), $GROUPICON);

        # Now, expand parent's group and focus the new connection
        $$self{_GUI}{treeConnections}->_setTreeFocus($txt_uuid);

        $UNITY and $FUNCS{_TRAY}->_setTrayMenu;
        $self->_setCFGChanged(1);
        return 1;
    });

    # Capture 'rename node' button clicked
    $$self{_GUI}{nodeRenBtn}->signal_connect('clicked' => sub {
        my $selection = $$self{_GUI}{treeConnections}->get_selection;
        my $modelsort = $$self{_GUI}{treeConnections}->get_model;
        my $model = $modelsort->get_model;
        my ($path) = _getSelectedRows($selection);
        if (!defined $path) {
            return 1;
        }
        my $node_uuid = $model->get_value($modelsort->convert_iter_to_child_iter($modelsort->get_iter($path)), 2);
        my $node = $$self{_CFG}{'environments'}{$node_uuid}{'name'};

        if ($$self{_CFG}{'environments'}{$node_uuid}{'_protected'}) {
            return _wMessage(undef, "Can not rename selection:\nSelected node is <b>'Protected'</b>");
        }

        my ($new_name, $new_title);
        if ($$self{_CFG}{'environments'}{$node_uuid}{'_is_group'}) {
            $new_name = _wEnterValue($$self{_GUI}{main}, "<b>Renaming Group</b>", "Enter a new name for Group '$node'", $node);
            $new_title = 'x';
        } else {
            ($new_name, $new_title) = _wAddRenameNode('rename', $$self{_CFG}, $node_uuid);
        }
        if ((!defined $new_name)||($new_name =~ /^\s*$/go)||($new_name eq '__PAC__ROOT__')||(!defined $new_title)||($new_title =~ /^\s*$/go)) {
            return 1;
        }
        my $gui_name = $self->__treeBuildNodeName($node_uuid,$new_name);

        $model->set($modelsort->convert_iter_to_child_iter($modelsort->get_iter($path)), 1, $gui_name);
        $$self{_CFG}{'environments'}{$node_uuid}{'description'} =~ s/^Connection with \'$$self{_CFG}{environments}{$node_uuid}{name}\'/Connection with \'$new_name\'/go;
        $$self{_CFG}{'environments'}{$node_uuid}{'name'} = $new_name;
        if (!$$self{_CFG}{'environments'}{$node_uuid}{'_is_group'}) {
            $$self{_CFG}{'environments'}{$node_uuid}{'title'} = $new_title;
        }

        $self->_setCFGChanged(1);
        if ($UNITY) {
            $FUNCS{_TRAY}->_setTrayMenu;
        }
        $self->_updateGUIWithUUID($node_uuid);
        return 1;
    });

    # Capture 'delete environment' button clicked
    $$self{_GUI}{nodeDelBtn}->signal_connect('clicked' => sub {
        my @del = $$self{_GUI}{treeConnections}->_getSelectedUUIDs();

        if (scalar(@del) && $del[0] eq '__PAC__ROOT__') {
            return 1;
        }
        if ($self->_hasProtectedChildren(\@del)) {
            return _wMessage(undef, "Can not delete selection:\nThere are <b>'Protected'</b> nodes selected");
        }

        if (scalar(@del) > 1) {
            if (!_wConfirm($$self{_GUI}{main}, "Delete <b>'" . (scalar(@del)) . "'</b> nodes and ALL of their contents?")) {
                return 1;
            }
        } elsif (!_wConfirm($$self{_GUI}{main}, "Delete node <b>'" . __($$self{_CFG}{'environments'}{ $del[0] }{'name'}) . "'</b> and ALL of its contents?")) {
            return 1;
        }
        # Delete selected nodes from treeConnections
        map $$self{_GUI}{treeConnections}->_delNode($_), @del;
        # Delete selected node from the configuration
        $self->_delNodes(@del);
        if ($UNITY) {
            $FUNCS{_TRAY}->_setTrayMenu;
        }
        $self->_setCFGChanged(1);
        return 1;
    });

    # Prepare common signalhandler for favs and hist trees (edit, row activate and lite tree menu)
    foreach my $what ('treeFavourites', 'treeHistory') {
        # Capture 'treeFavourites' keypress
        $$self{_GUI}{$what}->signal_connect('key_press_event' => sub {
            my ($widget, $event) = @_;

            my $keyval = '' . ($event->keyval);
            my $state = '' . ($event->state);
            if (!(($event->state == [qw(mod1-mask)])&&(!$$self{_CFG}{'defaults'}{'disable ALT key bindings'}))) {
                return 0;
            }
            my @sel = $$self{_GUI}{$what}->_getSelectedUUIDs();
            # e --> Show main edit connection window
            if (chr($keyval) eq 'e') {
                if ($sel[0] ne '__PAC_SHELL__') {
                    $$self{_GUI}{connEditBtn}->clicked();
                }
                return 1;
            }
            return 0;
        });

        # Capture row double clicking (execute selected connection)
        $$self{_GUI}{$what}->signal_connect('row_activated' => sub {
            $$self{_GUI}{connExecBtn}->clicked();
            return 1;
        });

        # Capture right click
        $$self{_GUI}{$what}->signal_connect('button_release_event' => sub {
            my ($widget, $event) = @_;
            if ($event->button ne 3) {
                return 0;
            }
            if (!$$self{_GUI}{$what}->_getSelectedUUIDs()) {
                return 1;
            }
            $self->_treeConnections_menu_lite($$self{_GUI}{$what});
            return 0;
        });
    }

    # Capture selected element changed
    $$self{_GUI}{treeFavourites}->get_selection->signal_connect('changed' => sub { $self->_updateGUIFavourites(); });
    $$self{_GUI}{treeHistory}->get_selection->signal_connect('changed' => sub { $self->_updateGUIHistory(); });

    $$self{_GUI}{btneditclu}->signal_connect('clicked' => sub { $$self{_CLUSTER}->show(1); });

    # Capture 'treeClusters' row activated
    $$self{_GUI}{treeClusters}->signal_connect('row_activated' => sub {
        my @sel = $$self{_GUI}{treeClusters}->_getSelectedNames;
        $self->_startCluster($sel[0]);
    });

    $$self{_GUI}{treeClusters}->get_selection->signal_connect('changed' => sub { $self->_updateGUIClusters(); });
    $$self{_GUI}{treeClusters}->signal_connect('key_press_event' => sub {
        my ($widget, $event) = @_;

        my $keyval = '' . ($event->keyval);
        my $state = '' . ($event->state);
        my @sel = $$self{_GUI}{treeClusters}->_getSelectedNames;
        if (!@sel) {
            return 0;
        }
        if (($event->state == [qw(mod1-mask)])&&(!$$self{_CFG}{'defaults'}{'disable ALT key bindings'})) {
            # e --> Show main edit connection Window
            if (chr($keyval) eq 'e') {
                $$self{_CLUSTER}->show($sel[0]);
                return 1;
            }
        }
    });

    # Capture 'treeconnections' keypress
    $$self{_GUI}{treeConnections}->signal_connect('key_press_event' => sub {
        my ($widget, $event) = @_;

        my $keyval = '' . ($event->keyval);
        my $state = '' . ($event->state);
        my $stateb = $event->get_state;
        my $unicode = Gtk3::Gdk::keyval_to_unicode($event->keyval); # 0 if not a character
        my $shift = $stateb * ['shift-mask'];
        my $ctrl = $stateb * ['control-mask'];
        my $alt = $stateb * ['mod1-mask'];
        my $alt2 = $stateb * ['mod2-mask'];
        my $alt5 = $stateb * ['mod5-mask'];

        #print "TREECONNECTIONS KEYPRESS:*$state*$keyval*" . chr($keyval) . "*$unicode*\n";
        #print "*$shift*$ctrl*$alt*$alt2*$alt5*\n";

        my @sel = $$self{_GUI}{treeConnections}->_getSelectedUUIDs();

        my $is_group = 0;
        my $is_root = 0;
        foreach my $uuid (@sel) {
            if ($uuid eq '__PAC__ROOT__') {
                $is_root = 1;
            }
            if ($$self{_CFG}{'environments'}{$uuid}{'_is_group'}) {
                $is_group = 1;
            }
        }

        # <Ctrl>
        if (($ctrl) && (! $$self{_CFG}{'defaults'}{'disable CTRL key bindings'})) {
            # <Ctrl>f --> FIND in treeView
            if ($keyval == 102) {
                $$self{_SHOWFINDTREE} = 1;
                $$self{_GUI}{_vboxSearch}->show;
                $$self{_GUI}{_entrySearch}->grab_focus();
                return 1;
            }
            # r --> Expand all
            elsif (chr($keyval) eq 'r') {
                $$self{_GUI}{treeConnections}->expand_all;
            }
            # t --> Collapse all
            elsif (chr($keyval) eq 't') {
                $$self{_GUI}{treeConnections}->collapse_all;
            }
            if (scalar(@sel)==0) {
                return 0;
            }

            # <Ctrl>d --> CLONE current connection
            if (chr($keyval) eq 'd') {
                $self->_copyNodes;
                foreach my $child (keys %{ $$self{_COPY}{'data'}{'__PAC__COPY__'}{'children'} }) {
                    $self->_pasteNodes($$self{_CFG}{'environments'}{ $sel[0] }{'parent'}, $child);
                    $$self{_COPY}{'data'} = {};
                };
            }
            # <Ctrl>c --> COPY current CONNECTION
            elsif ($keyval == 99) {
                $self->_copyNodes; return 1;
            }
            # <Ctrl>x --> CUT current CONNECTION
            elsif ($keyval == 120) {
                $self->_cutNodes;
                return 1;
            }
            # <Ctrl>v --> PASTE cut/copied CONNECTION
            elsif ($keyval == 118) {
                map $self->_pasteNodes($sel[0], $_), keys %{ $$self{_COPY}{'data'}{'__PAC__COPY__'}{'children'} };
                $$self{_COPY}{'data'} = {};
                return 1;
            }
        }
        # <Alt>
        elsif (($alt) && (!$$self{_CFG}{'defaults'}{'disable ALT key bindings'})) {
            # e --> Show main edit connection window
            if (chr($keyval) eq 'e') {
                if (!$is_root) {
                    $$self{_GUI}{connEditBtn}->clicked();
                }
                return 1;
            }
            # r --> Toggle protection flag
            elsif (chr($keyval) eq 'r') {
                if (!$is_root) {
                    $self->__treeToggleProtection();
                }
                return 1;
            }
            return 0;
        }
        # Capture 'F2' keypress to rename nodes
        elsif ($event->keyval == 65471) {
            if ((scalar(@sel) == 1) && ($sel[0] ne '__PAC__ROOT__')) {
                $$self{_GUI}{nodeRenBtn}->clicked();
            }
            return 1;
        }
        # Capture 'Del' keypress to delete connection
        elsif ($event->keyval == 65535) {
            $$self{_GUI}{nodeDelBtn}->clicked();
            return 1;
        }
        # Capture 'left arrow'  keypress to collapse row
        elsif ($event->keyval == 65361) {
            my @idx;
            foreach my $uuid (@sel) {
                push(@idx, [ $uuid ]);
            }
            if (scalar @idx != 1) {
                return 0;
            }
            my $tree = $$self{_GUI}{treeConnections};
            my $selection = $tree->get_selection;
            my $model = $tree->get_model;
            my @paths = _getSelectedRows($selection);
            my $uuid = $model->get_value($model->get_iter($paths[0]), 2);

            if (($uuid eq '__PAC__ROOT__') || ($$self{_CFG}{'environments'}{$uuid}{'_is_group'})) {
                if ($tree->row_expanded($$self{_GUI}{treeConnections}->_getPath($uuid))) {
                    $tree->collapse_row($$self{_GUI}{treeConnections}->_getPath($uuid));
                } elsif ($uuid ne '__PAC__ROOT__') {
                    $tree->set_cursor($$self{_GUI}{treeConnections}->_getPath($$self{_CFG}{'environments'}{$uuid}{'parent'}), undef, 0);
                }
            } else {
                $tree->set_cursor($$self{_GUI}{treeConnections}->_getPath($$self{_CFG}{'environments'}{$uuid}{'parent'}), undef, 0);
            }
        }
        # Capture 'right arrow' keypress to expand row
        elsif ($event->keyval == 65363) {
            my @idx;
            foreach my $uuid (@sel) {
                push(@idx, [ $uuid ]);
            }
            if (scalar @idx != 1) {
                return 0;
            }
            my $tree = $$self{_GUI}{treeConnections};
            my $selection = $tree->get_selection;
            my $model = $tree->get_model;
            my @paths = _getSelectedRows($selection);
            my $uuid = $model->get_value($model->get_iter($paths[0]), 2);
            if (!(($uuid eq '__PAC__ROOT__') || ($$self{_CFG}{'environments'}{$uuid}{'_is_group'}))) {
                return 0;
            }
            $tree->expand_row($paths[0], 0);
        }
        # Capture 'intro' keypress to expand/collapse row or launch terminals
        elsif ($event->keyval == 65293) {
            my $tree = $$self{_GUI}{treeConnections};
            my $selection = $tree->get_selection;
            my $model = $tree->get_model;
            my @paths = _getSelectedRows($selection);
            my $uuid = $model->get_value($model->get_iter($paths[0]), 2);

            if ((scalar(@paths) == 1) && (($uuid eq '__PAC__ROOT__') || ($$self{_CFG}{'environments'}{$uuid}{'_is_group'}))) {
                $tree->row_expanded($paths[0]) ? $tree->collapse_row($paths[0]) : $tree->expand_row($paths[0], 0);
            } else {
                my @idx;
                foreach my $uuid (@sel) {
                    push(@idx,[$uuid]);
                }
                $self->_launchTerminals(\@idx);
            }

            return 1;
        }
        # Capture 'standard ascii characters' to start custom interactive search
        elsif (($event->keyval >= 32) && ($event->keyval <= 126)) {
            $$self{_SHOWFINDTREE} = 1;
            $$self{_GUI}{_vboxSearch}->show;
            $$self{_GUI}{_entrySearch}->grab_focus();
            $$self{_GUI}{_entrySearch}->insert_text(chr($event->keyval), -1, 0);
            $$self{_GUI}{_entrySearch}->set_position(-1);
            return 1;
        } else {
            return 0;
        }
        return 1;
    });

    # Capture 'treeconnections' selected element changed
    $$self{_GUI}{treeConnections}->get_selection->signal_connect('changed' => sub {
        $self->_updateGUIPreferences();
        });

    # Capture row double clicking (execute selected connection)
    $$self{_GUI}{treeConnections}->signal_connect('row_activated' => sub {
        my @idx;
        foreach my $uuid ($$self{_GUI}{treeConnections}->_getSelectedUUIDs()) {
            push(@idx, [ $uuid ]);
        }
        if (scalar @idx != 1) {
            return 0;
        }

        my $tree = $$self{_GUI}{treeConnections};
        my $selection = $tree->get_selection;
        my $model = $tree->get_model;
        my @paths = _getSelectedRows($selection);
        my $uuid = $model->get_value($model->get_iter($paths[0]), 2);

        if (($uuid eq '__PAC__ROOT__') || ($$self{_CFG}{'environments'}{$uuid}{'_is_group'})) {
            if (!(($uuid eq '__PAC__ROOT__') || ($$self{_CFG}{'environments'}{$uuid}{'_is_group'}))) {
                return 0;
            }
            $tree->row_expanded($paths[0]) ? $tree->collapse_row($paths[0]) : $tree->expand_row($paths[0], 0);
        } else {
            $$self{_GUI}{connExecBtn}->clicked();
        }
    });

    # Capture tree rows collapsing
    $$self{_GUI}{treeConnections}->signal_connect('row_collapsed' => sub {
        my ($tree, $iter, $path) = @_;

        my $selection = $$self{_GUI}{treeConnections}->get_selection;
        my $modelsort = $$self{_GUI}{treeConnections}->get_model;
        my $model = $modelsort->get_model;
        my $group_uuid = $model->get_value($modelsort->convert_iter_to_child_iter($modelsort->get_iter($path)), 2);
        $$self{_GUI}{treeConnections}->columns_autosize;
        if ($group_uuid eq '__PAC__ROOT__') {
            return 0;
        }
        $model->set($modelsort->convert_iter_to_child_iter($modelsort->get_iter($path)), 0, $GROUPICONCLOSED);
        return 1;
    });

    # Capture tree rows expanding
    $$self{_GUI}{treeConnections}->signal_connect('row_expanded' => sub {
        my ($tree, $iter, $path) = @_;

        my $selection = $$self{_GUI}{treeConnections}->get_selection;
        my $modelsort = $$self{_GUI}{treeConnections}->get_model;
        my $model = $modelsort->get_model;
        my $group_uuid = $model->get_value($modelsort->convert_iter_to_child_iter($modelsort->get_iter($path)), 2);
        if ($group_uuid eq '__PAC__ROOT__') {
            return 0;
        }
        $model->set($modelsort->convert_iter_to_child_iter($modelsort->get_iter($path)), 0, $GROUPICONOPEN);
        foreach my $child ($$self{_GUI}{treeConnections}->_getChildren($group_uuid, 1, 0)) {
            $model->set($modelsort->convert_iter_to_child_iter($modelsort->get_iter($$self{_GUI}{treeConnections}->_getPath($child))), 0, $GROUPICONCLOSED);
        }
        return 1;
    });

    # Capture 'treeconnections' right click
    $$self{_GUI}{treeConnections}->signal_connect('button_press_event' => sub {
        my ($widget, $event) = @_;
        if ($event->button ne 3) {
            return 0;
        }
        if (!$$self{_GUI}{treeConnections}->_getSelectedUUIDs()) {
            return 0;
        }
        $self->_treeConnections_menu($event);
        return 1;
    });

    # Capture 'add connection' button clicked
    $$self{_GUI}{connAddBtn}->signal_connect('clicked' => sub {
        my @groups = $$self{_GUI}{treeConnections}->_getSelectedUUIDs();
        my $group_uuid = $groups[0];
        if (!(($group_uuid eq '__PAC__ROOT__') || $$self{_CFG}{'environments'}{$group_uuid}{'_is_group'})) {
            return 1;
        }
        # Prepare the input window
        my ($new_conn, $new_title) = _wAddRenameNode('add', $$self{_CFG}, $group_uuid);
        if ((! defined $new_conn) || ($new_conn =~ /^\s*$/go) || ($new_conn eq '__PAC__ROOT__')) {
            return 1;
        }
        my $uuid = OSSP::uuid->new; $uuid->make("v4");
        my $txt_uuid = $uuid->export("str");
        undef $uuid;

        # Create and initialize the new connection in configuration
        $$self{_CFG}{'environments'}{$txt_uuid}{'_is_group'} = 0;
        $$self{_CFG}{'environments'}{$txt_uuid}{'name'} = $new_conn;
        $$self{_CFG}{'environments'}{$txt_uuid}{'parent'} = $group_uuid;
        $$self{_CFG}{'environments'}{$txt_uuid}{'description'} = "Connection with '$new_conn'";
        $$self{_CFG}{'environments'}{$txt_uuid}{'screenshots'} = [];
        $$self{_CFG}{'environments'}{$txt_uuid}{'title'} = $new_title;
        $$self{_CFG}{'environments'}{$txt_uuid}{'method'} = 'ssh';
        $$self{_CFG}{'environments'}{$txt_uuid}{'ip'} = '';
        $$self{_CFG}{'environments'}{$txt_uuid}{'port'} = 22;
        $$self{_CFG}{'environments'}{$txt_uuid}{'user'} = '';
        $$self{_CFG}{'environments'}{$txt_uuid}{'pass'} = '';
        $$self{_CFG}{'environments'}{$txt_uuid}{'use proxy'} = 0;
        $$self{_CFG}{'environments'}{$txt_uuid}{'options'} = '';
        @{ $$self{_CFG}{'environments'}{$txt_uuid}{'local before'} } = ();
        @{ $$self{_CFG}{'environments'}{$txt_uuid}{'local connected'} } = ();
        @{ $$self{_CFG}{'environments'}{$txt_uuid}{'local after'} } = ();
        @{ $$self{_CFG}{'environments'}{$txt_uuid}{'macros'} } = ();
        @{ $$self{_CFG}{'environments'}{$txt_uuid}{'expect'} } = ();

        _cfgSanityCheck($$self{_CFG});

        # Add the node to the tree
        $$self{_GUI}{treeConnections}->_addNode($$self{_CFG}{'environments'}{$txt_uuid}{'parent'}, $txt_uuid, $self->__treeBuildNodeName($txt_uuid), $$self{_METHODS}{ $$self{_CFG}{'environments'}{$txt_uuid}{'method'} }{'icon'});
        $$self{_GUI}{treeConnections}->_setTreeFocus($txt_uuid);

        # Add the node to the parent's childs list
        $$self{_CFG}{'environments'}{$group_uuid}{'children'}{$txt_uuid} = 1;

        $self->_updateGUIPreferences();

        $$self{_EDIT}->show($txt_uuid, 'new');

        $UNITY and $FUNCS{_TRAY}->_setTrayMenu;
        $self->_setCFGChanged(1);
        return 1;
    });

    # Capture 'quick connect' button clicked
    $$self{_GUI}{connQuickBtn}->signal_connect('clicked' => sub {
        my $txt_uuid = '__PAC__QUICK__CONNECT__';

        # Create and initialize the new connection in configuration
        $$self{_CFG}{'environments'}{$txt_uuid}{'_is_group'} = 0;
        $$self{_CFG}{'environments'}{$txt_uuid}{'name'} = 'Quick Connect';
        $$self{_CFG}{'environments'}{$txt_uuid}{'parent'} = '__PAC__ROOT__';
        $$self{_CFG}{'environments'}{$txt_uuid}{'description'} = 'Quick Connection';
        $$self{_CFG}{'environments'}{$txt_uuid}{'screenshots'} = [];
        $$self{_CFG}{'environments'}{$txt_uuid}{'title'} = 'Quick Connect';
        $$self{_CFG}{'environments'}{$txt_uuid}{'method'} = 'ssh';
        $$self{_CFG}{'environments'}{$txt_uuid}{'ip'} = '';
        $$self{_CFG}{'environments'}{$txt_uuid}{'port'} = 22;
        $$self{_CFG}{'environments'}{$txt_uuid}{'user'} = '';
        $$self{_CFG}{'environments'}{$txt_uuid}{'pass'} = '';
        $$self{_CFG}{'environments'}{$txt_uuid}{'use proxy'} = 0;
        $$self{_CFG}{'environments'}{$txt_uuid}{'options'} = '';
        @{ $$self{_CFG}{'environments'}{$txt_uuid}{'local before'} } = ();
        @{ $$self{_CFG}{'environments'}{$txt_uuid}{'local connected'} } = ();
        @{ $$self{_CFG}{'environments'}{$txt_uuid}{'local after'} } = ();
        @{ $$self{_CFG}{'environments'}{$txt_uuid}{'macros'} } = ();
        @{ $$self{_CFG}{'environments'}{$txt_uuid}{'expect'} } = ();

        _cfgSanityCheck($$self{_CFG});

        $$self{_EDIT}->show($txt_uuid, 'quick');

        return 1;
    });

    ###############################
    # OTHER CALLBACKS
    ###############################

    $$self{_GUI}{connSearch}->signal_connect('clicked' => sub {
        if (!$$self{_GUI}{_vboxSearch}->get_visible) {
            $$self{_SHOWFINDTREE} = 1;
            $$self{_GUI}{_vboxSearch}->show;
            $$self{_GUI}{_entrySearch}->grab_focus();
        } else {
            $$self{_SHOWFINDTREE} = 0;
            $$self{_GUI}{_vboxSearch}->hide;
        }
    });
    $$self{_GUI}{_entrySearch}->signal_connect('key_press_event' => sub {
        # Capture 'escape' keypress to hide the interactive search
        if ($_[1]->keyval == 65307) {
            $$self{_SHOWFINDTREE} = 0;
            $$self{_GUI}{_entrySearch}->set_text('');
            $$self{_GUI}{_vboxSearch}->hide;
            $$self{_GUI}{treeConnections}->grab_focus();
            return 1;
        }
        # Capture 'up arrow'  keypress to move to previous ocurrence
        elsif ($_[1]->keyval == 65362) {
            $$self{_GUI}{_btnPrevSearch}->clicked();
            return 1;
        }
        # Capture 'down arrow'  keypress to move to next ocurrence
        elsif ($_[1]->keyval == 65364) {
            $$self{_GUI}{_btnNextSearch}->clicked();
            return 1;
        }
        return 0
    });

    $$self{_GUI}{_entrySearch}->signal_connect('activate' => sub {
        my @sel = $$self{_GUI}{treeConnections}->_getSelectedUUIDs();
        if ((scalar(@sel)==1)&&($sel[0] ne '__PAC__ROOT__')&&(!$$self{_CFG}{'environments'}{$sel[0]}{'_is_group'})&&($$self{_GUI}{_entrySearch}->get_chars(0, -1) ne '')) {
            $$self{_GUI}{connExecBtn}->clicked();
        }
    });
    $$self{_GUI}{_entrySearch}->signal_connect('focus_out_event' => sub {
        $$self{_SHOWFINDTREE} = 0;
        $$self{_GUI}{_vboxSearch}->hide;
        $$self{_GUI}{_entrySearch}->set_text('');
    });
    foreach my $what ('Name', 'Host', 'Desc') {
        $$self{_GUI}{"_rbSearch" . $what}->signal_connect('toggled' => sub {
            my $text = $$self{_GUI}{_entrySearch}->get_chars(0, -1);
            $$self{_GUI}{_btnPrevSearch}->set_sensitive(0);
            $$self{_GUI}{_btnNextSearch}->set_sensitive(0);
            if ($text eq '') {
                return 0;
            }
            my $where = 'name';
            $$self{_GUI}{_rbSearchHost}->get_active() and $where = 'host';
            $$self{_GUI}{_rbSearchDesc}->get_active() and $where = 'desc';
            $$self{_GUI}{_RESULT} = $self->__search($text, $$self{_GUI}{treeConnections}, $where);
            $$self{_GUI}{_ACTUAL} = 0;
            if (@{ $$self{_GUI}{_RESULT} }) {
                $$self{_GUI}{_btnPrevSearch}->set_sensitive(1);
                $$self{_GUI}{_btnNextSearch}->set_sensitive(1);
                $$self{_GUI}{treeConnections}->_setTreeFocus($$self{_GUI}{_RESULT}[ $$self{_GUI}{_ACTUAL} ]);
            }
            return 0;
        });
    }
    $$self{_GUI}{_entrySearch}->signal_connect('changed' => sub {
        my $text = $$self{_GUI}{_entrySearch}->get_chars(0, -1);
        $$self{_GUI}{_btnPrevSearch}->set_sensitive(0);
        $$self{_GUI}{_btnNextSearch}->set_sensitive(0);
        if ($text eq '') {
            return 0;
        }
        my $where = 'name';
        $$self{_GUI}{_rbSearchHost}->get_active() and $where = 'host';
        $$self{_GUI}{_rbSearchDesc}->get_active() and $where = 'desc';
        $$self{_GUI}{_RESULT} = $self->__search($text, $$self{_GUI}{treeConnections}, $where);
        $$self{_GUI}{_ACTUAL} = 0;
        if (@{ $$self{_GUI}{_RESULT} }) {
            $$self{_GUI}{_btnPrevSearch}->set_sensitive(1);
            $$self{_GUI}{_btnNextSearch}->set_sensitive(1);
            $$self{_GUI}{treeConnections}->_setTreeFocus($$self{_GUI}{_RESULT}[ $$self{_GUI}{_ACTUAL} ]);
        } else {
            $$self{_GUI}{_btnPrevSearch}->set_sensitive(0);
            $$self{_GUI}{_btnNextSearch}->set_sensitive(0);
            $$self{_GUI}{treeConnections}->_setTreeFocus('__PAC__ROOT__');
        }
        return 0;
    });

    $$self{_GUI}{_btnPrevSearch}->signal_connect('clicked' => sub {
        if (!@{$$self{_GUI}{_RESULT}}) {
            return 1;
        }
        if ($$self{_GUI}{_ACTUAL} == 0) {
            $$self{_GUI}{_ACTUAL} = $#{$$self{_GUI}{_RESULT}};
        } else {
            $$self{_GUI}{_ACTUAL}--;
        }
        $$self{_GUI}{treeConnections}->_setTreeFocus($$self{_GUI}{_RESULT}[$$self{_GUI}{_ACTUAL}]);
        return 1;
    });

    $$self{_GUI}{_btnNextSearch}->signal_connect('clicked' => sub {
        if (!@{$$self{_GUI}{_RESULT}}) {
            return 1;
        }
        if ($$self{_GUI}{_ACTUAL} == $#{ $$self{_GUI}{_RESULT} }) {
            $$self{_GUI}{_ACTUAL} = 0;
        } else {
            $$self{_GUI}{_ACTUAL}++;
        }
        $$self{_GUI}{treeConnections}->_setTreeFocus($$self{_GUI}{_RESULT}[ $$self{_GUI}{_ACTUAL} ]);
        return 1;
    });

    $$self{_GUI}{showConnBtn}->signal_connect('toggled' => sub {
        $$self{_GUI}{showConnBtn}->get_active() ? $$self{_GUI}{vbox3}->show : $$self{_GUI}{vbox3}->hide;
        if ($$self{_GUI}{showConnBtn}->get_active()) {
            $$self{_GUI}{treeConnections}->grab_focus();
        }
        return 1;
    });

    # Catch buttons' keypresses
    $$self{_GUI}{connExecBtn}->signal_connect('clicked' => sub {
        my ($tree,@idx,%tmp);
        my $pnum = $$self{_GUI}{nbTree}->get_current_page();
        if  ($$self{_GUI}{nbTree}->get_nth_page($pnum) eq $$self{_GUI}{scroll1}) {
            $tree = $$self{_GUI}{treeConnections};
        } elsif ($$self{_GUI}{nbTree}->get_nth_page($pnum) eq $$self{_GUI}{scroll2}) {
            $tree = $$self{_GUI}{treeFavourites};
        } elsif ($$self{_GUI}{nbTree}->get_nth_page($pnum) eq $$self{_GUI}{scroll3}) {
            $tree = $$self{_GUI}{treeHistory};
        } else {
            my @sel = $$self{_GUI}{treeClusters}->_getSelectedNames;
            $self->_startCluster($sel[0]);
            return 1;
        }
        if (!$tree->_getSelectedUUIDs()) {
            return 1;
        }
        foreach my $uuid ($tree->_getSelectedUUIDs()) {
            if (($$self{_CFG}{'environments'}{$uuid}{'_is_group'}) || ($uuid eq '__PAC__ROOT__')) {
                my @children = $$self{_GUI}{treeConnections}->_getChildren($uuid, 0, 1);
                foreach my $child (@children) {
                    if (!$$self{_CFG}{'environments'}{$child}{'_is_group'}) {
                        $tmp{$child} = 1;
                    }
                }
            } else {
                $tmp{$uuid} = 1;
            }
        }
        map push(@idx,[$_]),keys %tmp;
        $self->_launchTerminals(\@idx);
    });
    $$self{_GUI}{configBtn}->signal_connect('clicked' => sub { $$self{_CONFIG}->show; });
    $$self{_GUI}{connEditBtn}->signal_connect('clicked' => sub {
        my $pnum = $$self{_GUI}{nbTree}->get_current_page();
        my $tree;

        if  ($pnum == 0) {
            $tree = $$self{_GUI}{treeConnections};
        } elsif ($pnum == 1) {
            $tree = $$self{_GUI}{treeFavourites};
        } else {
            $tree = $$self{_GUI}{treeHistory};
        }
        my @sel = $tree->_getSelectedUUIDs();
        if (!scalar(@sel)) {
            return 1;
        }
        my $is_group = 0;
        my $is_root = 0;

        foreach my $uuid (@sel) {
            if ($uuid eq '__PAC__ROOT__') {
                $is_root = 1;
            }
            if ($$self{_CFG}{'environments'}{$uuid}{'_is_group'}) {
                $is_group = 1;
            }
        }
        if (((scalar(@sel)>1) || ((scalar(@sel)==1) && $is_group)) && ($self->_hasProtectedChildren(\@sel))) {
            return _wMessage(undef, "Can not " . (scalar(@sel) > 1 ? 'Bulk ' : ' ') . "Edit selection:\nThere are <b>'Protected'</b> nodes selected");
        }

        if ((scalar(@sel) == 1) && (! $is_group)) {
            $$self{_EDIT}->show($sel[0]);
        } elsif ((scalar(@sel) > 1) || ((scalar(@sel) == 1) && $is_group)) {
            my ($list, $all) = $self->_bulkEdit("$APPNAME (v$APPVERSION) : Bulk Edit", "Bulk Editing <b>" . scalar(@sel) . "</b> nodes.\nSelect and change the values you want to modify in the list below.\n<b>Only those checked will be affected.</b>\nFor Regular Expressions, <b>Match pattern</b> will substituted with <b>New value</b>,\nmuch like Perl's: <b>s/<span foreground=\"#E60023\">Match pattern</span>/<span foreground=\"#04C100\">New value</span>/g</b>", $is_group);
            if (!defined $list) {
                return 1;
            }
            foreach my $parent_uuid (@sel) {
                if ($$self{_CFG}{'environments'}{$parent_uuid}{'_is_group'} || $parent_uuid eq '__PAC__ROOT__') {
                    foreach my $uuid ($$self{_GUI}{treeConnections}->_getChildren($parent_uuid, 0, $all)) {
                        _substCFG($$self{_CFG}{'environments'}{$uuid}, $list);
                    }
                } else {
                    _substCFG($$self{_CFG}{'environments'}{$parent_uuid}, $list);
                }
            }
            $self->_setCFGChanged(1);
        }
    });
    $$self{_GUI}{shellBtn}->signal_connect('clicked' => sub { $self->_launchTerminals([ [ '__PAC_SHELL__' ] ]); return 1; });
    $$self{_GUI}{clusterBtn}->signal_connect('clicked' => sub { $$self{_CLUSTER}->show; });
    $$self{_GUI}{connFavourite}->signal_connect('toggled' => sub {
        if ($$self{_NO_PROPAGATE_FAV_TOGGLE}) {
            return 1;
        }
        my $pnum = $$self{_GUI}{nbTree}->get_current_page();
        my $tree;
        if  ($pnum == 0) {
            $tree = $$self{_GUI}{treeConnections};
        } elsif ($pnum == 1) {
            $tree = $$self{_GUI}{treeFavourites};
        } else {
            $tree = $$self{_GUI}{treeHistory};
        }
        if (!$tree->_getSelectedUUIDs()) {
            return 1;
        }
        map $$self{_CFG}{'environments'}{$_}{'favourite'} = $$self{_GUI}{connFavourite}->get_active(), $tree->_getSelectedUUIDs();
        if ($$self{_GUI}{nbTree}->get_current_page() == 1) {
            $self->_updateFavouritesList();
            $self->_updateGUIFavourites();
            $self->_updateGUIPreferences();
        }
        $$self{_GUI}{connFavourite}->set_image(Gtk3::Image->new_from_stock('pac-favourite-' . ($$self{_GUI}{connFavourite}->get_active() ? 'on' : 'off'), 'button'));
        if ($UNITY) {
            $FUNCS{_TRAY}->_setTrayMenu;
        }
        $self->_setCFGChanged(1);
        return 1;
    });
    $$self{_GUI}{scriptsBtn}->signal_connect('clicked' => sub { $$self{_SCRIPTS}->show(); });
    $$self{_GUI}{pccBtn}->signal_connect('clicked' => sub { $$self{_PCC}->show(); });
    $$self{_GUI}{quitBtn}->signal_connect('clicked' => sub { $self->_quitProgram(); });
    $$self{_GUI}{saveBtn}->signal_connect('clicked' => sub { $self->_saveConfiguration(); });
    $$self{_GUI}{aboutBtn}->signal_connect('clicked' => sub { $self->_showAboutWindow(); });
    $$self{_GUI}{wolBtn}->signal_connect('clicked' => sub { _wakeOnLan; });
    $$self{_GUI}{lockPACBtn}->signal_connect('toggled' => sub { $$self{_GUI}{lockPACBtn}->get_active() ? $self->_lockPAC : $self->_unlockPAC; });

    # Capture CONN TAB page switching
    $$self{_GUI}{nbTree}->signal_connect('switch_page' => sub {
        my ($nb, $p, $pnum) = @_;

        $$self{_NO_PROPAGATE_FAV_TOGGLE} = 1;
        $$self{_GUI}{connFavourite}->set_active(0);
        $$self{_GUI}{connFavourite}->set_sensitive(0);
        $$self{_GUI}{connFavourite}->set_image(Gtk3::Image->new_from_stock('pac-favourite-off', 'button'));
        $$self{_NO_PROPAGATE_FAV_TOGGLE} = 0;

        my $page = $$self{_GUI}{nbTree}->get_nth_page($pnum);

        # Connections
        if ($page eq $$self{_GUI}{scroll1}) {
            $self->_updateGUIPreferences();
        }
        # Favourites
        elsif ($page eq $$self{_GUI}{scroll2}) {
            $self->_updateFavouritesList();
            $self->_updateGUIFavourites();
        }
        # History
        elsif ($page eq $$self{_GUI}{scroll3}) {
            $self->_updateGUIHistory();
        }
        # Clusters
        else {
            $self->_updateClustersList();
            $self->_updateGUIClusters();
        }
        return 1;
    });

    # Capture tabs events on pactabs window
    $$self{_GUI}{nb}->signal_connect('page_removed' => sub {
        if (!defined $$self{_GUI}{_PACTABS}) {
            return 1;
        }
        if  ($$self{_GUI}{nb}->get_n_pages == 0) {
            $$self{_GUI}{_PACTABS}->hide();
        } elsif ($$self{_GUI}{nb}->get_n_pages == 1) {
            $$self{_GUI}{treeConnections}->grab_focus();
            $$self{_GUI}{showConnBtn}->set_active(1);

            if ($$self{_CFG}{defaults}{'when no more tabs'} == 0) {
                #nothing
            }
            elsif ($$self{_CFG}{defaults}{'when no more tabs'} == 1) {
                #quit
                $self->_quitProgram();
            }
            elsif ($$self{_CFG}{defaults}{'when no more tabs'} == 2) {
                #hide
                if ($UNITY) {
                    $$self{_TRAY}{_TRAY}->set_active();
                } else {
                    $$self{_TRAY}{_TRAY}->set_visible(1);
                }
                # Trigger the "lock" procedure ?
                if ($$self{_CFG}{'defaults'}{'use gui password'} && $$self{_CFG}{'defaults'}{'use gui password tray'}) {
                    $$self{_GUI}{lockPACBtn}->set_active(1);
                }
                # Hide main window
                $self->_hideConnectionsList();
            }
        }
        return 1;
    });
    $$self{_GUI}{nb}->signal_connect('page_added' => sub {
        if (defined $$self{_GUI}{_PACTABS}) {
            if ($$self{_GUI}{nb}->get_n_pages) {
                $$self{_GUI}{_PACTABS}->show;
            }
        }
        return 1;
    });

    # Capture TABs window closing
    ! $$self{_CFG}{defaults}{'tabs in main window'} and $$self{_GUI}{_PACTABS}->signal_connect('delete_event' => sub {
        if ($$self{_GUILOCKED} || ! _wConfirm(undef, "Close <b>TABBED TERMINALS</b> Window ?")) {
            return 1;
        }
        foreach my $uuid (keys %RUNNING) {
            # Should && this two together, will leave it for another time
            if (!defined $RUNNING{$uuid}{'terminal'}) {
                next;
            }
            if (!($RUNNING{$uuid}{'terminal'}{_TABBED} || $RUNNING{$uuid}{'terminal'}{_RETABBED})) {
                next;
            }
            $RUNNING{$uuid}{'terminal'}->stop('force');
        }
        return 1;
    });

    # Capture some keypress on TABBED window
    $$self{_GUI}{_PACTABS}->signal_connect('key_press_event' => sub {
        my ($widget, $event) = @_;

        my $keyval = Gtk3::Gdk::keyval_name($event->keyval);
        my $unicode = Gtk3::Gdk::keyval_to_unicode($event->keyval); # 0 if not a character
        my $state = $event->get_state;
        my $ctrl = $state * ['control-mask'];
        my $shift = $state * ['shift-mask'];
        my $alt = $state * ['mod1-mask'];

        #print "TABBED WINDOW KEYPRESS:*$state*$keyval*" . chr($keyval) . "*$unicode*\n";

        # Get current page's tab number
        my $curr_page = $$self{_GUI}{nb}->get_current_page();

        # Continue checking keypress only if <Ctrl> is pushed
        if ($ctrl && $shift && (! $$self{_CFG}{'defaults'}{'disable CTRL key bindings'}) && (! $$self{_CFG}{'defaults'}{'disable SHIFT key bindings'})) {
            if ($keyval !~ /^.*_?Tab/go) {
                return 0;
            }

            if ($$self{_CFG}{defaults}{'ctrl tab'} eq 'last') {
                $$self{_GUI}{nb}->set_current_page($$self{_PREVTAB});
            } else {
                if ($curr_page == 0) {
                    $$self{_GUI}{nb}->set_current_page($$self{_GUI}{nb}->get_n_pages - 1);
                } else {
                    $$self{_GUI}{nb}->prev_page();
                }
            }
            return 1;
        }
        # Continue checking keypress only if <Ctrl> is pushed
        elsif ($ctrl && (! $$self{_CFG}{'defaults'}{'disable CTRL key bindings'})) {
            # Capture <Ctrl>PgUp/Left --> select previous tab
            if ($keyval eq 'Page_Up' && ! $$self{_CFG}{'defaults'}{'how to switch tabs'}) {
                if ($curr_page == 0) {
                    $$self{_GUI}{nb}->set_current_page(-1);
                } else {
                    $$self{_GUI}{nb}->prev_page();
                }
            }
            # Capture <Ctrl>PgDwn/Right --> select next tab
            elsif ($keyval eq 'Page_Down' && ! $$self{_CFG}{'defaults'}{'how to switch tabs'}) {
                if ($curr_page == $$self{_GUI}{nb}->get_n_pages - 1) {
                    $$self{_GUI}{nb}->set_current_page(0);
                } else {
                    $$self{_GUI}{nb}->next_page();
                }
            }
            # Capture <Ctrl>number --> select number tab
            elsif ($keyval =~ /^\d$/go) {
                $$self{_GUI}{nb}->set_current_page($keyval - ($$self{_CFG}{'defaults'}{'tabs in main window'} ? 0 : 1));
            }
            # Capture <Ctrl>TAB --> switch between tabs
            elsif ($keyval eq 'Tab') {
                if ($$self{_CFG}{defaults}{'ctrl tab'} eq 'last') {
                    $$self{_GUI}{nb}->set_current_page($$self{_PREVTAB});
                } else {
                    if ($curr_page == $$self{_GUI}{nb}->get_n_pages - 1) {
                        $$self{_GUI}{nb}->set_current_page(0);
                    } else {
                        $$self{_GUI}{nb}->next_page();
                    }
                }
            } else {
                return 0;
            }
            return 1;
        # Continue checking keypress only if <Alt> is pushed
        } elsif ($alt && (! $$self{_CFG}{'defaults'}{'disable ALT key bindings'}) && $$self{_CFG}{'defaults'}{'how to switch tabs'}) {
            # Capture <Alt>PgUp/Left --> select previous tab
            if ($keyval eq 'Left') {
                if ($curr_page == 0) {
                    $$self{_GUI}{nb}->set_current_page(-1);
                } else {
                    $$self{_GUI}{nb}->prev_page();
                }
            }
            # Capture <Alt>PgDwn/Right --> select next tab
            elsif ($keyval eq 'Right') {
                if ($curr_page == $$self{_GUI}{nb}->get_n_pages - 1) {
                    $$self{_GUI}{nb}->set_current_page(0);
                } else {
                    $$self{_GUI}{nb}->next_page();
                }
            } else {
                return 0;
            }
            return 1;
        }
        return 0;
    });

    # Capture some keypress on Description widget
    $$self{_GUI}{descView}->signal_connect('key_press_event' => sub {
        my ($widget, $event) = @_;
        my $keyval = '' . ($event->keyval);
        my $state = '' . ($event->state);

        # Check if <Ctrl>z is pushed
        if (($event->state == [ qw(control-mask) ]) && (chr($keyval) eq 'z') && (scalar @{ $$self{_UNDO} })) {
            $$self{_GUI}{descBuffer}->set_text(pop(@{ $$self{_UNDO} }));
            return 1;
        }
        return 0;
    });

    # Capture text changes on Description widget
    $$self{_GUI}{descBuffer}->signal_connect('begin_user_action' => sub {
        $self->_setCFGChanged(1);
        push(@{ $$self{_UNDO} }, $$self{_GUI}{descBuffer}->get_property('text'));
        return 0;
    });
    $$self{_GUI}{descBuffer}->signal_connect('changed' => sub {
        my @sel = $$self{_GUI}{treeConnections}->_getSelectedUUIDs();
        if (!(scalar(@sel) == 1 && $$self{_GUI}{nbTree}->get_current_page() == 0 && $$self{_GUI}{descView}->is_sensitive)) {
            return 0;
        }
        $$self{_CFG}{environments}{$sel[0]}{description} = $$self{_GUI}{descBuffer}->get_property('text');
        return 0;
    });

    # Capture TAB page switching
    $$self{_GUI}{nb}->signal_connect('switch_page' => sub {
        my ($nb, $p, $pnum) = @_;

        $$self{_PREVTAB} = $nb->get_current_page();

        my $tab_page = $nb->get_nth_page($pnum);

        $$self{_HAS_FOCUS} = '';
        foreach my $tmp_uuid (keys %RUNNING) {
            my $check_gui = $RUNNING{$tmp_uuid}{terminal}{_SPLIT} ? $RUNNING{$tmp_uuid}{terminal}{_SPLIT_VPANE} : $RUNNING{$tmp_uuid}{terminal}{_GUI}{_VBOX};

            if ((!defined $check_gui) || ($check_gui ne $tab_page)) {
                next;
            }

            my $uuid = $RUNNING{$tmp_uuid}{uuid};
            my $path = $$self{_GUI}{treeConnections}->_getPath($uuid);
            if ($path) {
                $$self{_GUI}{treeConnections}->expand_to_path($path);
                $$self{_GUI}{treeConnections}->set_cursor($path, undef, 0);
            }

            $RUNNING{$tmp_uuid}{terminal}->_setTabColour();

            if (!$RUNNING{$tmp_uuid}{terminal}{EMBED}) {
                eval {
                    if (defined $RUNNING{$tmp_uuid}{terminal}{FOCUS}->get_window()) {
                        $RUNNING{$tmp_uuid}{terminal}{FOCUS}->get_window()->focus(time);
                    }
                };
                $RUNNING{$tmp_uuid}{terminal}{_GUI}{_VTE}->grab_focus();
            }
            $$self{_HAS_FOCUS} = $RUNNING{$tmp_uuid}{terminal}{_GUI}{_VTE};
            last;
        }
        $$self{_GUI}{hbuttonbox1}->set_visible(($pnum == 0) || ($pnum && ! $$self{'_CFG'}{'defaults'}{'auto hide button bar'}));
        if (($pnum == 0)&&($$self{_CFG}{'defaults'}{'auto hide connections list'})) {
            # Info Tab, show connection list
            $$self{_GUI}{showConnBtn}->set_active(1);
        } elsif (($$self{_CFG}{'defaults'}{'auto hide connections list'})&&($$self{_GUI}{showConnBtn}->get_active())) {
            $$self{_GUI}{showConnBtn}->set_active(0);
        }
        return 1;
    });

    # Capture window closing
    $$self{_GUI}{main}->signal_connect('delete_event' => sub {
        if ($$self{_CFG}{defaults}{'close to tray'}) {
            # Show tray icon
            if ($UNITY) {
                $$self{_TRAY}{_TRAY}->set_active();
            } else {
                $$self{_TRAY}{_TRAY}->set_visible(1);
            }
            # Trigger the "lock" procedure ?
            if ($$self{_CFG}{'defaults'}{'use gui password'} && $$self{_CFG}{'defaults'}{'use gui password tray'}) {
                $$self{_GUI}{lockPACBtn}->set_active(1);
            }
            # Hide main window
            if ($ENV{'ASBRU_DESKTOP'} eq 'gnome-shell') {
                $$self{_GUI}{main}->iconify();
            } else {
                $self->_hideConnectionsList();
            }
        } else {
            $self->_quitProgram();
        }
        return 1;
    });
    $$self{_GUI}{main}->signal_connect('destroy' => sub { exit 0; });

    # Save GUI size/position/... *before* it hides
    $$self{_GUI}{main}->signal_connect('unmap_event' => sub { $self->_saveGUIData; return 0; });

    $$self{_GUI}{_vboxSearch}->signal_connect('map' => sub { $$self{_GUI}{_vboxSearch}->hide() unless $$self{_SHOWFINDTREE}; });

    # Capture 'treeconnections' keypress
    $$self{_GUI}{main}->signal_connect('key_press_event' => sub {
        my ($widget, $event) = @_;

        my $keyval = Gtk3::Gdk::keyval_name($event->keyval);
        my $unicode = Gtk3::Gdk::keyval_to_unicode($event->keyval); # 0 if not a character
        my $state = $event->get_state;
        my $shift = $state * ['shift-mask'];
        my $ctrl = $state * ['control-mask'];
        my $alt = $state * ['mod1-mask'];
        my $alt2 = $state * ['mod2-mask'];
        my $alt5 = $state * ['mod5-mask'];

        #print "TERMINAL KEYPRESS:*$state*$keyval*" . chr($keyval) . "*$unicode*\n";
        #print "*$shift*$ctrl*$alt*$alt2*$alt5*\n";

        # <Ctrl><Shift>
        if (!(($ctrl && $shift) && (! $$self{_CFG}{'defaults'}{'disable CTRL key bindings'})  && (! $$self{_CFG}{'defaults'}{'disable SHIFT key bindings'}))) {
            return 0;
        }

        # F --> FIND in treeView
        if($_[1]->keyval == 102)  {
            $$self{_SHOWFINDTREE} = 1;
            $$self{_GUI}{_vboxSearch}->show;
            $$self{_GUI}{_entrySearch}->grab_focus();
            return 1;
        }
        # Q --> Finish
        elsif ($_[1]->keyval == 113) {
            $PACMain::FUNCS{_MAIN}->_quitProgram();
            return 1;
        }
        # T --> Open local shell
        elsif (lc $keyval eq 't') {
            $$self{_GUI}{shellBtn}->clicked();
            return 1;
        }
        return 0;
    });
    $$self{_SIGNALS}{_WINDOWSTATEVENT} = $$self{_GUI}{main}->signal_connect('window_state_event' => sub {
        $$self{_GUI}{maximized} = $_[1]->new_window_state eq 'maximized';
        return 0;
    });
    return 1;
}

sub _lockPAC {
    my $self = shift;

    $$self{_GUI}{lockPACBtn}->set_image(Gtk3::Image->new_from_stock('pac-protected', 'GTK_ICON_SIZE_BUTTON'));
    $$self{_GUI}{lockPACBtn}->set_active(1);
    $$self{_GUI}{vbox3}->set_sensitive(0);
    $$self{_GUI}{showConnBtn}->set_sensitive(0);
    $$self{_GUI}{shellBtn}->set_sensitive(0);
    $$self{_GUI}{quitBtn}->set_sensitive(0);
    $$self{_GUI}{saveBtn}->set_sensitive(0);
    $$self{_GUI}{configBtn}->set_sensitive(0);
    $$self{_GUI}{aboutBtn}->set_sensitive(0);
    $$self{_GUI}{wolBtn}->set_sensitive(0);

    if ($$self{_TABSINWINDOW}){
        $$self{_GUI}{_PACTABS}->set_sensitive(0);
    }
    foreach my $tmp_uuid (keys %RUNNING) {
        $RUNNING{$tmp_uuid}{terminal}->lock;
    }
    $$self{_GUILOCKED} = 1;

    return 1;
}

sub _unlockPAC {
    my $self = shift;

    my $pass = _wEnterValue($self, 'GUI Unlock', 'Enter current GUI Password to remove protection...', undef, 0, 'pac-protected');
    if ((! defined $pass) || ($CIPHER->encrypt_hex($pass) ne $$self{_CFG}{'defaults'}{'gui password'})) {
        $$self{_GUI}{lockPACBtn}->set_active(1);
        _wMessage($$self{_WINDOWCONFIG}, 'ERROR: Wrong password!!');
        return 0;
    }

    $$self{_GUI}{lockPACBtn}->set_image(Gtk3::Image->new_from_stock('pac-unprotected', 'GTK_ICON_SIZE_BUTTON'));
    $$self{_GUI}{lockPACBtn}->set_active(0);
    $$self{_GUI}{vbox3}->set_sensitive(1);
    $$self{_GUI}{showConnBtn}->set_sensitive(1);
    $$self{_GUI}{shellBtn}->set_sensitive(1);
    $$self{_GUI}{quitBtn}->set_sensitive(1);
    $$self{_GUI}{saveBtn}->set_sensitive(1);
    $$self{_GUI}{configBtn}->set_sensitive(1);
    $$self{_GUI}{aboutBtn}->set_sensitive(1);
    $$self{_GUI}{wolBtn}->set_sensitive(1);

    $$self{_TABSINWINDOW} and $$self{_GUI}{_PACTABS}->set_sensitive(1);
    foreach my $tmp_uuid (keys %RUNNING) {
        $RUNNING{$tmp_uuid}{terminal}->unlock;
    }
    $$self{_GUILOCKED} = 0;

    return 1;
}

sub __search {
    my $self = shift;
    my $text = shift;
    my $tree = shift;
    my $where = shift // 'name';

    my @result;
    my $model = $tree->get_model;
    $model->foreach(sub {
        my ($store, $path, $iter) = @_;
        my $elem_uuid = $model->get_value($model->get_iter($path), 2);
        my %elem;
        $elem{name} = $$self{_CFG}{environments}{$elem_uuid}{name} // '';
        $elem{host} = $$self{_CFG}{environments}{$elem_uuid}{ip} // '';
        $elem{desc} = $$self{_CFG}{environments}{$elem_uuid}{description} // '';
        if ($elem{$where} !~ /$text/gi) {
            return 0;
        }
        push(@result, $elem_uuid);
        return 0;
    });
    return \@result;
}

sub __treeSort {
    my ($treestore, $a_iter, $b_iter, $cfg) = @_;

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
        my $a_is_group = $$cfg{'environments'}{ $a_uuid }{'_is_group'};
        my $b_is_group = $$cfg{'environments'}{ $b_uuid }{'_is_group'};
        if ($a_is_group && ! $b_is_group){
            return -1;
        }
        if (! $a_is_group && $b_is_group){
            return 1;
        }
    }
    # ... then alphabetically
    return lc($$cfg{'environments'}{$a_uuid}{name}) cmp lc($$cfg{'environments'}{$b_uuid}{name});
}

sub __treeBuildNodeName {
    my $self = shift;
    my $uuid = shift;
    my $name = shift;
    my $bold = '';
    my $pset = '';

    my $is_group = $$self{_CFG}{'environments'}{$uuid}{'_is_group'} // 0;
    my $protected = ($$self{_CFG}{'environments'}{$uuid}{'_protected'} // 0) || 0;
    my $p_set = $$self{_CFG}{defaults}{'protected set'};
    my $p_color = $$self{_CFG}{defaults}{'protected color'};

    if ($name) {
        $name = __($name);
    } else {
        $name = __($$self{_CFG}{'environments'}{$uuid}{'name'});
    }
    if ($is_group) {
        $bold = " weight='bold'";
    }
    if ($protected) {
        $pset = "$p_set='$p_color'";
    }
    $name = "<span $pset$bold font='$$self{_CFG}{defaults}{'tree font'}'>$name</span>";

    return $name;
}

sub _hasProtectedChildren {
    my $self = shift;
    my $uuids = shift;
    my $search_children = shift // 1;

    my $with_protected = 0;

    foreach my $uuid (@{ $uuids }) {
        if ($$self{_CFG}{'environments'}{$uuid}{'_is_group'}) {
            if (!$search_children) {
                next;
            }
            foreach my $child ($$self{_GUI}{treeConnections}->_getChildren($uuid, 'all', 1)) {
                if ($with_protected = ($$self{_CFG}{'environments'}{$child}{'_protected'} // 0) || 0) {
                    last;
                }
            }
        } elsif ($with_protected = ($$self{_CFG}{'environments'}{$uuid}{'_protected'} // 0) || 0) {
            last;
        }
    }

    return $with_protected;
}

sub __treeToggleProtection {
    my $self = shift;

    my $selection = $$self{_GUI}{treeConnections}->get_selection;
    my $modelsort = $$self{_GUI}{treeConnections}->get_model;
    my $model = $modelsort->get_model;
    my @sel = $$self{_GUI}{treeConnections}->_getSelectedUUIDs();

    foreach my $uuid (@sel) {
        $$self{_CFG}{'environments'}{$uuid}{'_protected'} = !$$self{_CFG}{'environments'}{$uuid}{'_protected'};
        my $gui_name = $self->__treeBuildNodeName($uuid);
        $model->set($modelsort->convert_iter_to_child_iter($modelsort->get_iter($$self{_GUI}{treeConnections}->_getPath($uuid))), 1, $gui_name);
    }
    $self->_setCFGChanged(1);
}

sub _treeConnections_menu_lite {
    my $self = shift;
    my $tree = shift;

    my @sel = $tree->_getSelectedUUIDs();

    if (scalar(@sel) == 0) {
        return 1;
    }

    my $with_protected = $self->_hasProtectedChildren(\@sel);
    my @tree_menu_items;

    # Edit
    if (scalar(@sel) == 1) {
        push(@tree_menu_items, {
            label => 'Edit connection',
            stockicon => 'gtk-edit',
            shortcut => '<alt>e',
            tooltip => "Edit this connection\'s data",
            sensitive => $sel[0] ne '__PAC_SHELL__',
            code => sub { $$self{_GUI}{connEditBtn}->clicked(); }
        });
    }
    # Bulk Edit
    elsif (scalar(@sel) > 1) {
        push(@tree_menu_items, {
            label => 'Bulk Edit connections...',
            stockicon => 'gtk-edit',
            shortcut => '<alt>e',
            tooltip => "Bulk edit some values of selected connection\'s",
            sensitive => 1,
            code => sub { $$self{_GUI}{connEditBtn}->clicked(); }
        });
    }

    # Quick Edit variables
    my @var_submenu;
    my $i = 0;
    foreach my $var (map{ $_->{txt} // '' } @{ $$self{_CFG}{'environments'}{$sel[0]}{'variables'} }) {
        my $j = $i;
        push(@var_submenu, {
            label => '<V:' . $j . '> = ' . $var,
            code => sub {
                my $new_var = _wEnterValue(
                    $$self{_GUI}{main},
                    "Change variable <b>" . __("<V:$j>") . "</b>",
                    'Enter a NEW value or close to keep this value...',
                    $var
                );
                if (!defined $new_var) {
                    return 1;
                }
                $$self{_CFG}{'environments'}{$sel[0]}{'variables'}[$j]{txt} = $new_var;
            }
        });

        ++$i;
    }
    if (scalar(@sel) == 1) {
        push(@tree_menu_items, {
            label => 'Edit Local Variables',
            stockicon => 'gtk-dialog-question',
            sensitive => ! $with_protected,
            submenu => \@var_submenu
        });
    }

    # Send Wake On LAN magic packet
    if ($sel[0] ne '__PAC_SHELL__') {
        push(@tree_menu_items, {
            label => 'Wake On LAN...' . ($$self{_CFG}{'environments'}{$sel[0]}{'use proxy'} || $$self{_CFG}{'defaults'}{'use proxy'} ? '(can\'t, PROXY configured!!)' : ''),
            stockicon => 'pac-wol',
            sensitive => ! ($$self{_CFG}{'environments'}{$sel[0]}{'use proxy'} || $$self{_CFG}{'defaults'}{'use proxy'}) && (scalar(@sel) >= 1) && (scalar(@sel) == 1) && (! ($$self{_CFG}{'environments'}{$sel[0]}{'_is_group'} || $sel[0] eq '__PAC__ROOT__')),
            code => sub { $self->_setCFGChanged(_wakeOnLan($$self{_CFG}{'environments'}{$sel[0]}, $sel[0])); }
        });
    }

    # Start various instances of this connection
    my @submenu_nconns;
    foreach my $i (2 .. 9) {
        push(@submenu_nconns, {
            label => "$i instances",
            code => sub {
                my @idx;
                foreach my $uuid (@sel) {
                    foreach my $j (1 .. $i) {
                        push(@idx, [ $uuid ]);
                    }
                }
                $self->_launchTerminals(\@idx);
            }
        });
    }
    if (scalar(@sel) == 1) {
        push(@tree_menu_items, {

            label => 'Start',
            stockicon => 'gtk-execute',
            sensitive => (scalar(@sel) == 1) && ! ($$self{_CFG}{'environments'}{$sel[0]}{'_is_group'} || $sel[0] eq '__PAC__ROOT__'),
            submenu => \@submenu_nconns
        });
    }

    push(@tree_menu_items, { separator => 1 });

    # Execute clustered
    push(@tree_menu_items, {
        label => 'Execute in New Cluster...',
        stockicon => 'gtk-new',
        shortcut => '',
        sensitive => scalar @sel >= 1,
        code => sub {
            my $cluster = _wEnterValue($self, 'Enter a name for the <b>New Cluster</b>');
            if ((!defined $cluster) || ($cluster =~ /^\s*$/go)){
                return 1;
            }
            my @idx;
            my %tmp;
            foreach my $uuid ($tree->_getSelectedUUIDs()) {
                $tmp{$uuid} = 1;
            }
            foreach my $uuid (keys %tmp) {
                push(@idx, [ $uuid, undef, $cluster ]);
            }
            $self->_launchTerminals(\@idx);
        }
    });

    my @submenu_cluster;
    my %clusters;
    foreach my $uuid_tmp (keys %RUNNING) {
        if ($RUNNING{$uuid_tmp}{terminal}{_CLUSTER} eq '') {
            next;
        }
        $clusters{$RUNNING{$uuid_tmp}{terminal}{_CLUSTER}}{total}++;
        $clusters{$RUNNING{$uuid_tmp}{terminal}{_CLUSTER}}{connections} .= "$RUNNING{$uuid_tmp}{terminal}{_NAME}\n";
    }
    foreach my $cluster (sort { $a cmp $b } keys %clusters) {
        my $tmp = $cluster;
        push(@submenu_cluster, {
            label => "$cluster ($clusters{$cluster}{total} terminals connected)",
            tooltip => $clusters{$cluster}{connections},
            sensitive => $cluster ne $$self{_CLUSTER},
            code => sub {
                my @idx;
                my %tmp;
                foreach my $uuid ($tree->_getSelectedUUIDs()) {
                    $tmp{$uuid} = 1;
                }
                foreach my $uuid (keys %tmp) {
                    push(@idx, [ $uuid, undef, $cluster ]);
                }
                $self->_launchTerminals(\@idx);
            }
        });
    }
    if (scalar(keys(%clusters))) {
        push(@tree_menu_items, {
            label => 'Execute in existing Cluster',
            stockicon => 'gtk-add',
            submenu => \@submenu_cluster
        });
    }

    _wPopUpMenu(\@tree_menu_items);

    return 1;
}

sub _treeConnections_menu {
    my $self = shift;
    my $event = shift;
    my $p = '';
    my $clip = scalar (keys %{$$self{_COPY}{'data'}{'__PAC__COPY__'}{'children'}});

    my @sel = $$self{_GUI}{treeConnections}->_getSelectedUUIDs();
    if (scalar(@sel) == 0) {
        return 1;
    } elsif ((scalar(@sel)>1)||($clip > 1)) {
        $p = 's';
    }
    my $with_protected = $self->_hasProtectedChildren(\@sel);
    my $with_groups = 0;
    foreach my $uuid (@sel) {
        if ($with_groups = $$self{_CFG}{'environments'}{ $uuid }{'_is_group'}) {
            last;
        }
    }

    my @tree_menu_items;
    # Expand All
    push(@tree_menu_items, {
        label => 'Expand all',
        stockicon => 'gtk-add',
        shortcut => '<ctrl>r',
        tooltip => 'Expand ALL (including sub-nodes)',
        sensitive => 1,
        code => sub { $$self{_GUI}{treeConnections}->expand_all; }
    });
    # Collapse All
    push(@tree_menu_items, {
        label => 'Collapse all',
        stockicon => 'gtk-remove',
        shortcut => '<ctrl>t',
        tooltip => 'Collapse ALL (including sub-nodes)',
        sensitive => 1,
        code => sub { $$self{_GUI}{treeConnections}->collapse_all; }
    });
    push(@tree_menu_items, { separator => 1 });
    # Toggle Protect
    if (scalar(@sel) >= 1 && $sel[0] ne '__PAC__ROOT__') {
        push(@tree_menu_items, {
            label => scalar(@sel) > 1 ? ('Toggle Protected state') : (($$self{_CFG}{'environments'}{ $sel[0] }{'_protected'} ? 'Un-' : '') . 'Protect'),
            stockicon => 'pac-' . ($$self{_CFG}{'environments'}{ $sel[0] }{'_protected'} ? 'un' : '') . 'protected',
            shortcut => '<alt>r',
            tooltip => "Protect or not this node, in order to avoid any changes (Edit, Delete, Rename, ...)",
            sensitive => 1,
            code => sub { $self->__treeToggleProtection(); }
        });
    }
    # Edit
    if (scalar(@sel) == 1 && (! $$self{_CFG}{'environments'}{$sel[0]}{'_is_group'}) && $sel[0] ne '__PAC__ROOT__') {
        push(@tree_menu_items, {
            label => "Edit connection$p",
            stockicon => 'gtk-edit',
            shortcut => '<alt>e',
            tooltip => "Edit this connection\'s data",
            sensitive => 1,
            code => sub { $$self{_GUI}{connEditBtn}->clicked(); }
        });
    }
    # Copy Connection Password
    if ((defined($$self{_CFG}{environments}{$sel[0]}{'pass'}) && $$self{_CFG}{environments}{$sel[0]}{'pass'} ne '') || (defined($$self{_CFG}{environments}{$sel[0]}{'passphrase'}) && $$self{_CFG}{environments}{$sel[0]}{'passphrase'} ne '')) {
        push(@tree_menu_items, {
            label => 'Copy Password',
            stockicon => 'gtk-copy',
            shortcut => '',
            sensitive => 1,
            code => sub {
                _copyPASS($sel[0]);
            }
        });
    }
    # Bulk Edit
    if ((scalar(@sel) > 1 || $$self{_CFG}{'environments'}{$sel[0]}{'_is_group'}) && $sel[0] ne '__PAC__ROOT__') {
        push(@tree_menu_items, {
            label => 'Bulk Edit connections...',
            stockicon => 'gtk-edit',
            shortcut => '<alt>e',
            tooltip => "Bulk edit some values of selected connection\'s",
            sensitive => 1,
            code => sub { $$self{_GUI}{connEditBtn}->clicked(); }
        });
    }
    # Export
    push(@tree_menu_items, {
        label => 'Export ' . ($sel[0] eq '__PAC__ROOT__' ? 'ALL' : 'SELECTED') . ' connection(s)...',
        stockicon => 'gtk-save-as',
        shortcut => '',
        tooltip => 'Export connection(s) to a YAML file',
        sensitive =>  scalar @sel >= 1,
        code => sub {
            if ($sel[0] eq '__PAC__ROOT__') {
                $$self{_GUI}{treeConnections}->get_selection->unselect_path(Gtk3::TreePath->new_from_string('0'));
                for my $i (1 .. 65535) {
                    $$self{_GUI}{treeConnections}->get_selection->select_path(Gtk3::TreePath->new_from_string("$i"));
                }
                $self->__exportNodes;
                for my $i (1 .. 65535) {
                    $$self{_GUI}{treeConnections}->get_selection->unselect_path(Gtk3::TreePath->new_from_string("$i"));
                }
                $$self{_GUI}{treeConnections}->set_cursor(Gtk3::TreePath->new_from_string('0'), undef, 0);
            } else {
                $self->__exportNodes;
            }
        }
    });
    # Import
    push(@tree_menu_items, {
        label => 'Import connection(s)...',
        stockicon => 'gtk-open',
        shortcut => '',
        tooltip => 'Import connection(s) from a file',
        sensitive =>  (scalar(@sel) == 1) && ($$self{_CFG}{'environments'}{$sel[0]}{'_is_group'} || $sel[0] eq '__PAC__ROOT__'),
        code => sub { $self->__importNodes }
    });
    if ($ENV{'ASBRU_DESKTOP'} eq 'gnome-shell') {
        # Display settings options in gnome-shell, there is no tray icon to access it
        push(@tree_menu_items, {
            label => 'Settings...',
            stockicon => 'gtk-preferences',
            shortcut => '',
            tooltip => 'Settings',
            sensitive =>  1,
            code => sub { $$self{_GUI}{configBtn}->clicked(); }
        });
    }
    # Quick Edit variables
    my @var_submenu;
    my $i = 0;
    foreach my $var (map{ $_->{txt} // '' } @{ $$self{_CFG}{'environments'}{$sel[0]}{'variables'} }) {
        my $j = $i;
        push(@var_submenu, {
            label => '<V:' . $j . '> = ' . $var,
            code => sub {
                my $new_var = _wEnterValue(
                    $$self{_GUI}{main},
                    "Change variable <b>" . __("<V:$j>") . "</b>",
                    'Enter a NEW value or close to keep this value...',
                    $var
                );
                if (!defined $new_var) {
                    return 1;
                }
                $$self{_CFG}{'environments'}{$sel[0]}{'variables'}[$j]{txt} = $new_var;
            }
        });
        ++$i;
    }
    if ((scalar(@sel) == 1) && !($$self{_CFG}{'environments'}{$sel[0]}{'_is_group'} || $sel[0] eq '__PAC__ROOT__')) {
        push(@tree_menu_items, {
            label => 'Edit Local Variables',
            stockicon => 'gtk-dialog-question',
            sensitive => ! $with_protected,
            submenu => \@var_submenu
        });
    }

    push(@tree_menu_items, { separator => 1 });
    # Add connection/group
    if ((scalar @sel == 1) && ($$self{_CFG}{'environments'}{$sel[0]}{'_is_group'} || $sel[0] eq '__PAC__ROOT__')) {
        # Add Connection
        push(@tree_menu_items, {
            label => 'Add Connection',
            stockicon => 'pac-node-add',
            tooltip => "Create a new CONNECTION under '" . ($sel[0] eq '__PAC__ROOT__' ? 'ROOT' : $$self{_CFG}{'environments'}{$sel[0]}{'name'}) . "'",
            code => sub{ $$self{_GUI}{connAddBtn}->clicked(); }
        });
        # Add Group
        push(@tree_menu_items, {
            label => 'Add Group',
            stockicon => 'pac-group-add',
            tooltip => "Create a new GROUP under '" . ($sel[0] eq '__PAC__ROOT__' ? 'ROOT' : $$self{_CFG}{'environments'}{$sel[0]}{'name'}) . "'",
            code => sub{ $$self{_GUI}{groupAddBtn}->clicked(); }
        });
    }
    # Rename
    push(@tree_menu_items, {
        label => 'Rename ' . ($$self{_CFG}{'environments'}{$sel[0]}{'_is_group'} || $sel[0] eq '__PAC__ROOT__' ? 'Group' : 'Connection'),
        stockicon => 'gtk-spell-check',
        shortcut => 'F2',
        sensitive => (scalar(@sel) == 1) && $sel[0] ne '__PAC__ROOT__' && ! $with_protected,
        code => sub { $$self{_GUI}{nodeRenBtn}->clicked(); }
    });
    # Delete
    push(@tree_menu_items, {
        label => 'Delete...',
        stockicon => 'gtk-delete',
        sensitive => (scalar(@sel) >= 1) && $sel[0] ne '__PAC__ROOT__' && ! $with_protected,
        code => sub { $$self{_GUI}{nodeDelBtn}->clicked(); }
    });

    push(@tree_menu_items, { separator => 1 });
    # Clone connection
    push(@tree_menu_items, {
        label => "Clone connection$p",
        stockicon => 'gtk-copy',
        shortcut => '<control>d',
        sensitive => ((scalar(@sel) == 1) && ! ($$self{_CFG}{'environments'}{$sel[0]}{'_is_group'} || $sel[0] eq '__PAC__ROOT__')),
        code => sub {
            $self->_copyNodes;
            foreach my $child (keys %{ $$self{_COPY}{'data'}{'__PAC__COPY__'}{'children'} }) {
                $self->_pasteNodes($$self{_CFG}{'environments'}{ $sel[0] }{'parent'}, $child);
            }
            $$self{_COPY}{'data'} = {};
        }
    });
    # Copy
    push(@tree_menu_items, {
        label => "Copy node$p",
        stockicon => 'gtk-copy',
        shortcut => '<control>c',
        sensitive => ((scalar @sel >= 1) && ($sel[0] ne '__PAC__ROOT__')),
        code => sub{
            $self->_copyNodes;
            # Unselect nodes after copy
            $$self{_GUI}{treeConnections}->get_selection()->unselect_all();
        }
    });
    # Cut
    push(@tree_menu_items, {
        label => "Cut node$p",
        stockicon => 'gtk-cut',
        shortcut => '<control>x',
        sensitive => ((scalar @sel >= 1) && ($sel[0] ne '__PAC__ROOT__') && (! $with_protected)),
        code => sub{  $self->_cutNodes; }
    });
    push(@tree_menu_items, {
        label => "Paste node$p",
        stockicon => 'gtk-paste',
        shortcut => '<control>v',
        #sensitive => scalar(keys %{ $$self{_COPY}{'data'} }) && (scalar @sel == 1) && (($sel[0] eq '__PAC__ROOT__') || ($$self{_CFG}{'environments'}{$sel[0]}{'_is_group'})),
        sensitive => (($clip)&&(scalar @sel == 1)) ? 1 : 0,
        code => sub {
            foreach my $child (keys %{ $$self{_COPY}{'data'}{'__PAC__COPY__'}{'children'} }) {
                $self->_pasteNodes($sel[0], $child);
            }
            $$self{_COPY}{'data'} = {};
            return 1;
        }
    });

    push(@tree_menu_items, { separator => 1 });

    # Send Wake On LAN magic packet
    push(@tree_menu_items, {

        label => 'Wake On LAN...' . ($$self{_CFG}{'environments'}{$sel[0]}{'use proxy'} || $$self{_CFG}{'defaults'}{'use proxy'} ? '(can\'t, PROXY configured!!)' : ''),
        stockicon => 'pac-wol',
        sensitive => ! ($$self{_CFG}{'environments'}{$sel[0]}{'use proxy'} || $$self{_CFG}{'defaults'}{'use proxy'}) && (scalar(@sel) >= 1) && (scalar(@sel) == 1) && (! ($$self{_CFG}{'environments'}{$sel[0]}{'_is_group'} || $sel[0] eq '__PAC__ROOT__')),
        code => sub { $self->_setCFGChanged(_wakeOnLan($$self{_CFG}{'environments'}{$sel[0]}, $sel[0])); }
    });

    # Start various instances of this connection
    my @submenu_nconns;
    foreach my $i (2 .. 9) {
        push(@submenu_nconns, {
            label => "$i instances",
            code => sub {
                my @idx;
                foreach my $uuid (@sel) {
                    foreach my $j (1 .. $i) {
                        push(@idx, [ $uuid ]);
                    }
                }
                $self->_launchTerminals(\@idx);
            }
        });
    }
    if ((scalar(@sel) == 1) && ! ($$self{_CFG}{'environments'}{$sel[0]}{'_is_group'} || $sel[0] eq '__PAC__ROOT__')) {
        push(@tree_menu_items, {
            label => 'Start',
            stockicon => 'gtk-execute',
            sensitive => (scalar(@sel) == 1) && ! ($$self{_CFG}{'environments'}{$sel[0]}{'_is_group'} || $sel[0] eq '__PAC__ROOT__'),
            submenu => \@submenu_nconns
        });
    }

    push(@tree_menu_items, { separator => 1 });
    # Execute clustered
    push(@tree_menu_items, {
        label => 'Execute in New Cluster...',
        stockicon => 'gtk-new',
        shortcut => '',
        sensitive => ((scalar @sel >= 1) && ($sel[0] ne '__PAC__ROOT__')),
        code => sub {
            my $cluster = _wEnterValue($self, 'Enter a name for the <b>New Cluster</b>');
            if ((! defined $cluster) || ($cluster =~ /^\s*$/go)) {
                return 1;
            }
            my @idx;
            my %tmp;
            foreach my $uuid ($$self{_GUI}{treeConnections}->_getSelectedUUIDs()) {
                if (($$self{_CFG}{'environments'}{$uuid}{'_is_group'}) || ($uuid eq '__PAC__ROOT__')) {
                    my @children = $$self{_GUI}{treeConnections}->_getChildren($uuid, 0, 1);
                    foreach my $child (@children) {
                        $tmp{$child} = 1;
                    }
                } else {
                    $tmp{$uuid} = 1;
                }
            }
            foreach my $uuid (keys %tmp) {
                push(@idx, [ $uuid, undef, $cluster ]);
            }
            $self->_launchTerminals(\@idx);
        }
    });

    my @submenu_cluster;
    my %clusters;
    foreach my $uuid_tmp (keys %RUNNING) {
        if ($RUNNING{$uuid_tmp}{terminal}{_CLUSTER} eq '') {
            next;
        }
        $clusters{$RUNNING{$uuid_tmp}{terminal}{_CLUSTER}}{total}++;
        $clusters{$RUNNING{$uuid_tmp}{terminal}{_CLUSTER}}{connections} .= "$RUNNING{$uuid_tmp}{terminal}{_NAME}\n";
    }
    foreach my $cluster (sort { $a cmp $b } keys %clusters) {
        my $tmp = $cluster;
        push(@submenu_cluster, {
            label => "$cluster ($clusters{$cluster}{total} terminals connected)",
            tooltip => $clusters{$cluster}{connections},
            sensitive => $cluster ne $$self{_CLUSTER},
            code => sub {
                my @idx;
                my %tmp;
                foreach my $uuid ($$self{_GUI}{treeConnections}->_getSelectedUUIDs()) {
                    if (($$self{_CFG}{'environments'}{$uuid}{'_is_group'}) || ($uuid eq '__PAC__ROOT__')) {
                        my @children = $$self{_GUI}{treeConnections}->_getChildren($uuid, 0, 1);
                        foreach my $child (@children) {
                            $tmp{$child} = 1;
                        }
                    } else {
                        $tmp{$uuid} = 1;
                    }
                }
                foreach my $uuid (keys %tmp) {
                    push(@idx, [ $uuid, undef, $cluster ]);
                }
                $self->_launchTerminals(\@idx);
            }
        });
    }
    if (scalar(keys(%clusters))) {
        push(@tree_menu_items, {
            label => 'Execute in existing Cluster',
            stockicon => 'gtk-add',
            submenu => \@submenu_cluster
        });
    }
    _wPopUpMenu(\@tree_menu_items, $event);

    return 1;
}

sub _showAboutWindow {
    my $self = shift;

    Gtk3::show_about_dialog(
        $$self{_GUI}{main},(
        "program_name" => '',  # name is shown in the logo
        "version" => "v$APPVERSION",
        "logo" => _pixBufFromFile("$RES_DIR/asbru-logo-400.png"),
        "copyright" => "Copyright (C) 2017-2020 Ásbrú Connection Manager team\nCopyright 2010-2016 David Torrejón Vaquerizas",
        "website" => 'https://asbru-cm.net/',
        "license" => "
Ásbrú Connection Manager

Copyright (C) 2017-2020 Ásbrú Connection Manager team <https://asbru-cm.net>
Copyright (C) 2010-2016 David Torrejón Vaquerizas

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program.  If not, see <http://www.gnu.org/licenses/>.
"
    ));

    return 1;
}

sub _startCluster {
    my $self = shift;
    my $cluster = shift;

    my @idx;
    my $clulist = $$self{_CLUSTER}->getCFGClusters;

    if (defined $$self{_CFG}{defaults}{'auto cluster'}{$cluster}) {
        my $name = qr/$$self{_CFG}{defaults}{'auto cluster'}{$cluster}{name}/;
        my $host = qr/$$self{_CFG}{defaults}{'auto cluster'}{$cluster}{host}/;
        my $title = qr/$$self{_CFG}{defaults}{'auto cluster'}{$cluster}{title}/;
        my $desc = qr/$$self{_CFG}{defaults}{'auto cluster'}{$cluster}{desc}/;
        foreach my $uuid (keys %{ $$self{_CFG}{environments} }) {
            if ($uuid eq '__PAC__ROOT__' || $$self{_CFG}{environments}{$uuid}{_is_group}) {
                next;
            }
            if (($name ne '')&&($$self{_CFG}{environments}{$uuid}{name} !~ /$name/)) {
                next;
            }
            if (($host ne '')&&($$self{_CFG}{environments}{$uuid}{ip} !~ /$host/)) {
                next;
            }
            if (($title ne '')&&($$self{_CFG}{environments}{$uuid}{title} !~ /$title/)) {
                next;
            }
            if (($desc ne '')&&($$self{_CFG}{environments}{$uuid}{description} !~ /$desc/)) {
                next;
            }
            push(@idx, [ $uuid, undef, $cluster ]);
        }
    } else {
        foreach my $uuid (keys %{ $$clulist{$cluster} }) {
            push(@idx, [ $uuid, undef, $cluster ]);
        }
    }
    if ((scalar(@idx) >= 10)&&(!_wConfirm($$self{_GUI}{main}, "Are you sure you want to start <b>" . (scalar(@idx)) . " terminals from cluster '$cluster'</b> ?"))) {
        return 1;
    } elsif (!@idx) {
        _wMessage($$self{_GUI}{main}, "Cluster <b>$cluster</b> contains no elements");
        return 1;
    }
    $self->_launchTerminals(\@idx);
    return 1;
}

sub _launchTerminals {
    my $self = shift;
    my $terminals = shift;
    my $keys_buffer = shift;

    my @new_terminals;
    if (defined $$self{_GUI} && defined $$self{_GUI}{main}) {
        $$self{_GUI}{main}->get_window()->set_cursor(Gtk3::Gdk::Cursor->new('watch'));
        $$self{_GUI}{main}->set_sensitive(0);
    }

    # Check if user wants main window to be close when a terminal comes up
    if ($$self{_CFG}{'defaults'}{'hide on connect'} && ! $$self{_CFG}{'defaults'}{'tabs in main window'}) {
        if ($ENV{'ASBRU_DESKTOP'} eq 'gnome-shell') {
            $$self{_GUI}{main}->iconify();
        } else {
            $self->_hideConnectionsList();
        }
    }
    if ($$self{_CFG}{'defaults'}{'tabs in main window'} && $$self{_CFG}{'defaults'}{'auto hide connections list'}) {
        $$self{_GUI}{showConnBtn}->set_active(0);
    }
    if ($$self{_CFG}{'defaults'}{'auto hide button bar'}) {
        $$self{_GUI}{hbuttonbox1}->hide();
    }

    my $wtmp;
    scalar(@{ $terminals }) > 1 and $wtmp = _wMessage($$self{_GUI}{main}, "Starting '<b><big>". (scalar(@{ $terminals })) . "</big></b>' terminals...", 0);
    $ENV{'NTERMINALES'} = scalar(@{ $terminals });

    # Create all selected terminals
    foreach my $sel (@{ $terminals }) {
        my $uuid = $$sel[0];
        if (! defined $$self{_CFG}{'environments'}{$uuid}) {
            _wMessage($$self{_GUI}{main}, "ERROR: UUID <b>$uuid</b> does not exist in DDBB\nNot starting connection!", 1);
            next;
        } elsif ($$self{_CFG}{'environments'}{$uuid}{_is_group} || ($uuid eq '__PAC__ROOT__')) {
            _wMessage($$self{_GUI}{main}, "ERROR: UUID <b>$uuid</b> is a GROUP\nNot starting anything!", 1);
            next;
        }
        my $pset = $$self{_CFG}{'environments'}{$uuid}{'terminal options'}{'open in tab'} ? 'tab' : 'window';
        my $gset = $$self{_CFG}{'defaults'}{'open connections in tabs'} ? 'tab' : 'window';
        my $usepset = $$self{_CFG}{'environments'}{$uuid}{'terminal options'}{'use personal settings'};
        my $where = $$sel[1] // ($usepset ? $pset : $gset);
        my $cluster = $$sel[2] // '';
        my $manual = $$sel[3];
        my $name = $$self{_CFG}{'environments'}{$uuid}{'name'};
        # Change some variables
        my $pre_def = $$self{_CFG}{'defaults'}{'open connections in tabs'};
        my $pre_ter = $$self{_CFG}{'environments'}{$uuid}{'terminal options'}{'open in tab'};
        $$self{_CFG}{'defaults'}{'open connections in tabs'} = $where eq 'tab';
        $$self{_CFG}{'environments'}{$uuid}{'terminal options'}{'open in tab'} = $where eq 'tab';

        my $t = PACTerminal->new($$self{_CFG}, $uuid, $$self{_GUI}{nb}, $$self{_GUI}{_PACTABS}, $cluster, $manual) or die "ERROR: Could not create object($!)";
        push(@new_terminals, $t);

        # Restore previously changed variables
        $$self{_CFG}{'defaults'}{'open connections in tabs'} = $pre_def;
        $$self{_CFG}{'environments'}{$uuid}{'terminal options'}{'open in tab'} = $pre_ter;
    }

    # Start all created terminals
    foreach my $t (@new_terminals) {
        $$self{_GUI}{_PACTABS}->present if $$t{_TABBED};
        if (! $t->start($keys_buffer)) {
            _wMessage($$self{_GUI}{main}, __("ERROR: Could not start terminal '$$self{_CFG}{environments}{ $$t{_UUID} }{title}':\n$$t{ERROR}"), 1);
            next;
        }
        my $uuid = $$t{_UUID};
        my $icon = $uuid eq '__PAC_SHELL__' ? Gtk3::Gdk::Pixbuf->new_from_file_at_scale($RES_DIR . '/asbru_shell.png', 16, 16, 0) : $$self{_METHODS}{ $$self{_CFG}{'environments'}{$uuid}{'method'} }{'icon'};
        my $name = __($$self{_CFG}{'environments'}{$uuid}{'name'});
        unshift(@{ $$self{_GUI}{treeHistory}{data} }, ({ value => [ $icon, $name, $uuid,  strftime("%H:%M:%S %d-%m-%Y", localtime($FUNCS{_STATS}{statistics}{$uuid}{start})) ] }));
    }

    if (scalar(@{ $terminals }) > 1) {
        $wtmp->destroy(); undef $wtmp;
    }

    if (defined $$self{_GUI} && defined $$self{_GUI}{main}) {
        $$self{_GUI}{main}->get_window()->set_cursor(Gtk3::Gdk::Cursor->new('left-ptr'));
        $$self{_GUI}{main}->set_sensitive(1);
    }

    if ($$self{_CFG}{'defaults'}{'open connections in tabs'} && $$self{_CFG}{'defaults'}{'tabs in main window'}) {
        $self->_showConnectionsList(0);
    }
    if (@new_terminals && scalar(keys %RUNNING) > 1) {
        # Makes sure the focus is reset on that terminal if lost during startup process
        # (This only happens when another terminal is already open)
        $$self{_HAS_FOCUS} = $new_terminals[ $#new_terminals ]{_GUI}{_VTE};
    }

    return \@new_terminals;
}

sub _quitProgram {
    my $self = shift;
    my $force = shift // '0';

    my $changed = $$self{_CFG}{tmp}{changed} // '0';
    my $save = 0;
    my $rc = 0;

    # Get the list of connected terminals
    foreach my $uuid_tmp (keys %RUNNING) {
        $rc += $RUNNING{$uuid_tmp}{'terminal'}{CONNECTED} // 0;
    }

    # Check for user confirmation for close/save
    if (!$force) {
        my $string = "Are you sure you want to <b>exit</b> $APPNAME ?";
        $rc and $string .= "\n\n(" . ($rc > 1 ? "there are $rc open terminals" : "there is $rc open terminal")  . ")";
        if ($$self{_CFG}{'defaults'}{'confirm exit'} || $rc) {
            if (!_wConfirm($$self{_GUI}{main}, $string)) {
                return 1;
            }
        };
        if ($changed && (! $$self{_CFG}{defaults}{'save on exit'})) {
            my $opt = _wYesNoCancel($$self{_GUI}{main}, "<b>Configuration has changed.</b>\n\nSave changes?");
            $save = $opt eq 'yes';
            if ($opt eq 'cancel') {
                return 1;
            }
        } elsif ($changed) {
            $save = 1;
        }
    }

    print "INFO: Finishing ($Script) with pid $$\n";

    # Disconnect some events (to avoid side effects when closing/hiding)
    $$self{_GUI}{main}->signal_handler_disconnect($$self{_SIGNALS}{_WINDOWSTATEVENT}) if $$self{_SIGNALS}{_WINDOWSTATEVENT};

    # Hide every GUI component has already finished
    if ($UNITY) {
        $$self{_TRAY}{_TRAY}->set_passive;
    } else {
        $$self{_TRAY}{_TRAY}->set_visible(0);     # Hide tray icon?
    }
    $$self{_SCRIPTS}{_WINDOWSCRIPTS}{main}->hide();    # Hide scripts window
    $$self{_CLUSTER}{_WINDOWCLUSTER}{main}->hide();    # Hide clusters window
    $$self{_PCC}{_WINDOWPCC}{main}->hide();    # Hide PCC window
    $$self{_GUI}{main}->hide();    # Hide main window
    $$self{_GUI}{_PACTABS}->hide();    # Hide TABs window

    if ($$self{_READONLY}) {
        Gtk3->main_quit;
        return 1;
    }

    # Force the stop of every opened terminal
    foreach my $tmp_uuid (keys %RUNNING) {
        if (!defined $RUNNING{$tmp_uuid}{terminal}) {
            next;
        }
        if (ref($RUNNING{$tmp_uuid}{terminal}) =~ /^PACTerminal|PACShell$/go) {
            $RUNNING{$tmp_uuid}{terminal}->stop(1, 0);
        }
    }

    Gtk3::main_iteration while Gtk3::events_pending;   # Update GUI
    # Once everything is hidden, we may last any time in our final I/O
    delete $$self{_CFG}{environments}{'__PAC_SHELL__'};    # Delete PACShell environment
    delete $$self{_CFG}{environments}{'__PAC__QUICK__CONNECT__'}; # Delete quick connect environment
    $self->_saveTreeExpanded;          # Save Tree opened/closed  groups
    $self->_saveConfiguration if $save;       # Save config, if applies
    $$self{_GUI}{statistics}->purge($$self{_CFG});    # Purge trash statistics
    $$self{_GUI}{statistics}->saveStats;       # Save statistics
    unless (grep(/^--no-backup$/, @{ $$self{_OPTS} })) {
        $$self{_CONFIG}->_exporter('yaml', $CFG_FILE);   # Export as YAML file
        $$self{_CONFIG}->_exporter('perl', $CFG_FILE_DUMPER); # Export as Perl data
    };
    chdir(${CFG_DIR}) and system("rm -rf sockets/* tmp/*");  # Delete temporal files

    # And finish every GUI
    Gtk3->main_quit;

    return 1;
}

sub _saveConfiguration {
    my $self = shift;
    my $cfg = shift // $$self{_CFG};
    my $normal = shift // 1;

    _purgeUnusedOrMissingScreenshots($cfg);
    _cfgSanityCheck($cfg);
    _cipherCFG($cfg);
    nstore($cfg, $CFG_FILE_NFREEZE) or _wMessage($$self{_GUI}{main}, "ERROR: Could not save config file '$CFG_FILE_NFREEZE':\n\n$!");
    if ($R_CFG_FILE) {
        nstore($cfg, $R_CFG_FILE) or _wMessage($$self{_GUI}{main}, "ERROR: Could not save config file '$R_CFG_FILE':\n\n$!\n\nLocal copy saved at '$CFG_FILE_NFREEZE'");
    }
    _decipherCFG($cfg);

    $self->_saveTreeExpanded;
    $$self{_GUI}{statistics}->saveStats;

    $normal and $self->_setCFGChanged(0);

    # Prepare the .desktop file to contain list of favourites connections
    #_makeDesktopFile($cfg);

    return $CFG_FILE_NFREEZE;
}

sub _readConfiguration {
    my $self = shift;
    my $splash = shift // 1;

    my $continue = 1;

    if ($continue && $R_CFG_FILE && -r $R_CFG_FILE) {
        eval { $$self{_CFG} = retrieve($R_CFG_FILE); };
        if ($@) {
            print STDERR "WARNING: There were errors reading remote file '$R_CFG_FILE' config file: $@\n";
        } else {
            print STDERR "INFO: Used remote config file '$R_CFG_FILE'\n";
            $continue = 0;
        }
    }

    if ($continue && -f $CFG_FILE_NFREEZE) {
        eval { $$self{_CFG} = retrieve($CFG_FILE_NFREEZE); };
        if ($@) {
            print STDERR "WARNING: There were errors reading '$CFG_FILE_NFREEZE' config file: $@\n";
        } else {
            print STDERR "INFO: Used config file '$CFG_FILE_NFREEZE'\n";
            if ($R_CFG_FILE) {
                nstore($$self{_CFG}, $R_CFG_FILE) or die "ERROR: Could not save remote config file '$R_CFG_FILE': $!";
            }
            $continue = 0;
        }
    }

    if ($continue && -f $CFG_FILE) {
        if (! ($$self{_CFG} = YAML::LoadFile($CFG_FILE))) {
            print STDERR "WARNING: Could not load config file '$CFG_FILE': $!\n";
        } else {
            print STDERR "INFO: Used config file '$CFG_FILE'\n";
            if ($R_CFG_FILE) {
                nstore($$self{_CFG}, $R_CFG_FILE) or die "ERROR: Could not save remote config file '$R_CFG_FILE': $!";
            }
            nstore($$self{_CFG}, $CFG_FILE_NFREEZE) or die "ERROR: Could not save config file '$CFG_FILE_NFREEZE': $!";
            $continue = 0;
        }
    }

    if ($continue && -f $CFG_FILE_DUMPER) {
        if (!open(F,"<:utf8",$CFG_FILE_DUMPER)) {
            die "ERROR: Could open for reading file '$CFG_FILE_DUMPER': $!";
        }
        my $data = '';
        while (my $line = <F>) {
            $data .= $line;
        }
        close F;
        my $VAR1;
        eval $data;
        if ($@) {
            print STDERR "ERROR: Could not load config file from '$CFG_FILE_DUMPER': $@\n";
        } else {
            print STDERR "INFO: Used config file '$CFG_FILE_DUMPER'\n";
            $$self{_CFG} = $VAR1;
            nstore($$self{_CFG}, $CFG_FILE_NFREEZE) or die "ERROR: Could not save config file '$CFG_FILE_NFREEZE': $!";
            if ($R_CFG_FILE) {
                nstore($$self{_CFG}, $R_CFG_FILE) or die "ERROR: Could not save remote config file '$R_CFG_FILE': $!";
            }
            $continue = 0;
        }
    }

    if ($continue && -f $CFG_FILE_FREEZE) {
        eval {
            $$self{_CFG} = retrieve($CFG_FILE_FREEZE);
        };
        if ($@) {
            print STDERR "WARNING: There were errors reading the '$CFG_FILE_FREEZE' config file: $@\n";
        } else {
            print STDERR "INFO: Used config file '$CFG_FILE_FREEZE'\n";
            nstore($$self{_CFG}, $CFG_FILE_NFREEZE) or die"ERROR: Could not save config file '$CFG_FILE_NFREEZE': $!";
            if ($R_CFG_FILE) {
                nstore($$self{_CFG}, $R_CFG_FILE) or die "ERROR: Could not save remote config file '$R_CFG_FILE': $!";
            }
            unlink($CFG_FILE_FREEZE);
            $continue = 0;
        }
    }

     # PENDING: I think we should be able to remove this code
    if ($continue && (! -f "${CFG_FILE}.prev3") && (-f $CFG_FILE)) {
        print STDERR "INFO: Migrating config file to v3...\n";
        PACUtils::_splash(1, "$APPNAME (v$APPVERSION):Migrating config...", ++$PAC_START_PROGRESS, $PAC_START_TOTAL);
        $$self{_CFG} = _cfgCheckMigrationV3;
        copy($CFG_FILE, "${CFG_FILE}.prev3") or die "ERROR: Could not copy pre v.3 cfg file '$CFG_FILE' to '$CFG_FILE.prev3': $!";
        nstore($$self{_CFG}, $CFG_FILE_NFREEZE) or die"ERROR: Could not save config file '$CFG_FILE_NFREEZE': $!";
        if ($R_CFG_FILE) {
            nstore($$self{_CFG}, $R_CFG_FILE) or die "ERROR: Could not save remote config file '$R_CFG_FILE': $!";
        }
        $continue = 0;
    }
    # END of removing

    if ($R_CFG_FILE && $continue) {
         print STDERR "WARN: No configuration file in (remote) '$CFG_DIR', creating a new one...\n";
    }
    if ($continue) {
        print STDERR "WARN: No configuration file found in '$CFG_DIR', creating a new one...\n";
    }

    # Make some sanity checks
    $splash and PACUtils::_splash(1, "$APPNAME (v$APPVERSION):Checking config...", 4, 5);
    _cfgSanityCheck($$self{_CFG});
    _decipherCFG($$self{_CFG});

    $$self{_CFG}{'defaults'}{'layout'} = defined $$self{_CFG}{'defaults'}{'layout'} ? $$self{_CFG}{'defaults'}{'layout'} : 'Traditional';
    return 1;
}

sub _loadTreeConfiguration {
    my $self = shift;
    my $group = shift;
    my $tree = shift // $$self{_GUI}{treeConnections};

    @{ $$self{_GUI}{treeConnections}{'data'} } =
    ({
        value => [ $GROUPICON_ROOT, '<b>AVAILABLE CONNECTIONS</b>', '__PAC__ROOT__' ],
        children => []
    });
    foreach my $child (keys %{ $$self{_CFG}{environments}{'__PAC__ROOT__'}{children} }) {
        push(@{ $$tree{data} }, $self->__recurLoadTree($child));
    }

    # Select the root path
    $tree->set_cursor(Gtk3::TreePath->new_from_string('0'), undef, 0);

    return 1;
}

sub __recurLoadTree {
    my $self = shift;
    my $uuid = shift;

    my $node_name = $self->__treeBuildNodeName($uuid);
    my @list;

    if (!$$self{_CFG}{environments}{$uuid}{'_is_group'}) {
        push(@list, {
            value => [ $$self{_METHODS}{ $$self{_CFG}{'environments'}{$uuid}{'method'} }{'icon'}, $node_name, $uuid ],
            children => []
        });
    } else {
        my @clist;
        foreach my $child (keys %{ $$self{_CFG}{environments}{$uuid}{children} }) {
            push(@clist, $self->__recurLoadTree($child));
        }
        push(@list, {
            value => [ $GROUPICONCLOSED, $node_name, $uuid ],
            children => \@clist
        });
    }

    return @list;
}

sub _saveTreeExpanded {
    my $self = shift;
    my $tree = shift // $$self{_GUI}{treeConnections};

    my $selection = $tree->get_selection;
    my $modelsort = $tree->get_model;
    my $model = $modelsort->get_model;

    open(F,">:utf8","$CFG_FILE.tree") or die "ERROR: Could not save Tree Config file '$CFG_FILE.tree': $!";
    $modelsort->foreach(sub {
        my ($store, $path, $iter, $tmp) = @_;
        my $uuid = $store->get_value($iter, 2);
        if (!($tree->row_expanded($path) && $uuid ne '__PAC__ROOT__')) {
            return 0;
        }
        print F $uuid . "\n";
        return 0;
    });

    my $page0 = $$self{_GUI}{nbTree}->get_nth_page(0);
    my $page1 = $$self{_GUI}{nbTree}->get_nth_page(1);
    my $page2 = $$self{_GUI}{nbTree}->get_nth_page(2);
    my $page3 = $$self{_GUI}{nbTree}->get_nth_page(3);

    # Connections
    $$self{_GUI}{scroll1} eq $page0 and print F "tree_page_0:scroll1\n";
    $$self{_GUI}{scroll1} eq $page1 and print F "tree_page_1:scroll1\n";
    $$self{_GUI}{scroll1} eq $page2 and print F "tree_page_2:scroll1\n";
    $$self{_GUI}{scroll1} eq $page3 and print F "tree_page_3:scroll1\n";
    # Favourites
    $$self{_GUI}{scroll2} eq $page0 and print F "tree_page_0:scroll2\n";
    $$self{_GUI}{scroll2} eq $page1 and print F "tree_page_1:scroll2\n";
    $$self{_GUI}{scroll2} eq $page2 and print F "tree_page_2:scroll2\n";
    $$self{_GUI}{scroll2} eq $page3 and print F "tree_page_3:scroll2\n";
    # History
    $$self{_GUI}{scroll3} eq $page0 and print F "tree_page_0:scroll3\n";
    $$self{_GUI}{scroll3} eq $page1 and print F "tree_page_1:scroll3\n";
    $$self{_GUI}{scroll3} eq $page2 and print F "tree_page_2:scroll3\n";
    $$self{_GUI}{scroll3} eq $page3 and print F "tree_page_3:scroll3\n";
    # Clusters
    $$self{_GUI}{vboxclu} eq $page0 and print F "tree_page_0:vboxclu\n";
    $$self{_GUI}{vboxclu} eq $page1 and print F "tree_page_1:vboxclu\n";
    $$self{_GUI}{vboxclu} eq $page2 and print F "tree_page_2:vboxclu\n";
    $$self{_GUI}{vboxclu} eq $page3 and print F "tree_page_3:vboxclu\n";

    close F;

    return 1;
}

sub _loadTreeExpanded {
    my $self = shift;
    my $tree = shift // $$self{_GUI}{treeConnections};

    my %TREE_TABS;

    if (-f "$CFG_FILE.tree") {
        open(F,"<:utf8","$CFG_FILE.tree") or die "ERROR: Could not read Tree Config file '$CFG_FILE.tree': $!";;
        foreach my $uuid (<F>) {

            chomp $uuid;
            if ($uuid =~ /^tree_page_(\d):(.+)$/go) {
                $TREE_TABS{$1} = $2;
            } else {
                my $path = $$self{_GUI}{treeConnections}->_getPath($uuid) or next;
                $tree->expand_row($path, 0);
            }
        }
        close F;
    }

    defined $TREE_TABS{0} and $$self{_GUI}{nbTree}->reorder_child($$self{_GUI}{$TREE_TABS{0}}, 0);
    defined $TREE_TABS{1} and $$self{_GUI}{nbTree}->reorder_child($$self{_GUI}{$TREE_TABS{1}}, 1);
    defined $TREE_TABS{2} and $$self{_GUI}{nbTree}->reorder_child($$self{_GUI}{$TREE_TABS{2}}, 2);
    defined $TREE_TABS{3} and $$self{_GUI}{nbTree}->reorder_child($$self{_GUI}{$TREE_TABS{3}}, 3);

    return 1;
}

sub _saveGUIData {
    my $self = shift;

    open(F,">:utf8","$CFG_FILE.gui") or die "ERROR: Could not save GUI Config file '$CFG_FILE.gui': $!";;

    # Save Top Window size/position
    if ($$self{_GUI}{maximized}) {
        print F 'maximized';
    } else {
        my ($x, $y) = $$self{_GUI}{main}->get_position();
        my ($w, $h) = $$self{_GUI}{main}->get_size();
        print F $x . ':' . $y . ':' . $w . ':' . $h;
    }
    print F "\n";

    # Save connections list width
    my $treepos = $$self{_GUI}{hpane}->get_position();
    print F $treepos . "\n";

    close F;

    return 1;
}

sub _loadGUIData {
    my $self = shift;

    if (!-f "$CFG_FILE.gui") {
        return 1;
    }

    open(F,"<:utf8","$CFG_FILE.gui") or die "ERROR: Could not read GUI Config file '$CFG_FILE.gui': $!";

    # Read top level window's psize/position
    my $win = <F>;
    chomp $win;

    ($$self{_GUI}{posx}, $$self{_GUI}{posy}, $$self{_GUI}{sw}, $$self{_GUI}{sh}) =
        $win eq 'maximized'
        ? ('maximized', 'maximized', 'maximized', 'maximized')
        : split(':', $win);

    # Read connections list width
    my $tree = <F> // '-1';
    chomp $tree;
    $$self{_GUI}{hpanepos} = $tree;

    close F;

    return 1;
}

sub _updateGUIWithUUID {
    my $self = shift;
    my $uuid = shift;

    my $is_root = $uuid eq '__PAC__ROOT__';

    if ($is_root) {
        $$self{_GUI}{descBuffer}->set_text(qq"

 * Welcome to $APPNAME version $APPVERSION *

 - To create a New GROUP of Connections:

   1- 'click' over 'AVAILABLE CONNECTIONS' (to create it at root) or any other GROUP
   2- 'click' on the most left icon over the connections tree (or right-click over selected GROUP)
   3- Follow instructions

 - To create a New CONNECTION in a selected Group or at root:

   1- Select the container group to create the new connection into (or 'AVAILABLE CONNECTIONS' to create it at root)
   2- 'click' on the second most left icon over the connections tree (or right-click over selected GROUP)
   3- Follow instructions

 - For the latest news, check the project website (https://asbru-cm.net/).

");
    } else {
        if (!$$self{_CFG}{'environments'}{$uuid}{'description'}) {
            $$self{_CFG}{'environments'}{$uuid}{'description'} = 'Insert your comments for this connection here ...';
        }
        $$self{_GUI}{descBuffer}->set_text("$$self{_CFG}{'environments'}{$uuid}{'description'}");
    }

    if ($$self{_CFG}{'defaults'}{'show statistics'}) {
        $$self{_GUI}{statistics}->update($uuid, $$self{_CFG});
        $$self{_GUI}{frameStatistics}->show;
    } else {
        $$self{_GUI}{frameStatistics}->hide();
    }

    if ($$self{_CFG}{'defaults'}{'show screenshots'}) {
        $$self{_GUI}{screenshots}->update($$self{_CFG}{'environments'}{$uuid}, $uuid);
        $$self{_GUI}{frameScreenshots}->show_all();
    } else {
        $$self{_GUI}{frameScreenshots}->hide();
    }

    return 1;
}

sub _updateGUIPreferences {
    my $self = shift;

    my @sel_uuids = $$self{_GUI}{treeConnections}->_getSelectedUUIDs();
    my $total = scalar(@sel_uuids);

    my $is_group = 0;
    my $is_root = 0;
    my $protected = 0;
    my $uuid = $sel_uuids[0];
    defined $uuid or return 1;

    foreach my $uuid (@sel_uuids) {
        $uuid eq '__PAC__ROOT__' and $is_root = 1;
        $$self{_CFG}{'environments'}{$uuid}{'_is_group'} and $is_group = 1;
        $$self{_CFG}{'environments'}{$uuid}{'_protected'} and $protected = 1;
    }

    $$self{_GUI}{nbTreeTabLabel}->set_text(' Connections');
    $$self{_GUI}{nbFavTabLabel}->set_text('');
    $$self{_GUI}{nbHistTabLabel}->set_text('');
    $$self{_GUI}{nbCluTabLabel}->set_text('');

    $$self{_GUI}{connSearch}->set_sensitive(1);
    $$self{_GUI}{groupAddBtn}->set_sensitive($total eq 1 && ($is_group || $is_root));
    $$self{_GUI}{connAddBtn}->set_sensitive($total eq 1 && ($is_group || $is_root));
    $$self{_GUI}{connEditBtn}->set_sensitive($total >= 1 && ! $is_root);
    $$self{_GUI}{nodeRenBtn}->set_sensitive($total eq 1 && ! $is_root && ! $protected);
    $$self{_GUI}{nodeDelBtn}->set_sensitive($total >= 1 && ! $is_root && ! $protected);
    $$self{_GUI}{connExecBtn}->set_sensitive($total >= 1);
    $$self{_GUI}{descView}->set_sensitive($total eq 1 && ! $is_root);
    $$self{_GUI}{frameStatistics}->set_sensitive($total eq 1);
    $$self{_GUI}{frameScreenshots}->set_sensitive($total eq 1 && ! $is_root);
    $$self{_GUI}{connFavourite}->set_sensitive($total >= 1 && ! ($is_root || $is_group));
    $$self{_NO_PROPAGATE_FAV_TOGGLE} = 1;
    $$self{_GUI}{connFavourite}->set_active($total eq 1 && ! ($is_root || $is_group) && $$self{_CFG}{'environments'}{$uuid}{'favourite'});
    $$self{_GUI}{connFavourite}->set_image(Gtk3::Image->new_from_stock('pac-favourite-' . ($$self{_CFG}{'environments'}{$uuid}{'favourite'} ? 'on' : 'off'), 'button'));
    $$self{_NO_PROPAGATE_FAV_TOGGLE} = 0;

    $$self{_GUI}{nb}->set_tab_pos($$self{_CFG}{'defaults'}{'tabs position'});
    $$self{_GUI}{treeConnections}->set_enable_tree_lines($$self{_CFG}{'defaults'}{'enable tree lines'});
    $$self{_GUI}{descView}->modify_font(Pango::FontDescription::from_string($$self{_CFG}{'defaults'}{'info font'}));

    if ($UNITY) {
        (! $$self{_GUI}{main}->get_visible || $$self{_CFG}{defaults}{'show tray icon'}) ? $$self{_TRAY}{_TRAY}->set_active() : $$self{_TRAY}{_TRAY}->set_passive();
    } else {
        $$self{_TRAY}{_TRAY}->set_visible(! $$self{_GUI}{main}->get_visible || $$self{_CFG}{defaults}{'show tray icon'});
    }

    $$self{_GUI}{lockPACBtn}->set_sensitive($$self{_CFG}{'defaults'}{'use gui password'});

    $self->_updateGUIWithUUID($sel_uuids[0]) if $total == 1;

    return 1;
}

sub _updateGUIFavourites {
    my $self = shift;

    my @sel_uuids = $$self{_GUI}{treeFavourites}->_getSelectedUUIDs();
    my $total = scalar(@sel_uuids);
    my $uuid = $sel_uuids[0];

    $$self{_GUI}{nbTreeTabLabel}->set_text('');
    $$self{_GUI}{nbFavTabLabel}->set_text(' Favourites');
    $$self{_GUI}{nbHistTabLabel}->set_text('');
    $$self{_GUI}{nbCluTabLabel}->set_text('');

    $$self{_GUI}{connSearch}->set_sensitive(0);
    $$self{_GUI}{groupAddBtn}->set_sensitive(0);
    $$self{_GUI}{connAddBtn}->set_sensitive(0);
    $$self{_GUI}{connEditBtn}->set_sensitive($total >= 1 && $uuid ne '__PAC__ROOT__');
    $$self{_GUI}{nodeRenBtn}->set_sensitive(0);
    $$self{_GUI}{nodeDelBtn}->set_sensitive(0);
    $$self{_GUI}{connExecBtn}->set_sensitive($total >= 1 && $uuid ne '__PAC__ROOT__');
    $$self{_GUI}{descView}->set_sensitive(0);
    $$self{_GUI}{frameStatistics}->set_sensitive(0);
    $$self{_GUI}{frameScreenshots}->set_sensitive(0);
    $$self{_GUI}{connFavourite}->set_sensitive(1 && $uuid ne '__PAC__ROOT__');
    $$self{_NO_PROPAGATE_FAV_TOGGLE} = 1;
    $$self{_GUI}{connFavourite}->set_active($uuid ne '__PAC__ROOT__');
    $$self{_GUI}{connFavourite}->set_image(Gtk3::Image->new_from_stock('pac-favourite-on', 'button'));
    $$self{_NO_PROPAGATE_FAV_TOGGLE} = 0;

    if ($total == 1) {
        $self->_updateGUIWithUUID($sel_uuids[0]);
    }

    return 1;
}

sub _updateGUIHistory {
    my $self = shift;

    my @sel_uuids = $$self{_GUI}{treeHistory}->_getSelectedUUIDs();
    my $total = scalar(@sel_uuids);
    my $uuid = $sel_uuids[0];

    $$self{_GUI}{nbTreeTabLabel}->set_text('');
    $$self{_GUI}{nbFavTabLabel}->set_text('');
    $$self{_GUI}{nbHistTabLabel}->set_text(' History');
    $$self{_GUI}{nbCluTabLabel}->set_text('');

    $$self{_GUI}{connSearch}->set_sensitive(0);
    $$self{_GUI}{groupAddBtn}->set_sensitive(0);
    $$self{_GUI}{connAddBtn}->set_sensitive(0);
    $$self{_GUI}{connEditBtn}->set_sensitive($total >= 1 && $uuid ne '__PAC__ROOT__' && $uuid ne '__PAC_SHELL__');
    $$self{_GUI}{nodeRenBtn}->set_sensitive(0);
    $$self{_GUI}{nodeDelBtn}->set_sensitive(0);
    $$self{_GUI}{connExecBtn}->set_sensitive($total >= 1 && $uuid ne '__PAC__ROOT__');
    $$self{_GUI}{descView}->set_sensitive(0);
    $$self{_GUI}{frameStatistics}->set_sensitive(0);
    $$self{_GUI}{frameScreenshots}->set_sensitive(0);
    $$self{_GUI}{connFavourite}->set_sensitive(0);
    $$self{_NO_PROPAGATE_FAV_TOGGLE} = 1;
    $$self{_GUI}{connFavourite}->set_active($$self{_CFG}{'environments'}{$uuid}{'favourite'});
    $$self{_GUI}{connFavourite}->set_image(Gtk3::Image->new_from_stock('pac-favourite-' . ($$self{_CFG}{'environments'}{$uuid}{'favourite'} ? 'on' : 'off'), 'button'));
    $$self{_NO_PROPAGATE_FAV_TOGGLE} = 0;

    $self->_updateGUIWithUUID($sel_uuids[0]) if $total == 1;

    return 1;
}

sub _updateGUIClusters {
    my $self = shift;

    my @sel_uuids = $$self{_GUI}{treeClusters}->_getSelectedNames;
    my $total = scalar(@sel_uuids);
    my $uuid = $sel_uuids[0];

    $$self{_GUI}{nbTreeTabLabel}->set_text('');
    $$self{_GUI}{nbFavTabLabel}->set_text('');
    $$self{_GUI}{nbHistTabLabel}->set_text('');
    $$self{_GUI}{nbCluTabLabel}->set_text(' Clusters');

    $$self{_GUI}{connSearch}->set_sensitive(0);
    $$self{_GUI}{groupAddBtn}->set_sensitive(0);
    $$self{_GUI}{connAddBtn}->set_sensitive(0);
    $$self{_GUI}{connEditBtn}->set_sensitive(0);
    $$self{_GUI}{nodeRenBtn}->set_sensitive(0);
    $$self{_GUI}{nodeDelBtn}->set_sensitive(0);
    $$self{_GUI}{connExecBtn}->set_sensitive($total == 1);
    $$self{_GUI}{descView}->set_sensitive(0);
    $$self{_GUI}{frameStatistics}->set_sensitive(0);
    $$self{_GUI}{frameScreenshots}->set_sensitive(0);
    $$self{_GUI}{connFavourite}->set_sensitive(0);
    $$self{_NO_PROPAGATE_FAV_TOGGLE} = 1;
    $$self{_GUI}{connFavourite}->set_active(0);
    $$self{_NO_PROPAGATE_FAV_TOGGLE} = 0;

    $self->_updateGUIWithUUID('__PAC__ROOT__');

    return 1;
}

sub _updateClustersList {
    my $self = shift;

    @{ $$self{_GUI}{treeClusters}{data} } = ();
    foreach my $ac (sort { $a cmp $b } keys %{ $$self{_CFG}{defaults}{'auto cluster'} }) {
        push(@{ $$self{_GUI}{treeClusters}{data} }, ({ value => [ $AUTOCLUSTERICON, $ac ]}));
    }
    foreach my $cluster (sort { $a cmp $b } keys %{ $$self{_CLUSTER}->getCFGClusters }) {
        push(@{ $$self{_GUI}{treeClusters}{data} }, ({ value => [ $CLUSTERICON, $cluster ]}));
    }

    return 1;
}

sub _updateFavouritesList {
    my $self = shift;
    my ($name);

    @{ $$self{_GUI}{treeFavourites}{data} } = ();
    foreach my $uuid (keys %{ $$self{_CFG}{'environments'} }) {
        if (!$$self{_CFG}{'environments'}{$uuid}{'favourite'}) {
            next;
        }
        my $icon = $$self{_METHODS}{ $$self{_CFG}{'environments'}{$uuid}{'method'} }{'icon'};
        my $group = $$self{_CFG}{'environments'}{$uuid}{'parent'};
        if ($group) {
            $name = __($$self{_CFG}{'environments'}{$uuid}{'name'});
            $group = __("$$self{_CFG}{'environments'}{$group}{'name'} : ");
            $name = "$group$name";
        } else {
            $name = __($$self{_CFG}{'environments'}{$uuid}{'name'});
        }
        push(@{ $$self{_GUI}{treeFavourites}{data} }, ({ value => [ $icon, $name, $uuid ] }));
    }

    $self->_updateGUIFavourites();

    return 1;
}

sub _delNodes {
    my $self = shift;
    my @uuids = @_;

    foreach my $uuid (@uuids) {
        if (!defined $$self{_CFG}{'environments'}{$uuid}) {
            next;
        }

        # Delete every possible "sweet child of mine"
        $$self{_CFG}{'environments'}{$uuid}{'_is_group'} and $self->_delNodes($_) foreach (keys %{ $$self{_CFG}{'environments'}{$uuid}{'children'} });

        # Delete me from my parent's children list
        my $parent_uuid = $$self{_CFG}{'environments'}{$uuid}{'parent'};
        if (!((defined $parent_uuid) && (defined $$self{_CFG}{'environments'}{$parent_uuid}))) {
            next;
        }
        if (defined $$self{_CFG}{'environments'}{$parent_uuid}{'children'}{$uuid}) {
            delete $$self{_CFG}{'environments'}{$parent_uuid}{'children'}{$uuid};
        }

        # Delete me from the configuration
        delete $$self{_CFG}{'environments'}{$uuid};
    }

    return 1;
}

sub _showConnectionsList {
    my $self = shift;
    my $move = shift // 1;

    $$self{_GUI}{main}->show;
    #$$self{_GUI}{main}->present_with_time(time);
    $$self{_GUI}{main}->present;

    if ($move) {
        $$self{_GUI}{main}->move($$self{_GUI}{posx} // 0, $$self{_GUI}{posy} // 0);
    }
}

sub _hideConnectionsList {
    my $self = shift;

    ($$self{_GUI}{posx}, $$self{_GUI}{posy}) = $$self{_GUI}{main}->get_position();
    $$self{_GUI}{main}->hide();
}

sub _toggleConnectionsList {
    my $self = shift;
    $$self{_GUI}{showConnBtn}->set_active(! $$self{_GUI}{showConnBtn}->get_active());
}

sub _copyNodes {
    my $self = shift;
    my $cut = shift // '0';
    my $parent = shift // '__PAC__COPY__';
    my $sel_uuids = shift // [ $$self{_GUI}{treeConnections}->_getSelectedUUIDs() ];

    # Empty the copy-vault
    $$self{_COPY}{'data'} = {};
    $$self{_COPY}{'cut'} = $cut;

    my $total = scalar(@{ $sel_uuids });
    if (!$total || ($$sel_uuids[0] eq '__PAC__ROOT__')) {
        return 1;
    }
    foreach my $sel (@{ $sel_uuids }) {
        $self->__dupNodes($parent, $sel, $$self{_COPY}{'data'}, $cut);
    }

    return 1;
}

sub _cutNodes {
    my $self = shift;

    my @sel_uuids = $$self{_GUI}{treeConnections}->_getSelectedUUIDs();
    my $total = scalar(@sel_uuids);

    if (!$total || ($sel_uuids[0] eq '__PAC__ROOT__')) {
        return 1;
    }
    if ($self->_hasProtectedChildren(\@sel_uuids)) {
        return _wMessage(undef, "Can not CUT selection:\nThere are <b>'Protected'</b> nodes selected");
    }

    # Copy the selected nodes
    $self->_copyNodes('cut');
    if (! scalar(keys %{ $$self{_COPY}{'data'} })) {
        return 1;
    }

    # Delete selected nodes from treeConnections
    foreach my $uuid (@sel_uuids) {
        $$self{_GUI}{treeConnections}->_delNode($uuid);
    }

    # Delete selected nodes from the configuration
    $self->_delNodes(@sel_uuids);

    #$$self{_CFG}{tmp}{changed} = 1;
    $self->_setCFGChanged(1);
    return 1;
};

sub _pasteNodes {
    my $self = shift;
    my $parent = shift // '__PAC__COPY__';
    my $uuid = shift;
    my $first = shift // 1;

    if (!scalar(keys %{ $$self{_COPY}{'data'} })) {
        return 1;
    }
    if ((!$$self{_CFG}{'environments'}{$parent}{'_is_group'}) && ($parent ne '__PAC__ROOT__')) {
        return 1;
    }

    if ($parent ne $$self{_COPY}{'data'}{$uuid}{'original_parent'}) {
        # If paste is under different parent, remove copy message, it is not necessary
        $$self{_COPY}{'data'}{$uuid}{'name'} =~ s/ - copy//;
    }
    # Remove original_parent value is not part of the configuration standard
    delete $$self{_COPY}{'data'}{$uuid}{'original_parent'};

    # Add new node to configuration
    $$self{_CFG}{'environments'}{$uuid} = $$self{_COPY}{'data'}{$uuid};
    $$self{_CFG}{'environments'}{$uuid}{'parent'} = $parent;
    $$self{_CFG}{'environments'}{$parent}{'children'}{$uuid} = 1;

    # Add new node to Connections Tree
    $$self{_GUI}{treeConnections}->_addNode(
        $$self{_CFG}{'environments'}{$uuid}{'parent'},       # Parent UUID
        $uuid,                                               # UUID
        $self->__treeBuildNodeName($uuid),                   # Name
        ! $$self{_CFG}{'environments'}{$uuid}{'_is_group'} ? # Icon
            $$self{_METHODS}{ $$self{_CFG}{'environments'}{$uuid}{'method'} }{'icon'} :
            $GROUPICONCLOSED);

    # Repeat procedure for every 1st level child
    foreach my $child (keys %{ $$self{_COPY}{'data'}{$uuid}{'children'} }) {
        $self->_pasteNodes($uuid, $child, 0);
        delete $$self{_COPY}{'data'}{$uuid};
    }

    if ($first and $UNITY) {
        $FUNCS{_TRAY}->_setTrayMenu;
    }

    #$$self{_CFG}{tmp}{changed} = 1;
    $self->_setCFGChanged(1);
    return 1;
};

sub __dupNodes {
    my $self = shift;
    my $parent = shift;
    my $uuid = shift;
    my $cfg = shift;
    my $cut = shift // '0';

    # Generate a new UUID for the copied element
    my $new_uuid = OSSP::uuid->new; $new_uuid->make("v4");
    my $new_txt_uuid = $new_uuid->export("str");
    undef $new_uuid;

    # Clone the node with the NEW UUID
    $$cfg{$new_txt_uuid} = dclone($$self{_CFG}{'environments'}{$uuid});
    # Save original parent node for reference on paste
    $$cfg{$new_txt_uuid}{'original_parent'} = $$cfg{$new_txt_uuid}{'parent'};
    $$cfg{$new_txt_uuid}{'parent'} = $parent;
    if (!$cut) {
        # If action is not a cut, add 'copy' to the name, so it is different from previous node
        $$cfg{$new_txt_uuid}{'name'} = "$$self{_CFG}{'environments'}{$uuid}{'name'} - copy";
    }
    $$cfg{$parent}{'children'}{$new_txt_uuid} = 1;

    # Delete screenshots and statistics on duplicated node
    $$cfg{$new_txt_uuid}{'screenshots'} = ();
    delete $FUNCS{_STATS}{statistics}{$new_txt_uuid};

    delete $$cfg{$parent}{'children'}{$uuid};

    # Repeat procedure for every 1st level child
    foreach my $child ($$self{_GUI}{treeConnections}->_getChildren($uuid, 'all', 0)) {
        $self->__dupNodes($new_txt_uuid, $child, $cfg, $cut);
    }

    return $cfg;
}

sub __exportNodes {
    my $self = shift;
    my $sel = shift // [ $$self{_GUI}{treeConnections}->_getSelectedUUIDs() ];

    my ($list, $all, $cipher) = $self->_bulkEdit("$APPNAME (v.$APPVERSION) Choose fields to skip during Export phase", "Please, <b>check</b> the fields to be changed during the Export phase\nand put a new (may be empty) value for them.\n<b>Unchecked</b> elements will be exported with their original values.", 0, 'ask for cipher');

    if (!defined $list) {
        return 0;
    }

    my $choose = Gtk3::FileChooserDialog->new(
        "$APPNAME (v.$APPVERSION) Choose file to Export",
        $$self{_WINDOWCONFIG},
        'GTK_FILE_CHOOSER_ACTION_SAVE',
        'Export' , 'GTK_RESPONSE_ACCEPT',
        'Cancel' , 'GTK_RESPONSE_CANCEL',
    );
    $choose->set_do_overwrite_confirmation(1);
    $choose->set_current_folder($ENV{'HOME'} // '/tmp');
    $choose->set_current_name("pac_export.yml");

    my $out = $choose->run;
    my $file = $choose->get_filename;
    $file =~ /^(.+)\.yml$/ or $file .= '.yml';
    $choose->destroy();

    if ($out ne 'accept') {
        return 1;
    }

    my $w = _wMessage($$self{_WINDOWCONFIG}, "Please, wait while file '$file' is being exported...", 0);
    Gtk3::main_iteration while Gtk3::events_pending;

    # Make a backup of the original CFG
    my $backup_cfg = dclone($$self{_CFG}{'environments'});

    # Modify the config (_substCFG) based on the provided list (_bulkEdit)
    foreach my $uuid (keys %{ $$self{_CFG}{'environments'} }) {
        _substCFG($$self{_CFG}{'environments'}{$uuid}, $list);
    }

    # Cipher the configuration
    $cipher and _cipherCFG($$self{_CFG});

    # Copy the selected nodes
    $self->_copyNodes(0, '__PAC__EXPORTED__', $sel);
    my $cfg = dclone($$self{_COPY}{'data'});
    delete $$self{_COPY}{'data'}{'children'};

    # Restore the original configuration
    $$self{_CFG}{'environments'} = $backup_cfg;

    require YAML;
    if (YAML::DumpFile($file, $cfg)) {
        $w->destroy();
        _wMessage($$self{_WINDOWCONFIG}, "Connection(s) succesfully exported to:\n\n$file");
    } else {
        $w->destroy();
        _wMessage($$self{_WINDOWCONFIG}, "ERROR: Could not export connection(s) to file '$file':\n\n$!");
    }

    return 1;
}

sub __importNodes {
    my $self = shift;

    my @sel = $$self{_GUI}{treeConnections}->_getSelectedUUIDs();

    my $parent_uuid = $sel[0];
    my $parent_name = $$self{_CFG}{'environments'}{$sel[0]}{'name'};

    my $choose = Gtk3::FileChooserDialog->new(
        "$APPNAME (v.$APPVERSION) Choose a YAML file to Import",
        $$self{_WINDOWCONFIG},
        'GTK_FILE_CHOOSER_ACTION_OPEN',
        'Import' , 'GTK_RESPONSE_ACCEPT',
        'Cancel' , 'GTK_RESPONSE_CANCEL',
    );
    $choose->set_do_overwrite_confirmation(1);
    $choose->set_current_folder($ENV{'HOME'} // '/tmp');
    my $filter = Gtk3::FileFilter->new;
    $filter->set_name('YAML Files');
    $filter->add_pattern('*.yml');
    $choose->add_filter($filter);

    my $out = $choose->run;
    my $file = $choose->get_filename;
    $choose->destroy();
    if (($out ne 'accept') || (!-f $file) || ($file !~ /^(.+)\.yml$/go)) {
        return 1;
    }

    my $w = _wMessage($$self{_GUI}{main}, "Please, wait while file '$file' is being imported...", 0);
    Gtk3::main_iteration while Gtk3::events_pending;

    require YAML;
    Gtk3::main_iteration while Gtk3::events_pending;
    eval { $$self{_COPY}{'data'} = YAML::LoadFile($file); };
    if ($@) {
        $w->destroy();
        _wMessage($$self{_WINDOWCONFIG}, "ERROR: Could not import connection from file '$file':\n\n$@");
        return 1;
    }

    Gtk3::main_iteration while Gtk3::events_pending;

    # Full export file? (including config!)
    if (defined $$self{_COPY}{'data'}{'__PAC__EXPORTED__FULL__'}) {
        if (! _wConfirm($$self{_GUI}{main}, "Selected config file is a <b>FULL</b> backup.\nImporting it will result in all current data being <b>substituted</b> by the new one.\n<b>Plus, it REQUIRES restarting the application</b>.\nReplace current configuration?")) {
            delete $$self{_COPY}{'data'}{'children'};
            $w->destroy();
            return 1;
        }

        Gtk3::main_iteration while Gtk3::events_pending;
        @{ $$self{_GUI}{treeConnections}{'data'} } = ();
        @{ $$self{_GUI}{treeConnections}{'data'} } = ({
            value => [ $GROUPICON_ROOT, '<b>AVAILABLE CONNECTIONS</b>', '__PAC__ROOT__' ],
            children => []
        });
        Gtk3::main_iteration while Gtk3::events_pending;

        copy($file, $CFG_FILE) and unlink $CFG_FILE_NFREEZE;
        delete $$self{_CFG};
        $self->_readConfiguration(0);
        $self->_loadTreeConfiguration('__PAC__ROOT__');
        delete $$self{_COPY}{'data'};
        $w->destroy();
        $self->_setCFGChanged(1);
        delete $$self{_CFG}{'__PAC__EXPORTED__'};
        delete $$self{_CFG}{'__PAC__EXPORTED__FULL__'};
        _wMessage($$self{_WINDOWCONFIG}, "File '$file' succesfully imported.\n now <b>restarting</b> (wait 3 seconds...)", 0);
        system("(sleep 3; $0) &");
        sleep 2;
        exit 0;

    # Bad export file
    } elsif (! defined $$self{_COPY}{'data'}{'__PAC__EXPORTED__'}) {
        delete $$self{_COPY}{'data'}{'children'};
        $w->destroy();
        _wMessage($$self{_WINDOWCONFIG}, "File '$file' does not look like a valid exported connection!");
        return 1;

    # Correct partial export file
    } else {
        my $i = 0;
        foreach my $child (keys %{ $$self{_COPY}{'data'}{'__PAC__EXPORTED__'}{'children'} }) {
            $self->_pasteNodes($parent_uuid, $child);
            ++$i;
        }
        $$self{_COPY}{'data'} = {};
        _decipherCFG($$self{_CFG});
        $w->destroy();
        _wMessage($$self{_WINDOWCONFIG}, "File '<b>$file</b>' succesfully imported:\n<b>$i</b> element(s) added");
        delete $$self{_CFG}{'__PAC__EXPORTED__'};
        delete $$self{_CFG}{'__PAC__EXPORTED__FULL__'};
        $self->_setCFGChanged(1);
    }

    if ($UNITY) {
        $FUNCS{_TRAY}->_setTrayMenu;
    }

    return 1;
}

sub _bulkEdit {
    my $self = shift;
    my $title = shift // "$APPNAME (v$APPVERSION) : Bulk Edit";
    my $label = shift // "Select and change the values you want to modify in the list below.\n<b>Only those checked will be affected.</b>\nFor Regular Expressions, <b>Match pattern</b> will be substituted with <b>New value</b>,\nmuch like Perl's: <b>s/Match pattern/New value/g</b>";
    my $groups = shift // 0;
    my $cipher = shift // 0;
    my %list;
    my %w;

    # Create the 'bulkEdit' dialog window,
    $w{data} = Gtk3::Dialog->new_with_buttons(
        $title,
        undef,
        'modal',
        'gtk-ok' => 'ok',
        'gtk-cancel' => 'cancel'
    );

    $w{data}->signal_connect('delete_event' => sub {
        $w{data}->destroy();
        undef %w;
        return 1;
    });

    # and setup some dialog properties.
    $w{data}->set_border_width(5);
    $w{data}->set_position('center');
    $w{data}->set_icon_from_file($APPICON);
    $w{data}->set_resizable(0);
    $w{data}->set_default_response('ok');

    $w{gui}{hboxIconLabel} = Gtk3::HBox->new(0, 5);
    $w{data}->get_content_area->pack_start($w{gui}{hboxIconLabel}, 0, 1, 5);

    $w{gui}{imgUP} = Gtk3::Image-> new_from_stock('gtk-edit', 'dialog');
    $w{gui}{hboxIconLabel}->pack_start($w{gui}{imgUP}, 0, 1, 0);

    $w{gui}{lblUP} = Gtk3::Label->new;
    $w{gui}{lblUP}->set_markup($label);
    $w{gui}{hboxIconLabel}->pack_start($w{gui}{lblUP}, 0, 1, 0);

    $w{data}->get_content_area->pack_start(Gtk3::HSeparator->new, 0, 1, 0);

    #$w{gui}{frameAffect} = Gtk3::Frame->new(' There are GROUP(S) in the selection. Apply to: ');
    $w{gui}{frameAffect} = Gtk3::Frame->new;
    my $lblaffect = Gtk3::Label->new;
    $lblaffect->set_markup(' There are <b>GROUP(S)</b> in the selection. Apply to: ');
    $w{gui}{frameAffect}->set_label_widget($lblaffect);
    $w{data}->get_content_area->pack_start($w{gui}{frameAffect}, 0, 1, 0);

    $w{gui}{vboxaffect} = Gtk3::VBox->new(0, 0);
    $w{gui}{frameAffect}->add($w{gui}{vboxaffect});

    $w{gui}{rb1level} = Gtk3::RadioButton->new_with_label('level affected', "1st level children");
    $w{gui}{vboxaffect}->pack_start($w{gui}{rb1level}, 0, 1, 0);
    $w{gui}{rballlevel} = Gtk3::RadioButton->new_with_label_from_widget($w{gui}{rb1level}, "ALL sub-levels children");
    $w{gui}{vboxaffect}->pack_start($w{gui}{rballlevel}, 0, 1, 0);

    # Create a vbox for the list os elements to bulk-edit
    $w{gui}{vboxlist} = Gtk3::VBox->new(0, 0);
    $w{data}->get_content_area->pack_start($w{gui}{vboxlist}, 1, 1, 0);

    $w{gui}{framecommon} = Gtk3::Frame->new;
    my $lblcom = Gtk3::Label->new;
    $lblcom->set_markup(' <b><span foreground="orange">COMMON</span></b> entries: ');
    $w{gui}{framecommon}->set_label_widget($lblcom);
    $w{data}->get_content_area->pack_start($w{gui}{framecommon}, 0, 1, 0);

    $w{gui}{vboxcommon} = Gtk3::VBox->new(0, 0);
    $w{gui}{framecommon}->add($w{gui}{vboxcommon});

    # Build the COMMON elements
    foreach my $key ('title', 'ip', 'port', 'user', 'pass', 'passphrase user', 'passphrase') {
        $w{gui}{"hb$key"} = Gtk3::HBox->new(0, 0);
        $w{gui}{vboxcommon}->pack_start($w{gui}{"hb$key"}, 0, 1, 0);

        $w{gui}{"cb$key"} = Gtk3::CheckButton->new("Set '$key': ");
        $w{gui}{"hb$key"}->pack_start($w{gui}{"cb$key"}, 0, 1, 0);
        $w{gui}{"cb$key"}->set('can_focus', 0);

        $w{gui}{"hboxre$key"} = Gtk3::HBox->new(0, 0);
        $w{gui}{"hb$key"}->pack_start($w{gui}{"hboxre$key"}, 1, 1, 0);

        $w{gui}{"hboxre$key"}->pack_start(Gtk3::Label->new('change '), 0, 1, 0);

        $w{gui}{"entryWhat$key"} = Gtk3::Entry->new;
        $w{gui}{"hboxre$key"}->pack_start($w{gui}{"entryWhat$key"}, 1, 1, 0);
        $w{gui}{"entryWhat$key"}->set_activates_default(1);
        $w{gui}{"entryWhat$key"}->hide();

        $w{gui}{"hboxre$key"}->pack_start(Gtk3::Label->new(' with '), 0, 1, 0);

        $w{gui}{"entry$key"} = Gtk3::Entry->new;
        $w{gui}{"hb$key"}->pack_start($w{gui}{"entry$key"}, 1, 1, 0);
        $w{gui}{"entry$key"}->set_activates_default(1);

        $w{gui}{"cbRE$key"} = Gtk3::CheckButton->new('RegExp');
        $w{gui}{"hb$key"}->pack_start($w{gui}{"cbRE$key"}, 0, 1, 0);
        $w{gui}{"cbRE$key"}->set('can_focus', 0);
        $w{gui}{"cbRE$key"}->set_active(1);

        $w{gui}{"image$key"} = Gtk3::Image->new_from_stock('gtk-edit', 'button');
        $w{gui}{"hb$key"}->pack_start($w{gui}{"image$key"}, 0, 1, 0);

        # And setup some signals
        $w{gui}{"entry$key"}->signal_connect('changed', sub { $w{gui}{"cb$key"}->set_active($w{gui}{"entry$key"}->get_chars(0, -1) ne ''); });
        $w{gui}{"cb$key"}->signal_connect('toggled', sub { $w{gui}{"image$key"}->set_from_stock(($w{gui}{"cb$key"}->get_active() ? 'gtk-ok' : 'gtk-edit'), 'button'); });
        $w{gui}{"cbRE$key"}->signal_connect('toggled', sub { $w{gui}{"cbRE$key"}->get_active() ? $w{gui}{"hboxre$key"}->show : $w{gui}{"hboxre$key"}->hide(); });

        # Asign a callback to populate this entry with its own context menu
        $w{gui}{"entry$key"}->signal_connect('button_press_event' => sub {
            my ($widget, $event) = @_;
            return 0 unless $event->button eq 3;
            my @menu_items;

            # Populate with global defined variables
            my @global_variables_menu;
            foreach my $var (sort { $a cmp $b } keys %{ $PACMain::FUNCS{_MAIN}{_CFG}{'defaults'}{'global variables'} }) {
                my $val = $PACMain::FUNCS{_MAIN}{_CFG}{'defaults'}{'global variables'}{$var}{'value'};
                push(@global_variables_menu, {
                    label => "<GV:$var> ($val)",
                    code => sub { $w{gui}{"entry$key"}->insert_text("<GV:$var>", -1, $w{gui}{"entry$key"}->get_position()); }
                    });
                }
                push(@menu_items, {
                    label => 'Global variables...',
                    sensitive => scalar(@global_variables_menu),
                    submenu => \@global_variables_menu
                });

                # Populate with environment variables
                my @environment_menu;
                foreach my $key (sort { $a cmp $b } keys %ENV) {
                    my $value = $ENV{$key};
                    push(@environment_menu, {
                        label => "<ENV:$key>",
                        tooltip => "$key=$value",
                        code => sub { $w{gui}{"entry$key"}->insert_text("<ENV:$key>", -1, $w{gui}{"entry$key"}->get_position()); }
                    });
                }
                push(@menu_items, {
                    label => 'Environment variables...',
                    submenu => \@environment_menu
                });
                # Put an option to ask user for variable substitution
                push(@menu_items, {
                    label => 'Runtime substitution (<ASK:change_by_number>)',
                    code => sub {
                        my $pos = $w{gui}{"entry$key"}->get_property('cursor_position');
                        $w{gui}{"entry$key"}->insert_text("<ASK:change_by_number>", -1, $w{gui}{"entry$key"}->get_position());
                        $w{gui}{"entry$key"}->select_region($pos + 5, $pos + 21);
                    }
                });
                # Populate with <ASK:*|> special string
                push(@menu_items, {
                    label => 'Interactive user choose from list',
                    tooltip => 'User will be prompted to choose a value form a user defined list separated with "|" (pipes without quotes)',
                    code => sub {
                        my $pos = $w{gui}{"entry$key"}->get_property('cursor_position');
                        $w{gui}{"entry$key"}->insert_text('<ASK:descriptive line|opt1|opt2|...|optN>', -1, $w{gui}{"entry$key"}->get_position());
                        $w{gui}{"entry$key"}->select_region($pos + 5, $pos + 40);
                    }
                });
                # Populate with <CMD:*> special string
                push(@menu_items, {
                    label => 'Use a command output as value',
                    tooltip => 'The given command line will be locally executed, and its output (both STDOUT and STDERR) will be used to replace this value',
                    code => sub {
                        my $pos = $w{gui}{"entry$key"}->get_property('cursor_position');
                        $w{gui}{"entry$key"}->insert_text('<CMD:command to launch>', -1, $w{gui}{"entry$key"}->get_position());
                        $w{gui}{"entry$key"}->select_region($pos + 5, $pos + 22);
                    }
                });
                # Populate with <KPX_(title|username|url):*> special string
                if ($PACMain::FUNCS{_MAIN}{_CFG}{'defaults'}{'keepass'}{'use_keepass'}) {
                    my (@titles, @usernames, @urls);
                    foreach my $hash ($PACMain::FUNCS{_KEEPASS}->find) {
                        push(@titles, {
                            label => "<KPX_title:$$hash{title}>",
                            tooltip => "$$hash{password}",
                            code => sub { $w{gui}{"entry$key"}->insert_text("<KPX_title:$$hash{title}>", -1, $w{gui}{"entry$key"}->get_position()); }
                        });
                        push(@usernames, {
                            label => "<KPX_username:$$hash{username}>",
                            tooltip => "$$hash{password}",
                            code => sub { $w{gui}{"entry$key"}->insert_text("<KPX_username:$$hash{username}>", -1, $w{gui}{"entry$key"}->get_position()); }
                        });
                        push(@urls, {
                            label => "<KPX_url:$$hash{url}>",
                            tooltip => "$$hash{password}",
                            code => sub { $w{gui}{"entry$key"}->insert_text("<KPX_url:$$hash{url}>", -1, $w{gui}{"entry$key"}->get_position()); }
                        });
                    }
                    push(@menu_items, {
                        label => 'KeePassX',
                        stockicon => 'pac-keepass',
                        submenu => [
                            {
                                label => 'KeePassX title values',
                                submenu => \@titles
                            }, {
                                label => 'KeePassX username values',
                                submenu => \@usernames
                            }, {
                                label => 'KeePassX URL values',
                                submenu => \@urls
                            }, {
                                label => "KeePass Extended Query",
                                tooltip => "This allows you to select the value to be returned, based on another value's match againt a Perl Regular Expression",
                                code => sub { $w{gui}{"entry$key"}->insert_text("<KPXRE_GET_(title|username|password|url)_WHERE_(title|username|password|url)==Your_RegExp_here==>", -1, $w{gui}{"entry$key"}->get_position()); }
                            }
                        ]
                    });
                }

                _wPopUpMenu(\@menu_items, $event);

                return 1;
        });
    }

    $w{gui}{frameExpect} = Gtk3::Frame->new;
    my $lblexp = Gtk3::Label->new;
    $lblexp->set_markup(' <b><span foreground="orange">EXPECT</span></b> entries: ');
    $w{gui}{frameExpect}->set_label_widget($lblexp);
    $w{data}->get_content_area->pack_start($w{gui}{frameExpect}, 0, 1, 0);

    $w{gui}{vboxexpect} = Gtk3::VBox->new(0, 0);
    $w{gui}{frameExpect}->add($w{gui}{vboxexpect});

    # Build the EXPECT elements
    foreach my $key ('expect', 'send') {
        $w{gui}{"hb$key"} = Gtk3::HBox->new(0, 0);
        $w{gui}{vboxexpect}->pack_start($w{gui}{"hb$key"}, 0, 1, 0);

        $w{gui}{"cb$key"} = Gtk3::CheckButton->new("Set '$key': ");
        $w{gui}{"hb$key"}->pack_start($w{gui}{"cb$key"}, 0, 1, 0);
        $w{gui}{"cb$key"}->set('can_focus', 0);

        $w{gui}{"hboxre$key"} = Gtk3::HBox->new(0, 0);
        $w{gui}{"hb$key"}->pack_start($w{gui}{"hboxre$key"}, 1, 1, 0);

        $w{gui}{"hboxre$key"}->pack_start(Gtk3::Label->new('change '), 0, 1, 0);

        $w{gui}{"entryWhat$key"} = Gtk3::Entry->new;
        $w{gui}{"hboxre$key"}->pack_start($w{gui}{"entryWhat$key"}, 1, 1, 0);
        $w{gui}{"entryWhat$key"}->set_activates_default(1);
        $w{gui}{"entryWhat$key"}->hide();

        $w{gui}{"hboxre$key"}->pack_start(Gtk3::Label->new(' with '), 0, 1, 0);

        $w{gui}{"entry$key"} = Gtk3::Entry->new;
        $w{gui}{"hb$key"}->pack_start($w{gui}{"entry$key"}, 1, 1, 0);
        $w{gui}{"entry$key"}->set_activates_default(1);

        $w{gui}{"cbRE$key"} = Gtk3::CheckButton->new('RegExp');
        $w{gui}{"hb$key"}->pack_start($w{gui}{"cbRE$key"}, 0, 1, 0);
        $w{gui}{"cbRE$key"}->set('can_focus', 0);
        $w{gui}{"cbRE$key"}->set_active(1);

        $w{gui}{"image$key"} = Gtk3::Image->new_from_stock('gtk-edit', 'button');
        $w{gui}{"hb$key"}->pack_start($w{gui}{"image$key"}, 0, 1, 0);

        # And setup some signals
        $w{gui}{"entry$key"}->signal_connect('changed', sub { $w{gui}{"cb$key"}->set_active($w{gui}{"entry$key"}->get_chars(0, -1) ne ''); });
        $w{gui}{"cb$key"}->signal_connect('toggled', sub { $w{gui}{"image$key"}->set_from_stock(($w{gui}{"cb$key"}->get_active() ? 'gtk-ok' : 'gtk-edit'), 'button'); });
        $w{gui}{"cbRE$key"}->signal_connect('toggled', sub { $w{gui}{"cbRE$key"}->get_active() ? $w{gui}{"hboxre$key"}->show : $w{gui}{"hboxre$key"}->hide(); });

        # Asign a callback to populate this entry with its own context menu
        $w{gui}{"entry$key"}->signal_connect('button_press_event' => sub {
            my ($widget, $event) = @_;

            return 0 unless $event->button eq 3;

            my @menu_items;

            # Populate with global defined variables
            my @global_variables_menu;
            foreach my $var (sort { $a cmp $b } keys %{ $PACMain::FUNCS{_MAIN}{_CFG}{'defaults'}{'global variables'} }) {
                my $val = $PACMain::FUNCS{_MAIN}{_CFG}{'defaults'}{'global variables'}{$var}{'value'};
                push(@global_variables_menu, {
                    label => "<GV:$var> ($val)",
                    code => sub { $w{gui}{"entry$key"}->insert_text("<GV:$var>", -1, $w{gui}{"entry$key"}->get_position()); }
                });
            }
            push(@menu_items, {
                label => 'Global variables...',
                sensitive => scalar(@global_variables_menu),
                submenu => \@global_variables_menu
            });
            # Populate with environment variables
            my @environment_menu;
            foreach my $key (sort { $a cmp $b } keys %ENV) {
                my $value = $ENV{$key};
                push(@environment_menu, {
                    label => "<ENV:$key>",
                    tooltip => "$key=$value",
                    code => sub { $w{gui}{"entry$key"}->insert_text("<ENV:$key>", -1, $w{gui}{"entry$key"}->get_position()); }
                });
            }
            push(@menu_items, {
                label => 'Environment variables...',
                submenu => \@environment_menu
            });

            # Put an option to ask user for variable substitution
            push(@menu_items, {
                label => 'Runtime substitution (<ASK:change_by_number>)',
                code => sub {
                    my $pos = $w{gui}{"entry$key"}->get_property('cursor_position');
                    $w{gui}{"entry$key"}->insert_text("<ASK:change_by_number>", -1, $w{gui}{"entry$key"}->get_position());
                    $w{gui}{"entry$key"}->select_region($pos + 5, $pos + 21);
                }
            });

            # Populate with <ASK:*|> special string
            push(@menu_items, {
                label => 'Interactive user choose from list',
                tooltip => 'User will be prompted to choose a value form a user defined list separated with "|" (pipes without quotes)',
                code => sub {
                    my $pos = $w{gui}{"entry$key"}->get_property('cursor_position');
                    $w{gui}{"entry$key"}->insert_text('<ASK:descriptive line|opt1|opt2|...|optN>', -1, $w{gui}{"entry$key"}->get_position());
                    $w{gui}{"entry$key"}->select_region($pos + 5, $pos + 40);
                }
            });

            # Populate with <CMD:*> special string
            push(@menu_items, {
                label => 'Use a command output as value',
                tooltip => 'The given command line will be locally executed, and its output (both STDOUT and STDERR) will be used to replace this value',
                code => sub {
                    my $pos = $w{gui}{"entry$key"}->get_property('cursor_position');
                    $w{gui}{"entry$key"}->insert_text('<CMD:command to launch>', -1, $w{gui}{"entry$key"}->get_position());
                    $w{gui}{"entry$key"}->select_region($pos + 5, $pos + 22);
                }
            });

            # Populate with <KPX_(title|username|url):*> special string
            if ($PACMain::FUNCS{_MAIN}{_CFG}{'defaults'}{'keepass'}{'use_keepass'}) {
                my (@titles, @usernames, @urls);
                foreach my $hash ($PACMain::FUNCS{_KEEPASS}->find) {
                    push(@titles, {
                        label => "<KPX_title:$$hash{title}>",
                        tooltip => "$$hash{password}",
                        code => sub { $w{gui}{"entry$key"}->insert_text("<KPX_title:$$hash{title}>", -1, $w{gui}{"entry$key"}->get_position()); }
                    });
                    push(@usernames, {
                        label => "<KPX_username:$$hash{username}>",
                        tooltip => "$$hash{password}",
                        code => sub { $w{gui}{"entry$key"}->insert_text("<KPX_username:$$hash{username}>", -1, $w{gui}{"entry$key"}->get_position()); }
                    });
                    push(@urls, {
                        label => "<KPX_url:$$hash{url}>",
                        tooltip => "$$hash{password}",
                        code => sub { $w{gui}{"entry$key"}->insert_text("<KPX_url:$$hash{url}>", -1, $w{gui}{"entry$key"}->get_position()); }
                    });
                }

                push(@menu_items, {
                    label => 'KeePassX',
                    stockicon => 'pac-keepass',
                    submenu => [
                        {
                            label => 'KeePassX title values',
                            submenu => \@titles
                        }, {
                            label => 'KeePassX username values',
                            submenu => \@usernames
                        }, {
                            label => 'KeePassX URL values',
                            submenu => \@urls
                        }, {
                            label => "KeePass Extended Query",
                            tooltip => "This allows you to select the value to be returned, based on another value's match againt a Perl Regular Expression",
                            code => sub { $w{gui}{"entry$key"}->insert_text("<KPXRE_GET_(title|username|password|url)_WHERE_(title|username|password|url)==Your_RegExp_here==>", -1, $w{gui}{"entry$key"}->get_position()); }
                        }
                    ]
                });
            }

            _wPopUpMenu(\@menu_items, $event);

            return 1;
        });
    }

    $w{gui}{cbDelHidden} = Gtk3::CheckButton->new("Remove strings checked 'Hide' from the 'Expect' configuration");
    $w{gui}{vboxexpect}->pack_start($w{gui}{cbDelHidden}, 0, 1, 0);
    $w{gui}{cbDelHidden}->set_tooltip_text("If checked, every field marked as 'hide' (for example, under 'Expect' TAB) will be erased.\nThis overrides any value set for both 'pass' and 'passphrase'");

    if ($cipher) {
        $w{gui}{cbCipher} = Gtk3::CheckButton->new("Cipher secure strings");
        $w{data}->get_content_area->pack_start($w{gui}{cbCipher}, 0, 1, 0);
        $w{gui}{cbCipher}->set_tooltip_text("If checked, every passord-like and field marked as 'hide' (for example, under 'Expect' TAB) will be ciphered.\nThis may cause incompatibilities when importing from a server other than this.");
    }

    $w{data}->get_content_area->pack_start(Gtk3::HSeparator->new, 0, 1, 0);

    $w{data}->show_all();
    $groups or $w{gui}{frameAffect}->hide();
    if ($w{data}->run ne 'ok') {
        defined $w{data} and $w{data}->destroy();
        return undef;
    }

    # Get the GUI data
    foreach my $key ('title', 'ip', 'port', 'user', 'pass', 'passphrase user', 'passphrase', 'expect', 'send') {
        my $tkey = $key;
        ($key eq 'expect') and $tkey = 'EXPECT:' . $key;
        ($key eq 'send')  and $tkey = 'EXPECT:' . $key;
        $list{$tkey}{change} = $w{gui}{"cb$key"}->get_active();
        $list{$tkey}{match} = $w{gui}{"entryWhat$key"}->get_chars(0, -1);
        $list{$tkey}{value} = $w{gui}{"entry$key"}->get_chars(0, -1);
        $list{$tkey}{regexp} = $w{gui}{"cbRE$key"}->get_active();
    }
    $list{'__delete_hidden_fields__'} = $w{gui}{cbDelHidden}->get_active();

    $w{data}->destroy();
    return \%list, $w{gui}{rballlevel}->get_active(), $cipher ? $w{gui}{cbCipher}->get_active() : undef;
}

sub _setCFGChanged {
    my $self = shift;
    my $stat = shift;

    if ($$self{_READONLY}) {
        $$self{_GUI}{saveBtn}->set_label('READ ONLY INSTANCE');
        $$self{_GUI}{saveBtn}->set_sensitive(0);
    } elsif ($$self{_CFG}{defaults}{'auto save'}) {
        $$self{_GUI}{saveBtn}->set_label('Auto saving ACTIVE');
        $$self{_GUI}{saveBtn}->set_tooltip_text('Every configuration change will be saved automatically.  You can disable this feature in Preferences > Main Options.');
        $$self{_GUI}{saveBtn}->set_sensitive(0);
        $self->_saveConfiguration(undef, 0);
    } else {
        $$self{_CFG}{tmp}{changed} = $stat;
        $$self{_GUI}{saveBtn}->set_sensitive($stat);
        $$self{_GUI}{saveBtn}->set_label('_Save');
        $$self{_GUI}{saveBtn}->set_tooltip_text('Save your configuration');
    }
    return 1;
}

# Sends a message to the Ásbrú application that is already running
sub _sendAppMessage {
    my $app = shift;
    my $msg = shift;
    my $text = shift // '';

    # Do not open any file but pass the message as 'hint'
    $app->open ([], $msg.'|'.$text);
}

# Set and recover conflictive options
sub _setSafeLayoutOptions {
    my ($self,$layout) = @_;

    if ($layout eq 'Compact') {
        # This layout to work implies some configuration settings to work correctly
        $$self{_CFG}{'defaults'}{'tabs in main window'} = 0;
        $$self{_CFG}{'defaults'}{'auto hide connections list'} = 0;
        if ($ENV{'ASBRU_DESKTOP'} eq 'gnome-shell') {
            $$self{_CFG}{'defaults'}{'start iconified'} = 0;
        } else {
            $$self{_CFG}{'defaults'}{'close to tray'} = 1;
        }
    } else {
        # Traditional
        if ((!defined $$self{_CFG}{'defaults'}{'layout traditional settings'})||($$self{_CFG}{'defaults'}{'layout previous'} eq $layout)) {
            # Load current traditional options that are changed in Compact mode
            $$self{_CFG}{'defaults'}{'lt tabs in main window'} = $$self{_CFG}{'defaults'}{'tabs in main window'};
            $$self{_CFG}{'defaults'}{'layout traditional settings'} = 1;
            $$self{_CFG}{'defaults'}{'lt start iconified'} = $$self{_CFG}{'defaults'}{'start iconified'};
            $$self{_CFG}{'defaults'}{'lt close to tray'} = $$self{_CFG}{'defaults'}{'close to tray'};
            $$self{_CFG}{'defaults'}{'lt auto save'} = $$self{_CFG}{'defaults'}{'auto save'};
        } elsif (($$self{_CFG}{'defaults'}{'layout previous'} ne $layout) && (defined defined $$self{_CFG}{'defaults'}{'layout traditional settings'})) {
            # Recover previous know settings after comming back from compact layout
            $$self{_CFG}{'defaults'}{'tabs in main window'} = $$self{_CFG}{'defaults'}{'lt tabs in main window'};
            $$self{_CFG}{'defaults'}{'start iconified'} = $$self{_CFG}{'defaults'}{'lt start iconified'};
            $$self{_CFG}{'defaults'}{'close to tray'} = $$self{_CFG}{'defaults'}{'lt close to tray'};
            $$self{_CFG}{'defaults'}{'auto save'} = $$self{_CFG}{'defaults'}{'lt auto save'};
        }
    }
    $$self{_CFG}{'defaults'}{'layout previous'} = $layout;
}

# Apply layout to window and widgets
sub _ApplyLayout {
    my ($self,$layout) = @_;

    if ($layout eq 'Compact') {
        # This layout to work implies some configuration settings to work correctly
        foreach my $e ('hbuttonbox1','connSearch','connExecBtn','connQuickBtn','connFavourite','vbox5','vboxInfo') {
            $$self{_GUI}{$e}->hide();
        }
        if ($ENV{'ASBRU_DESKTOP'} eq 'gnome-shell') {
            if (!$$self{_GUI}{main}->get_visible) {
                $self->_showConnectionsList;
            }
        } else {
            if ($$self{_GUI}{main}->get_visible) {
                $self->_hideConnectionsList();
            }
        }
        $$self{_GUI}{main}->set_default_size(220,600);
        $$self{_GUI}{main}->resize(220,600);
    }
}

# END: Define PRIVATE CLASS functions
###################################################################

1;

__END__

=encoding utf8

=head1 NAME

PACMain.pm

=head1 SYNOPSIS

Creates the GTK application, main window, event handlers, and elements.

    $main = PACMain->new(@ARGV);

B<@ARGV> : List of command line parameters (perldoc asbru-cm)

=head1 DESCRIPTION

=head2 Important Global Variables

    %RUNNING :  Table of PACTerminal Objects. $RUNNING{UUID}
                For a description of Terminal objects (perldoc PACTerminal.pm)

B<UUID> = 'pac_PID' + I<pid number> + '_n' + I<Counter>

=head2 PACMain Internal Variables

    _APP            : Main Gtk object
    _CFG            : Reference tu structure object loaded by YAML::LoadFile
    _OPTS           : User options from command line
    _GUI            : Access to Gtk elements of the application (defined at _initGUI)
    _TABSINWINDOW   : 0 No , 1 Yes
    _UPDATING       : 0 No , 1 Yes
    _READONLY       : 0 No , 1 Yes
    _HAS_FOCUS      : VTE Object with the current focus
    _GUILOCKED      : 0 No , 1 Yes
    _PING           : Access to Net::Ping object

=head3 _CFG

Check asbru.yml for a reference for the complete list of options

    default         Access to global options
    environments    List of UUIDS in the nodes tree
    tmp             Access to temporary file references

    Example access:

    $$self{'_CFG'}{'defaults'}{'allow more instances'}
    $$self{'_CFG'}{'environments'}{$uuid}{'_protected'}

=head3 _GUI

Check _initGUI for object names

    Example access:

    $$self{'_GUI'}{object_name}      (as named in _initGUI)


=head2 sub new

    Creates a new instance of PACMain

=head2 sub DESTROY

    Destroys object when finished

=head2 sub start

    Start GTK application

=head2 sub _initGUI

Creates the main window and elements

=head2 sub _setupCallbacks

Sets up all callbacks to elements in the window

=head2 sub _lockPAC

Locks Pack to leave unatended.

Sets different objects property sesitive = 0

=head2 sub _unlockPAC

Asks for a GUI Password to unlock variables

If password OK, set sensitive = 1

=head2 sub __search (text,tree,where)

Search action over nodes : {CFG}{environments}{uuid}{name,ip,description}

    text    text to search
    tree    gtk tree object to search from
    where   name , host or desc

=head2 sub __treeSort ()

Sorts nodes tree by alphaetical order

=head2 sub __treeBuildNodeName (uuid)

Gets node name as html tags applied with color depending on protected status

=head2 sub _hasProtectedChildren (@uuids[,search children])

Range over uuids to determine if node or any children are protected

=head2 sub __treeToggleProtection

Protects the full tree of nodes

=head2 sub _treeConnections_menu_lite (tree)

Creates a window popup menu for selected nodes

=head2 sub _treeConnections_menu

Create window popup on right click over connections tree

It will enable or disable options based on:

  * if there are elements selected
  * if there are elements to paste

=head2 sub _showAboutWindow

Shows about window

=head2 sub _startCluster (cluster name)

Start a cluster

    Finds all related nodes
    adds them to array @idx
    Calls _launchTerminals(\@ids), to start all toguether

=head2 sub _launchTerminals (@array_reference)

    Calls PACTerminal->new() for each $uuid in array_reference

=head2 sub _quitProgram

Execute quit program logic.

    Close terminals
    Ask for confirmations
    Gtk->main_quit

=head2 sub _saveConfiguration (_CFG)

Saves configuration data to $CFG_DIR

Saves Tree configuration

Last state en nfreez

=head2 sub _readConfiguration

Reads Configuraions into _CFG

=head2 sub _loadTreeConfiguration

Loads the last saved Tree Configuration using __recurLoadTree

=head2 sub __recurLoadTree

Recursively loads all tree configuration

=head2 sub _saveTreeExpanded

Saves configuration about node tree expanded in $CFG_FILE.tree

=head2 sub _loadTreeExpanded

Loas last information of expanded nodes from $CFG_FILE.tree

=head2 sub _saveGUIData

Saves general information about the GUI : x,y position and dimentions

=head2 sub _loadGUIData

Loads last saves GUI Data

=head2 sub _updateGUIWithUUID

Displays Welcome information in Message Area

=head2 sub _updateGUIPreferences

Update runtime GUI Preferences

=head2 sub _updateGUIFavourites

Updates GUI Favorites

Updates GUII Favorites

=head2 sub _updateGUIHistory

Updates information on History

=head2 sub _updateGUIClusters

Updates Clusters

=head2 sub _updateClustersList

Updates cluster List

=head2 sub _updateFavouritesList

Update Favourited List

=head2 sub _delNodes (@uuids)

Deletes all @uuids from the nodes tree

=head2 sub _showConnectionsList

Pending

=head2 sub _hideConnectionsList

Hides the Connections list

=head2 sub _toggleConnectionsList

Toggles Connection Lista (active, inactie)

=head2 sub _copyNodes (cut [0,'cut'], parent, @selected_uuids)

For each uuid, execute __dupNodes()

This duplicates nodes in memory, storing the nodes in : $$self{_COPY}{'data'}

if cut == true { removes existing nodes from the tree }

=head2 sub _cutNodes ()

Event Handler

Gets Selected UUIDS, validates they are not protected

Calls _copyNodes('cut')

=head2 sub _pasteNodes (parent, uuid_to_copy, first)

Creates a new node on $parent root, then adds a node and possible children that come in : $$self{_COPY}{'data'}

Calls _pasteNodes for each children

=head2 sub __dupNodes (parent, uuid, cfg)

    Creates a copy of the existing uuid and assigns secuencial number to new node
    The copies are stored in $cfg which points to -> $$self{_COPY}{'data'}
    If node has children calls recusively to add children nodes, taking as parent the current new node
      $self->__dupNodes($new_txt_uuid, $child, $cfg);

=head2 sub __exportNodes

Exporst current nodes to file

=head2 sub __importNodes

Imports nodes from previous generated file

=head2 sub _bulkEdit

Creates GUI for a bulk editing of common properties to all selected nodes

=head2 sub _setCFGChanged

Updates runtime Configuration changes that affect the Main GUI: Readonly, Auto Save

=head2 sub _sendAppMessage

Pending

