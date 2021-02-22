package PACExpectEntry;

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

    $self->{container} = undef;
    $self->{frame} = {};
    $self->{list} = [];

    _buildExpectGUI($self);
    defined $self->{cfg} and PACExpectEntry::update($self->{cfg});

    bless($self, $class);
    return $self;
}

sub update {
    my $self = shift;
    my $cfg = shift;
    my $variables = shift;

    defined $cfg and $$self{cfg} = $cfg;
    defined $variables and $$self{variables} = $variables;

    # Destroy previuos widgets
    $$self{frame}{vbexpect}->foreach(sub {$_[0]->destroy();});

    # Empty parent's widgets' list
    $$self{list} = [];

    # Now, add the -new?- widgets
    foreach my $hash (@{$$self{cfg}}) {_buildExpect($self, $hash);}

    # Delete "up" arrow from first element...
    defined $$self{list}[0] and $$self{list}[0]{ebup}->destroy();

    # ... and delete "down" arrow from last element.
    defined $$self{list}[$#{$$self{list}}] and  $$self{list}[$#{$$self{list}}]{ebdown}->destroy();

    return 1;
}

sub get_cfg {
    my $self = shift;

    my @cfg;

    foreach my $w (@{$self->{list}}) {
        my %hash;
        $hash{expect} = $$w{expect}->get_chars(0, -1);
        $hash{send} = $$w{send}->get_chars(0, -1);
        $hash{hidden} = $$w{hidden}->get_active || '0';
        $hash{active} = $$w{active}->get_active || '0';
        $hash{return} = $$w{return}->get_active || '0';

        if ($$w{cbOnMatch}->get_active) {
            $hash{on_match} = $$w{rbOnMatchGoto}->get_active ? $$w{on_match}->get_chars(0, -1) : -2;
        } else {
            $hash{on_match} = -1;
        }
        if ($$w{cbOnFail}->get_active) {
            $hash{on_fail} = $$w{rbOnFailGoto}->get_active ? $$w{on_fail}->get_chars(0, -1) : -2;
        } else {
            $hash{on_fail} = -1;
        }

        $hash{time_out} = $$w{cbTimeOut}->get_active ? $$w{time_out}->get_chars(0, -1) : -1;
        push(@cfg, \%hash);
    }

    return \@cfg;
}

# END: Public class methods
###################################################################

###################################################################
# START: Private functions definitions

sub _buildExpectGUI {
    my $self = shift;

    my $cfg = $self->{cfg};

    my %w;

    # Build a vbox for:buttons, separator and expect widgets
    $w{vbox} = Gtk3::VBox->new(0, 0);
    $w{hbox} = Gtk3::HBox->new(1, 0);

    # Build a hbuttonbox for widgets actions (add, etc.)
    $w{bbox} = Gtk3::HButtonBox->new();
    $w{vbox}->pack_start($w{hbox}, 0, 1, 0);
    $w{hbox}->pack_start($w{bbox}, 0, 1, 0);
    $w{bbox}->set_layout('GTK_BUTTONBOX_START');

    # Build 'add' button
    $w{btnadd} = Gtk3::Button->new_from_stock('gtk-add');
    $w{bbox}->add($w{btnadd});

    $w{help} = Gtk3::LinkButton->new('https://docs.asbru-cm.net/Manual/Connections/SSH/#expect');
    $w{help}->set_halign('GTK_ALIGN_END');
    $w{help}->set_label('');
    $w{help}->set_tooltip_text('Open Online Help');
    $w{help}->set_always_show_image(1);
    $w{help}->set_image(Gtk3::Image->new_from_stock('asbru-help', 'button'));
    $w{hbox}->pack_start($w{help}, 0, 1, 0);

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
    #$w{vp}->set_property('border-width', 0);
    $w{vp}->set_shadow_type('none');

    # Build and add the vbox that will contain the expect widgets
    $w{vbexpect} = Gtk3::VBox->new(0, 0);
    $w{vp}->add($w{vbexpect});

    $$self{container} = $w{vbox};
    $$self{frame} = \%w;

    # Button(s) callback(s)

    $w{btnadd}->signal_connect('clicked', sub {
        # Save current cfg
        $$self{cfg} = $self->get_cfg();
        # Append an empty expect entry to cfg
        push(@{$$self{cfg}}, {'expect' => '', 'send' => '', 'active' => 1, 'hidden' => 0});
        # Update gui
        $self->update();
        # Set keyboard focus on last created entry
        $$self{list}[$#{$$self{list}}]{expect}->grab_focus();
        return 1;
    });

    return 1;
}

sub _buildExpect {
    my $self = shift;
    my $hash = shift;

    my $exp = $$hash{'expect'} // '';
    my $cmd = $$hash{'send'} // '';
    my $hide = $$hash{'hidden'} // 0;
    my $active = $$hash{'active'} // (($cmd ne '') && ($exp ne '') );
    my $return = $$hash{'return'} // 1;
    my $on_match = $$hash{'on_match'} // -1;
    my $on_fail = $$hash{'on_fail'} // -1;
    my $time_out = $$hash{'time_out'} // -1;

    my @undo_expect;
    my $undoing_expect = 0;
    my @undo_exec;
    my $undoing_exec = 0;

    my %w;

    $w{position} = scalar @{$$self{list}};

    # Make a checkbox to use as frame's label
    $w{active} = Gtk3::CheckButton->new_with_label('Expect #' . $w{position} . ' ');
    $w{active}->set_active($active);

    # Make an container frame
    $w{frame} = Gtk3::Frame->new;
    $w{frame}->set_label_widget($w{active});
    $w{frame}->set_shadow_type('GTK_SHADOW_NONE');

    # Build an HBox
    $w{vbox} = Gtk3::VBox->new(0, 5);
    $w{hbox1} = Gtk3::HBox->new(0, 0);
    $w{frame}->add($w{vbox});
    $w{vbox}->pack_start($w{hbox1}, 0, 1, 0);

    # Build a vbox for event_boxes 1 & 2
    $w{vbox1} = Gtk3::VBox->new(0, 0);
    $w{hbox1}->pack_start($w{vbox1}, 0, 1, 0);

    # Build first event_box and add a go-up arrow
    $w{ebup} = Gtk3::EventBox->new;
    $w{vbox1}->pack_start($w{ebup}, 1, 1, 0);
    $w{ebup}->add(Gtk3::Image->new_from_stock('gtk-go-up', 'small-toolbar') );

    # Build first event_box and add a go-down arrow
    $w{ebdown} = Gtk3::EventBox->new;
    $w{vbox1}->pack_start($w{ebdown}, 1, 1, 0);
    $w{ebdown}->add(Gtk3::Image->new_from_stock('gtk-go-down', 'small-toolbar') );

    # Build a vbox for expect and send entries
    $w{vbox2} = Gtk3::VBox->new(0, 3);
    $w{hbox1}->pack_start($w{vbox2}, 1, 1, 0);
    $w{vbox2}->set_sensitive($active);

    # Build an HBox to contain label & expect entry
    $w{hboxExpect} = Gtk3::HBox->new(0, 0);
    $w{vbox2}->pack_start($w{hboxExpect}, 0, 1, 0);

    # Build and add the label
    $w{hboxExpect}->pack_start(Gtk3::Label->new('Expect: '), 0, 1, 0);

    # Build and add the expect entry
    $w{expect} = Gtk3::Entry->new;
    $w{hboxExpect}->pack_start($w{expect}, 1, 1, 0);
    $w{expect}->set_text($exp);
    $w{expect}->set_icon_from_stock('primary', 'asbru-prompt');

    $w{cbTimeOut} = Gtk3::CheckButton->new('Time out (seconds): ');
    $w{cbTimeOut}->set_active($time_out != -1);
    $w{hboxExpect}->pack_start($w{cbTimeOut}, 0, 1, 0);
    $w{time_out} = Gtk3::SpinButton->new_with_range(1, 65535, 1);
    $w{time_out}->set_value($time_out);
    $w{time_out}->set_sensitive($w{cbTimeOut}->get_active);
    $w{hboxExpect}->pack_start($w{time_out}, 0, 1, 0);

    # Build an HBox to contain label, hide checkbox & send entry
    $w{hboxSend} = Gtk3::HBox->new(0, 0);
    $w{vbox2}->pack_start($w{hboxSend}, 1, 1, 0);

    # Build and add the label
    $w{hboxSend}->pack_start(Gtk3::Label->new('Send('), 0, 1, 0);

    # Build the hide checkbox
    $w{hidden} = Gtk3::CheckButton->new_with_label('Hide');
    $w{hboxSend}->pack_start($w{hidden}, 0, 1, 0);
    $w{hidden}->set_active($hide);

    # Build and add the label
    $w{hboxSend}->pack_start(Gtk3::Label->new('): '), 0, 1, 0);

    # Build and add the send entry
    $w{send} = Gtk3::Entry->new;
    $w{hboxSend}->pack_start($w{send}, 1, 1, 0);
    $w{send}->set_icon_from_stock('primary', 'gtk-media-play');
    $w{send}->set_text($cmd);
    $w{send}->set_visibility(! $hide);

    # Build and add the return checkbox
    $w{return} = Gtk3::CheckButton->new_with_label('Return');
    $w{hboxSend}->pack_start($w{return}, 0, 1, 0);
    $w{return}->set_active($return);
    $w{return}->set_tooltip_text('Sends a <RETURN> (\n) after the string is entered.\nFor IBM 3270 connections, sends a \r\f (Carriage Return and Line Feed)');

    # Add ON_MATCH, ON_FAIL and TIME_OUT entries

    $w{vbox33} = Gtk3::HBox->new(0, 0);
    $w{vbox2}->pack_start($w{vbox33}, 0, 1, 0);

    $w{hbox33} = Gtk3::HBox->new(0, 0);
    $w{hbox33}->set_tooltip_text('If "Expect" IS matched, the "Send" string will be sent and we will "go to" selected Expect number. If stop is selected, Expect processing will stop, and control will be returned to user (no disconnect will happen)');
    $w{vbox33}->pack_start($w{hbox33}, 0, 1, 0);

    $w{cbOnMatch} = Gtk3::CheckButton->new('On MATCH: ');
    $w{cbOnMatch}->set_active($on_match != -1);
    $w{hbox33}->pack_start($w{cbOnMatch}, 1, 1, 0);

    $w{onmatchhbox} = Gtk3::HBox->new(0, 0);
    $w{onmatchhbox}->set_sensitive($w{cbOnMatch}->get_active);
    $w{hbox33}->pack_start($w{onmatchhbox}, 0, 1, 0);

    $w{rbOnMatchGoto} = Gtk3::RadioButton->new_with_label(undef, 'goto ');
    $w{rbOnMatchGoto}->set_active($on_match > -1);
    $w{onmatchhbox}->pack_start($w{rbOnMatchGoto}, 1, 1, 0);

    $w{on_match} = Gtk3::SpinButton->new_with_range(0, 65535, 1);
    $w{on_match}->set_value($on_match);
    $w{on_match}->set_sensitive($w{rbOnMatchGoto}->get_active);
    $w{onmatchhbox}->pack_start($w{on_match}, 0, 1, 0);

    $w{rbOnMatchStop} = Gtk3::RadioButton->new_with_label_from_widget($w{rbOnMatchGoto}, 'stop');
    $w{rbOnMatchStop}->set_active($on_match == -2);
    $w{onmatchhbox}->pack_start($w{rbOnMatchStop}, 1, 1, 0);

    $w{hbox33}->pack_start(Gtk3::VSeparator->new, 0, 1, 5);

    $w{hbox34} = Gtk3::HBox->new(0, 0);
    $w{hbox34}->set_tooltip_text('If "Expect" IS NOT matched, no string will be sent, and we will "go to" selected Expect. If stop is selected, Expect processing will stop, and control will be returned to user (no disconnect will happen)');
    $w{vbox33}->pack_start($w{hbox34}, 0, 1, 0);

    $w{cbOnFail} = Gtk3::CheckButton->new('On FAIL: ');
    $w{cbOnFail}->set_active($on_fail != -1);
    $w{hbox34}->pack_start($w{cbOnFail}, 1, 1, 0);

    $w{onfailhbox} = Gtk3::HBox->new(0, 0);
    $w{onfailhbox}->set_sensitive($w{cbOnFail}->get_active);
    $w{hbox34}->pack_start($w{onfailhbox}, 0, 1, 0);

    $w{rbOnFailGoto} = Gtk3::RadioButton->new_with_label(undef, 'goto ');
    $w{rbOnFailGoto}->set_active($on_fail > -1);
    $w{onfailhbox}->pack_start($w{rbOnFailGoto}, 1, 1, 0);

    $w{on_fail} = Gtk3::SpinButton->new_with_range(0, 65535, 1);
    $w{on_fail}->set_value($on_fail);
    $w{on_fail}->set_sensitive($w{rbOnFailGoto}->get_active);
    $w{onfailhbox}->pack_start($w{on_fail}, 0, 1, 0);

    $w{rbOnFailStop} = Gtk3::RadioButton->new_with_label_from_widget($w{rbOnFailGoto}, 'stop');
    $w{rbOnFailStop}->set_active($on_fail == -2);
    $w{onfailhbox}->pack_start($w{rbOnFailStop}, 1, 1, 0);

    # Build delete button
    $w{btn} = Gtk3::Button->new_from_stock('gtk-delete');
    $w{btn}->set_valign('GTK_ALIGN_START');
    $w{hbox1}->pack_start($w{btn}, 0, 0, 0);

    $w{vbox}->pack_start(Gtk3::HSeparator->new(), 1, 1, 0);

    # Add built control to main container
    $$self{frame}{vbexpect}->pack_start($w{frame}, 0, 1, 0);
    $$self{frame}{vbexpect}->show_all;

    $$self{list}[$w{position}] = \%w;

    # Setup some callbacks

    # Disable scroll on spin buttons to avoid changes by mistake
    foreach my $spin ('time_out','on_match','on_fail') {
        $w{$spin}->signal_connect('scroll-event' => sub {
            return 1;
        });
    }

    $w{on_match}->signal_connect('value_changed' => sub {
        my $v = $w{on_match}->get_chars(0, -1);
        return 1 if $v <= scalar(@{$$self{cfg}} -1);
        $w{on_match}->set_value(scalar(@{$$self{cfg}}) - 1);
    });

    $w{on_fail}->signal_connect('value_changed' => sub {
        my $v = $w{on_fail}->get_chars(0, -1);
        return 1 if $v <= scalar(@{$$self{cfg}} - 1);
        $w{on_fail}->set_value(scalar(@{$$self{cfg}}) - 1);
    });

    # Asign Drag and Drop functions
    my @targets = (Gtk3::TargetEntry->new('PAC Expect', [], 0) );
    $w{active}->drag_source_set('GDK_BUTTON1_MASK', \@targets, ['move']);
    $w{active}->signal_connect('drag_begin' => sub {
        $_[1]->set_icon_pixbuf(_scale(_screenshot($$self{list}[$w{position}]{'frame'}), 256, 128, 1), 0, 0);
        $$self{_DND_SOURCE} = \%w;
    });

    $w{active}->drag_dest_set('GTK_DEST_DEFAULT_ALL', \@targets, ['move']);
    $w{active}->signal_connect('drag_drop' => sub {
        my $source_w = splice(@{$$self{cfg}}, $$self{_DND_SOURCE}{position}, 1);
        splice(@{$$self{cfg}}, $w{position}, 0, $source_w);
        $self->update;
    });

    $w{frame}->drag_dest_set('GTK_DEST_DEFAULT_ALL', \@targets, ['move']);
    $w{frame}->signal_connect('drag_drop' => sub {
        my $source_w = splice(@{$$self{cfg}}, $$self{_DND_SOURCE}{position}, 1);
        splice(@{$$self{cfg}}, $w{position}, 0, $source_w);
        $self->update;
    });

    # Asign a callback to show right-click mouse menu
    $w{active}->signal_connect('button_press_event' => sub {
        my ($widget, $event) = @_;

        ($event->button ne 3) and return 0;

        my @exec_menu_items;

        # Copy
        push(@exec_menu_items, {
            label => 'Copy',
            stockicon => 'gtk-copy',
            sensitive => ($w{active}->get_active()),
            code => sub {
                $self->{_COPY_EXPECT}{'expect'} = $w{expect}->get_chars(0, -1);
                $self->{_COPY_EXPECT}{'exec'} = $w{send}->get_chars(0, -1);
                $self->{_COPY_EXPECT}{'show'} = $w{hidden}->get_active() || '0';
                $self->{_COPY_EXPECT}{'use'} = $w{active}->get_active() || '0';
                $self->{_COPY_EXPECT}{'return'} = $w{return}->get_active() || '0';
                $self->{_COPY_EXPECT}{'cbOnMatch'} = $w{cbOnMatch}->get_active() || '0';
                $self->{_COPY_EXPECT}{'rbOnMatchGoto'} = $w{rbOnMatchGoto}->get_active() || '0';
                $self->{_COPY_EXPECT}{'on_match'} = $w{on_match}->get_chars(0, -1);
                $self->{_COPY_EXPECT}{'cbOnFail'} = $w{cbOnFail}->get_active() || '0';
                $self->{_COPY_EXPECT}{'rbOnFailGoto'} = $w{rbOnFailGoto}->get_active() || '0';
                $self->{_COPY_EXPECT}{'on_fail'} = $w{on_fail}->get_chars(0, -1);
                $self->{_COPY_EXPECT}{'cbTimeOut'} = $w{cbTimeOut}->get_active() || '0';
                $self->{_COPY_EXPECT}{'time_out'} = $w{time_out}->get_chars(0, -1);
                $self->{_COPY_EXPECT}{'cut'} = 0;
            }
        });
        # Cut
        push(@exec_menu_items, {
            label => 'Cut',
            stockicon => 'gtk-cut',
            sensitive => ($w{active}->get_active()),
            code => sub {
                $self->{_COPY_EXPECT}{'expect'} = $w{expect}->get_chars(0, -1);
                $self->{_COPY_EXPECT}{'exec'} = $w{send}->get_chars(0, -1);
                $self->{_COPY_EXPECT}{'show'} = $w{hidden}->get_active() || '0';
                $self->{_COPY_EXPECT}{'use'} = $w{active}->get_active() || '0';
                $self->{_COPY_EXPECT}{'return'} = $w{return}->get_active() || '0';
                $self->{_COPY_EXPECT}{'cbOnMatch'} = $w{cbOnMatch}->get_active() || '0';
                $self->{_COPY_EXPECT}{'rbOnMatchGoto'} = $w{rbOnMatchGoto}->get_active() || '0';
                $self->{_COPY_EXPECT}{'on_match'} = $w{on_match}->get_chars(0, -1);
                $self->{_COPY_EXPECT}{'cbOnFail'} = $w{cbOnFail}->get_active() || '0';
                $self->{_COPY_EXPECT}{'rbOnFailGoto'} = $w{rbOnFailGoto}->get_active() || '0';
                $self->{_COPY_EXPECT}{'on_fail'} = $w{on_fail}->get_chars(0, -1);
                $self->{_COPY_EXPECT}{'cbTimeOut'} = $w{cbTimeOut}->get_active() || '0';
                $self->{_COPY_EXPECT}{'time_out'} = $w{time_out}->get_chars(0, -1);
                $self->{_COPY_EXPECT}{'cut'} = 1;
                $w{expect}->set_text('');
                $w{send}->set_text('');
                $w{hidden}->set_active(1);
                $w{active}->set_active(0);
            }
        });
        # Paste ?
        push(@exec_menu_items, {
            label => 'Paste',
            stockicon => 'gtk-paste',
            sensitive => (defined $self->{_COPY_EXPECT}),
            code => sub {
                $w{expect}->set_text($self->{_COPY_EXPECT}{'expect'});
                $w{send}->set_text($self->{_COPY_EXPECT}{'exec'});
                $w{hidden}->set_active($self->{_COPY_EXPECT}{'show'});
                $w{active}->set_active($self->{_COPY_EXPECT}{'use'});
                $w{return}->set_active($self->{_COPY_EXPECT}{'return'});
                $w{cbOnMatch}->set_active($self->{_COPY_EXPECT}{'cbOnMatch'});
                $w{rbOnMatchGoto}->set_active($self->{_COPY_EXPECT}{'rbOnMatchGoto'});
                $w{on_match}->set_value($self->{_COPY_EXPECT}{'on_match'});
                $w{cbOnFail}->set_active($self->{_COPY_EXPECT}{'cbOnFail'});
                $w{rbOnFailGoto}-> set_active($self->{_COPY_EXPECT}{'rbOnFailGoto'});
                $w{on_fail}->set_value($self->{_COPY_EXPECT}{'on_fail'});
                $w{cbTimeOut}->set_active($self->{_COPY_EXPECT}{'cbTimeOut'});
                $w{time_out}->set_value($self->{_COPY_EXPECT}{'time_out'});
                $$self{_COPY_EXPECT}{'cut'} and $self->{_COPY_EXPECT} = undef;
            }
        });
        push(@exec_menu_items, {separator => 1});
        # Delete
        push(@exec_menu_items, {
            label => 'Delete',
            stockicon => 'gtk-delete',
            code => sub {
                $$self{cfg} = $self->get_cfg();
                splice(@{$$self{list}}, $w{position}, 1);
                splice(@{$$self{cfg}}, $w{position}, 1);
                $self->update;
            }
        });

        PACUtils::_wPopUpMenu(\@exec_menu_items, $event);

        return 1;
    });

    # Asign a callback for visibility of entry
    $w{hidden}->signal_connect('toggled' => sub {$w{send}->set_visibility(! $w{hidden}->get_active); return 1;});

    # Asign a callback for entry sensitiveness
    $w{active}->signal_connect('toggled' => sub {$w{vbox2}->set_sensitive($w{active}->get_active);});

    # Asign a callback for move up arrow click
    $w{ebup}->signal_connect('button_release_event' => sub {
        return 1 if $w{position} == 0;

        # Save moving widget
        my $exp = $w{expect}->get_chars(0, -1);
        my $cmd = $w{send}->get_chars(0, -1);
        my $hide = $w{hidden}->get_active() || '0';
        my $active = $w{active}->get_active() || '0';
        my $return = $w{return}->get_active() || '0';
        my $cbOnMatch = $w{cbOnMatch}->get_active() || '0';
        my $rbOnMatchGoto = $w{rbOnMatchGoto}->get_active() || '0';
        my $on_match = $w{on_match}->get_chars(0, -1);
        my $cbOnFail = $w{cbOnFail}->get_active() || '0';
        my $rbOnFailGoto = $w{rbOnFailGoto}->get_active() || '0';
        my $on_fail = $w{on_fail}->get_chars(0, -1);
        my $cbTimeOut = $w{cbTimeOut}->get_active() || '0';
        my $time_out = $w{time_out}->get_chars(0, -1);

        # Put in moving widget data from previous (position - 1)
        $w{expect}->set_text($$self{list}[$w{position} - 1]{expect}->get_chars(0, -1) );
        $w{send}->set_text($$self{list}[$w{position} - 1]{send}->get_chars(0, -1) );
        $w{hidden}->set_active($$self{list}[$w{position} - 1]{hidden}->get_active() || '0');
        $w{active}->set_active($$self{list}[$w{position} - 1]{active}->get_active() || '0');
        $w{return}->set_active($$self{list}[$w{position} - 1]{'return'}->get_active || '0');
        $w{cbOnMatch}->set_active($$self{list}[$w{position} - 1]{'cbOnMatch'}->get_active || '0');
        $w{rbOnMatchGoto}->set_active($$self{list}[$w{position} - 1]{'rbOnMatchGoto'}->get_active || '0');
        $w{on_match}->set_value($$self{list}[$w{position} - 1]{'on_match'}->get_chars(0, -1) );
        $w{cbOnFail}->set_active($$self{list}[$w{position} - 1]{'cbOnFail'}->get_active || '0');
        $w{rbOnFailGoto}->set_active($$self{list}[$w{position} - 1]{'rbOnFailGoto'}->get_active || '0');
        $w{on_fail}->set_value($$self{list}[$w{position} - 1]{'on_fail'}->get_chars(0, -1) );
        $w{cbTimeOut}->set_active($$self{list}[$w{position} - 1]{'cbTimeOut'}->get_active || '0');
        $w{time_out}->set_value($$self{list}[$w{position} - 1]{'time_out'}->get_chars(0, -1) );

        # Put in previous widget (position - 1) data from the moving one
        $$self{list}[$w{position} - 1]{expect}->set_text($exp);
        $$self{list}[$w{position} - 1]{send}->set_text($cmd);
        $$self{list}[$w{position} - 1]{hidden}->set_active($hide);
        $$self{list}[$w{position} - 1]{active}->set_active($active);
        $$self{list}[$w{position} - 1]{return}->set_active($return);
        $$self{list}[$w{position} - 1]{cbOnMatch}->set_active($cbOnMatch);
        $$self{list}[$w{position} - 1]{rbOnMatchGoto}->set_active($rbOnMatchGoto);
        $$self{list}[$w{position} - 1]{on_match}->set_value($on_match);
        $$self{list}[$w{position} - 1]{cbOnFail}->set_active($cbOnFail);
        $$self{list}[$w{position} - 1]{rbOnFailGoto}->set_active($rbOnFailGoto);
        $$self{list}[$w{position} - 1]{on_fail}->set_value($on_fail);
        $$self{list}[$w{position} - 1]{cbTimeOut}->set_active($cbTimeOut);
        $$self{list}[$w{position} - 1]{time_out}->set_value($time_out);

        return 1;
    });

    # Asign a callback for move down arrow click
    $w{ebdown}->signal_connect('button_release_event' => sub {
        return 1 if $w{position} == $#{$$self{list}};

        my $exp = $w{expect}->get_chars(0, -1);
        my $cmd = $w{send}->get_chars(0, -1);
        my $hide = $w{hidden}->get_active() || '0';
        my $active = $w{active}->get_active() || '0';
        my $return = $w{return}->get_active() || '0';
        my $cbOnMatch = $w{cbOnMatch}->get_active() || '0';
        my $rbOnMatchGoto = $w{rbOnMatchGoto}->get_active() || '0';
        my $on_match = $w{on_match}->get_chars(0, -1);
        my $cbOnFail = $w{cbOnFail}->get_active() || '0';
        my $rbOnFailGoto = $w{rbOnFailGoto}->get_active() || '0';
        my $on_fail = $w{on_fail}->get_chars(0, -1);
        my $cbTimeOut = $w{cbTimeOut}->get_active() || '0';
        my $time_out = $w{time_out}->get_chars(0, -1);

        # Put in moving widget data from previous (position - 1)
        $w{expect}->set_text($$self{list}[$w{position} + 1]{expect}->get_chars(0, -1) );
        $w{send}->set_text($$self{list}[$w{position} + 1]{send}->get_chars(0, -1) );
        $w{hidden}->set_active($$self{list}[$w{position} + 1]{hidden}->get_active() || '0');
        $w{active}->set_active($$self{list}[$w{position} + 1]{active}->get_active() || '0');
        $w{return}->set_active($$self{list}[$w{position} + 1]{'return'}->get_active || '0');
        $w{cbOnMatch}->set_active($$self{list}[$w{position} + 1]{'cbOnMatch'}->get_active || '0');
        $w{rbOnMatchGoto}->set_active($$self{list}[$w{position} + 1]{'rbOnMatchGoto'}->get_active || '0');
        $w{on_match}->set_value($$self{list}[$w{position} + 1]{'on_match'}->get_chars(0, -1) );
        $w{cbOnFail}->set_active($$self{list}[$w{position} + 1]{'cbOnFail'}->get_active || '0');
        $w{rbOnFailGoto}->set_active($$self{list}[$w{position} + 1]{'rbOnFailGoto'}->get_active || '0');
        $w{on_fail}->set_value($$self{list}[$w{position} + 1]{'on_fail'}->get_chars(0, -1) );
        $w{cbTimeOut}->set_active($$self{list}[$w{position} + 1]{'cbTimeOut'}->get_active || '0');
        $w{time_out}->set_value($$self{list}[$w{position} + 1]{'time_out'}->get_chars(0, -1) );

        # Put in previous widget (position - 1) data from the moving one
        $$self{list}[$w{position} + 1]{expect}->set_text($exp);
        $$self{list}[$w{position} + 1]{send}->set_text($cmd);
        $$self{list}[$w{position} + 1]{hidden}->set_active($hide);
        $$self{list}[$w{position} + 1]{active}->set_active($active);
        $$self{list}[$w{position} + 1]{return}->set_active($return);
        $$self{list}[$w{position} + 1]{cbOnMatch}->set_active($cbOnMatch);
        $$self{list}[$w{position} + 1]{rbOnMatchGoto}->set_active($rbOnMatchGoto);
        $$self{list}[$w{position} + 1]{on_match}->set_value($on_match);
        $$self{list}[$w{position} + 1]{cbOnFail}->set_active($cbOnFail);
        $$self{list}[$w{position} + 1]{rbOnFailGoto}->set_active($rbOnFailGoto);
        $$self{list}[$w{position} + 1]{on_fail}->set_value($on_fail);
        $$self{list}[$w{position} + 1]{cbTimeOut}->set_active($cbTimeOut);
        $$self{list}[$w{position} + 1]{time_out}->set_value($time_out);

        return 1;
    });

    # Asign a callback for deleting entry
    $w{btn}->signal_connect('clicked' => sub {
        $$self{cfg} = $self->get_cfg();
        splice(@{$$self{list}}, $w{position}, 1);
        splice(@{$$self{cfg}}, $w{position}, 1);
        $self->update();
        return 1;
    });

    # Asign a callback to populate this entry with oir own context menu
    $w{expect}->signal_connect('button_press_event' => sub {
        my ($widget, $event) = @_;

        return 0 unless $event->button eq 3;

        my @menu_items;

        # Populate with user defined command prompt
        push(@menu_items, {
            label => '<command prompt>',
            tooltip => 'Expect for a sting matching a COMMAND PROMPT (as defined under "Preferences")',
            stockicon => 'asbru-prompt',
            code => sub {$w{expect}->insert_text('<command prompt>', -1, $w{expect}->get_position);}
        });

        # Populate with user defined variables
        my @variables_menu;
        my $i = 0;
        foreach my $value (map{$_->{txt} // ''} @{$$self{variables}}) {
            my $j = $i;
            push(@variables_menu, {
                label => "<V:$j> ($value)",
                code => sub {$w{expect}->insert_text("<V:$j>", -1, $w{expect}->get_position);}
            });
            ++$i;
        }
        push(@menu_items, {
            label => 'User variables...',
            sensitive => scalar @{$$self{variables}},
            submenu => \@variables_menu
        });

        # Populate with global defined variables
        my @global_variables_menu;
        foreach my $var (sort {$a cmp $b} keys %{$PACMain::FUNCS{_MAIN}{_CFG}{'defaults'}{'global variables'}}) {
            my $val = $PACMain::FUNCS{_MAIN}{_CFG}{'defaults'}{'global variables'}{$var}{'value'};
            push(@global_variables_menu, {
                label => "<GV:$var> ($val)",
                code => sub {$w{expect}->insert_text("<GV:$var>", -1, $w{expect}->get_position);}
            });
        }
        push(@menu_items, {
            label => 'Global variables...',
            sensitive => scalar(@global_variables_menu),
            submenu => \@global_variables_menu
        });

        # Populate with <CMD:*> special string
        push(@menu_items, {
            label => 'Use a command output as value',
            tooltip => 'The given command line will be locally executed, and its output (both STDOUT and STDERR) will be used to replace this value',
            stockicon => 'gtk-execute',
            code => sub {
                my $pos = $w{expect}->get_property('cursor_position');
                $w{expect}->insert_text('<CMD:command to launch>', -1, $w{expect}->get_position);
                $w{expect}->select_region($pos + 5, $pos + 22);
            }
        });

        # Populate with Ásbrú Connection Manager internal variables
        my @int_variables_menu;
        push(@int_variables_menu, {label => "UUID",code => sub {$w{send}->insert_text("<UUID>", -1, $w{send}->get_position);} });
        push(@int_variables_menu, {label => "TIMESTAMP",code => sub {$w{send}->insert_text("<TIMESTAMP>", -1, $w{send}->get_position);} });
        push(@int_variables_menu, {label => "DATE_Y",code => sub {$w{send}->insert_text("<DATE_Y>", -1, $w{send}->get_position);} });
        push(@int_variables_menu, {label => "DATE_M",code => sub {$w{send}->insert_text("<DATE_M>", -1, $w{send}->get_position);} });
        push(@int_variables_menu, {label => "DATE_D",code => sub {$w{send}->insert_text("<DATE_D>", -1, $w{send}->get_position);} });
        push(@int_variables_menu, {label => "TIME_H",code => sub {$w{send}->insert_text("<TIME_H>", -1, $w{send}->get_position);} });
        push(@int_variables_menu, {label => "TIME_M",code => sub {$w{send}->insert_text("<TIME_M>", -1, $w{send}->get_position);} });
        push(@int_variables_menu, {label => "TIME_S",code => sub {$w{send}->insert_text("<TIME_S>", -1, $w{send}->get_position);} });
        push(@int_variables_menu, {label => "NAME",code => sub {$w{send}->insert_text("<NAME>", -1, $w{send}->get_position);} });
        push(@int_variables_menu, {label => "TITLE",code => sub {$w{send}->insert_text("<TITLE>", -1, $w{send}->get_position);} });
        push(@int_variables_menu, {label => "IP",code => sub {$w{send}->insert_text("<IP>", -1, $w{send}->get_position);} });
        push(@int_variables_menu, {label => "USER",code => sub {$w{send}->insert_text("<USER>", -1, $w{send}->get_position);} });
        push(@int_variables_menu, {label => "PASS",code => sub {$w{send}->insert_text("<PASS>", -1, $w{send}->get_position);} });
        push(@menu_items, {label => 'Internal variables...', submenu => \@int_variables_menu});

        $PACMain::FUNCS{_KEEPASS}->setRigthClickMenuEntry($PACMain::FUNCS{_EDIT}{_WINDOWEDIT},'username,password',$w{expect},\@menu_items);

        _wPopUpMenu(\@menu_items, $event);

        return 1;
    });

    # Asign a callback to populate this entry with oir own context menu
    $w{send}->signal_connect('button_press_event' => sub {
        my ($widget, $event) = @_;

        return 0 unless $event->button eq 3;

        my @menu_items;

        # Populate with user defined variables
        my @variables_menu;
        my $i = 0;
        foreach my $value (map{$_->{txt} // ''} @{$$self{variables}}) {
            my $j = $i;
            push(@variables_menu, {
                label => "<V:$j> ($value)",
                code => sub {$w{send}->insert_text("<V:$j>", -1, $w{send}->get_position);}
            });
            ++$i;
        }
        push(@menu_items, {
            label => 'User variables...',
            sensitive => scalar @{$$self{variables}},
            submenu => \@variables_menu
        });

        # Populate with global defined variables
        my @global_variables_menu;
        foreach my $var (sort {$a cmp $b} keys %{$PACMain::FUNCS{_MAIN}{_CFG}{'defaults'}{'global variables'}}) {
            my $val = $PACMain::FUNCS{_MAIN}{_CFG}{'defaults'}{'global variables'}{$var}{'value'};
            push(@global_variables_menu, {
                label => "<GV:$var> ($val)",
                code => sub {$w{send}->insert_text("<GV:$var>", -1, $w{send}->get_position);}
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
                label => "<ENV:" . __($key) . ">",
                tooltip => "$key=$value",
                code => sub {$w{send}->insert_text("<ENV:$key>", -1, $w{send}->get_position);}
            });
        }
        push(@menu_items, {
            label => 'Environment variables...',
            submenu => \@environment_menu
        });

        # Populate with <ASK:#> special string
        push(@menu_items, {
            label => 'Interactive user input',
            tooltip => 'User will be prompted to provide a value with a text box (free data type)',
            stockicon => 'gtk-dialog-question',
            code => sub {
                my $pos = $w{send}->get_property('cursor_position');
                $w{send}->insert_text('<ASK:number>', -1, $w{send}->get_position);
                $w{send}->select_region($pos + 5, $pos + 11);
            }
        });

        # Populate with <ASK:*|> special string
        push(@menu_items, {
            label => 'Interactive user choose from list',
            tooltip => 'User will be prompted to choose a value form a user defined list separated with "|" (pipes without quotes)',
            stockicon => 'gtk-dialog-question',
            code => sub {
                my $pos = $w{send}->get_property('cursor_position');
                $w{send}->insert_text('<ASK:descriptive line|opt1|opt2|...|optN>', -1, $w{send}->get_position);
                $w{send}->select_region($pos + 5, $pos + 40);
            }
        });

        # Populate with <CMD:*> special string
        push(@menu_items, {
            label => 'Use a command output as value',
            tooltip => 'The given command line will be locally executed, and its output (both STDOUT and STDERR) will be used to replace this value',
            stockicon => 'gtk-execute',
            code => sub {
                my $pos = $w{send}->get_property('cursor_position');
                $w{send}->insert_text('<CMD:command to launch>', -1, $w{send}->get_position);
                $w{send}->select_region($pos + 5, $pos + 22);
            }
        });

        # Populate with Ásbrú Connection Manager internal variables
        my @int_variables_menu;
        push(@int_variables_menu, {label => "UUID",code => sub {$w{send}->insert_text("<UUID>", -1, $w{send}->get_position);} });
        push(@int_variables_menu, {label => "TIMESTAMP",code => sub {$w{send}->insert_text("<TIMESTAMP>", -1, $w{send}->get_position);} });
        push(@int_variables_menu, {label => "DATE_Y",code => sub {$w{send}->insert_text("<DATE_Y>", -1, $w{send}->get_position);} });
        push(@int_variables_menu, {label => "DATE_M",code => sub {$w{send}->insert_text("<DATE_M>", -1, $w{send}->get_position);} });
        push(@int_variables_menu, {label => "DATE_D",code => sub {$w{send}->insert_text("<DATE_D>", -1, $w{send}->get_position);} });
        push(@int_variables_menu, {label => "TIME_H",code => sub {$w{send}->insert_text("<TIME_H>", -1, $w{send}->get_position);} });
        push(@int_variables_menu, {label => "TIME_M",code => sub {$w{send}->insert_text("<TIME_M>", -1, $w{send}->get_position);} });
        push(@int_variables_menu, {label => "TIME_S",code => sub {$w{send}->insert_text("<TIME_S>", -1, $w{send}->get_position);} });
        push(@int_variables_menu, {label => "NAME",code => sub {$w{send}->insert_text("<NAME>", -1, $w{send}->get_position);} });
        push(@int_variables_menu, {label => "TITLE",code => sub {$w{send}->insert_text("<TITLE>", -1, $w{send}->get_position);} });
        push(@int_variables_menu, {label => "IP",code => sub {$w{send}->insert_text("<IP>", -1, $w{send}->get_position);} });
        push(@int_variables_menu, {label => "USER",code => sub {$w{send}->insert_text("<USER>", -1, $w{send}->get_position);} });
        push(@int_variables_menu, {label => "PASS",code => sub {$w{send}->insert_text("<PASS>", -1, $w{send}->get_position);} });
        push(@menu_items, {label => 'Internal variables...', submenu => \@int_variables_menu});

        if ($PACMain::FUNCS{_KEEPASS}->getUseKeePass()) {
            # Copy User,Password from KeePassXC
            push(@menu_items, {
                label => 'Add Username KeePassXC',
                tooltip => 'KeePassXC Username',
                code => sub {
                    my $pos = $w{send}->get_property('cursor_position');
                    my $selection = $PACMain::FUNCS{_KEEPASS}->listEntries($$self{_WINDOWEDIT});
                    if ($selection) {
                        $w{send}->insert_text("<username|$selection>", -1, $w{expect}->get_position);
                    }
                }
            });
            push(@menu_items, {
                label => 'Add Password KeePassXC',
                tooltip => 'KeePassXC Password',
                code => sub {
                    my $pos = $w{send}->get_property('cursor_position');
                    my $selection = $PACMain::FUNCS{_KEEPASS}->listEntries($$self{_WINDOWEDIT});
                    if ($selection) {
                        $w{send}->insert_text("<password|$selection>", -1, $w{expect}->get_position);
                    }
                }
            });
        }

        _wPopUpMenu(\@menu_items, $event);

        return 1;
    });

    $w{expect}->signal_connect('delete_text' => sub {! $undoing_expect and push(@undo_expect, $w{expect}->get_chars(0, -1) ); return $_[1], $_[3];});
    $w{expect}->signal_connect('insert_text' => sub {! $undoing_expect and push(@undo_expect, $w{expect}->get_chars(0, -1) ); return $_[1], $_[3];});
    $w{expect}->signal_connect('key_press_event' => sub {
        my ($widget, $event) = @_;
        my $keyval = '' . ($event->keyval);
        my $state = '' . ($event->state);
        # Check if <Ctrl>z is pushed
        if (($event->state >= 'control-mask') && (chr($keyval) eq 'z') && (scalar @undo_expect) ) {
            $undoing_expect = 1;
            $w{expect}->set_text(pop(@undo_expect) );
            $undoing_expect = 0;
            return 1;
        }
        return 0;
    });

    $w{send}->signal_connect('delete_text' => sub {! $undoing_exec and push(@undo_exec, $w{send}->get_chars(0, -1) ); return $_[1], $_[3];});
    $w{send}->signal_connect('insert_text' => sub {! $undoing_exec and push(@undo_exec, $w{send}->get_chars(0, -1) ); return $_[1], $_[3];});
    $w{send}->signal_connect('key_press_event' => sub
    {
        my ($widget, $event) = @_;
        my $keyval = '' . ($event->keyval);
        my $state = '' . ($event->state);
        # Check if <Ctrl>z is pushed
        if (($event->state >= 'control-mask') && (chr($keyval) eq 'z') && (scalar @undo_exec) ) {
            $undoing_exec = 1;
            $w{send}->set_text(pop(@undo_exec) );
            $undoing_exec = 0;
            return 1;
        }
        return 0;
    });


    $w{rbOnMatchGoto}->signal_connect('toggled' => sub {$w{on_match}->set_sensitive($w{rbOnMatchGoto}->get_active);});
    $w{rbOnFailGoto}->signal_connect('toggled' => sub {$w{on_fail}->set_sensitive($w{rbOnFailGoto}->get_active);});
    $w{cbOnMatch}->signal_connect('toggled' => sub {$w{onmatchhbox}->set_sensitive($w{cbOnMatch}->get_active);});
    $w{cbOnFail}->signal_connect('toggled' => sub {$w{onfailhbox}->set_sensitive($w{cbOnFail}->get_active);});
    $w{cbTimeOut}->signal_connect('toggled' => sub {$w{time_out}->set_sensitive($w{cbTimeOut}->get_active);});
    return %w;
}

# END: Private functions definitions
###################################################################

1;
