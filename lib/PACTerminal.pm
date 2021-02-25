package PACTerminal;

###############################################################################
# This file is part of Ásbrú Connection Manager
#
# Copyright (C) 2017-2021 Ásbrú Connection Manager team (https://asbru-cm.net)
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

# Standard
use strict;
use warnings;

use FindBin qw ($RealBin $Bin $Script);
use lib "$RealBin/lib", "$RealBin/lib/ex";
use Storable qw (dclone nstore nstore_fd fd_retrieve);
use POSIX qw (strftime);
use File::Copy;
use Encode qw (encode decode);
use IO::Socket::INET;
use Time::HiRes qw (gettimeofday);
use PACKeePass;
use List::Util qw(min max);

# GTK
use Gtk3 '-init';
use Gtk3::SimpleList;
use Gtk3::Gdk;
eval {require Gtk3::SourceView2;};
my $SOURCEVIEW = ! $@;

# Ásbrú utilities
use PACUtils;

# VteTerminal (terminal widget)
use Vte;

# END: Import Modules
###################################################################

###################################################################
# Define GLOBAL CLASS variables

my $APPNAME = $PACUtils::APPNAME;
my $APPVERSION = $PACUtils::APPVERSION;
my $APPICON = "$RealBin/res/asbru-logo-64.png";
my $CFG_DIR = $ENV{"ASBRU_CFG"};

my $PERL_BIN = '/usr/bin/perl';
my $PAC_CONN = "$RealBin/lib/asbru_conn";

my $SHELL_BIN = -x '/bin/sh' ? '/bin/sh' : '/bin/bash';
my $SHELL_NAME = -x '/bin/sh' ? 'sh' : 'bash';

my $_C = 1;
my $EXEC_STORM_TIME = 0.2;

my @KPX;

my $NPOSX = 0;
my $NPOSY = 0;

my $right_click_deep = 0;

my $COL_GREEN = "\e[1;38;5;2m";
my $COL_RED   = "\e[1;38;5;1m";
my $COL_BLUE  = "\e[1;38;5;33m";
my $COL_YELL  = "\e[1;38;5;11m";
my $COL_RESET = "\e[0m";

# END: Define GLOBAL CLASS variables
###################################################################

###################################################################
# START: Define CLASS methods

# CONSTRUCTOR: build GUI and setup callbacks
sub new {
    my $class = shift;
    my $self = {};

    $self->{_CFG} = shift;
    $self->{_UUID} = shift;
    $self->{_NOTEBOOK} = shift;
    $self->{_NOTEBOOKWINDOW} = shift;
    $self->{_CLUSTER} = shift // '';
    $self->{_MANUAL} = shift;

    $self->{_TABBED} = $self->{_CFG}{'environments'}{$$self{'_UUID'}}{'terminal options'}{'use personal settings'} ? $self->{_CFG}{'environments'}{$$self{'_UUID'}}{'terminal options'}{'open in tab'} // 1 : $self->{_CFG}{'defaults'}{'open connections in tabs'} // 1;
    $self->{_NAME} = $self->{_CFG}{'environments'}{$$self{'_UUID'}}{'name'};
    $self->{_SPLIT} = 0;
    $self->{_SPLIT_VPANE} = 0;
    $self->{_SPLIT_VERTICAL} = 0;
    $self->{_POST_SPLIT} = 0;
    $self->{_PROPAGATE} = 1;
    $self->{_NO_UPDATE_CFG} = 0;
    $self->{_LAST_STATUS} = 'DISCONNECTED';
    $self->{_STATUS_UPDATER} = 0;
    $self->{_STATUS_COUNT} = 0;
    $self->{_LISTEN_COMMIT} = 1;
    $self->{_RESTART} = 0;
    $self->{_RECONNECTS} = 0;
    $self->{_GUI} = undef;
    $self->{_KEYS_BUFFER} = '';
    $self->{_SAVE_KEYS} = 1;
    $self->{_HAVE_PROMPT} = 0;
    $self->{_INTRO_PRESS} = 0;

    $self->{_SCRIPT_STATUS} = 'STOP';
    $self->{_SCRIPT_NAME} = '';

    $self->{_EXEC} = {};
    $self->{_EXEC_LAST} = join('.', gettimeofday());

    $self->{_BADEXIT} = 1;
    $self->{_GUILOCKED} = 0;
    $self->{CONNECTED} = 0;
    $self->{CONNECTING} = 0;
    $self->{ERROR} = '';
    $self->{_FULLSCREEN} = 0;
    $self->{_FSTOTAB} = 0;
    $self->{_NEW_DATA} = 0;
    $self->{_FOCUSED} = 0;
    $self->{FOCUS} = 0;
    $self->{EMBED} = $self->{_CFG}{'environments'}{$$self{_UUID}}{'embed'};
    $self->{EMBED_CHECK_COUNT} = 0;
    $self->{EMBED_CHECK_TIMEOUT} = 250; # in milliseconds
    $self->{EMBED_CHECK_TIMEOUT_ID} = undef;

    ++$_C;
    $self->{_UUID_TMP} = "asbru_PID{$$}_n$_C";

    if ($self->{_CFG}{'environments'}{$$self{_UUID}}{'save session logs'}) {
        $self->{_LOGFILE} = $self->{_CFG}{'environments'}{$$self{_UUID}}{'session logs folder'} . '/';
        $self->{_LOGFILE} .= _subst($self->{_CFG}{'environments'}{$$self{_UUID}}{'session log pattern'}, $$self{_CFG}, $$self{_UUID});
    } elsif ($self->{_CFG}{'defaults'}{'save session logs'}) {
        $self->{_LOGFILE} = $self->{_CFG}{'defaults'}{'session logs folder'} . '/';
        $self->{_LOGFILE} .= _subst($self->{_CFG}{'defaults'}{'session log pattern'}, $$self{_CFG}, $$self{_UUID});
    } else {
        $self->{_LOGFILE} = "$CFG_DIR/tmp/$$self{_UUID_TMP}.txt";
    }
    $self->{_TMPCFG} = "$CFG_DIR/tmp/$$self{_UUID_TMP}freeze";

    $self->{_TMPPIPE} = "$CFG_DIR/tmp/asbru_PID{$$}_n$_C.pipe";
    while (-f $$self{_TMPPIPE}) {
        ++$_C;
        $$self{_TMPPIPE} = "$CFG_DIR/tmp/asbru_PID{$$}_n$_C.pipe";
    }
    unlink $$self{_TMPPIPE};

    $self->{_TMPSOCKET} = "$CFG_DIR/sockets/asbru_PID{$$}_n$_C.socket";
    while (-f $$self{_TMPSOCKET}) {
        ++$_C;
        $$self{_TMPSOCKET} = "$CFG_DIR/sockets/asbru_PID{$$}_n$_C.socket";
    }
    unlink $$self{_TMPSOCKET};

    $self->{_TMPSOCKETEXEC} = "$CFG_DIR/sockets/asbru_PID{$$}_n$_C.exec.socket";
    while (-f $$self{_TMPSOCKETEXEC}) {
        ++$_C;
        $$self{_TMPSOCKETEXEC} = "$CFG_DIR/sockets/asbru_PID{$$}_n$_C.exec.socket";
    }
    unlink $$self{_TMPSOCKETEXEC};

    $self->{_CMD} = '';
    $self->{_PID} = 0;
    $self->{_HISTORY} = ();
    $self->{_TEXT} = ();

    # Prepare the title
    my $name = $$self{_CFG}{'environments'}{$$self{_UUID}}{'name'};
    my $title = $$self{_CFG}{'environments'}{$$self{_UUID}}{'title'};
    $$self{_TITLE} = $title || $name;
    $$self{_TITLE} = _subst($$self{_TITLE}, $$self{_CFG}, $$self{_UUID});

    # Build the GUI
    _initGUI($self) or return 0;
    # Setup callbacks
    _setupCallbacks($self) or return 0;
    # Load connection methods
    %{$$self{_METHODS}} = _getMethods($self,$PACMain::FUNCS{_MAIN}{_THEME}) or return 0;

    $PACMain::RUNNING{$$self{'_UUID_TMP'}}{'uuid'} = $$self{'_UUID'};
    $PACMain::RUNNING{$$self{'_UUID_TMP'}}{'terminal'} = $self;
    $PACMain::RUNNING{$$self{'_UUID_TMP'}}{'is_shell'} = 0;

    $PACMain::FUNCS{_KEYBINDS}->LoadHotKeys($$self{_CFG},$$self{_UUID});

    $self->{_EXPECTED} = 0;
    $self->{_PULSE} = 1;
    $self->{_TOTAL} = 0;

    $self->{_SOCKET_CONN} = undef;
    $self->{_SOCKET_CLIENT} = undef;

    $self->{_SOCKET_CONN} = IO::Socket::UNIX->new(
        Type => SOCK_STREAM,
        Listen => 1,
        Local => $$self{_TMPSOCKET}
    ) or die "ERROR:$!";

    $self->{_SOCKET_CONN_EXEC} = IO::Socket::UNIX->new(
        Type => SOCK_STREAM,
        Listen => 1,
        Local => $$self{_TMPSOCKETEXEC}
    ) or die "ERROR:$!";

    # Add a Glib watcher to listen to new connections (in a non-blocking fashion)
    $self->{_SOCKET_WATCH_EXEC} = Glib::IO->add_watch(fileno($self->{_SOCKET_CONN_EXEC}), ['in', 'hup', 'err'], sub {
        my ($fd, $cond, $self) = @_;

        my $tmp_client;
        do {$tmp_client = $self->{_SOCKET_CONN_EXEC}->accept()} until defined $tmp_client;

        $self->{_SOCKET_CLIENT_EXEC} = $tmp_client;
        $self->{_SOCKET_CLIENT_EXEC}->blocking(0);

        return 1;

    }, $self);

    # Add a Glib watcher to listen to new connections (in a non-blocking fashion)
    $self->{_SOCKET_WATCH} = Glib::IO->add_watch(fileno($self->{_SOCKET_CONN}), ['in', 'hup', 'err'], sub {
        my ($fd, $cond, $self) = @_;

        if (($cond >= 'hup') || ($cond >= 'err')) {
            if (defined $self->{_SOCKET_CONN}) {
                $self->{_SOCKET_CONN}->close();
            }
            _wMessage($$self{_PARENTWINDOW}, 'Master socket at port ' . $self->{_SOCKET_PORT} . ' was closed !!');
            return 0;
        }

        my $tmp_client;
        do {
            $tmp_client = $self->{_SOCKET_CONN}->accept();
        } until defined $tmp_client;

        # Make sure that this client is a PAC client:
        if (!$self->_authClient($tmp_client)) {
            return 1;
        }

        $self->{_SOCKET_CLIENT} = $tmp_client;
        $self->{_SOCKET_CLIENT}->blocking(0);

        # Once we got the client, add a new Glib watcher to listen to incoming data from that client
        $self->{_SOCKET_CLIENT_WATCH} = Glib::IO->add_watch(fileno($self->{_SOCKET_CLIENT}), ['in', 'hup', 'err'], \&_watchConnectionData, $self);

        return 1;

    }, $self);

    #Accessability shortcuts
    $$self{variables}=$$self{_CFG}{environments}{$$self{_UUID}}{variables};

    # Autohide non tabbed help terminals
    if ((defined $$self{_WINDOWTERMINAL})&&(!$$self{_CFG}{'defaults'}{'debug'})&&(!$$self{EMBED})&&($$self{_CFG}{'environments'}{$$self{_UUID}}{'method'} =~ /vnc/i)) {
        $$self{_WINDOWTERMINAL}->hide();
    }

    bless($self, $class);
    return $self;
}

# DESTRUCTOR
sub DESTROY {
    my $self = shift;
    if (defined $self->{_SOCKET_CONN}) {
        $self->{_SOCKET_CONN}->close();
    }
    if (defined $self->{_SOCKET_CLIENT}) {
        $self->{_SOCKET_CLIENT}->close();
    }
    undef $self;
    return 1;
}

# Launch connection
sub start {
    my $self = shift;
    $$self{_KEYS_RECEIVE} = shift // undef;

    if ($$self{CONNECTED} || $$self{CONNECTING}) {
        return 1;
    }
    my $name = $$self{_CFG}{'environments'}{$$self{_UUID}}{'name'};
    my $title = $$self{_TITLE};
    my $method = $$self{_CFG}{'environments'}{$$self{_UUID}}{'method'};
    my $reconnect_msg = '';
    my $reconnect_count = '';

    # Check that session information is still valid
    if (!defined($name)) {
        # Session is invalid for some reason, ignore
        return 0;
    }

    # If this terminal requires a KeePass database file and that we don't have a connection to a KeePass file yet; ask for the database password now
    if (!$ENV{'KPXC_MP'} && $PACMain::FUNCS{_KEEPASS}->hasKeePassField($$self{_CFG},$$self{_UUID})) {
        if ($$self{_CFG}{defaults}{keepass}{password}) {
            $ENV{'KPXC_MP'} = $$self{_CFG}{defaults}{keepass}{password};
        } else {
            my $kpxc = PACKeePass->new(0, $$self{_CFG}{defaults}{keepass});
            $kpxc->getMasterPassword($$self{_PARENTWINDOW});
        }
    }

    if ($$self{'_RECONNECTS'}) {
        $reconnect_msg = 'RE';
        $reconnect_count = " ${COL_RED}attempt:$$self{'_RECONNECTS'}${COL_RESET}";
    }
    my $string = $method eq 'generic' ? encode('UTF-8',"${COL_GREEN}${reconnect_msg}LAUNCHING${COL_RESET} ${COL_YELL}$title${COL_RESET}") : encode('UTF-8',"${COL_GREEN}${reconnect_msg}CONNECTING WITH${COL_RESET} ${COL_YELL}$title${COL_RESET}");
    _vteFeed($$self{_GUI}{_VTE},"\r\n$string (" . (localtime(time)) . ")$reconnect_count\r\n\n");

    $$self{_PULSE} = 1;

    # Check for pre-connection commands execution
    $self->_wPrePostExec('local before');

    # Prepare a timer to "pulse" the progress bar while connecting
    $$self{_PULSE_TIMER} = Glib::Timeout->add (100, sub {
        if ($$self{_PULSE} && defined $$self{_GUI}{pb} && $$self{_GUI}{pb}->get_property('visible')) {
            $$self{_GUI}{pb}->pulse;
            return 1;
        } else {
            delete $$self{_PULSE_TIMER};
            return 0;
        }
    });

    $$self{_CFG}{'tmp'}{'log file'} = $$self{_LOGFILE};
    $$self{_CFG}{'tmp'}{'socket'} = $$self{_TMPSOCKET};
    $$self{_CFG}{'tmp'}{'socket exec'} = $$self{_TMPSOCKETEXEC};
    $$self{_CFG}{'tmp'}{'uuid'} = $$self{_UUID_TMP};

    if ($$self{'EMBED'}) {
        # Reset counter
        $self->{EMBED_CHECK_COUNT} = 0;

        # Create new socket window to plug the embed window from the other process (rdp, vnc, ...)
        # (remove any remaining window before starting to add a new one)
        $$self{_GUI}{_SOCKET} = Gtk3::Socket->new();
        $$self{_GUI}{_SOCKET_PARENT_WINDOW}->foreach(sub {$$self{_GUI}{_SOCKET_PARENT_WINDOW}->remove($_[0]);});
        $$self{_GUI}{_SOCKET_PARENT_WINDOW}->add_with_viewport($$self{_GUI}{_SOCKET});

        # Do not show until conncection is completed
        $$self{_GUI}{_SOCKET_PARENT_WINDOW}->hide();

        # Retrieve the XID of the window on which the external process will have to plug into
        if ($$self{_GUI}{_SOCKET}->get_window()) {
            $$self{_CFG}{'tmp'}{'xid'} = $$self{_GUI}{_SOCKET}->get_window()->get_xid();
            $$self{FOCUS} = $$self{_GUI}{_SOCKET};
        } else {
            _vteFeed($$self{_GUI}{_VTE}, " !! ${COL_RED}ERROR${COL_RESET}: unable to created embedded window.  Terminal will be started in a separated window.\r\n\n");
        }

        # Update GUI before querying the size of the embed window
        Gtk3::main_iteration() while Gtk3::events_pending();

        # Get available size for the embed window
        $$self{_CFG}{'tmp'}{'width'} = $$self{_GUI}{_VBOX}->get_allocated_width();
        $$self{_CFG}{'tmp'}{'height'} = $$self{_GUI}{_VBOX}->get_allocated_height() - $$self{_GUI}{bottombox}->get_allocated_height();
        if (defined($$self{_GUI}{_MACROSBOX}) && $$self{_GUI}{_MACROSBOX}->get_visible()) {
            $$self{_CFG}{'tmp'}{'height'} -= $$self{_GUI}{_MACROSBOX}->get_allocated_height();
        }
        eval {
            $PACMain::FUNCS{_MAIN}{_GUI}{vboxCommandPanel}->get_visible() or $$self{_CFG}{'tmp'}{'width'} += $PACMain::FUNCS{_MAIN}{_GUI}{vboxCommandPanel}->get_allocated_width();
        };
    } else {
        delete $$self{_CFG}{'tmp'}{'xid'};
        delete $$self{_CFG}{'tmp'}{'width'};
        delete $$self{_CFG}{'tmp'}{'height'};
    }

    # Duplicate and dump non-persistent configuration into temporal file for 'asbru_conn'
    my %new_cfg;
    $new_cfg{'defaults'} = dclone($$self{_CFG}{'defaults'});
    $new_cfg{'environments'}{$$self{_UUID}} = dclone($$self{_CFG}{'environments'}{$$self{_UUID}});
    $new_cfg{'tmp'} = dclone($$self{_CFG}{'tmp'});
    if (defined $$self{_MANUAL}) {
        $new_cfg{'environments'}{$$self{_UUID}}{'auth type'} = $$self{_MANUAL};
    }
    nstore(\%new_cfg, $$self{_TMPCFG}) or die"ERROR: Could not save Ásbrú config file '$$self{_TMPCFG}': $!";
    undef %new_cfg;

    # Delete the oldest auto-saved session log
    if ($$self{_CFG}{'environments'}{$$self{_UUID}}{'save session logs'}) {
        if (-w $$self{_CFG}{'environments'}{$$self{_UUID}}{'session logs folder'}) {
            _deleteOldestSessionLog($$self{_UUID}, $$self{_CFG}{'environments'}{$$self{_UUID}}{'session logs folder'}, $$self{_CFG}{'environments'}{$$self{_UUID}}{'session logs amount'});
        } else {
            print STDERR "WARN: Unable to write into the session logs folder [$$self{_CFG}{'environments'}{$$self{_UUID}}{'session logs folder'}], session logs will not be recorded.\n";
            print STDERR "WARN: Check your terminal settings to fix the issue.\n";
        }
    }
    if (!$$self{_CFG}{'environments'}{$$self{_UUID}}{'save session logs'} && $$self{_CFG}{'defaults'}{'save session logs'}) {
        if (-w $$self{_CFG}{'defaults'}{'session logs folder'}) {
            _deleteOldestSessionLog($$self{_UUID}, $$self{_CFG}{'defaults'}{'session logs folder'}, $$self{_CFG}{'defaults'}{'session logs amount'});
        } else {
            print STDERR "WARN: Unable to write into the session logs folder [$$self{_CFG}{'defaults'}{'session logs folder'}], session logs will not be recorded.\n";
            print STDERR "WARN: Check your global preferences to fix the issue.\n";
        }
    }

    $$self{CONNECTING} = 1;
    $PACMain::FUNCS{_STATS}->start($$self{_UUID});
    my $isCluster = $$self{_CLUSTER} ? 1 : 0;
    # Start and fork our connector
    my @args;
    if ($$self{_CFG}{'defaults'}{'use login shell to connect'}) {
        @args = [$SHELL_BIN, $SHELL_NAME, '-l', '-c', "($PERL_BIN $PAC_CONN $$self{_TMPCFG} $$self{_UUID} $isCluster; exit)"];
    } else {
        @args = [$PERL_BIN, 'perl', $PAC_CONN, $$self{_TMPCFG}, $$self{_UUID}, $isCluster];
    }
    if (!$$self{_GUI}{_VTE}->spawn_sync([], $method eq 'PACShell' ? $$self{_CFG}{'defaults'}{'shell directory'} : undef, @args, undef, 'G_SPAWN_FILE_AND_ARGV_ZERO', undef, undef, undef)) {
        $$self{ERROR} = "ERROR: VTE could not fork command '$PAC_CONN $$self{_TMPCFG} $$self{_UUID}'!!";
        $$self{CONNECTING} = 0;
        return 0;
    }

    # ... and save its data
    $PACMain::RUNNING{$$self{'_UUID_TMP'}}{'uuid'} = $$self{_UUID};
    $PACMain::RUNNING{$$self{'_UUID_TMP'}}{'start_time'} = time;

    foreach my $exp (@{$$self{_CFG}{'environments'}{$$self{_UUID}}{'expect'}}) {
        if (!($$exp{'active'} // 0)) {
            next;
        }
        ++$$self{_TOTAL};
    }

    # Create a progressbar and add it to GUI's bottombox
    $$self{_GUI}{pb} = Gtk3::ProgressBar->new();
    $$self{_GUI}{bottombox}->pack_start($$self{_GUI}{pb}, 0, 1, 0);
    $$self{_GUI}{pb}->show();

    if ($$self{_CLUSTER}) {
        $PACMain::FUNCS{_CLUSTER}->addToCluster($$self{_UUID_TMP}, $$self{_CLUSTER});
    }

    # Create a Glib timeout to programatically send a given string to the connected terminal (if so is configured!)
    defined $$self{_SEND_STRING} and Glib::Source->remove($$self{_SEND_STRING});
    $$self{_CFG}{environments}{$$self{_UUID}}{'send string active'} and $$self{_SEND_STRING} = Glib::Timeout->add_seconds(
        $$self{_CFG}{environments}{$$self{_UUID}}{'send string every'},
        sub {
            if (not $$self{CONNECTED} && $$self{_CFG}{environments}{$$self{_UUID}}{'send string active'}) {
                return 1;
            }

            my $txt = $$self{_CFG}{environments}{$$self{_UUID}}{'send string txt'};
            my $intro = $$self{_CFG}{environments}{$$self{_UUID}}{'send string intro'};
            $txt = _subst($txt, $$self{_CFG}, $$self{_UUID});
            _vteFeedChild($$self{_GUI}{_VTE}, $txt . ($intro ? "\n" : ''));

            return 1;
        }
    );

    $$self{_CFG}{'environments'}{$$self{_UUID}}{'startup script'} and $PACMain::FUNCS{_SCRIPTS}->_execScript($$self{_CFG}{'environments'}{$$self{_UUID}}{'startup script name'},$self->{_PARENTWINDOW},$$self{_UUID_TMP});
    $$self{_GUI}{_VTE}->grab_focus();
    if ($PACMain::FUNCS{_MAIN}{_Vte}{has_bright}) {
        $$self{_GUI}{_VTE}->set_bold_is_bright($$self{_CFG}{'defaults'}{'bold is brigth'});
    }
    return 1;
}

# Stop and close GUI
sub stop {
    my $self = shift;
    my $force = shift // 0;
    my $deep = shift // 0;

    my $name = $self->{_CFG}{'environments'}{$$self{_UUID}}{'name'};
    my $title = $self->{_CFG}{'environments'}{$$self{_UUID}}{'title'};

    # First of all, save THIS page's widget (to prevent closing a not selected tab)
    my $p_widget = $$self{_GUI}{_VBOX};

    # Set mouse pointer in case a postexec was executed
    if ($p_widget->get_window()) {
        $p_widget->get_window()->set_cursor(Gtk3::Gdk::Cursor->new('left-ptr'));
    }

    if ($NPOSX>0) {
        $NPOSX--;
        if (($NPOSY>0)&&($NPOSX==0)) {
            $NPOSY--;
            $NPOSX=2;
        }
    } elsif ($NPOSY>0) {
        $NPOSY--;
        $NPOSX=1;
    }

    # TODO : This coding sequence looks repeated unless is it is necessary to confirm connection that many times

    # May be user wants to close without confirmation...
    if ((! $force) && ($self->{CONNECTED})) {
        # Ask for confirmation
        if (!_wConfirm($$self{_WINDOWTERMINAL}, "Are you sure you want to close '" . ($$self{_SPLIT} ? 'this split tab' : __($$self{_TITLE})) . "'?", 'yes')) {
            return 1;
        }

        # Check for post-connection commands execution
        if ($$self{CONNECTED}){
            $self->_wPrePostExec('local after');
        }
    } elsif (! $force) {
        # Check for post-connection commands execution
        if ($$self{CONNECTED}) {
            $self->_wPrePostExec('local after');
        }
    }

    # Send any configured keypress to close the forked binary
    if ($$self{CONNECTED} && defined $$self{_METHODS}{$$self{_CFG}{'environments'}{$$self{_UUID}}{'method'}}{'escape'}) {
        foreach my $esc (@{$$self{_METHODS}{$$self{_CFG}{'environments'}{$$self{_UUID}}{'method'}}{'escape'}}) {
            _vteFeedChild($$self{_GUI}{_VTE}, $esc);
        }
    }

    _vteFeedChild($$self{_GUI}{_VTE}, "__PAC__STOP__$$self{_UUID}__$$self{_PID}__");

    $$self{CONNECTED} = 0;

    if ($$self{_SPLIT} && $PACMain::RUNNING{$$self{_SPLIT}}{terminal}{CONNECTED}) {
        return 1;
    }
    if ($$self{_SPLIT} && $deep) {
        $PACMain::RUNNING{$$self{_SPLIT}}{terminal}->stop(1, 0);
    }

    # Try to ensure we leave no background "asbru_conn" processes running after closing the terminal
    $self->_disconnectTerminal();
    if ($$self{_PID}) {
        $PACMain::FUNCS{_STATS}->stop($$self{_UUID});
    }

    # Delete me from the running terminals list
    delete $PACMain::RUNNING{$$self{_UUID_TMP}};
    $PACMain::FUNCS{_CLUSTER}->_updateGUI();

    if (defined $$self{_SOCKET_CLIENT}) {
        $$self{_SOCKET_CLIENT}->close();
    }
    if (defined $$self{_SOCKET_CLIENT_WATCH}) {
        eval {
            Glib::Source->remove($$self{_SOCKET_CLIENT_WATCH});
        };
    }
    if (defined $$self{_SEND_STRING}) {
        eval {
            Glib::Source->remove($$self{_SEND_STRING});
        };
    }
    $self->_stopEmbedKidnapTimeout();

    # Finish the GUI
    if ($$self{_TABBED}) {
        my $p_num = -1;
        if ($$self{_SPLIT}) {
            $p_num = $$self{_NOTEBOOK}->page_num($p_widget->get_parent());
        } else {
            $p_num = $$self{_NOTEBOOK}->page_num($p_widget);
        }

        # Skip destruction if this tab does not exists after having answered to _wConfirm
        if ($p_num >= 0) {
            $$self{_NOTEBOOK}->remove_page($p_num);
        }
    } else {
        $$self{_WINDOWTERMINAL}->destroy();
        undef($$self{_WINDOWTERMINAL});
    }

    unlink($$self{_TMPCFG});
    unlink($$self{_TMPPIPE});
    unlink($$self{_TMPSOCKET});
    if (!($self->{_CFG}{'defaults'}{'save session logs'} || $self->{_CFG}{'environments'}{$$self{_UUID}}{'save session logs'})) {
        unlink($$self{_LOGFILE});
    }

    # If I was a temporal UUID, delete me
    if ($$self{_UUID} =~ /^_tmp_/go) {
        delete $$self{_CFG}{environments}{$$self{_UUID}};
    }

    # And delete ourselves
    $$self{_GUI} = undef;
    undef $self;

    return 1;
}

sub lock {
    my $self = shift;
    $$self{_TABBED} and $$self{_GUI}{_TABLBL}->set_sensitive(0);
    $$self{_GUI}{_VBOX}->set_sensitive(0);
    $$self{_GUILOCKED} = 1;
    return 1;
}

sub unlock {
    my $self = shift;
    $$self{_TABBED} and $$self{_GUI}{_TABLBL}->set_sensitive(1);
    $$self{_GUI}{_VBOX}->set_sensitive(1);
    $self->_updateCFG();
    $$self{_GUILOCKED} = 0;
    return 1;
}

# END: Define CLASS methods
###################################################################

###################################################################
# START: Private functions definitions

sub _initGUI {
    my $self = shift;

    my $tabs = $$self{_NOTEBOOK};

    # Create a GtkVBox and its child widgets:
    $$self{_GUI}{_VBOX} = Gtk3::VBox->new(0, 0);

    $$self{_GUI}{_HBOX} = Gtk3::HPaned->new();

    #### $vbox 1st row: this will contain an HBOX with Gnome's VTE and keypresses list

    # Create a GtkScrolledWindow,
    my $sc = Gtk3::ScrolledWindow->new();
    $sc->set_shadow_type('none');
    $sc->set_policy('automatic', 'automatic');

    # , build a Gnome VTE Terminal,
    $$self{_GUI}{_VTE} = Vte::Terminal->new();

    # , add VTE to the scrolled window and...
    if (!$$self{'EMBED'}) {
        $$self{_GUI}{_VTE}->set_size_request(200, 100);
        $sc->add($$self{_GUI}{_VTE});
    }

    if (!$$self{'EMBED'}) {
        $$self{_GUI}{_VBOX}->pack_start($$self{_GUI}{_HBOX}, 1, 1, 0);

        # ... put this scrolled vte in $vbox
        $$self{_GUI}{_HBOX}->pack1($sc, 1, 0);
        $$self{_GUI}{_HBOX}->set_position(3000);

        $$self{FOCUS} = $$self{_GUI}{_VTE};
    } else {
        $$self{_GUI}{_SOCKET_PARENT_WINDOW} = Gtk3::ScrolledWindow->new();
        $$self{_GUI}{_SOCKET_PARENT_WINDOW}->set_shadow_type('none');
        $$self{_GUI}{_SOCKET_PARENT_WINDOW}->set_policy('automatic', 'automatic');
        $$self{_GUI}{_SOCKET_PARENT_WINDOW}->hide();
        $$self{_GUI}{_VBOX}->pack_start($$self{_GUI}{_SOCKET_PARENT_WINDOW}, 1, 1, 0);

        $$self{_GUI}{_VBOX}->pack_start($$self{_GUI}{_VTE}, 1, 1, 0);
    }

    #### $vbox 2nd row: this will contain local/remote macros

    # MACROS Combobox??
    if ($$self{_CFG}{'defaults'}{'show commands box'} == 1) {
        $$self{_GUI}{_MACROSBOX} = Gtk3::HBox->new(0, 0);
        $$self{_GUI}{_VBOX}->pack_start($$self{_GUI}{_MACROSBOX}, 0, 1, 0);

        # Create a GtkButton and add it to $macrosbox
        $$self{_GUI}{_BTNLOCALTERMINALEXEC} = Gtk3::Button->new_with_mnemonic('_Local');
        $$self{_GUI}{_BTNLOCALTERMINALEXEC}->set_property('can_focus', 0);
        $$self{_GUI}{_BTNLOCALTERMINALEXEC}->set_sensitive(0);
        $$self{_GUI}{_BTNLOCALTERMINALEXEC}->set_image(Gtk3::Image->new_from_stock('gtk-execute', 'GTK_ICON_SIZE_SMALL_TOOLBAR'));
        $$self{_GUI}{_BTNLOCALTERMINALEXEC}->set_size_request(60, 25);
        $$self{_GUI}{_BTNLOCALTERMINALEXEC}->set('can_focus', 0);
        $$self{_GUI}{_MACROSBOX}->pack_start($$self{_GUI}{_BTNLOCALTERMINALEXEC}, 0, 1, 0);

        # Create a GtkComboBox and add it to $macrosbox
        $$self{_GUI}{_CBLOCALEXECTERMINAL} = Gtk3::ComboBoxText->new();
        $$self{_GUI}{_CBLOCALEXECTERMINAL}->set_property('can_focus', 0);
        $$self{_GUI}{_CBLOCALEXECTERMINAL}->set_size_request(200, -1); # Limit combobox hsize!!
        $$self{_GUI}{_CBLOCALEXECTERMINAL}->set_sensitive(0);
        $$self{_GUI}{_CBLOCALEXECTERMINAL}->set_size_request(30, 25);
        $$self{_GUI}{_CBLOCALEXECTERMINAL}->set('can_focus', 0);
        $$self{_GUI}{_MACROSBOX}->pack_start($$self{_GUI}{_CBLOCALEXECTERMINAL}, 1, 1, 0);

        # Checkbutton to send or not to all terminals in cluster
        $$self{_GUI}{_MACROSCLUSTER} = Gtk3::CheckButton->new_with_label('Sending THIS: ');
        $$self{_GUI}{_MACROSCLUSTER}->set('can-focus', 0);
        $$self{_GUI}{_MACROSCLUSTER}->signal_connect('toggled', sub {
            my $str = $$self{_GUI}{_MACROSCLUSTER}->get_active() ? 'Sending CLUSTER: ' : 'Sending THIS: ';
            $$self{_GUI}{_MACROSCLUSTER}->set_label($str);
        });
        $$self{_GUI}{_MACROSBOX}->pack_start($$self{_GUI}{_MACROSCLUSTER}, 0, 1, 0);

        # Create a GtkComboBox and add it to $macrosbox
        $$self{_GUI}{_CBMACROSTERMINAL} = Gtk3::ComboBoxText->new();
        $$self{_GUI}{_CBMACROSTERMINAL}->set_property('can_focus', 0);
        $$self{_GUI}{_CBMACROSTERMINAL}->set_size_request(200, -1); # Limit combobox hsize!!
        $$self{_GUI}{_CBMACROSTERMINAL}->set_sensitive(0);
        $$self{_GUI}{_CBMACROSTERMINAL}->set_size_request(60, 25);
        $$self{_GUI}{_CBMACROSTERMINAL}->set('can_focus', 0);
        $$self{_GUI}{_MACROSBOX}->pack_start($$self{_GUI}{_CBMACROSTERMINAL}, 1, 1, 0);

        # Create a GtkButton and add it to $macrosbox
        $$self{_GUI}{_BTNMACROSTERMINALEXEC} = Gtk3::Button->new_with_mnemonic('_Remote');
        $$self{_GUI}{_BTNMACROSTERMINALEXEC}->set_property('can_focus', 0);
        $$self{_GUI}{_BTNMACROSTERMINALEXEC}->set_sensitive(0);
        $$self{_GUI}{_BTNMACROSTERMINALEXEC}->set_image(Gtk3::Image->new_from_stock('gtk-execute', 'GTK_ICON_SIZE_SMALL_TOOLBAR'));
        $$self{_GUI}{_BTNMACROSTERMINALEXEC}->set_size_request(70, 25);
        $$self{_GUI}{_BTNMACROSTERMINALEXEC}->set('can_focus', 0);
        $$self{_GUI}{_MACROSBOX}->pack_start($$self{_GUI}{_BTNMACROSTERMINALEXEC}, 0, 1, 0);
    }
    # MACROS Buttonbox??
    elsif ($$self{_CFG}{'defaults'}{'show commands box'} == 2)
    {
        $$self{_GUI}{_SCROLLMACROS} = Gtk3::ScrolledWindow->new();
        $$self{_GUI}{_SCROLLMACROS}->set_policy('automatic', 'never');
        $$self{_GUI}{_MACROSBOX} = Gtk3::HBox->new(0, 0);
        $$self{_GUI}{_SCROLLMACROS}->add_with_viewport($$self{_GUI}{_MACROSBOX});

        $$self{_GUI}{_VBOX}->pack_start($$self{_GUI}{_SCROLLMACROS}, 0, 1, 0);
    }

    if (defined $$self{_GUI}{_MACROSBOX}) {
        $$self{_GUI}{_MACROSBOX}->hide;
    }

    # bottombox will contain both progress and status bar
    $$self{_GUI}{bottombox} = Gtk3::HBox->new(0, 0);
    if ($$self{_CFG}{defaults}{'terminal show status bar'}) {
        $$self{_GUI}{_VBOX}->pack_end($$self{_GUI}{bottombox}, 0, 1, 0);
    }

    # Only in traditional mode, show additional buttons
    if ($$self{_CFG}{'defaults'}{'layout'} ne 'Compact') {
        # Create a checkbox to show/hide the button bar
        $$self{_GUI}{btnShowButtonBar} = Gtk3::ToggleButton->new();
        $$self{_GUI}{btnShowButtonBar}->set_image(Gtk3::Image->new_from_stock($$self{_CFG}{'defaults'}{'auto hide button bar'} ? 'asbru-buttonbar-show' : 'asbru-buttonbar-hide', 'GTK_ICON_SIZE_BUTTON'));
        $$self{_GUI}{btnShowButtonBar}->set('can-focus' => 0);
        $$self{_GUI}{btnShowButtonBar}->set_tooltip_text('Show/Hide button bar');
        $$self{_GUI}{btnShowButtonBar}->set_active($$self{_CFG}{'defaults'}{'auto hide button bar'} ? 0 : 1);
        $$self{_GUI}{btnShowButtonBar}->set_inconsistent(0);
        $$self{_GUI}{bottombox}->pack_end($$self{_GUI}{btnShowButtonBar}, 0, 1, 4);

        # Create a button to show the info tab
        $$self{_GUI}{btnShowInfoTab} = Gtk3::Button->new();
        $$self{_GUI}{btnShowInfoTab}->set_image(Gtk3::Image->new_from_stock('gtk-info', 'GTK_ICON_SIZE_BUTTON'));
        $$self{_GUI}{bottombox}->pack_end($$self{_GUI}{btnShowInfoTab}, 0, 1, 4);
    }

    if ($$self{'EMBED'}) {
        $$self{_GUI}{_BTNLOG} = Gtk3::Button->new_with_mnemonic('Hide _messages');
        $$self{_GUI}{_BTNLOG}->set_image(Gtk3::Image->new_from_icon_name('gtk-select-all', 'GTK_ICON_SIZE_BUTTON'));
        $$self{_GUI}{_BTNLOG}->set_always_show_image(1);
        $$self{_GUI}{_BTNLOG}->set('can_focus', 0);
        $$self{_GUI}{bottombox}->pack_end($$self{_GUI}{_BTNLOG}, 0, 1, 4);

        $$self{_GUI}{_BTNFOCUS} = Gtk3::Button->new_with_mnemonic('Set _keyboard focus');
        $$self{_GUI}{_BTNFOCUS}->set_image(Gtk3::Image->new_from_icon_name('input-keyboard', 'GTK_ICON_SIZE_BUTTON'));
        $$self{_GUI}{_BTNFOCUS}->set('can_focus', 0);
        $$self{_GUI}{_BTNFOCUS}->set_sensitive(0);
        $$self{_GUI}{bottombox}->pack_end($$self{_GUI}{_BTNFOCUS}, 0, 1, 4);
    }

    # Create gtkstatusbar
    $$self{_GUI}{status} = Gtk3::Statusbar->new();
    $$self{_GUI}{bottombox}->pack_end($$self{_GUI}{status}, 1, 1, 4);

    # Create a status icon
    $$self{_GUI}{statusIcon} = Gtk3::Image->new_from_stock('asbru-terminal-ko-small', 'button');
    $$self{_GUI}{statusIcon}->set_tooltip_text('Disconnected');
    $$self{_GUI}{bottombox}->pack_start($$self{_GUI}{statusIcon}, 0, 0, 4);

    # Create an Expect execute icon
    $$self{_GUI}{statusExpect} = Gtk3::Image->new_from_stock('none', 'button');
    $$self{_GUI}{statusExpect}->set_tooltip_text('Disconnected');
    $$self{_GUI}{bottombox}->pack_start($$self{_GUI}{statusExpect}, 0, 0, 4);

    # Create a cluster icon
    $$self{_GUI}{statusCluster} = Gtk3::Image->new_from_stock('asbru-cluster-manager-off', 'button');
    $$self{_GUI}{statusCluster}->set_tooltip_text('Unclustered');
    $$self{_GUI}{bottombox}->pack_start($$self{_GUI}{statusCluster}, 0, 0, 4);

    # Set the number of scrollback lines
    # If -2, uses the global preferences, otherwise use the value defined in terminal options
    $$self{_GUI}{_VTE}->set_scrollback_lines($$self{_CFG}{environments}{$$self{_UUID}}{'terminal options'}{'terminal scrollback lines'} > -2 ? $$self{_CFG}{environments}{$$self{_UUID}}{'terminal options'}{'terminal scrollback lines'} : $$self{_CFG}{'defaults'}{'terminal scrollback lines'});

    ############################################################################
    # Check if this terminal should start in a new window or in a new tab/window
    ############################################################################

    # New TAB:
    if ($$self{_TABBED}) {
        # Append this GUI to a new TAB (with an associated label && event_box->image(close) button)
        $$self{_GUI}{_TABLBL} = Gtk3::HBox->new(0, 0);
        $$self{_GUI}{_TABLBL}{_EBLBL} = Gtk3::EventBox->new();
        $$self{_GUI}{_TABLBL}{_LABEL} = Gtk3::Label->new($$self{_TITLE});
        $$self{_GUI}{_TABLBL}{_EBLBL}->add($$self{_GUI}{_TABLBL}{_LABEL});
        $$self{_GUI}{_TABLBL}->pack_start($$self{_GUI}{_TABLBL}{_EBLBL}, 1, 1, 0);
        my $eblbl1 = Gtk3::EventBox->new();
        $eblbl1->add(Gtk3::Image->new_from_stock('gtk-close', 'menu'));
        $eblbl1->signal_connect('button_release_event' => sub {
            if ($_[1]->button != 1) {
                return 0;
            }
            $self->stop(undef, 1);
        });
        $$self{_GUI}{_TABLBL}->pack_start($eblbl1, 0, 1, 0);

        $$self{_GUI}{_TABLBL}{_EBLBL}->signal_connect('button_press_event' => sub {
            if ($_[1]->button eq 2) {
                # Mid-button
                $self->stop(undef, 1);
                return 1;
            } elsif ($_[1]->button eq 3) {
                # Right-button
                $self->_tabMenu($_[1]);
                return 1;
            }
            return 0;
        });

        $$self{_GUI}{_TABLBL}->show_all();

        _setupTabDND($self);

        # DevNote: append_page is having a side effect that shows the main window (if hidden), see #783
        $tabs->append_page($$self{_GUI}{_VBOX}, $$self{_GUI}{_TABLBL});
        $tabs->show();
        $$self{_GUI}{_VBOX}->show_all();
        $tabs->set_tab_reorderable($$self{_GUI}{_VBOX}, 1);
        $tabs->set_current_page(-1);
        if (! $$self{_CFG}{'environments'}{$$self{_UUID}}{'embed'}) {
            if ($$self{_FOCUSED}) {
                $$self{FOCUS}->child_focus('GTK_DIR_TAB_FORWARD');
            }
            if (defined $$self{FOCUS} && defined $$self{FOCUS}->get_window()) {
                $$self{FOCUS}->get_window()->show();
            }
        }
        if ($$self{_CFG}{'defaults'}{'start maximized'}) {
            $$self{_NOTEBOOKWINDOW}->maximize();
        }
        $self->{_PARENTWINDOW} = $$self{_NOTEBOOKWINDOW};

    }
    # New WINDOW:
    else
    {
        # Build a new window,
        $$self{_WINDOWTERMINAL} = Gtk3::Window->new();
        $$self{_WINDOWTERMINAL}->set_title("$$self{_TITLE} : $APPNAME (v$APPVERSION)");
        $$self{_WINDOWTERMINAL}->set_position('none');
        $$self{_WINDOWTERMINAL}->set_size_request(200, 100);

        my $hsize = $$self{_CFG}{environments}{$$self{_UUID}}{'terminal options'}{'use personal settings'} ? $$self{_CFG}{environments}{$$self{_UUID}}{'terminal options'}{'terminal window hsize'} : $$self{_CFG}{'defaults'}{'terminal windows hsize'};
        my $vsize = $$self{_CFG}{environments}{$$self{_UUID}}{'terminal options'}{'use personal settings'} ? $$self{_CFG}{environments}{$$self{_UUID}}{'terminal options'}{'terminal window vsize'} : $$self{_CFG}{'defaults'}{'terminal windows vsize'};

        my $conns_per_row = 2;
        my $conns_per_col = 1;
        if ($self->{_CLUSTER}) {
            if ($PACMain::FUNCS{_MAIN}{_NTERMINALS}>1) {
                my $screen = Gtk3::Gdk::Screen::get_default();
                my $sw = $screen->get_width();
                my $sh = $screen->get_height() - 100;
                $conns_per_row = $PACMain::FUNCS{_MAIN}{_NTERMINALS} < 5 ? 2 : 3;
                $conns_per_col = $PACMain::FUNCS{_MAIN}{_NTERMINALS} < 7 ? 2 : 3;
                my $rows = POSIX::ceil($PACMain::FUNCS{_MAIN}{_NTERMINALS} / $conns_per_row) || 1;
                my $cols = POSIX::ceil($PACMain::FUNCS{_MAIN}{_NTERMINALS} / $conns_per_col) || 1;
                $hsize = int($sw / (POSIX::ceil($PACMain::FUNCS{_MAIN}{_NTERMINALS} / $rows)));
                if ($PACMain::FUNCS{_MAIN}{_NTERMINALS}>2) {
                    $vsize = int($sh / (POSIX::ceil($PACMain::FUNCS{_MAIN}{_NTERMINALS} / $cols)));
                } else {
                    $vsize = $sh;
                }
            }
        }
        $$self{_WINDOWTERMINAL}->set_default_size($hsize, $vsize);
        if ($$self{_CFG}{'defaults'}{'start maximized'}) {
            $$self{_WINDOWTERMINAL}->maximize();
        }
        $$self{_WINDOWTERMINAL}->set_icon_name('gtk-disconnect');
        $$self{_WINDOWTERMINAL}->add($$self{_GUI}{_VBOX});
        $$self{_WINDOWTERMINAL}->move(($NPOSX*$hsize+3),5+($NPOSY*$vsize+($NPOSY*50)));

        if (($$self{_CFG}{environments}{$$self{_UUID}}{'terminal options'}{'use personal settings'} && $$self{_CFG}{environments}{$$self{_UUID}}{'terminal options'}{'terminal transparency'} > 0) || $$self{_CFG}{defaults}{'terminal support transparency'}) {
            _setWindowPaintable($$self{_WINDOWTERMINAL});
        }

        $$self{_WINDOWTERMINAL}->show_all();
        $$self{_WINDOWTERMINAL}->present();
        $NPOSX++;
        if ($NPOSX == $conns_per_row) {
            $NPOSY++;
            $NPOSX = 0;
        }
        $self->{_PARENTWINDOW} = $$self{_WINDOWTERMINAL};
    }

    _updateCFG($self);

    return 1;
}

sub _setupCallbacks {
    my $self = shift;

    # Show Bar (if any)
    if ($$self{_GUI}{btnShowButtonBar}) {
        $$self{_GUI}{btnShowButtonBar}->signal_connect('toggled', sub {
            if ($$self{_GUI}{btnShowButtonBar}->get_active()) {
                $$self{_GUI}{btnShowButtonBar}->set_image(Gtk3::Image->new_from_stock('asbru-buttonbar-hide', 'GTK_ICON_SIZE_BUTTON'));
                $PACMain::FUNCS{_MAIN}{_GUI}{hbuttonbox1}->show();
            } else {
                $$self{_GUI}{btnShowButtonBar}->set_image(Gtk3::Image->new_from_stock('asbru-buttonbar-show', 'GTK_ICON_SIZE_BUTTON'));
                $PACMain::FUNCS{_MAIN}{_GUI}{hbuttonbox1}->hide();
            };
        });
    }

    # Info button event (if any)
    if ($$self{_GUI}{btnShowInfoTab}) {
        $$self{_GUI}{btnShowInfoTab}->signal_connect('clicked', sub {
            $self->_showInfoTab();
        });
    }

    # Mouse move in out VTE events
    if ($$self{_CFG}{defaults}{'tabs in main window'}) {
        $$self{_GUI}{_VTE}->signal_connect('motion_notify_event', sub {
            if ($$self{_CFG}{'defaults'}{'prevent mouse over show tree'}) {
                return 0;
            }
            my @geo = $$self{_GUI}{_VTE}->get_window()->get_geometry();
            if ($$self{_CFG}{defaults}{'tree on right side'}) {
                if ($$self{_SPLIT_VPANE} && (($$self{_SPLIT_VPANE}->get_child1()) eq $$self{_GUI}{_VBOX}) && !$$self{_SPLIT_VERTICAL}) {
                    return 0;
                }
                $PACMain::FUNCS{_MAIN}{_GUI}{showConnBtn}->set_active($_[1]->x >= ($geo[2] - 30));
            } else {
                if ($$self{_SPLIT_VPANE} && (($$self{_SPLIT_VPANE}->get_child2()) eq $$self{_GUI}{_VBOX}) && !$$self{_SPLIT_VERTICAL}) {
                    return 0;
                }
                $PACMain::FUNCS{_MAIN}{_GUI}{showConnBtn}->set_active($_[1]->x <= 10);
            }
            return 0;
        });
    }

    # ------------------------------
    # Register callbacks from VTE
    # ------------------------------

    # Capture VTE title changes
    # note: actually raised by the appropriate Xterm escape sequence, see http://www.faqs.org/docs/Linux-mini/Xterm-Title.html#s3
    $$self{_GUI}{_VTE}->signal_connect('window-title-changed' => sub {
        my ($terminal, $myself) = @_;
        my $new_title=$terminal->get_window_title();
        if ($$self{_CFG}{defaults}{'capture xterm title'}) {
            $$myself{_TITLE} = $new_title;
        }
    }, $self);

    # Capture focus-in
    $$self{_GUI}{_VTE}->signal_connect('focus_in_event' => sub {
        if ($$self{_CFG}{defaults}{'change main title'}) {
            $$self{_NOTEBOOKWINDOW}->set_title("@{[__($$self{_TITLE})]}  - $APPNAME");
        }
    });

    # Capture focus-out of VTE when it shouldn't get out!!!
    $$self{_GUI}{_VTE}->signal_connect('focus_out_event' => sub {
        if (($PACMain::FUNCS{_MAIN}{_HAS_FOCUS} // '') eq $$self{_GUI}{_VTE}) {
            if (defined $$self{_WINDOWTERMINAL}) {
                $$self{_WINDOWTERMINAL}->present();
            }
            $$self{_GUI}{_VTE}->grab_focus();
            $PACMain::FUNCS{_MAIN}{_HAS_FOCUS} = '';
            1;
        }
    });

    # Capture keypresses on VTE
    $$self{_GUI}{_VTE}->signal_connect('key_press_event' => sub {
        my ($widget, $event) = @_;
        my $keyval  = Gtk3::Gdk::keyval_name($event->keyval) // '';
        my $unicode = Gtk3::Gdk::keyval_to_unicode($event->keyval); # 0 if not a character
        my ($action,$keymask);

        if (defined $$self{_KEYS_RECEIVE}) {
            return 1;
        }

        if ($$self{_TABBED}) {
            ($action,$keymask) = $PACMain::FUNCS{_KEYBINDS}->GetAction('pactabs', $widget, $event, $$self{_UUID});
            if ($action eq 'close') {
                $self->stop(undef, 1);
                return 1;
            }
        }

        ($action,$keymask) = $PACMain::FUNCS{_KEYBINDS}->GetAction('terminal', $widget, $event, $$self{_UUID});

        if (!$action) {
            return 0;
        } elsif ($action eq 'Return' && !$$self{CONNECTED} && !$$self{CONNECTING}) {
            # Only consider "RETURN" if disconnected ; otherwise do not consider it as an action
            $self->start();
        } elsif ($action eq 'start') {
            if (!$$self{CONNECTED} && !$$self{CONNECTING}) {
                $self->start();
            }
        } elsif ($action eq 'fullscreen') {
            if ($$self{_FULLSCREEN}) {
                $$self{_FSTOTAB} and $self->_winToTab();
                $$self{_GUI}{_VBOX}->get_window()->unfullscreen();
                $$self{_FULLSCREEN} = 0;
            } else {
                $$self{_FSTOTAB} = $$self{_TABBED};
                $$self{_TABBED} and $self->_tabToWin();
                $$self{_GUI}{_VBOX}->get_window()->fullscreen();
                $$self{_FULLSCREEN} = 1;
            }
        } elsif ($action eq 'disconnect') {
            $self->_disconnectTerminal();
        } elsif ($action eq 'sftp') {
            $self->_openSFTP()
        } elsif ($action eq 'reset') {
            $$self{_GUI}{_VTE}->reset(1, 0);
        } elsif ($action eq 'reset-clear') {
            $$self{_GUI}{_VTE}->reset(1, 1);
        } elsif ($action eq 'remove_from_cluster') {
            $PACMain::FUNCS{_CLUSTER}->delFromCluster($$self{_UUID_TMP}, $$self{_CLUSTER});
        } elsif ($action eq 'copy') {
            $$self{_GUI}{_VTE}->copy_clipboard();
        } elsif ($action eq 'paste') {
            $$self{_GUI}{_VTE}->paste_clipboard();
        } elsif ($action eq 'paste-primary') {
            $$self{_GUI}{_VTE}->paste_primary();
        } elsif ($action eq 'paste-passwd' && ($$self{_CFG}{environments}{$$self{_UUID}}{'pass'} ne '' || $$self{_CFG}{environments}{$$self{_UUID}}{'passphrase'} ne '')) {
            $self->_pasteConnectionPassword();
        } elsif ($action eq 'paste-delete') {
            my $text = $$self{_GUI}{_VTE}->get_clipboard(Gtk3::Gdk::Atom::intern_static_string('CLIPBOARD'))->wait_for_text();
            my $delete = _wEnterValue(
                $$self{_PARENTWINDOW},
                "Enter the String/RegExp of text to be *deleted* when pasting.\nUseful for, for example, deleting 'carriage return' from the text before pasting it.",
                'Use string or Perl RegExps (ex: \n means "carriage return")',
                '\n|\f|\r'
            ) or return 1;
            $text =~ s/$delete//g;
            _vteFeedChild($$self{_GUI}{_VTE}, $text);
        } elsif ($action eq 'hostname') {
            ($$self{CONNECTED} && !$$self{CONNECTING}) and $self->_execute('remote', '<CTRL_TITLE:hostname>', undef, undef, undef);
        } elsif ($action eq 'close') {
            $self->stop(undef, 1);
        } elsif ($action eq 'quit') {
            $PACMain::FUNCS{_MAIN}->_quitProgram;
        } elsif ($action eq 'find') {
            $PACMain::FUNCS{_MAIN}->_showConnectionsList(0);
            $PACMain::FUNCS{_MAIN}{_GUI}{_vboxSearch}->show();
            $PACMain::FUNCS{_MAIN}{_GUI}{_entrySearch}->grab_focus();
        } elsif ($action eq 'closealltabs') {
            $self->_closeAllTerminals();
        } elsif ($action eq 'close-disconected') {
            $self->_closeDisconnectedTerminals();
        } elsif ($action eq 'duplicate') {
            my $terminals = $PACMain::FUNCS{_MAIN}->_launchTerminals([[$$self{_UUID}]]);
            $$self{_NOTEBOOK}->reorder_child ($$terminals[0]->{_GUI}{_VBOX}, $$self{_NOTEBOOK}->page_num($$self{_GUI}{_VBOX}) + 1);
        } elsif ($action eq 'restart') {
            if ($$self{CONNECTED} || $$self{CONNECTING}) {
                $self->_disconnectAndRestartTerminal();
            } else {
                $self->start();
            }
        } elsif ($action eq 'infotab') {
            $self->_showInfoTab();
        } elsif ($action eq 'find-terminal') {
            _wFindInTerminal($self);
        } elsif ($action eq 'showconnections') {
            $PACMain::FUNCS{_MAIN}->_toggleConnectionsList();
        } elsif ($action eq 'edit_node') {
            if (not $$self{_UUID} eq '__PAC_SHELL__') {
                $PACMain::FUNCS{_EDIT}->show($$self{_UUID});
            }
        } elsif ($action =~ /zoom/) {
            $self->_zoomHandler($action);
        } elsif ($action =~ /HOTKEY_CMD:(\w+)/) {
            my $where = $1;
            my ($ask,$cmd) = $PACMain::FUNCS{_KEYBINDS}->GetHotKeyCommand('terminal',$keymask,$$self{_UUID});
            if (!$cmd) {
                return 0;
            }
            if ($where eq 'local') {
                $self->_execute('local', $cmd, $ask);
            } else {
                my $ok = $self->_execute('remote', $cmd, $ask,1,0,0);
                if (($$self{_CLUSTER})&&($ok)) {
                    $self->_clusterCommit(undef, $cmd, undef);
                }
            }
        } elsif ($action eq 'cisco') {
            _vteFeedChildBinary($$self{_GUI}{_VTE}, "\c^x");
            #_vteFeedChildBinary($$self{_GUI}{_VTE}, "\c^");
            #_vteFeedChildBinary($$self{_GUI}{_VTE}, "\c]");
            _vteFeedChildBinary($$self{_GUI}{_VTE}, chr(30) . 'x');
            return 1;
        } else {
            return 0;
        }
        return 1;
    });

    # Right mouse click on VTE
    $$self{_GUI}{_VTE}->signal_connect('button_press_event' => sub {
        if ($right_click_deep) {
            return 0;  # Bubble up, let VTE's original handler take care of it.
        }
        my ($widget, $event) = @_;
        my $state = $event->get_state();
        my $shift = $state * ['shift-mask'];

        if ($event->button eq 2) {
            if (!$$self{_CFG}{'environments'}{$$self{_UUID}}{'send slow'}) {
                return 0;
            }
            $$self{_GUI}{_VTE}->paste_primary();
            $$self{FOCUS}->child_focus('GTK_DIR_TAB_FORWARD');
            return 1;
        } elsif ($event->button eq 3 and $event -> type eq 'button-press') {
            # See #209 for all this hack.
            my $handled_by_vte = 0;
            if (! $shift) {
                $right_click_deep = 1;
                $handled_by_vte = $$self{_GUI}{_VTE}->event($event);
                $right_click_deep = 0;
            }
            if (!$handled_by_vte) {
                $$self{FOCUS}->child_focus('GTK_DIR_TAB_FORWARD');
                $self->_vteMenu($event);
            }
            return 1;  # One way or another, we've handled it.
        }

        return 0;
    });

    # Capture mouse selection on VTE
    $$self{_GUI}{_VTE}->signal_connect('selection_changed' => sub {
        if ($$self{_CFG}{defaults}{'selection to clipboard'}) {
            if ($$self{_GUI}{_VTE}->get_has_selection()) {
                $$self{_GUI}{_VTE}->copy_clipboard();
                my $txt = $$self{_GUI}{_VTE}->get_clipboard(Gtk3::Gdk::Atom::intern_static_string('PRIMARY'))->wait_for_text();
                $txt =~ s/ +$//gm;
                use bytes;
                my $blen = length($txt);
                no bytes;
                Gtk3::Clipboard::get(Gtk3::Gdk::Atom::intern('CLIPBOARD', 0))->set_text($txt, $blen);
            }
        }
        return 0;
    });
    $$self{_GUI}{_VTE}->signal_connect('commit' => sub {
        $self->_clusterCommit(@_);
    });
    $$self{_GUI}{_VTE}->signal_connect('cursor_moved' => sub {
        $$self{_NEW_DATA} = 1;
        $self->_setTabColour();
    });

    # Capture Drag and Drop events
    my @targets = (Gtk3::TargetEntry->new('Ásbrú Connect', [], 0));
    $$self{_GUI}{_VTE}->drag_dest_set('GTK_DEST_DEFAULT_ALL', \@targets, ['move']);
    $$self{_GUI}{_VTE}->signal_connect('drag_drop' => sub {
        if (!$$self{CONNECTED}) {
            _wMessage($$self{_PARENTWINDOW}, "This terminal is <b>DISCONNECTED</b>.\nPlease, start the connection before trying to <b>chain</b>.", 1);
            return 0;
        } elsif ($$self{CONNECTING}) {
            _wMessage($$self{_PARENTWINDOW}, "Please, <b>WAIT for current chain to finish</b> before starting a new one.", 1);
            return 0;
        } elsif ($$self{CONNECTED} && (scalar @{$PACMain::{FUNCS}{_MAIN}{'DND'}{'selection'}} == 1)) {
            my $sel = shift @{$PACMain::{FUNCS}{_MAIN}{'DND'}{'selection'}};
            my $name = $$self{_CFG}{environments}{$sel}{name};
            my $title = $$self{_CFG}{environments}{$sel}{title};
            if (!$self->_wSelectChain($sel)) {
                _wMessage($$self{_PARENTWINDOW}, "No '<b>Expect/Send</b>' data available in:\n<b>$name ($title)</b>\nSo, there are <b>no commands to chain</b>");
            }
            if ($$self{_FOCUSED}) {
                $$self{FOCUS}->child_focus('GTK_DIR_TAB_FORWARD');
            }
            return 1;
        } else {
            if ($$self{_FOCUSED}) {
                $$self{FOCUS}->child_focus('GTK_DIR_TAB_FORWARD');
            }
            return 0;
        }
    });
    $$self{_GUI}{_VTE}->signal_connect('drag_motion' => sub {
        $_[0]->get_parent_window()->raise(); return 1;
    });

    # Depending on terminal creation (window/tab), process connection closing differently
    if (!$$self{_TABBED}) {
        # Capture window close
        $$self{_WINDOWTERMINAL}->signal_connect('delete_event' => sub {
            if (!$$self{_GUILOCKED}) {
                $self->stop(undef, 1);
            }
            return 1;
        });
    }

    # If embedded, add some more callback to manage keyboard focus and messages window
    if ($$self{EMBED}) {
        $$self{_GUI}{_BTNFOCUS}->signal_connect('clicked' => sub {
            if (defined $$self{FOCUS}) {
                $$self{FOCUS}->child_focus('GTK_DIR_TAB_FORWARD');
            }
        });
        $$self{_GUI}{_BTNLOG}->signal_connect ('clicked' => sub {
            if ($$self{_GUI}{_VTE}->is_visible()) {
                # Messages (in Vte) were shown; hide them now
                $self->_hideEmbedMessages();
            } else {
                # Messages (in Vte) were not shown; show them now, and hide the actual embed window
                $self->_showEmbedMessages();
            }
        });
        $$self{_GUI}{_SOCKET_PARENT_WINDOW}->signal_connect('enter-notify-event' => sub {
            if (defined $$self{FOCUS}) {
                $$self{FOCUS}->child_focus('GTK_DIR_TAB_FORWARD');
            }
            return 0;
        });
    }

    # Connect to the "map" signal of macrosbox widget to avoid showing it if so is configured
    if (defined $$self{_GUI}{_MACROSBOX}) {
        $$self{_GUI}{_MACROSBOX}->signal_connect('map' => sub {
            if (!$$self{_NO_UPDATE_CFG}) {
                $self->_updateCFG();
            }
        });
    }

    # Append VTE's connection finalization with CLOSE event
    $$self{_GUI}{_VTE}->signal_connect ('child_exited' => sub {
        if (defined $$self{_GUI}{statusIcon}) {
            $$self{_GUI}{statusIcon}->set_from_stock('asbru-terminal-ko-small', 'button');
        }
        if (defined $$self{_GUI}{statusIcon}) {
            $$self{_GUI}{statusIcon}->set_tooltip_text('Disconnected');
        }
        if (defined $$self{_GUI}{pb}) {
            $$self{_GUI}{pb}->destroy();
        }

        if (!defined $$self{_UUID}) {
            # Signal received too late, terminal is already closed
            return;
        }

        $PACMain::RUNNING{$$self{'_UUID_TMP'}}{'stop_time'} = time();
        $PACMain::FUNCS{_STATS}->stop($$self{_UUID});

        # Update 'CONNECTED' status
        $$self{_LAST_STATUS} = 'DISCONNECTED';
        $$self{CONNECTED} = 0;
        $$self{CONNECTING} = 0;

        # Show a "reconnect" message
        my $string = "DISCONNECTED (PRESS <ENTER> TO RECONNECT)";
        if (!defined($$self{_CFG}{'environments'}{$$self{_UUID}}{'method'})) {
            # Likely the session has been deleted from 'environments', there is no way to restart this session
            $string = "THIS CONNECTION IS NOT AVAILABLE ANYMORE";
        } elsif ($$self{_CFG}{'environments'}{$$self{_UUID}}{'method'} eq 'generic') {
            $string = "EXECUTION FINISHED (PRESS <ENTER> TO EXECUTE AGAIN)";
        }
        if (defined $$self{_GUI}{_VTE}) {
            _vteFeed($$self{_GUI}{_VTE}, "\r\n${COL_RED}$string (" . (localtime(time)) . ")${COL_RESET}\r\n\n");
        }

        # Switch to the message window
        if ($$self{EMBED}) {
            $self->_showEmbedMessages();
        }

        if (defined $$self{_SOCKET_CLIENT_EXEC}) {
            $$self{_SOCKET_CLIENT_EXEC}->close();
        }
        if (defined $$self{_SEND_STRING}) {
            eval {
                Glib::Source->remove($$self{_SEND_STRING});
            };
        }
        $self->_stopEmbedKidnapTimeout();

        # _SOCKET_CLIENT is close so no more watch to expect
        undef $$self{_SOCKET_CLIENT_WATCH};

        $self->_setTabColour();
        $self->_updateStatus();

        # Update Cluster GUI
        $PACMain::FUNCS{_CLUSTER}->_updateGUI();

        if ($$self{_SPLIT} && $$self{_CFG}{'defaults'}{'unsplit disconnected terminals'}) {
            $self->_unsplit();
        }

        $$self{_PID} = 0;

        # Do retry on disconnect
        if ($$self{_RESTART} && $$self{_RECONNECTS} < $$self{_CFG}{'defaults'}{'max retry on disconnect'}) {
            if (!defined $$self{_RECONNECT_WAIT_TIME}) {
                # Using a list of prime numbers to wait more after each retry
                # (see http://neilk.net/blog/2000/06/01/abigails-regex-to-test-for-prime-numbers/)
                @{$$self{_RECONNECT_WAIT_TIME}} = grep { $_ if (1 x $_) !~ /^1?$|^(11+?)\1+$/ } 1..500;
            }
            sleep($$self{_RECONNECT_WAIT_TIME}[min(@{$$self{_RECONNECT_WAIT_TIME}}, $$self{_RECONNECTS})]);
            $$self{_RECONNECTS}++;
            $self->start();
        } else {
            # Check for post-connection commands execution
            $self->_wPrePostExec('local after');

            # And close if so is configured
            if (($$self{_CFG}{'defaults'}{'close terminal on disconnect'}) && (!$$self{_BADEXIT} || $$self{_CFG}{'environments'}{$$self{_UUID}}{'method'} !~ /ssh/i)) {
                $self->stop(undef, 1);
            }
        }

        $self->_updateCFG();

        return 1;
    });

    return 1;
}

sub _watchConnectionData {
    my ($fd, $cond, $self) = @_;

    if (($cond >= 'hup') || ($cond >= 'err')) {
        return 0;
    }

    # This should be as fast as possible, since we are called from a 'data-in' callback from the client socket
    $self->_receiveData();

    while (my $data = shift(@{$self->{_SOCKET_BUFFER}})) {
        $data = decode('UTF-16', $data);

        if ($data eq 'CONNECTED') {
            $$self{_GUI}{statusIcon}->set_from_stock('asbru-terminal-ok-small', 'button');
            $$self{_GUI}{statusIcon}->set_tooltip_text('Connected');
            $$self{_GUI}{statusExpect}->clear();
            $$self{CONNECTED} = 1;
            $$self{CONNECTING} = 0;
            $$self{_BADEXIT} = 0;
            $$self{_RECONNECTS} = 0;
            if (defined $$self{_GUI}{pb}) {
                $$self{_GUI}{pb}->destroy();
            }
            $$self{_GUI}{pb} = undef;
            $$self{_SCRIPT_STATUS} = 'STOP';
            $PACMain::FUNCS{_MAIN}{_HAS_FOCUS} = '';
            $PACMain::FUNCS{_CLUSTER}->_updateGUI();
            $self->_updateCFG();
            $data = $self->_checkSendKeystrokes($data);

            $self->_stopEmbedKidnapTimeout();
            if ($$self{EMBED} && ($$self{_CFG}{environments}{$$self{_UUID}}{method} eq 'RDP (xfreerdp)' || $$self{_CFG}{environments}{$$self{_UUID}}{method} eq 'VNC')) {
                $$self{_EMBED_KIDNAP} = Glib::Timeout->add(500, sub {
                    my $title = 'FreeRDP: ' . $$self{_CFG}{environments}{$$self{_UUID}}{ip} . ($$self{_CFG}{environments}{$$self{_UUID}}{port} == 3389 ? '' : ":$$self{_CFG}{environments}{$$self{_UUID}}{port}");
                    $title = $$self{_CFG}{environments}{$$self{_UUID}}{method} eq 'RDP (xfreerdp)' ?
                    "FreeRDP: $$self{_CFG}{environments}{$$self{_UUID}}{ip}" . ($$self{_CFG}{environments}{$$self{_UUID}}{port} == 3389 ? '' : ":$$self{_CFG}{environments}{$$self{_UUID}}{port}") :
                    "TightVNC: $$self{_CFG}{environments}{$$self{_UUID}}{user}";
                    my $list = _getXWindowsList();
                    if (grep({$_ =~ /$title/ and $title = $_;} keys %{$$list{'by_name'}})) {
                        $$self{_GUI}{_SOCKET}->add_id($$list{'by_name'}{$title}{'xid'});
                    }
                    $$self{_EMBED_KIDNAP} = undef;
                    return 0;
                });
            }

            # Check that the embed window is ready and hide messages window accordingly
            if ($$self{EMBED}) {
                $self->_checkEmbedWindow();
            }

        } elsif ($data =~ /^EXPLORER:(.+)/go) {
            system("xdg-open '$1' &");
        } elsif ($data =~ /^PIPE_WAIT\[(.+?)\]\[(.+)\]/go) {
            my $time = $1;
            my $prompt = $2;

            if (! defined $$self{_GUI}{pb}) {
                $$self{_GUI}{pb} = Gtk3::ProgressBar->new();
                $$self{_GUI}{bottombox}->pack_start($$self{_GUI}{pb}, 0, 1, 0);
                $$self{_GUI}{pb}->show();
            }
            $$self{CONNECTING} = 1;
            $$self{_PULSE} = 1;

            # Prepare a timer to "pulse" the progress bar while executing script
            $$self{_PULSE_TIMER} = Glib::Timeout->add (100, sub {
                if (defined $$self{_GUI}{pb}) {
                    $$self{_GUI}{pb}->pulse;
                    return $$self{_PULSE};
                }
            });
        } elsif ($data =~ /^SCRIPT_(START|STOP)\[NAME:(.+)\]/go) {
            $$self{_PULSE_TIMER} = Glib::Timeout->add (100, sub {defined $$self{_GUI}{pb} and $$self{_GUI}{pb}->pulse; return $$self{_PULSE};});
        }
        elsif ($data =~ /^SCRIPT_(START|STOP)\[NAME:(.+)\]/go) {
            my ($status, $name) = ($1, $2);
            $$self{_SCRIPT_STATUS} = $status;
            $$self{_SCRIPT_NAME} = $name;

            if ($$self{CONNECTING} = $status eq 'START') {
                if (! defined $$self{_GUI}{pb}) {
                    $$self{_GUI}{pb} = Gtk3::ProgressBar->new();
                    $$self{_GUI}{bottombox}->pack_start($$self{_GUI}{pb}, 0, 1, 0);
                    $$self{_GUI}{pb}->show();
                }
                $$self{_PULSE} = 1;

                # Prepare a timer to "pulse" the progress bar while executing script
                $$self{_PULSE_TIMER} = Glib::Timeout->add (100, sub {
                    if (defined $$self{_GUI}{pb}) {
                        $$self{_GUI}{pb}->pulse;
                        return $$self{_PULSE};
                    }
                });
            } else {
                $$self{_PULSE} = 0;
                if (defined $$self{_GUI}{pb}) {
                    $$self{_GUI}{pb}->destroy();
                }
                $$self{_GUI}{pb} = undef;
                $PACMain::FUNCS{_CLUSTER}->_updateGUI();
            }
        } elsif ($data =~ /^SCRIPT_SUB_(.+)\[NAME:(.+)\]\[PARAMS:(.*)\]/go) {
            my ($func, $name, $params) = ($1, $2, $3);
            $data = "Ásbrú Script '$name' --> $func($params)";
        } elsif ($data =~ /^TITLE:(.+)/go) {
            my $t = $1;
            if ($t !~ /<\w+:.+?>/) {
                $$self{_TITLE} = $t;
                $self->_updateCFG();
            }
        } elsif ($data =~ /^GET_TITLE:/go) {
            $self->_sendData("GET_TITLE|:|$$self{_TITLE}");
        } elsif ($data =~ /^PAC_CONN_MSG:(.+)/go) {
            _wMessage($$self{_PARENTWINDOW}, $1, 1);
            next;
        } elsif ($data eq 'RESTART') {
            $$self{_RESTART} = 1;
        } elsif ($data =~ /^CHAIN:(.+):(.+):(.+):(.+)/go) {
            my ($chain_name, $chain_uuid, $exp_partial, $exp_total) = ($1, $2, $3, $4);
            $$self{_GUI}{statusExpect}->set_from_stock('gtk-media-play', 'button');
            $$self{_GUI}{statusExpect}->set_tooltip_text("Expect / Execute: $1 / $2");
            $$self{_PULSE} = 0;
            if (! defined $$self{_GUI}{pb}) {
                $$self{_GUI}{pb} = Gtk3::ProgressBar->new();
                $$self{_GUI}{bottombox}->pack_start($$self{_GUI}{pb}, 0, 1, 0);
                $$self{_GUI}{pb}->show();
            }
            $$self{_GUI}{pb}->set_fraction($exp_partial / $exp_total);
            $$self{CONNECTING} = 1;
        } elsif ($data eq 'EXEC:RECEIVE_OUT') {
            my $rin = '';
            vec($rin, fileno($$self{_SOCKET_CLIENT_EXEC}), 1) = 1;
            select($rin, undef, undef, 2) or return 1;
            $$self{_EXEC}{RECEIVED} = undef;
            eval {$$self{_EXEC}{RECEIVED} = ${fd_retrieve($$self{_SOCKET_CLIENT_EXEC})};};
            if ($@) {_wMessage($$self{_PARENTWINDOW}, "ERROR: Could not retrieve output from command execution:\n$@"); return 1;}
            if (defined $$self{_EXEC}{RECEIVED}) {
                $$self{_EXEC_PROCESS} = Glib::Timeout->add(100, sub {$self->_pipeExecOutput; return 0;});
            }
        } elsif ($data =~ /^SENDSLOW:(.+)/go) {
            my $txt = $1;
            $$self{_PULSE} = 1;
            if (! defined $$self{_GUI}{pb}) {
                $$self{_GUI}{pb} = Gtk3::ProgressBar->new();
                $$self{_GUI}{bottombox}->pack_start($$self{_GUI}{pb}, 0, 1, 0);
                $$self{_GUI}{pb}->show();
            }
            # Prepare a timer to "pulse" the progress bar while connecting
            $$self{_PULSE_TIMER} = Glib::Timeout->add (100, sub {
                if ($$self{_PULSE} && defined $$self{_GUI}{pb} && $$self{_GUI}{pb}->get_property('visible')) {
                    $$self{_GUI}{pb}->pulse;
                    return 1;
                } else {
                    delete $$self{_PULSE_TIMER};
                    return 0;
                }
            });
        } elsif (($data eq 'DISCONNECTED') || ($data =~ /^CLOSE:.+/go) || ($data =~ /^TIMEOUT:.+/go) || ($data =~ /^connect\(\) failed with error '.+'$/go)) {
            $self->_stopEmbedKidnapTimeout();
            if ($$self{EMBED}) {
                $self->_showEmbedMessages();
            }
            $$self{_GUI}{statusExpect}->clear;
            $$self{_BADEXIT} = $$self{CONNECTING};
            $self->_disconnectTerminal();
        } elsif ($data =~ /^EXPECT:WAITING:(.+)/go) {
            $$self{_GUI}{statusExpect}->set_from_stock('gtk-media-play', 'button');
            $$self{_GUI}{statusExpect}->set_tooltip_text("Expecting '$1'");
            $$self{_PULSE} = 0;
            $$self{_GUI}{pb}->set_fraction(++$$self{_EXPECTED} / $$self{_TOTAL});
            $$self{CONNECTING} = 1;
        } elsif ($data =~ /^SPAWNED:'(.+)'\s*\(PID:(\d+)\)$/go) {
            $$self{_CMD} = $1;
            $$self{_PID} = $2;
            $$self{CONNECTING} = 1;
            $$self{_RESTART} = 0;
        } elsif ($data eq 'HIDE_TERMINAL') {
            if (defined $$self{_WINDOWTERMINAL}) {
                $$self{_WINDOWTERMINAL}->hide();
            }
        } elsif ($data =~ /^WENTER\|/) {
            $PACMain::FUNCS{_MAIN}{_HAS_FOCUS} = '';
            my ($cmd,$lblup,$lbldown,$default,$visible) = split /\|:\|/,$data;
            my ($val,$pos) = _wEnterValue($$self{_PARENTWINDOW},$lblup,$lbldown,$default,$visible);
            if (defined $$self{_WINDOWTERMINAL}) {
                $$self{_WINDOWTERMINAL}->grab_focus();
                $PACMain::FUNCS{_MAIN}{_HAS_FOCUS} = $$self{_WINDOWTERMINAL};
            }
            $self->_sendData("WENTER|:|$val|:|$pos");
        }

        $$self{_LAST_STATUS} = $data;
    }

    $self->_setTabColour();
    $self->_updateStatus();

    return 1;
}

sub _receiveData {
    my $self = shift;
    my $socket = shift // $$self{_SOCKET_CLIENT};

    my $buffer = '';
    $$self{_SOCKET_BUFFER} = ();

    my $data = '';
    my $bytes;

    # At least one read should be done
    do {
        $bytes = sysread($socket, $data, 1024) // 0;
        if (!defined $bytes) {
            last;
        }

        $buffer .= $data;
        chomp $buffer;

        $buffer =~ s/\R/ /go;

        my $empty_buffer = 0;
        while ($buffer =~ s/PAC_MSG_START\[(.+?)\]PAC_MSG_END/$1/o) {
            my $buffer = $1;
            if (!$buffer) {
                next;
            }
            push(@{$$self{_SOCKET_BUFFER}}, $buffer);
            $empty_buffer = 1;
        }
        $empty_buffer and $buffer = '';

    } until $bytes < 1024;

    return 1;
}

# Send data back to the terminal or the defined socket
sub _sendData {
    my $self = shift;
    my $msg = shift // '';
    my $socket = shift // $$self{_SOCKET_CLIENT};

    $msg = encode('UTF-16', $msg);
    $socket->send("PAC_MSG_START[$msg]PAC_MSG_END");
}

sub _authClient {
    my $self = shift;
    my $socket = shift;

    # Make sure that this client is a PAC client:
    $self->_receiveData($socket);
    my $data = shift(@{$self->{_SOCKET_BUFFER}});
    $data = decode('UTF-16', $data);

    if ($data ne "!!_PAC_AUTH_[$$self{_UUID_TMP}]!!") {
        return 0;
    }

    $socket->send("!!_PAC_AUTH_[$$self{_UUID_TMP}]!!");

    return 1;
}

sub _vteMenu {
    my $self = shift;
    my $event = shift;

    my @vte_menu_items;

    push(@vte_menu_items, {
        label => "Show Terminal Keybindings",
        stockicon => 'gtk-help',
        sensitive => 1,
        code => sub {
            _wMessage($$self{_PARENTWINDOW},$PACMain::FUNCS{_KEYBINDS}->ListKeyBindings('terminal'),1,0,'w-info');
        }
    });
    # If PAC Script running, show a STOP script menuitem
    if ($$self{_SCRIPT_STATUS} ne 'STOP') {
        push(@vte_menu_items,
        {
            label => "Stop script '$$self{_SCRIPT_NAME}'",
            stockicon => 'gtk-media-stop',
            sensitive => 1,
            code => sub {
                $self->_disconnectTerminal();
            }
        });

        _wPopUpMenu(\@vte_menu_items, $event);
        return 1,
    }

    if (!$$self{_CFG}{'defaults'}{'hide connections submenu'}) {
        # Add a submenu with available connections (including: LOCAL SHELL) and chaining connections
        push(@vte_menu_items, {
            label => 'Connection',
            stockicon => 'asbru-group',
            submenu =>
            [
                {
                    label => 'Favourites',
                    stockicon => 'asbru-favourite-on',
                    submenu => _menuFavouriteConnections($self)
                },
                {
                    label => 'All',
                    stockicon => 'asbru-treelist',
                    submenu =>
                    [
                        {label => 'Local Shell', stockicon => 'gtk-home', code => sub {$PACMain::FUNCS{_MAIN}{_GUI}{shellBtn}->clicked;}},
                        {separator => 1},
                        @{_menuAvailableConnections($PACMain::FUNCS{_MAIN}{_GUI}{treeConnections}{data}, $self)}
                    ]
                },
            ]
        });
    }

    # Show a popup with the opened tabs (if tabbed!!)
    if ($$self{_TABBED}) {
        my @submenu_split_v;
        my @submenu_split_h;
        foreach my $uuid_tmp (keys %PACMain::RUNNING) {
            if (!defined $PACMain::RUNNING{$uuid_tmp}{terminal}{_SPLIT}) {
                next;
            }
            my $i = $$self{_NOTEBOOK}->page_num($PACMain::RUNNING{$uuid_tmp}{terminal}{_SPLIT} ? $PACMain::RUNNING{$uuid_tmp}{terminal}{_SPLIT_VPANE} : $PACMain::RUNNING{$uuid_tmp}{terminal}{_GUI}{_VBOX});
            if ($uuid_tmp eq $$self{_UUID_TMP} || $PACMain::RUNNING{$uuid_tmp}{terminal}{_TITLE} eq 'Info ' || $i < 0) {
                next;
            }
            if (($$self{_SPLIT} || $PACMain::RUNNING{$uuid_tmp}{terminal}{_SPLIT}) || (! $PACMain::RUNNING{$uuid_tmp}{terminal}{_TABBED})) {
                next;
            }
            push(@submenu_split_v,
            {
                label => "$i: $PACMain::RUNNING{$uuid_tmp}{terminal}{_TITLE}",
                tooltip => "Arrange both connections ($$self{_TITLE}) and ($PACMain::RUNNING{$uuid_tmp}{terminal}{_TITLE}) into the same vertically split window.",
                code => sub {$self->_split($uuid_tmp);}
            });
            push(@submenu_split_h,
            {
                label => "$i: $PACMain::RUNNING{$uuid_tmp}{terminal}{_TITLE}",
                tooltip => "Arrange both connections ($$self{_TITLE}) and ($PACMain::RUNNING{$uuid_tmp}{terminal}{_TITLE}) into the same horizontally split window .",
                code => sub {$self->_split($uuid_tmp, 1);}
            });
        }
        @submenu_split_v = sort {$$a{label} cmp $$b{label}} @submenu_split_v;
        @submenu_split_h = sort {$$a{label} cmp $$b{label}} @submenu_split_h;

        push(@vte_menu_items,
        {
            sensitive => 1,
            label => 'Detach tab to a new Window',
            stockicon => 'gtk-fullscreen',
            shortcut => $PACMain::FUNCS{_KEYBINDS}->GetAccelerator('terminal','fullscreen'),
            tooltip => 'Separate this connection window from the tabbed view, and put it in a separate window',
            code => sub {$self->_tabToWin();}
        });

        if ($$self{_SPLIT}) {
            push(@vte_menu_items,
            {
                label => 'Unsplit',
                stockicon => 'gtk-zoom-fit',
                tooltip => "Remove the split view and put each connection into its own tab",
                code => sub {$self->_unsplit();}
            });
            push(@vte_menu_items,
            {
                label => 'Equally resize terminals',
                stockicon => 'gtk-zoom-fit',
                tooltip => "Resize terminals equally",
                code => sub {$self->_equalresize();}
            });
        } else {
            push(@vte_menu_items,
            {
                label => 'Split',
                stockicon => 'gtk-zoom-fit',
                sensitive => scalar(@submenu_split_v) && scalar(@submenu_split_h),
                submenu =>
                [
                    {
                        label => 'Vertically',
                        stockicon => 'gtk-zoom-fit',
                        submenu => \@submenu_split_v,
                        sensitive => scalar(@submenu_split_v)
                    },
                    {
                        label => 'Horizontally',
                        stockicon => 'gtk-zoom-fit',
                        submenu => \@submenu_split_h,
                        sensitive => scalar(@submenu_split_h)
                    }
                ]
            });
        }
        push(@vte_menu_items, {separator => 1});
    } else {
        push(@vte_menu_items,
        {
            label => 'Attach Window to main tab bar',
            stockicon => 'gtk-leave-fullscreen',
            tooltip => 'Put this connection window into main tabbed window',
            code => sub {_winToTab($self);}
        });
        push(@vte_menu_items, {separator => 1});
    }

    # Prepare the "Add to Cluster" submenu...
    my @submenu_cluster;
    my %clusters;
    push(@submenu_cluster,
    {
        label => 'New Cluster...',
        stockicon => 'gtk-new',
        tooltip => 'Create a new cluster and put this connection in it',
        code => sub {
            my $cluster = _wEnterValue($$self{_PARENTWINDOW}, 'Enter a name for the <b>New Cluster</b>');
            if ((! defined $cluster) || ($cluster =~ /^\s*$/go)) {
                return 1;
            }
            $PACMain::FUNCS{_CLUSTER}->addToCluster($$self{_UUID_TMP}, $cluster);
        }
    });
    foreach my $uuid_tmp (keys %PACMain::RUNNING) {
        if (!defined $PACMain::RUNNING{$uuid_tmp}{terminal}{_CLUSTER} || $PACMain::RUNNING{$uuid_tmp}{terminal}{_CLUSTER} eq '') {
            next;
        }
        $clusters{$PACMain::RUNNING{$uuid_tmp}{terminal}{_CLUSTER}}{total}++;
        $clusters{$PACMain::RUNNING{$uuid_tmp}{terminal}{_CLUSTER}}{connections} .= "$PACMain::RUNNING{$uuid_tmp}{terminal}{_NAME}\n";
    }
    foreach my $cluster (sort {$a cmp $b} keys %clusters) {
        my $tmp = $cluster;
        push(@submenu_cluster,
        {
            label => "$cluster ($clusters{$cluster}{total} terminals connected)",
            tooltip => "Add to selected cluster, with connections:\n" . $clusters{$cluster}{connections},
            sensitive => $cluster ne $$self{_CLUSTER},
            code => sub {$PACMain::FUNCS{_CLUSTER}->addToCluster($$self{_UUID_TMP}, $tmp);}
        });
    }
    # Add to cluster
    push(@vte_menu_items,
    {
        label => ($$self{_CLUSTER} eq '' ? 'Add' : 'Change') . ' to Cluster',
        stockicon => 'gtk-add',
        sensitive => 1,
        submenu => \@submenu_cluster
    });
    # Remove from cluster
    push(@vte_menu_items,
    {
        label => 'Remove from Cluster',
        stockicon => 'gtk-delete',
        shortcut => $PACMain::FUNCS{_KEYBINDS}->GetAccelerator('terminal','remove_from_cluster'),
        tooltip => $$self{_CLUSTER} ne '' ? "Remove this connection from cluster '$$self{_CLUSTER}'" : '',
        sensitive => $$self{_CLUSTER} ne '',
        code => sub {$PACMain::FUNCS{_CLUSTER}->delFromCluster($$self{_UUID_TMP}, $$self{_CLUSTER});}
    });
    # Show the PCC
    push(@vte_menu_items,
    {
        label => 'Power Cluster Controller',
        stockicon => 'gtk-justify-fill',
        sensitive => 1,
        tooltip => 'Bring up the Power Cluster Controller GUI',
        code => sub {$PACMain::FUNCS{_PCC}->show();}
    });
    push(@vte_menu_items, {separator => 1});

    # Show the list of available PAC Scripts to execute
    my @scripts_sub_menu;
    my $sl = $PACMain::FUNCS{_SCRIPTS}->scriptsList;
    foreach my $name (sort {$a cmp $b} keys %{$sl}) {
        my $file = $$sl{$name};
        push(@scripts_sub_menu,
        {
            label => $name,
            stockicon => 'gtk-execute',
            sensitive => $$self{CONNECTED},
            tooltip => "Exec the CONNECTIONS part of '$name' in this connection",
            code => sub {$PACMain::FUNCS{_SCRIPTS}->_execScript($name,$self->{_PARENTWINDOW},$$self{_UUID_TMP});}
        });
    }
    push(@vte_menu_items,
    {
        label => 'Execute Script',
        stockicon => 'asbru-script',
        tooltip => 'Execute selected Ásbrú Script in this connection',
        submenu => \@scripts_sub_menu,
    });

    # Show the list of REMOTE commands to execute
    my @cmd_remote_sub_menu;
    # Organize Remote commands by groups, Join Terminal Macros they are the same
    my %hgs;
    my $lg;
    foreach my $hash (@{$$self{_CFG}{'defaults'}{'remote commands'}},@{$self->{_CFG}{'environments'}{$$self{_UUID}}{'macros'}}) {
        my $cmd = ref($hash) ? $$hash{txt} : $hash;
        my $desc = ref($hash) ? $$hash{description} : $hash;
        my $confirm = ref($hash) ? $$hash{confirm} : 0;
        my $intro = ref($hash) ? $$hash{intro} : 0;
        if ($cmd eq '') {
            next;
        }
        my ($g,$d) = split /:/,$desc,2;
        if (!$d) {
            $d = $g;
            $g = 'Other???';
        }
        push (@{$hgs{$g}}, {
            label => $d,
            sensitive => $$self{CONNECTED},
            tooltip => $cmd,
            stockicon => $confirm ? 'gtk-dialog-question' : '',
            code => sub {
                my $ok = $self->_execute('remote', $cmd, $confirm,1,0,$intro);
                if (($$self{_CLUSTER})&&($ok)) {
                    if ($intro) {
                        $intro = "\n";
                    } else {
                        $intro = "";
                    }
                    $self->_clusterCommit(undef, "$cmd$intro", undef);
                }
            }
        });
    }
    # Create submenus except 'Others'
    foreach my $g (sort keys %hgs) {
        if ($g eq 'Other???') {
            next;
        }
        push(@cmd_remote_sub_menu, {
            label => $g,
            stockicon => 'gtk-execute',
            submenu => \@{$hgs{$g}},
        });
    }
    # Push Others at the end with no group
    if ((defined $hgs{'Other???'})&&(@{$hgs{'Other???'}})) {
        push(@cmd_remote_sub_menu,@{$hgs{'Other???'}});
    }
    push(@vte_menu_items, {
        label => 'Remote commands',
        stockicon => 'gtk-execute',
        tooltip => 'Send to this connection the selected command (keypresses)',
        submenu => \@cmd_remote_sub_menu,
    });

    # Show the list of LOCAL commands to execute
    my @cmd_local_sub_menu;
    foreach my $hash (@{$self->{_CFG}{'environments'}{$$self{_UUID}}{'local connected'}}) {
        my $cmd = ref($hash) ? $$hash{txt} : $hash;
        my $desc = ref($hash) ? $$hash{description} : $hash;
        my $confirm = ref($hash) ? $$hash{confirm} : 0;
        if ($cmd eq '') {
            next;
        }
        push(@cmd_local_sub_menu,
        {
            label => ($confirm ? 'CONFIRM: ' : '') . ($desc ? $desc : $cmd),
            tooltip => $desc ? $cmd : $desc,
            stockicon => $confirm ? 'gtk-dialog-question' : '',
            code => sub {$self->_execute('local', $cmd, $confirm)}
        });
    }
    foreach my $hash (@{$$self{_CFG}{'defaults'}{'local commands'}}) {
        my $cmd = ref($hash) ? $$hash{txt} : $hash;
        my $desc = ref($hash) ? $$hash{description} : $hash;
        my $confirm = ref($hash) ? $$hash{confirm} : 0;
        if ($cmd eq '') {
            next;
        }
        push(@cmd_local_sub_menu,
        {
            label => ($confirm ? 'CONFIRM: ' : '') . ($desc ? $desc : $cmd),
            tooltip => $desc ? $cmd : $desc,
            sensitive => $$self{CONNECTED},
            stockicon => $confirm ? 'gtk-dialog-question' : '',
            code => sub {$self->_execute('local', $cmd, $confirm)}
        });
    }
    push(@vte_menu_items,
    {
        label => 'Local commands',
        stockicon => 'gtk-execute',
        tooltip => 'Execute LOCALLY (in YOUR computer) the selected command',
        submenu => \@cmd_local_sub_menu,
    });

    my @insert_menu_items;

    # Populate with user defined variables
    my @variables_menu;
    my $i = 0;
    foreach my $value (map{$_->{txt} // ''} @{$$self{variables}}) {
        my $j = $i;
        push(@variables_menu,
        {
            #label => "<V:$j> ($value)",
            #code => sub {_vteFeedChild($$self{_GUI}{_VTE}, _subst("<V:$j>", $$self{_CFG}, $$self{_UUID}));}
            label => __($j),
            tooltip => "$j=$value",
            code => sub {my $t = _subst("<V:$j>", $$self{_CFG}, $$self{_UUID}); _vteFeedChild($$self{_GUI}{_VTE}, $t);}
        });
        ++$i;
    }
    push(@insert_menu_items,
    {
        label => 'User variables...',
        sensitive => scalar @{$$self{variables}},
        submenu => \@variables_menu
    });

    # Populate with global defined variables
    my @global_variables_menu;
    foreach my $var (sort {$a cmp $b} keys %{$PACMain::FUNCS{_MAIN}{_CFG}{'defaults'}{'global variables'}}) {
        my $val = $PACMain::FUNCS{_MAIN}{_CFG}{'defaults'}{'global variables'}{$var}{'value'};
        push(@global_variables_menu,
        {
            label => __($var),
            tooltip => "$var=$val",
            code => sub {my $t = _subst("<GV:$var>", $$self{_CFG}, $$self{_UUID}); _vteFeedChild($$self{_GUI}{_VTE}, $t);}
        });
    }
    push(@insert_menu_items,
    {
        label => 'Global variables...',
        sensitive => scalar(@global_variables_menu),
        submenu => \@global_variables_menu
    });

    # Populate with environment variables
    my @environment_menu;
    foreach my $key (sort {$a cmp $b} keys %ENV) {
        # Do not offer Master Password, or any other environment variable with word PRIVATE, TOKEN
        if ($key =~ /KPXC|PRIVATE|TOKEN/i) {
            next;
        }
        my $value = $ENV{$key};
        push(@environment_menu,
        {
            label => __($key),
            tooltip => "$key=$value",
            code => sub {my $t = _subst("<ENV:$key>", $$self{_CFG}, $$self{_UUID}); _vteFeedChild($$self{_GUI}{_VTE}, $t);}
        });
    }
    push(@insert_menu_items,
    {
        label => 'Environment variables...',
        submenu => \@environment_menu
    });

    push(@vte_menu_items,
    {
        label => 'Insert value',
        stockicon => 'gtk-edit',
        tooltip => 'Send selected local/global/environment value to terminal',
        submenu => \@insert_menu_items,
    });

    push(@vte_menu_items, {separator => 1});

    # Copy
    push(@vte_menu_items,
    {
        label => 'Copy',
        stockicon => 'gtk-copy',
        shortcut => $PACMain::FUNCS{_KEYBINDS}->GetAccelerator('terminal','copy'),
        code => sub {$$self{_GUI}{_VTE}->copy_clipboard();}
    });
    # Copy Connection Password
    if (($$self{_CFG}{environments}{$$self{_UUID}}{'pass'} ne '')||($$self{_CFG}{environments}{$$self{_UUID}}{'passphrase'} ne '')) {
        push(@vte_menu_items, {
            label => 'Copy Connection Password',
            stockicon => 'gtk-copy',
            sensitive => $$self{CONNECTED},
            code => sub {
                _copyPass($$self{_UUID});
            }
        });
    };
    # Paste
    push(@vte_menu_items,
    {
        label => 'Paste',
        stockicon => 'gtk-paste',
        shortcut => $PACMain::FUNCS{_KEYBINDS}->GetAccelerator('terminal','paste'),
        sensitive => $$self{CONNECTED} && $$self{_GUI}{_VTE}->get_clipboard(Gtk3::Gdk::Atom::intern_static_string('CLIPBOARD'))->wait_is_text_available(),
        code => sub {
            $$self{_GUI}{_VTE}->paste_clipboard();
        }
    });
    # Paste Current Connection Password
    if (($$self{_CFG}{environments}{$$self{_UUID}}{'pass'} ne '')||($$self{_CFG}{environments}{$$self{_UUID}}{'passphrase'} ne '')) {
        push(@vte_menu_items,
        {
            label => 'Paste Connection Password',
            stockicon => 'gtk-paste',
            shortcut => $PACMain::FUNCS{_KEYBINDS}->GetAccelerator('terminal','paste-passwd'),
            code => sub {
                $self->_pasteConnectionPassword();
            }
        });
    };
    # Paste Special
    push(@vte_menu_items,
    {
        label => 'Paste and Delete...',
        stockicon => 'gtk-paste',
        shortcut => $PACMain::FUNCS{_KEYBINDS}->GetAccelerator('terminal','paste-delete'),
        tooltip => 'Paste clipboard contents, but remove any Perl RegExp matching string from the appearing prompt GUI',
        sensitive => $$self{CONNECTED} && $$self{_GUI}{_VTE}->get_clipboard(Gtk3::Gdk::Atom::intern_static_string('CLIPBOARD'))->wait_is_text_available(),
        code => sub {
            my $text = $$self{_GUI}{_VTE}->get_clipboard(Gtk3::Gdk::Atom::intern_static_string('CLIPBOARD'))->wait_for_text();
            my $delete = _wEnterValue(
                $$self{_PARENTWINDOW},
                "Enter the String/RegExp of text to be *deleted* when pasting.\nUseful for, for example, deleting 'carriage return' from the text before pasting it.",
                'Use string or Perl RegExps (ex: \n means "carriage return")',
                '\n|\f|\r'
            ) or return 1;
            $text =~ s/$delete//g;
            _vteFeedChild($$self{_GUI}{_VTE}, $text);
        }
    });

    # Add find string
    push(@vte_menu_items, {separator => 1});
    push(@vte_menu_items, {label => 'Find...', stockicon => 'gtk-find', shortcut => $PACMain::FUNCS{_KEYBINDS}->GetAccelerator('terminal','find-terminal'), code => sub {$self->_wFindInTerminal(); return 1;}});

    # Add save session log
    push(@vte_menu_items, {label => 'Save session log...', stockicon => 'gtk-save', code => sub{$self->_saveSessionLog;}});

    # Add edit session
    push(@vte_menu_items, {label => 'Edit session...', stockicon => 'gtk-edit', sensitive => $$self{_UUID} ne '__PAC_SHELL__', code => sub{$PACMain::FUNCS{_EDIT}->show($$self{_UUID});}});

    # Add change temporary tab label
    push(@vte_menu_items, {label => 'Temporary TAB Label change...', stockicon => 'gtk-edit', code => sub {
        # Prepare the input window
        my $new_label = _wEnterValue(
            $$self{_PARENTWINDOW},
            "<b>Temporaly renaming label '@{[__($$self{_TITLE})]}'</b>",
            'Enter the new temporal label:', $$self{_TITLE}
        );
        if ((defined $new_label) && ($new_label !~ /^\s*$/go)) {
            $$self{_TITLE} = $new_label;
        }
        $self->_setTabColour();
    }});

    # Change title with guessed hostname
    push(@vte_menu_items, {label => 'Set title with guessed hostname', sensitive => ($$self{CONNECTED} && ! $$self{CONNECTING}), code => sub {$self->_execute('remote', '<CTRL_TITLE:hostname>', undef, undef, undef);}});

    # Open file explorer on current directory (for PAC Shells only)
    $$self{_UUID} eq '__PAC_SHELL__' and push(@vte_menu_items, {label => 'Open file manager on current dir', stockicon => 'gtk-open', sensitive => ($$self{CONNECTED} && ! $$self{CONNECTING}), code => sub {$self->_execute('remote', 'xdg-open .', undef, undef, undef);}});

    # Add take screenshot
    push(@vte_menu_items, {label => 'Take Screenshot', stockicon => 'gtk-media-record', sensitive => $$self{_UUID} ne '__PAC_SHELL__', code => sub {
        my $screenshot_file = '';
        $screenshot_file = '/tmp/asbru_screenshot_' . rand(123456789). '.png';
        while(-f $screenshot_file) {
            $screenshot_file = '/tmp/asbru_screenshot_' . rand(123456789). '.png';
        }
        select(undef, undef, undef, 0.5);
        _screenshot($$self{_GUI}{_VBOX}, $screenshot_file);
        $PACMain::FUNCS{_MAIN}{_GUI}{screenshots}->add($screenshot_file, $self->{_CFG}{'environments'}{$$self{_UUID}});
        $PACMain::FUNCS{_MAIN}->_updateGUIPreferences();
    }});

    push(@vte_menu_items, {separator => 1});

    if (($$self{_CFG}{environments}{$$self{_UUID}}{method} =~ /^.*ssh.*$/) || ($$self{_CFG}{environments}{$$self{_UUID}}{method} eq 'SSH')) {
        # Open SFTP to this connection if it is SSH
        push(@vte_menu_items, {
            label => 'Open new SFTP window',
            stockicon => 'asbru-method-SFTP',
            shortcut => $PACMain::FUNCS{_KEYBINDS}->GetAccelerator('terminal','sftp'),
            sensitive => 1,
            code => sub {
                $self->_openSFTP();
            }
        });
    }

    # Terminal reset options
    push(@vte_menu_items,
    {
        label => 'Terminal',
        stockicon => 'asbru-shell',
        sensitive => 1,
        submenu =>
        [
            {
                label => 'Reset',
                stockicon => 'gtk-refresh',
                shortcut => $PACMain::FUNCS{_KEYBINDS}->GetAccelerator('terminal','reset'),
                sensitive => 1,
                code => sub{$$self{_GUI}{_VTE}->reset(1, 0);}
            },
            {
                label => 'Reset and clear',
                stockicon => 'gtk-refresh',
                shortcut => $PACMain::FUNCS{_KEYBINDS}->GetAccelerator('terminal','reset-clear'),
                sensitive => 1,
                code => sub{$$self{_GUI}{_VTE}->reset(1, 1);}
            }
        ]
    });

    # Session options
    push(@vte_menu_items,
    {
        label => 'Session',
        stockicon => 'asbru-method-' . $$self{_CFG}{environments}{$$self{_UUID}}{method},
        sensitive => 1,
        submenu =>
        [
            # Start/stop automatic string sending
            {
                label => (defined $$self{_SEND_STRING} ? 'Stop' : 'Start') . ' programatically string sending',
                tooltip => $$self{_CFG}{environments}{$$self{_UUID}}{'send string txt'} ne '' ? ($$self{_CFG}{environments}{$$self{_UUID}}{'send string txt'} . "\nEvery: " . ($$self{_CFG}{environments}{$$self{_UUID}}{'send string every'}) . ' seconds') : '',
                sensitive => $$self{_CFG}{environments}{$$self{_UUID}}{'send string txt'} ne '',
                stockicon => defined $$self{_SEND_STRING} ? 'gtk-stop' : 'gtk-media-play',
                code => sub {
                    if (defined $$self{_SEND_STRING}) {
                        Glib::Source->remove($$self{_SEND_STRING});
                        undef $$self{_SEND_STRING};
                    } else {
                        defined $$self{_SEND_STRING} and Glib::Source->remove($$self{_SEND_STRING});
                        $$self{_SEND_STRING} = Glib::Timeout->add_seconds($$self{_CFG}{environments}{$$self{_UUID}}{'send string every'}, sub {
                            if (!$$self{CONNECTED}) {
                                return 1;
                            }

                            my $txt = $$self{_CFG}{environments}{$$self{_UUID}}{'send string txt'};
                            my $intro = $$self{_CFG}{environments}{$$self{_UUID}}{'send string intro'};
                            $txt = _subst($txt, $$self{_CFG}, $$self{_UUID});
                            _vteFeedChild($$self{_GUI}{_VTE}, $txt . ($intro ? "\n" : ''));

                            return 1;
                        });
                    }
                }
            },
            # Duplicate connection
            {
                label => 'Duplicate connection',
                stockicon => 'gtk-copy',
                code => sub {
                    $PACMain::FUNCS{_MAIN}->_launchTerminals([[$$self{_UUID}]]);
                }
            },
            # Restart session
            {
                label => 'Restart session',
                stockicon => 'gtk-execute',
                sensitive => ! $$self{CONNECTED} || ! $$self{_PID},
                code => sub{
                    $self->start();
                }
            },
            # Disconnect
            {
                label => 'Disconnect',
                stockicon => 'gtk-stop',
                shortcut => $PACMain::FUNCS{_KEYBINDS}->GetAccelerator('terminal','disconnect'),
                sensitive => $$self{_PID},
                code => sub {
                    $self->_disconnectTerminal();
                }
            },
            # Disconnect and restart session
            {
                label => 'Disconnect and Restart session',
                stockicon => 'gtk-refresh',
                shortcut => $PACMain::FUNCS{_KEYBINDS}->GetAccelerator('terminal','restart'),
                sensitive => $$self{CONNECTED} && $$self{_PID},
                code => sub {
                    $self->_disconnectAndRestartTerminal();
                }
            },
            # Close terminal
            {
                label => 'Close Terminal',
                stockicon => 'gtk-close',
                shortcut => $PACMain::FUNCS{_KEYBINDS}->GetAccelerator('terminal','close'),
                code => sub {
                    $self->stop(0, 1);
                }
            },
            # Close all terminals
            {
                label => 'Close All Terminals',
                shortcut => $PACMain::FUNCS{_KEYBINDS}->GetAccelerator('terminal','closeallterminals'),
                stockicon => 'gtk-close',
                sensitive => $self->_hasOtherTerminals(),
                code => sub {
                    $self->_closeAllTerminals();
                }
            },
            # Close disconnected terminals
            {
                label => 'Close Disconnected Terminals',
                stockicon => 'gtk-close',
                shortcut => $PACMain::FUNCS{_KEYBINDS}->GetAccelerator('terminal','close-disconected'),
                sensitive => $self->_hasDisconnectedTerminals(),
                code => sub {
                    $self->_closeDisconnectedTerminals();
                }
            }
        ]
    });

    _wPopUpMenu(\@vte_menu_items, $event);
    return 1;
}

sub _setTabColour {
    my $self = shift;
    my $i = shift // 1;

    # Auto take screenshots of connections without any of them
    # Disable auto screen shots on compact mode
    if (($$self{_CFG}{'defaults'}{'layout'} ne 'Compact') && (defined $$self{_TAKE_SCREENSHOT} && scalar(@{$$self{_CFG}{environments}{$$self{_UUID}}{screenshots}}))) {
        if (($$self{_UUID} ne '__PAC__QUICK__CONNECT__') && ($$self{_UUID} ne '__PAC_SHELL__') && $$self{'_CFG'}{'defaults'}{'show screenshots'}) {
            $$self{_TAKE_SCREENSHOT} = Glib::Timeout->add_seconds($$self{_CFG}{environments}{$$self{_UUID}}{method} =~ /rdesktop|RDP/go ? 10 : 2, sub {
                if ((! $$self{CONNECTED}) || (! $$self{_FOCUSED})) {
                    return 1;
                }

                my $screenshot_file = '';
                $screenshot_file = '/tmp/asbru_screenshot_' . rand(123456789). '.png';
                while(-f $screenshot_file) {$screenshot_file = '/tmp/asbru_screenshot_' . rand(123456789). '.png';}
                _screenshot($$self{EMBED} ? $$self{FOCUS} : $$self{_GUI}{_VBOX}, $screenshot_file);
                $PACMain::FUNCS{_MAIN}{_GUI}{screenshots}->add($screenshot_file, $$self{_CFG}{'environments'}{$$self{_UUID}});
                $PACMain::FUNCS{_MAIN}->_updateGUIPreferences();

                return 0;

            });
        }
    }

    # On TABS, choose correct colour depending on connection status
    if ($$self{_TABBED}) {
        my $check_gui = $PACMain::RUNNING{$$self{_UUID_TMP}}{terminal}{_SPLIT} ? $PACMain::RUNNING{$$self{_UUID_TMP}}{terminal}{_SPLIT_VPANE} : $PACMain::RUNNING{$$self{_UUID_TMP}}{terminal}{_GUI}{_VBOX};
        if (!defined $check_gui) {
            return 1;
        }
        $$self{_FOCUSED} = $check_gui->get_child_visible;

        $$self{_NEW_DATA} &&= ! $$self{_FOCUSED};
        if ($PACMain::RUNNING{$$self{_UUID_TMP}}{terminal}{_SPLIT}) {
            $PACMain::RUNNING{$PACMain::RUNNING{$$self{_UUID_TMP}}{terminal}{_SPLIT}}{terminal}{_FOCUSED} = $check_gui->get_child_visible;
        }
        $PACMain::RUNNING{$PACMain::RUNNING{$$self{_UUID_TMP}}{terminal}{_SPLIT}}{terminal}{_NEW_DATA} &&= ! $PACMain::RUNNING{$PACMain::RUNNING{$$self{_UUID_TMP}}{terminal}{_SPLIT}}{terminal}{_FOCUSED} if $PACMain::RUNNING{$$self{_UUID_TMP}}{terminal}{_SPLIT};

        my $conn_color = $$self{_NEW_DATA} ? $$self{_CFG}{defaults}{'new data color'} : $$self{_CFG}{defaults}{'connected color'};
        my $disconn_color = $$self{_CFG}{defaults}{'disconnected color'};
        my $rem_conn_color = $PACMain::RUNNING{$$self{_SPLIT}}{terminal}{_NEW_DATA} ? $$self{_CFG}{defaults}{'new data color'} : $$self{_CFG}{defaults}{'connected color'} if $$self{_SPLIT};

        if ($$self{_SPLIT}) {
            my $back1 = $$self{_CFG}{'environments'}{$$self{_UUID}}{'terminal options'}{'use personal settings'} && $$self{_CFG}{'environments'}{$$self{_UUID}}{'terminal options'}{'use tab back color'} ? "background=\"$$self{_CFG}{'environments'}{$$self{_UUID}}{'terminal options'}{'tab back color'}\"" : '';
            my $fore1 = 'foreground="' . ($$self{CONNECTED} ? $conn_color : $disconn_color) . '"';
            my $back2 = $$self{_CFG}{'environments'}{$PACMain::RUNNING{$$self{_SPLIT}}{terminal}{_UUID}}{'terminal options'}{'use personal settings'} && $$self{_CFG}{'environments'}{$PACMain::RUNNING{$$self{_SPLIT}}{terminal}{_UUID}}{'terminal options'}{'use tab back color'} ? "background=\"$$self{_CFG}{'environments'}{$PACMain::RUNNING{$$self{_SPLIT}}{terminal}{_UUID}}{'terminal options'}{'tab back color'}\"" : '';
            my $fore2 = 'foreground="' . ($PACMain::RUNNING{$$self{_SPLIT}}{terminal}{CONNECTED} ? $rem_conn_color : $disconn_color) . '"';
            $$self{_GUI}{_TABLBL}{_LABEL}->set_markup("<span $back1 $fore1>@{[__($$self{_TITLE})]}</span> + <span $back2 $fore2>__($PACMain::RUNNING{$$self{_SPLIT}}{terminal}{_TITLE})</span>");
            if ($i) {
                $PACMain::RUNNING{$$self{_SPLIT}}{terminal}->_setTabColour(--$i);
            }
        } else {
            my $back = $$self{_CFG}{'environments'}{$$self{_UUID}}{'terminal options'}{'use personal settings'} && $$self{_CFG}{'environments'}{$$self{_UUID}}{'terminal options'}{'use tab back color'} ? "background=\"$$self{_CFG}{'environments'}{$$self{_UUID}}{'terminal options'}{'tab back color'}\"" : '';
            my $fore = 'foreground="' . ($$self{CONNECTED} ? $conn_color : $disconn_color) . '"';
            $$self{_GUI}{_TABLBL}{_LABEL}->set_markup("<span $back $fore>@{[__($$self{_TITLE})]}</span>");
        }
    } else {
        defined $$self{_WINDOWTERMINAL} and $$self{_WINDOWTERMINAL}->set_icon_from_file($$self{CONNECTED} ? "$RealBin/res/asbru_terminal64x64.png" : "$RealBin/res/asbru_terminal_x64x64.png");
    }

    # Once checked the availability of new data, reset its value
    $$self{_NEW_DATA} = 0;

    return 1;
}

sub _updateStatus {
    my $self = shift;

    if (!defined $$self{_GUI}{status}) {
        return 1;
    }
    if ($$self{_STATUS_COUNT}++ >= 15) {
        splice(@{$$self{_HISTORY}}, 0, 2, ('(... older status skipped...)'));
    }
    push(@{$$self{_HISTORY}}, $$self{_LAST_STATUS});

    # Control CLUSTER status
    if ($$self{_CLUSTER} ne '') {
        $$self{_GUI}{status}->push(0, "[IN CLUSTER: $$self{_CLUSTER}] - Status: $$self{_LAST_STATUS}");
    } else {
        $$self{_GUI}{status}->push(0, "Status: $$self{_LAST_STATUS}");
    }

    if (defined $$self{_GUI}{status}) {
        $$self{_GUI}{status}->set_property('tooltip-text', join("\n", @{$$self{_HISTORY}}));
    }
    if (defined $$self{_GUI}{pb}) {
        $$self{_GUI}{pb}->set_property('tooltip-text', join("\n", @{$$self{_HISTORY}}));
    }

    return 1;
}

sub _openSFTP {
    my $self = shift;

    if ($$self{_CFG}{environments}{$$self{_UUID}}{method} ne 'SSH') {
        return 0;
    }

    my @idx;
    my $newuuid = '_tmp_' . rand;
    push(@idx, [$newuuid]);
    $$self{_CFG}{environments}{$newuuid} = dclone($$self{_CFG}{environments}{$$self{_UUID}});
    $$self{_CFG}{environments}{$newuuid}{method} = 'SFTP';
    $$self{_CFG}{environments}{$newuuid}{expect} = [];
    $$self{_CFG}{environments}{$newuuid}{options} = '';
    $$self{_CFG}{environments}{$newuuid}{autossh} = 0;
    $$self{_CFG}{environments}{$newuuid}{_protected} = 1;
    $PACMain::{FUNCS}{_MAIN}->_launchTerminals(\@idx);
}

sub _clusterCommit {
    my ($self, $terminal, $string, $int) = @_;

    if (!($$self{_LISTEN_COMMIT} && ($$self{_CLUSTER} ne '') && $$self{CONNECTED} && $$self{_PROPAGATE})) {
        return 1;
    }
    $$self{_LISTEN_COMMIT} = 0;
    foreach my $uuid_tmp (keys %PACMain::RUNNING) {
        if ((!$PACMain::RUNNING{$uuid_tmp}{terminal}{CONNECTED}) || ($PACMain::RUNNING{$uuid_tmp}{terminal}{_CLUSTER} ne $$self{_CLUSTER}) || ($PACMain::RUNNING{$uuid_tmp}{terminal}{_UUID_TMP} eq $$self{_UUID_TMP})) {
            next;
        }
        $PACMain::RUNNING{$uuid_tmp}{terminal}{_LISTEN_COMMIT} = 0;
        _vteFeedChild($PACMain::RUNNING{$uuid_tmp}{terminal}{_GUI}{_VTE}, $string);
        $PACMain::RUNNING{$uuid_tmp}{terminal}{_LISTEN_COMMIT} = 1;
    }
    $$self{_LISTEN_COMMIT} = 1;

    return 1;
}

sub _tabToWin {
    my $self = shift;
    my $explode = shift;

    my $tabs = $self->{_NOTEBOOK};

    my $i = $$self{_SPLIT} ? $$self{_GUI}{_SPLIT_VPANE} : $$self{_NOTEBOOK}->page_num($$self{_GUI}{_VBOX});

    $self->{_WINDOWTERMINAL} = Gtk3::Window->new();
    if ($$self{_SPLIT_VPANE}) {
        $$self{_SPLIT_VPANE}->reparent($self->{_WINDOWTERMINAL});
        $PACMain::RUNNING{$$self{_SPLIT}}{terminal}{_TABBED} = 0;
    } else {
        if ($$self{EMBED}) {
            my $vbox = Gtk3::VBox-> new(0, 0);
            $$self{_WINDOWTERMINAL}->add($vbox);

            my $sc2 = Gtk3::ScrolledWindow->new();
            $sc2->set_shadow_type('none');
            $sc2->set_policy('automatic', 'automatic');
            $vbox->pack_start($sc2, 1, 1, 0);

            my $vp = Gtk3::Viewport->new();
            $sc2->add($vp);

            my $btnfocus = Gtk3::Button->new_with_mnemonic('Set _keyboard focus');
            $btnfocus->set_image(Gtk3::Image->new_from_icon_name('input-keyboard', 'GTK_ICON_SIZE_SMALL_TOOLBAR'));
            $btnfocus->set('can_focus', 0);
            $btnfocus->signal_connect ('clicked' => sub {$$self{FOCUS}->child_focus('GTK_DIR_TAB_FORWARD');});
            $vbox->pack_start($btnfocus, 0, 1, 0);

            $$self{_WINDOWTERMINAL}->set_default_size($$self{_GUI}{_VBOX}->get_allocated_width(), $$self{_GUI}{_VBOX}->get_allocated_height() - $$self{_GUI}{status}->get_allocated_height());
            $$self{_WINDOWTERMINAL}->show_all();
            $$self{_GUI}{_SOCKET}->reparent($vp);
            $$self{_GUI}{_VBOX}->destroy();
        } else {
            $$self{_GUI}{_VBOX}->reparent($self->{_WINDOWTERMINAL});
        }
    }

    $$self{_TABBED} = 0;

    $$self{_WINDOWTERMINAL}->set_title("$APPNAME (v$APPVERSION) : $$self{_TITLE}");
    $$self{_WINDOWTERMINAL}->set_icon_name($$self{CONNECTED} ? 'gtk-connect' : 'gtk-disconnect');
    $$self{_WINDOWTERMINAL}->set_size_request(200, 100);

    my $hsize = $$self{_CFG}{environments}{$$self{_UUID}}{'terminal options'}{'use personal settings'} ? $$self{_CFG}{environments}{$$self{_UUID}}{'terminal options'}{'terminal window hsize'} : $$self{_CFG}{'defaults'}{'terminal windows hsize'};
    my $vsize = $$self{_CFG}{environments}{$$self{_UUID}}{'terminal options'}{'use personal settings'} ? $$self{_CFG}{environments}{$$self{_UUID}}{'terminal options'}{'terminal window vsize'} : $$self{_CFG}{'defaults'}{'terminal windows vsize'};
    $$self{_WINDOWTERMINAL}->set_default_size(defined $explode ? ($$explode{'width'}, $$explode{'height'}) : ($hsize, $vsize));

    $$self{_WINDOWTERMINAL}->show();
    $$self{_WINDOWTERMINAL}->present();
    $self->{_PARENTWINDOW} = $$self{_WINDOWTERMINAL};

    # Capture window close
    $$self{_WINDOWTERMINAL}->signal_connect('delete_event' => sub {
        if (!$$self{_GUILOCKED}) {
            $self->stop(undef, 1);
        }
        return Gtk3::EVENT_STOP; # stop propagation
    });

    $self->_updateCFG();

    $$self{_SPLIT} and $PACMain::RUNNING{$$self{_SPLIT}}{terminal}{_WINDOWTERMINAL} = $$self{_WINDOWTERMINAL};
    $$self{_POST_SPLIT} and $self->{_NOTEBOOK}->remove_page($i);

    return 1;
}

sub _winToTab {
    my $self = shift;

    my $tabs = $$self{_NOTEBOOK};

    # Append this GUI to a new TAB (with an associated label && event_box->image(close) button)
    $$self{_GUI}{_TABLBL} = Gtk3::HBox->new(0, 0);

    $$self{_GUI}{_TABLBL}{_EBLBL} = Gtk3::EventBox->new();
    $$self{_GUI}{_TABLBL}->pack_start($$self{_GUI}{_TABLBL}{_EBLBL}, 1, 1, 0);
    $$self{_GUI}{_TABLBL}{_LABEL} = Gtk3::Label->new($$self{_TITLE});
    $$self{_GUI}{_TABLBL}{_EBLBL}->add($$self{_GUI}{_TABLBL}{_LABEL});

    my $eblbl1 = Gtk3::EventBox->new();
    $eblbl1->add(Gtk3::Image->new_from_stock('gtk-close', 'menu'));
    $eblbl1->signal_connect('button_release_event' => sub {
        if ($_[1]->button != 1) {
            return 0;
        }
        $self->stop(undef, 1);
    });
    $$self{_GUI}{_TABLBL}->pack_start($eblbl1, 0, 1, 0);

    $$self{_GUI}{_TABLBL}{_EBLBL}->signal_connect('button_press_event' => sub {
        my ($widget, $event) = @_;

        if ($event->button eq 2) {
            $self->stop(undef, 1);
            return 1;
        }
        if ($event->button ne 3) {
            return 0;
        }

        $self->_tabMenu($event);
    });

    $$self{_GUI}{_TABLBL}->show_all();
    $self->{_PARENTWINDOW} = $$self{_NOTEBOOKWINDOW};

    $self->_setupTabDND();

    $tabs->show();

    if ($$self{_SPLIT_VPANE}) {
        $$self{_SPLIT_VPANE}->reparent($tabs);
        $tabs->set_tab_label($$self{_SPLIT_VPANE}, $$self{_GUI}{_TABLBL});
        $tabs->set_tab_reorderable($$self{_SPLIT_VPANE}, 1);
        $PACMain::RUNNING{$$self{_SPLIT}}{terminal}{_TABBED} = 1;
        $PACMain::RUNNING{$$self{_SPLIT}}{terminal}{_WINDOWTERMINAL}->destroy();
        undef($PACMain::RUNNING{$$self{_SPLIT}}{terminal}{_WINDOWTERMINAL});
        if (!$PACMain::RUNNING{$$self{_SPLIT}}{'is_shell'}) {
            $PACMain::RUNNING{$$self{_SPLIT}}{terminal}->_updateCFG();
        }
    } else {
        $$self{_GUI}{_VBOX}->reparent($tabs);
        $tabs->set_tab_label($$self{_GUI}{_VBOX}, $$self{_GUI}{_TABLBL});
        $tabs->set_tab_reorderable($$self{_GUI}{_VBOX}, 1);
        $$self{_WINDOWTERMINAL}->destroy();
        undef($$self{_WINDOWTERMINAL});
    }

    $$self{_TABBED} = 1;
    $self->_updateCFG();

    $tabs->set_current_page(-1);
    if ($$self{EMBED}) {
        $$self{FOCUS}->child_focus('GTK_DIR_TAB_FORWARD');
    } else {
        $$self{FOCUS}->grab_focus();
    }

    return 1;
}

sub _tabMenu {
    my $self = shift;
    my $event = shift;

    my @vte_menu_items;

    # Show a popup with the opened tabs (if tabbed!!)
    my @submenu_goto;
    foreach my $uuid (keys %PACMain::RUNNING) {
        if (!defined $PACMain::RUNNING{$uuid}{terminal}{_SPLIT}) {
            next;
        }
        my $i = $$self{_NOTEBOOK}->page_num($PACMain::RUNNING{$uuid}{terminal}{_SPLIT} ? $PACMain::RUNNING{$uuid}{terminal}{_SPLIT_VPANE} : $PACMain::RUNNING{$uuid}{terminal}{_GUI}{_VBOX});
        if ($uuid eq $$self{_UUID} || $i < 0) {
            next;
        }
        push(@submenu_goto,
        {
            label => "$i: $PACMain::RUNNING{$uuid}{terminal}{_TITLE}",
            code => sub {$$self{_NOTEBOOK}->set_current_page($i);}
        });
    }
    @submenu_goto = sort {$$a{label} cmp $$b{label}} @submenu_goto;
    push(@vte_menu_items,
    {
        label => 'Goto TAB',
        stockicon => 'gtk-jump-to',
        submenu => \@submenu_goto,
        sensitive => scalar(@submenu_goto)
    });

    # If PAC Script running, show a STOP script menuitem
    if ($$self{_SCRIPT_STATUS} ne 'STOP') {
        push(@vte_menu_items,
        {
            label => "Stop script '$$self{_SCRIPT_NAME}'",
            stockicon => 'gtk-media-stop',
            sensitive => 1,
            code => sub {
                $self->_disconnectTerminal();
            }
        });

        _wPopUpMenu(\@vte_menu_items, $event);
        return 1,
    }

    # Show a popup with the opened tabs (if tabbed!!)
    if (!$$self{EMBED}) {
        if ($$self{_TABBED}) {
            my @submenu_split_v;
            my @submenu_split_h;
            foreach my $uuid_tmp (keys %PACMain::RUNNING) {
                if (!defined $PACMain::RUNNING{$uuid_tmp}{terminal}{_SPLIT}) {
                    next;
                }
                my $i = $$self{_NOTEBOOK}->page_num($PACMain::RUNNING{$uuid_tmp}{terminal}{_SPLIT} ? $PACMain::RUNNING{$uuid_tmp}{terminal}{_SPLIT_VPANE} : $PACMain::RUNNING{$uuid_tmp}{terminal}{_GUI}{_VBOX});
                if ($uuid_tmp eq $$self{_UUID_TMP} || $PACMain::RUNNING{$uuid_tmp}{terminal}{_TITLE} eq 'Info ' || $i < 0) {
                    next;
                }
                if (($$self{_SPLIT} || $PACMain::RUNNING{$uuid_tmp}{terminal}{_SPLIT}) || (! $PACMain::RUNNING{$uuid_tmp}{terminal}{_TABBED})) {
                    next;
                }
                push(@submenu_split_v,
                {
                    label => "$i: $PACMain::RUNNING{$uuid_tmp}{terminal}{_TITLE}",
                    code => sub {$self->_split($uuid_tmp);}
                });
                push(@submenu_split_h,
                {
                    label => "$i: $PACMain::RUNNING{$uuid_tmp}{terminal}{_TITLE}",
                    code => sub {$self->_split($uuid_tmp, 1);}
                });
            }
            @submenu_split_v = sort {$$a{label} cmp $$b{label}} @submenu_split_v;
            @submenu_split_h = sort {$$a{label} cmp $$b{label}} @submenu_split_h;

            push(@vte_menu_items, {label => 'Detach TAB to a new Window', stockicon => 'gtk-fullscreen', code => sub {_tabToWin($self); return 1;}});

            if ($$self{_SPLIT}) {
                push(@vte_menu_items,
                {
                    label => 'Unsplit',
                    stockicon => 'gtk-zoom-fit',
                    code => sub {$self->_unsplit();}
                });
                push(@vte_menu_items,
                {
                    label => 'Equally resize terminals',
                    stockicon => 'gtk-zoom-fit',
                    code => sub {$self->_equalresize();}
                });
            } else {
                push(@vte_menu_items,
                {
                    label => 'Split',
                    stockicon => 'gtk-zoom-fit',
                    sensitive => scalar(@submenu_split_v) && scalar(@submenu_split_h),
                    submenu =>
                    [
                        {
                            label => 'Vertically ',
                            stockicon => 'gtk-zoom-fit',
                            submenu => \@submenu_split_v,
                            sensitive => scalar(@submenu_split_v)
                        },
                        {
                            label => 'Horizontally',
                            stockicon => 'gtk-zoom-fit',
                            submenu => \@submenu_split_h,
                            sensitive => scalar(@submenu_split_h)
                        }
                    ]
                });
            }
            push(@vte_menu_items, {separator => 1});
        } else {
            push(@vte_menu_items, {label => 'Attach Window to main TAB bar', stockicon => 'gtk-leave-fullscreen', code => sub {_winToTab($self); return 1;}});
            push(@vte_menu_items, {separator => 1});
        }
    }

    # Prepare the "Add to Cluster" submenu...
    my @submenu_cluster;
    my %clusters;
    push(@submenu_cluster,
    {
        label => 'New Cluster...',
        stockicon => 'gtk-new',
        code => sub {
            my $cluster = _wEnterValue($$self{_PARENTWINDOW}, 'Enter a name for the <b>New Cluster</b>');
            if ((! defined $cluster) || ($cluster =~ /^\s*$/go)) {
                return 1;
            }
            $PACMain::FUNCS{_CLUSTER}->addToCluster($$self{_UUID_TMP}, $cluster);
        }
    });
    foreach my $uuid_tmp (keys %PACMain::RUNNING) {
        if (!defined $PACMain::RUNNING{$uuid_tmp}{terminal}{_CLUSTER} || $PACMain::RUNNING{$uuid_tmp}{terminal}{_CLUSTER} eq '') {
            next;
        }
        $clusters{$PACMain::RUNNING{$uuid_tmp}{terminal}{_CLUSTER}}{total}++;
        $clusters{$PACMain::RUNNING{$uuid_tmp}{terminal}{_CLUSTER}}{connections} .= "$PACMain::RUNNING{$uuid_tmp}{terminal}{_NAME}\n";
    }
    foreach my $cluster (sort {$a cmp $b} keys %clusters) {
        my $tmp = $cluster;
        push(@submenu_cluster,
        {
            label => "$cluster ($clusters{$cluster}{total} terminals connected)",
            tooltip => $clusters{$cluster}{connections},
            sensitive => $cluster ne $$self{_CLUSTER},
            code => sub {$PACMain::FUNCS{_CLUSTER}->addToCluster($$self{_UUID_TMP}, $tmp);}
        });
    }
    push(@vte_menu_items,
    {
        label => ($$self{_CLUSTER} eq '' ? 'Add' : 'Change') . ' to Cluster',
        stockicon => 'gtk-add',
        sensitive => 1,
        submenu => \@submenu_cluster
    });
    push(@vte_menu_items,
    {
        label => 'Remove from Cluster',
        stockicon => 'gtk-delete',
        sensitive => $$self{_CLUSTER} ne '',
        code => sub {$PACMain::FUNCS{_CLUSTER}->delFromCluster($$self{_UUID_TMP}, $$self{_CLUSTER});}
    });
    push(@vte_menu_items,
    {
        label => 'Cluster Admin...',
        stockicon => 'gtk-justify-fill',
        sensitive => 1,
        code => sub {$PACMain::FUNCS{_CLUSTER}->show();}
    });
    push(@vte_menu_items, {separator => 1});

    push(@vte_menu_items, {label => 'Find...', stockicon => 'gtk-find', code => sub {$self->_wFindInTerminal; return 1;}});

    # Add save session log
    push(@vte_menu_items, {label => 'Save session log...', stockicon => 'gtk-save', code => sub{$self->_saveSessionLog;}});

    # Add edit session
    push(@vte_menu_items, {label => 'Edit session...', stockicon => 'gtk-edit', sensitive => $$self{_UUID} ne '__PAC_SHELL__', code => sub{$PACMain::FUNCS{_EDIT}->show($$self{_UUID});}});

    # Add change temporary tab label
    push(@vte_menu_items, {label => 'Temporary TAB Label change...', stockicon => 'gtk-edit', code => sub {
        # Prepare the input window
        my $new_label = _wEnterValue(
            $$self{_PARENTWINDOW},
            "<b>Temporaly renaming label '@{[__($$self{_TITLE})]}'</b>",
            'Enter the new temporal label:',
            $$self{_TITLE}
        );

        if ((defined $new_label) && ($new_label !~ /^\s*$/go)) {
            $$self{_TITLE} = $new_label;
        }
        $self->_setTabColour();
    }});

    # Add a submenu with available connections
    push(@vte_menu_items, {separator => 1});
    push(@vte_menu_items, {label => 'New connection', stockicon => 'gtk-connect', submenu => &_menuAvailableConnections($PACMain::FUNCS{_MAIN}{_GUI}{treeConnections}{data})});

    # Add a 'duplicate connection' button
    push(@vte_menu_items, {label => 'Duplicate connection', stockicon => 'gtk-copy', sensitive => 1, code => sub{$PACMain::FUNCS{_MAIN}->_launchTerminals([[$$self{_UUID}]]);}});

    # Add close terminal
    push(@vte_menu_items, {separator => 1});
    # Add a 'disconnect' button to disconnect without closing the terminal
    push(@vte_menu_items, {label => 'Disconnect session', stockicon => 'gtk-stop', sensitive => $$self{_PID}, code => sub {$self->_disconnectTerminal();}});
    push(@vte_menu_items, {label => 'Restart session', stockicon => 'gtk-execute', sensitive => !$$self{CONNECTED} || !$$self{_PID}, code => sub {$self->start();}});
    push(@vte_menu_items, {label => 'Close terminal', stockicon => 'gtk-close', code => sub {$self->stop(undef, 1);}});
    push(@vte_menu_items, {label => 'Close all terminals', stockicon => 'gtk-close', code => sub {
        return $self->_closeAllTerminals();
    }});

    _wPopUpMenu(\@vte_menu_items, $event);

    return 1;
}

sub _split {
    my $self = shift;
    my $uuid_tmp = shift;
    my $vertical = shift // '0';

    my $tabs = $self->{_NOTEBOOK};
    $$self{_SPLIT_VERTICAL} = $vertical;

    my $new_vpane = $vertical ? Gtk3::VPaned->new() : Gtk3::HPaned->new();

    $$self{_SPLIT_VPANE} = $new_vpane; # Assign new parent pane to both terminals
    $PACMain::RUNNING{$uuid_tmp}{terminal}{_SPLIT_VPANE} = $new_vpane; # Assign new parent pane to both terminals

    $$self{_GUI}{_VBOX}->reparent($new_vpane); # Move ME into new created PANE
    $PACMain::RUNNING{$uuid_tmp}{terminal}{_GUI}{_VBOX}->reparent($new_vpane); # Move THE OTHER TERMINAL into new created PANE

    # Append this GUI to a new TAB (with an associated label && event_box->image(close) button)
    $$self{_GUI}{_TABLBL} = Gtk3::HBox->new(0, 0);

    $$self{_GUI}{_TABLBL}{_EBLBL} = Gtk3::EventBox->new();
    $$self{_GUI}{_TABLBL}->pack_start($$self{_GUI}{_TABLBL}{_EBLBL}, 1, 1, 0);
    $$self{_GUI}{_TABLBL}{_LABEL} = Gtk3::Label->new("$$self{_TITLE} + $PACMain::RUNNING{$uuid_tmp}{terminal}{_TITLE}");
    $$self{_GUI}{_TABLBL}{_EBLBL}->add($$self{_GUI}{_TABLBL}{_LABEL});

    my $eblbl1 = Gtk3::EventBox->new();
    $eblbl1->add(Gtk3::Image->new_from_stock('gtk-close', 'menu'));
    $eblbl1->signal_connect('button_release_event' => sub {$_[1]->button != 1 and return 0; $self->stop(undef, 1);});
    $$self{_GUI}{_TABLBL}->pack_start($eblbl1, 0, 1, 0);

    $$self{_GUI}{_TABLBL}{_EBLBL}->signal_connect('button_press_event' => sub {
        my ($widget, $event) = @_;
        if ($event->button eq 2) {$self->stop(undef, 1); return 1;}
        elsif ($event->button ne 3) {return 0;}
        $self->_tabMenu($event);
        return 1;
    });

    $$self{_GUI}{_TABLBL}->show_all();

    $tabs->append_page($new_vpane, $$self{_GUI}{_TABLBL});

    $tabs->show_all();
    $tabs->set_tab_reorderable($new_vpane, 1);
    $tabs->set_current_page(-1);

    $self->_setupTabDND($$self{_NOTEBOOK});

    $$self{_SPLIT} = $uuid_tmp;
    $$self{_POST_SPLIT} = 0;
    $PACMain::RUNNING{$uuid_tmp}{terminal}{_SPLIT} = $$self{_UUID_TMP};
    $PACMain::RUNNING{$uuid_tmp}{terminal}{_POST_SPLIT} = 0;

    $self->_updateCFG();
    $self->_setTabColour();
    $PACMain::RUNNING{$uuid_tmp}{terminal}->_updateCFG();

    # Force redraw to have the correct split pane size
    Gtk3::main_iteration() while Gtk3::events_pending();

    # Equal size by default
    $self->_equalresize();

    # To always force keeping equal size
    if ($$self{_CFG}{'defaults'}{'force split tabs to 50%'}) {
        $$self{_SPLIT_VPANE}->signal_connect('size-allocate', sub {
            $self->_equalresize();
        });
    }

    return 1;
}

sub _equalresize {
    my $self = shift;

    my ($w, $h) = ($$self{_SPLIT_VPANE}->get_allocated_width(), $$self{_SPLIT_VPANE}->get_allocated_height());
    my $s = (($$self{_SPLIT_VERTICAL} ? $h : $w) / 2) - 7;

    # Set split position
    $$self{_SPLIT_VPANE}->set_position($s);

    # Force redraw
    Gtk3::main_iteration() while Gtk3::events_pending();

    return 1;
}

sub _unsplit {
    my $self = shift;

    my $uuid_tmp = $$self{_SPLIT};
    my $tabs = $$self{_NOTEBOOK};
    my $page = $$self{_NOTEBOOK}->page_num($$self{_SPLIT_VPANE});

    my $new_vbox_1 = Gtk3::VBox->new(0, 0);
    my $new_vbox_2 = Gtk3::VBox->new(0, 0);

    $$self{_GUI}{_VBOX}->reparent($new_vbox_1);
    $$self{_GUI}{_VBOX} = $new_vbox_1;
    $$self{_TABBED} = 1;
    $PACMain::RUNNING{$uuid_tmp}{terminal}{_GUI}{_VBOX}->reparent($new_vbox_2);
    $PACMain::RUNNING{$uuid_tmp}{terminal}{_GUI}{_VBOX} = $new_vbox_2;
    $PACMain::RUNNING{$uuid_tmp}{terminal}{_TABBED} = 1;

    # Append this GUI to a new TAB (with an associated label && event_box->image(close) button)
    $$self{_GUI}{_TABLBL} = Gtk3::HBox->new(0, 0);

    $$self{_GUI}{_TABLBL}{_EBLBL} = Gtk3::EventBox->new();
    $$self{_GUI}{_TABLBL}->pack_start($$self{_GUI}{_TABLBL}{_EBLBL}, 1, 1, 0);
    $$self{_GUI}{_TABLBL}{_LABEL} = Gtk3::Label->new($$self{_TITLE});
    $$self{_GUI}{_TABLBL}{_EBLBL}->add($$self{_GUI}{_TABLBL}{_LABEL});

    my $eblbl1 = Gtk3::EventBox->new();
    $eblbl1->add(Gtk3::Image->new_from_stock('gtk-close', 'menu'));
    $eblbl1->signal_connect('button_release_event' => sub {$_[1]->button != 1 and return 0; $self->stop(undef, 1);});
    $$self{_GUI}{_TABLBL}->pack_start($eblbl1, 0, 1, 0);

    $$self{_GUI}{_TABLBL}{_EBLBL}->signal_connect('button_press_event' => sub {
        my ($widget, $event) = @_;

        if ($event->button eq 2) {
            $self->stop(undef, 1);
            return 1;
        } elsif ($event->button ne 3) {
            return 0;
        }

        $self->_tabMenu($event);
        return 1;
    });

    $$self{_GUI}{_TABLBL}->show_all();
    $tabs->append_page($new_vbox_1, $$self{_GUI}{_TABLBL});

    $tabs->show_all();
    $tabs->set_tab_reorderable($new_vbox_1, 1);

    $self->_setupTabDND();

    # Append this GUI to a new TAB (with an associated label && event_box->image(close) button)
    $PACMain::RUNNING{$uuid_tmp}{terminal}{_GUI}{_TABLBL} = Gtk3::HBox->new(0, 0);

    $PACMain::RUNNING{$uuid_tmp}{terminal}{_GUI}{_TABLBL}{_EBLBL} = Gtk3::EventBox->new();
    $PACMain::RUNNING{$uuid_tmp}{terminal}{_GUI}{_TABLBL}->pack_start($PACMain::RUNNING{$uuid_tmp}{terminal}{_GUI}{_TABLBL}{_EBLBL}, 1, 1, 0);
    $PACMain::RUNNING{$uuid_tmp}{terminal}{_GUI}{_TABLBL}{_LABEL} = Gtk3::Label->new($PACMain::RUNNING{$uuid_tmp}{terminal}{_TITLE});
    $PACMain::RUNNING{$uuid_tmp}{terminal}{_GUI}{_TABLBL}{_EBLBL}->add($PACMain::RUNNING{$uuid_tmp}{terminal}{_GUI}{_TABLBL}{_LABEL});

    my $eblbl3 = Gtk3::EventBox->new();
    $eblbl3->add(Gtk3::Image->new_from_stock('gtk-close', 'menu'));
    $eblbl3->signal_connect('button_release_event' => sub {$_[1]->button != 1 and return 0; $self->stop(undef, 1);});
    $PACMain::RUNNING{$uuid_tmp}{terminal}{_GUI}{_TABLBL}->pack_start($eblbl3, 0, 1, 0);

    $PACMain::RUNNING{$uuid_tmp}{terminal}{_GUI}{_TABLBL}{_EBLBL}->signal_connect('button_press_event' => sub {
        my ($widget, $event) = @_;

        if ($event->button eq 2) {
            $self->stop(undef, 1);
            return 1;
        } elsif ($event->button ne 3) {
            return 0;
        }

        $self->_tabMenu($event);
        return 1;
    });

    $PACMain::RUNNING{$uuid_tmp}{terminal}{_GUI}{_TABLBL}->show_all();
    $tabs->append_page($new_vbox_2, $PACMain::RUNNING{$uuid_tmp}{terminal}{_GUI}{_TABLBL});

    $tabs->show_all();
    $tabs->set_tab_reorderable($new_vbox_2, 1);

    $PACMain::RUNNING{$uuid_tmp}{terminal}->_setupTabDND();

    $$self{_SPLIT} = 0;
    $PACMain::RUNNING{$uuid_tmp}{terminal}{_SPLIT} = 0;
    $$self{_POST_SPLIT} = $new_vbox_1;
    $PACMain::RUNNING{$uuid_tmp}{terminal}{_POST_SPLIT} = $new_vbox_1;

    $$self{_SPLIT_VPANE} = 0;
    $PACMain::RUNNING{$uuid_tmp}{terminal}{_SPLIT_VPANE} = 0;

    $$self{_NOTEBOOK}->remove_page($page);

    $tabs->set_current_page(-1);

    $self->_updateCFG();
    $PACMain::RUNNING{$uuid_tmp}{terminal}->_updateCFG();

    return 1;
}

sub _setupTabDND {
    my $self = shift;
    my $widget = shift // $$self{_GUI}{_VBOX};

    my @targets = (Gtk3::TargetEntry->new('Ásbrú Tabbed', [], 0));
    $$self{_GUI}{_TABLBL}->drag_source_set('GDK_BUTTON1_MASK', \@targets, ['move']);
    $$self{_GUI}{_TABLBL}->signal_connect('drag_begin' => sub {
        # Does not work anymore on Gtk3
        #$_[1]->set_icon_pixbuf(_scale(_screenshot($widget), 128, 128, 1), 0, 0);
        my $i = $$self{_NOTEBOOK}->page_num($$self{_GUI}{_VBOX});
        $PACMain::FUNCS{_MAIN}{DND}{source_tab} = $$self{_NOTEBOOK}->get_nth_page($i);
    });
    $$self{_GUI}{_TABLBL}->signal_connect('drag_end' => sub {$PACMain::FUNCS{_MAIN}{DND} = undef; return 1;});
    $$self{_GUI}{_TABLBL}->signal_connect('drag_failed' => sub {
        if ($_[2] eq 'user-cancelled') {
            return 0;
        }
        $self->_tabToWin();
    });

    $$self{_GUI}{_TABLBL}->drag_dest_set('GTK_DEST_DEFAULT_ALL', \@targets, ['move']);
    $$self{_GUI}{_TABLBL}->signal_connect('drag_drop' => sub {
        my $i = $$self{_NOTEBOOK}->page_num($$self{_GUI}{_VBOX});
        $$self{_NOTEBOOK}->reorder_child($PACMain::FUNCS{_MAIN}{DND}{source_tab}, $i);
        $$self{_NOTEBOOK}->set_current_page($i);
    });

    return 1;
}

sub _saveSessionLog {
    my $self = shift;

    my $new_file = $$self{_LOGFILE};
    $new_file =~ s/.*\///go;

    my $dialog = Gtk3::FileChooserDialog->new (
        'Select file to save session log',
        undef,
        'select-folder',
        'gtk-cancel' => 'GTK_RESPONSE_CANCEL',
        'gtk-ok' => 'GTK_RESPONSE_OK'
    );
    $dialog->set_action('GTK_FILE_CHOOSER_ACTION_SAVE');
    $dialog->set_do_overwrite_confirmation(1);
    $dialog->set_current_folder($ENV{'HOME'});
    $dialog->set_current_name($new_file);

    if ($dialog->run ne 'ok') {
        $dialog->destroy();
        return 1;
    }
    $new_file = $dialog->get_filename;
    $dialog->destroy();

    my $confirm = _wYesNoCancel($$self{_PARENTWINDOW}, 'Do you want to remove escape sequences from the saved log?');

    if ($confirm eq 'yes') {
        if (!open(F, "$$self{_LOGFILE}")) {
            _wMessage($$self{_PARENTWINDOW}, "ERROR: Could not open file '$$self{_LOGFILE}' for reading!! ($!)");
            return 1;
        }
        my @lines = <F>;
        close F;

        if (!open(F, ">$new_file")) {
            _wMessage($$self{_PARENTWINDOW}, "ERROR: Could not open file '$new_file' for writting!! ($!)");
            return 1;
        }
        print F _removeEscapeSeqs(join('', @lines));
        close F;
    } elsif ($confirm eq 'no') {
        # Copy temporal log file to selected path
        copy($$self{_LOGFILE}, $new_file);
    }

    return 1;
}

sub _execute {
    my $self = shift;
    my $where = shift;
    my $comm = shift;
    my $confirm = shift // 0;
    my $subst = shift // 1;
    my $chain = shift // 0;
    my $intro = shift // 1;

    # Ask for confirmation
    if (($confirm) && (!_wConfirm($$self{_WINDOWTERMINAL}, "Execute <b>'$comm'</b> " . ($where ne 'remote' ? 'LOCALLY' : 'REMOTELY')))) {
        return 0;
    }

    my ($cmd, $data) = _subst($comm, $$self{_CFG}, $$self{_UUID});
    if (!defined $cmd) {
        _wMessage($$self{_PARENTWINDOW}, "Canceled '<b>$where</b>' execution of '<b>$comm</b>'");
        return 0;
    }

    # Finally, execute 'remote' or 'local'
    if ($where eq 'remote') {
        # Save last executed command
        $$self{_EXEC}{CMD} = $cmd;
        $$self{_EXEC}{PIPE} = $$data{pipe};
        $$self{_EXEC}{PROMPT} = $$data{prompt};
        $$self{_EXEC}{FULL_CMD} = $comm;

        # Prevent "Remote Executions storms" (half a second between interruptions to spawned processes)
        my $time = join('.', gettimeofday());
        if (($time - $$self{_EXEC_LAST}) <= $EXEC_STORM_TIME) {
            _wMessage($$self{_PARENTWINDOW}, "Please, wait at least <b>$EXEC_STORM_TIME</b> seconds between Remote Commands Executions", 1);
            return 0;
        }
        $$self{_EXEC_LAST} = $time;

        if (!kill('USR1', $$self{_PID})) {
            _wMessage($$self{_PARENTWINDOW}, "ERROR: Could not signal process '$$self{_PID}'\nInconsistent state!\nPlease, restart PAC!!", 1);
            return 0;
        }
        my %tmp;
        $tmp{pipe} = defined $$data{pipe} ? 1 : 0;
        $tmp{tee} = $$data{tee} // 0;
        $tmp{prompt} = $$data{prompt};
        $tmp{ctrl} = $$data{ctrl};
        $tmp{intro} = $intro // 1;
        $tmp{cmd} = $cmd;
        nstore_fd(\%tmp, $$self{_SOCKET_CLIENT}) or die "ERROR:$!";
    } elsif ($where eq 'local') {
        system($cmd . ' &');
    }

    return 1;
}

sub _pipeExecOutput {
    my $self = shift;

    my $out = $$self{_EXEC}{RECEIVED};
    my $pipe = $$self{_EXEC}{PIPE};

    if (!defined $out or !defined $pipe) {
        return 1;
    }
    foreach my $cmd (@{$pipe}) {
        open(F,">:utf8",$$self{_TMPPIPE});
        print F $out;
        close F;
        $out = `cat $$self{_TMPPIPE} | $cmd 2>&1`;
    }
    $$self{_EXEC}{OUT} = $out;
    $PACMain::FUNCS{_PIPE}->show();

    return 1;
}

sub _wPrePostExec {
    my $self = shift;
    my $when = shift;

    if (!((defined $$self{_CFG}{'environments'}{$$self{_UUID}}{$when} && scalar(@{$$self{_CFG}{'environments'}{$$self{_UUID}}{$when}})))) {
        return 1;
    }

    # Build window
    my %ppe = _ppeGUI($self);

    # Empty the connections tree
    @{$ppe{window}{gui}{treeview}{data}} = ();

    # Populate the local executions tree
    my $total = 0;
    my $total_noask = 0;
    my $total_ask = 0;
    foreach my $hash (@{$$self{_CFG}{'environments'}{$$self{_UUID}}{$when}}) {
        my $ask = $$hash{'ask'} || 0;
        my $default = $$hash{'default'} || 0;
        my $command = $$hash{'command'};
        if ($command eq '') {
            next;
        }

        $total_noask += ! $ask;
        $total_ask  += $ask;

        push(@{$ppe{window}{gui}{treeview}{data}}, [$default, $command]);
        ++$total;
    }
    if (!$total) {
        return 1;
    }

    # Change mouse cursor (to busy) in VTE window
    $$self{_GUI}{_VBOX}->get_window()->set_cursor(Gtk3::Gdk::Cursor->new('watch'));

    # Now, prepare the local executions window, show it, AND stop until something clicked
    $ppe{window}{data}->show_all();

    if (($total_noask) && ! $total_ask) {
        $ppe{window}{btnOk}->activate;
        return 1;
    }

    if ($when eq 'local before') {
        my $ok = $ppe{window}{data}->run;
    }

    return 1;

    sub _execLocalPPE {
        my $self = shift;
        my %ppe = %{shift()};

        # Get total # of commands checked to be executed (for the progress bar)
        my $t = 0;
        foreach my $line (@{$ppe{window}{gui}{treeview}{data}}) {
            my ($def, $cmd) = @{$line};
            $t += $def;
        }

        # Change mouse cursor (to busy)
        $ppe{window}{data}->get_window()->set_cursor(Gtk3::Gdk::Cursor->new('watch'));
        $ppe{window}{data}->set_sensitive(0);

        my $i = 0;
        foreach my $line (@{$ppe{window}{gui}{treeview}{data}}) {
            my ($def, $cmd) = @{$line};

            # Skip unchecked commands
            if (!$def) {
                next;
            }

            # Replace PAC variables with their corresponding values
            $cmd = _subst($cmd, $$self{_CFG}, $$self{_UUID});

            # Make some update to progress bar
            $ppe{window}{gui}{pb}->set_text('Executing: ' . $cmd);
            $ppe{window}{gui}{pb}->set_fraction(++$i / $t);
            Gtk3::main_iteration while Gtk3::events_pending;

            # Launch the local command
            system($cmd);
        }

        # Change mouse cursor (to normal)
        $ppe{window}{data}->get_window()->set_cursor(Gtk3::Gdk::Cursor->new('left-ptr'));
        $ppe{window}{data}->set_sensitive(1);

        return 1;
    }

    sub _ppeGUI {
        my $self = shift;

        my %w;

        # Create the dialog window,
        $w{window}{data} = Gtk3::Dialog->new_with_buttons(
            $self->{_NAME} . " : $APPNAME : Local execution",
            $self->{_PARENTWINDOW},
            'modal',
        );
        # and setup some dialog properties.
        $w{window}{data}->set_default_response('ok');
        $w{window}{data}->set_icon_from_file($APPICON);
        $w{window}{data}->set_size_request(400, 300);
        $w{window}{data}->set_resizable(1);
        $w{window}{btnOk} = $w{window}{data}->add_button('_Ok' , 1);
        $w{window}{btnCancel} = $w{window}{data}->add_button('_Cancel' , 0);

        # Create frame
        $w{window}{gui}{frame} = Gtk3::Frame->new();
        $w{window}{data}->get_content_area->pack_start($w{window}{gui}{frame}, 1, 1, 0);
        $w{window}{gui}{frame}->set_label('Select local command(s) to execute:');
        $w{window}{gui}{frame}->set_border_width(5);

        # Create a GtkScrolledWindow,
        my $sct = Gtk3::ScrolledWindow->new();
        $w{window}{gui}{frame}->add($sct);

        $sct->set_shadow_type('none');
        $sct->set_policy('automatic', 'automatic');

        # Create treeview
        $w{window}{gui}{treeview} = Gtk3::SimpleList->new_from_treeview (
            Gtk3::TreeView->new(),
            ' EXECUTE?' => 'bool',
            ' LOCAL COMMAND' => 'text'
        );
        $sct->add($w{window}{gui}{treeview});

        # Create progress bar
        $w{window}{gui}{pb} = Gtk3::ProgressBar->new();
        $w{window}{data}->get_content_area->pack_start($w{window}{gui}{pb}, 0, 1, 5);

        $w{window}{data}->signal_connect('response' => sub {
            my ($me, $response) = @_;
            if ($response eq '1') {
                _execLocalPPE($self, \%w);
            }
            $w{window}{data}->destroy();
            if (defined $$self{_GUI}{_VBOX}) {
                # Change mouse pointer when pre exec, on post exec, the window might be gone already
                $$self{_GUI}{_VBOX}->get_window()->set_cursor(Gtk3::Gdk::Cursor->new('left-ptr'));
            }
            undef %w;
        });

        return %w;
    }

}

sub _wSelectChain {
    my $self = shift;
    my $drop_uuid = shift;

    # Build window
    my %ppe = _chainGUI($self, $drop_uuid);

    # Empty the connections tree
    @{$ppe{window}{gui}{treeview}{data}} = ();

    # Populate the local executions tree
    my $total = 0;
    my $sfce = $$self{_CFG}{'defaults'}{'skip first chain expect'};
    foreach my $hash (@{$$self{_CFG}{'environments'}{$drop_uuid}{'expect'}}) {
        my $pattern = $$hash{'expect'}  // '';
        my $command = $$hash{'send'}  // '';
        my $hide = $$hash{'hidden'}  // 0;
        my $active = $$hash{'active'}  // 0;
        my $return = $$hash{'return'}  // 1;
        my $on_match = $$hash{'on_match'} // -1;
        my $on_fail = $$hash{'on_fail'}  // -1;
        my $time_out = $$hash{'time_out'} // -1;

        push(@{$ppe{window}{gui}{treeview}{data}},
        [
            $total,
            $active,
            $total ? $pattern : $sfce ? '<no-expect!>' : $pattern,
            $command,
            $return ? 'yes' : 'no',
            $on_match == -1 ? '' : ($on_match == -2 ? 'stop' : $on_match),
            $on_fail == -1 ? '' : ($on_fail == -2 ? 'stop' : $on_fail),
            $time_out == -1 ? '' : $time_out
        ]);
        ++$total;
    }
    if (!$total) {
        return 0;
    }

    if ($$self{_CFG}{'defaults'}{'confirm chains'}) {
        # Now, prepare the chains window, show it, AND stop until something clicked
        $ppe{window}{data}->show_all();
        $ppe{window}{data}->action_area->child_focus('GTK_DIR_TAB_FORWARD');
        $ppe{window}{data}->signal_connect('response' => sub {
            my ($me, $response) = @_;
            $response eq 'ok' and _chain($self, $drop_uuid, \%ppe);
            $ppe{window}{data}->destroy();
            undef %ppe;
        });
        my $ok = $ppe{window}{data}->run;
    } else {
        _chain($self, $drop_uuid, \%ppe);
    }

    return 1;

    sub _chain
    {
        my $self = shift;
        my $drop_uuid = shift;
        my %ppe = %{shift()};

        # Prepare configuration to be chained with current connection
        my %new_cfg;
        $new_cfg{'defaults'} = dclone($$self{_CFG}{'defaults'});
        $new_cfg{'environments'}{$drop_uuid} = dclone($$self{_CFG}{'environments'}{$drop_uuid});
        $new_cfg{'tmp'} = dclone($$self{_CFG}{'tmp'});
        $new_cfg{'tmp'}{'set title'} = $ppe{window}{gui}{cbChangeTitle}->get_active;
        $new_cfg{'tmp'}{'title'} = $ppe{window}{gui}{entrytitle}->get_chars(0, -1);
        $new_cfg{'environments'}{$drop_uuid}{'expect'} = ();

        my $total = 0;
        my $sfce = $$self{_CFG}{'defaults'}{'skip first chain expect'};
        foreach my $line (@{$ppe{window}{gui}{treeview}{data}}) {
            my ($num, $active, $pattern, $command, $return, $on_match, $on_fail, $time_out) = @{$line};

            push(@{$new_cfg{'environments'}{$drop_uuid}{'expect'}}, {
                'expect' => $total ? $pattern : $sfce ? '' : $pattern,
                'send' => $command,
                'hidden' => 0,
                'active' => $active,
                'return' => $return eq '1',
                'on_match' => $on_match eq '' ? -1 : ($on_match eq 'stop' ? -2 : $on_match),
                'on_fail' => $on_fail  eq '' ? -1 : ($on_fail eq 'stop' ? -2 : $on_fail),
                'time_out' => $time_out ne '' ? $time_out : -1,
            });
            ++$total;
        }

        if ($ppe{window}{gui}{cbExecInCluster}->get_active) {
            foreach my $cluster_uuid (keys %PACMain::RUNNING) {
                if (! kill('HUP', $PACMain::RUNNING{$cluster_uuid}{terminal}{_PID})) {
                    _wMessage($$self{_PARENTWINDOW}, "ERROR: Could not signal process '$PACMain::RUNNING{$cluster_uuid}{terminal}{_PID}'\nInconsistent state!\nPlease, restart PAC!!", 1);
                    return 0;
                }

                # Send the UUID to chain with
                $PACMain::RUNNING{$cluster_uuid}{terminal}{_SOCKET_CLIENT}->send("!!_PAC_CHAIN_[$drop_uuid]!!");
                # And send the configuration for that UUID
                nstore_fd(\%new_cfg, $PACMain::RUNNING{$cluster_uuid}{terminal}{_SOCKET_CLIENT}) or die "ERROR:$!";
            }
        } else {
            if (! kill('HUP', $$self{_PID})) {
                _wMessage($$self{_PARENTWINDOW}, "ERROR: Could not signal process '$$self{_PID}'\nInconsistent state!\nPlease, restart PAC!!", 1);
                return 0;
            }

            # Send the UUID to chain with
            $$self{_SOCKET_CLIENT}->send("!!_PAC_CHAIN_[$drop_uuid]!!");
            # And send the configuration for that UUID
            nstore_fd(\%new_cfg, $$self{_SOCKET_CLIENT}) or die "ERROR:$!";
        }

        undef %new_cfg;

        return 1;
    }

    sub _chainGUI
    {
        my $self = shift;
        my $drop_uuid = shift;

        my $select_all = 0;

        my %w;

        # Create the dialog window,
        $w{window}{data} = Gtk3::Dialog->new_with_buttons(
            $self->{_NAME} . " : $APPNAME : Chain connections",
            $PACMain::FUNCS{_MAIN}{_GUI}{main},
            'modal',
            'gtk-cancel' => 'cancel',
            'gtk-ok' => 'ok'
        );
        # and setup some dialog properties.
        $w{window}{data}->set_default_response('ok');
        $w{window}{data}->set_position('center');
        $w{window}{data}->set_icon_from_file($APPICON);
        $w{window}{data}->set_size_request(600, 300);
        $w{window}{data}->set_resizable(1);

        # Create frame
        $w{window}{gui}{frame} = Gtk3::Frame->new();
        $w{window}{data}->get_content_area->pack_start($w{window}{gui}{frame}, 1, 1, 0);
        $w{window}{gui}{frame}->set_label(" Select 'expect/command' pairs from '$$self{_CFG}{'environments'}{$drop_uuid}{'name'}' to be executed into '$$self{_CFG}{'environments'}{$$self{_UUID}}{'name'}': ");
        $w{window}{gui}{frame}->set_border_width(5);

        # Create a GtkScrolledWindow,
        my $sct = Gtk3::ScrolledWindow->new();
        $w{window}{gui}{frame}->add($sct);

        $sct->set_shadow_type('none');
        $sct->set_policy('automatic', 'automatic');

        # Create treeview
        $w{window}{gui}{treeview} = Gtk3::SimpleList->new_from_treeview (
            Gtk3::TreeView->new(),
            ' # ' => 'int',
            ' ACTIVE ' => 'bool',
            ' PATTERN ' => 'text',
            ' COMMAND ' => 'text',
            ' RETURN ' => 'bool',
            ' ON MATCH ' => 'text',
            ' ON FAIL ' => 'text',
            ' TIME OUT ' => 'text'
        );
        $sct->add($w{window}{gui}{treeview});

        $w{window}{gui}{hboxtitle} = Gtk3::HBox->new(0, 0),
        $w{window}{data}->get_content_area->pack_start($w{window}{gui}{hboxtitle}, 0, 1, 0);

        $w{window}{gui}{btnSelectAll} = Gtk3::Button->new("Select All/None");
        $w{window}{gui}{hboxtitle}->pack_start($w{window}{gui}{btnSelectAll}, 0, 1, 5);
        $w{window}{gui}{btnSelectAll}->signal_connect('clicked' => sub {
            $$_[0] = $select_all foreach (@{$w{window}{gui}{treeview}{data}});
            $select_all = ! $select_all;
        });

        $w{window}{gui}{cbChangeTitle} = Gtk3::CheckButton->new_with_label("Change TAB/Window title to: ");
        $w{window}{gui}{cbChangeTitle}->set_active(1);
        $w{window}{gui}{hboxtitle}->pack_start($w{window}{gui}{cbChangeTitle}, 0, 1, 0);

        $w{window}{gui}{entrytitle} = Gtk3::Entry->new();
        $w{window}{gui}{hboxtitle}->pack_start($w{window}{gui}{entrytitle}, 1, 1, 0);
        $w{window}{gui}{entrytitle}->set_text($$self{_CFG}{'environments'}{$drop_uuid}{'title'});

        $w{window}{gui}{cbExecInCluster} = Gtk3::CheckButton->new_with_label('Send Chain to all connections in cluster' . ($$self{_CLUSTER} ne '' ? " '$$self{_CLUSTER}'" : ''));
        $w{window}{data}->get_content_area->pack_start($w{window}{gui}{cbExecInCluster}, 0, 1, 0);
        $w{window}{gui}{cbExecInCluster}->set_active(0);
        $w{window}{gui}{cbExecInCluster}->set_sensitive($$self{_CLUSTER} ne '');

        return %w;
    }

}

sub _updateCFG {
    my $self = shift;

    $$self{_NO_UPDATE_CFG} = 1;

    if (defined $$self{_GUI}{_MACROSBOX}) {
        $$self{_GUI}{_MACROSBOX}->hide;
        $$self{_GUI}{_MACROSBOX}->set_sensitive($$self{CONNECTED});
    }

    # Build ComboBoxes for macros
    if ($$self{_CFG}{'defaults'}{'show commands box'} == 1 && defined $$self{_GUI}{_MACROSBOX}) {
        $$self{_GUI}{_MACROSBOX}->show_all();
        # Empty every 'remote' and 'local' command
        $$self{_GUI}{_CBMACROSTERMINAL}->remove_all();
        $$self{_GUI}{_CBLOCALEXECTERMINAL}->remove_all();
        $$self{_GUI}{_BTNMACROSTERMINALEXEC}->set('can_focus', 0);
        $$self{_GUI}{_BTNLOCALTERMINALEXEC}->set('can_focus', 0);
        $$self{_GUI}{_BTNMACROSTERMINALEXEC}->set_sensitive($$self{CONNECTED});
        $$self{_GUI}{_CBMACROSTERMINAL}->set_sensitive($$self{CONNECTED});
        $$self{_GUI}{_BTNLOCALTERMINALEXEC}->set_sensitive(0);
        $$self{_GUI}{_CBLOCALEXECTERMINAL}->set_sensitive(0);

        ###################################################################
        # Populate the macros (remote executions) combobox
        foreach my $hash (sort {lc($$a{description}) cmp lc($$b{description})} @{$self->{_CFG}{'environments'}{$$self{_UUID}}{'macros'}}) {
            my $cmd = $$hash{txt};
            my $desc = $$hash{description} // '';
            my $confirm = $$hash{confirm};
            if ($cmd eq '') {
                next;
            }

            $$self{_GUI}{_BTNMACROSTERMINALEXEC}->set_sensitive(1);
            $$self{_GUI}{_CBMACROSTERMINAL}->set_sensitive(1);

            $$self{_GUI}{_CBMACROSTERMINAL}->append_text(($confirm ? 'CONFIRM: ' : '') . ($desc ? $desc : $cmd));

            $$self{_GUI}{_MACROSCLUSTER}->show();
            $$self{_GUI}{_MACROSBOX}->show();
            $$self{_GUI}{_BTNMACROSTERMINALEXEC}->show_all();
            $$self{_GUI}{_CBMACROSTERMINAL}->show_all();
        }
        foreach my $hash (sort {lc($$a{description}) cmp lc($$b{description})} @{$self->{_CFG}{'defaults'}{'remote commands'}}) {
            my $cmd = ref($hash) ? $$hash{txt} : $hash;
            my $desc = ref($hash) ? $$hash{description} : $hash;
            my $confirm = ref($hash) ? $$hash{confirm} : 0;
            if ($cmd eq '') {
                next;
            }

            $$self{_GUI}{_BTNMACROSTERMINALEXEC}->set_sensitive(1);
            $$self{_GUI}{_CBMACROSTERMINAL}->set_sensitive(1);

            $$self{_GUI}{_MACROSCLUSTER}->show();
            $$self{_GUI}{_CBMACROSTERMINAL}->append_text(($confirm ? 'CONFIRM: ' : '') . ($desc ? $desc : $cmd));
            $$self{_GUI}{_MACROSBOX}->show();
            $$self{_GUI}{_BTNMACROSTERMINALEXEC}->show_all();
            $$self{_GUI}{_CBMACROSTERMINAL}->show_all();
        }
        $$self{_GUI}{_CBMACROSTERMINAL}->set_active($$self{_BTNREMOTESEL} // 0);
        if ($$self{_SIGNALS}{_BTNMACROSTERMINALEXEC}) {
            $$self{_GUI}{_BTNMACROSTERMINALEXEC}->signal_handler_disconnect($$self{_SIGNALS}{_BTNMACROSTERMINALEXEC});
        }
        $$self{_SIGNALS}{_BTNMACROSTERMINALEXEC} = $$self{_GUI}{_BTNMACROSTERMINALEXEC}->signal_connect('clicked' => sub {
            my $active = $$self{_GUI}{_CBMACROSTERMINAL}->get_active;
            my $conn_cmds = scalar(@{$$self{_CFG}{'environments'}{$$self{_UUID}}{'macros'}});
            if ($$self{_GUI}{_CBMACROSTERMINAL}->get_active == -1) {
                return 1;
            }
            $$self{_BTNREMOTESEL} = $active;

            my $hash = $active >= $conn_cmds ? $$self{_CFG}{'defaults'}{'remote commands'}[$active - $conn_cmds] : $$self{_CFG}{'environments'}{$$self{_UUID}}{'macros'}[$active];
            my $cmd = $$hash{txt};
            my $desc = $$hash{description};
            my $confirm = $$hash{confirm};
            my $intro = $$hash{intro};

            my $ok = $self->_execute('remote', $cmd, $confirm, undef, undef, $intro);
            if (($ok)&&($$self{_GUI}{_MACROSCLUSTER}->get_active())) {
                $self->_clusterCommit(undef, $cmd . "\n", undef);
            }
            return 1;
        });
        ###################################################################

        ###################################################################
        # Populate the local executions combobox
        foreach my $hash (sort {lc($$a{description}) cmp lc($$b{description})} @{$self->{_CFG}{'environments'}{$$self{_UUID}}{'local connected'}}) {
            my $cmd = $$hash{txt};
            my $desc = $$hash{description} // '';
            my $confirm = $$hash{confirm};
            if ($cmd eq '') {
                next;
            }

            $$self{_GUI}{_BTNLOCALTERMINALEXEC}->set_sensitive(1);
            $$self{_GUI}{_CBLOCALEXECTERMINAL}->set_sensitive(1);

            $$self{_GUI}{_CBLOCALEXECTERMINAL}->append_text(($confirm ? 'CONFIRM: ' : '') . ($desc ? $desc : $cmd));

            $$self{_GUI}{_MACROSBOX}->show();
            $$self{_GUI}{_BTNLOCALTERMINALEXEC}->show_all();
            $$self{_GUI}{_CBLOCALEXECTERMINAL}->show_all();
        }
        foreach my $hash (sort {lc($$a{description}) cmp lc($$b{description})} @{$self->{_CFG}{'defaults'}{'local commands'}}) {
            my $cmd = ref($hash) ? $$hash{txt} : $hash;
            my $desc = ref($hash) ? $$hash{description} : $hash;
            my $confirm = ref($hash) ? $$hash{confirm} : 0;
            if ($cmd eq '') {
                next;
            }

            $$self{_GUI}{_BTNLOCALTERMINALEXEC}->set_sensitive(1);
            $$self{_GUI}{_CBLOCALEXECTERMINAL}->set_sensitive(1);

            $$self{_GUI}{_CBLOCALEXECTERMINAL}->append_text(($confirm ? 'CONFIRM: ' : '') . ($desc ? $desc : $cmd));
            $$self{_GUI}{_MACROSBOX}->show();
            $$self{_GUI}{_BTNLOCALTERMINALEXEC}->show_all();
            $$self{_GUI}{_CBLOCALEXECTERMINAL}->show_all();
        }
        $$self{_GUI}{_CBLOCALEXECTERMINAL}->set_active($$self{_BTNLOCALSEL} // 0);
        if ($$self{_SIGNALS}{_BTNLOCALTERMINALEXEC}) {
            $$self{_GUI}{_BTNLOCALTERMINALEXEC}->signal_handler_disconnect($$self{_SIGNALS}{_BTNLOCALTERMINALEXEC});
        }
        $$self{_SIGNALS}{_BTNLOCALTERMINALEXEC} = $$self{_GUI}{_BTNLOCALTERMINALEXEC}->signal_connect('clicked' => sub {
            my $active = $$self{_GUI}{_CBLOCALEXECTERMINAL}->get_active;
            my $conn_cmds = scalar(@{$$self{_CFG}{'environments'}{$$self{_UUID}}{'local connected'}});
            if ($active == -1) {
                return 1;
            }
            $$self{_BTNLOCALSEL} = $active;

            my $hash = $active >= $conn_cmds ? $$self{_CFG}{'defaults'}{'local commands'}[$active - $conn_cmds] : $$self{_CFG}{'environments'}{$$self{_UUID}}{'local connected'}[$active];
            my $cmd = $$hash{txt};
            my $desc = $$hash{description};
            my $confirm = $$hash{confirm};

            $self->_execute('local', $cmd, $confirm);
            return 1;
        });
        ###################################################################
    }
    # Build Buttons for macros
    elsif ($$self{_CFG}{'defaults'}{'show commands box'} == 2 && defined($$self{_GUI}{_MACROSBOX}))
    {
        my $isCluster = $$self{_CLUSTER} ? 1 : 0;
        my $wasMacroClusterActive = defined($$self{_GUI}{_MACROSCLUSTER}) ? $$self{_GUI}{_MACROSCLUSTER}->get_active() : $isCluster;

        my $updateMacroButton = sub  {
            my $str = 'Sending ' . ($$self{_GUI}{_MACROSCLUSTER}->get_active() ? 'CLUSTER' : 'THIS') . ':';
            $$self{_GUI}{_MACROSCLUSTER}->set_label($str);
        };

        $$self{_GUI}{_MACROSBOX}->set_sensitive($$self{CONNECTED});
        $$self{_GUI}{_MACROSBOX}->foreach(sub {$_[0]->destroy();});
        $$self{_GUI}{_MACROSCLUSTER} = Gtk3::CheckButton->new();
        $$self{_GUI}{_MACROSCLUSTER}->set('can-focus', 0);
        $$self{_GUI}{_MACROSCLUSTER}->signal_connect('toggled', $updateMacroButton);
        $$self{_GUI}{_MACROSCLUSTER}->set_active($wasMacroClusterActive);
        &$updateMacroButton();
        $$self{_GUI}{_MACROSBOX}->pack_start($$self{_GUI}{_MACROSCLUSTER}, 0, 1, 0);

        ###################################################################
        # Populate the macros (remote executions) buttons box
        my $i = 0;
        foreach my $hash (sort {lc($$a{description}) cmp lc($$b{description})} @{$self->{_CFG}{'environments'}{$$self{_UUID}}{'macros'}}) {
            my $cmd = $$hash{txt};
            my $desc = $$hash{description} // '';
            my $confirm = $$hash{confirm};
            my $intro = $$hash{intro};
            if ($cmd eq '') {
                next;
            }

            $$self{_GUI}{"_BTNMACRO_$i"} = Gtk3::Button->new();
            $$self{_GUI}{"_BTNMACRO_$i"}->set('can-focus', 0);
            $$self{_GUI}{"_BTNMACRO_$i"}->set_tooltip_text($cmd);
            my $btn1 = Gtk3::Label->new($desc ? $desc : $cmd);
            $btn1->set_ellipsize('PANGO_ELLIPSIZE_END');
            $$self{_GUI}{"_BTNMACRO_$i"}->add($btn1);
            $$self{_GUI}{"_BTNMACRO_$i"}->set_size_request(60, 20);
            $$self{_GUI}{_MACROSBOX}->pack_start($$self{_GUI}{"_BTNMACRO_$i"}, 1, 1, 0);
            $$self{_GUI}{_MACROSBOX}->show_all();

            $$self{_GUI}{"_BTNMACRO_$i"}->signal_connect('clicked' => sub {
                my $ok = $self->_execute('remote', $cmd, $confirm, undef, undef, $intro);
                if ($ok && $$self{_GUI}{_MACROSCLUSTER}->get_active()) {
                    $self->_clusterCommit(undef, $cmd . "\n", undef);
                }
            });

            ++$i;
        }
        if ($$self{_CFG}{'defaults'}{'show global commands box'}) {
            foreach my $hash (sort {lc($$a{description}) cmp lc($$b{description})} @{$self->{_CFG}{'defaults'}{'remote commands'}}) {
                my $cmd = ref($hash) ? $$hash{txt} : $hash;
                my $desc = ref($hash) ? $$hash{description} : $hash;
                my $confirm = ref($hash) ? $$hash{confirm} : 0;
                my $intro = ref($hash) ? $$hash{intro} : 0;
                if ($cmd eq '') {
                    next;
                }

                $$self{_GUI}{"_BTNMACRO_GLOB_$i"} = Gtk3::Button->new();
                $$self{_GUI}{"_BTNMACRO_GLOB_$i"}->set('can-focus', 0);
                $$self{_GUI}{"_BTNMACRO_GLOB_$i"}->set_tooltip_text($cmd);

                my $btn2 = Gtk3::Label->new($desc ? $desc : $cmd);
                $btn2->set_ellipsize('PANGO_ELLIPSIZE_END');
                $$self{_GUI}{"_BTNMACRO_GLOB_$i"}->add($btn2);
                $$self{_GUI}{"_BTNMACRO_GLOB_$i"}->set_size_request(60, 20);
                $$self{_GUI}{_MACROSBOX}->pack_start($$self{_GUI}{"_BTNMACRO_GLOB_$i"}, 1, 1, 0);
                $$self{_GUI}{_MACROSBOX}->show_all();

                $$self{_GUI}{"_BTNMACRO_GLOB_$i"}->signal_connect('clicked' => sub {
                    my $ok = $self->_execute('remote', $cmd, $confirm, undef, undef, $intro);
                    if ($ok && $$self{_GUI}{_MACROSCLUSTER}->get_active()) {
                        $self->_clusterCommit(undef, $cmd . "\n", undef);
                    }
                });

                ++$i;
            }
        }
    }

    _setTabColour($self);

    my $colors = [Gtk3::Gdk::RGBA::parse($$self{_CFG}{'defaults'}{'color black'} // '#000000000000'),  # black
        Gtk3::Gdk::RGBA::parse($$self{_CFG}{'defaults'}{'color red'}), # red
        Gtk3::Gdk::RGBA::parse($$self{_CFG}{'defaults'}{'color green'}), # green
        Gtk3::Gdk::RGBA::parse($$self{_CFG}{'defaults'}{'color yellow'}), # yellow (=brown)
        Gtk3::Gdk::RGBA::parse($$self{_CFG}{'defaults'}{'color blue'}), # blue
        Gtk3::Gdk::RGBA::parse($$self{_CFG}{'defaults'}{'color magenta'}), # magenta
        Gtk3::Gdk::RGBA::parse($$self{_CFG}{'defaults'}{'color cyan'}), # cyan
        Gtk3::Gdk::RGBA::parse($$self{_CFG}{'defaults'}{'color white'}), # white (=light grey)
        Gtk3::Gdk::RGBA::parse($$self{_CFG}{'defaults'}{'color bright black'}), # light black (=dark grey)
        Gtk3::Gdk::RGBA::parse($$self{_CFG}{'defaults'}{'color bright red'}), # light red
        Gtk3::Gdk::RGBA::parse($$self{_CFG}{'defaults'}{'color bright green'}), # light green
        Gtk3::Gdk::RGBA::parse($$self{_CFG}{'defaults'}{'color bright yellow'}), # light yellow
        Gtk3::Gdk::RGBA::parse($$self{_CFG}{'defaults'}{'color bright blue'}), # light blue
        Gtk3::Gdk::RGBA::parse($$self{_CFG}{'defaults'}{'color bright magenta'}), # light magenta
        Gtk3::Gdk::RGBA::parse($$self{_CFG}{'defaults'}{'color bright cyan'}), # light cyan
        Gtk3::Gdk::RGBA::parse($$self{_CFG}{'defaults'}{'color bright white'})
    ]; # light white
    # Update some VTE options
    if (($$self{_CFG}{environments}{$$self{_UUID}}{'terminal options'}{'use personal settings'}) && (defined $$self{_GUI}{_VTE})) {
        $$self{_GUI}{_VTE}->set_colors(scalar Gtk3::Gdk::RGBA::parse($$self{_CFG}{environments}{$$self{_UUID}}{'terminal options'}{'text color'}), scalar Gtk3::Gdk::RGBA::parse($$self{_CFG}{environments}{$$self{_UUID}}{'terminal options'}{'back color'}), $colors);
        if ($$self{_CFG}{defaults}{'terminal support transparency'} && $$self{_CFG}{environments}{$$self{_UUID}}{'terminal options'}{'terminal transparency'} > 0) {
            _setTransparency($self, $$self{_CFG}{environments}{$$self{_UUID}}{'terminal options'}{'terminal transparency'}, $$self{_CFG}{environments}{$$self{_UUID}}{'terminal options'}{'back color'});
        } else {
            $$self{_GUI}{_VTE}->set_color_background(scalar Gtk3::Gdk::RGBA::parse($$self{_CFG}{environments}{$$self{_UUID}}{'terminal options'}{'back color'}));
        }
        $$self{_GUI}{_VTE}->set_color_foreground(scalar Gtk3::Gdk::RGBA::parse($$self{_CFG}{environments}{$$self{_UUID}}{'terminal options'}{'text color'}));
        $$self{_GUI}{_VTE}->set_color_bold(scalar Gtk3::Gdk::RGBA::parse($$self{_CFG}{environments}{$$self{_UUID}}{'terminal options'}{'bold color like text'} ? $$self{_CFG}{environments}{$$self{_UUID}}{'terminal options'}{'text color'} : $$self{_CFG}{environments}{$$self{_UUID}}{'terminal options'}{'bold color'}));
        $$self{_GUI}{_VTE}->set_font(Pango::FontDescription::from_string($$self{_CFG}{environments}{$$self{_UUID}}{'terminal options'}{'terminal font'}));
        $$self{_GUI}{_VTE}->set_property('cursor-shape', $$self{_CFG}{environments}{$$self{_UUID}}{'terminal options'}{'cursor shape'});
        $$self{_GUI}{_VTE}->set_encoding($$self{_CFG}{environments}{$$self{_UUID}}{'terminal options'}{'terminal character encoding'} // 'UTF-8');
        $$self{_GUI}{_VTE}->set_backspace_binding($$self{_CFG}{environments}{$$self{_UUID}}{'terminal options'}{'terminal backspace'});
        $$self{_GUI}{_VTE}->set_word_char_exceptions($$self{_CFG}{environments}{$$self{_UUID}}{'terminal options'}{'terminal select words'});
        $$self{_GUI}{_VTE}->set_audible_bell($$self{_CFG}{environments}{$$self{_UUID}}{'terminal options'}{'audible bell'});
    } elsif (defined $$self{_GUI}{_VTE}) {
        $$self{_GUI}{_VTE}->set_colors(scalar Gtk3::Gdk::RGBA::parse($$self{_CFG}{'defaults'}{'text color'}), scalar Gtk3::Gdk::RGBA::parse($$self{_CFG}{'defaults'}{'back color'}), $colors);
        if ($$self{_CFG}{defaults}{'terminal support transparency'} && $$self{_CFG}{defaults}{'terminal transparency'} > 0) {
            _setTransparency($self, $$self{_CFG}{defaults}{'terminal transparency'}, $$self{_CFG}{'defaults'}{'back color'});
        } else {
            $$self{_GUI}{_VTE}->set_color_background(scalar Gtk3::Gdk::RGBA::parse($$self{_CFG}{'defaults'}{'back color'}));
        }
        $$self{_GUI}{_VTE}->set_color_foreground(scalar Gtk3::Gdk::RGBA::parse($$self{_CFG}{'defaults'}{'text color'}));
        $$self{_GUI}{_VTE}->set_color_bold(scalar Gtk3::Gdk::RGBA::parse($$self{_CFG}{'defaults'}{'bold color like text'} ? $$self{_CFG}{'defaults'}{'text color'} : $$self{_CFG}{'defaults'}{'bold color'}));
        $$self{_GUI}{_VTE}->set_font(Pango::FontDescription::from_string($$self{_CFG}{'defaults'}{'terminal font'}));
        $$self{_GUI}{_VTE}->set_property('cursor-shape', $$self{_CFG}{'defaults'}{'cursor shape'});
        $$self{_GUI}{_VTE}->set_encoding($$self{_CFG}{'defaults'}{'terminal character encoding'} // 'UTF-8');
        $$self{_GUI}{_VTE}->set_backspace_binding($$self{_CFG}{'defaults'}{'terminal backspace'});
        $$self{_GUI}{_VTE}->set_word_char_exceptions($$self{_CFG}{'defaults'}{'word characters'});
        $$self{_GUI}{_VTE}->set_audible_bell($$self{_CFG}{'defaults'}{'audible bell'});
    }

    if ($$self{_FOCUSED} && $$self{FOCUS}) {
        $$self{FOCUS}->child_focus('GTK_DIR_TAB_FORWARD');
    }
    $$self{_NO_UPDATE_CFG} = 0;

    return 1;
}

sub _setTransparency {
    my $self = shift;
    my $transparency = shift;
    my $bgcolor = shift;
    my $alpha = 1 - $transparency;

    my $color = Gtk3::Gdk::RGBA::parse($bgcolor);
    if (!$color) {
        $color = Gtk3::Gdk::RGBA::parse("#000000");
    }
    $color->alpha($alpha);
    $$self{_GUI}{_VTE}->set_color_background($color);
}

sub _wFindInTerminal {
    my $self = shift;
    our $searching = 0;
    our $stop = 0;
    our %w;
    my $text;

    if (defined $w{window}) {
        # Load the contents of the textbuffer with the corresponding log file
        if (open(F, "<:utf8",$$self{_LOGFILE})) {
            @{$$self{_TEXT}} = <F>;
            $text = _removeEscapeSeqs(join('', @{$$self{_TEXT}}));
            close F;
        } else {
            $text = "ERROR: Could not open file '$$self{_LOGFILE}': $!";
        }
        $w{window}{buffer}->set_text($text // '');

        return $w{window}{data}->present();
    }

    # Create the 'windowFind' dialog window,
    $w{window}{data} = Gtk3::Window->new();

    $w{window}{data}->signal_connect('delete_event' => sub {
        $searching = 0;
        $stop = 0;
        $w{window}{data}->destroy();
        undef %w;
        return 1;
    });

    $w{window}{data}->signal_connect('key_press_event' => sub {
        my ($widget, $event) = @_;
        my $keyval = '' . ($event->keyval);
        if ($keyval != 65307) {
            return 0;
        }
        $w{window}{gui}{btnclose}->activate();
        return 1;
    });

    # and setup some dialog properties.
    $w{window}{data}->set_title("$$self{_TITLE} : $APPNAME : Find in Terminal");
    $w{window}{data}->set_position('center');
    $w{window}{data}->set_icon_from_file($APPICON);
    $w{window}{data}->set_default_size(600, 400);
    $w{window}{data}->maximize();
    $w{window}{data}->set_resizable(1);

    # Create an hbox
    $w{window}{gui}{hboxmain} = Gtk3::HPaned->new();
    $w{window}{data}->add($w{window}{gui}{hboxmain});

    # Create a vbox
    $w{window}{gui}{vbox} = Gtk3::VBox->new(0, 0);
    $w{window}{gui}{vbox}->set_size_request(300, 200);
    $w{window}{gui}{hboxmain}->pack1($w{window}{gui}{vbox}, 1, 0);

    # Create frame 1
    $w{window}{gui}{frame1} = Gtk3::Frame->new();
    $w{window}{gui}{vbox}->pack_start($w{window}{gui}{frame1}, 0, 1, 0);
    $w{window}{gui}{frame1}->set_label(' Enter Regular Expression to look for: ');
    $w{window}{gui}{frame1}->set_border_width(5);

    $w{window}{gui}{hbox} = Gtk3::HBox->new(0, 0);
    $w{window}{gui}{frame1}->add($w{window}{gui}{hbox});
    $w{window}{gui}{hbox}->set_border_width(5);

    # Create 'find' image
    $w{window}{gui}{img} = Gtk3::Image->new_from_stock('gtk-find', 'dialog');
    $w{window}{gui}{hbox}->pack_start($w{window}{gui}{img}, 0, 1, 5);

    # Create search entry
    $w{window}{gui}{entry} = Gtk3::Entry->new();
    $w{window}{gui}{hbox}->pack_start($w{window}{gui}{entry}, 1, 1, 0);
    $w{window}{gui}{entry}->set_activates_default(1);
    $w{window}{gui}{entry}->has_focus();

    # Create 'case sensitive search' checkbutton
    $w{window}{gui}{cbCaseSensitive} = Gtk3::CheckButton->new_with_label('Case sensitive');
    $w{window}{gui}{hbox}->pack_start($w{window}{gui}{cbCaseSensitive}, 0, 1, 0);
    $w{window}{gui}{cbCaseSensitive}->set_active(0);

    # Create "Search" button
    $w{window}{gui}{btnfind} = Gtk3::Button->new_from_stock('gtk-find');
    $w{window}{gui}{hbox}->pack_start($w{window}{gui}{btnfind}, 0, 1, 0);
    $w{window}{gui}{btnfind}->signal_connect('clicked' => sub {
        if (!$searching) {
            $searching = 1;
            $self->_find;
            $searching = 0;
        } else {
            $stop = 1;
        }
    });
    $w{window}{gui}{btnfind}->set_can_default(1);
    $w{window}{gui}{btnfind}->grab_default;

    # Create frame 2
    $w{window}{gui}{frame2} = Gtk3::Frame->new();
    $w{window}{gui}{vbox}->pack_start($w{window}{gui}{frame2}, 1, 1, 0);
    $w{window}{gui}{frame2}->set_label(' Lines matching string: ');
    $w{window}{gui}{frame2}->set_border_width(5);

    # Create a GtkScrolledWindow,
    my $sctxt = Gtk3::ScrolledWindow->new();
    $w{window}{gui}{frame2}->add($sctxt);
    $sctxt->set_shadow_type('none');
    $sctxt->set_policy('automatic', 'automatic');
    $sctxt->set_border_width(5);

    # Create treefound
    $w{window}{gui}{treefound} = Gtk3::SimpleList->new_from_treeview (
        Gtk3::TreeView->new(),
        ' Line # ' => 'text',
        ' Line contents ' => 'text'
    );
    $w{window}{gui}{treefound}->set_headers_visible(1);
    $w{window}{gui}{treefound}->set_grid_lines('both');
    $w{window}{gui}{treefound}->get_selection->set_mode('multiple');

    $w{window}{gui}{treefound}->signal_connect('row_activated' => sub {
        my @index = $w{window}{gui}{treefound}->get_selected_indices;
        if (scalar(@index) != 1) {
            return;
        }
        my $id = pop(@index);
        $self->_showLine($w{window}{gui}{treefound}{data}[$id][0]);
        return 1;
   });

    # Put treefound into scrolled window
    $sctxt->add($w{window}{gui}{treefound});

    # Put a separator
    $w{window}{gui}{sep} = Gtk3::HSeparator->new();
    $w{window}{gui}{vbox}->pack_start($w{window}{gui}{sep}, 0, 1, 5);

    # Put a hbox to add copy/close buttons
    $w{window}{gui}{hbtnbox} = Gtk3::HBox->new();
    $w{window}{gui}{vbox}->pack_start($w{window}{gui}{hbtnbox}, 0, 1, 0);
    $w{window}{gui}{hbtnbox}->set_border_width(5);

    # Put a button to copy selected rows to clipboard
    $w{window}{gui}{btnCopy} = Gtk3::Button->new_from_stock('gtk-copy');
    $w{window}{gui}{hbtnbox}->pack_start($w{window}{gui}{btnCopy}, 1, 1, 0);
    $w{window}{gui}{btnCopy}->signal_connect('clicked' => sub {
        $$self{_GUI}{_VTE}->get_clipboard(Gtk3::Gdk::Atom::intern_static_string('CLIPBOARD'))->set_text (
            join(
            "\n",
            map $w{window}{gui}{treefound}{data}[$_][1],
            $w{window}{gui}{treefound}->get_selected_indices
        )),
    });

    # Put a 'close' button
    $w{window}{gui}{btnclose} = Gtk3::Button->new_from_stock('gtk-close');
    $w{window}{gui}{hbtnbox}->pack_start($w{window}{gui}{btnclose}, 0, 1, 0);
    $w{window}{gui}{btnclose}->signal_connect('clicked' => sub {$w{window}{data}->destroy(); undef %w; return 1;});

    # Create frame 3
    $w{window}{gui}{frame3} = Gtk3::Frame->new();
    $w{window}{gui}{frame3}->set_size_request(200, 200);
    $w{window}{gui}{hboxmain}->pack2($w{window}{gui}{frame3}, 1, 0);
    $w{window}{gui}{frame3}->set_label(' Contents of current log: ');
    $w{window}{gui}{frame3}->set_border_width(5);

    $w{window}{gui}{scroll} = Gtk3::ScrolledWindow->new();
    $w{window}{gui}{frame3}->add($w{window}{gui}{scroll});
    $w{window}{gui}{scroll}->set_policy('automatic', 'automatic');
    $w{window}{gui}{scroll}->set_border_width(5);

    if ($SOURCEVIEW) {
        $w{window}{buffer} = Gtk3::SourceView2::Buffer->new(undef);
        $w{window}{gui}{text} = Gtk3::SourceView2::View->new_with_buffer($w{window}{buffer});
        $w{window}{gui}{text} ->set_show_line_numbers(1);
        $w{window}{gui}{text} ->set_highlight_current_line(1);
    } else {
        $w{window}{buffer} = Gtk3::TextBuffer->new();
        $w{window}{gui}{text} = Gtk3::TextView->new_with_buffer($w{window}{buffer});
    }

    $w{window}{gui}{text}->set_editable(0);
    $w{window}{gui}{text}->modify_font(Pango::FontDescription::from_string('monospace'));
    $w{window}{gui}{scroll}->add($w{window}{gui}{text});

    $w{window}{data}->show_all();
    $w{window}{gui}{hboxmain}->set_position(($w{window}{data}->get_size) / 2);

    # Load the contents of the textbuffer with the corresponding log file
    if (open(F, "<:utf8",$$self{_LOGFILE})) {
        @{$$self{_TEXT}} = <F>;
        $text = _removeEscapeSeqs(join('', @{$$self{_TEXT}}));
        close F;
    } else {
        $text = "ERROR: Could not open file '$$self{_LOGFILE}': $!";
    }
    $w{window}{buffer}->set_text($text);

    sub _showLine {
        my $self = shift;
        my $line = shift;

        --$line;

        my $siter = $w{window}{buffer}->get_iter_at_line($line);
        my $eiter = $w{window}{buffer}->get_iter_at_line($line);
        $eiter->forward_to_line_end;
        $w{window}{buffer}->select_range($siter, $eiter);
        $w{window}{gui}{text}->scroll_to_iter($siter, 0, 1, 0, 0.5);

        return 1;
    }

    sub _find {
        my $self = shift;

        my $val = $w{window}{gui}{entry}->get_chars(0, -1);

        $w{window}{gui}{vbox}->get_window()->set_cursor(Gtk3::Gdk::Cursor->new('watch'));
        $w{window}{gui}{hbtnbox}->set_sensitive(0);
        $w{window}{gui}{frame2}->set_label(' PLEASE, WAIT. SEARCHING... ');
        $w{window}{gui}{btnfind}->set_label('STOP SEARCH');
        $w{window}{gui}{btnfind}->set_image(Gtk3::Image->new_from_stock('gtk-close', 'GTK_ICON_SIZE_BUTTON'));

        # Empty previous found lines
        @{$w{window}{gui}{'treefound'}{data}} = ();

        Gtk3::main_iteration while Gtk3::events_pending;

        my %found;
        my $i = 0;
        my $l = 0;
        my $regexp = $w{window}{gui}{cbCaseSensitive}->get_active ? qr/$val/m : qr/$val/im;
        foreach my $line (@{$$self{_TEXT}}) {
            ++$l;
            if ($stop) {
                last;
            }
            if (++$i >= 1000) {
                $i = 0;
                $w{window}{gui}{frame2}->set_label(' PLEASE, WAIT. Searching... (' . scalar(keys %found) . " lines matching '$val' so far in $l processed lines) ");
                Gtk3::main_iteration;
            }
            chomp $line;
            if ($line !~ /$regexp/) {
                next;
            }
            $found{$l} = _removeEscapeSeqs($line);
        }

        if ($stop) {
            # Update label text to announce that search was stopped
            $w{window}{gui}{frame2}->set_label(' SEARCH WAS STOPPED WITH ' . scalar(keys %found) . " LINES MATCHING '$val' SO FAR!! ");
            Gtk3::main_iteration;
            $stop = 0;
        } else {
            # Update label text with number of matches found
            $w{window}{gui}{frame2}->set_label(' PLEASE, WAIT. Updating... (' . scalar(keys %found) . " lines matching '$val') ");
            Gtk3::main_iteration while Gtk3::events_pending;
            # Update tree with the list of found lines
            foreach my $line_num (sort {$a <=> $b} keys %found) {
                push(@{$w{window}{gui}{treefound}{data}}, [$line_num, $found{$line_num}]);
            }
        }

        $w{window}{gui}{vbox}->get_window()->set_cursor(Gtk3::Gdk::Cursor->new('left-ptr'));
        $w{window}{gui}{hbtnbox}->set_sensitive(1);
        $w{window}{gui}{frame2}->set_label(' ' . scalar(keys %found) . " lines matching '$val': ");
        $w{window}{gui}{btnfind}->set_label('Find');
        $w{window}{gui}{btnfind}->set_image(Gtk3::Image->new_from_stock('gtk-find', 'GTK_ICON_SIZE_BUTTON'));

        $w{window}{gui}{entry}->has_focus();
        $w{window}{gui}{entry}->grab_focus();

        return 1;
    }

    return 1;
}

sub _checkSendKeystrokes {
    my $self = shift;
    my $data = shift // '';

    if (! defined $$self{_KEYS_RECEIVE}{cmd}) {
        delete $$self{_KEYS_RECEIVE};
        return $data;
    }

    my $prev_data = $data;
    $data = "CONNECTED: Sending keystrokes for FULL Duplication ($$self{_KEYS_RECEIVE}{sleep} seconds interval)...";

    my $keys = $$self{_KEYS_RECEIVE};
    my $accum = 0;
    my $i = 0;
    $$self{_PULSE} = 0;

    if (! defined $$self{_GUI}{pb}) {
        $$self{_GUI}{pb} = Gtk3::ProgressBar->new();
        $$self{_GUI}{bottombox}->pack_start($$self{_GUI}{pb}, 0, 1, 0);
        $$self{_GUI}{pb}->show();
    }

    foreach my $cmd (@{$$keys{cmd}}) {
        my $j = $i++;
        Glib::Timeout->add_seconds($accum += ($$keys{sleep}), sub {
            if (!defined $$self{_GUI}{pb}) {
                return 0;
            }

            $$self{_GUI}{pb}->set_fraction($j / ($#{$$keys{cmd}} || $#{$$keys{cmd}} + 1));
            _vteFeedChild($$self{_GUI}{_VTE}, $cmd . "\n");
            if ($j < $#{$$keys{cmd}}) {
                return 0; # Continue, unless finish reached
            }

            $$self{_GUI}{pb}->destroy();
            $$self{_GUI}{pb} = undef;
            delete $$self{_KEYS_RECEIVE};
            $data = $prev_data;
            $$self{_LAST_STATUS} = $data;
            $self->_updateCFG();
            $self->_updateStatus();

            return 0; # Finish
        });
    }

    return $data;
}

sub _disconnectTerminal {
    my $self = shift;

    if ($self->{CONNECTED} && $$self{_PID}) {
        # Hide the embed window to avoid unexpected updates or crashes when killing the underlying process
        if ($$self{_GUI}{_SOCKET} && $$self{_GUI}{_SOCKET}->get_plug_window()) {
            $self->_showEmbedMessages();
        }
        return kill(15, $$self{_PID});
    }

    return 0;
}

sub _disconnectAndRestartTerminal {
    my $self = shift;

    if ($self->_disconnectTerminal()) {
        # If successfully killed, restart
        Glib::Timeout->add_seconds(1, sub {
            $self->start();
            return 0;
        });
    }
}

sub _closeAllTerminals {
    my $self = shift;
    my @list = keys %PACMain::RUNNING;

    if (!(scalar(@list) && _wConfirm($$self{_PARENTWINDOW}, "Are you sure you want to close <b>all</b> terminals?"))) {
        return 1;
    }
    foreach my $uuid (@list) {
        if (ref($PACMain::RUNNING{$uuid}{'terminal'}) =~ /^PACTerminal|PACShell$/go) {
            $PACMain::RUNNING{$uuid}{'terminal'}->stop('force', 'deep');
        }
    }
    return 1;
}

sub _hasOtherTerminals {
    my $self = shift;
    my $list_count = keys %PACMain::RUNNING;

    return $list_count > 1;
}

sub _closeDisconnectedTerminals {
    my $self = shift;
    my @list = keys %PACMain::RUNNING;

    foreach my $uuid (@list) {
        if (defined $PACMain::RUNNING{$uuid}{'terminal'}{_LAST_STATUS} && $PACMain::RUNNING{$uuid}{'terminal'}{_LAST_STATUS} eq 'DISCONNECTED') {
            $PACMain::RUNNING{$uuid}{'terminal'}->stop('force', 'deep');
        }
    }
    return 1;
}

sub _hasDisconnectedTerminals {
    my $self = shift;
    my @list = keys %PACMain::RUNNING;

    foreach my $uuid (@list) {
        if (! defined $PACMain::RUNNING{$uuid}{'terminal'}{_LAST_STATUS} || ($PACMain::RUNNING{$uuid}{'terminal'}{_LAST_STATUS} eq 'DISCONNECTED')) {
            return 1;
        }
    }
    return 0;
}

sub _showInfoTab {
    my $self = shift;

    $PACMain::FUNCS{_MAIN}{_GUI}{nb}->set_current_page(0);
}

sub _hideEmbedMessages {
    my $self = shift;

    if (!$$self{_GUI}{_VTE}) {
        # Too late, probably ; message window does not exist anymore
        return;
    }

    # Hide messages and show the embed window
    $$self{_GUI}{_VTE}->hide();
    $$self{_GUI}{_SOCKET_PARENT_WINDOW}->show_all();
    if ($$self{FOCUS}) {
        $$self{FOCUS}->child_focus('GTK_DIR_TAB_FORWARD');
    }
    $$self{_GUI}{_BTNFOCUS}->set_sensitive(1);

    # Next time we click on the button, it will be to hide messages
    $$self{_GUI}{_BTNLOG}->set_label('Show _messages');
}

sub _showEmbedMessages {
    my $self = shift;

    if (!$$self{_GUI}{_VTE}) {
        # Too late, probably ; message window does not exist anymore
        return;
    }

    # Show messages and hide the embed window
    $$self{_GUI}{_SOCKET_PARENT_WINDOW}->hide();
    $$self{_GUI}{_VTE}->show();
    $$self{_GUI}{_VTE}->grab_focus();
    $$self{_GUI}{_BTNFOCUS}->set_sensitive(0);

    # Next time we click on the button, it will be to hide messages
    $$self{_GUI}{_BTNLOG}->set_label('Hide _messages');
}

sub _zoomHandler {
    my $self = shift;
    my $action = shift;

    my $zoom = 0;
    my $scale = $$self{_GUI}{_VTE}->get_font_scale();

    if ($action eq 'zoomin') {
        $zoom = 1;
        $scale += 0.1;
    } elsif ($action eq 'zoomout') {
        $zoom = 1;
        $scale -= 0.1;
    } elsif ($action eq 'zoomreset') {
        $zoom = 1;
        $scale = 1;
    }
    if ($zoom) {
        $$self{_GUI}{_VTE}->set_font_scale($scale);
        return 1;
    }

    return 0;
}

sub _pasteConnectionPassword {
    my $self = shift;
    my $pass = '';

    if ($$self{_CFG}{environments}{$$self{_UUID}}{'passphrase'} ne '') {
        $pass = $$self{_CFG}{environments}{$$self{_UUID}}{'passphrase'};
    } else {
        $pass = $$self{_CFG}{environments}{$$self{_UUID}}{'pass'};
    }
    if ($$self{_CFG}{defaults}{'keepass'}{'use_keepass'} && PACKeePass->isKeePassMask($pass)) {
        my $kpxc = $PACMain::FUNCS{_KEEPASS};
        $pass = $kpxc->applyMask($pass);
    }
    _vteFeedChild($$self{_GUI}{_VTE}, $pass);
}

sub _checkEmbedWindow {
    my $self = shift;
    my $time_to_connect = $self->{_CFG}{'defaults'}{'timeout connect'};

    if (!$$self{_GUI}{_SOCKET}) {
        # Too late, the socket does not exist anymore
        $self->{EMBED_CHECK_TIMEOUT_ID} = undef;
        return 0;
    }

    if ($$self{_GUI}{_SOCKET}->get_plug_window()) {
        $self->_hideEmbedMessages();
        # We found the plugged window, stop timeout
        $self->{EMBED_CHECK_TIMEOUT_ID} = undef;
        return 0;
    }

    if ($time_to_connect > 0 && ($self->{EMBED_CHECK_COUNT}++) * $self->{EMBED_CHECK_TIMEOUT} > 1000 * $time_to_connect) {
        # We waited too long, force disconnection (if still connected)
        if ($self->{CONNECTED}) {
            _vteFeed($$self{_GUI}{_VTE},"\r\n\n${COL_YELL}WARNING: No window could be connected with expected timeout of $time_to_connect seconds, aborting connection...${COL_RESET}\r\n(note: this timeout can be changed in Preferences > Terminal Options)\r\n");
            $self->_disconnectTerminal();
        }
        # and stop the timeout
        $self->{EMBED_CHECK_TIMEOUT_ID} = undef;
        return 0;
    };

    # Update GUI before querying the size of the embed window
    Gtk3::main_iteration() while Gtk3::events_pending();
    $self->_showEmbedMessages();

    # If not yet done, start a timeout that will check again that the embed window
    # if correctly plugged into the Ásbrú socket
    if (!defined($self->{EMBED_CHECK_TIMEOUT_ID})) {
        $self->{EMBED_CHECK_TIMEOUT_ID} = Glib::Timeout->add($self->{EMBED_CHECK_TIMEOUT}, sub {
            return $self->_checkEmbedWindow();
        });
    }

    return 1;
}

sub _stopEmbedKidnapTimeout {
    my $self = shift;

    if (defined($$self{_EMBED_KIDNAP})) {
        Glib::Source->remove($$self{_EMBED_KIDNAP});
        $$self{_EMBED_KIDNAP} = undef;
    }
}

# END: Private functions definitions
###################################################################

1;

__END__

=encoding utf8

=head1 NAME

PACTerminal.pm

=head1 SYNOPSIS

Package to create a terminal object with its own windows, event handlers and menus.

=head1 DESCRIPTION

=head2 Internal Variables

    $NPOSX,$NPOSY       Next coordinates to locate the next tiled window when opening a cluster in multiple windows

    _CFG                Pointer to configuration object structure
    _UUID               Internal UUID of this terminal in the nodes tree in PACMain
    _CLUSTER            Cluster name : If window is attached to a cluster
    _TABBED             0 No , 1 Yes
    _NAME               Name of this terminal from node tree configuration
    _LAST_STATUS        DISCONNECTED, CONNECTED
    _GUI                Access to gtk window object and its elements
    {_GUI}{_VTE}        Access to the Vte::Terminal object attached to this GUI
    _FOCUS              0 No , 1 Yes
    _GUILOCKED          0 No , 1 Yes
    _FOCUSED            0 No , 1 Yes
    _UUID_TMP           Current UUID assigned to this terminal : asbru_PID{pidnumber}_n$COUNT

=head2 sub new

Create new terminal object

    CONNECTED = 0
    CONNECTING = 0
    Calls _initGUI
    Calls _setupCallbacks
        _watchConnectionData : receive connection from forked connectin

=head2 sub DESTROY

Destroys object on exit

=head2 sub start

Create the connection

    Create connection using lib/asbru_conn
    Update progressbar
    CONNECTED=1
    Execute Startup scripts
    Grab focus

=head2 sub stop

Stop the terminal and the Gui

    Remove count of opened terminals for reposition cluster windows
    CONNECTED = 0
    Kill processes
    Close window, tab

=head2 sub lock

Lock terminal

=head2 sub unlock

Unlock Terminal

=head2 sub _initGUI

    Create Gtk Window and attach elements to it
    Create a terminal and assign instance to : {_GUI}{VTE}
    Attaches Terminal to newly created window
    Attach more elements to window depending on users options:
        Satusbar
        Command History
        Macro Buttons, List
    if _TABBED
        Append to Current tabs list
    else
        Create new Window and position on screen
        if Cluster
            Calculate screen width,height
            Calculate position of next terminal
            Move terminal and size to new position
    Call _updateCFG

=head2 sub _setupCallbacks

Attaches different event signals from Gui elements and the terminal to routines to handle each event

    Gui Callbacks for elements in the StatusBar
    Vte Callbacks
        Mouse events
        Keys events

=head2 sub _watchConnectionData

    Ignore 'hup','err' signals
    _receiveData    : load data into _SOCKET_BUFFER
    Process command received from attached connection
        CONNECTED              : inform the user we are connected, set icons messages
        EXPLORER
        PIPE_WAIT
        SCRIPT_(START|STOP)
        SCRIPT_SUB
        TITLE
        PAC_CONN_MSG
        CHAIN
        EXEC:RECEIVE_OUT
        SENDSLOW
        DISCONNECTED           : inform user we got disconnected
        EXPECT:WAIT
        SPAWNED
        UNHIDE_TERMINAL        : in window mode, unhide terminals that open rdp, vnc connections
        WENTER                 : request user to enter data and return to the forked connection


=head2 sub _receiveData

Read data from socket and save into _SOCKET_BUFFER

=head2 sub _sendData

Send a message to the de defined socket or the attached connection

=head2 sub _authClient

Validate the socket connection is from Asbru application and not some other process

=head2 sub _vteMenu

Display the popup Terminal menu on [shift] - right click

=head2 sub _setTabColour

Set the Tab title color based on the status of the terminal: green (connected) or red (disconnected)

=head2 sub _updateStatus

Update status information on Statusbar

=head2 sub _clusterCommit

Transmit characters to other terminals in the same cluster using the _vteFeedChild routine

=head2 sub _tabToWin

Move a tabbed terminal to a stand alone window

=head2 sub _winToTab

Move a window terminal to a Tab

=head2 sub _tabMenu

Open a popup menu with tabbed terminals

=head2 sub _split

Split terminal

=head2 sub _equalresize

Calculate width, height of new detached window or split

=head2 sub _unsplit

Closed split termina (on tb or window) and remove

=head2 sub _setupTabDND

Drag and Drop Terminals in Tab

=head2 sub _saveSessionLog

Create a log file of the current session session

=head2 sub _execute

Execute a typed command locally or remotely

=head2 sub _pipeExecOutput

Send command using a pipe to terminal

Command output read in : _watchConnectionData

=head2 sub _wPrePostExec (when)

Called on start to execute commands before connection
Called on disconnect to execute commands before connection ends

    calls   _execLocalPPE
            _ppeGUI

=head3 sub _execLocalPPE

Routine to execute pre post commands

=head3 sub _ppeGUI

Creates Dialog Window for pre post commands execution

=head2 sub _wSelectChain

Documentation pending

=head3 sub _chain

Pending

=head3 sub _chainGUI

Pending

=head2 sub _updateCFG

Update configuration changes in current session

=head2 sub _wFindInTerminal

Find Dialog to search session history

=head3 sub _showLine

Support routines to _wFindInTerminal

=head3 sub _find

Support routines to _wFindInTerminal

=head2 sub _wHistory

Creates the History window

=head2 sub _checkSendKeystrokes

Receives keystrokes from _watchConnectionData and transfer the data to the current terminal

=head2 sub _disconnectAndRestartTerminal

Kill the terminal and restart again

=head2 sub _closeAllTerminals

Function to close all opened terminals

=head2 sub _hasOtherTerminals

Check if there are other terminals open beside the current one

=head2 sub _closeDisconnectedTerminals

Close terminal window if disconnected

=head2 sub _hasDisconnectedTerminals

Returns true (1) if there are disconnected terminals, 0 if none

=head2 sub _showInfoTab

Show the information Tab

=head2 sub _hideEmbedMessages

For an embed connection, hide the console displaying the messages concerning the connection.

=head2 sub _showEmbedMessages

For an embed connection, show the console displaying the messages concerning the connection.

=head2 sub _zoomHandler

On a keypress, check if zoom factor of the terminal should be changed.

=head2 sub _hasKeePassField

Returns true (1) if this terminal has a least on field whose value is kept into a KeePass database file

=head2 sub _pasteConnectionPassword

Paste the password of the current connection into the current VTE terminal

=head1 Vte::Terminal

Reference to available methods are located at : https://developer.gnome.org/vte/

=head2 C to Perl mapping examples

    |C Methods                |Perl Methods                      |
    |-------------------------|----------------------------------|
    |vte_terminal_feed()      |$$self{'_GUI'}{_VTE}->feed()      |
    |vte_terminal_feed_child()|$$self{'_GUI'}{_VTE}->feed_child()|

=head2 Access to properties examples

    Properties are available through methods, though not all methods are documented and yet they exist

    |Properties   |C method to access a property  |Perl access to property                  |
    |-------------|-------------------------------|-----------------------------------------|
    |audible-bell |vte_terminal_set_audible_bell()|$$self{'_GUI'}{_VTE}->set_audible_bell() |
    |audible-bell |vte_terminal_get_audible_bell()|$$self{'_GUI'}{_VTE}->get_audible_bell() |
    |property-name|not documented                 |$$self{'_GUI'}{_VTE}->get_property_name()|

=head2 Signal handling examples

    |Signal      |Perl catch event                                                     |
    |------------|---------------------------------------------------------------------|
    |child-exited|$$self{_GUI}{_VTE}->signal_connect('child_exited' => sub {# my code})|
    |commit      |$$self{_GUI}{_VTE}->signal_connect('commit' => sub {# my code})      |

=======
