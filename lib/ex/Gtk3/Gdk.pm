package Gtk3::Gdk;

use Glib::Object::Introspection;

sub import {
  Glib::Object::Introspection->setup(basename => 'GdkX11',
                                     version => '3.0',
                                     package => 'Gtk3::Gdk');
}

1;
