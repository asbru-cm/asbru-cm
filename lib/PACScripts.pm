package PACScripts;

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

# Standard
use strict;
use warnings;
use FindBin qw ($RealBin $Bin $Script);
use Encode qw (encode);
use File::Copy;
use File::Basename;
use Storable qw (dclone nstore_fd);

eval {require Gtk3::SourceView2;};
my $SOURCEVIEW = ! $@;

my $PERL = `which perl 2>&1`;

# GTK
use Gtk3 '-init';

# PAC modules
use PACUtils;

# END: Import Modules
###################################################################

###################################################################
# Define GLOBAL CLASS variables

my $APPNAME = $PACUtils::APPNAME;
my $APPVERSION = $PACUtils::APPVERSION;
my $APPICON = $RealBin . '/res/asbru-logo-64.png';
my $CFG_DIR = $ENV{"ASBRU_CFG"};
my $SCRIPTS_DIR = $CFG_DIR . '/scripts';

# PAC Help
my $PAC_SCRIPTS_HELP = '#Ásbrú Scripts are simple Perl programs, so:
use strict;        # Get serious :)
use warnings;    # Really serious! ;)

# Inherited Variables, containing both variables and subroutine references
# It is *MANDATORY* to declare them (as "our" or "local")

our %SHARED;    # Hash to pass data from SESSION to CONNECTION
our %COMMON;    # Common Ásbrú utilities (substitutions, etc...) to be used *ANYWHERE* in script
our %PAC;        # GUI/Terminals manipulation to be used under *SESSION* subroutine
our %TERMINAL;    # Command/Prompt manipulation to be used under *CONNECTION* subroutine

# *ATTENTION* Anything written OUT of SESSION and CONNECTION, will be executed *at least*:
# once for SESSION management and once for every started/selected CONNECTION.
# As a rule of thumb, you should not write big chunks of code outside SESSION or CONNECTION
# (For all you Perl Gurus: in fact, this script is "eval\'ed" twice)

####################################################
# %SHARED hash definition
####################################################

# %SHARED hash is a simple container to pass data from SESSION
# to CONNECTION subroutine, which do not share any other variable.
# So, if want to retrieve any data at sessions start/selection, use
# %SHARED as your data storage

%{$list} = $SHARED{_list_};
# This special pre-populated variable contains the list of connections
# started/selected at SESSION subroutine.
# It will only be populated once SESSION has been executed, so,
# it will *only* be availabe on CONNECTION subroutine

####################################################
# %COMMON hash definition
####################################################

%{$cfg} = $COMMON{cfg}([0|1]);
# Retrieve a copy (0->default) or a reference (1) to *whole* PAC\'s configuration
# *ATTENTION* Retrieving a REFERENCE (1) to PAC\'s config may lead to Ásbrú misconfiguration!!
# NOT RECOMMENDED!! USE AT YOUR VERY OWN RISK!!!!!!

$txt = $COMMON{subst}(<text>);
# Substitute given text with internal variables (<ASK:desc|opt1|opt2|...|optN>, <GV:2>, ...)
# Returns a string

$txt = $COMMON{del_esc}(<text>)
# Remove ESCape sequences (mainly used for removing ANSI colouring output)
# Returns a string

$COMMON{cfg_sanity}(\%cfg);
# Perform a sanity check for given %cfg (reference!), which may be empty, in which case it will
# construct an empty Ásbrú cfg skeleton over *referenced* %cfg variable
# Returns a string

####################################################
# %PAC hash definition
####################################################

($uuid, $tmp_uuid) = $PAC{start_uuid}(<UUID>[, <cluster>]);
# Start session with given "UUID" (optionally in cluster "cluster")
# Returns an array with UUID and temporal UUID of started connection

($uuid, $tmp_uuid) = $PAC{start_uuid_manual}(<UUID>);
# Start session with given "UUID" with manual login flag set
# Returns an array with UUID and temporal UUID of started connection

($uuid, $tmp_uuid) = $PAC{start}(<name>[, <cluster>]);
# Start session named "name" (optionally in cluster "cluster")
# Returns an array with UUID and temporal UUID of started connection

($uuid, $tmp_uuid) = $PAC{start_manual}(<name>);
# Start session named "name" with manual login flag set
# Returns an array with UUID and temporal UUID of started connection

($uuid, $tmp_uuid) = $PAC{select}(<name>);
# Select an existing session named "name"
# Returns an array with UUID and temporal UUID of selected connection

%{$connections_list} = $PAC{select}("*ALL*");
# Select ALL open sessions
# Return a hash ref {tmp_uuid => uuid} with the list of selected terminals

$PAC{stop}(<$tmp_uuid>);
# Stop and close session identified by $tmp_uuid

$PAC{msg}([<message text>[, 0|1]]);
# Shows a message window with given "message_text" or
# hide any existing message window if no "message_text" is provided, and
# an OK (1) or not (0->default) button

$PAC{split}(<$tmp_uuid1>, <$tmp_uuid2>[, 0|1]);
# Split horizontally (0->default) or vertically (1) given connections

$PAC{unsplit}(<$tmp_uuid>);
# Unsplit given connection

$PAC{to_window}(<$tmp_uuid>);
# Untab given connection

$PAC{to_tab}(<$tmp_uuid>);
# Retab given connection

$file = $PAC{cfg_save}();
# Save current Ásbrú cfg to standard Ásbrú config file.
# Returns the name of such file

$file = $PAC{cfg_export}([file]);
# Save current Ásbrú cfg to given file (or ask for a file through a GUI if no file provided)
# in YAML format, suitable to be imported in any PAC instance
# Returns the name of saved file

####################################################
# %TERMINAL hash definition
####################################################

$filehandle = $TERMINAL{log}([<log file>]);
# Function to set/remove output log file
# Returns the filehandle for given log file

$input = $TERMINAL{ask}(<text>[, 0|1]);
# Ask user for input, showing (1->default) or not (0)  user input
# Returns a string with user provided text, or undef

$expect_obj = $TERMINAL{exp}();
# Returns the Perl Expect object for this connection (see "perldoc Expect")
# *WARNING*, Low level! Not recommended!

$TERMINAL{name};
# Constant with the Name of the connection

$TERMINAL{uuid};
# Constant with the UUID of the connection

$TERMINAL{tmp_uuid};
# Constant with the Temporal UUID of current executing connection

$TERMINAL{error};
# Variable with the latest error from the "expect" function

$TERMINAL{msg}(<text>);
# Function to print an ANSI coloured message on the Terminal

$prompt = $TERMINAL{get_prompt}([0|1]);
# Function to GUESS this connection prompt and remove (1->default) or not (0) any ESCape sequence (tipically for colouring)
# Returns a Quoted string "\Qprompt_sting\E" valid for RegExp matching or $TERMINAL{expect}($prompt) API function
# Prompt is guessed by simply sending an INTRO to the connection, and checking the difference between current and previous line,
# so, it may not work for dynamic or menu-driven prompts

$TERMINAL{send}(<string[\n]>);
# Function to SEND some string (input) to the connection (\n sends a <INTRO>)

$out = $TERMINAL{send_get}(<string>[, 0]);
# Function to SEND some string (input) to the connection (\n is auto-inserted unless ", 0" is appended as parameter) and RETRIEVE
# its output in a best-effort manner (may not work on some kind of terminals), or UNDEF otherwise.
# First line of $out (which contains the command executed) is removed, and the
# $COMMON{del_esq} function is applied, in order to remove every "ugly" character
# This function has a timeout to retrieve the output defined by any "default" PAC config
# or per connection defined on "time out command" variable (40 seconds default)

$res = $TERMINAL{expect}(<string>[, <seconds>]);
# Function to EXPECT for some STRING (Perl RegExp) from the connection for given SECONDS, or 1 second if undefined
# Returns, TRUE (1) on STRING found or FALSE (0) otherwise
# Sets $TERMINAL{error} variable with the error that produced the EXPECT not matching given STRING.
# If STRINGS matches, then other two variables are set:
# $TERMINAL{out1}->contains the output of the latest string sent UP TO the matched STRING (the one you usually want!)
#                     Its first line will probably be the command executed
# $TERMINAL{out2}->contains the output of the latest string sent FROM the matched STRING onwards
# It is *CRUCIAL* that "string" matches correctly what you want or you will end up with
# wrong data collected in $TERMINAL{out1} and $TERMINAL{out2}, and an unresponsive terminal (until TIMEOUT reaches)
# All $TERMINAL{error|out1|out2} are resetted every time a SEND command is executed

sub SESSION
{
    # Subroutine SESSION->return 1 (true) to identify a good ending, or 0 (false) to notice a controlled bad ending
    # Here you START (or SELECT alreday started) connections where you want to run this script (the CONNECTION subroutine)
    # This definition is mandatory if you want to execute this script from PAC\'s "Scripts" GUI, but optional
    # if you want to execute it from a connection\'s right-click context menu
    # This routine is executed *ONCE*
    # If you want to ask for some variable and then reuse the output on every connection, you should
    # write something like:
    # my $SHARE{cmd} = $COMMON{subst}("<ASK:Command to send|ls -laF|df -h|uptime|date>");
    # From now on, $SHARE{cmd} will contain the output from the user input, and will be also available
    # on the CONNECTION subroutine
    #
    # Here you can use: %COMMON, %PAC and %SHARED (NOT pre-populated at all)

    return 1;
}

sub CONNECTION
{
    # Subroutine CONNECTION->return 1 (true) to identify a good ending, or 0 (false) to notice a controlled bad ending
    # Here you decide what to do on every previously selected connection(what to send, what to expect for, ...)
    # This subroutine will be executed on *every started/selected* connection from the SESSION definition above,
    # so you may want to make some kind of check before sending/expecting anything.
    # %SHARED hash is available under CONNECTION
    #
    # Here you can use: %COMMON, %TERMINAL and %SHARED (pre-populated with $SHARED{_list_})
    #
    # It is always a *GOOD* idea to start the scripts by EXPECting a regular command prompt IF the connection was
    # started by us (the script, with $PAC{start}). Other else ($PAC{select}), you should not need to make any initial expect.
    # $TERMINAL{expect}("\[your_user_name@your_hostname ~\]");

    return 1;
}

return 1;';

# PAC New Script Body
my $PAC_SCRIPTS_NEW = '# PAC Script
use strict;        # Get serious :)
use warnings;    # Really serious! ;)

our (%COMMON, %PAC, %TERMINAL, %SHARED);

sub SESSION
{
    # Start/select connections

    return 1;
}

sub CONNECTION
{
    # Do things on every started/selected connection
    # my $prompt = $TERMINAL{get_prompt}();

    return 1;
}

return 1;';

# END: Define GLOBAL CLASS variables
###################################################################

###################################################################
# START: Define PUBLIC CLASS methods

sub new {
    my $class = shift;

    my $self = {};

    $self->{_WINDOWSCRIPTS} = undef;
    $self->{_SCRIPTS} = {};
    $self->{_UNDO} = ();
    $self->{_SELECTED} = '';
    $self->{_PREVENT_UPDATES} = 0;
    $self->{_SYNTAX_CHANGED} = 0;
    $self->{_TIMER_CHECK} = undef;

    # Build the GUI
    _initGUI($self) or return 0;

    # Setup callbacks
    _setupCallbacks($self);

    # Load the scripts list
    _reloadDir($self);

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
sub show {
    my $self = shift;

    $$self{_WINDOWSCRIPTS}{main}->show_all;
    $$self{_WINDOWSCRIPTS}{main}->present;

    $self->_reloadDir unless $$self{_WINDOWSCRIPTS}{main}->get_window->is_visible;
    $self->_updateGUI;

    # Setup a timer to check syntax of selected script
    (! defined $$self{_TIMER_CHECK} && $PERL) and $$self{_TIMER_CHECK} = Glib::Timeout->add_seconds(1, sub {
        return 1 unless $$self{_WINDOWSCRIPTS}{main}->get_property('has-toplevel-focus') && $$self{_SYNTAX_CHANGED};

        my $selection = $$self{_WINDOWSCRIPTS}{treeScripts}->get_selection;
        my $model = $$self{_WINDOWSCRIPTS}{treeScripts}->get_model;

        my @sel = _getSelectedRows($selection);
        if (scalar @sel != 1) {
            $$self{_WINDOWSCRIPTS}{gui}{status}->set_markup('');
            $$self{_WINDOWSCRIPTS}{gui}{status}->set_tooltip_text('');
            return 1;
        }

        my $file = $model->get_value($model->get_iter($sel[0]), 0);
        my $name = $model->get_value($model->get_iter($sel[0]), 1);

        my $tmpfile = $CFG_DIR . '/tmp/' . $name . '.check';
        $self->_saveFile($sel[0], $tmpfile);

        my @lines = `perl -cw $tmpfile 2>&1`;
        my $err = $?;
        my $result = pop(@lines); chomp $result;
        $result =~ s/^\Q$tmpfile\E\s+(.+)$/$1/g;

        $$self{_WINDOWSCRIPTS}{gui}{status}->set_markup('<span foreground="' . ($err ? 'red' : '#00D206') . '">' . "<b>" . __("$name: $result") . "</b>" . '</span>');
        $$self{_WINDOWSCRIPTS}{gui}{status}->set_tooltip_text(' * ' . localtime(time) . " :\n" . ($err ? join('', @lines) : 'syntax ok') );

        $$self{_SYNTAX_CHANGED} = 0;
        return 1;
    });

    return 1;
}

sub scriptsList {return wantarray ? keys %{$_[0]{_SCRIPTS}} : $_[0]{_SCRIPTS};}

# END: Define PUBLIC CLASS methods
###################################################################

###################################################################
# START: Define PRIVATE CLASS functions

sub _initGUI {
    my $self = shift;

    # Create the 'windowFind' dialog window,
    $$self{_WINDOWSCRIPTS}{main} = Gtk3::Window->new;

    # and setup some dialog properties.
    $$self{_WINDOWSCRIPTS}{main}->set_title("$APPNAME (v$APPVERSION) : Scripts");
    $$self{_WINDOWSCRIPTS}{main}->set_position('center');
    $$self{_WINDOWSCRIPTS}{main}->set_icon_from_file($APPICON);
    $$self{_WINDOWSCRIPTS}{main}->set_default_size(800, 500);
    $$self{_WINDOWSCRIPTS}{main}->set_resizable(1);
    $$self{_WINDOWSCRIPTS}{main}->maximize;

        $$self{_WINDOWSCRIPTS}{gui}{vbox} = Gtk3::VBox->new(0, 0);
        $$self{_WINDOWSCRIPTS}{main}->add($$self{_WINDOWSCRIPTS}{gui}{vbox});

            my $hboxaux = Gtk3::HBox->new(0, 0);
            $$self{_WINDOWSCRIPTS}{gui}{vbox}->pack_start($hboxaux, 0, 1, 0);
            $hboxaux->pack_start(PACUtils::_createBanner('asbru-scripts-manager.svg', 'Scripts Manager'), 1, 1, 0);

            # Create an hpane
            $$self{_WINDOWSCRIPTS}{gui}{hpane} = Gtk3::HPaned->new;
            $$self{_WINDOWSCRIPTS}{gui}{vbox}->pack_start($$self{_WINDOWSCRIPTS}{gui}{hpane}, 1, 1, 0);

                # Terminals list
                $$self{_WINDOWSCRIPTS}{gui}{scroll2} = Gtk3::ScrolledWindow->new;
                $$self{_WINDOWSCRIPTS}{gui}{hpane}->pack1($$self{_WINDOWSCRIPTS}{gui}{scroll2}, 0, 0);
                $$self{_WINDOWSCRIPTS}{gui}{scroll2}->set_policy('automatic', 'automatic');

                    $$self{_WINDOWSCRIPTS}{treeScripts} = Gtk3::SimpleList->new_from_treeview (
                        Gtk3::TreeView->new,
                        'FILE' => 'hidden',
                        'SCRIPT' => 'text'
                    );

                    $$self{_WINDOWSCRIPTS}{gui}{scroll2}->add($$self{_WINDOWSCRIPTS}{treeScripts});
                    $$self{_WINDOWSCRIPTS}{treeScripts}->set_tooltip_text('Ásbrú Scripts. You may Drag \'n Drop Perl (.pl) files here to import them.');
                    $$self{_WINDOWSCRIPTS}{treeScripts}->set_headers_visible(1);
                    $$self{_WINDOWSCRIPTS}{treeScripts}->get_selection->set_mode('GTK_SELECTION_MULTIPLE');

                # Create a notebook
                $$self{_WINDOWSCRIPTS}{nb} = Gtk3::Notebook->new;
                $$self{_WINDOWSCRIPTS}{gui}{hpane}->pack2($$self{_WINDOWSCRIPTS}{nb}, 1, 0);

                    # PAC Script Editor

                    my $tablbl = Gtk3::HBox->new(0, 0);
                    $tablbl->pack_start(Gtk3::Label->new(' Script Editor '), 1, 1, 0);
                    $tablbl->pack_start(Gtk3::Image->new_from_stock('asbru-script', 'menu'), 0, 1, 0);
                    $tablbl->show_all;

                    $$self{_WINDOWSCRIPTS}{gui}{hpanededitfunc} = Gtk3::HPaned->new;
                    $$self{_WINDOWSCRIPTS}{nb}->append_page($$self{_WINDOWSCRIPTS}{gui}{hpanededitfunc}, $tablbl);
                    $$self{_WINDOWSCRIPTS}{nb}->set_tab_reorderable($$self{_WINDOWSCRIPTS}{gui}{hpanededitfunc}, 0);
                    $$self{_WINDOWSCRIPTS}{nb}->set_tab_detachable($$self{_WINDOWSCRIPTS}{gui}{hpanededitfunc}, 0);

                        $$self{_WINDOWSCRIPTS}{gui}{vboxedit} = Gtk3::VBox->new(0, 0);
                        $$self{_WINDOWSCRIPTS}{gui}{hpanededitfunc}->pack1($$self{_WINDOWSCRIPTS}{gui}{vboxedit}, 0, 0);

                            $$self{_WINDOWSCRIPTS}{gui}{scrollMultiText} = Gtk3::ScrolledWindow->new;
                            $$self{_WINDOWSCRIPTS}{gui}{vboxedit}->pack_start($$self{_WINDOWSCRIPTS}{gui}{scrollMultiText}, 1, 1, 0);
                            $$self{_WINDOWSCRIPTS}{gui}{scrollMultiText}->set_policy('automatic', 'automatic');
                            $$self{_WINDOWSCRIPTS}{gui}{scrollMultiText}->set_border_width(5);

                                if ($SOURCEVIEW) {
                                    $$self{_WINDOWSCRIPTS}{multiTextBuffer} = Gtk3::SourceView2::Buffer->new(undef);
                                    $$self{_WINDOWSCRIPTS}{gui}{textScript} = Gtk3::SourceView2::View->new_with_buffer($$self{_WINDOWSCRIPTS}{multiTextBuffer});
                                    $$self{_WINDOWSCRIPTS}{gui}{textScript} ->set_smart_home_end('before');
                                    $$self{_WINDOWSCRIPTS}{gui}{textScript} ->set_show_line_numbers(1);
                                    $$self{_WINDOWSCRIPTS}{gui}{textScript} ->set_tab_width(4);
                                    $$self{_WINDOWSCRIPTS}{gui}{textScript} ->set_indent_on_tab(1);
                                    $$self{_WINDOWSCRIPTS}{gui}{textScript} ->set_auto_indent(1);
                                    $$self{_WINDOWSCRIPTS}{gui}{textScript} ->set('auto-indent', 1);
                                    $$self{_WINDOWSCRIPTS}{gui}{textScript} ->set_highlight_current_line(1);
                                    $$self{_WINDOWSCRIPTS}{gui}{textScript}->modify_font(Pango::FontDescription::from_string('monospace') );
                                } else {
                                    $$self{_WINDOWSCRIPTS}{multiTextBuffer} = Gtk3::TextBuffer->new;
                                    $$self{_WINDOWSCRIPTS}{gui}{textScript} = Gtk3::TextView->new_with_buffer($$self{_WINDOWSCRIPTS}{multiTextBuffer});
                                }

                                $$self{_WINDOWSCRIPTS}{gui}{textScript}->set_border_width(5);
                                $$self{_WINDOWSCRIPTS}{gui}{textScript}->set_size_request(320, 200);
                                $$self{_WINDOWSCRIPTS}{gui}{scrollMultiText}->add($$self{_WINDOWSCRIPTS}{gui}{textScript});
                                $$self{_WINDOWSCRIPTS}{gui}{textScript}->set_wrap_mode('GTK_WRAP_WORD');
                                $$self{_WINDOWSCRIPTS}{gui}{textScript}->set_sensitive(1);
                                $$self{_WINDOWSCRIPTS}{gui}{textScript}->set('can_focus', 1);

                            if (! $SOURCEVIEW) {
                                $$self{_WINDOWSCRIPTS}{gui}{statusLib} = Gtk3::Statusbar->new;
                                $$self{_WINDOWSCRIPTS}{gui}{vboxedit}->pack_start($$self{_WINDOWSCRIPTS}{gui}{statusLib}, 0, 1, 0);
                                $$self{_WINDOWSCRIPTS}{gui}{statusLib}->push(1, "Install 'libgtk2-sourceview2-perl' to enjoy Syntax Highlight");
                            }

                            $$self{_WINDOWSCRIPTS}{gui}{status} = Gtk3::Label->new;
                            $$self{_WINDOWSCRIPTS}{gui}{status}->set_justify('center');
                            $$self{_WINDOWSCRIPTS}{gui}{vboxedit}->pack_start($$self{_WINDOWSCRIPTS}{gui}{status}, 0, 1, 0);

                        # API functions list
                        $$self{_WINDOWSCRIPTS}{gui}{scrollfunc} = Gtk3::ScrolledWindow->new;
                        $$self{_WINDOWSCRIPTS}{gui}{hpanededitfunc}->pack2($$self{_WINDOWSCRIPTS}{gui}{scrollfunc}, 0, 0);
                        $$self{_WINDOWSCRIPTS}{gui}{scrollfunc}->set_policy('automatic', 'automatic');

                            $$self{_WINDOWSCRIPTS}{treeFuncs} = Gtk3::SimpleList->new_from_treeview (
                                Gtk3::TreeView->new,
                                'API NAME' => 'hidden',
                                'API CALL' => 'markup',
                            );
                            $$self{_WINDOWSCRIPTS}{gui}{scrollfunc}->add($$self{_WINDOWSCRIPTS}{treeFuncs});
                            $$self{_WINDOWSCRIPTS}{treeFuncs}->set_headers_visible(1);
                            $$self{_WINDOWSCRIPTS}{treeFuncs}->get_selection->set_mode('GTK_SELECTION_SINGLE');

                            push(@{$$self{_WINDOWSCRIPTS}{treeFuncs}{data}},
                                ['$SHARED{_list_}'                                    , '<span foreground="#606060">'        . __('$SHARED{_list_}')                                    . '</span>'],
                                ['$COMMON{cfg}([0|1])'                            , '<span foreground="#007710">'        . __('$COMMON{cfg}([0|1])')                                . '</span>'],
                                ['$COMMON{subst}(<text>)'                            , '<span foreground="#007710">'        . __('$COMMON{subst}(<text>)')                            . '</span>'],
                                ['$COMMON{del_esc}(<text>)'                        , '<span foreground="#007710">'        . __('$COMMON{del_esc}(<text>)')                        . '</span>'],
                                ['$COMMON{cfg_sanity}(\%cfg)'                        , '<span foreground="#007710">'        . __('$COMMON{cfg_sanity}(\%cfg)')                        . '</span>'],
                                ['$PAC{start_uuid}(<UUID>[, <cluster>])'            , '<span foreground="blue">'        . __('$PAC{start_uuid}(<UUID>[, <cluster>])')            . '</span>'],
                                ['$PAC{start_uuid_manual}(<UUID>)'                , '<span foreground="blue">'        . __('$PAC{start_uuid_manual}(<UUID>)')                    . '</span>'],
                                ['$PAC{start}(<name>[, <cluster>])'                , '<span foreground="blue">'        . __('$PAC{start}(<name>[, <cluster>])')                . '</span>'],
                                ['$PAC{start_manual}(<name>)'                        , '<span foreground="blue">'        . __('$PAC{start_manual}(<name>)')                        . '</span>'],
                                ['$PAC{select}(<name>)'                            , '<span foreground="blue">'        . __('$PAC{select}(<name>)')                            . '</span>'],
                                ['$PAC{select}("*ALL*")'                            , '<span foreground="blue">'        . __('$PAC{select}("*ALL*")')                            . '</span>'],
                                ['$PAC{stop}(<$tmp_uuid>)'                        , '<span foreground="blue">'        . __('$PAC{stop}(<$tmp_uuid>)')                            . '</span>'],
                                ['$PAC{msg}(<text>[, 0|1])'                        , '<span foreground="blue">'        . __('$PAC{msg}(<text>[, 0|1])')                        . '</span>'],
                                ['$PAC{split}(<$tmp_uuid1>, <$tmp_uuid2>[, 0|1])'    , '<span foreground="blue">'        . __('$PAC{split}(<$tmp_uuid1>, <$tmp_uuid2>[, 0|1])')    . '</span>'],
                                ['$PAC{unsplit}(<$tmp_uuid>)'                        , '<span foreground="blue">'        . __('$PAC{unsplit}(<$tmp_uuid>)')                        . '</span>'],
                                ['$PAC{to_window}(<$tmp_uuid>)'                    , '<span foreground="blue">'        . __('$PAC{to_window}(<$tmp_uuid>)')                    . '</span>'],
                                ['$PAC{to_tab}(<$tmp_uuid>)'                        , '<span foreground="blue">'        . __('$PAC{to_tab}(<$tmp_uuid>)')                        . '</span>'],
                                ['$PAC{cfg_save}()'                                    , '<span foreground="blue">'        . __('$PAC{cfg_save}()')                                    . '</span>'],
                                ['$PAC{cfg_export}(<filename>)'                    , '<span foreground="blue">'        . __('$PAC{cfg_export}(<filename>)')                    . '</span>'],
                                ['$TERMINAL{log}([<log file>])'                    , '<span foreground="red">'            . __('$TERMINAL{log}([<log file>])')                    . '</span>'],
                                ['$TERMINAL{ask}(<text>[, 0|1])'                    , '<span foreground="red">'            . __('$TERMINAL{ask}(<text>[, 0|1])')                    . '</span>'],
                                ['$TERMINAL{exp}()'                                    , '<span foreground="red">'            . __('$TERMINAL{exp}()')                                    . '</span>'],
                                ['$TERMINAL{name}'                                    , '<span foreground="red">'            . __('$TERMINAL{name}')                                    . '</span>'],
                                ['$TERMINAL{uuid}'                                    , '<span foreground="red">'            . __('$TERMINAL{uuid}')                                    . '</span>'],
                                ['$TERMINAL{tmp_uuid}'                                , '<span foreground="red">'            . __('$TERMINAL{tmp_uuid}')                                . '</span>'],
                                ['$TERMINAL{error}'                                    , '<span foreground="red">'            . __('$TERMINAL{error}')                                    . '</span>'],
                                ['$TERMINAL{msg}(<text>)'                            , '<span foreground="red">'            . __('$TERMINAL{msg}(<text>)')                            . '</span>'],
                                ['$TERMINAL{get_prompt}([0|1])'                    , '<span foreground="red">'            . __('$TERMINAL{get_prompt}([0|1])')                    . '</span>'],
                                ['$TERMINAL{send}(<string[\n]>)'                    , '<span foreground="red">'            . __('$TERMINAL{send}(<string[\n]>)')                    . '</span>'],
                                ['$TERMINAL{send_get}(<string>[, 0])'                , '<span foreground="red">'            . __('$TERMINAL{send_get}(<string>[, 0])')                . '</span>'],
                                ['$TERMINAL{expect}(<string>[, <seconds>])'        , '<span foreground="red">'            . __('$TERMINAL{expect}(<string>[, <seconds>])')        . '</span>']
                        );

                    # PAC Script Help

                    my $tablbl2 = Gtk3::HBox->new(0, 0);
                    $tablbl2->pack_start(Gtk3::Label->new(' Ásbrú Script Help '), 1, 1, 0);
                    $tablbl2->pack_start(Gtk3::Image->new_from_stock('gtk-help', 'menu'), 0, 1, 0);
                    $tablbl2->show_all;

                    $$self{_WINDOWSCRIPTS}{gui}{vboxhelp} = Gtk3::VBox->new(0, 0);
                    $$self{_WINDOWSCRIPTS}{nb}->append_page($$self{_WINDOWSCRIPTS}{gui}{vboxhelp}, $tablbl2);
                    $$self{_WINDOWSCRIPTS}{nb}->set_tab_reorderable($$self{_WINDOWSCRIPTS}{gui}{vboxhelp}, 0);
                    $$self{_WINDOWSCRIPTS}{nb}->set_tab_detachable($$self{_WINDOWSCRIPTS}{gui}{vboxhelp}, 0);

                        $$self{_WINDOWSCRIPTS}{gui}{scrollHelp} = Gtk3::ScrolledWindow->new;
                        $$self{_WINDOWSCRIPTS}{gui}{vboxhelp}->pack_start($$self{_WINDOWSCRIPTS}{gui}{scrollHelp}, 1, 1, 0);
                        $$self{_WINDOWSCRIPTS}{gui}{scrollHelp}->set_policy('automatic', 'automatic');
                        $$self{_WINDOWSCRIPTS}{gui}{scrollHelp}->set_border_width(5);

                            if ($SOURCEVIEW) {
                                $$self{_WINDOWSCRIPTS}{helpBuffer} = Gtk3::SourceView2::Buffer->new(undef);
                                $$self{_WINDOWSCRIPTS}{gui}{helpScript} = Gtk3::SourceView2::View->new_with_buffer($$self{_WINDOWSCRIPTS}{helpBuffer});
                                $$self{_WINDOWSCRIPTS}{gui}{helpScript} ->set_show_line_numbers(0);
                                $$self{_WINDOWSCRIPTS}{gui}{helpScript} ->set_tab_width(4);
                                $$self{_WINDOWSCRIPTS}{gui}{helpScript} ->set_indent_on_tab(1);
                                $$self{_WINDOWSCRIPTS}{gui}{helpScript} ->set_highlight_current_line(1);
                                $$self{_WINDOWSCRIPTS}{gui}{helpScript}->modify_font(Pango::FontDescription::from_string('monospace') );

                                $$self{_WINDOWSCRIPTS}{helpBuffer}->begin_not_undoable_action;
                                $$self{_WINDOWSCRIPTS}{helpBuffer}->set_text($PAC_SCRIPTS_HELP);
                                $$self{_WINDOWSCRIPTS}{helpBuffer}->end_not_undoable_action;
                                $$self{_WINDOWSCRIPTS}{helpBuffer}->place_cursor($$self{_WINDOWSCRIPTS}{helpBuffer}->get_start_iter);

                                my $manager = Gtk3::SourceView2::LanguageManager->get_default;
                                my $language = $manager->get_language('perl');
                                $$self{_WINDOWSCRIPTS}{helpBuffer}->set_language($language);
                            } else {
                                $$self{_WINDOWSCRIPTS}{helpBuffer} = Gtk3::TextBuffer->new;
                                $$self{_WINDOWSCRIPTS}{gui}{helpScript} = Gtk3::TextView->new_with_buffer($$self{_WINDOWSCRIPTS}{helpBuffer});
                                $$self{_WINDOWSCRIPTS}{helpBuffer}->set_text($PAC_SCRIPTS_HELP);
                                $$self{_WINDOWSCRIPTS}{helpBuffer}->place_cursor($$self{_WINDOWSCRIPTS}{helpBuffer}->get_start_iter);
                            }

                            $$self{_WINDOWSCRIPTS}{gui}{helpScript}->set_border_width(5);
                            $$self{_WINDOWSCRIPTS}{gui}{scrollHelp}->add($$self{_WINDOWSCRIPTS}{gui}{helpScript});
                            $$self{_WINDOWSCRIPTS}{gui}{helpScript}->set_wrap_mode('GTK_WRAP_WORD');
                            $$self{_WINDOWSCRIPTS}{gui}{helpScript}->set_editable(0);
                            $$self{_WINDOWSCRIPTS}{gui}{helpScript}->set('can_focus', 1);

            # Set notebook properties
            $$self{_WINDOWSCRIPTS}{nb}->set_scrollable(1);
            $$self{_WINDOWSCRIPTS}{nb}->set_tab_pos('top');
# FIXME-HOMOGENEOUS            $$self{_WINDOWSCRIPTS}{nb}->set('homogeneous', 1);
            $$self{_WINDOWSCRIPTS}{nb}->set_current_page(0);

            # Action buttons
            $$self{_WINDOWSCRIPTS}{gui}{btnbox} = Gtk3::HBox->new(0, 0);
            $$self{_WINDOWSCRIPTS}{gui}{vbox}->pack_start($$self{_WINDOWSCRIPTS}{gui}{btnbox}, 0, 1, 0);

                # Put a 'execute' button
                $$self{_WINDOWSCRIPTS}{gui}{btnexec} = Gtk3::Button->new('E_xecute');
                $$self{_WINDOWSCRIPTS}{gui}{btnexec}->set_image(Gtk3::Image->new_from_stock('gtk-media-play', 'button') );
                $$self{_WINDOWSCRIPTS}{gui}{btnexec}->set('can_focus', 0);
                $$self{_WINDOWSCRIPTS}{gui}{btnbox}->pack_start($$self{_WINDOWSCRIPTS}{gui}{btnexec}, 1, 1, 0);

                # Put a 'add' button
                $$self{_WINDOWSCRIPTS}{gui}{btnadd} = Gtk3::Button->new_from_stock('gtk-new');
                $$self{_WINDOWSCRIPTS}{gui}{btnadd}->set('can_focus', 0);
                $$self{_WINDOWSCRIPTS}{gui}{btnbox}->pack_start($$self{_WINDOWSCRIPTS}{gui}{btnadd}, 1, 1, 0);

                # Put a 'import' button
                $$self{_WINDOWSCRIPTS}{gui}{btnimport} = Gtk3::Button->new('Import...');
                $$self{_WINDOWSCRIPTS}{gui}{btnimport}->set('can_focus', 0);
                $$self{_WINDOWSCRIPTS}{gui}{btnimport}->set_image(Gtk3::Image->new_from_stock('gtk-open', 'button') );
                $$self{_WINDOWSCRIPTS}{gui}{btnbox}->pack_start($$self{_WINDOWSCRIPTS}{gui}{btnimport}, 1, 1, 0);

                # Put a 'remove' button
                $$self{_WINDOWSCRIPTS}{gui}{btnremove} = Gtk3::Button->new_from_stock('gtk-delete');
                $$self{_WINDOWSCRIPTS}{gui}{btnremove}->set('can_focus', 0);
                $$self{_WINDOWSCRIPTS}{gui}{btnbox}->pack_start($$self{_WINDOWSCRIPTS}{gui}{btnremove}, 1, 1, 0);

                # Put a 'reload' button
                $$self{_WINDOWSCRIPTS}{gui}{btnreload} = Gtk3::Button->new_from_stock('gtk-refresh');
                $$self{_WINDOWSCRIPTS}{gui}{btnreload}->set('can_focus', 0);
                $$self{_WINDOWSCRIPTS}{gui}{btnbox}->pack_start($$self{_WINDOWSCRIPTS}{gui}{btnreload}, 1, 1, 0);

                # Put a 'save' button
                $$self{_WINDOWSCRIPTS}{gui}{btnsave} = Gtk3::Button->new_from_stock('gtk-save');
                $$self{_WINDOWSCRIPTS}{gui}{btnsave}->set('can_focus', 0);
                $$self{_WINDOWSCRIPTS}{gui}{btnbox}->pack_start($$self{_WINDOWSCRIPTS}{gui}{btnsave}, 1, 1, 0);

                # Put a 'close' button
                $$self{_WINDOWSCRIPTS}{gui}{btnclose} = Gtk3::Button->new_from_stock('gtk-close');
                $$self{_WINDOWSCRIPTS}{gui}{btnclose}->set('can_focus', 0);
                $$self{_WINDOWSCRIPTS}{gui}{btnbox}->pack_start($$self{_WINDOWSCRIPTS}{gui}{btnclose}, 1, 1, 0);

    $$self{_WINDOWSCRIPTS}{gui}{hpane}->set_position(100);
    $$self{_WINDOWSCRIPTS}{gui}{hpanededitfunc}->set_position(600);

    return 1;
}

sub _setupCallbacks {
    my $self = shift;

    # Asign a callback to populate this textview with its own context menu
    $$self{_WINDOWSCRIPTS}{gui}{textScript}->signal_connect('button_press_event' => sub {
        my ($widget, $event) = @_;

        return 0 unless $event->button eq 3;

        my @menu_items;

        # COMMON
        my @comm_menu_items;
        push(@comm_menu_items,
        {
            label => 'Del ESCape sequences ($COMMON{del_esc}(<text>) )',
            tooltip => "Remove ESCape sequences (mainly used for removing ANSI colouring output)",
            code => sub {$$self{_WINDOWSCRIPTS}{multiTextBuffer}->insert_at_cursor("\$COMMON{del_esc}(<text>) ");}
        });

        push(@comm_menu_items,
        {
            label => 'Var substitution ($COMMON{subst}(<text>) )',
            tooltip => "Substitute given text with internal variables (<ASK:a>, <GV:2>, ...)",
            code => sub {$$self{_WINDOWSCRIPTS}{multiTextBuffer}->insert_at_cursor("\$COMMON{subst}(<text>) ");}
        });

        push(@comm_menu_items,
        {
            label => 'Get Ásbrú Config ($COMMON{cfg}([0|1]) )',
            tooltip => "Retrieve a copy (0->default) or a reference (1) to *whole* PAC's configuration
*ATTENTION* Retrieving a REFERENCE (1) to PAC's config may lead to Ásbrú misconfiguration!!
NOT RECOMMENDED!! USE AT YOUR VERY OWN RISK!!!!!!",
            code => sub {$$self{_WINDOWSCRIPTS}{multiTextBuffer}->insert_at_cursor("\$COMMON{cfg}([0|1]) ");}
        });

        push(@comm_menu_items,
        {
            label => 'Run Config sanity check($COMMON{sanity}(\%cfg) )',
            tooltip => "Perform a sanity check for given %cfg, which may be empty, in which case it will",
            code => sub {$$self{_WINDOWSCRIPTS}{multiTextBuffer}->insert_at_cursor("\$COMMON{sanity}(\%sanity]) ");}
        });

        push(@menu_items,
        {
            label => 'COMMON methods',
            stockicon => 'asbru-script',
            submenu => \@comm_menu_items
        });

        # SESSION
        my @session_menu_items;
        push(@session_menu_items,
        {
            label => 'Start session with "UUID"($PAC{start_uuid}(<UUID>[, <cluster>]) )',
            tooltip => "Start session with 'UUID' (optionally in cluster 'cluster')",
            code => sub {$$self{_WINDOWSCRIPTS}{multiTextBuffer}->insert_at_cursor("\$PAC{start_uuid}(<UUID>[, <cluster>])");}
        });

        push(@session_menu_items,
        {
            label => 'Start session "UUID" with manual login(""PAC{start_uuid_manual}(<UUID>) )',
            tooltip => "Start session with 'UUID' with manual login (you must write your login code under CONNECTION)",
            code => sub {$$self{_WINDOWSCRIPTS}{multiTextBuffer}->insert_at_cursor("\$PAC{start_uuid_manual}(<UUID>)");}
        });

        push(@session_menu_items,
        {
            label => 'Start session named "name"($PAC{start}(<name>[, <cluster>]) )',
            tooltip => "Start session named 'name' (optionally in cluster 'cluster')",
            code => sub {$$self{_WINDOWSCRIPTS}{multiTextBuffer}->insert_at_cursor("\$PAC{start}(<name>[, <cluster>])");}
        });

        push(@session_menu_items,
        {
            label => 'Start session "name" with manual login(""PAC{start_manual}(<name>) )',
            tooltip => "Start session named 'name' with manual login (you must write your login code under CONNECTION)",
            code => sub {$$self{_WINDOWSCRIPTS}{multiTextBuffer}->insert_at_cursor("\$PAC{start_manual}(<name>)");}
        });

        push(@session_menu_items,
        {
            label => 'Select existing session "name"($PAC{select}(<name>) )',
            tooltip => "Select an existing session named 'name', returning (uuid, \$tmp_uuid) (array)",
            code => sub {$$self{_WINDOWSCRIPTS}{multiTextBuffer}->insert_at_cursor("\$PAC{select}(<name>)");}
        });

        push(@session_menu_items,
        {
            label => "Select ALL open sessions(\$PAC{select}('*ALL*') )",
            tooltip => "Select ALL open sessions, return (hash ref) the whole list {tmp_uuid => uuid}",
            code => sub {$$self{_WINDOWSCRIPTS}{multiTextBuffer}->insert_at_cursor("\$PAC{select}('*ALL*')");}
        });

        push(@session_menu_items,
        {
            label => 'Stop session $tmp_uuid($PAC{stop}(<$tmp_uuid>) )',
            tooltip => 'Stop and close session identified by $tmp_uuid',
            code => sub {$$self{_WINDOWSCRIPTS}{multiTextBuffer}->insert_at_cursor("\$PAC{stop}(<\$tmp_uuid>)");}
        });

        push(@session_menu_items,
        {
            label => 'Show/hide a message($PAC{msg}([<message text>[, 0|1]]) )',
            tooltip => "Show/hide a message window with an OK (1) or not (0 - default) button",
            code => sub {$$self{_WINDOWSCRIPTS}{multiTextBuffer}->insert_at_cursor("\$PAC{msg}([<message text>[, 0|1]])");}
        });

        push(@session_menu_items,
        {
            label => 'Split connections($PAC{split}(<$tmp_uuid1>, <$tmp_uuid2>[, 0|1]) )',
            tooltip => "Split horizontally (0->default) or vertically (1) given connections",
            code => sub {$$self{_WINDOWSCRIPTS}{multiTextBuffer}->insert_at_cursor("\$PAC{split}(<\$tmp_uuid1>, <\$tmp_uuid2>[, 0|1])");}
        });

        push(@session_menu_items,
        {
            label => 'Unsplit($PAC{unsplit}(<$tmp_uuid>) )',
            tooltip => "Unsplit given connection",
            code => sub {$$self{_WINDOWSCRIPTS}{multiTextBuffer}->insert_at_cursor("\$PAC{unsplit}(<\$tmp_uuid>)");}
        });

        push(@session_menu_items,
        {
            label => 'Untab($PAC{to_window}(<$tmp_uuid>) )',
            tooltip => "Untab given connection",
            code => sub {$$self{_WINDOWSCRIPTS}{multiTextBuffer}->insert_at_cursor("\$PAC{to_window}(<\$tmp_uuid>)");}
        });

        push(@session_menu_items,
        {
            label => 'Retab($PAC{to_tab}(<$tmp_uuid>) )',
            tooltip => "Retab given connection",
            code => sub {$$self{_WINDOWSCRIPTS}{multiTextBuffer}->insert_at_cursor("\$PAC{to_tab}(<\$tmp_uuid>)");}
        });

        push(@session_menu_items,
        {
            label => 'Save current Ásbrú CFG($PAC{cfg_save}())',
            tooltip => "Save current Ásbrú cfg to standard Ásbrú config file",
            code => sub {$$self{_WINDOWSCRIPTS}{multiTextBuffer}->insert_at_cursor("\$PAC{cfg_save}()");}
        });

        push(@session_menu_items,
        {
            label => 'Export Ásbrú CFG to file($PAC{cfg_export}([file]) )',
            tooltip => "Save current Ásbrú cfg to given file (or ask for a file through a GUI if no file provided)",
            code => sub {$$self{_WINDOWSCRIPTS}{multiTextBuffer}->insert_at_cursor("\$PAC{cfg_export}([file])");}
        });

        push(@menu_items,
        {
            label => 'Ásbrú methods',
            stockicon => 'asbru-tab',
            submenu => \@session_menu_items
        });

        # CONNECTION
        my @connection_menu_items;
        push(@connection_menu_items,
        {
            label => 'Set output log file($TERMINAL{log}([<log file>]) )',
            tooltip => 'Function to set/remove output log file. Returns the log filehandle applied',
            code => sub {$$self{_WINDOWSCRIPTS}{multiTextBuffer}->insert_at_cursor("\$TERMINAL{log}([<log file>])");}
        });

        push(@connection_menu_items,
        {
            label => 'User input($TERMINAL{ask}(<text>[, 0|1]) )',
            tooltip => 'Ask user for input, showing (1->default) or not (0)  user input',
            code => sub {$$self{_WINDOWSCRIPTS}{multiTextBuffer}->insert_at_cursor("\$TERMINAL{ask}(<text>[, 0|1])");}
        });

        push(@connection_menu_items,
        {
            label => 'Get EXPecxt object($TERMINAL{exp}())',
            tooltip => 'Returns the Perl Expect object for this connection (*WARNING*, dangerous function! Not recommended!)',
            code => sub {$$self{_WINDOWSCRIPTS}{multiTextBuffer}->insert_at_cursor("\$TERMINAL{exp}()");}
        });

        push(@connection_menu_items,
        {
            label => 'Connection name($TERMINAL{name})',
            tooltip => 'Variable with the Name of the connection',
            code => sub {$$self{_WINDOWSCRIPTS}{multiTextBuffer}->insert_at_cursor("\$TERMINAL{name}");}
        });

        push(@connection_menu_items,
        {
            label => 'Connection UUID($TERMINAL{uuid})',
            tooltip => 'Variable with the UUID of the connection',
            code => sub {$$self{_WINDOWSCRIPTS}{multiTextBuffer}->insert_at_cursor("\$TERMINAL{uuid}");}
        });

        push(@connection_menu_items,
        {
            label => 'Connection TMP_UUID($TERMINAL{tmp_uuid})',
            tooltip => 'Variable with the Temporal UUID of current executing connection',
            code => sub {$$self{_WINDOWSCRIPTS}{multiTextBuffer}->insert_at_cursor("\$TERMINAL{tmp_uuid}");}
        });

        push(@connection_menu_items,
        {
            label => 'Latest error($TERMINAL{error})',
            tooltip => 'Variable with the latest error from the "expect" function',
            code => sub {$$self{_WINDOWSCRIPTS}{multiTextBuffer}->insert_at_cursor("\$TERMINAL{error}");}
        });

        push(@connection_menu_items,
        {
            label => 'Print MSG on terminal($TERMINAL{msg}(<message>) )',
            tooltip => 'Function to print a message on the Terminal',
            code => sub {$$self{_WINDOWSCRIPTS}{multiTextBuffer}->insert_at_cursor("\$TERMINAL{msg}(<message>)");}
        });

        push(@connection_menu_items,
        {
            label => 'Guess connection prompt($TERMINAL{get_prompt}([0|1]) )',
            tooltip => 'Function retrieve connection prompt and remove (1) or not (0->default) any ESCape sequence. Returns a Quoted string \Qprompt_sting\E valid for RegExp matching',
            code => sub {$$self{_WINDOWSCRIPTS}{multiTextBuffer}->insert_at_cursor("\$TERMINAL{get_prompt}([0|1])");}
        });

        push(@connection_menu_items,
        {
            label => 'Send input to terminal($TERMINAL{send}(<string[\n]>) )',
            tooltip => 'Function to SEND some string (input) to the connection (\n sends a <INTRO>)',
            code => sub {$$self{_WINDOWSCRIPTS}{multiTextBuffer}->insert_at_cursor("\$TERMINAL{send}(<string[\n]>)");}
        });

        push(@connection_menu_items,
        {
            label => 'Send input to terminal($TERMINAL{send_get}(<string>[, 0]) )',
            tooltip => 'Function to SEND some string (input) to the connection (\n is automatically appended)',
            code => sub {$$self{_WINDOWSCRIPTS}{multiTextBuffer}->insert_at_cursor("\$TERMINAL{send_get}(<string>[, 0])");}
        });

        push(@connection_menu_items,
        {
            label => 'Send input to terminal($TERMINAL{expect}(<string>[, <seconds>]) )',
            tooltip => 'Function to EXPECT for some STRING from the connection for given SECONDS, or indefinetly if undefined
Returns, TRUE (1) on STRING found or FALSE (0) otherwise, setting the $TERMINAL{error} variable with
the error that produced the EXPECT not matching given STRING.
If STRINGS matches, then other two variables are set:
$TERMINAL{out1}->contains the output of the latest string SENT UP TO the matched STRING
$TERMINAL{out2}->contains the output of the latest string SENT FROM the matched STRING onwards
All $CONNECTIONS{error|out1|out2} are resetted every time a SEND command is executed',
            code => sub {$$self{_WINDOWSCRIPTS}{multiTextBuffer}->insert_at_cursor("\$TERMINAL{expect}(<string>[, <seconds>])");}
        });

        push(@menu_items,
        {
            label => 'TERMINAL methods',
            stockicon => 'asbru-shell',
            submenu => \@connection_menu_items
        });

        push(@menu_items, {separator => 1});

        # Populate with global defined variables
        my @global_variables_menu;
        foreach my $var (sort {$a cmp $b} keys %{$PACMain::FUNCS{_MAIN}{_CFG}{'defaults'}{'global variables'}})
        {
            my $val = $PACMain::FUNCS{_MAIN}{_CFG}{'defaults'}{'global variables'}{$var}{'value'};
            push(@global_variables_menu,
            {
                label => "<GV:$var> ($val)",
                code => sub {$$self{_WINDOWSCRIPTS}{multiTextBuffer}->insert_at_cursor("\$COMMON{subst}('<GV:$var>')");}
            });
        }
        push(@menu_items,
        {
            label => 'Global variables...',
            sensitive => scalar(@global_variables_menu),
            submenu => \@global_variables_menu
        });

        # Populate with environment variables
        my @environment_menu;
        foreach my $key (sort {$a cmp $b} keys %ENV)
        {
            # Do not offer Master Password, or any other environment variable with word PRIVATE, TOKEN
            if ($key =~ /KPXC|PRIVATE|TOKEN/i) {
                next;
            }
            my $value = $ENV{$key};
            push(@environment_menu,
            {
                label => "<ENV:$key>",
                tooltip => "$key=$value",
                code => sub {$$self{_WINDOWSCRIPTS}{multiTextBuffer}->insert_at_cursor("\$COMMON{subst}('<ENV:$key>')");}
            });
        }
        push(@menu_items,
        {
            label => 'Environment variables...',
            submenu => \@environment_menu
        });

        # Put an option to ask user for variable substitution
        push(@menu_items,
        {
            label => 'Runtime substitution (<ASK:change_by_number>)',
            code => sub {$$self{_WINDOWSCRIPTS}{multiTextBuffer}->insert_at_cursor("\$COMMON{subst}('<ASK:change_by_number>')");}
        });

        # Populate with <ASK:*|> special string
        push(@menu_items,
        {
            label => 'Interactive user choose from list',
            tooltip => 'User will be prompted to choose a value form a user defined list separated with "|" (pipes)',
            code => sub {$$self{_WINDOWSCRIPTS}{multiTextBuffer}->insert_at_cursor("\$COMMON{subst}('<ASK:descriptive_line|opt1|opt2|...|optN>')");}
        });

        # Populate with <CMD:*> special string
        push(@menu_items,
        {
            label => 'Use a command output as value',
            tooltip => 'The given command line will be locally executed, and its output (both STDOUT and STDERR) will be used to replace this value',
            code => sub {$$self{_WINDOWSCRIPTS}{multiTextBuffer}->insert_at_cursor("\$SUBST('<CMD:command_to_launch>')");}
        });

        _wPopUpMenu(\@menu_items, $event);

        return 1;
    });

    # Capture <ctrl><z> for undo
    $$self{_WINDOWSCRIPTS}{gui}{textScript}->signal_connect('key_press_event' => sub {
        my ($widget, $event) = @_;

        my $keyval = Gtk3::Gdk::keyval_name($event->keyval);
        my $unicode = Gtk3::Gdk::keyval_to_unicode($event->keyval); # 0 if not a character
        my $state = $event->get_state;
        my $ctrl = $state * ['control-mask'];
        my $shift = $state * ['shift-mask'];
        my $alt = $state * ['mod1-mask'];

        # Ctr-Enter
        if ($ctrl && (($keyval eq 'Return') || ($keyval eq 'KP_Enter') )) {
            $$self{_WINDOWSCRIPTS}{gui}{btnAll}->clicked;
        }
        # Ctrl-y
        elsif ($ctrl && (lc $keyval eq 'y') && $SOURCEVIEW) {
            $$self{_WINDOWSCRIPTS}{multiTextBuffer}->redo if $$self{_WINDOWSCRIPTS}{multiTextBuffer}->can_redo;
        }
        # Ctrl-z
        elsif ($ctrl && (lc $keyval eq 'z') && ! $SOURCEVIEW && (scalar @{$$self{_UNDO}}) ) {
            $$self{_WINDOWSCRIPTS}{multiTextBuffer}->set_text(pop(@{$$self{_UNDO}}));
            $$self{_WINDOWSCRIPTS}{multiTextBuffer}->set_modified(scalar(@{$$self{_UNDO}}) );
        }
        else {return  0;}

        return 1;
    });

    # Capture text changes on multitext widget
    ! $SOURCEVIEW && $$self{_WINDOWSCRIPTS}{multiTextBuffer}->signal_connect('begin_user_action' => sub {
        push(@{$$self{_UNDO}}, $$self{_WINDOWSCRIPTS}{multiTextBuffer}->get_property('text') );
        $$self{_WINDOWSCRIPTS}{multiTextBuffer}->set_modified(1);
        return 0;
    });

    # Set a flag to check for syntax when text has changed
    $$self{_WINDOWSCRIPTS}{multiTextBuffer}->signal_connect('changed' => sub {$$self{_SYNTAX_CHANGED} = 1; $$self{_WINDOWSCRIPTS}{multiTextBuffer}->set_modified(1);});

    $$self{_WINDOWSCRIPTS}{treeScripts}->get_selection->signal_connect('changed' => sub {$self->_updateGUI; return 1;});
    $$self{_WINDOWSCRIPTS}{treeFuncs}->signal_connect('row_activated' => sub {

        return 1 unless (scalar(_getSelectedRows($$self{_WINDOWSCRIPTS}{treeScripts}->get_selection) ) && $$self{_WINDOWSCRIPTS}{gui}{textScript}->get_sensitive);

        my $selection = $$self{_WINDOWSCRIPTS}{treeFuncs}->get_selection;
        my $model = $$self{_WINDOWSCRIPTS}{treeFuncs}->get_model;

        my @sel = _getSelectedRows($selection);
        return 1 unless scalar @sel == 1;

        my $apicall = $model->get_value($model->get_iter($sel[0]), 0);

        $$self{_WINDOWSCRIPTS}{multiTextBuffer}->insert_at_cursor($apicall);

        return 1;
    });

    # Setup Drag 'n Drop
    my @targets = (Gtk3::TargetEntry->new('STRING', [], 0) );
    $$self{_WINDOWSCRIPTS}{treeScripts}->drag_dest_set('all', \@targets, ['copy', 'move']);
    $$self{_WINDOWSCRIPTS}{treeScripts}->signal_connect('drag_data_received' => sub {
        my ($me, $context, $x, $y, $data, $info, $time) = @_;

        return 0 if (($data->length < 0) || ($data->type->name ne 'STRING') );

        foreach my $line (split(/\R/, $data->data) ) {
            $line =~ s/\R//go;
            next unless $line =~ /file:\/\/(.+)/go;
            my $file = $1;

            my ($filename, $directories, $suffix) = fileparse ($file, '.pl');
            if ($suffix ne '.pl') {
                _wMessage($$self{_WINDOWSCRIPTS}{main}, "File '$file' does not end with a '.pl' Perl extension", 1);
                next;
            }
            next if -f "$SCRIPTS_DIR/$filename.pl" && ! _wConfirm($$self{_WINDOWSCRIPTS}{main}, "File '$filename.pl' already exists. Overwrite it?");

            $self->_import($file);
        }

        $self->_reloadDir;
        $self->_updateGUI;

        return 1;
    });

    $$self{_WINDOWSCRIPTS}{main}->signal_connect('key_press_event' => sub {
        my ($widget, $event) = @_;
        my $keyval = '' . ($event->keyval);
        return 0 unless $keyval == 65307;
        $$self{_WINDOWSCRIPTS}{gui}{btnclose}->activate;
        return 1;
    });
    $$self{_WINDOWSCRIPTS}{main}->signal_connect('delete_event' => sub {$$self{_WINDOWSCRIPTS}{gui}{btnclose}->activate; return 1;});
    $$self{_WINDOWSCRIPTS}{treeScripts}->signal_connect('row_activated' => sub {$$self{_WINDOWSCRIPTS}{gui}{btnexec}->activate;});
    $$self{_WINDOWSCRIPTS}{gui}{btnexec}->signal_connect('clicked' => sub {
        my $selection = $$self{_WINDOWSCRIPTS}{treeScripts}->get_selection;
        my $model = $$self{_WINDOWSCRIPTS}{treeScripts}->get_model;

        my @sel = _getSelectedRows($selection);
        return 1 unless scalar @sel == 1;

        my $name = $model->get_value($model->get_iter($sel[0]), 1);
        $self->_execScript($name,$$self{_WINDOWSCRIPTS}{main});

        return 1;
    });
    $$self{_WINDOWSCRIPTS}{gui}{btnadd}->signal_connect('clicked' => sub {
        my $name = _wEnterValue($$self{_WINDOWSCRIPTS}{main}, "<b>Creating new Script</b>"  , "Enter a name for the new Ásbrú Script");
        return 1 if ((! defined $name) || ($name =~ /^\s*$/go) );
        return 1 if -f "$SCRIPTS_DIR/$name.pl" && ! _wConfirm($$self{_WINDOWSCRIPTS}{main}, "File '$name.pl' already exists. Overwrite it?");

        if (! open(F,">:utf8","$SCRIPTS_DIR/$name.pl")) {
            _wMessage($$self{_WINDOWSCRIPTS}{main}, "ERROR: Can not open file '$name.pl' for writting ($!)");
            return 1;
        }

        print F $PAC_SCRIPTS_NEW;
        close F;

        $self->_reloadDir;
        $self->_selectFile($name . '.pl');

        return 1;
    });
    $$self{_WINDOWSCRIPTS}{gui}{btnimport}->signal_connect('clicked' => sub {
        my $choose = Gtk3::FileChooserDialog->new(
            "$APPNAME (v.$APPVERSION) Choose a text file to Import",
            $$self{_WINDOWSCRIPTS}{main},
            'GTK_FILE_CHOOSER_ACTION_OPEN',
            'Open' , 'GTK_RESPONSE_ACCEPT',
            'Cancel' , 'GTK_RESPONSE_CANCEL',
        );
        $choose->set_current_folder($ENV{'HOME'} // '/tmp');
        $choose->set_select_multiple(1);

        my $filter = Gtk3::FileFilter->new;
        $filter->set_name('Perl files (.pl)');
        $filter->add_pattern('*.pl');
        $choose->add_filter($filter);

        my $out = $choose->run;
        my @files = $choose->get_filenames;
        $choose->destroy;
        return 1 unless $out eq 'accept' && scalar(@files);

        foreach my $file (@files) {$self->_import($file);}

        $self->_reloadDir;
        $self->_updateGUI;

        return 1;
    });

    $$self{_WINDOWSCRIPTS}{gui}{btnreload}->signal_connect('clicked' => sub {$self->_reloadDir; return 1;});
    $$self{_WINDOWSCRIPTS}{gui}{btnclose}->signal_connect('clicked' => sub {
        if ($$self{_WINDOWSCRIPTS}{multiTextBuffer}->get_modified) {
            my $name = $$self{_WINDOWSCRIPTS}{treeScripts}->get_model->get_value($$self{_WINDOWSCRIPTS}{treeScripts}->get_model->get_iter($$self{_SELECTED}), 0);
            my $out = _wYesNoCancel($$self{_WINDOWSCRIPTS}{main}, "Ásbrú Script '$name' has changed.\nSave data before closing Ásbrú Script window?");
            $out eq 'yes' and $self->_saveFile($$self{_SELECTED});
            $out eq 'cancel' and return 1;
            $out eq 'no' and $self->_loadFile($$self{_SELECTED});
        }
        $$self{_WINDOWSCRIPTS}{main}->hide;
        Glib::Source->remove($$self{_TIMER_CHECK}) if defined $$self{_TIMER_CHECK};
        $$self{_TIMER_CHECK} = undef;
        return 1;
    });
    $$self{_WINDOWSCRIPTS}{gui}{btnremove}->signal_connect('clicked' => sub {
        my $selection = $$self{_WINDOWSCRIPTS}{treeScripts}->get_selection;
        my $model = $$self{_WINDOWSCRIPTS}{treeScripts}->get_model;

        # Check for changes before removing
        if ($$self{_WINDOWSCRIPTS}{multiTextBuffer}->get_modified) {
            my $name = $model->get_value($model->get_iter($$self{_SELECTED}), 0);
            $self->_saveFile($$self{_SELECTED}) if _wConfirm($$self{_WINDOWSCRIPTS}{main}, "Ásbrú Script '$name' has changed.\nSave data before loading another script?");
        }

        my @sel = _getSelectedRows($selection);
        return 1 unless scalar(@sel);
        return 1 unless _wConfirm($$self{_WINDOWSCRIPTS}{main}, "Are you sure you want to remove ". (scalar(@sel) ) . " Ásbrú Scripts?");

        # Delete selected files
        foreach my $path (@sel) {
            my ($file, $name) = $model->get_value($model->get_iter($path) );
            unlink($file);
        }

        $$self{_SELECTED} = '';
        $self->_reloadDir;
        $self->_updateGUI;

        return 1;
    });

    $$self{_WINDOWSCRIPTS}{gui}{btnsave}->signal_connect('clicked' => sub {
        my ($path) = _getSelectedRows($$self{_WINDOWSCRIPTS}{treeScripts}->get_selection);
        defined $path or return 1;
        my $file = $$self{_WINDOWSCRIPTS}{treeScripts}->get_model->get_value($$self{_WINDOWSCRIPTS}{treeScripts}->get_model->get_iter($path), 0);

        $self->_saveFile($path);

        return 1;
    });

    return 1;
}

sub _selectFile {
    my $self = shift;
    my $sel = shift;

    my $selection = $$self{_WINDOWSCRIPTS}{treeScripts}->get_selection;
    my $model = $$self{_WINDOWSCRIPTS}{treeScripts}->get_model;

    # Locate every connection under $uuid
    $model->foreach(sub {
        my ($store, $path, $iter, $tmp) = @_;
        my ($file, $name) = $store->get_value($iter);

        return 0 unless $name eq $sel;
        $selection->select_path($path);
        return 1;
    });

    return 1;
}

sub _saveFile {
    my $self = shift;
    my $path = shift;
    my $file = shift // $$self{_WINDOWSCRIPTS}{treeScripts}->get_model->get_value($$self{_WINDOWSCRIPTS}{treeScripts}->get_model->get_iter($path), 0);

    if (!open(F,">:utf8",$file)) {
        _wMessage($$self{_WINDOWSCRIPTS}{main}, "ERROR: Can not open for writting '$file' ($!)");
        return 0;
    }
    print F $$self{_WINDOWSCRIPTS}{multiTextBuffer}->get_text($$self{_WINDOWSCRIPTS}{multiTextBuffer}->get_start_iter, $$self{_WINDOWSCRIPTS}{multiTextBuffer}->get_end_iter, 0);
    close F;

    return 1;
}

sub _loadFile {
    my $self = shift;
    my $path = shift;

    my $selection = $$self{_WINDOWSCRIPTS}{treeScripts}->get_selection;
    my $model = $$self{_WINDOWSCRIPTS}{treeScripts}->get_model;

    my $file = $model->get_value($model->get_iter($path), 0);
    my $name = $model->get_value($model->get_iter($path), 1);

    # Loading a file should not be undoable.
    my $content = '';
    if (!open(F,"<:utf8",$file)) {
        $$self{_WINDOWSCRIPTS}{gui}{btnremove}->clicked if _wConfirm($$self{_WINDOWSCRIPTS}{main}, "ERROR: Can not read file '$file' ($!)\nDelete it?");
        return 0;
    }
    while (my $line = <F>) {$content .= $line;}
    close F;

    if ($SOURCEVIEW) {
        $$self{_WINDOWSCRIPTS}{multiTextBuffer}->begin_not_undoable_action;
        $$self{_WINDOWSCRIPTS}{multiTextBuffer}->set_text($content);
        if ($$self{_WINDOWSCRIPTS}{multiTextBuffer}->get_text($$self{_WINDOWSCRIPTS}{multiTextBuffer}->get_start_iter, $$self{_WINDOWSCRIPTS}{multiTextBuffer}->get_end_iter, 0) eq '') {
            _wMessage($$self{_WINDOWSCRIPTS}{main}, "WARNING: file '$file' is " . (-z $file ? 'empty' : 'not a valid text file!') );
        }
        $$self{_WINDOWSCRIPTS}{multiTextBuffer}->end_not_undoable_action;
        $$self{_WINDOWSCRIPTS}{multiTextBuffer}->place_cursor($$self{_WINDOWSCRIPTS}{multiTextBuffer}->get_start_iter);

        my $manager = Gtk3::SourceView2::LanguageManager->get_default;
        my $language = $manager->guess_language($file);
        $$self{_WINDOWSCRIPTS}{multiTextBuffer}->set_language($language);
    } else {
        $$self{_WINDOWSCRIPTS}{multiTextBuffer}->set_text($content);
    }

    $$self{_WINDOWSCRIPTS}{multiTextBuffer}->set_modified(0);

    $$self{_SYNTAX_CHANGED} = 1;
    $$self{_WINDOWSCRIPTS}{nb}->set_current_page(0);
    return 1;
}

sub _import {
    my $self = shift;
    my $file = shift // '';

    return 0 unless -f $file;
    my ($filename, $directories, $suffix) = fileparse ($file, '.pl');
    return 0 unless $suffix eq '.pl';

    if (defined $$self{_SCRIPTS}{$filename})    {_wMessage($$self{_WINDOWSCRIPTS}{main}, "ERROR: It already exists a file named '$file' in '$SCRIPTS_DIR'");}
    elsif (! copy($file, $SCRIPTS_DIR) )        {_wMessage($$self{_WINDOWSCRIPTS}{main}, "ERROR: Could not import file '$file' into '$SCRIPTS_DIR' ($!)");}
    else                                        {return 1;}
    return 0;
}

sub _reloadDir {
    my $self = shift;

    # Check for changes before reloading
    if ($$self{_WINDOWSCRIPTS}{multiTextBuffer}->get_modified && $$self{_SELECTED}) {
        my $name = $$self{_WINDOWSCRIPTS}{treeScripts}->get_model->get_value($$self{_WINDOWSCRIPTS}{treeScripts}->get_model->get_iter($$self{_SELECTED}), 0);
        $self->_saveFile($$self{_SELECTED}) if _wConfirm($$self{_WINDOWSCRIPTS}{main}, "Ásbrú Script '$name' has changed.\nSave data before loading another script?");
    }

    my $dh;
    my @files;

    # Read file from the directory
    if (! opendir($dh, $SCRIPTS_DIR) ) {
        _wMessage($$self{_WINDOWSCRIPTS}{main}, "ERROR: Could not open directory '$SCRIPTS_DIR' for reading ($!)");
        return 0;
    }
    delete $$self{_SCRIPTS};
    while (my $f = readdir($dh) ) {
        my ($filename, $directories, $suffix) = fileparse ($SCRIPTS_DIR . '/' . $f, '.pl');
        next unless $suffix eq '.pl';
        $$self{_SCRIPTS}{$f} = $SCRIPTS_DIR . '/' . $f;
    }
    closedir $dh;

    # Delete and re-populate the scripts list
    $$self{_SELECTED} = '';
    $$self{_PREVENT_UPDATES} = 1;
    @{$$self{_WINDOWSCRIPTS}{treeScripts}{data}} = ();
    foreach my $name (sort {lc($a) cmp lc($b)} keys %{$$self{_SCRIPTS}}) {
        my $file = $SCRIPTS_DIR . '/' . $name;
        push(@{$$self{_WINDOWSCRIPTS}{treeScripts}{data}}, [$file, $name]);
    }
    $$self{_PREVENT_UPDATES} = 0;

    return 1;
}

sub _updateGUI {
    my $self = shift;

    return 1 if $$self{_PREVENT_UPDATES};

    my @sel = _getSelectedRows($$self{_WINDOWSCRIPTS}{treeScripts}->get_selection);

    my $default = "* Ásbrú Scripts *\n
- Take a look at Ásbrú example scripts to see how they work\n
- Now, 'Import' or create your own brand 'New' scripts, and 'Execute' them!\n
- You may also 'Import' scripts by Drag and Drop Perl '.pl' files to the scripts list on the left side of this window\n
- Remember: only one script can be executed at a time, and while executing, connection will be user-unresponsive (non-interactive)

Feel free to send me any Ásbrú Script you may find useful to the community!";

    if (! scalar(@sel) ) {
        if ($$self{_SELECTED} && $$self{_WINDOWSCRIPTS}{multiTextBuffer}->get_modified) {
            my $name = $$self{_WINDOWSCRIPTS}{treeScripts}->get_model->get_value($$self{_WINDOWSCRIPTS}{treeScripts}->get_model->get_iter($$self{_SELECTED}), 0);
            $self->_saveFile($$self{_SELECTED}) if _wConfirm($$self{_WINDOWSCRIPTS}{main}, "Ásbrú Script '$name' has changed.\nSave data before loading another script?");
        }

        $SOURCEVIEW and $$self{_WINDOWSCRIPTS}{multiTextBuffer}->begin_not_undoable_action;
        $$self{_WINDOWSCRIPTS}{multiTextBuffer}->set_text($default);
        $SOURCEVIEW and $$self{_WINDOWSCRIPTS}{multiTextBuffer}->end_not_undoable_action;

        $$self{_SELECTED} = '';
        $$self{_WINDOWSCRIPTS}{gui}{textScript}->set_sensitive(0);
        $$self{_WINDOWSCRIPTS}{gui}{btnadd}->set_sensitive(! $PACMain::FUNCS{_MAIN}{_READONLY});
        $$self{_WINDOWSCRIPTS}{gui}{btnimport}->set_sensitive(! $PACMain::FUNCS{_MAIN}{_READONLY});
        $$self{_WINDOWSCRIPTS}{gui}{btnreload}->set_sensitive(! $PACMain::FUNCS{_MAIN}{_READONLY});
        $$self{_WINDOWSCRIPTS}{gui}{btnclose}->set_sensitive(! $PACMain::FUNCS{_MAIN}{_READONLY});
        $$self{_WINDOWSCRIPTS}{gui}{btnremove}->set_sensitive(0);
        $$self{_WINDOWSCRIPTS}{gui}{btnsave}->set_sensitive(0);
        $$self{_SYNTAX_CHANGED} = 0;

        $$self{_WINDOWSCRIPTS}{gui}{status}->set_markup('');
        $$self{_WINDOWSCRIPTS}{gui}{status}->set_tooltip_text('');
    } elsif (scalar(@sel) == 1) {
        return 1 if ($$self{_SELECTED} && ($sel[0]->to_string eq $$self{_SELECTED}->to_string) );

        my $file = $$self{_WINDOWSCRIPTS}{treeScripts}->get_model->get_value($$self{_WINDOWSCRIPTS}{treeScripts}->get_model->get_iter($sel[0]), 0);
        my $name = $$self{_WINDOWSCRIPTS}{treeScripts}->get_model->get_value($$self{_WINDOWSCRIPTS}{treeScripts}->get_model->get_iter($sel[0]), 0);

        if ($$self{_WINDOWSCRIPTS}{multiTextBuffer}->get_modified && ($sel[0] ne $$self{_SELECTED}) ) {
            $self->_saveFile($$self{_SELECTED}) if _wConfirm($$self{_WINDOWSCRIPTS}{main}, "Ásbrú Script '$name' has changed.\nSave data before loading another script?");
        }
        $$self{_SELECTED} = $sel[0];
        $$self{_WINDOWSCRIPTS}{gui}{textScript}->set_sensitive(! $PACMain::FUNCS{_MAIN}{_READONLY});
        $$self{_WINDOWSCRIPTS}{gui}{btnadd}->set_sensitive(! $PACMain::FUNCS{_MAIN}{_READONLY});
        $$self{_WINDOWSCRIPTS}{gui}{btnimport}->set_sensitive(! $PACMain::FUNCS{_MAIN}{_READONLY});
        $$self{_WINDOWSCRIPTS}{gui}{btnreload}->set_sensitive(! $PACMain::FUNCS{_MAIN}{_READONLY});
        $$self{_WINDOWSCRIPTS}{gui}{btnclose}->set_sensitive(! $PACMain::FUNCS{_MAIN}{_READONLY});
        $$self{_WINDOWSCRIPTS}{gui}{btnremove}->set_sensitive(! $PACMain::FUNCS{_MAIN}{_READONLY});
        $$self{_WINDOWSCRIPTS}{gui}{btnsave}->set_sensitive(! $PACMain::FUNCS{_MAIN}{_READONLY});
        $self->_loadFile($sel[0]);
        $$self{_SYNTAX_CHANGED} = 1;
    } elsif (scalar(@sel) > 1) {
        if ($$self{_SELECTED} && $$self{_WINDOWSCRIPTS}{multiTextBuffer}->get_modified) {
            my $name = $$self{_WINDOWSCRIPTS}{treeScripts}->get_model->get_value($$self{_WINDOWSCRIPTS}{treeScripts}->get_model->get_iter($$self{_SELECTED}), 0);
            $self->_saveFile($$self{_SELECTED}) if _wConfirm($$self{_WINDOWSCRIPTS}{main}, "Ásbrú Script '$name' has changed.\nSave data before loading another script?");
        }

        $SOURCEVIEW and $$self{_WINDOWSCRIPTS}{multiTextBuffer}->begin_not_undoable_action;
        $$self{_WINDOWSCRIPTS}{multiTextBuffer}->set_text($default);
        $SOURCEVIEW and $$self{_WINDOWSCRIPTS}{multiTextBuffer}->end_not_undoable_action;

        $$self{_SELECTED} = '';
        $$self{_WINDOWSCRIPTS}{gui}{textScript}->set_sensitive(0);
        $$self{_WINDOWSCRIPTS}{gui}{btnadd}->set_sensitive(! $PACMain::FUNCS{_MAIN}{_READONLY});
        $$self{_WINDOWSCRIPTS}{gui}{btnimport}->set_sensitive(! $PACMain::FUNCS{_MAIN}{_READONLY});
        $$self{_WINDOWSCRIPTS}{gui}{btnreload}->set_sensitive(! $PACMain::FUNCS{_MAIN}{_READONLY});
        $$self{_WINDOWSCRIPTS}{gui}{btnclose}->set_sensitive(! $PACMain::FUNCS{_MAIN}{_READONLY});
        $$self{_WINDOWSCRIPTS}{gui}{btnremove}->set_sensitive(! $PACMain::FUNCS{_MAIN}{_READONLY});
        $$self{_WINDOWSCRIPTS}{gui}{btnsave}->set_sensitive(! $PACMain::FUNCS{_MAIN}{_READONLY});
        $$self{_SYNTAX_CHANGED} = 0;

        $$self{_WINDOWSCRIPTS}{gui}{status}->set_markup('');
        $$self{_WINDOWSCRIPTS}{gui}{status}->set_tooltip_text('');
    }

    $$self{_WINDOWSCRIPTS}{multiTextBuffer}->set_modified(0);

    return 1;
}

sub _execScript {
    my $self = shift;
    my $name = shift;
    my $parentWindow = shift;

    my @uuid_tmps = @_;

    return 1 unless defined $name;

    # %SESSION and %CONNECTION *MUST* be reset every time we are called!!
    our %COMMON;    undef %COMMON;
    our %PAC;        undef %PAC;
    our %TERMINAL;    undef %TERMINAL;
    our %SHARED;    undef %SHARED;

    $COMMON{subst} = sub {return _subst(shift // '', $PACMain::FUNCS{_MAIN}{_CFG});};
    $COMMON{cfg} = sub {my $ref = shift // 0; return $ref ? $PACMain::FUNCS{_MAIN}{_CFG} : dclone($PACMain::FUNCS{_MAIN}{_CFG});};
    $COMMON{cfg_sanity} = sub {_cfgSanityCheck(shift);};
    $COMMON{del_esc} = sub {return _removeEscapeSeqs(shift // '');};
    $PAC{cfg_save} = sub {return $PACMain::FUNCS{_MAIN}->_saveConfiguration(shift);};
    $PAC{cfg_export} = sub {return $PACMain::FUNCS{_MAIN}{_CONFIG}->_exporter('yaml', shift);};
    $PAC{to_window} = sub {
        my $uuid_tmp = shift;

        defined $uuid_tmp or return 0;
        $uuid_tmp = _subst($uuid_tmp, $PACMain::FUNCS{_MAIN}{_CFG});
        (! defined $PACMain::RUNNING{$uuid_tmp} || ! $PACMain::RUNNING{$uuid_tmp}{terminal}{_TABBED}) and return 0;
        $PACMain::RUNNING{$uuid_tmp}{terminal}->_tabToWin;
        return 1;
    };
    $PAC{to_tab} = sub {
        my $uuid_tmp = shift;

        defined $uuid_tmp or return 0;
        $uuid_tmp = _subst($uuid_tmp, $PACMain::FUNCS{_MAIN}{_CFG});
        (! defined $PACMain::RUNNING{$uuid_tmp} || $PACMain::RUNNING{$uuid_tmp}{terminal}{_TABBED}) and return 0;
        $PACMain::RUNNING{$uuid_tmp}{terminal}->_winToTab;
        return 1;
    };
    $PAC{split} = sub {
        my $uuid_tmp1 = shift;
        my $uuid_tmp2 = shift;
        my $vertical = shift // 1;

        defined $uuid_tmp1 or return 0;
        defined $uuid_tmp2 or return 0;

        $uuid_tmp1 = _subst($uuid_tmp1, $PACMain::FUNCS{_MAIN}{_CFG});
        $uuid_tmp2 = _subst($uuid_tmp2, $PACMain::FUNCS{_MAIN}{_CFG});

        (! defined $PACMain::RUNNING{$uuid_tmp1} || $PACMain::RUNNING{$uuid_tmp1}{terminal}{_SPLIT}) and return 0;
        (! defined $PACMain::RUNNING{$uuid_tmp2} || $PACMain::RUNNING{$uuid_tmp2}{terminal}{_SPLIT}) and return 0;

        $PACMain::RUNNING{$uuid_tmp1}{terminal}->_split($uuid_tmp2, $vertical);
        return 1;
    };
    $PAC{unsplit} = sub {
        my $uuid_tmp = shift;

        defined $uuid_tmp or return 0;
        $uuid_tmp = _subst($uuid_tmp, $PACMain::FUNCS{_MAIN}{_CFG});
        (! defined $PACMain::RUNNING{$uuid_tmp} || ! $PACMain::RUNNING{$uuid_tmp}{terminal}{_SPLIT}) and return 0;
        $PACMain::RUNNING{$uuid_tmp}{terminal}->_unsplit;
        return 1;
    };
    $PAC{start_uuid} = sub {
        my $uuid = shift;
        my $cluster = shift // '';

        defined $uuid or return 0;

        $cluster = _subst($cluster, $PACMain::FUNCS{_MAIN}{_CFG});

        my @idx;
        push(@idx, [$uuid, undef, $cluster]);
        my $terminals = $PACMain::FUNCS{_MAIN}->_launchTerminals(\@idx);

        $PAC{list}{$$terminals[0]{_UUID_TMP}} = $$terminals[0]{_UUID};

        return $$terminals[0]{_UUID}, $$terminals[0]{_UUID_TMP};
    };
    $PAC{start} = sub {
        my $name = shift;
        my $cluster = shift // '';

        defined $name or return 0;

        $name = _subst($name, $PACMain::FUNCS{_MAIN}{_CFG});
        $cluster = _subst($cluster, $PACMain::FUNCS{_MAIN}{_CFG});

        my $uuid = $self->_getUUID($name);
        defined $uuid or return 0;

        my @idx;
        push(@idx, [$uuid, undef, $cluster]);
        my $terminals = $PACMain::FUNCS{_MAIN}->_launchTerminals(\@idx);

        $PAC{list}{$$terminals[0]{_UUID_TMP}} = $$terminals[0]{_UUID};

        return $$terminals[0]{_UUID}, $$terminals[0]{_UUID_TMP};
    };
    $PAC{start_manual} = sub {
        my $name = shift;

        defined $name or return 0;

        $name = _subst($name, $PACMain::FUNCS{_MAIN}{_CFG});

        my $uuid = $self->_getUUID($name);
        defined $uuid or return 0;

        my @idx;
        push(@idx, [$uuid, undef, undef, 'manual']);
        my $terminals = $PACMain::FUNCS{_MAIN}->_launchTerminals(\@idx);

        $PAC{list}{$$terminals[0]{_UUID_TMP}} = $$terminals[0]{_UUID};

        return $$terminals[0]{_UUID}, $$terminals[0]{_UUID_TMP};
    };
    $PAC{start_uuid_manual} = sub {
        my $uuid = shift;

        defined $uuid or return 0;

        my @idx;
        push(@idx, [$uuid, undef, undef, 'manual']);
        my $terminals = $PACMain::FUNCS{_MAIN}->_launchTerminals(\@idx);

        $PAC{list}{$$terminals[0]{_UUID_TMP}} = $$terminals[0]{_UUID};

        return $$terminals[0]{_UUID}, $$terminals[0]{_UUID_TMP};
    };
    $PAC{stop} = sub {
        my $tmp_uuid = shift;

        defined $tmp_uuid or return 0;

        $tmp_uuid = _subst($tmp_uuid, $PACMain::FUNCS{_MAIN}{_CFG});

        defined $PACMain::RUNNING{$tmp_uuid} and $PACMain::RUNNING{$tmp_uuid}{terminal}->stop(1, 0);
        delete $PAC{list}{$tmp_uuid};

        return 1;
    };
    $PAC{select} = sub {
        my $name = shift;

        defined $name or return 0;

        if ($name eq '*ALL*') {
            map ($PAC{list}{$_} = $PACMain::RUNNING{$_}{uuid}, keys %PACMain::RUNNING);
            return $PAC{list};
        }

        $name = _subst($name, $PACMain::FUNCS{_MAIN}{_CFG});

        my $tmp_uuid = $self->_getTmpUUID($name);
        return 0 unless defined $tmp_uuid;

        my $uuid = $self->_getUUID($name);

        $PAC{list}{$tmp_uuid} = $uuid;

        return $uuid, $tmp_uuid;
    };
    $PAC{msg} = sub {
        my $msg = shift;
        my $modal = shift // 0;

        if ((defined $msg) && ($msg ne '') ) {
            $msg = _subst($msg, $PACMain::FUNCS{_MAIN}{_CFG});

            if (defined $PAC{_msg_wid}) {
                $PAC{_msg_wid}->destroy;
                delete $PAC{_msg_wid};
            }
            $PAC{_msg_wid} = _wMessage($parentWindow, __($msg), $modal);
        } else {
            $PAC{_msg_wid}->destroy if defined $PAC{_msg_wid};
            undef $PAC{_msg_wid};
        }
    };

    my $file = $$self{_SCRIPTS}{$name};

    defined &SESSION and undef &SESSION;
    if (! open(F,"<:utf8",$file)) {
        _wMessage($parentWindow, "Could not open Ásbrú Script file '$file' for reading: $!");
        return 1;
    }
    my @lines = <F>;
    my $txt = join('', @lines);
    close F;

    no warnings ('redefine');
    eval $txt;
    use warnings;
    if ($@) {_wMessage($parentWindow, "Error parsing Ásbrú Script: $@"); $PAC{msg}(); return 0;}

    # SESSION execution (local)
    if (scalar @uuid_tmps) {
        foreach my $uuid_tmp (@uuid_tmps) {
            next unless defined $PACMain::RUNNING{$uuid_tmp};
            $PAC{list}{$uuid_tmp} = $PACMain::RUNNING{$uuid_tmp}{uuid};
        }
    } else {
        if (! defined &SESSION) {
            _wMessage($parentWindow, "Error executing Ásbrú Script:\nNo 'SESSION' function declaration found, and script not being executed directly from any Terminal!");
            $PAC{msg}();
            return 0;
        } else {
            eval {&SESSION;};
            if ($@) {_wMessage($parentWindow, "Error executing Ásbrú Script: $@"); $PAC{msg}(); return 0;}
        }
    }

    # Save the list of started connections in $SHARED{_list_}
    $SHARED{_list_} = $PAC{list};

    # CONNECTION execution (asbru_conn)
    foreach my $tmp_uuid (keys %{$PAC{list}}) {
        next unless defined $PACMain::RUNNING{$tmp_uuid};
        if ($PACMain::RUNNING{$tmp_uuid}{terminal}{_SCRIPT_STATUS} ne 'STOP') {
            _wMessage($parentWindow, "ERROR: Can not start a new Ásbrú Script while another one is still running:\nTerminal '$PACMain::RUNNING{$tmp_uuid}{terminal}{_NAME}' is running '$PACMain::RUNNING{$tmp_uuid}{terminal}{_SCRIPT_NAME}'", 1) ;
            next;
        }

        Glib::Timeout->add(500, sub {
            # Skip if this tmp_uuid has disappeared (for any reason)
            return 0 unless defined $PACMain::RUNNING{$tmp_uuid};
            # Continue waiting if this tmp_uuid is still in "CONNECTING" state
            return 1 if $PACMain::RUNNING{$tmp_uuid}{terminal}{CONNECTING};
            # Skip if this tmp_uuid was not properly connected (for some reason)
            return 0 unless $PACMain::RUNNING{$tmp_uuid}{terminal}{CONNECTED};

            # Advise asbru_conn to receive script name
            kill(12, $PACMain::RUNNING{$tmp_uuid}{terminal}{_PID});
            my %tmp;
            $tmp{name} = $name;
            $tmp{script} = $txt;
            $tmp{shared} = \%SHARED;

            nstore_fd(\%tmp, $PACMain::RUNNING{$tmp_uuid}{terminal}{_SOCKET_CLIENT}) or die "ERROR:$!";

            # Stop
            return 0;
        });
    }

    return 1;
}

sub _getUUID {
    my $self = shift;
    my $name = shift;

    defined $name or return undef;

    my $cfg = $PACMain::FUNCS{_MAIN}{_CFG};

    my $uuid;
    foreach my $cuuid (keys %{$$cfg{'environments'}}) {
        next unless (($$cfg{'environments'}{$cuuid}{'name'} // '') eq $name);
        $uuid = $cuuid;
        last;
    }

    return $uuid;
}

sub _getTmpUUID {
    my $self = shift;
    my $name = shift;

    defined $name or return undef;

    my $tmp_uuid;
    foreach my $tuuid (keys %PACMain::RUNNING) {
        next unless defined $PACMain::RUNNING{$tuuid} && $PACMain::RUNNING{$tuuid}{terminal}{'_NAME'} eq $name;
        $tmp_uuid = $tuuid;
        last;
    }

    return $tmp_uuid;
}

# END: Define PRIVATE CLASS functions
###################################################################

1;
