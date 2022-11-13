package PACTrayUnity;

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

# GTK
use Gtk3 '-init';

# PAC modules
use PACUtils;

# AppIndicator
eval {
    Glib::Object::Introspection->setup(
        basename => 'AppIndicator3',
        version  => '0.1',
        package  => 'AppIndicator',
    );
};
if ($@) {
    eval {
        Glib::Object::Introspection->setup(
            basename => 'AyatanaAppIndicator3',
            version  => '0.1',
            package  => 'AppIndicator',
        );
    };
    if ($@) {
        warn "WARNING: AppIndicator is missing --> there might be no icon showing up in the status bar when running Unity!\n";
        return 0;
    }
}

# END: Import Modules
###################################################################

###################################################################
# Define GLOBAL CLASS variables

my $APPNAME = $PACUtils::APPNAME;
my $APPVERSION = $PACUtils::APPVERSION;
my $APPICON = $RealBin . '/res/asbru-logo-64.png';
my $TRAYICON = $RealBin . '/res/asbru-logo-tray.png';
my $GROUPICON_ROOT = _pixBufFromFile($RealBin . '/res/themes/default/asbru_group.svg');
# END: Define GLOBAL CLASS variables
###################################################################

###################################################################
# START: Define PUBLIC CLASS methods

sub new {
    my $class = shift;

    my $self = {};

    $self->{_MAIN} = shift;

    $self->{_TRAY} = undef;

    if ($$self{_MAIN}{_CFG}{defaults}{'use bw icon'}) {
        $TRAYICON = $RealBin . '/res/asbru_tray_bw.png';
    }

    # Build the GUI
    _initGUI($self) or return 0;

    bless($self, $class);
    return $self;
}

# DESTRUCTOR
sub DESTROY {
    my $self = shift;
    undef $self;
    return 1;
}

# Returns TRUE if the tray icon is currently visible
sub is_visible {
    my $self = shift;

    return $$self{_TRAY}->get_status() ne 'passive';
}

# Returns size and placement of the tray icon
sub get_geometry {
    my $self = shift;

    # DevNote: there is no way API to retrieve the place of the icon ; returns dummy values
    return ({}, {}, {x => 0, y => 0});
}

# Enable the tray menu
sub set_tray_menu {
    my $self = shift;

    return $self->_setTrayMenu();
}

# Make the tray icon active/inactive (aka 'shown/hidden')
sub set_active() {
    my $self = shift;
    $$self{_TRAY}->set_status('active');
}
sub set_passive() {
    my $self = shift;
    $$self{_TRAY}->set_status('passive');
}


# END: Define PUBLIC CLASS methods
###################################################################

###################################################################
# START: Define PRIVATE CLASS functions

sub _initGUI {
    my $self = shift;

    $$self{_TRAY} = AppIndicator::Indicator->new('asbru-cm', $TRAYICON, 'application-status');
    $$self{_TRAY}->set_icon_theme_path($RealBin . '/res');
    $$self{_TRAY}->set_status('active');
    $$self{_MAIN}{_CFG}{'tmp'}{'tray available'} = ! $@;
    return 1;
}

sub _setTrayMenu {
    my $self = shift;
    my $widget = shift;
    my $event = shift;

    my @m;

    push(@m, {label => 'Local Shell', stockicon => $PACMain::UNITY ? '' : 'gtk-home', code => sub {$PACMain::FUNCS{_MAIN}{_GUI}{shellBtn}->clicked();} });
    push(@m, {separator => 1});
    push(@m, {label => 'Clusters', stockicon => $PACMain::UNITY ? '' : 'asbru-cluster-manager', submenu => _menuClusterConnections}) unless $PACMain::UNITY;
    push(@m, {label => 'Favourites', stockicon => $PACMain::UNITY ? '' : 'asbru-favourite-on', submenu => _menuFavouriteConnections});
    push(@m, {label => 'Connect to', stockicon => 'asbru-group', submenu => _menuAvailableConnections($PACMain::FUNCS{_MAIN}{_GUI}{treeConnections}{data})});
    push(@m, {separator => 1});
    push(@m, {label => 'Preferences...', stockicon => 'gtk-preferences', code => sub {$$self{_MAIN}{_CONFIG}->show();} });
    push(@m, {label => 'Clusters...', stockicon => $PACMain::UNITY ? '' : 'gtk-justify-fill'    , code => sub {$$self{_MAIN}{_CLUSTER}->show();}  });
    push(@m, {label => 'PCC', stockicon => 'gtk-justify-fill', code => sub {$$self{_MAIN}{_PCC}->show();}});
    push(@m, {label => 'Show Window', stockicon => $PACMain::UNITY ? '' : 'gtk-home', code => sub {
        # Check if show password is required
        if ($$self{_MAIN}{_CFG}{'defaults'}{'use gui password'} && $$self{_MAIN}{_CFG}{'defaults'}{'use gui password tray'}) {
            # Trigger the "unlock" procedure
            $$self{_MAIN}{_GUI}{lockApplicationBtn}->set_status('passive');
            if (! $$self{_MAIN}{_GUI}{lockApplicationBtn}->get_active()) {
                $$self{_MAIN}{_CFG}{defaults}{'show tray icon'} ? $$self{_TRAY}->set_status('active') : $$self{_TRAY}->set_passive();
                $$self{_MAIN}->_showConnectionsList();
            }
        } else {
            $$self{_MAIN}{_CFG}{defaults}{'show tray icon'} ? $$self{_TRAY}->set_status('active') : $$self{_TRAY}->set_passive();
            $$self{_MAIN}->_showConnectionsList();
        }
    }});
    push(@m, {separator => 1});
    push(@m, {label => 'About', stockicon => 'gtk-about', code => sub {$$self{_MAIN}->_showAboutWindow();} });
    push(@m, {label => 'Exit', stockicon => 'gtk-quit', code => sub {$$self{_MAIN}->_quitProgram();} });

    $$self{_TRAY}->set_menu(_wPopUpMenu(\@m, $event, 'below calling widget', 'get_menu_ref'));

    return 1;
}

# END: Define PRIVATE CLASS functions
###################################################################

1;
