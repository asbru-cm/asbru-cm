package Wnck;

use Glib::Object::Introspection;

sub import {
  Glib::Object::Introspection->setup(basename => 'Wnck',
                                     version => '3.0',
                                     package => 'Wnck');
}

1;
