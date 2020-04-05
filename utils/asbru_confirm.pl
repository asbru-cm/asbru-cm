#!/usr/bin/perl

###############################################################################
# This file is part of Ásbrú Connection Manager
#
# Copyright (C) 2020 Ásbrú Connection Manager team (https://asbru-cm.net)
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

use strict;

use Gtk3 '-init';
use utf8;
use Encode;

our (%window, %opt);

($opt{type}, $opt{title}, $opt{msg}) = ($ARGV[0], decode('utf8',$ARGV[1]), decode('utf8',$ARGV[2]));

$opt{msg} =~ s/&cr;/\n/g;
$opt{msg} =~ s/&squot;/\'/g;
$opt{msg} =~ s/&dquot;/\"/g;

$window{main} = Gtk3::Window->new('GTK_WINDOW_TOPLEVEL');
$window{main}->set_title($opt{'title'});
$window{main}->set_position('center');
$window{main}->set_keep_above(1);
$window{main}->set_deletable(0);
$window{main}->set_resizable(0);
$window{main}->set_default_size(200, 100);
$window{main}->signal_connect('destroy' => sub {
    print "CANCEL";
    Gtk3->main_quit();
});
$window{main}->set_border_width(8);

$window{frame} = Gtk3::Frame->new();
$window{main}->add($window{frame});

$window{frame}{vbox} = Gtk3::VBox->new();
$window{frame}{vbox}->set_border_width(8);
$window{frame}->add($window{frame}{vbox});

$window{frame}{msg} = Gtk3::Label->new();
$window{frame}{msg}->set_markup($opt{msg});
$window{frame}{vbox}->pack_start($window{frame}{msg}, 1, 1, 0);

$window{frame}{hbox} = Gtk3::HBox->new();
$window{frame}{vbox}->pack_start($window{frame}{hbox}, 1, 1, 0);
if ($opt{type} eq 'Confirm') {
    $window{frame}{btnCancel} = Gtk3::Button->new('Cancel');
    $window{frame}{hbox}->pack_start($window{frame}{btnCancel}, 1, 1, 0);
    $window{frame}{btnCancel}->signal_connect( 'clicked' => sub {
        print "CANCEL";
        Gtk3->main_quit();
    });
}

$window{frame}{btnContinue} = Gtk3::Button->new('Continue');
$window{frame}{hbox}->pack_start($window{frame}{btnContinue}, 1, 1, 0);

$window{frame}{btnContinue}->signal_connect('clicked' => sub {
    print "OK";
    Gtk3->main_quit();
});


$window{main}->show_all();

Gtk3->main();
