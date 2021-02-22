package PACPipe;

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
my $APPICON = "$RealBin/res/asbru-logo-64.png";

# END: Define GLOBAL CLASS variables
###################################################################

###################################################################
# START: Define PUBLIC CLASS methods

sub new {
    my $class = shift;
    my $self = {};

    $self->{_WINDOWPIPE} = undef;
    $self->{_EXECS} = {};

    # Build the GUI
    _initGUI($self) or return 0;

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

# Start GUI and launch connection
sub show {
    my $self = shift;
    my $uuid_tmp = shift;

    $$self{_WINDOWPIPE}{data}->show_all;
    $$self{_WINDOWPIPE}{data}->present;

    $self->_updateGUI;
    $$self{_WINDOWPIPE}{treeTerminals}->get_selection->select_all;

    return 1;
}

# END: Define PUBLIC CLASS methods
###################################################################

###################################################################
# START: Define PRIVATE CLASS functions

sub _initGUI {
    my $self = shift;

    # Create the 'windowFind' dialog window,
    $$self{_WINDOWPIPE}{data} = Gtk3::Window->new;

    # and setup some dialog properties.
    $$self{_WINDOWPIPE}{data}->set_title("$APPNAME : Pipe output");
    $$self{_WINDOWPIPE}{data}->set_position('center');
    $$self{_WINDOWPIPE}{data}->set_icon_from_file($APPICON);
    $$self{_WINDOWPIPE}{data}->set_default_size(640, 480);
    $$self{_WINDOWPIPE}{data}->set_resizable(1);
    #$$self{_WINDOWPIPE}{data}->set_modal(1);
    $$self{_WINDOWPIPE}{data}->maximize;

    $$self{_WINDOWPIPE}{gui}{vbox} = Gtk3::VBox->new(0, 0);
    $$self{_WINDOWPIPE}{data}->add($$self{_WINDOWPIPE}{gui}{vbox});

    # Create an hpane
    $$self{_WINDOWPIPE}{gui}{hpane} = Gtk3::HPaned->new;
    $$self{_WINDOWPIPE}{gui}{vbox}->pack_start($$self{_WINDOWPIPE}{gui}{hpane}, 1, 1, 0);

    $$self{_WINDOWPIPE}{gui}{frame1} = Gtk3::Frame->new;
    $$self{_WINDOWPIPE}{gui}{frame1}->set_size_request(200, 200);
    $$self{_WINDOWPIPE}{gui}{hpane}->pack1($$self{_WINDOWPIPE}{gui}{frame1}, 0, 0);
    (my $lbl1 = Gtk3::Label->new)->set_markup(' <b>Terminals:</b> ');
    $$self{_WINDOWPIPE}{gui}{frame1}->set_label_widget($lbl1);
    $$self{_WINDOWPIPE}{gui}{frame1}->set_border_width(5);

    # Terminals list
    $$self{_WINDOWPIPE}{gui}{scroll2} = Gtk3::ScrolledWindow->new;
    $$self{_WINDOWPIPE}{gui}{frame1}->add($$self{_WINDOWPIPE}{gui}{scroll2});
    $$self{_WINDOWPIPE}{gui}{scroll2}->set_policy('automatic', 'automatic');
    $$self{_WINDOWPIPE}{gui}{frame1}->set_border_width(5);

    $$self{_WINDOWPIPE}{treeTerminals} = Gtk3::SimpleList->new_from_treeview (
        Gtk3::TreeView->new,
        'UUID_TMP' => 'hidden',
        'NAME' => 'text',
        'TITLE' => 'text'
    );

    $$self{_WINDOWPIPE}{gui}{scroll2}->add($$self{_WINDOWPIPE}{treeTerminals});
    $$self{_WINDOWPIPE}{treeTerminals}->set_tooltip_text('List of Terminals where the locally PIPEd command was executed');
    $$self{_WINDOWPIPE}{treeTerminals}->set_headers_visible(1);
    $$self{_WINDOWPIPE}{treeTerminals}->get_selection->set_mode('GTK_SELECTION_MULTIPLE');
    my @col_terminals = $$self{_WINDOWPIPE}{treeTerminals}->get_columns;
    $col_terminals[0]->set_expand(0);
    $col_terminals[1]->set_expand(0);
    $col_terminals[1]->set_expand(0);

    # Create a vpane
    $$self{_WINDOWPIPE}{gui}{vpane} = Gtk3::VPaned->new;
    $$self{_WINDOWPIPE}{gui}{hpane}->pack2($$self{_WINDOWPIPE}{gui}{vpane}, 1, 0);

    # Create frame 2
    $$self{_WINDOWPIPE}{gui}{frame2} = Gtk3::Frame->new;
    $$self{_WINDOWPIPE}{gui}{vpane}->pack1($$self{_WINDOWPIPE}{gui}{frame2}, 1, 0);
    (my $lbl2 = Gtk3::Label->new)->set_markup(' <b>Expanded command:</b> ');
    $$self{_WINDOWPIPE}{gui}{frame2}->set_label_widget($lbl2);
    $$self{_WINDOWPIPE}{gui}{frame2}->set_border_width(5);

    $$self{_WINDOWPIPE}{gui}{scroll1} = Gtk3::ScrolledWindow->new;
    $$self{_WINDOWPIPE}{gui}{frame2}->add($$self{_WINDOWPIPE}{gui}{scroll1});
    $$self{_WINDOWPIPE}{gui}{scroll1}->set_policy('automatic', 'automatic');
    $$self{_WINDOWPIPE}{gui}{scroll1}->set_border_width(5);

    $$self{_WINDOWPIPE}{bufferCmd} = Gtk3::TextBuffer->new;
    $$self{_WINDOWPIPE}{gui}{text1} = Gtk3::TextView->new_with_buffer($$self{_WINDOWPIPE}{bufferCmd});

    $$self{_WINDOWPIPE}{gui}{text1}->set_editable(0);
    $$self{_WINDOWPIPE}{gui}{text1}->modify_font(Pango::FontDescription::from_string('monospace') );
    $$self{_WINDOWPIPE}{gui}{scroll1}->add($$self{_WINDOWPIPE}{gui}{text1});

    # Create frame 3
    $$self{_WINDOWPIPE}{gui}{frame3} = Gtk3::Frame->new;
    $$self{_WINDOWPIPE}{gui}{vpane}->pack2($$self{_WINDOWPIPE}{gui}{frame3}, 1, 0);
    (my $lbl3 = Gtk3::Label->new)->set_markup(' <b>Final output (locally piped):</b> ');
    $$self{_WINDOWPIPE}{gui}{frame3}->set_label_widget($lbl3);
    $$self{_WINDOWPIPE}{gui}{frame3}->set_border_width(5);

    $$self{_WINDOWPIPE}{gui}{scroll} = Gtk3::ScrolledWindow->new;
    $$self{_WINDOWPIPE}{gui}{frame3}->add($$self{_WINDOWPIPE}{gui}{scroll});
    $$self{_WINDOWPIPE}{gui}{scroll}->set_policy('automatic', 'automatic');
    $$self{_WINDOWPIPE}{gui}{scroll}->set_border_width(5);

    $$self{_WINDOWPIPE}{bufferOut} = Gtk3::TextBuffer->new;
    $$self{_WINDOWPIPE}{gui}{text} = Gtk3::TextView->new_with_buffer($$self{_WINDOWPIPE}{bufferOut});

    $$self{_WINDOWPIPE}{gui}{text}->set_editable(0);
    $$self{_WINDOWPIPE}{gui}{text}->modify_font(Pango::FontDescription::from_string('monospace') );
    $$self{_WINDOWPIPE}{gui}{scroll}->add($$self{_WINDOWPIPE}{gui}{text});

    $$self{_WINDOWPIPE}{gui}{btnbox} = Gtk3::HBox->new(0, 0);
    $$self{_WINDOWPIPE}{gui}{vbox}->pack_start($$self{_WINDOWPIPE}{gui}{btnbox}, 0, 1, 0);

    # Put a 'always on top' checkbutton
    $$self{_WINDOWPIPE}{gui}{cbaot} = Gtk3::CheckButton->new_with_label('Always On Top');
    $$self{_WINDOWPIPE}{gui}{btnbox}->pack_start($$self{_WINDOWPIPE}{gui}{cbaot}, 0, 1, 0);

    # Put a 'refresh' button
    $$self{_WINDOWPIPE}{gui}{btnrefresh} = Gtk3::Button->new_from_stock('gtk-refresh');
    $$self{_WINDOWPIPE}{gui}{btnbox}->pack_start($$self{_WINDOWPIPE}{gui}{btnrefresh}, 1, 1, 0);

    # Put a 'close' button
    $$self{_WINDOWPIPE}{gui}{btnclose} = Gtk3::Button->new_from_stock('gtk-close');
    $$self{_WINDOWPIPE}{gui}{btnbox}->pack_start($$self{_WINDOWPIPE}{gui}{btnclose}, 1, 1, 0);

    $$self{_WINDOWPIPE}{gui}{vpane}->set_position(($$self{_WINDOWPIPE}{data}->get_size) / 2);

    return 1;
}

sub _setupCallbacks {
    my $self = shift;

    $$self{_WINDOWPIPE}{data}->signal_connect('key_press_event' => sub {
        my ($widget, $event) = @_;
        my $keyval = '' . ($event->keyval);
        return 0 unless $keyval == 65307;
        $$self{_WINDOWPIPE}{gui}{btnclose}->activate;
        return 1;
    });

    $$self{_WINDOWPIPE}{treeTerminals}->get_selection->signal_connect('changed' => sub {
        # Populate both command an piped output text entries with data depending on selected terminals
        my $full_cmd = '';
        my $full_out = '';
        $$self{_WINDOWPIPE}{bufferCmd}->set_text('');
        $$self{_WINDOWPIPE}{bufferOut}->set_text('');

        my $model = $$self{_WINDOWPIPE}{treeTerminals}->get_model;
        foreach my $path (_getSelectedRows($$self{_WINDOWPIPE}{treeTerminals}->get_selection) ) {
            my $uuid_tmp = $model->get_value($model->get_iter($path), 0);
            my $t = $PACMain::RUNNING{$uuid_tmp}{'terminal'};
            my $name = $$t{_NAME};
            my $title = $$t{_TITLE};
            my $exec = $$t{_EXEC};
            next unless defined $$exec{FULL_CMD} and defined $$exec{RECEIVED};

            $full_cmd .= "=======================================================\n";
            $full_cmd .= "* CONNECTION: NAME '$name' TITLE '$title'\n";
            $full_cmd .= "------------------------------------------------------\n";
            $full_cmd .= "* ORIGINAL COMMAND:\n";
            $full_cmd .= $$exec{FULL_CMD} . "\n";
            $full_cmd .= "------------------------------------------------------\n";
            $full_cmd .= "* EXPANDED COMMAND:\n";
            $full_cmd .= $$exec{RECEIVED} . ' | ' . join(' | ', @{$$exec{PIPE}}) . "\n";
            $full_cmd .= "------------------------------------------------------\n" if defined $$exec{PROMPT};
            $full_cmd .= "* EXPECTED PROMPT: '$$exec{PROMPT}' \n" if defined $$exec{PROMPT};
            $full_cmd .= "=======================================================\n\n";

            $full_out .= "=======================================================\n";
            $full_out .= "* CONNECTION: NAME '$name' TITLE '$title' OUTPUT:\n";
            $full_out .= $$exec{OUT} // '';
            $full_out .= "=======================================================\n\n";
        }

        $$self{_WINDOWPIPE}{bufferCmd}->set_text(_removeEscapeSeqs($full_cmd));
        $$self{_WINDOWPIPE}{bufferOut}->set_text(_removeEscapeSeqs($full_out));

        return 1;
    });

    $$self{_WINDOWPIPE}{data}->signal_connect('delete_event' => sub {$$self{_WINDOWPIPE}{gui}{btnclose}->activate; return 1;});
    $$self{_WINDOWPIPE}{gui}{cbaot}->signal_connect('toggled' => sub {$$self{_WINDOWPIPE}{data}->set_keep_above($$self{_WINDOWPIPE}{gui}{cbaot}->get_active);});
    $$self{_WINDOWPIPE}{gui}{btnrefresh}->signal_connect('clicked' => sub {$self->_updateGUI; $$self{_WINDOWPIPE}{treeTerminals}->get_selection->select_all; return 1;});
    $$self{_WINDOWPIPE}{gui}{btnclose}->signal_connect('clicked' => sub {$$self{_WINDOWPIPE}{data}->hide; return 1;});

    return 1;
}

sub _updateGUI {
    my $self = shift;

    # Delete and re-populate the connections list
    @{$$self{_WINDOWPIPE}{treeTerminals}{data}} = ();
    foreach my $uuid_tmp (sort {lc($PACMain::RUNNING{$a}{terminal}{_NAME}) cmp lc($PACMain::RUNNING{$b}{terminal}{_NAME})} keys %PACMain::RUNNING) {
        push(@{$$self{_WINDOWPIPE}{treeTerminals}{data}}, [$uuid_tmp, $PACMain::RUNNING{$uuid_tmp}{terminal}{_NAME}, $PACMain::RUNNING{$uuid_tmp}{terminal}{_TITLE}]);
    }

    return 1;
}

# END: Define PRIVATE CLASS functions
###################################################################

1;
