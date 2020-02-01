package PACTree;

use strict;
use Carp;
use Gtk3;

use PACUtils;

use TiedTree;

our @ISA = 'Gtk3::TreeView';

our $VERSION = '0.50';

our %column_types;
*column_types = \%Gtk3::SimpleList::column_types;
*add_column_type = \&Gtk3::SimpleList::add_column_type;

# Start PAC specific methods
sub _getSelectedUUIDs {
    my $self = shift;
    my $selection = $self->get_selection;
    my $model = $self->get_model;
    my @paths = _getSelectedRows($selection);

    my @selected;

    scalar(@paths) or push(@selected, '__PAC__ROOT__');
    foreach my $path (@paths) {push(@selected, $model->get_value($model->get_iter($path), 2) ) ;}

    return wantarray ? @selected : scalar(@selected);
}

sub _getSelectedNames {
    my $self = shift;
    my $selection = $self->get_selection;
    my $model = $self->get_model;
    my @paths = _getSelectedRows($selection);

    my @selected;

    foreach my $path (@paths) {push(@selected, $model->get_value($model->get_iter($path), 1) ) ;}

    return wantarray ? @selected : scalar(@selected);
}

sub _getChildren {
    my $self = shift;
    my $uuid = shift;
    my $which = shift // 'all'; # 0:nodes, 1:groups, all:nodes+groups
    my $deep = shift // 0; # 0:1st_level, 1:all_levels

    my $selection = $self->get_selection;
    my $modelsort = $self->get_model;
    my $model = $modelsort->get_model;

    my @list;
    my $root;

    # Locate every node under $uuid
    $modelsort->foreach(sub
    {
        my ($store, $path, $iter, $tmp) = @_;
        my $node_uuid = $store->get_value($iter, 2);
        my $node_name = $store->get_value($iter, 1);

        ($node_uuid eq $uuid) and $root = $path->to_string;
        return 0 unless (defined $root && ($deep || $path->to_string =~ /^$root:\d+$/g) );

        (($path->to_string =~ /^$root:/g) && (((defined($$self{children}) || '0') eq $which) || ($which eq 'all') ) && ($node_uuid ne '__PAC__ROOT__') ) and push(@list, $node_uuid);
        return $path->to_string !~ /^$root/g;
    });

    return wantarray ? @list : scalar(@list);
}

sub _getPath {
    my $self = shift;
    my $uuid = shift;

    my $selection = $self->get_selection;
    my $modelsort = $self->get_model;
    my $model = $modelsort->get_model;

    my $ret_path;

    # Locate every connection under $uuid
    $modelsort->foreach(sub
    {
        my ($store, $path, $iter, $tmp) = @_;
        my $node_uuid = $store->get_value($iter, 2);

        return 0 unless $node_uuid eq $uuid;
        $ret_path = $path->to_string;
        return 1;
    });

    return (defined $ret_path) ? Gtk3::TreePath->new_from_string($ret_path) : undef;
}

sub _addNode {
    my $self = shift;
    my $parent_uuid = shift;
    my $new_uuid = shift;
    my $gui_name = shift;
    my $icon = shift;
    my $tree = shift // $$self{data};

    foreach my $elem_hash (@{$tree}) {
        my $this_uuid = $$elem_hash{'value'}[2];

        # Parent group is __PAC__ROOT__
        if ((! defined $parent_uuid) || ($parent_uuid eq '__PAC__ROOT__') ) {
            push(@{$$self{'data'}}, {value => [$icon, $gui_name, $new_uuid]});
            return 1;
        }
        # Parent group found, insert here (the TreeModelSort will order it itself)
        elsif ($this_uuid eq $parent_uuid) {
            splice(@{$$elem_hash{'children'}}, 0, 0, ({value => [$icon, $gui_name, $new_uuid]}) );
            return 1;
        }
        # Parent group not found, keep on searching in its children
        else {
            $self->_addNode($parent_uuid, $new_uuid, $gui_name, $icon, $$elem_hash{'children'});
        }
    }

    return 1;
}

sub _delNode {
    my $self = shift;
    my $uuid = shift;

    my $selection = $self->get_selection;
    my $modelsort = $self->get_model;
    my $model = $modelsort->get_model;

    # Delete the given UUID from the PACTree
    $modelsort->foreach(sub
    {
        my ($store, $path, $iter, $tmp) = @_;
        my $node_uuid = $store->get_value($iter, 2);
        return 0 unless $node_uuid eq $uuid;
        $model->remove($modelsort->convert_iter_to_child_iter($modelsort->get_iter($path) ));
        return 1;
    });

    return 1;
}

sub _setTreeFocus {
    my $self = shift;
    my $uuid = shift;

    my $model = $self->get_model;

    $model->foreach(sub
    {
        my ($store, $path, $iter) = @_;

        my $elem_uuid = $model->get_value($model->get_iter($path), 2);

        return 0 unless $elem_uuid eq $uuid;

        $self->expand_to_path($path);
        $self->set_cursor($path, undef, 0);

        return 1;
    });

    return 1;
}
# End of PAC specific methods

sub text_cell_edited {
    my ($cell_renderer, $text_path, $new_text, $model) = @_;
    my $path = Gtk3::TreePath->new_from_string ($text_path);
    my $iter = $model->get_iter ($path);
    $model->set ($iter, $cell_renderer->{column}, $new_text);
}

sub new {
    croak "Usage: $_[0]\->new (title => type, ...)\n"
        . " expecting a list of column title and type name pairs.\n"
        . " can't create a SimpleTree with no columns"
        unless @_ >= 3; # class, key1, val1
    return shift->new_from_treeview (Gtk3::TreeView->new (), @_);
}

sub new_from_treeview {
    my $class = shift;
    my $view = shift;
    croak "treeview is not a Gtk3::TreeView"
        unless defined ($view)
           and UNIVERSAL::isa ($view, 'Gtk3::TreeView');
    croak "Usage: $class\->new_from_treeview (treeview, title => type, ...)\n"
        . " expecting a treeview reference and list of column title and type name pairs.\n"
        . " can't create a SimpleTree with no columns"
        unless @_ >= 2; # key1, val1

    # Defines a special column type that does not use a standard renderer
    # The renderer is built by function 'column_builder'
    # The renderer will assume the first attribute of the model is defining the icon to show
    # and the second attribute contains the markup text to display
    $class->add_column_type('image_text',
        type => 'Glib::Scalar',
        renderer => undef,
        column_builder => sub {
            my $pixrd = Gtk3::CellRendererPixbuf->new();
            my $txtrd = Gtk3::CellRendererText->new();
            my $column = Gtk3::TreeViewColumn->new();
            $column->pack_start($pixrd, 0);
            $column->pack_start($txtrd, 1);
            $column->add_attribute($pixrd, 'pixbuf', 0);
            $column->add_attribute($txtrd, 'markup', 1);
            return $column;
        }
    );

    # Build the columns list for this new tree
    # according to the definition of column types
    my @column_info = ();
    for (my $i = 0; $i < @_ ; $i+=2) {
        my $typekey = $_[$i+1];
        croak "expecting pairs of title=>type"
            unless $typekey;
        croak "unknown column type $typekey, use one of "
            . join(", ", keys %column_types)
            unless exists $column_types{$typekey};
        my $type = $column_types{$typekey}{type};
        if (not defined $type) {
            $type = 'Glib::String';
            carp "column type $typekey has no type field; did you"
               . " create a custom column type incorrectly?\n"
               . "limping along with $type";
        }
        push @column_info, {
            title => $_[$i],
            type => $type,
            rtype => $column_types{$_[$i+1]}{renderer},
            attr => $column_types{$_[$i+1]}{attr},
            column_builder => $column_types{$_[$i+1]}{column_builder},
        };
    }

    ## Create the store
    my $model = Gtk3::TreeStore->new (map {$_->{type}} @column_info);

    ## Create the view
    # just in case, 'cause i'm paranoid like that.
    map {$view->remove_column ($_)} $view->get_columns;
    $view->set_model ($model);
    for (my $i = 0; $i < @column_info ; $i++) {
        if (!defined($column_info[$i]{rtype}) && defined($column_info[$i]{column_builder}) && ('CODE' eq ref $column_info[$i]{column_builder})) {
            # A column builder has been defined
            $view->append_column($column_info[$i]{column_builder}());
        }
        elsif ('CODE' eq ref $column_info[$i]{attr})
        {
            $view->insert_column_with_data_func (-1,
                $column_info[$i]{title},
                $column_info[$i]{rtype}->new,
                $column_info[$i]{attr}, $i);
        }
        elsif ('hidden' eq $column_info[$i]{attr})
        {
            # skip hidden column
        }
        else
        {
            my $column = Gtk3::TreeViewColumn->new_with_attributes (
                $column_info[$i]{title},
                $column_info[$i]{rtype}->new,
                $column_info[$i]{attr} => $i,
            );
            $view->append_column ($column);

            if ($column_info[$i]{attr} eq 'active') {
                # make boolean columns respond to editing.
                my $r = $column->get_cells;
                $r->set (activatable => 1);
                $r->signal_connect (toggled => sub {
                    my ($renderer, $row, $col) = @_;
                    my $path = Gtk3::TreePath->new_from_string ($row);
                    my $iter = $model->get_iter ($path);
                    my $val = $model->get ($iter, $col);
                    $model->set ($iter, $col, !$val);
                    }, $i);

            } elsif ($column_info[$i]{attr} eq 'text') {
                # attach a decent 'edited' callback to any
                # columns using a text renderer.  we do NOT
                # turn on editing by default.
                my $r = $column->get_cells;
                $r->{column} = $i;
                $r->signal_connect (edited => \&text_cell_edited,
                            $model);
            }
        }
    }

    my @a;
    tie @a, 'TiedTree', $model;

    $view->{data} = \@a;
    return bless $view, $class;
}

sub set_column_editable {
    my ($self, $index, $editable) = @_;
    my $column = $self->get_column ($index);
    croak "invalid column index $index"
        unless defined $column;
    my $cell_renderer = $column->get_cells;
    $cell_renderer->set (editable => $editable);
}

sub get_column_editable {
    my ($self, $index, $editable) = @_;
    my $column = $self->get_column ($index);
    croak "invalid column index $index"
        unless defined $column;
    my $cell_renderer = $column->get_cells;
    return $cell_renderer->get ('editable');
}

sub set_data_array {
    @{$_[0]->{data}} = @{$_[1]};
}

1;

# FIXME-DOC The documentation below is outdated, incorrect and probably misleading,
# especially due to the blind Gtk2->Gtk3 search'n'replace.

__END__

=head1 NAME

Tree - A simple interface to Gtk3's complex MVC tree widget

=head1 SYNOPSIS

  use Glib qw(TRUE FALSE);
  use Gtk3 '-init';
  use Tree;

  my $stree = Tree->new (
          'Text Field' => 'text',
          'Int Field' => 'int',
          'Double Field' => 'double',
          'Bool Field' => 'bool',
          'Scalar Field' => 'scalar',
      );

  @{$stree->{data}} = (
    {
        value => ['one', 1, 1.1],
        children =>
        [
            {
                value => ['one-b', -1, 1.11,],
            },
        ]
    },
  );

=head1 ABSTRACT

Simple::Tree is a simple interface to the powerful but complex Gtk3::TreeView
and Gtk3::TreeStore combination, implementing using tied arrays to make
thing simple and easy.

=head1 DESCRIPTION

Gtk3 has a powerful, but complex MVC (Model, View, Controller) system used to
implement list and tree widgets.  Tree automates the complex
setup work and allows you to treat the tree model as a more natural list of
hash refs.

After creating a new Tree object with the desired columns you
may set the tree data with a simple Perl array assignment. Rows may be added or
deleted with all of the normal array operations. You can treat the C<data>
member of the Simple::Tree object as an array reference, and manipulate the
tree data with perl's normal operators. Each element is a hash reference
containing (optionally) C<value> and C<children> members. C<value> holds the
value of the node while C<children> is a array reference of futher nodes.
(recursive)

A mechanism has also been put into place allowing columns to be Perl scalars.
The scalar is converted to text through Perl's normal mechanisms and then
displayed in the tree. This same mechanism can be expanded by defining
arbitrary new column types before calling the new function.

=head1 OBJECT HIERARCHY

 Glib::Object
 +--- Gtk3::Object
      +--- Gtk3::Widget
           +--- Gtk3::TreeView
            +--- Tree

=head1 METHODS

=over

=item $stree = Tree->new ($cname, $ctype, ...)

=over

=over

=item * $cname (string)

=item * $ctype (string)

=back

=back

Creates a new Tree object with the specified columns. The
parameter C<cname> is the name of the column, what will be displayed in the
tree headers if they are turned on. The parameter ctype is the type of the
column, one of:

 text    normal text strings
 markup  pango markup strings
 int     integer values
 double  double-precision floating point values
 bool    boolean values, displayed as toggle-able checkboxes
 scalar  a perl scalar, displayed as a text string by default
 pixbuf  a Gtk3::Gdk::Pixbuf

or the name of a custom type you add with C<add_column_type>.  These should be
provided in pairs according to the desired columns for your tree.

=item $stree = Tree->new_from_treeview ($treeview, $cname, $ctype, ...)

=over

=over

=item * $treeview (Gtk3::TreeView)

=item * $cname (string)

=item * $ctype (string)

=back

=back

Like C<< Tree->new() >>, but turns an existing Gtk3::TreeView
into a Tree.  This is intended mostly for use with stuff like
Glade, where the widget is created for you.  This will create and attach a new
model and remove any existing columns from I<treeview>.  Returns I<treeview>,
re-blessed as a Tree.

=item $stree->set_data_array ($arrayref)

=over

=over

=item * $arrayref (array reference)

=back

=back

Set the data in the tree to the array reference $arrayref. This is completely
equivalent to @{$tree->{data}} = @{$arrayref} and is only here for convenience
and for those programmers who don't like to type-cast and have static, set once
data.

=item $stree->set_column_editable ($index, $editable)

=over

=over

=item * $index (integer)

=item * $editable (boolean)

=back

=back

=item boolean = $stree->get_column_editable ($index)

=over

=over

=item * $index (integer)

=back

=back

This is a very simple interface to Gtk3::TreeView's editable text column cells.
All columns which use the attr "text" (basically, any text or number column,
see C<add_column_type>) automatically have callbacks installed to update data
when cells are edited.  With C<set_column_editable>, you can enable the
in-place editing.

C<get_column_editable> tells you if column I<index> is currently editable.

=item Tree->add_column_type ($type_name, ...)


=over

=over

=item $type_name (string)

=back

=back

Add a new column type to the list of possible types. Initially six column types
are defined, text, int, double, bool, scalar, and pixbuf. The bool column type
uses a toggle cell renderer, the pixbuf uses a pixbuf cell renderer, and the
rest use text cell renderers. In the process of adding a new column type you
may use any cell renderer you wish.

The first parameter is the column type name, the list of six are examples.
There are no restrictions on the names and you may even overwrite the existing
ones should you choose to do so. The remaining parameters are the type
definition consisting of key value pairs. There are three required: type,
renderer, and attr. The type key determines what actual datatype will be
stored in the underlying model representation; this is a package name, e.g.
Glib::String, Glib::Int, Glib::Boolean, but in general if you want an
arbitrary Perl data structure you will want to use 'Glib::Scalar'. The
renderer key should hold the class name of the cell renderer to create for this
column type; this may be any of Gtk3::CellRendererText,
Gtk3::CellRendererToggle, Gtk3::CellRendererPixbuf, or some other, possibly
custom, cell renderer class.  The attr key is magical; it may be either a
string, in which case it specifies the attribute which will be set from the
specified column (e.g. 'text' for a text renderer, 'active' for a toggle
renderer, etc), or it may be a reference to a subroutine which will be called
each time the renderer needs to draw the data.

This function, described as a GtkTreeCellDataFunc in the API reference,
will receive 5 parameters: $treecol, $cell, $model, $iter,
$col_num (when SimpleList hooks up the function, it sets the column number to
be passed as the user data).  The data value for the particular cell in question
is available via $model->get ($iter, $col_num); you can then do whatever it is
you have to do to render the cell the way you want.  Here are some examples:

  # just displays the value in a scalar as
  # Perl would convert it to a string
  Tree->add_column_type('a_scalar',
          type => 'Glib::Scalar',
      renderer => 'Gtk3::CellRendererText',
          attr => sub {
               my ($treecol, $cell, $model, $iter, $col_num) = @_;
               my $info = $model->get ($iter, $col_num);
               $cell->set (text => $info);
      }
     );

  # sums up the values in an array ref and displays
  # that in a text renderer
  Tree->add_column_type('sum_of_array',
          type => 'Glib::Scalar',
      renderer => 'Gtk3::CellRendererText',
          attr => sub {
               my ($treecol, $cell, $model, $iter, $col_num) = @_;
               my $sum = 0;
               my $info = $model->get ($iter, $col_num);
               foreach (@$info)
               {
                   $sum += $_;
               }
               $cell->set (text => $sum);
          }
     );

=back

=head1 MODIFYING TREE DATA

Examples only, possibilities are too numerous to list here (see examples.)

  # first level assignment
  $stree->{data}[3]{value}[1] = 6;

  # second level assignment
  $stree->{data}[3]{children}[1]{value}[1] = 12;

  # first level store
  @{$stree->{data}[1]{value}} = ('store', -1, -1.1, 1, 'store',);

  # second level store
  @{$stree->{data}[1]{children}[0]{value}} = ('store', -2, -2.1, 0, 'store',);

  # first level push
  push @{$tdata}, {value => ['push', 1, 1.1, 1, 'push',],};

  # second level push
  push @{$stree->{data}[4]{children}}, {value => ['push-b', 2, 2.2, 0, 'push-b',],};

=head1 SEE ALSO

Perl(1), Glib(3pm), Gtk3(3pm), Gtk3::TreeView(3pm), Gtk3::TreeModel(3pm),
Gtk3::TreeStore(3pm).

=head1 AUTHORS

 muppet <scott at asofyet dot org>
 Ross McFarland <rwmcfa1 at neces dot com>

=head1 COPYRIGHT AND LICENSE

Copyright 2004 by the Gtk3-Perl team.

This library is free software; you can redistribute it and/or modify it under
the terms of the GNU Library General Public License as published by the Free
Software Foundation; either version 2.1 of the License, or (at your option) any
later version.

This library is distributed in the hope that it will be useful, but WITHOUT ANY
WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A
PARTICULAR PURPOSE.  See the GNU Library General Public License for more
details.

You should have received a copy of the GNU Library General Public License along
with this library; if not, write to the Free Software Foundation, Inc., 59
Temple Place - Suite 330, Boston, MA  02111-1307  USA.

=cut
