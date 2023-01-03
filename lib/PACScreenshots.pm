package PACScreenshots;

###############################################################################
# This file is part of Ásbrú Connection Manager
#
# Copyright (C) 2017-2022 Ásbrú Connection Manager team (https://asbru-cm.net)
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
use File::Copy;

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
my $CFG_DIR = $ENV{"ASBRU_CFG"};

# END: Define GLOBAL CLASS variables
###################################################################

###################################################################
# START: Public class methods

sub new {
    my $class = shift;
    my $self = {};

    $self->{cfg} = shift;

    $self->{container} = undef;
    $self->{frame} = {};
    $self->{list} = [];

    _buildScreenshotsGUI($self);
    if (defined $self->{cfg}) {
        PACScreenshots::update($self->{cfg});
    }
    bless($self, $class);
    return $self;
}

sub update {
    my $self = shift;
    my $cfg = shift;
    my $uuid = shift;

    if (defined $cfg) {
        $$self{cfg} = $cfg;
    }
    if (defined $uuid) {
        $$self{uuid} = $uuid;
    }

    # Destroy previous widgets
    $$self{frame}{hbscreenshots}->foreach(sub {
        $_[0]->destroy();
    });

    # Empty parent widgets' list
    $$self{list} = [];

    # Now, add the -new?- widgets
    foreach my $file (@{$$self{cfg}{screenshots}}) {
        $self->_buildScreenshots($file);
    }

    return 1;
}

sub add {
    my $self = shift;
    my $file = shift;
    my $cfg = shift;

    my $new_cfg = $$self{cfg};
    if (defined $cfg) {
        $new_cfg = $cfg;
    }

    if (! _pixBufFromFile($file) ) {
        _wMessage($PACMain::FUNCS{_MAIN}{_GUI}{main}, "File '$file' could not be loaded as a screenshot file");
        return 0;
    }

    my $screenshot_file = '';
    my $rn = rand(123456789);
    $screenshot_file = "$CFG_DIR/screenshots/asbru_screenshot_$rn.png";
    while (-f $screenshot_file) {
        $rn = rand(123456789);
        $screenshot_file = "$CFG_DIR/screenshots/asbru_screenshot_$rn.png";
    }

    copy($file, $screenshot_file);

    push(@{$$new_cfg{screenshots}}, $screenshot_file);
    $self->update();
    $PACMain::FUNCS{_MAIN}->_setCFGChanged(1);

    return 1;
}

# END: Public class methods
###################################################################

###################################################################
# START: Private functions definitions

sub _buildScreenshotsGUI {
    my $self = shift;

    my $cfg = $self->{cfg};

    my %w;

    # Build a vbox for:buttons, separator and image widgets
    $w{hbox} = Gtk3::HBox->new(0, 0);
    $w{hbox}->set_size_request(200, 170);

    # Build a buttonbox for widgets actions (add, etc.)
    $w{bbox} = Gtk3::VButtonBox->new();
    $w{hbox}->pack_start($w{bbox}, 0, 1, 5);
    $w{bbox}->set_layout('GTK_BUTTONBOX_SPREAD');

    # Build 'add' button
    $w{btnadd} = Gtk3::Button->new();

    $w{hboxbtnadd} = Gtk3::HBox->new(0, 5);
    $w{btnadd}->add($w{hboxbtnadd});
    $w{btnadd}->set('can_focus', 0);

    $w{hboxbtnadd}->pack_start(Gtk3::Image->new_from_stock('gtk-add', 'menu'), 0, 1, 5);
    $w{hboxbtnadd}->pack_start(Gtk3::Label->new("Add\nScreenshot"), 0, 1, 5);


    $w{bbox}->add($w{btnadd});

    $w{btnopenfolder} = Gtk3::Button->new();

    $w{hboxbtnopenfolder} = Gtk3::HBox->new(0, 5);
    $w{btnopenfolder}->add($w{hboxbtnopenfolder});
    $w{btnopenfolder}->set('can_focus', 0);

    $w{hboxbtnopenfolder}->pack_start(Gtk3::Image->new_from_stock('gtk-open', 'menu'), 0, 1, 5);
    $w{hboxbtnopenfolder}->pack_start(Gtk3::Label->new("Open Folder"), 0, 1, 5);


    $w{bbox}->add($w{btnopenfolder});

    # Build a scrolled window
    $w{sw} = Gtk3::ScrolledWindow->new();
    $w{hbox}->pack_start($w{sw}, 1, 1, 0);
    $w{sw}->set_policy('automatic', 'automatic');
    $w{sw}->set_shadow_type('none');

    $w{vp} = Gtk3::Viewport->new();
    $w{sw}->add($w{vp});
    $w{vp}->set_property('border-width', 5);
    $w{vp}->set_shadow_type('none');

    # Build and add the vbox that will contain the image widgets
    $w{hbscreenshots} = Gtk3::HBox->new(0, 0);
    $w{vp}->add($w{hbscreenshots});

    $$self{container} = $w{hbox};
    $$self{frame} = \%w;

    # Button(s) callback(s)
    $w{btnadd}->signal_connect('clicked', sub {
        # Save current cfg
        my $file = $self->_chooseScreenshot;
        if ($file) {
            my $screenshot_file = '';
            $screenshot_file = $CFG_DIR . '/screenshots/asbru_screenshot_' . rand(123456789). '.png';
            while(-f $screenshot_file) {$screenshot_file = $CFG_DIR . '/screenshots/asbru_screenshot_' . rand(123456789). '.png';}
            _pixBufFromFile($file)->save($screenshot_file, 'png');

            push(@{$$self{cfg}{screenshots}}, $screenshot_file) and $self->update();
            $PACMain::FUNCS{_MAIN}->_setCFGChanged(1);
        }
        return 1;
    });

    $w{btnopenfolder}->signal_connect('clicked', sub {
        system("$ENV{'ASBRU_ENV_FOR_EXTERNAL'} /usr/bin/xdg-open $CFG_DIR/screenshots");}
    );

    my @targets = (Gtk3::TargetEntry->new('STRING', [], 0) );
    $w{hbox}->drag_dest_set('all', \@targets, ['copy', 'move']);
    $w{hbox}->signal_connect('drag_data_received' => sub {
        my ($me, $context, $x, $y, $data, $info, $time) = @_;
        if (($data->length < 0) || ($data->type->name ne 'STRING')) {
            return 0;
        }

        foreach my $line (split(/\R/, $data->data) ) {
            $line =~ s/\R//go;
            if ($line !~ /file:\/\/(.+)/go) {
                next;
            }
            my $file = $1;
            if (-f $file) {
                $self->add($file);
            }
        }

        return 1;
    });

    return 1;
}

sub _buildScreenshots {
    my $self = shift;
    my $file = shift;

    my %w;

    $w{file} = $file // '';
    $w{position} = scalar @{$$self{list}};

    # Create an eventbox for the image
    $w{ebScreenshot} = Gtk3::EventBox->new();

    # Create a gtkImage to contain the screenshot
    $w{imageScreenshot} = Gtk3::Image->new();
    -f $file and $w{imageScreenshot}->set_from_pixbuf(_scale($file, 200, 200, 1) );
    $w{ebScreenshot}->add($w{imageScreenshot});

    # Add built control to main container
    $$self{frame}{hbscreenshots}->pack_start($w{ebScreenshot}, 0, 1, 5);
    $$self{frame}{hbscreenshots}->show_all;

    $$self{list}[$w{position}] = \%w;

    # Setup some callbacks

    # Show right-click menu for the screenshots image viewer
    $w{ebScreenshot}->signal_connect('button_press_event' => sub {
        my ($widget, $event) = @_;

        if ($event->button eq 1) {
            $self->_showImage($w{file});
            return 1;
        } elsif ($event->button eq 3) {
            my @screenshot_menu_items;
            push(@screenshot_menu_items, {
                label => 'Change Screenshot file...',
                stockicon => 'gtk-edit',
                code => sub {
                    my $file = $self->_chooseScreenshot;
                    if ($file) {
                        $w{file} = $file;
                        $w{imageScreenshot}->set_from_pixbuf(_scale($file, 200, 200, 'keep aspect ratio') );
                        splice(@{$$self{cfg}{screenshots}}, $w{position}, 1, $w{file});
                        $PACMain::FUNCS{_MAIN}->_setCFGChanged(1);
                    }
                    return 1;
                }
            });
            push(@screenshot_menu_items, {
                label => 'Save picture as...',
                sensitive => $w{imageScreenshot}->get_storage_type ne 'stock',
                stockicon => 'gtk-save',
                code => sub {
                    my $new_file = $APPNAME . '-' . ($self->{cfg}->{name} || 'SCREENSHOT') . '-' . ($self->{cfg}->{uuid} || 'FILE') . '.png';
                    $new_file =~ s/\s+/_/go;

                    my $dialog = Gtk3::FileChooserDialog->new (
                        'Select file to save screenshot',
                        undef,
                        'select-folder',
                        'gtk-cancel' => 'GTK_RESPONSE_CANCEL',
                        'gtk-ok' => 'GTK_RESPONSE_OK'
                    );
                    $dialog->set_action('GTK_FILE_CHOOSER_ACTION_SAVE');
                    $dialog->set_do_overwrite_confirmation(1);
                    $dialog->set_current_folder($ENV{'HOME'});
                    $dialog->set_current_name($new_file);

                    if ($dialog->run ne 'ok') {$dialog->destroy; return 1;}

                    $new_file = $dialog->get_filename;
                    $dialog->destroy;

                    # Copy temporal log file to selected path
                    copy($w{file}, $new_file);

                    return 1;
                }
            });
            push(@screenshot_menu_items, {
                label => 'Remove Screenshot',
                sensitive => $w{imageScreenshot}->get_storage_type ne 'stock',
                stockicon => 'gtk-delete',
                code => sub {
                    return 1 unless _wConfirm(undef, "Remove Screenshot file '$w{file}'?");

                    splice(@{$$self{list}}, $w{position}, 1);
                    splice(@{$$self{cfg}{screenshots}}, $w{position}, 1);
                    $PACMain::FUNCS{_MAIN}->_setCFGChanged(1);
                    $self->update($$self{cfg});
                    return 1;
                }
            });
            _wPopUpMenu(\@screenshot_menu_items, $event);
        } else {
            return 0;
        }

        return 1,
    });

    return %w;
}

sub _chooseScreenshot {
    my $self = shift;

    my $filter_images = Gtk3::FileFilter->new();
    $filter_images->set_name('Images');
    $filter_images->add_pixbuf_formats;

    my $dialog = Gtk3::FileChooserDialog->new(
        'Choose Screenshot',
        $$self{_GUI}{main},
        'GTK_FILE_CHOOSER_ACTION_OPEN',
        'gtk-cancel', 'GTK_RESPONSE_CANCEL',
        'gtk-open', 'GTK_RESPONSE_ACCEPT'
    );

    $dialog->add_filter($filter_images);
    if (-d CFG_DIR . '/screenshots') {
        $dialog->set_current_folder($CFG_DIR . '/screenshots');
    } else {
        $dialog->set_current_folder($ENV{'HOME'});
    }

    $dialog->signal_connect('update-preview' => sub {$self->_preview($dialog);});

    my $file = '';

    # Add a "Show hidden" checkbox
    my $cbShowHidden = Gtk3::CheckButton->new_with_mnemonic('Show _hidden files');
    $dialog->get_action_area->pack_start($cbShowHidden, 0, 1, 0);
    $cbShowHidden->signal_connect('toggled', sub {$dialog->set_show_hidden($cbShowHidden->get_active);});

    $dialog->show_all;
    if ($dialog->run eq 'accept') {
        $file = $dialog->get_filename;
    }
    $dialog->destroy;

    return $file;
}

sub _preview {
    my $self = shift;
    my $dialog = shift;

    $dialog->set_preview_widget_active(0);

    my $file = $dialog->get_preview_filename;
    if (!(defined $file && -f $file)) {
        return 1;
    }

    my $preview = Gtk3::Image->new();
    $dialog->set_preview_widget($preview);

    my $preview_pixbuf = Gtk3::Gdk::Pixbuf->new_from_file_at_size($file, 256, 256);
    $preview->set_from_pixbuf($preview_pixbuf);
    $dialog->set_preview_widget_active($preview_pixbuf);

    return 1;
}

sub _showImage {
    my $self = shift;
    my $file = shift;

    if ($PACMain::FUNCS{_MAIN}{_CFG}{'defaults'}{'screenshots use external viewer'}) {
        system("$ENV{'ASBRU_ENV_FOR_EXTERNAL'} " . $PACMain::FUNCS{_MAIN}{_CFG}{'defaults'}{'screenshots external viewer'}, $file);
        return 1;
    }

    my $screen = Gtk3::Gdk::Screen::get_default;
    my $sw = $screen->get_width;
    my $sh = $screen->get_height;

    my $window = Gtk3::Dialog->new_with_buttons(
        "$APPNAME (v$APPVERSION) : Screenshot '$file'",
        $PACMain::FUNCS{_MAIN}{_GUI}{main},
        'GTK_DIALOG_DESTROY_WITH_PARENT',
        'gtk-close' => 'close',
    );
    # and setup some dialog properties.
    $window->set_default_response('close');
    $window->set_position('center');
    $window->set_icon_from_file($APPICON);
    $window->set_size_request(320, 200);
    $window->set_resizable(1);

    my $sc = Gtk3::ScrolledWindow->new();
    my $pb = _pixBufFromFile($file);
    my $image = Gtk3::Image->new_from_pixbuf($pb);
    my $pw = $pb->get_width + 30;
    my $ph = $pb->get_height + 50;

    $sc->set_policy('automatic', 'automatic');
    $sc->set_min_content_width($pw);
    $sc->set_min_content_height($ph);
    $window->get_content_area->add($sc);

    $sc->add_with_viewport($image);

    $pw = $pb->get_width + 30;
    $ph = $pb->get_height + 50;

    if ($pw > $sw || $ph > $sh) {
        $window->maximize;
    } else {
        $window->set_default_size($pw, $ph);
    }

    $window->signal_connect('response', sub {$window->destroy; return 1;});

    $window->show_all;

    return 1;
}

# END: Private functions definitions
###################################################################

1;
