package PACExecEntry;

###############################################################################
# This file is part of Ásbrú Connection Manager
#
# Copyright (C) 2017-2020 Ásbrú Connection Manager team (https://asbru-cm.net)
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

# GTK
use Gtk3 '-init';

# PAC modules
use PACUtils;

# END: Import Modules
###################################################################

###################################################################
# Define GLOBAL CLASS variables

# END: Define GLOBAL CLASS variables
###################################################################

###################################################################
# START: Public class methods

sub new {
    my $class = shift;

    my $self = {};

    $self->{cfg} = shift;
    $self->{variables} = shift;
    $self->{where} = shift;

    $self->{container} = undef;
    $self->{frame} = {};
    $self->{list} = [];

    _buildExecGUI($self);
    if (defined $$self{cfg}) {
        PACExecEntry::update($$self{cfg});
    }

    bless($self, $class);
    return $self;
}

sub update {
    my $self = shift;
    my $cfg = shift;
    my $variables = shift;
    my $where = shift;

    if (defined $cfg) {
        $$self{cfg} = $cfg;
    }
    if (defined $variables) {
        $$self{variables} = $variables;
    }
    if (defined $where) {
        $$self{where} = $where;
    }

    # Destroy previous widgets
    $$self{frame}{vbexec}->foreach(sub {
        $_[0]->destroy();}
    );

    # Empty parent widgets list
    $$self{list} = [];

    # Now, add configured widgets
    foreach my $hash (sort {lc($$a{description}) cmp lc($$b{description})} @{$$self{cfg}}) {
        _buildExec($self, $hash);
    }

    return 1;
}

sub get_cfg {
    my $self = shift;

    my @cfg;

    foreach my $w (@{$self->{list}}) {
        my %hash;
        $hash{txt} = $$w{txt}->get_chars(0, -1);
        $hash{description} = $$w{desc}->get_chars(0, -1);
        $hash{confirm} = $$w{confirm}->get_active() || '0';
        $hash{intro} = $$w{intro}->get_active() || '0';
        # Force no descriptions equal to command
        if (!$hash{description}) {
            $hash{description} = $hash{txt};
        }
        # Normalize capitalization of groups
        $hash{description} =~ s/^(.+?):/\u\L$1\E:/;
        push(@cfg, \%hash) unless $hash{txt} eq '';
    }

    @cfg = sort {lc($$a{description}) cmp lc($$b{description})} @cfg;
    return \@cfg;
}

# END: Public class methods
###################################################################

###################################################################
# START: Private functions definitions

sub _buildExecGUI {
    my $self = shift;

    my $container = $self->{container};
    my $cfg = $self->{cfg};

    my %w;

    # Build a vbox for:buttons, separator and expect widgets
    $w{vbox} = Gtk3::VBox->new(0, 0);

    # Build a hbuttonbox for widgets actions (add, etc.)
    $w{bbox} = Gtk3::HButtonBox->new();
    $w{vbox}->pack_start($w{bbox}, 0, 1, 0);
    $w{bbox}->set_layout('GTK_BUTTONBOX_START');

    # Build 'add' button
    $w{btnadd} = Gtk3::Button->new_from_stock('gtk-add');
    $w{bbox}->add($w{btnadd});

    # Build a separator
    $w{sep} = Gtk3::HSeparator->new();
    $w{vbox}->pack_start($w{sep}, 0, 1, 5);

    # Build a scrolled window
    $w{sw} = Gtk3::ScrolledWindow->new();
    $w{vbox}->pack_start($w{sw}, 1, 1, 0);
    $w{sw}->set_policy('automatic', 'automatic');
    $w{sw}->set_shadow_type('none');

    $w{vp} = Gtk3::Viewport->new();
    $w{sw}->add($w{vp});
    $w{vp}->set_property('border-width', 5);
    $w{vp}->set_shadow_type('none');

    # Build and add the vbox that will contain the expect widgets
    $w{vbexec} = Gtk3::VBox->new(0, 0);
    $w{vp}->add($w{vbexec});

    $$self{container} = $w{vbox};
    $$self{frame} = \%w;

    # Button(s) callback(s)

    $w{btnadd}->signal_connect('clicked', sub {
        # Save current cfg
        $$self{cfg} = $self->get_cfg();
        # Append an empty exec entry to cfg
        unshift(@{$$self{cfg}}, {'txt' => '', 'description' => '', 'confirm' => 0});
        # Update gui
        $self->update();
        # Set keyboard focus on last created entry
        $$self{list}[0]{txt}->grab_focus();
        return 1;
    });

    return 1;
}

sub _buildExec {
    my $self = shift;
    my $hash = shift;

    my $txt = $hash;
    my $desc = '';
    my $confirm = 0;
    my $intro = 1;

    if (ref($hash) ) {
        $txt = $$hash{txt} // '';
        $desc = $$hash{description} // '';
        $confirm = $$hash{confirm} // 0;
        $intro = $$hash{intro} // 1;
    }

    my @undo;
    my $undoing = 0;

    my %w;

    $w{position} = scalar @{$$self{list}};

    # Build the confirm checkbox
    $w{confirm} = Gtk3::CheckButton->new_with_label('Confirm');
    $w{confirm}->set_active($confirm);

    $w{frame} = Gtk3::Frame->new();
    $w{frame}->set_label_widget($w{confirm});

    # Make an HBox to contain checkbox, entry and delete
    $w{hbox} = Gtk3::HBox->new(0, 0);
    $w{frame}->add($w{hbox});

    $w{vbox} = Gtk3::VBox->new(0, 0);
    $w{hbox}->pack_start($w{vbox}, 1, 1, 0);

    $w{hbox3} = Gtk3::HBox->new(0, 0);
    $w{vbox}->pack_start($w{hbox3}, 0, 1, 0);

    # Build label
    $w{lbl} = Gtk3::Label->new('Command: ');
    $w{hbox3}->pack_start($w{lbl}, 0, 1, 0);

    # Build entry
    $w{txt} = Gtk3::Entry->new();
    $w{hbox3}->pack_start($w{txt}, 1, 1, 0);
    $w{txt}->set_icon_from_stock('primary', 'gtk-execute');
    $w{txt}->set_text($txt);

    # Build checkbutton
    $w{intro} = Gtk3::CheckButton->new(' send <INTRO> at the end');
    $w{hbox3}->pack_start($w{intro}, 0, 1, 0);
    $w{intro}->set_active($intro);

    $w{hbox4} = Gtk3::HBox->new(0, 0);
    $w{vbox}->pack_start($w{hbox4}, 0, 1, 0);

    # Build label
    $w{lbl2} = Gtk3::Label->new('Description: ');
    $w{hbox4}->pack_start($w{lbl2}, 0, 1, 0);
    $w{hbox4}->set_tooltip_markup("<i>Group</i><b>:</b><i>Description</i>\n<b>Group:</b> This value will group all commands with the same name in the menu.\n\nExample <b>Mysql</b>:<i>Show tables</i>");

    # Build entry
    $w{desc} = Gtk3::Entry->new();
    $w{hbox4}->pack_start($w{desc}, 1, 1, 0);
    $w{desc}->set_text($desc);

    $w{vbox2} = Gtk3::VBox->new(0, 0);
    $w{hbox}->pack_start($w{vbox2}, 0, 1, 0);

    # Build delete button
    $w{btn} = Gtk3::Button->new_from_stock('gtk-delete');
    $w{vbox2}->pack_start($w{btn}, 1, 1, 0);

    if ($$self{'where'} eq 'local') {
        # Build exec button
        $w{btnExec} = Gtk3::Button->new_from_stock('gtk-execute');
        $w{vbox2}->pack_start($w{btnExec}, 0, 1, 0);
    }

    # Add built control to main container
    $$self{frame}{vbexec}->pack_start($w{frame}, 0, 1, 0);
    $$self{frame}{vbexec}->show_all();

    $$self{list}[$w{position}] = \%w;

    # Setup some callbacks

    # Assign a callback for deleting entry
    $w{btn}->signal_connect('clicked' => sub {
        splice(@{$$self{list}}, $w{position}, 1);
        splice(@{$$self{cfg}}, $w{position}, 1);
        $self->update();
        return 1;
    });

    # Assign a callback for executing entry
    $w{btnExec}->signal_connect('clicked' => sub {
        my $cmd = $w{txt}->get_chars(0, -1);

        # Ask for confirmation
        if ($w{confirm}->get_active()) {
            if (!_wConfirm(undef, "Execute <b>'" . __($cmd) . "'</b> " . 'LOCALLY')) {
                # Not confirmed, do not execute
                return 1;
            }
        };

        system(_subst($cmd, $PACMain::FUNCS{_MAIN}{_CFG}) . ' &');

        return 1;
    }) if ($$self{'where'} eq 'local');

    # Assign a callback to populate this entry with its own context menu
    $w{txt}->signal_connect('button_press_event' => sub {
        my ($widget, $event) = @_;

        return 0 unless $event->button eq 3;

        my @menu_items;

        # Populate with user defined variables
        my @variables_menu;
        my $i = 0;
        foreach my $value (map{$_->{txt} // ''} @{$$self{variables}}) {
            my $j = $i;
            push(@variables_menu,
            {
                label => "<V:$j> ($value)",
                code => sub {
                    $w{txt}->insert_text("<V:$j>", -1, $w{txt}->get_position());
                }
            });
            ++$i;
        }
        push(@menu_items, {
            label => 'User Local variables...',
            sensitive => scalar @{$$self{variables}},
            submenu => \@variables_menu
        });

        # Populate with global defined variables
        my @global_variables_menu;
        foreach my $var (sort {$a cmp $b} keys %{$PACMain::FUNCS{_MAIN}{_CFG}{'defaults'}{'global variables'}}) {
            my $val = $PACMain::FUNCS{_MAIN}{_CFG}{'defaults'}{'global variables'}{$var}{'value'};
            push(@global_variables_menu, {
                label => "<GV:$var> ($val)",
                code => sub {
                    $w{txt}->insert_text("<GV:$var>", -1, $w{txt}->get_position());
                }
            });
        }
        push(@menu_items, {
            label => 'Global variables...',
            sensitive => scalar(@global_variables_menu),
            submenu => \@global_variables_menu
        });

        # Populate with environment variables
        my @environment_menu;
        foreach my $key (sort {$a cmp $b} keys %ENV) {
            my $value = $ENV{$key};
            push(@environment_menu, {
                label => "<ENV:$key>",
                tooltip => "$key=$value",
                code => sub {
                    $w{txt}->insert_text("<ENV:$key>", -1, $w{txt}->get_position());
                }
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
                my $pos = $w{txt}->get_property('cursor_position');
                $w{txt}->insert_text("<ASK:change_by_number>", -1, $w{txt}->get_position());
                $w{txt}->select_region($pos + 5, $pos + 21);
            }
        });

        # Populate with <ASK:*|> special string
        push(@menu_items, {
            label => 'Interactive user choose from list',
            tooltip => 'User will be prompted to choose a value form a user defined list separated with "|" (pipes without quotes)',
            code => sub {
                my $pos = $w{txt}->get_property('cursor_position');
                $w{txt}->insert_text('<ASK:descriptive line|opt1|opt2|...|optN>', -1, $w{txt}->get_position());
                $w{txt}->select_region($pos + 5, $pos + 40);
            }
        });

        # Populate with <CMD:*> special string
        push(@menu_items, {
            label => 'Use a command output as value',
            tooltip => 'The given command line will be locally executed, and its output (both STDOUT and STDERR) will be used to replace this value',
            code => sub {
                my $pos = $w{txt}->get_property('cursor_position');
                $w{txt}->insert_text('<CMD:command to launch>', -1, $w{txt}->get_position());
                $w{txt}->select_region($pos + 5, $pos + 22);
            }
        });

        # Populate with Ásbrú Connection Manager internal variables
        my @int_variables_menu;
        push(@int_variables_menu, {label => "UUID",      code => sub {$w{txt}->insert_text("<UUID>",      -1, $w{txt}->get_position());} });
        push(@int_variables_menu, {label => "TIMESTAMP", code => sub {$w{txt}->insert_text("<TIMESTAMP>", -1, $w{txt}->get_position());} });
        push(@int_variables_menu, {label => "DATE_Y",    code => sub {$w{txt}->insert_text("<DATE_Y>",    -1, $w{txt}->get_position());} });
        push(@int_variables_menu, {label => "DATE_M",    code => sub {$w{txt}->insert_text("<DATE_M>",    -1, $w{txt}->get_position());} });
        push(@int_variables_menu, {label => "DATE_D",    code => sub {$w{txt}->insert_text("<DATE_D>",    -1, $w{txt}->get_position());} });
        push(@int_variables_menu, {label => "TIME_H",    code => sub {$w{txt}->insert_text("<TIME_H>",    -1, $w{txt}->get_position());} });
        push(@int_variables_menu, {label => "TIME_M",    code => sub {$w{txt}->insert_text("<TIME_M>",    -1, $w{txt}->get_position());} });
        push(@int_variables_menu, {label => "TIME_S",    code => sub {$w{txt}->insert_text("<TIME_S>",    -1, $w{txt}->get_position());} });
        push(@int_variables_menu, {label => "NAME",      code => sub {$w{txt}->insert_text("<NAME>",      -1, $w{txt}->get_position());} });
        push(@int_variables_menu, {label => "TITLE",     code => sub {$w{txt}->insert_text("<TITLE>",     -1, $w{txt}->get_position());} });
        push(@int_variables_menu, {label => "IP",        code => sub {$w{txt}->insert_text("<IP>",        -1, $w{txt}->get_position());} });
        push(@int_variables_menu, {label => "USER",      code => sub {$w{txt}->insert_text("<USER>",      -1, $w{txt}->get_position());} });
        push(@int_variables_menu, {label => "PASS",      code => sub {$w{txt}->insert_text("<PASS>",      -1, $w{txt}->get_position());} });
        push(@menu_items, {label => 'Internal variables...', submenu => \@int_variables_menu});

        # Populate with <KPX_(title|username|url):*> special string
        if ($PACMain::FUNCS{_MAIN}{_CFG}{'defaults'}{'keepass'}{'use_keepass'}) {
            my (@titles, @usernames, @urls);
            foreach my $hash ($PACMain::FUNCS{_KEEPASS}->find()) {
                push(@titles, {
                    label => "<KPX_title:$$hash{title}>",
                    tooltip => "$$hash{password}",
                    code => sub {
                        $w{txt}->insert_text("<KPX_title:$$hash{title}>", -1, $w{txt}->get_position());
                    }
                });
                push(@usernames, {
                    label => "<KPX_username:$$hash{username}>",
                    tooltip => "$$hash{password}",
                    code => sub {
                        $w{txt}->insert_text("<KPX_username:$$hash{username}>", -1, $w{txt}->get_position());
                    }
                });
                push(@usernames, {
                    label => "<KPX_url:$$hash{url}>",
                    tooltip => "$$hash{password}",
                    code => sub {
                        $w{txt}->insert_text("<KPX_url:$$hash{url}>", -1, $w{txt}->get_position());
                    }
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
                        code => sub {
                            $w{txt}->insert_text("<KPXRE_GET_(title|username|password|url)_WHERE_(title|username|password|url)==Your_RegExp_here==>", -1, $w{txt}->get_position());
                        }
                    }
                ]
            });
        }

        _wPopUpMenu(\@menu_items, $event);

        return 1;
    });
    $w{txt}->signal_connect('delete_text' => sub {
        if (!$undoing) {
            push(@undo, $w{txt}->get_chars(0, -1));
        }
        return $_[1], $_[3];
    });
    $w{txt}->signal_connect('insert_text' => sub {
        if (!$undoing) {
            push(@undo, $w{txt}->get_chars(0, -1));
        }
        return $_[1], $_[3];
    });
    $w{txt}->signal_connect('key_press_event' => sub {
        my ($widget, $event) = @_;
        my $keyval = '' . ($event->keyval);
        my $state = '' . ($event->state);
        # Check if <Ctrl>z is pushed
        if (($event->state >= 'control-mask') && (chr($keyval) eq 'z') && (scalar @undo) ) {
            $undoing = 1;
            $w{txt}->set_text(pop(@undo) );
            $undoing = 0;
            return 1;
        }
        return 0;
    });

    return %w;
}

# END: Private functions definitions
###################################################################

1;
