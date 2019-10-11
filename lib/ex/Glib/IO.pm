package Glib::IO;

use Glib::Object::Introspection;

sub import {
  Glib::Object::Introspection->setup(basename => 'Gio',
                                     version => '2.0',
                                     package => 'Glib::IO');
}

1;
