package PACPCC;

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
use Encode;

# GTK
use Gtk3 '-init';
eval {require Gtk3::SourceView2;};
my $SOURCEVIEW = ! $@;

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

my %LANG;
if ($SOURCEVIEW) {
    my $i = 0;
    $LANG{'name_to_id'}{' <NO HIGHLIGHT>'}{'id'} = ' <NO HIGHLIGHT>';
    $LANG{'name_to_id'}{' <NO HIGHLIGHT>'}{'n'} = $i;
    $LANG{'id_to_name'}{' <NO HIGHLIGHT>'}{'name'} = ' <NO HIGHLIGHT>';
    $LANG{'id_to_name'}{' <NO HIGHLIGHT>'}{'n'} = $i;
    my $LM = Gtk3::SourceView2::LanguageManager->get_default;
    foreach my $lang_id (sort {lc $a cmp lc $b} $LM->get_language_ids) {
        ++$i;
        my $name = $LM->get_language($lang_id)->get_name;
        $LANG{'name_to_id'}{$name}{id} = $lang_id;
        $LANG{'name_to_id'}{$name}{n} = $i;
        $LANG{'id_to_name'}{$lang_id}{name} = $name;
        $LANG{'id_to_name'}{$lang_id}{n} = $i;
    }
}

# END: Define GLOBAL CLASS variables
###################################################################

###################################################################
# START: Define PUBLIC CLASS methods

sub new {
    my $class = shift;
    my $self = {};

    $self->{_RUNNING} = shift;

    $self->{_CLUSTERS} = undef;
    $self->{_WINDOWPCC} = undef;
    $self->{_SELECTED} = '';

    $self->{_UNDO} = [];

    # Build the GUI
    _initGUI($self) or return 0;

    # Setup callbacks
    _setupCallbacks($self);

    # Autoload any text
    #if (($$self{_WINDOWPCC}{cbAutoSave}->get_active // 1) && (open(F, "$CFG_DIR/asbru.pcc") ))

    my @content;
    if (open(F,"<:utf8","$CFG_DIR/asbru.pcc") ) {
        @content = <F>;
        close F;

        if ((defined $content[0]) && ($content[0] =~ /^__PAC__PCC__LANG__(.+)$/go) ) {
            my $name = $1;
            shift @content;
            $$self{_WINDOWPCC}{comboLang}->set_active($LANG{'name_to_id'}{$name}{n} // 0);
        }

        if ((defined $content[0]) && ($content[0] =~ /^__PAC__PCC__POSITION__(\d+):(\d+)$/go) ) {
            ($$self{_X}, $$self{_Y}) = ($1, $2);
            shift @content;
            $$self{_WINDOWPCC}{main}->move($$self{_X}, $$self{_Y});
        }

        if ((defined $content[0]) && ($content[0] =~ /^__PAC__PCC__SIZE__(\d+):(\d+)$/go) ) {
            ($$self{_W}, $$self{_H}) = ($1, $2);
            shift @content;
            $$self{_WINDOWPCC}{main}->resize($$self{_W}, $$self{_H});
        }

        if ((defined $content[0]) && ($content[0] =~ /^__PAC__PCC__MULTILINE__$/go) ) {
            shift @content;
            $$self{_WINDOWPCC}{cbShowMultiText}->set_active(1);
        }
    }

    if ($$self{_WINDOWPCC}{cbAutoSave}->get_active // 1) {
        if ($SOURCEVIEW) {
            $$self{_WINDOWPCC}{multiTextBuffer}->begin_not_undoable_action;
            $$self{_WINDOWPCC}{multiTextBuffer}->set_text(join('', @content));
            $$self{_WINDOWPCC}{multiTextBuffer}->end_not_undoable_action;
            $$self{_WINDOWPCC}{multiTextBuffer}->set_modified(0);
        } else {
            $$self{_WINDOWPCC}{multiTextBuffer}->set_text(join('', @content));
        }
    }

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

    $$self{_WINDOWPCC}{main}->set_title("$APPNAME (v$APPVERSION): Power Cluster Controller");
    $$self{_WINDOWPCC}{main}->show_all;
    $$self{_WINDOWPCC}{main}->present;

    $self->_updateGUI;

    foreach my $cluster (keys %{$$self{_CLUSTERS}}) {
        foreach my $uuid (keys %{$$self{_CLUSTERS}{$cluster}}) {
            $$self{_RUNNING}{$uuid}{'terminal'}{_PROPAGATE} = ! $$self{_WINDOWPCC}{cbPreventSingle}->get_active;
        }
    }

    #$$self{_WINDOWPCC}{entryData}->grab_focus;

    return 1;
}

# END: Define PUBLIC CLASS methods
###################################################################

###################################################################
# START: Define PRIVATE CLASS functions

sub _initGUI {
    my $self = shift;

    $$self{_WINDOWPCC}{main} = Gtk3::Window->new;
    $$self{_WINDOWPCC}{main}->set_keep_above(1);
    $$self{_WINDOWPCC}{main}->set_icon_from_file($APPICON);
    $$self{_WINDOWPCC}{main}->set_resizable(0);
    $$self{_WINDOWPCC}{main}->set_border_width(2);

    my $vbox0 = Gtk3::VBox->new(0, 0);
    $$self{_WINDOWPCC}{main}->add($vbox0);

    $vbox0->pack_start(PACUtils::_createBanner('asbru-cluster.svg', 'Power Cluster Controller'), 0, 1, 0);

    my $vbox1 = Gtk3::VBox->new(0, 0);
    $vbox0->pack_start($vbox1, 0, 1, 0);

    my $hbox1 = Gtk3::HBox->new(0, 0);
    $vbox1->pack_start($hbox1, 0, 1, 0);

    my $lblSendTo = Gtk3::Label->new('Send to Cluster: ');
    $hbox1->pack_start($lblSendTo, 0, 1, 0);

    $$self{_WINDOWPCC}{comboTerminals} = Gtk3::ComboBoxText->new;
    $hbox1->pack_start($$self{_WINDOWPCC}{comboTerminals}, 1, 1, 0);
    $$self{_WINDOWPCC}{comboTerminals}->set('can_focus', 0);
    $$self{_WINDOWPCC}{comboTerminals}->set_tooltip_text('Selected cluster will be the one used to send the keystrokes and for both the "Explode" and "Close ALL" buttons');

    $$self{_WINDOWPCC}{cbSendToAll} = Gtk3::CheckButton->new_with_label('Send to ALL terminals');
    $hbox1->pack_start($$self{_WINDOWPCC}{cbSendToAll}, 0, 1, 0);
    $$self{_WINDOWPCC}{cbSendToAll}->set_active(0);
    $$self{_WINDOWPCC}{cbSendToAll}->set('can_focus', 0);
    $$self{_WINDOWPCC}{cbSendToAll}->set_tooltip_text('If checked, commands will be sent to *EVERY* terminal opened, either clustered or unclustered');

    $$self{_WINDOWPCC}{btnRestartAll} = Gtk3::Button->new_with_mnemonic('_Restart all');
    $hbox1->pack_start($$self{_WINDOWPCC}{btnRestartAll}, 0, 1, 0);
    $$self{_WINDOWPCC}{btnRestartAll}->set_tooltip_text("Restart (stop->start) *every* terminal in selected cluster");
    $$self{_WINDOWPCC}{btnRestartAll}->set_image(Gtk3::Image->new_from_stock('gtk-refresh', 'button') );
    $$self{_WINDOWPCC}{btnRestartAll}->set('can_focus', 0);

    $$self{_WINDOWPCC}{btnCloseAll} = Gtk3::Button->new_with_mnemonic('Close _ALL');
    $hbox1->pack_start($$self{_WINDOWPCC}{btnCloseAll}, 0, 1, 0);
    $$self{_WINDOWPCC}{btnCloseAll}->set_tooltip_text("Close *every* terminal in selected cluster");
    $$self{_WINDOWPCC}{btnCloseAll}->set_image(Gtk3::Image->new_from_stock('gtk-close', 'button') );
    $$self{_WINDOWPCC}{btnCloseAll}->set('can_focus', 0);

    $vbox1->pack_start(Gtk3::HSeparator->new, 1, 1, 0);

    $$self{_WINDOWPCC}{optsbox} = Gtk3::HBox->new(0, 0);
    $vbox1->pack_start($$self{_WINDOWPCC}{optsbox}, 0, 1, 0);

    $$self{_WINDOWPCC}{cbPreventSingle} = Gtk3::CheckButton->new_with_label('Prevent single window keys broadcast');
    $$self{_WINDOWPCC}{optsbox}->pack_start($$self{_WINDOWPCC}{cbPreventSingle}, 0, 1, 0);
    $$self{_WINDOWPCC}{cbPreventSingle}->set_active(1);
    $$self{_WINDOWPCC}{cbPreventSingle}->set('can_focus', 0);
    $$self{_WINDOWPCC}{cbPreventSingle}->set_tooltip_text('If checked, any kestroke over a single connection will not be propagated to the rest of the elements of the selected cluster');

    $$self{_WINDOWPCC}{cbAlwaysOnTop} = Gtk3::CheckButton->new_with_label('PCC Window Always on top');
    $$self{_WINDOWPCC}{optsbox}->pack_start($$self{_WINDOWPCC}{cbAlwaysOnTop}, 0, 1, 0);
    $$self{_WINDOWPCC}{cbAlwaysOnTop}->set_active(1);
    $$self{_WINDOWPCC}{cbAlwaysOnTop}->set('can_focus', 0);
    $$self{_WINDOWPCC}{cbAlwaysOnTop}->set_tooltip_text('If checked, this window will always stay on top (over) the rest of windows');

    $$self{_WINDOWPCC}{cbShowMultiText} = Gtk3::CheckButton->new_with_label('Use Multi-Line Text Entry');
    $$self{_WINDOWPCC}{optsbox}->pack_start($$self{_WINDOWPCC}{cbShowMultiText}, 0, 1, 0);
    $$self{_WINDOWPCC}{cbShowMultiText}->set_active(0);
    $$self{_WINDOWPCC}{cbShowMultiText}->set('can_focus', 0);
    $$self{_WINDOWPCC}{cbShowMultiText}->set_tooltip_text('If checked, you will have a bigger text entry to write your commands, ready to be sent to the selected cluster all at once when clicking on any of the buttons below');

    $vbox1->pack_start(Gtk3::HSeparator->new, 1, 1, 0);

    $$self{_WINDOWPCC}{hboxData} = Gtk3::HBox->new(0, 0);
    $vbox1->pack_start($$self{_WINDOWPCC}{hboxData}, 0, 1, 0);

    $$self{_WINDOWPCC}{lblData} = Gtk3::Label->new('Type commands here: ');
    $$self{_WINDOWPCC}{hboxData}->pack_start($$self{_WINDOWPCC}{lblData}, 0, 1, 0);

    $$self{_WINDOWPCC}{entryData} = Gtk3::Entry->new;
    $$self{_WINDOWPCC}{hboxData}->pack_start($$self{_WINDOWPCC}{entryData}, 1, 1, 0);
    $$self{_WINDOWPCC}{entryData}->set_icon_from_stock('primary', 'gtk-edit');
    $$self{_WINDOWPCC}{entryData}->drag_dest_unset;

    $$self{_WINDOWPCC}{cbApplyOnIntro} = Gtk3::CheckButton->new_with_label('Send on <INTRO>');
    $$self{_WINDOWPCC}{hboxData}->pack_start($$self{_WINDOWPCC}{cbApplyOnIntro}, 0, 1, 0);
    $$self{_WINDOWPCC}{cbApplyOnIntro}->set_active(0);
    $$self{_WINDOWPCC}{cbApplyOnIntro}->set('can_focus', 0);
    $$self{_WINDOWPCC}{cbApplyOnIntro}->set_tooltip_text("If checked, keypresses will appear here, and will be sent on <INTRO> keypress\nOther else, they will not be echoed out, but sent each of them instantly");

    $vbox1->pack_start(Gtk3::HSeparator->new, 0, 1, 0);

    $$self{_WINDOWPCC}{vboxMultiText} = Gtk3::VBox->new(0, 0);
    $vbox0->pack_start($$self{_WINDOWPCC}{vboxMultiText}, 1, 1, 0);

    my $hbTextBtn = Gtk3::HBox->new(0, 0);
    $$self{_WINDOWPCC}{vboxMultiText}->pack_start($hbTextBtn, 0, 0, 3);

    $$self{_WINDOWPCC}{btnLoadFile} = Gtk3::Button->new_with_mnemonic('_Open');
    $$self{_WINDOWPCC}{btnLoadFile}->set_tooltip_text('Load a text file');
    $$self{_WINDOWPCC}{btnLoadFile}->set_image(Gtk3::Image->new_from_stock('gtk-open', 'button') );
    $$self{_WINDOWPCC}{btnLoadFile}->set('can_focus', 0);
    $hbTextBtn->pack_start($$self{_WINDOWPCC}{btnLoadFile}, 0, 0, 5);

    $$self{_WINDOWPCC}{btnSaveAsFile} = Gtk3::Button->new_with_mnemonic('_Save as...');
    $$self{_WINDOWPCC}{btnSaveAsFile}->set_tooltip_text('Save as a text file');
    $$self{_WINDOWPCC}{btnSaveAsFile}->set_image(Gtk3::Image->new_from_stock('gtk-save-as', 'button') );
    $$self{_WINDOWPCC}{btnSaveAsFile}->set('can_focus', 0);
    $hbTextBtn->pack_start($$self{_WINDOWPCC}{btnSaveAsFile}, 0, 0, 5);

    $$self{_WINDOWPCC}{cbAutoSave} = Gtk3::CheckButton->new_with_label('Auto save/load...');
    $$self{_WINDOWPCC}{cbAutoSave}->set_tooltip_text('Automatically save/load current text');
    $$self{_WINDOWPCC}{cbAutoSave}->set('can_focus', 0);
    $$self{_WINDOWPCC}{cbAutoSave}->set_active($PACMain::FUNCS{_MAIN}{_CFG}{'defaults'}{'autosave PCC text'} // 1);
    $hbTextBtn->pack_start($$self{_WINDOWPCC}{cbAutoSave}, 0, 0, 0);

    $hbTextBtn->pack_start(Gtk3::VSeparator->new, 0, 1, 0);

    $hbTextBtn->pack_start(Gtk3::Label->new('Syntax highlight: '), 0, 0, 5);

    $$self{_WINDOWPCC}{comboLang} = Gtk3::ComboBoxText->new;
    $hbTextBtn->pack_start($$self{_WINDOWPCC}{comboLang}, 0, 0, 5);
    $$self{_WINDOWPCC}{btnSaveAsFile}->set_tooltip_text('Force selected language for syntax highlighting');
    if ($SOURCEVIEW) {
        $$self{_WINDOWPCC}{comboLang}->append_text($LANG{'id_to_name'}{$_}{'name'})
        foreach sort {lc $a cmp lc $b} keys %{$LANG{'id_to_name'}};
    }
    $$self{_WINDOWPCC}{comboLang}->set_active(0);
    $$self{_WINDOWPCC}{comboLang}->set_sensitive($SOURCEVIEW);

    $hbTextBtn->pack_start(Gtk3::VSeparator->new, 0, 1, 0);

    $$self{_WINDOWPCC}{btnClearFile} = Gtk3::Button->new_with_mnemonic('Clea_r');
    $$self{_WINDOWPCC}{btnClearFile}->set_tooltip_text('Clear out all the data from the edit box');
    $$self{_WINDOWPCC}{btnClearFile}->set_image(Gtk3::Image->new_from_stock('gtk-clear', 'button') );
    $$self{_WINDOWPCC}{btnClearFile}->set('can_focus', 0);
    $hbTextBtn->pack_start($$self{_WINDOWPCC}{btnClearFile}, 0, 0, 5);

    $$self{_WINDOWPCC}{vboxMultiText}->pack_start(Gtk3::HSeparator->new, 0, 1, 0);

    # Create a scrolled2 scrolled window to contain the description textview
    $$self{_WINDOWPCC}{scrollMultiText} = Gtk3::ScrolledWindow->new;
    $$self{_WINDOWPCC}{vboxMultiText}->pack_start($$self{_WINDOWPCC}{scrollMultiText}, 1, 1, 0);
    $$self{_WINDOWPCC}{scrollMultiText}->set_policy('automatic', 'automatic');

    # Create descView as a gtktextview with descBuffer
    if ($SOURCEVIEW) {
        $$self{_WINDOWPCC}{multiTextBuffer} = Gtk3::SourceView2::Buffer->new(undef);
        $$self{_WINDOWPCC}{multiTextView} = Gtk3::SourceView2::View->new_with_buffer($$self{_WINDOWPCC}{multiTextBuffer});
        $$self{_WINDOWPCC}{multiTextView}->set_show_line_numbers(1);
        $$self{_WINDOWPCC}{multiTextView}->set_tab_width(4);
        $$self{_WINDOWPCC}{multiTextView}->set_indent_on_tab(1);
        $$self{_WINDOWPCC}{multiTextView}->set_highlight_current_line(1);
        $$self{_WINDOWPCC}{multiTextView}->modify_font(Pango::FontDescription::from_string('monospace') );
    } else {
        $$self{_WINDOWPCC}{multiTextBuffer} = Gtk3::TextBuffer->new;
        $$self{_WINDOWPCC}{multiTextView} = Gtk3::TextView->new_with_buffer($$self{_WINDOWPCC}{multiTextBuffer});
    }

    $$self{_WINDOWPCC}{multiTextView}->set_border_width(5);
    $$self{_WINDOWPCC}{multiTextView}->set_size_request(320, 100);
    $$self{_WINDOWPCC}{scrollMultiText}->add($$self{_WINDOWPCC}{multiTextView});
    $$self{_WINDOWPCC}{multiTextView}->set_wrap_mode('GTK_WRAP_WORD');
    $$self{_WINDOWPCC}{multiTextView}->set_sensitive(1);
    $$self{_WINDOWPCC}{multiTextView}->set('can_focus', 1);
    #$$self{_WINDOWPCC}{multiTextView}->set_tooltip_text('Write here your commands, and execute them in the selected cluster by pressing any of the buttons below');

    $$self{_WINDOWPCC}{frameExec} = Gtk3::Frame->new(' Execute: ');
    $$self{_WINDOWPCC}{vboxMultiText}->pack_start($$self{_WINDOWPCC}{frameExec}, 0, 1, 0);
    $$self{_WINDOWPCC}{frameExec}->set_shadow_type('etched-in');

    my $hbbox0 = Gtk3::HBox->new(1, 0);
    $$self{_WINDOWPCC}{frameExec}->add($hbbox0);

    $$self{_WINDOWPCC}{btnAll} = Gtk3::Button->new_with_mnemonic('A_ll');
    $$self{_WINDOWPCC}{btnAll}->set_tooltip_text('Send the *all* the text to cluster (<Ctrl><INTRO>)');
    $$self{_WINDOWPCC}{btnAll}->set_image(Gtk3::Image->new_from_stock('gtk-media-play', 'button') );
    $$self{_WINDOWPCC}{btnAll}->set('can_focus', 0);
    $hbbox0->pack_start($$self{_WINDOWPCC}{btnAll}, 0, 1, 0);
    $$self{_WINDOWPCC}{btnBlock} = Gtk3::Button->new_with_mnemonic('_Block');
    $$self{_WINDOWPCC}{btnBlock}->set_tooltip_text('Send current *block* text (that separated with blank lines up and down from the cursor position) to cluster (<Alt><INTRO>)');
    $$self{_WINDOWPCC}{btnBlock}->set_image(Gtk3::Image->new_from_stock('gtk-indent', 'button') );
    $$self{_WINDOWPCC}{btnBlock}->set('can_focus', 0);
    $hbbox0->pack_start($$self{_WINDOWPCC}{btnBlock}, 0, 1, 0);
    $$self{_WINDOWPCC}{btnSelection} = Gtk3::Button->new_with_mnemonic('_Selection');
    $$self{_WINDOWPCC}{btnSelection}->set_tooltip_text('Send the *selected* text to cluster');
    $$self{_WINDOWPCC}{btnSelection}->set_image(Gtk3::Image->new_from_stock('gtk-select-all', 'button') );
    $$self{_WINDOWPCC}{btnSelection}->set('can_focus', 0);
    $hbbox0->pack_start($$self{_WINDOWPCC}{btnSelection}, 0, 1, 0);
    $$self{_WINDOWPCC}{cbSubstitute} = Gtk3::CheckButton->new_with_label('Use Ásbrú variables');
    $$self{_WINDOWPCC}{cbSubstitute}->set_tooltip_text('Allow Ásbrú to replace standard known variables (ie: <GV:var_name>, <CMD:command>, ...)');
    $$self{_WINDOWPCC}{cbSubstitute}->set_active(1);
    $$self{_WINDOWPCC}{cbSubstitute}->set('can_focus', 0);
    $hbbox0->pack_start($$self{_WINDOWPCC}{cbSubstitute}, 0, 1, 0);

    $$self{_WINDOWPCC}{vboxMultiText}->pack_start(Gtk3::HSeparator->new, 0, 1, 0);

    my $hbbox1 = Gtk3::HButtonBox->new;
    $vbox0->pack_start($hbbox1, 0, 1, 5);

    $$self{_WINDOWPCC}{btnClose} = Gtk3::Button->new_from_stock('gtk-close');
    $$self{_WINDOWPCC}{btnClose}->set('can_focus', 0);
    $$self{_WINDOWPCC}{btnClusterAdmin} = Gtk3::Button->new_with_mnemonic('Cl_usters');
    $$self{_WINDOWPCC}{btnClusterAdmin}->set('can_focus', 0);
    $$self{_WINDOWPCC}{btnClusterAdmin}->set_image(Gtk3::Image->new_from_stock('asbru-cluster-manager', 'button') );
    $$self{_WINDOWPCC}{btnSeparate} = Gtk3::Button->new_with_mnemonic('_Explode');
    $$self{_WINDOWPCC}{btnSeparate}->set('can_focus', 0);
    $$self{_WINDOWPCC}{btnSeparate}->set_tooltip_text("Separate and resize clustered windows to fit screen");
    $$self{_WINDOWPCC}{btnSeparate}->set_image(Gtk3::Image->new_from_stock('gtk-fullscreen', 'button') );
    $$self{_WINDOWPCC}{btnReTab} = Gtk3::Button->new_with_mnemonic('Re_Tab');
    $$self{_WINDOWPCC}{btnReTab}->set('can_focus', 0);
    $$self{_WINDOWPCC}{btnReTab}->set_tooltip_text("Put every independent connection window in PAC's main TAB");
    $$self{_WINDOWPCC}{btnReTab}->set_image(Gtk3::Image->new_from_stock('gtk-leave-fullscreen', 'button') );
    $$self{_WINDOWPCC}{btnShowPipe} = Gtk3::Button->new_with_mnemonic('_Piped Output');
    $$self{_WINDOWPCC}{btnShowPipe}->set('can_focus', 0);
    $$self{_WINDOWPCC}{btnShowPipe}->set_tooltip_text("Show the window with the locally piped data");
    $$self{_WINDOWPCC}{btnShowPipe}->set_image(Gtk3::Image->new_from_stock('gtk-index', 'button') );
    $hbbox1->set_layout('GTK_BUTTONBOX_EDGE');
    $hbbox1->add($$self{_WINDOWPCC}{btnShowPipe});
    $hbbox1->add($$self{_WINDOWPCC}{btnSeparate});
    $hbbox1->add($$self{_WINDOWPCC}{btnReTab});
    $hbbox1->add($$self{_WINDOWPCC}{btnClusterAdmin});
    $hbbox1->add($$self{_WINDOWPCC}{btnClose});

    return 1;
}

sub _setupCallbacks {
    my $self = shift;

    ###############################
    # CLUSTERS RELATED CALLBACKS
    ###############################

    $$self{_WINDOWPCC}{entryData}->signal_connect('button_release_event' => sub {
        my ($widget, $event) = @_;
        if ($event->button ne 2) {
            return 0;
        }
        if ($$self{_WINDOWPCC}{cbApplyOnIntro}->get_active) {
            return 1;
        }
        # Get the pasted text
        my $text = $$self{_WINDOWPCC}{entryData}->get_chars(0, -1);

        # Empty the entryBox
        $$self{_WINDOWPCC}{entryData}->set_text('');

        my $cluster = $$self{_WINDOWPCC}{comboTerminals}->get_active_text // '';

        foreach my $uuid (keys %{$$self{_RUNNING}}) {
            my $connected = $$self{_RUNNING}{$uuid}{'terminal'}{'CONNECTED'};
            my $this_cluster = $$self{_RUNNING}{$uuid}{'terminal'}{'_CLUSTER'} // '';
            my $vte = $$self{_RUNNING}{$uuid}{'terminal'}{'_GUI'}{_VTE};

            if (!((defined $vte) && ((($cluster ne '') && ($this_cluster eq $cluster) ) || $$self{_WINDOWPCC}{cbSendToAll}->get_active))) {
                next;
            }
            $$self{_RUNNING}{$uuid}{'terminal'}{_LISTEN_COMMIT} = 0;
            _vteFeedChild($$self{_RUNNING}{$uuid}{'terminal'}{_GUI}{_VTE}, $text);
            $$self{_RUNNING}{$uuid}{'terminal'}{_LISTEN_COMMIT} = 1;
        }
        return 1;
    });

    $$self{_WINDOWPCC}{cbApplyOnIntro}->signal_connect('toggled' => sub {$$self{_WINDOWPCC}{entryData}->set_text('') unless $$self{_WINDOWPCC}{cbApplyOnIntro}->get_active;});

    $$self{_WINDOWPCC}{comboTerminals}->signal_connect('changed' => sub {
        ($$self{_WINDOWPCC}{cbShowMultiText}->get_active ? $$self{_WINDOWPCC}{multiTextView} : $$self{_WINDOWPCC}{entryData})->grab_focus;
    }) ;

    # Capture every 'key press' and send it to every terminal in the cluster
    $$self{_WINDOWPCC}{entryData}->signal_connect('key_press_event' => sub {
        my ($widget, $event) = @_;
        my $cluster = $$self{_WINDOWPCC}{comboTerminals}->get_active_text // '';

        if ($$self{_WINDOWPCC}{cbApplyOnIntro}->get_active) {
            # Return unless INTRO is pressed
            if ($event->keyval != 65293) {
                return 0;
            }
            my $txt = $$self{_WINDOWPCC}{entryData}->get_text;
            $$self{_WINDOWPCC}{entryData}->set_text('');
            $self->_execOnClusterTerminals($txt, 1);

            # Return 'TRUE' to prevent the characters from appearing in the entry box
            return 1;
        }

        foreach my $uuid (keys %{$$self{_RUNNING}}) {
            my $connected = $$self{_RUNNING}{$uuid}{'terminal'}{'CONNECTED'};
            my $this_cluster = $$self{_RUNNING}{$uuid}{'terminal'}{'_CLUSTER'} // '';
            my $vte = $$self{_RUNNING}{$uuid}{'terminal'}{'_GUI'}{_VTE};

            if (!((defined $vte) && ((($cluster ne '') && ($this_cluster eq $cluster) ) || $$self{_WINDOWPCC}{cbSendToAll}->get_active))) {
                next;
            }
            $$self{_RUNNING}{$uuid}{'terminal'}{_LISTEN_COMMIT} = 0;
            $vte->signal_emit('key_press_event', $event);
            $$self{_RUNNING}{$uuid}{'terminal'}{_LISTEN_COMMIT} = 1;
        }

        # Return 'TRUE' to prevent the characters from appearing in the entry box
        return 1;
    });

     # Capture 'send to all' checkbox state change
    $$self{_WINDOWPCC}{cbSendToAll}->signal_connect('toggled' => sub {$$self{_WINDOWPCC}{comboTerminals}->set_sensitive(! $$self{_WINDOWPCC}{cbSendToAll}->get_active);});

    # Capture 'key propagation' checkbox state change
    $$self{_WINDOWPCC}{cbPreventSingle}->signal_connect('toggled' => sub {
        foreach my $cluster (keys %{$$self{_CLUSTERS}}) {
            foreach my $uuid (keys %{$$self{_CLUSTERS}{$cluster}}) {
                $$self{_RUNNING}{$uuid}{'terminal'}{_PROPAGATE} = ! $$self{_WINDOWPCC}{cbPreventSingle}->get_active;
            }
        }
    });

    # Capture 'always on top' checkbox state change
    $$self{_WINDOWPCC}{cbAlwaysOnTop}->signal_connect('toggled' => sub {
        $$self{_WINDOWPCC}{main}->set_keep_above($$self{_WINDOWPCC}{cbAlwaysOnTop}->get_active);
    });

    # Capture 'show text box' checkbox state change
    $$self{_WINDOWPCC}{cbShowMultiText}->signal_connect('toggled' => sub {
        if ($$self{_WINDOWPCC}{cbShowMultiText}->get_active) {
            $$self{_WINDOWPCC}{hboxData}->hide;
            $$self{_WINDOWPCC}{main}->set_resizable(1);
            $$self{_WINDOWPCC}{vboxMultiText}->show_all;
            $$self{_WINDOWPCC}{hboxData}->set_sensitive(0);
            $$self{_WINDOWPCC}{multiTextView}->grab_focus;

            $$self{_WINDOWPCC}{main}->resize($$self{_W} // 300, $$self{_H} // 200);
        } else {
            $$self{_WINDOWPCC}{hboxData}->show;
            $$self{_WINDOWPCC}{main}->set_resizable(0);
            $$self{_WINDOWPCC}{vboxMultiText}->hide;
            $$self{_WINDOWPCC}{hboxData}->set_sensitive(1);
            $$self{_WINDOWPCC}{entryData}->grab_focus;
        }
    });

    ###############################
    # MULTI-TEXT RELATED CALLBACKS
    ###############################

    $$self{_WINDOWPCC}{multiTextView}->signal_connect('button_release_event' => sub {
        my ($widget, $event) = @_;
        if ($event->button ne 1) {
            return 0;
        }
        $$self{_WINDOWPCC}{btnSelection}->set_sensitive($$self{_WINDOWPCC}{multiTextView}->get_clipboard(Gtk3::Gdk::Atom::intern_static_string('PRIMARY') )->wait_is_text_available());
        $$self{_WINDOWPCC}{btnBlock}->set_sensitive($self->_getCurrentBlock($$self{_WINDOWPCC}{multiTextBuffer}) );
        return 0;
    });

    $$self{_WINDOWPCC}{multiTextView}->signal_connect('key_release_event' => sub {
        $$self{_WINDOWPCC}{btnSelection}->set_sensitive($$self{_WINDOWPCC}{multiTextView}->get_clipboard(Gtk3::Gdk::Atom::intern_static_string('PRIMARY') )->wait_is_text_available());
        $$self{_WINDOWPCC}{btnBlock}->set_sensitive($self->_getCurrentBlock($$self{_WINDOWPCC}{multiTextBuffer}) );
        return 0;
    });

    # Asign a callback to populate this textview with its own context menu
    $$self{_WINDOWPCC}{multiTextView}->signal_connect('button_press_event' => sub {
        my ($widget, $event) = @_;

        if ($event->button ne 3) {
            return 0;
        }

        my @menu_items;

        # Populate with global defined variables
        my @global_variables_menu;
        foreach my $var (sort {$a cmp $b} keys %{$PACMain::FUNCS{_MAIN}{_CFG}{'defaults'}{'global variables'}}) {
            my $val = $PACMain::FUNCS{_MAIN}{_CFG}{'defaults'}{'global variables'}{$var}{'value'};
            push(@global_variables_menu,
            {
                label => "<GV:$var> ($val)",
                code => sub {$$self{_WINDOWPCC}{multiTextBuffer}->insert_at_cursor("<GV:$var>");}
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
        foreach my $key (sort {$a cmp $b} keys %ENV) {
            # Do not offer Master Password, or any other environment variable with word PRIVATE, TOKEN
            if ($key =~ /KPXC|PRIVATE|TOKEN/i) {
                next;
            }
            my $value = $ENV{$key};
            push(@environment_menu,
            {
                label => "<ENV:$key>",
                tooltip => "$key=$value",
                code => sub {$$self{_WINDOWPCC}{multiTextBuffer}->insert_at_cursor("<ENV:$key>");}
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
            code => sub {$$self{_WINDOWPCC}{multiTextBuffer}->insert_at_cursor("<ASK:change_by_number>");}
        });

        # Populate with <ASK:*|> special string
        push(@menu_items,
        {
            label => 'Interactive user choose from list',
            tooltip => 'User will be prompted to choose a value form a user defined list separated with "|" (pipes without quotes)',
            code => sub {$$self{_WINDOWPCC}{multiTextBuffer}->insert_at_cursor('<ASK:descriptive_line|opt1|opt1|...|optN>');}
        });

        # Populate with <CMD:*> special string
        push(@menu_items,
        {
            label => 'Use a command output as value',
            tooltip => 'The given command line will be locally executed, and its output (both STDOUT and STDERR) will be used to replace this value',
            code => sub {$$self{_WINDOWPCC}{multiTextBuffer}->insert_at_cursor('<CMD:command_to_launch>');}
        });

        # Populate with <TEE:*> special string
        push(@menu_items,
        {
            label => 'Tee remote output to a local file',
            tooltip => 'The given command line will be executed, and its output will be saved in provided file (after TEE:...) LOCALLY',
            code => sub {$$self{_WINDOWPCC}{multiTextBuffer}->insert_at_cursor('<TEE:local_file>');}
        });

        # Populate with <PIPE:*> special string
        push(@menu_items,
        {
            label => 'Pipe remote output throught local command',
            tooltip => 'The given command line will be remotely executed, and its output will be piped throught the provide command (after PIPE:...) LOCALLY',
            code => sub {$$self{_WINDOWPCC}{multiTextBuffer}->insert_at_cursor('<PIPE:local_command_to_pipe_through[:pattern_to_expect_at_the_end_of_the_remote_command]>');}
        });

        # Populate with <KPXRE...*> special string
        push(@menu_items,
        {
            label => "KeePass Extended Query",
            tooltip => "This allows you to select the value to be returned, based on another value's match againt a Perl Regular Expression",
            code => sub {$$self{_WINDOWPCC}{multiTextBuffer}->insert_at_cursor("<KPXRE_GET_(title|username|password|url)_WHERE_(title|username|password|url)==Your_RegExp_here==>");}
        });

        _wPopUpMenu(\@menu_items, $event);

        return 1;
    });

    # Capture <ctrl><z> for undo
    $$self{_WINDOWPCC}{multiTextView}->signal_connect('key_press_event' => sub {
        my ($widget, $event) = @_;

        my $keyval = Gtk3::Gdk::keyval_name($event->keyval);
        my $unicode = Gtk3::Gdk::keyval_to_unicode($event->keyval); # 0 if not a character
        my $state = $event->get_state;
        my $ctrl = $state * ['control-mask'];
        my $shift = $state * ['shift-mask'];
        my $alt = $state * ['mod1-mask'];

        if ($alt && (($keyval eq 'Return') || ($keyval eq 'KP_Enter'))) {
            $$self{_WINDOWPCC}{btnBlock}->clicked;
        } elsif ($ctrl && (($keyval eq 'Return') || ($keyval eq 'KP_Enter'))) {
            $$self{_WINDOWPCC}{btnAll}->clicked;
        } elsif ($ctrl && (lc $keyval eq 'y') && $SOURCEVIEW) {
            $$self{_WINDOWPCC}{multiTextBuffer}->redo if $$self{_WINDOWPCC}{multiTextBuffer}->can_redo;
        } elsif ($ctrl && (lc $keyval eq 'z') && !$SOURCEVIEW && (scalar @{$$self{_UNDO}})) {
            $$self{_WINDOWPCC}{multiTextBuffer}->set_text(pop(@{$$self{_UNDO}}));
        } else {
            return 0;
        }
        return 1;
    });

    # Capture 'btnAll' button click
    $$self{_WINDOWPCC}{btnAll}->signal_connect('clicked' => sub {
        my ($widget, $event) = @_;

        my $txtAll = $$self{_WINDOWPCC}{multiTextBuffer}->get_property('text') // '';
        $self->_execOnClusterTerminals($txtAll);

        return 1;
    });

    # Capture 'btnBlock' button click
    $$self{_WINDOWPCC}{btnBlock}->signal_connect('clicked' => sub {
        my ($widget, $event) = @_;

        my $txtBlock = $self->_getCurrentBlock($$self{_WINDOWPCC}{multiTextBuffer}) or return 1;
        $self->_execOnClusterTerminals($txtBlock);

        return 1;
    });

    # Capture 'btnSelection' button click
    $$self{_WINDOWPCC}{btnSelection}->signal_connect('clicked' => sub {
        my ($widget, $event) = @_;

        my ($sel_start, $sel_end) = $$self{_WINDOWPCC}{multiTextBuffer}->get_selection_bounds;
        $sel_start && $sel_end or return 1;
        my $txtSelection = $$self{_WINDOWPCC}{multiTextBuffer}->get_text($sel_start, $sel_end, 0);

        $self->_execOnClusterTerminals($txtSelection);

        return 1;
    });

    ###############################
    # OTHER CALLBACKS
    ###############################

    # Capture text changes on multitext widget
    $SOURCEVIEW or $$self{_WINDOWPCC}{multiTextBuffer}->signal_connect('begin_user_action' => sub {
        push(@{$$self{_UNDO}}, $$self{_WINDOWPCC}{multiTextBuffer}->get_property('text') );
        return 0;
    });

    $$self{_WINDOWPCC}{btnLoadFile}->signal_connect('clicked' => sub {
        my $choose = Gtk3::FileChooserDialog->new(
            "$APPNAME (v.$APPVERSION) Choose a text file to load",
            $$self{_WINDOWPCC}{main},
            'GTK_FILE_CHOOSER_ACTION_OPEN',
            'Open' , 'GTK_RESPONSE_ACCEPT',
            'Cancel' , 'GTK_RESPONSE_CANCEL',
        );
        $choose->set_current_folder($ENV{'HOME'} // '/tmp');

        my $out = $choose->run;
        my $file = $choose->get_filename;
        $choose->destroy;
        if ($out ne 'accept') {
            return 1;
        }

        # Guess the programming language of the file
        $SOURCEVIEW and $$self{_WINDOWPCC}{multiTextBuffer}->set_language(Gtk3::SourceView2::LanguageManager->get_default->guess_language($file) );

        # Loading a file should not be undoable.
        my $content = '';
        if (!open(F,"<:utf8",$file)) {
            _wMessage($$self{_WINDOWPCC}{main}, "ERROR: Can not open for reading '$file' ($!)");
            return 1;
        }
        while (my $line = <F>) {
            $content .= $line;
        }
        close F;

        if ($SOURCEVIEW) {
            $$self{_WINDOWPCC}{multiTextBuffer}->begin_not_undoable_action;
            $$self{_WINDOWPCC}{multiTextBuffer}->set_text($content);
            if ($$self{_WINDOWPCC}{multiTextBuffer}->get_text($$self{_WINDOWPCC}{multiTextBuffer}->get_start_iter, $$self{_WINDOWPCC}{multiTextBuffer}->get_end_iter, 0) eq '') {
                _wMessage($$self{_WINDOWPCC}{main}, "WARNING: file '$file' is " . (-z $file ? 'empty' : 'not a valid text file!') );
            }
            $$self{_WINDOWPCC}{multiTextBuffer}->end_not_undoable_action;
            $$self{_WINDOWPCC}{multiTextBuffer}->set_modified(0);
            $$self{_WINDOWPCC}{multiTextBuffer}->place_cursor($$self{_WINDOWPCC}{multiTextBuffer}->get_start_iter);

            my $manager = Gtk3::SourceView2::LanguageManager->get_default;
            my $language = $manager->guess_language($file);
            my $n = defined $language ? $LANG{'name_to_id'}{$language->get_name // ' <NO HIGHLIGHT>'}{n} : 0;

            $$self{_WINDOWPCC}{comboLang}->set_active($n);
        } else {
            $$self{_WINDOWPCC}{multiTextBuffer}->set_text($content);
        }

        return 1;
    });

    $$self{_WINDOWPCC}{btnSaveAsFile}->signal_connect('clicked' => sub {
        my $choose = Gtk3::FileChooserDialog->new(
            "$APPNAME (v.$APPVERSION) Choose a file to save",
            $$self{_WINDOWPCC}{main},
            'GTK_FILE_CHOOSER_ACTION_OPEN',
            'Save' , 'GTK_RESPONSE_ACCEPT',
            'Cancel' , 'GTK_RESPONSE_CANCEL',
        );
        $choose->set_do_overwrite_confirmation(1);
        $choose->set_current_folder($ENV{'HOME'} // '/tmp');

        my $out = $choose->run;
        my $file = $choose->get_filename;
        $choose->destroy;
        if ($out ne 'accept') {
            return 1;
        }

        # Loading a file should not be undoable.
        if (!open(F,">:utf8",$file)) {
            _wMessage($$self{_WINDOWPCC}{main}, "ERROR: Can not open for writting '$file' ($!)");
            return 1;
        }
        print F $$self{_WINDOWPCC}{multiTextBuffer}->get_text($$self{_WINDOWPCC}{multiTextBuffer}->get_start_iter, $$self{_WINDOWPCC}{multiTextBuffer}->get_end_iter, 0);
        close F;

        if ($SOURCEVIEW) {
            # Guess the programming language of the file
            $$self{_WINDOWPCC}{multiTextBuffer}->set_language(Gtk3::SourceView2::LanguageManager->get_default->guess_language($file) );
            my $manager = Gtk3::SourceView2::LanguageManager->get_default;
            my $language = $manager->guess_language($file);
            my $n = defined $language ? $LANG{'name_to_id'}{$language->get_name // ' <NO HIGHLIGHT>'}{n} : 0;
            $$self{_WINDOWPCC}{comboLang}->set_active($n);
        }
        _wMessage($$self{_WINDOWPCC}{main}, "Correctly saved file '$file'");
        return 1;
    });

    $$self{_WINDOWPCC}{btnClearFile}->signal_connect('clicked' => sub {$$self{_WINDOWPCC}{multiTextBuffer}->set_text('')});

    $SOURCEVIEW and $$self{_WINDOWPCC}{comboLang}->signal_connect('changed' => sub {
        my $lang = $$self{_WINDOWPCC}{comboLang}->get_active_text // return 0;
        my $id = $LANG{'name_to_id'}{$lang}{'id'};
        $$self{_WINDOWPCC}{multiTextBuffer}->set_language($lang eq ' <NO HIGHLIGHT>' ? undef : Gtk3::SourceView2::LanguageManager->get_default->get_language($id) );
        return 0;
    });

    # Capture 'Cluster admin' button clicked
    $$self{_WINDOWPCC}{btnClusterAdmin}->signal_connect('clicked' => sub {
        $$self{_WINDOWPCC}{main}->hide;
        $PACMain::FUNCS{_CLUSTER}->show;
        return 1;
    });

    $$self{_WINDOWPCC}{btnRestartAll}->signal_connect('clicked' => sub {
        my $cluster = $$self{_WINDOWPCC}{comboTerminals}->get_active_text // '';
        my @list = keys %{$$self{_WINDOWPCC}{cbSendToAll}->get_active ? $$self{_RUNNING} : $$self{_CLUSTERS}{$cluster}};
        return 1 unless scalar(@list) && _wConfirm($$self{_WINDOWPCC}{main}, "Are you sure you want to RESTART <b>every</b> terminal" . ($cluster ne '' ? " in cluster '$cluster'" : '') . "?");
        foreach my $uuid (@list) {
            kill(15, $$self{_RUNNING}{$uuid}{'terminal'}{_PID}) if ($$self{_RUNNING}{$uuid}{'terminal'}{_PID} // 0);
            $$self{_RUNNING}{$uuid}{'terminal'}->start;
        }
        return 1;
    });

    # Capture 'Explode' button clicked
    $$self{_WINDOWPCC}{btnSeparate}->signal_connect('clicked' => sub {
        my $screen = Gtk3::Gdk::Screen::get_default();
        my $sw = $screen->get_width();
        my $sh = $screen->get_height() - 100;
        my $cluster = $$self{_WINDOWPCC}{comboTerminals}->get_active_text() // '';
        my $total = scalar(keys %{$$self{_WINDOWPCC}{cbSendToAll}->get_active() ? $$self{_RUNNING} : $$self{_CLUSTERS}{$cluster}}) or return 1;

        my $conns_per_row = $total < 5 ? 2 : 3;
        my $rows = POSIX::ceil($total / $conns_per_row) || 1;
        my $defw = int($sw / (POSIX::ceil($total / $rows)));
        my $defh = int($sh / (POSIX::ceil($total / $rows)));


        my $col = 0;
        my $row = 0;
        my @list = keys %{$$self{_WINDOWPCC}{cbSendToAll}->get_active() ? $$self{_RUNNING} : $$self{_CLUSTERS}{$cluster}};
        foreach my $uuid (@list) {
            my $terminal = $$self{_RUNNING}{$uuid}{'terminal'};

            # Check that these are valid terminals
            if (!defined($$self{_RUNNING}{$uuid}{terminal})) {
                next;
            }
            if (ref($$self{_RUNNING}{$uuid}{terminal}) !~ /^PACTerminal|PACShell$/go) {
                next;
            }

            if ($col == $conns_per_row) {
                $row++; $col = 0;
            }
            # Resize the new 'exploded' window
            if ($$terminal{_TABBED}) {
                $terminal->_tabToWin({'width' => $defw, 'height' => $defh});
            } else {
                $$terminal{_WINDOWTERMINAL}->resize($defw, $defh);
            }
            # Move it to its corresponding position
            $$terminal{_WINDOWTERMINAL}->move(($col*$defw+3), 5+($row*$defh+($row*50)));
            $col++;
            if ($col == $conns_per_row) {
                $row++;
                $col=0;
            }
        }
        return 1;
    });
    # Capture 'Separate' button clicked
    $$self{_WINDOWPCC}{btnShowPipe}->signal_connect('clicked' => sub {$PACMain::FUNCS{_PIPE}->show;});

    # Capture 'ReTab' button clicked
    $$self{_WINDOWPCC}{btnReTab}->signal_connect('clicked' => sub {
        my $cluster = $$self{_WINDOWPCC}{comboTerminals}->get_active_text // '';
        my @list = keys %{$$self{_WINDOWPCC}{cbSendToAll}->get_active ? $$self{_RUNNING} : $$self{_CLUSTERS}{$cluster}};
        foreach my $uuid (@list) {
            # Check that these are valid terminals
            if (!defined($$self{_RUNNING}{$uuid}{terminal})) {
                next;
            }
            if (ref($$self{_RUNNING}{$uuid}{terminal}) !~ /^PACTerminal|PACShell$/go) {
                next;
            }

            if (!$$self{_RUNNING}{$uuid}{'terminal'}{_TABBED}) {
                $$self{_RUNNING}{$uuid}{'terminal'}->_winToTab();
            }
        }
    });

    # Capture 'Close All' button clicked
    $$self{_WINDOWPCC}{btnCloseAll}->signal_connect('clicked' => sub {
        my $cluster = $$self{_WINDOWPCC}{comboTerminals}->get_active_text() // '';
        my @list = keys %{$$self{_WINDOWPCC}{cbSendToAll}->get_active() ? $$self{_RUNNING} : $$self{_CLUSTERS}{$cluster}};
        return 1 unless scalar(@list) && _wConfirm($$self{_WINDOWPCC}{main}, "Are you sure you want to CLOSE <b>every</b> terminal" . ($cluster ne '' ? " in cluster '$cluster'" : '') . "?");
        foreach my $uuid (@list) {
            if (defined($$self{_RUNNING}{$uuid}{'terminal'}) && ref($$self{_RUNNING}{$uuid}{terminal}) =~ /^PACTerminal|PACShell$/go) {
                $$self{_RUNNING}{$uuid}{'terminal'}->stop('force', 'deep');
            }
        }
        return 1;
    });

    # Capture 'Close' button clicked
    $$self{_WINDOWPCC}{btnClose}->signal_connect('clicked' => sub {
        foreach my $cluster (keys %{$$self{_CLUSTERS}}) {
            foreach my $uuid (keys %{$$self{_CLUSTERS}{$cluster}}) {
                $$self{_RUNNING}{$uuid}{'terminal'}{_PROPAGATE} = 1;
            }
        }
        open(F,">:utf8","$CFG_DIR/asbru.pcc");
        my ($x, $y) = $$self{_WINDOWPCC}{main}->get_position;
        my ($w, $h) = $$self{_WINDOWPCC}{main}->get_size;
        ($$self{_W}, $$self{_H}) = ($w, $h) if $$self{_WINDOWPCC}{cbShowMultiText}->get_active;
        print F '__PAC__PCC__LANG__' . ($$self{_WINDOWPCC}{comboLang}->get_active_text // ' <NO HIGHLIGHT>') . "\n";
        print F '__PAC__PCC__POSITION__' . $x . ':' . $y . "\n";
        print F '__PAC__PCC__SIZE__' . $w . ':' . $h . "\n";
        print F "__PAC__PCC__MULTILINE__\n" if $$self{_WINDOWPCC}{cbShowMultiText}->get_active;
        $$self{_WINDOWPCC}{main}->hide;
        if ($$self{_WINDOWPCC}{cbAutoSave}->get_active // 1) {
            print(F $$self{_WINDOWPCC}{multiTextBuffer}->get_property('text') // '');
        }
        close F;
        return 1;
    });

    # Capture "Auto save/load" checkbutton toggled state
    $$self{_WINDOWPCC}{cbAutoSave}->signal_connect('toggled' => sub {
        $PACMain::FUNCS{_MAIN}{_CFG}{'defaults'}{'autosave PCC text'} = $$self{_WINDOWPCC}{cbAutoSave}->get_active;
        #$PACMain::FUNCS{_MAIN}{_CFG}{'tmp'}{'changed'} = 1;
        $PACMain::FUNCS{_MAIN}->_setCFGChanged(1);
        return 1;
    });

    # Capture window closing
    $$self{_WINDOWPCC}{main}->signal_connect('delete_event' => sub {$$self{_WINDOWPCC}{btnClose}->activate;});

    return 1;
}

sub _execOnClusterTerminals {
    my $self = shift;
    my $text = shift;
    my $force_subst = shift // 0;

    if (!defined $text) {
        return 1;
    }
    my $cluster = $$self{_WINDOWPCC}{comboTerminals}->get_active_text // '';
    foreach my $uuid (keys %{$$self{_RUNNING}}) {
        my $this_cluster = $$self{_RUNNING}{$uuid}{'terminal'}{'_CLUSTER'} // '';
        my $vte = $$self{_RUNNING}{$uuid}{'terminal'}{'_GUI'}{_VTE};

        if (!((defined $vte) && ((($cluster ne '') && ($this_cluster eq $cluster) ) || $$self{_WINDOWPCC}{cbSendToAll}->get_active))) {
            next;
        }
        $$self{_RUNNING}{$uuid}{'terminal'}{_LISTEN_COMMIT} = 0;
        $$self{_RUNNING}{$uuid}{'terminal'}->_execute('remote', $text, 0, $$self{_WINDOWPCC}{cbSubstitute}->get_active || $force_subst);
        $$self{_RUNNING}{$uuid}{'terminal'}{_LISTEN_COMMIT} = 1;
    }

    return 1;
}

sub _updateGUI {
    my $self = shift;

    # Empty the entry box
    $$self{_WINDOWPCC}{entryData}->set_text('');

    if ($$self{_WINDOWPCC}{cbShowMultiText}->get_active) {
        $$self{_WINDOWPCC}{hboxData}->hide;
        $$self{_WINDOWPCC}{main}->set_resizable(1);
        $$self{_WINDOWPCC}{vboxMultiText}->show_all;
        $$self{_WINDOWPCC}{hboxData}->set_sensitive(0);
        $$self{_WINDOWPCC}{multiTextView}->grab_focus;
        $$self{_WINDOWPCC}{main}->resize($$self{_W} // 300, $$self{_H} // 200);
    } else {
        $$self{_WINDOWPCC}{hboxData}->show;
        $$self{_WINDOWPCC}{main}->set_resizable(0);
        $$self{_WINDOWPCC}{vboxMultiText}->hide;
        $$self{_WINDOWPCC}{hboxData}->set_sensitive(1);
        $$self{_WINDOWPCC}{entryData}->grab_focus;
    }

    # Save currenty selected cluster
    $$self{_SELECTED} = $$self{_WINDOWPCC}{comboTerminals}->get_active_text // '';

    # Empty the clusters combobox
    $$self{_WINDOWPCC}{comboTerminals}->remove_all();

    $$self{_CLUSTERS} = undef;

    # Look into every started terminal, and save the list of clusters/term per cluster
    foreach my $uuid (keys %{$$self{_RUNNING}}) {
        my $name = $$self{_RUNNING}{$uuid}{'terminal'}{'_NAME'};
        if (!defined $name) {
            next;
        }
        # Populate the CLUSTER variable
        if (my $cluster = $$self{_RUNNING}{$uuid}{'terminal'}{_CLUSTER}) {
            $$self{_CLUSTERS}{$cluster}{$uuid} = 1;
        }
    }

    # Now, populate the cluters combobox with the configured clusters...
    my $i = 0;
    my $sel = 0;
    foreach my $cluster (sort {$a cmp $b} keys %{$$self{_CLUSTERS}}) {
        $$self{_WINDOWPCC}{comboTerminals}->append_text($cluster);
        $$self{_WINDOWPCC}{comboTerminals}->set_active(0);
        if ($cluster eq $$self{_SELECTED}) {
            $sel = $i
        };
        $i++;
    }
    # Select the previously selected cluster
    $$self{_WINDOWPCC}{comboTerminals}->set_active($sel);

    my $cluster = $$self{_WINDOWPCC}{comboTerminals}->get_active_text // '';
    # Setup every connection to avoid keypresses propagation if such option is checked in PCC
    foreach my $uuid (keys %{$$self{_CLUSTERS}{$cluster}}) {
        $$self{_RUNNING}{$uuid}{'terminal'}{_PROPAGATE} = ! $$self{_WINDOWPCC}{cbPreventSingle}->get_active unless ! $$self{_WINDOWPCC}{main}->get_visible;
    }

    return 1;
}

sub _getCurrentBlock {
    my $self = shift;
    my $txtBuffer = shift;
    my $txtBlock = '';
    my $txtAll = $txtBuffer->get_property('text') // '';

    if ($txtAll eq '') {
        return '';
    }
    my $iter = $txtBuffer->get_iter_at_mark($txtBuffer->get_insert);
    if (!$iter) {
        return '';
    }
    my @lines = split(/\R/, $txtAll);
    my $line = $iter->get_line;
    my $line_start = $line;
    my $line_end = $line;

    # Find the first block line (the first non-empty line over the current cursor line)
    for(my $i = $line; $i >= 0; $i--) {
        if (($lines[$i] // '') eq '') {
            last;
        }
        $line_start = $i;
    }
    # Find the last block line (the last non-empty line down the current cursor line)
    for(my $i = $line; $i <= $#lines; $i++) {
        if (($lines[$i] // '') eq '') {
            last;
        }
        $line_end = $i;
    }
    # Now save every line
    for(my $i = $line_start; $i <= $line_end; $i++) {
        $txtBlock .= ($lines[$i] // '') . "\n";
    }
    return $txtBlock;
}

# END: Define PRIVATE CLASS functions
###################################################################

1;
