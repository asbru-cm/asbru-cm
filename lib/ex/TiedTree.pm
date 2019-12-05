#
# $Header: /cvsroot/gtk2-perl-ex/Gtk3-Ex/Simple/Tree/lib/Gtk3/Ex/Simple/TiedTree.pm,v 1.1.1.1 2004/10/21 00:00:58 rwmcfa1 Exp $
#

# nomenclature:
#    piter - parent iter of what we're working with, undef means root of
#        whole tree
#    iter - iter of the node('s values) we're working with
#    citer - child iter
#    prow - parent row, Gtk3::TreeRowReference (a persistent version of an
#    iter)

package TiedTree;

use strict;
use Gtk3;
use Carp;

our $VERSION = '0.1';

=for nothing

TiedTree is an array in which each element is a row in the liststore.

=cut

sub TIEARRAY {
    my $class = shift;
    my $model = shift;
    my $iter = shift;

    croak "usage tie (\@ary, 'class', model, iter=undef)"
    if (!$model || !UNIVERSAL::isa ($model, 'Gtk3::TreeModel') ||
        ($iter  && !UNIVERSAL::isa ($iter, 'Gtk3::TreeIter')));

    my $path = $model->get_path ($iter) if ($iter);
    my $rowref = Gtk3::TreeRowReference->new ($model, $path) if ($path);

    return bless {
        model => $model,
        prow => $rowref,
    }, $class;
}

sub FETCH {# this, index
    my $self = shift;
    my $index = shift;

    my $model = $self->{model};
    my $prow = $self->{prow};

    # get our parent iter, if we have one
    my $piter;
    $piter = _get_iter_from_row ($model, $prow) if ($prow);

    my $iter = $model->iter_nth_child ($piter, $index);
    return undef unless defined $iter;

    # tie this row's values
    my @values;
    tie @values, 'Gtk3::SimpleList::TiedRow', $model, $iter;

    # this this row's children
    my @children;
    tie @children, 'TiedTree', $model, $iter;

    # and return a newly made hashref in our magic format
    return {value => \@values, children => \@children};
}

sub _get_iter_from_row
{
    my $model = shift;
    my $row = shift;

    return $model->get_iter ($row->get_path);
}

sub _do_node
{
    my ($model, $iter, $store) = @_;

    # tie this row's values
    my @row;
    tie @row, 'Gtk3::SimpleList::TiedRow', $model, $iter;
    if ('ARRAY' eq ref $store->{value}) {
        @row = @{$store->{value}};
    } else {
        $row[0] = $store->{value};
    }

    # tie the children, a recursive TiedTree
    my @a;
    tie @a, 'TiedTree', $model, $iter;
    @a = @{$store->{children}} if ($store->{children});
}

sub STORE {# this, index, value
    my $self = shift;
    my $index = shift;
    my $store = shift;

    my $model = $self->{model};
    my $prow = $self->{prow};

    # get our parent iter, if we have one
    my $piter;
    $piter = _get_iter_from_row ($model, $prow) if ($prow);

    # if we're overriding a child get it
    my $iter = $model->iter_nth_child ($piter, $index);
    # we're creating a new child
    $iter = $model->insert ($piter, $index) if not defined $iter;

    _do_node ($model, $iter, $store);

    return $store;
}

sub FETCHSIZE {# this
    my $model = $_[0]->{model};
    my $prow = $_[0]->{prow};

    # get the parent iter, if one
    my $piter;
    $piter = _get_iter_from_row ($model, $prow) if ($prow);

    # return the number of children below
    return $model->iter_n_children ($piter);
}

sub PUSH {# this, list
    my $self = shift;

    my $model = $self->{model};
    my $prow = $self->{prow};

    # get our parent iter, if we have one
    my $piter;
    $piter = _get_iter_from_row ($model, $prow) if ($prow);

    # do each of the values being stored
    my $iter;
    # for the rest of the params
    foreach (@_)
    {
        # get an append iter under our parent, if one
        $iter = $model->append ($piter);

        # insert this node
        _do_node ($model, $iter, $_);
    }

    return $model->iter_n_children ($piter);
}

# duplicate everything b/c it's cominging out of the model and therefore
# tie's won't work any more
sub _copy_node
{
    my $model = shift;
    my $iter = shift;

    my @children;

    my $nchild = $model->iter_n_children ($iter)-1;
    my $citer; # child iter
    foreach (0..$nchild)
    {
        $citer = $model->iter_nth_child ($iter, $_);
        push @children, _copy_node ($model, $citer);
    }

    {value => [$model->get ($iter)], children => \@children};
}

sub POP {# this
    my $model = $_[0]->{model};
    my $prow = $_[0]->{prow};

    # get our parent iter, if we have one
    my $piter;
    $piter = _get_iter_from_row ($model, $prow) if ($prow);

    my $iter = $model->iter_nth_child ($piter,
            $model->iter_n_children ($piter)-1);

    # since we're going away, our children will to, get them first
    # before we go away get our values and create our return hashref
    my $ret = _copy_node ($model, $iter);

    # delete ourself (and our children)
    $model->remove($iter);

    return $ret;
}

sub SHIFT {# this
    my $model = $_[0]->{model};
    my $prow = $_[0]->{prow};

    # get our parent iter, if we have one
    my $piter;
    $piter = _get_iter_from_row ($model, $prow) if ($prow);

    my $iter = $model->iter_nth_child($piter, 0);

    # since we're going away, our children will to, get them first
    my $ret = _copy_node ($model, $iter);

    # delete ourself (and our children)
    $model->remove($iter) if($iter);

    return $ret;
}

sub UNSHIFT {# this, list
    my $self = shift;

    my $model = $self->{model};
    my $prow = $self->{prow};

    # get our parent iter, if we have one
    my $piter;
    $piter = _get_iter_from_row ($model, $prow) if ($prow);

    my $iter;
    foreach (@_)
    {
        # get a prepend iter under our parent if one
        $iter = $model->prepend ($piter);

        _do_node ($model, $iter, $_);
    }

    return $model->iter_n_children (undef);
}

# note: really, arrays aren't supposed to support the delete operator this
#       way, but we don't want to break existing code.
sub DELETE {# this, key
    my $model = $_[0]{model};
    my $prow = $_[0]{prow};
    my $index = $_[1];

    # get our parent iter, if we have one
    my $piter;
    $piter = _get_iter_from_row ($model, $prow) if ($prow);

    my $ret;
    if ($index < $model->iter_n_children ($piter)) {
        my $iter = $model->iter_nth_child ($piter, $index);

        # since we're going away, our children will to, get them first
        $ret = _copy_node ($model, $iter);

        # delete ourself (and our children)
        $model->remove ($iter);
    }
    return $ret;
}

sub _remove_children
{
    my $model = shift;
    my $piter = shift;

    my $nchild = $model->iter_n_children ($piter)-1;
    my $citer; # child iter
    foreach (0..$nchild)
    {
        $citer = $model->iter_nth_child ($piter, $_);
        $model->remove ($citer) if ($citer);
    }
}

sub CLEAR {# this
    my $model = $_[0]{model};
    my $prow = $_[0]{prow};

    if ($prow)
    {
        my $piter = _get_iter_from_row ($model, $prow);
        _remove_children ($model, $piter);
    }
    else
    {
        $model->clear;
    }
}

# note: arrays aren't supposed to support exists, either.
sub EXISTS {# this, key
    my $model = $_[0]{model};
    my $prow = $_[0]{prow};
    my $index = $_[1];

    # get our parent iter, if we have one
    my $piter;
    $piter = _get_iter_from_row ($model, $prow) if ($prow);

    return($index < $model->iter_n_children ($piter));
}

# we can't really, reasonably, extend the tree store in one go, it will be
# extend as items are added
sub EXTEND {}

sub get_model {
    return $_[0]{model};
}

sub STORESIZE {carp "STORESIZE: operation not supported";}

sub SPLICE {# this, offset, length, list
    my $self = shift;

    my $model = $self->{model};
    my $prow = $self->{prow};

    # get our parent iter, if we have one
    my $piter;
    $piter = _get_iter_from_row ($model, $prow) if ($prow);

    # get the offset
    my $offset = shift || 0;
    # if offset is neg, invert it
    $offset = $model->iter_n_children ($piter) + $offset if ($offset < 0);
    # get the number of elements to remove
    my $length = shift;
    # if len was undef, not just false, calculate it
    $length = $self->FETCHSIZE() - $offset unless (defined ($length));
    # get any elements we need to insert into their place
    my @list = @_;

    # place to store any returns
    my @ret = ();

    # remove the desired elements
    my $ret;
    for (my $i = $offset; $i < $offset+$length; $i++)
    {
        # things will be shifting forward, so always delete at offset
        $ret = $self->DELETE ($offset);
        push @ret, $ret if defined $ret;
    }

    # insert the passed list at offset in reverse order, so the will
    # be in the correct order
    foreach (reverse @list)
    {
        # insert a new row
        $model->insert ($piter, $offset);
        # and put the data in it
        $self->STORE ($offset, $_);
    }

    # return deleted rows in array context, the last row otherwise
    # if nothing deleted return empty
    return (@ret ? (wantarray ? @ret : $ret[-1]) : ());
}

1;

__END__

Copyright (C) 2004 by the gtk2-perl team (see the file AUTHORS for the
full list).  See LICENSE for more information.
