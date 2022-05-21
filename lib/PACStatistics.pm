package PACStatistics;

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
use Storable qw (nstore retrieve);
use POSIX qw(strftime);

# GTK
use Gtk3 '-init';

# Other application modules
use PACUtils;

# END: Import Modules
###################################################################

###################################################################
# Define GLOBAL CLASS variables

my $APPNAME = $PACUtils::APPNAME;
my $APPVERSION = $PACUtils::APPVERSION;
my $APPICON = $RealBin . '/res/asbru-logo-64.png';
my $CFG_DIR = $ENV{"ASBRU_CFG"};
my $STATS_FILE = $CFG_DIR . '/asbru_stats.nfreeze';

# END: Define GLOBAL CLASS variables
###################################################################

###################################################################
# START: Public class methods

sub new {
    my $class = shift;

    my $self = {};

    $self->{cfg} = shift;
    $self->{statistics} = {};
    $self->{container} = undef;
    $self->{frame} = {};

    readStats($self);
    _buildStatisticsGUI($self);

    bless($self, $class);
    return $self;
}

sub update {
    my $self = shift;
    my $uuid = shift;
    my $cfg = shift // $PACMain::FUNCS{_MAIN}{_CFG};

    $$self{cfg} = $cfg;
    $$self{uuid} = $uuid;
    my $name = $$cfg{environments}{$uuid}{name};

    my $font = 'font="monospace 9"';

    $$self{frame}{lblPR}->set_markup('');
    $$self{frame}{lblPG}->set_markup('');
    $$self{frame}{lblPN}->set_markup('');
    $$self{frame}{hboxPACRoot}->hide();
    $$self{frame}{hboxPACGroup}->hide();
    $$self{frame}{hboxPACNode}->hide();

    # Show/Hide widgets
    if ($uuid eq '__PAC__ROOT__') {
        $$self{frame}{hboxPACRoot}->show();
        $$self{frame}{hboxPACGroup}->hide();
        $$self{frame}{hboxPACNode}->hide();

        my $groups = 0;
        my $nodes = 0;
        my $total_conn = 0;
        my $total_time = 0;

        foreach my $tmpuuid (keys %{$$cfg{'environments'}}) {
            if ($tmpuuid eq '__PAC__ROOT__') {
                next;
            }
            if ($$cfg{'environments'}{$tmpuuid}{_is_group}) {
                $groups++;
                $total_conn += ($$self{statistics}{$tmpuuid}{total_connections} // 0);
            } else {
                if ($tmpuuid ne '__PAC_SHELL__') {
                    $nodes++;
                }
                $total_time += ($$self{statistics}{$tmpuuid}{total_time} // 0);
                $total_conn += ($$self{statistics}{$tmpuuid}{total_conn} // 0);
            }
        }

        # Prepare STRINGIFIED data
        my $str_total_time = '';
        $str_total_time .= int($total_time / 86400) . ' days, ';
        $str_total_time .= ($total_time / 3600) % 24 . ' hours, ';
        $str_total_time .= ($total_time / 60) % 60 . ' minutes, ';
        $str_total_time .= $total_time % 60 . ' seconds';

        $$self{frame}{lblPR}->set_markup(
            "<span $font><b>All connections</b>\n" .
            "Total groups:                  <b>$groups</b>\n" .
            "Total nodes:                   <b>$nodes</b>\n" .
            "Total connections established: <b>$total_conn</b>\n" .
            "Total time connected:          <b>$str_total_time</b></span>"
        );
    } elsif ($$cfg{environments}{$uuid}{_is_group}) {
        $$self{frame}{hboxPACRoot}->hide();
        $$self{frame}{hboxPACGroup}->show();
        $$self{frame}{hboxPACNode}->hide();

        my $groups = 0;
        my $nodes = 0;
        my $total_conn = 0;
        my $total_time = 0;

        foreach my $tmpuuid ($PACMain::FUNCS{_MAIN}{_GUI}{treeConnections}->_getChildren($uuid, 'all', 1) ) {
            if ($$cfg{'environments'}{$tmpuuid}{_is_group}) {
                $groups++;
                $total_conn += ($$self{statistics}{$tmpuuid}{total_conn} // 0);
            } else {
                $nodes++;
                $total_time += ($$self{statistics}{$tmpuuid}{total_time} // 0);
                $total_conn += ($$self{statistics}{$tmpuuid}{total_conn} // 0);
            }
        }

        # Prepare STRINGIFIED data
        my $str_total_time = '';
        $str_total_time .= int($total_time / 86400) . ' days, ';
        $str_total_time .= ($total_time / 3600) % 24 . ' hours, ';
        $str_total_time .= ($total_time / 60) % 60 . ' minutes, ';
        $str_total_time .= $total_time % 60 . ' seconds';

        $$self{frame}{lblPG}->set_markup(
            "<span $font><b>Group: @{[__($name)]}</b>\n" .
            "Total sub-groups:              <b>$groups</b>\n" .
            "Total contained nodes:         <b>$nodes</b>\n" .
            "Total connections established: <b>$total_conn</b>\n" .
            "Total time connected:          <b>$str_total_time</b></span>"
        );
    } else {
        $$self{frame}{hboxPACRoot}->hide();
        $$self{frame}{hboxPACGroup}->hide();
        $$self{frame}{hboxPACNode}->show();

        my $groups = 0;
        my $nodes = 0;
        my $start = 0;
        my $stop = 0;
        my $total_conn = 0;
        my $total_time = 0;

        if (! defined $$self{statistics}{$uuid}) {
            $$self{statistics}{$uuid}{start} = 0;
            $$self{statistics}{$uuid}{stop} = 0;
            $$self{statistics}{$uuid}{total_conn} = 0;
            $$self{statistics}{$uuid}{total_time} = 0;
        }

        $start = $$self{statistics}{$uuid}{start} // 0;
        $stop = $$self{statistics}{$uuid}{stop} // 0;
        $total_conn = $$self{statistics}{$uuid}{total_conn} // 0;
        $total_time = $$self{statistics}{$uuid}{total_time} // 0;

        my $str_start = $start ? strftime("%Y-%m-%d %H:%M:%S", localtime($$self{statistics}{$uuid}{start}) ) : 'NO DATA AVAILABLE';
        my $str_stop = $stop ? strftime("%Y-%m-%d %H:%M:%S", localtime($$self{statistics}{$uuid}{stop}) ) : 'NO DATA AVAILABLE';

        # Prepare STRINGIFIED data
        my $str_total_time = '';
        $str_total_time .= int($total_time / 86400) . ' days, ';
        $str_total_time .= ($total_time / 3600) % 24 . ' hours, ';
        $str_total_time .= ($total_time / 60) % 60 . ' minutes, ';
        $str_total_time .= $total_time % 60 . ' seconds';

        $$self{frame}{lblPN}->set_markup(
            "<span $font><b>Connection: @{[__($name)]}</b>\n\n" .
            "Total connections established: <b>$total_conn</b>\n" .
            "Last connection:               <b>$str_start</b>\n" .
            "Total time connected:          <b>$str_total_time</b></span>"
        );
    }

    return 1;
}

sub readStats {
    my $self = shift;
    eval {$$self{statistics} = retrieve($STATS_FILE);};
    return $@ ? 0 : 1;
}

sub saveStats {return nstore($_[0]{statistics}, $STATS_FILE);}

sub start {
    my $self = shift;
    my $uuid = shift;

    $$self{statistics}{$uuid}{total_conn}++;
    $$self{statistics}{$uuid}{start} = time;
    $$self{statistics}{$uuid}{stop} = 0;
    $self->update($uuid);

    return 1;
}

sub stop {
    my $self = shift;
    my $uuid = shift;

    $$self{statistics}{$uuid}{stop} = time;
    $$self{statistics}{$uuid}{total_time} += ($$self{statistics}{$uuid}{stop} - $$self{statistics}{$uuid}{start});
    $self->update($uuid);

    return 1;
}

sub purge {
    my $self = shift;
    my $cfg = shift // $PACMain::FUNCS{_MAIN}{_CFG};

    foreach my $uuid (keys %{$$self{statistics}}) {delete $$self{statistics}{$uuid} unless $uuid eq '__PAC_SHELL__' || defined $$cfg{environments}{$uuid};}

    return 1;
}

# END: Public class methods
###################################################################

###################################################################
# START: Private functions definitions

sub _buildStatisticsGUI {
    my $self = shift;

    my $cfg = $$self{cfg};

    my %w;

    # Build a vbox for:buttons, separator and image widgets
    $w{hbox} = Gtk3::HBox->new(0, 0);

    $w{hboxReset} = Gtk3::HBox->new(0, 5);
    $w{hboxReset}->pack_start(Gtk3::Image->new_from_stock('gtk-refresh', 'menu'), 0, 1, 5);
    $w{hboxReset}->pack_start(Gtk3::Label->new("Reset\nStatistics"), 0, 1, 5);
    $w{btnReset} = Gtk3::Button->new();
    $w{btnReset}->set_size_request(155, 0);
    $w{btnReset}->set_valign('GTK_ALIGN_CENTER');
    $w{btnReset}->set('can_focus', 0);
    $w{btnReset}->add($w{hboxReset});
    $w{hbox}->pack_start($w{btnReset}, 0, 0, 5);

    $w{vbox} = Gtk3::VBox->new(0, 0);
    $w{hbox}->pack_start($w{vbox}, 1, 1, 0);

    $w{hboxPACRoot} = Gtk3::HBox->new(0, 0);
    $w{vbox}->pack_start($w{hboxPACRoot}, 0, 1, 0);

    $w{lblPR} = Gtk3::Label->new();
    $w{lblPR}->set_justify('left');
    $w{lblPR}->set_line_wrap(1);
    $w{hboxPACRoot}->pack_start($w{lblPR}, 0, 1, 0);

    $w{hboxPACGroup} = Gtk3::HBox->new(0, 0);
    $w{vbox}->pack_start($w{hboxPACGroup}, 0, 1, 0);

    $w{lblPG} = Gtk3::Label->new();
    $w{lblPG}->set_justify('left');
    $w{lblPG}->set_line_wrap(1);
    $w{hboxPACGroup}->pack_start($w{lblPG}, 0, 0, 0);

    $w{hboxPACNode} = Gtk3::HBox->new(0, 0);
    $w{vbox}->pack_start($w{hboxPACNode}, 0, 1, 0);

    $w{lblPN} = Gtk3::Label->new();
    $w{lblPN}->set_justify('left');
    $w{lblPN}->set_line_wrap(1);
    $w{hboxPACNode}->pack_start($w{lblPN}, 0, 1, 0);

    $$self{container} = $w{hbox};
    $$self{frame} = \%w;

    # Callback(s)
    $w{btnReset}->signal_connect('clicked', sub {
        my $cfg = $$self{cfg};
        my $uuid = $$self{uuid};
        my $name = $$cfg{environments}{$uuid}{name};

        if ($uuid eq '__PAC__ROOT__') {
            if (_wConfirm($PACMain::FUNCS{_MAIN}{_GUI}{main}, "Are you sure you want to reset <b>all Ásbrú</b> statistics?\n\nThis action can not be undone!")) {
                foreach my $child (keys %{$$cfg{environments}}) {
                    if ($child eq '__PAC__ROOT__') {
                        next;
                    }
                    $$self{statistics}{$child}{start} = 0;
                    $$self{statistics}{$child}{stop} = 0;
                    $$self{statistics}{$child}{total_conn} = 0;
                    $$self{statistics}{$child}{total_time} = 0;
                }
            }
        } elsif ($$cfg{environments}{$uuid}{_is_group}) {
            if (_wConfirm($PACMain::FUNCS{_MAIN}{_GUI}{main}, "Are you sure you want to reset statistics for group:\n\n<b>@{[__($name)]}</b>\n\nThis action can not be undone!")) {
                foreach my $child ($PACMain::FUNCS{_MAIN}{_GUI}{treeConnections}->_getChildren($uuid, 0, 1)) {
                    $$self{statistics}{$child}{start} = 0;
                    $$self{statistics}{$child}{stop} = 0;
                    $$self{statistics}{$child}{total_conn} = 0;
                    $$self{statistics}{$child}{total_time} = 0;
                }
            }
        } else {
            if (_wConfirm($PACMain::FUNCS{_MAIN}{_GUI}{main}, "Are you sure you want to reset statistics for connection:\n\n<b>@{[__($name)]}</b>\n\nThis action can not be undone!")) {
                $$self{statistics}{$uuid}{start} = 0;
                $$self{statistics}{$uuid}{stop} = 0;
                $$self{statistics}{$uuid}{total_conn} = 0;
                $$self{statistics}{$uuid}{total_time} = 0;
            }
        }

        $self->update($uuid);
        return 1;
    });

    return 1;
}

# END: Private functions definitions
###################################################################

1;
