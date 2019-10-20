package KeePass;

=head1 NAME

File::KeePass - Interface to KeePass V1 and V2 database files

=cut

use strict;
use warnings;
use Crypt::Rijndael;
use Digest::SHA qw(sha256);

use constant DB_HEADSIZE_V1 => 124;
use constant DB_SIG_1 => 0x9AA2D903;
use constant DB_SIG_2_v1 => 0xB54BFB65;
use constant DB_SIG_2_v2 => 0xB54BFB67;
use constant DB_VER_DW_V1 => 0x00030002;
use constant DB_VER_DW_V2 => 0x00030000; # recent KeePass is 0x0030001
use constant DB_FLAG_RIJNDAEL => 2;
use constant DB_FLAG_TWOFISH => 8;

our $VERSION = '2.03';
my %locker;
my $salsa20_iv = "\xe8\x30\x09\x4b\x97\x20\x5d\x2a";
my $qr_date = qr/^(\d\d\d\d)-(\d\d)-(\d\d)[T](\d\d):(\d\d):(\d\d)(\.\d+|)?Z?$/;

sub new {
    my $class = shift;
    my $args = ref($_[0]) ? {%{shift()}} : {@_};
    return bless $args, $class;
}

sub auto_lock {
    my $self = shift;
    $self->{'auto_lock'} = shift if @_;
    return !exists($self->{'auto_lock'}) || $self->{'auto_lock'};
}

sub groups {shift->{'groups'} || die "No groups loaded yet\n"}

sub header {shift->{'header'}}

###----------------------------------------------------------------###

sub load_db {
    my $self = shift;
    my $file = shift || die "Missing file\n";
    my $pass = shift || die "Missing pass\n";
    my $args = shift || {};

    my $buffer = $self->slurp($file);
    return $self->parse_db($buffer, $pass, $args);
}

sub save_db {
    my ($self, $file, $pass, $head, $groups) = @_;
    die "Missing file\n" if ! $file;
    $head ||= {};
    my $v = $file =~ /\.kdbx$/i ? 2
          : $file =~ /\.kdb$/i  ? 1
          : $head->{'version'} || $self->{'version'};
    $head->{'version'} = $v;

    my $buf = $self->gen_db($pass, $head, $groups);
    my $bak = "$file.bak";
    my $tmp = "$file.new.".int(time());
    open my $fh, '>', $tmp or die "Could not open $tmp: $!\n";
    binmode $fh;
    print $fh $buf;
    close $fh;
    if (-s $tmp ne length($buf)) {
        die "Written file size of $tmp didn't match (".(-s $tmp)." != ".length($buf).") - not moving into place\n";
        unlink($tmp);
    }

    if (-e $bak) {
        unlink($bak) or unlink($tmp) or die "Could not removing already existing backup $bak: $!\n";
    }
    if (-e $file) {
        rename($file, $bak) or unlink($tmp) or die "Could not backup $file to $bak: $!\n";
    }
    rename($tmp, $file) or die "Could not move $tmp to $file: $!\n";
    if (!$self->{'keep_backup'} && -e $bak) {
        unlink($bak) or die "Could not removing temporary backup $bak: $!\n";
    }

    return 1;
}

sub clear {
    my $self = shift;
    $self->unlock if $self->{'groups'};
    delete @$self{qw(header groups)};
}

sub DESTROY {shift->clear}

###----------------------------------------------------------------###

sub parse_db {
    my ($self, $buffer, $pass, $args) = @_;
    $self = $self->new($args || {}) if ! ref $self;
    $buffer = $$buffer if ref $buffer;

    my $head = $self->parse_header($buffer);
    local $head->{'raw'} = substr $buffer, 0, $head->{'header_size'} if $head->{'version'} == 2;
    $buffer = substr $buffer, $head->{'header_size'};

    $self->unlock if $self->{'groups'}; # make sure we don't leave dangling keys should we reopen a new db

    my $meth = ($head->{'version'} == 1) ? '_parse_v1_body'
             : ($head->{'version'} == 2) ? '_parse_v2_body'
             : die "Unsupported keepass database version ($head->{'version'})\n";
    (my $meta, $self->{'groups'}) = $self->$meth($buffer, $pass, $head);
    $self->{'header'} = {%$head, %$meta};
    $self->auto_lock($args->{'auto_lock'}) if exists $args->{'auto_lock'};

    $self->lock if $self->auto_lock;
    return $self;
}

sub parse_header {
    my ($self, $buffer) = @_;
    my ($sig1, $sig2) = unpack 'LL', $buffer;
    die "File signature (sig1) did not match ($sig1 != ".DB_SIG_1().")\n" if $sig1 != DB_SIG_1;
    return $self->_parse_v1_header($buffer) if $sig2 eq DB_SIG_2_v1;
    return $self->_parse_v2_header($buffer) if $sig2 eq DB_SIG_2_v2;
    die "Second file signature did not match ($sig2 != ".DB_SIG_2_v1()." or ".DB_SIG_2_v2().")\n";
}

sub _parse_v1_header {
    my ($self, $buffer) = @_;
    my $size = length($buffer);
    die "File was smaller than db header ($size < ".DB_HEADSIZE_V1().")\n" if $size < DB_HEADSIZE_V1;
    my %h = (version => 1, header_size => DB_HEADSIZE_V1);
    my @f = qw(sig1 sig2 flags ver seed_rand enc_iv n_groups n_entries checksum seed_key rounds);
    my $t = 'L    L    L     L   a16       a16    L        L         a32      a32      L';
    @h{@f} = unpack $t, $buffer;
    die "Unsupported file version ($h{'ver'}).\n" if $h{'ver'} & 0xFFFFFF00 != DB_VER_DW_V1 & 0xFFFFFF00;
    $h{'enc_type'} = ($h{'flags'} & DB_FLAG_RIJNDAEL) ? 'rijndael'
                   : ($h{'flags'} & DB_FLAG_TWOFISH)  ? 'twofish'
                   : die "Unknown encryption type\n";
    return \%h;
}

sub _parse_v2_header {
    my ($self, $buffer) = @_;
    my %h = (version => 2, enc_type => 'rijndael');
    @h{qw(sig1 sig2 ver)} = unpack 'L3', $buffer;
    die "Unsupported file version2 ($h{'ver'}).\n" if $h{'ver'} & 0xFFFF0000 > 0x00020000 & 0xFFFF0000;
    my $pos = 12;

    while (1) {
        my ($type, $size) = unpack "\@$pos CS", $buffer;
        $pos += 3;
        my $val = substr $buffer, $pos, $size; # #my ($val) = unpack "\@$pos a$size", $buffer;
        if (!$type) {
            $h{'0'} = $val;
            $pos += $size;
            last;
        }
        $pos += $size;
        if ($type == 1) {
            $h{'comment'} = $val;
        } elsif ($type == 2) {
            warn "Cipher id did not match AES\n" if $val ne "\x31\xc1\xf2\xe6\xbf\x71\x43\x50\xbe\x58\x05\x21\x6a\xfc\x5a\xff";
            $h{'cipher'} = 'aes';
        } elsif ($type == 3) {
            $val = unpack 'V', $val;
            warn "Compression was too large.\n" if $val > 1;
            $h{'compression'} = $val;
        } elsif ($type == 4) {
            warn "Length of seed random was not 32\n" if length($val) != 32;
            $h{'seed_rand'} = $val;
        } elsif ($type == 5) {
            warn "Length of seed key was not 32\n" if length($val) != 32;
            $h{'seed_key'} = $val;
        } elsif ($type == 6) {
            $h{'rounds'} = unpack 'L', $val;
        } elsif ($type == 7) {
            warn "Length of encryption IV was not 16\n" if length($val) != 16;
            $h{'enc_iv'} = $val;
        } elsif ($type == 8) {
            warn "Length of stream key was not 32\n" if length($val) != 32;
            $h{'protected_stream_key'} = $val;
        } elsif ($type == 9) {
            warn "Length of start bytes was not 32\n" if length($val) != 32;
            $h{'start_bytes'} = $val;
        } elsif ($type == 10) {
            warn "Inner stream id did not match Salsa20\n" if unpack('V', $val) != 2;
            $h{'protected_stream'} = 'salsa20';
        } else {
            warn "Found an unknown header type ($type, $val)\n";
        }
    }

    $h{'header_size'} = $pos;
    return \%h;
}

sub _parse_v1_body {
    my ($self, $buffer, $pass, $head) = @_;
    die "Unimplemented enc_type $head->{'enc_type'}\n" if $head->{'enc_type'} ne 'rijndael';
    my $key = $self->_master_key($pass, $head);
    $buffer = $self->decrypt_rijndael_cbc($buffer, $key, $head->{'enc_iv'});

    die "The file could not be decrypted either because the key is wrong or the file is damaged.\n"
        if length($buffer) > 2**32-1 || (!length($buffer) && $head->{'n_groups'});
    die "The file checksum did not match.\nThe key is wrong or the file is damaged\n"
        if $head->{'checksum'} ne sha256($buffer);

    my ($groups, $gmap, $pos) = $self->_parse_v1_groups($buffer, $head->{'n_groups'});
    $self->_parse_v1_entries($buffer, $head->{'n_entries'}, $pos, $gmap, $groups);
    return ({}, $groups);
}

sub _parse_v2_body {
    my ($self, $buffer, $pass, $head) = @_;
    my $key = $self->_master_key($pass, $head);
    $buffer = $self->decrypt_rijndael_cbc($buffer, $key, $head->{'enc_iv'});
    die "The database key appears invalid or else the database is corrupt.\n"
        if substr($buffer, 0, 32, '') ne $head->{'start_bytes'};
    $buffer = $self->unchunksum($buffer);
    $buffer = eval {$self->decompress($buffer)} or die "Failed to decompress document: $@" if ($head->{'compression'} || '') eq '1';
    $self->{'xml_in'} = $buffer if $self->{'keep_xml'} || $head->{'keep_xml'};

    my $uuid = sub {
        my $id = shift;
        if ($id) {
            $id = $self->decode_base64($id);
            $id = 0 if $id eq "\0"x16;
            $id =~ s/^0+(?=\d)// if $id =~ /^\d{16}$/;
        }
        return $id;
    };

    # parse the XML - use our own parser since XML::Simple does not do event based actions
    my $tri = sub {return !defined($_[0]) ? undef : ('true' eq lc $_[0]) ? 1 : ('false' eq lc $_[0]) ? 0 : undef};
    my $s20_stream = $self->salsa20_stream({key => sha256($head->{'protected_stream_key'}), iv => $salsa20_iv, rounds => 20});
    my %BIN;
    my $META;
    my @GROUPS;
    my $level = 0;
    my $data = $self->parse_xml($buffer, {
        top => 'KeePassFile',
        force_array => {map {$_ => 1} qw(Binaries Binary Group Entry String Association Item DeletedObject)},
        start_handlers => {Group => sub {$level++}},
        end_handlers => {
            Meta => sub {
                my ($node, $parent) = @_;
                die "Found multiple intances of Meta.\n" if $META;
                $META = {};
                my $pro = delete($node->{'MemoryProtection'}) || {}; # flatten out protection
                @$node{map {s/Protect/protect_/; lc $_} keys %$pro} = map {$tri->($_)} values %$pro;
                for my $key (keys %$node) {
                    next if $key eq 'Binaries';
                    (my $copy = $key) =~ s/([a-z])([A-Z])/${1}_${2}/g;
                    $META->{lc $copy} = $copy =~ /_changed$/i ? $self->_parse_v2_date($node->{$key}) : $node->{$key};
                }
                $META->{'recycle_bin_enabled'} = $tri->($META->{'recycle_bin_enabled'});
                $META->{$_} = $uuid->($META->{$_}) for qw(entry_templates_group last_selected_group last_top_visible_group recycle_bin_uuid);
                die "HeaderHash recorded in file did not match actual hash of header.\n"
                    if $META->{'header_hash'} && $head->{'raw'} && $META->{'header_hash'} ne $self->encode_base64(sha256($head->{'raw'}));
            },
            Binary => sub {
                my ($node, $parent, $parent_tag, $tag) = @_;
                if ($parent_tag eq 'Binaries') {
                    my ($content, $id, $comp) = @$node{qw(content ID Compressed)};
                    $content = '' if ! defined $content;
                    $content = $self->decode_base64($content) if length $content;
                    if ($comp && $comp eq 'True' && length $content) {
                        eval {$content = $self->decompress($content)} or warn "Could not decompress associated binary ($id): $@";
                    }
                    warn "Duplicate binary id $id - using most recent.\n" if exists $BIN{$id};
                    $BIN{$id} = $content;
                } elsif ($parent_tag eq 'Entry') {
                    my $key = $node->{'Key'};
                    $key = do {warn "Missing key for binary."; 'unknown'} if ! defined $key;
                    warn "Duplicate binary key for entry." if $parent->{'__binary__'}->{$key};
                    $parent->{'__binary__'}->{$key} = $BIN{$node->{'Value'}->{'Ref'}};
                }
            },
            CustomData => sub {
                my ($node, $parent, $parent_tag, $tag) = @_;
                $parent->{$tag} = {map {$_->{'Key'} => $_->{'Value'}} @{$node->{'Item'} || []}}; # is order important?
            },
            Group => sub {
                my ($node, $parent, $parent_tag) = @_;
                my $group = {
                    id => $uuid->($node->{'UUID'}),
                    icon => $node->{'IconID'},
                    title => $node->{'Name'},
                    expanded => $tri->($node->{'IsExpanded'}),
                    level => $level,
                    accessed => $self->_parse_v2_date($node->{'Times'}->{'LastAccessTime'}),
                    expires => $self->_parse_v2_date($node->{'Times'}->{'ExpiryTime'}),
                    created => $self->_parse_v2_date($node->{'Times'}->{'CreationTime'}),
                    modified => $self->_parse_v2_date($node->{'Times'}->{'LastModificationTime'}),

                    auto_type_default => $node->{'DefaultAutoTypeSequence'},
                    auto_type_enabled => $tri->($node->{'EnableAutoType'}),
                    enable_searching => $tri->($node->{'EnableSearching'}),
                    last_top_entry => $uuid->($node->{'LastTopVisibleEntry'}),
                    expires_enabled => $tri->($node->{'Times'}->{'Expires'}),
                    location_changed => $self->_parse_v2_date($node->{'Times'}->{'LocationChanged'}),
                    usage_count => $node->{'Times'}->{'UsageCount'},
                    notes => $node->{'Notes'},

                    entries => delete($node->{'__entries__'}) || [],
                    groups => delete($node->{'__groups__'})  || [],
                };
                if ($parent_tag eq 'Group') {
                    push @{$parent->{'__groups__'}}, $group;
                } else {
                    push @GROUPS, $group;
                }
            },
            Entry => sub {
                my ($node, $parent, $parent_tag) = @_;
                my %str;
                for my $s (@{$node->{'String'} || []}) {
                    $str{$s->{'Key'}} = $s->{'Value'};
                    $str{'__protected__'}->{$s->{'Key'} =~ /^(Password|UserName|URL|Notes|Title)$/i ? lc($s->{'Key'}) : $s->{'Key'}} = 1 if $s->{'__protected__'};
                }
                my $entry = {
                    accessed => $self->_parse_v2_date($node->{'Times'}->{'LastAccessTime'}),
                    created => $self->_parse_v2_date($node->{'Times'}->{'CreationTime'}),
                    expires => $self->_parse_v2_date($node->{'Times'}->{'ExpiryTime'}),
                    modified => $self->_parse_v2_date($node->{'Times'}->{'LastModificationTime'}),
                    comment => delete($str{'Notes'}),
                    icon => $node->{'IconID'},
                    id => $uuid->($node->{'UUID'}),
                    title => delete($str{'Title'}),
                    url => delete($str{'URL'}),
                    username => delete($str{'UserName'}),
                    password => delete($str{'Password'}),

                    expires_enabled => $tri->($node->{'Times'}->{'Expires'}),
                    location_changed => $self->_parse_v2_date($node->{'Times'}->{'LocationChanged'}),
                    usage_count => $node->{'Times'}->{'UsageCount'},
                    tags => $node->{'Tags'},
                    background_color => $node->{'BackgroundColor'},
                    foreground_color => $node->{'ForegroundColor'},
                    override_url => $node->{'OverrideURL'},
                    auto_type => delete($node->{'AutoType'}->{'__auto_type__'}) || [],
                    auto_type_enabled => $tri->($node->{'AutoType'}->{'Enabled'}),
                    auto_type_munge => $node->{'AutoType'}->{'DataTransferObfuscation'} ? 1 : 0,
                    protected => delete($str{'__protected__'}),
                };
                $entry->{'history'} = $node->{'History'} if defined $node->{'History'};
                $entry->{'custom_icon_uuid'} = $node->{'CustomIconUUID'} if defined $node->{'CustomIconUUID'};
                $entry->{'strings'} = \%str if scalar keys %str;
                $entry->{'binary'} = delete($node->{'__binary__'}) if $node->{'__binary__'};
                push @{$parent->{'__entries__'}}, $entry;
            },
            String => sub {
                my $node = shift;
                my $val = $node->{'Value'};
                if (ref($val) eq 'HASH' && $val->{'Protected'} && $val->{'Protected'} eq 'True') {
                    $val = $val->{'content'};
                    $node->{'Value'} = (defined($val) && length($val)) ? $s20_stream->($self->decode_base64($val)) : '';
                    $node->{'__protected__'} = 1;
                }
            },
            Association => sub {
                my ($node, $parent) = @_;
                push @{$parent->{'__auto_type__'}},  {window => $node->{'Window'}, keys => $node->{'KeystrokeSequence'}};
            },
            History => sub {
                my ($node, $parent, $parent_tag, $tag) = @_;
                $parent->{$tag} = delete($node->{'__entries__'}) || [];
            },
            Association => sub {
                my ($node, $parent) = @_;
                push @{$parent->{'__auto_type__'}},  {window => $node->{'Window'}, keys => $node->{'KeystrokeSequence'}};
            },
            DeletedObject => sub {
                my ($node) = @_;
                push @{$GROUPS[0]->{'deleted_objects'}}, {
                    uuid => $self->decode_base64($node->{'UUID'}),
                    date => $self->_parse_v2_date($node->{'DeletionTime'}),
                } if $GROUPS[0] && $node->{'UUID'} && $node->{'DeletionTime'};
            },
        },
    });

    my $g = $GROUPS[0];
    @GROUPS = @{$g->{'groups'}} if @GROUPS == 1
        && $g && $g->{'notes'} && $g->{'notes'} eq "Added as a top group by File::KeePass"
        && @{$g->{'groups'} || []} && !@{$g->{'entries'} || []} && !$g->{'auto_type_default'};
    return ($META, \@GROUPS);
}

sub _parse_v1_groups {
    my ($self, $buffer, $n_groups) = @_;
    my $pos = 0;

    my @groups;
    my %gmap; # allow entries to find their groups (group map)
    my @gref = (\@groups); # group ref pointer stack - let levels nest safely
    my $group = {};
    while ($n_groups) {
        my $type = unpack 'S', substr($buffer, $pos, 2);
        $pos += 2;
        die "Group header offset is out of range. ($pos)" if $pos >= length($buffer);

        my $size = unpack 'L', substr($buffer, $pos, 4);
        $pos += 4;
        die "Group header offset is out of range. ($pos, $size)" if $pos + $size > length($buffer);

        if ($type == 1) {
            $group->{'id'} = unpack 'L', substr($buffer, $pos, 4);
        } elsif ($type == 2) {
            ($group->{'title'} = substr($buffer, $pos, $size)) =~ s/\0$//;
        } elsif ($type == 3) {
            $group->{'created'} = $self->_parse_v1_date(substr($buffer, $pos, $size));
        } elsif ($type == 4) {
            $group->{'modified'} = $self->_parse_v1_date(substr($buffer, $pos, $size));
        } elsif ($type == 5) {
            $group->{'accessed'} = $self->_parse_v1_date(substr($buffer, $pos, $size));
        } elsif ($type == 6) {
            $group->{'expires'} = $self->_parse_v1_date(substr($buffer, $pos, $size));
        } elsif ($type == 7) {
            $group->{'icon'} = unpack 'L', substr($buffer, $pos, 4);
        } elsif ($type == 8) {
            $group->{'level'} = unpack 'S', substr($buffer, $pos, 2);
        } elsif ($type == 0xFFFF) {
            $group->{'created'} ||= '';
            $n_groups--;
            $gmap{$group->{'id'}} = $group;
            my $level = $group->{'level'} || 0;
            if (@gref > $level + 1) {# gref is index base 1 because the root is a pointer to \@groups
                splice @gref, $level + 1;
            } elsif (@gref < $level + 1) {
                push @gref, ($gref[-1]->[-1]->{'groups'} = []);
            }
            push @{$gref[-1]}, $group;
            $group = {};
        } else {
            $group->{'unknown'}->{$type} = substr($buffer, $pos, $size);
        }
        $pos += $size;
    }

    return (\@groups, \%gmap, $pos);
}

sub _parse_v1_entries {
    my ($self, $buffer, $n_entries, $pos, $gmap, $groups) = @_;

    my $entry = {};
    while ($n_entries) {
        my $type = unpack 'S', substr($buffer, $pos, 2);
        $pos += 2;
        die "Entry header offset is out of range. ($pos)" if $pos >= length($buffer);

        my $size = unpack 'L', substr($buffer, $pos, 4);
        $pos += 4;
        die "Entry header offset is out of range for type $type. ($pos, ".length($buffer).", $size)" if $pos + $size > length($buffer);

        if ($type == 1) {
            $entry->{'id'} = substr($buffer, $pos, $size);
        } elsif ($type == 2) {
            $entry->{'group_id'} = unpack 'L', substr($buffer, $pos, 4);
        } elsif ($type == 3) {
            $entry->{'icon'} = unpack 'L', substr($buffer, $pos, 4);
        } elsif ($type == 4) {
            ($entry->{'title'} = substr($buffer, $pos, $size)) =~ s/\0$//;
        } elsif ($type == 5) {
            ($entry->{'url'} = substr($buffer, $pos, $size)) =~ s/\0$//;
        } elsif ($type == 6) {
            ($entry->{'username'} = substr($buffer, $pos, $size)) =~ s/\0$//;
        } elsif ($type == 7) {
            ($entry->{'password'} = substr($buffer, $pos, $size)) =~ s/\0$//;
        } elsif ($type == 8) {
            ($entry->{'comment'} = substr($buffer, $pos, $size)) =~ s/\0$//;
        } elsif ($type == 9) {
            $entry->{'created'} = $self->_parse_v1_date(substr($buffer, $pos, $size));
        } elsif ($type == 0xA) {
            $entry->{'modified'} = $self->_parse_v1_date(substr($buffer, $pos, $size));
        } elsif ($type == 0xB) {
            $entry->{'accessed'} = $self->_parse_v1_date(substr($buffer, $pos, $size));
        } elsif ($type == 0xC) {
            $entry->{'expires'} = $self->_parse_v1_date(substr($buffer, $pos, $size));
    } elsif ($type == 0xD) {
            ($entry->{'binary_name'} = substr($buffer, $pos, $size)) =~ s/\0$//;
    } elsif ($type == 0xE) {
            $entry->{'binary'} = substr($buffer, $pos, $size);
        } elsif ($type == 0xFFFF) {
            $entry->{'created'} ||= '';
            $n_entries--;
            my $gid = delete $entry->{'group_id'};
            my $ref = $gmap->{$gid};
            if (!$ref) {# orphaned nodes go in special group
                $gid = -1;
                if (!$gmap->{$gid}) {
                    push @$groups, ($gmap->{$gid} = {id => $gid, title => '*Orphaned*', icon => 0, created => $self->now});
                }
                $ref = $gmap->{$gid};
            }

            if ($entry->{'comment'} && $entry->{'comment'} eq 'KPX_GROUP_TREE_STATE') {
                if (!defined($entry->{'binary'}) || length($entry->{'binary'}) < 4) {
                    warn "Discarded metastream KPX_GROUP_TREE_STATE because of a parsing error."
                } else {
                    my $n = unpack 'L', substr($entry->{'binary'}, 0, 4);
                    if ($n * 5 != length($entry->{'binary'}) - 4) {
                        warn "Discarded metastream KPX_GROUP_TREE_STATE because of a parsing error.";
                    } else {
                        for (my $i = 0; $i < $n; $i++) {
                            my $group_id = unpack 'L', substr($entry->{'binary'}, 4 + $i * 5, 4);
                            my $is_expanded = unpack 'C', substr($entry->{'binary'}, 8 + $i * 5, 1);
                            $gmap->{$group_id}->{'expanded'} = $is_expanded;
                        }
                    }
                }
                $entry = {};
                next;
            }

            $self->_check_v1_binary($entry);
            $self->_check_v1_auto_type($entry);
            push @{$ref->{'entries'}}, $entry;
            $entry = {};
        } else {
            $entry->{'unknown'}->{$type} = substr($buffer, $pos, $size);
        }
        $pos += $size;
    }
}

sub _check_v1_binary {
    my ($self, $e) = @_;
    if (ref($e->{'binary'}) eq 'HASH') {
        delete $e->{'binary_name'};
        return;
    }
    my $bin = delete $e->{'binary'};
    my $bname = delete $e->{'binary_name'};
    if ((defined($bin) && length($bin)) || (defined($bname) && length($bname))) {
        defined($_) or $_ = '' for $bin, $bname;
        $e->{'binary'} = {$bname => $bin};
    }
}

sub _check_v1_auto_type {
    my ($self, $e, $del) = @_;
    $e->{'auto_type'} = [$e->{'auto_type'}] if ref($e->{'auto_type'}) eq 'HASH';
    if (ref($e->{'auto_type'}) eq 'ARRAY') {
        delete $e->{'auto_type_window'};
        return;
    }
    my @AT;
    my $key = delete $e->{'auto_type'};
    my $win = delete $e->{'auto_type_window'};
    if ((defined($key) && length($key)) || (defined($win) && length($win))) {
        push @AT, {keys => $key, window => $win};
    }
    return if ! $e->{'comment'};
    my %atw = my @atw = $e->{'comment'} =~ m{^Auto-Type-Window((?:-?\d+)?): [\t]* (.*?) [\t]*$}mxg;
    my %atk = my @atk = $e->{'comment'} =~ m{^Auto-Type((?:-?\d+)?): [\t]* (.*?) [\t]*$}mxg;
    $e->{'comment'} =~ s{^Auto-Type(?:-Window)?(?:-?\d+)?: .* \n?}{}mxg;
    while (@atw) {
        my ($n, $w) = (shift(@atw), shift(@atw));
        push @AT, {window => $w, keys => exists($atk{$n}) ? $atk{$n} : $atk{''}};
    }
    while (@atk) {
        my ($n, $k) = (shift(@atk), shift(@atk));
        push @AT, {keys => $k, window => exists($atw{$n}) ? $atw{$n} : $atw{''}};
    }
    for (@AT) {$_->{'window'} = '' if ! defined $_->{'window'}; $_->{'keys'} = '' if ! defined $_->{'keys'}}
    my %uniq;
    @AT = grep {!$uniq{"$_->{'window'}\e$_->{'keys'}"}++} @AT;
    $e->{'auto_type'} = \@AT if @AT;
}

sub _parse_v1_date {
    my ($self, $packed) = @_;
    my @b = unpack('C*', $packed);
    my $year = ($b[0] << 6) | ($b[1] >> 2);
    my $mon = (($b[1] & 0b11)     << 2) | ($b[2] >> 6);
    my $day = (($b[2] & 0b111111) >> 1);
    my $hour = (($b[2] & 0b1)      << 4) | ($b[3] >> 4);
    my $min = (($b[3] & 0b1111)   << 2) | ($b[4] >> 6);
    my $sec = (($b[4] & 0b111111));
    return sprintf "%04d-%02d-%02d %02d:%02d:%02d", $year, $mon, $day, $hour, $min, $sec;
}

sub _parse_v2_date {
    my ($self, $date) = @_;
    return ($date && $date =~ $qr_date) ? "$1-$2-$3 $4:$5:$6$7" : '';
}

sub _master_key {
    my ($self, $pass, $head) = @_;
    my $file;
    ($pass, $file) = @$pass if ref($pass) eq 'ARRAY';
    $pass = sha256($pass) if defined($pass) && length($pass);
    if ($file) {
        $file = ref($file) ? $$file : $self->slurp($file);
        if (length($file) == 64) {
            $file = join '', map {chr hex} ($file =~ /\G([a-f0-9A-F]{2})/g);
        } elsif (length($file) != 32) {
            $file = sha256($file);
        }
    }
    my $key = (!$pass && !$file) ? die "One or both of password or key file must be passed\n"
            : ($head->{'version'} && $head->{'version'} eq '2') ? sha256(grep {$_} $pass, $file)
            : ($pass && $file) ? sha256($pass, $file) : $pass ? $pass : $file;
    $head->{'enc_iv'}     ||= join '', map {chr rand 256} 1..16;
    $head->{'seed_rand'}  ||= join '', map {chr rand 256} 1..($head->{'version'} && $head->{'version'} eq '2' ? 32 : 16);
    $head->{'seed_key'}   ||= sha256(time.rand(2**32-1).$$);
    $head->{'rounds'} ||= $self->{'rounds'} || ($head->{'version'} && $head->{'version'} eq '2' ? 6_000 : 50_000);

    my $cipher = Crypt::Rijndael->new($head->{'seed_key'}, Crypt::Rijndael::MODE_ECB());
    $key = $cipher->encrypt($key) for 1 .. $head->{'rounds'};
    $key = sha256($key);
    $key = sha256($head->{'seed_rand'}, $key);
    return $key;
}

###----------------------------------------------------------------###

sub gen_db {
    my ($self, $pass, $head, $groups) = @_;
    $head ||= {};
    $groups ||= $self->groups;
    local $self->{'keep_xml'} = $head->{'keep_xml'} if exists $head->{'keep_xml'};
    my $v = $head->{'version'} || $self->{'version'};
    my $reuse = $head->{'reuse_header'}                        # explicit yes
                || (!exists($head->{'reuse_header'})           # not explicit no
                    && ($self->{'reuse_header'}                # explicit yes
                        || !exists($self->{'reuse_header'}))); # not explicit no
    if ($reuse) {
        ($head, my $args) = ($self->header || {}, $head);
        @$head{keys %$args} = values %$args;
    }
    $head->{'version'} = $v ||= $head->{'version'} || '1';
    delete @$head{qw(enc_iv seed_key seed_rand protected_stream_key start_bytes)} if $reuse && $reuse < 0;

    die "Missing pass\n" if ! defined($pass);
    die "Please unlock before calling gen_db\n" if $self->is_locked($groups);

    srand(rand(time() ^ $$)) if ! $self->{'no_srand'};
    if ($v eq '2') {
        return $self->_gen_v2_db($pass, $head, $groups);
    } else {
        return $self->_gen_v1_db($pass, $head, $groups);
    }
}

sub _gen_v1_db {
    my ($self, $pass, $head, $groups) = @_;
    if ($head->{'sig2'} && $head->{'sig2'} eq DB_SIG_2_v2) {
        substr($head->{'seed_rand'}, 16, 16, '') if $head->{'seed_rand'} && length($head->{'seed_rand'}) == 32; # if coming from a v2 db use a smaller key (roundtripable)
    }
    my $key = $self->_master_key($pass, $head);
    my $buffer = '';
    my $entries = '';
    my %gid;
    my $gid = sub {# v1 groups id size can only be a 32 bit int - v2 is supposed to be a 16 digit string
        local $_ = my $gid = shift;
        return $gid{$gid} ||= do {
            $_ = (/^\d+$/ && $_ < 2**32) ? $_ : /^([a-f0-9]{16})/i ? hex($1) : int(rand 2**32);
            $_ = int(rand 2**32) while $gid{"\e$_\e"}++;
            $_;
        };
    };
    my %uniq;
    my $uuid = sub {return $self->uuid(shift, \%uniq)};

    my @g = $self->find_groups({}, $groups);
    if (grep {$_->{'expanded'}} @g) {
        my $bin = pack 'L', scalar(@g);
        $bin .= pack('LC', $gid->($_->{'id'}), $_->{'expanded'} ? 1 : 0) for @g;
        my $e = ($self->find_entries({title => 'Meta-Info', username => 'SYSTEM', comment => 'KPX_GROUP_TREE_STATE', url => '$'}))[0] || $self->add_entry({
            comment => 'KPX_GROUP_TREE_STATE',
            title => 'Meta-Info',
            username => 'SYSTEM',
            url => '$',
            id => '0000000000000000',
            group => $g[0],
            binary => {'bin-stream' => $bin},
        });
    }
    $head->{'n_groups'} = $head->{'n_entries'} = 0;
    foreach my $g (@g) {
        $head->{'n_groups'}++;
        my @d = ([1,      pack('LL', 4, $gid->($g->{'id'}))],
                 [2,      pack('L', length($g->{'title'})+1)."$g->{'title'}\0"],
                 [3,      pack('L',  5). $self->_gen_v1_date($g->{'created'}  || $self->now)],
                 [4,      pack('L',  5). $self->_gen_v1_date($g->{'modified'} || $self->now)],
                 [5,      pack('L',  5). $self->_gen_v1_date($g->{'accessed'} || $self->now)],
                 [6,      pack('L',  5). $self->_gen_v1_date($g->{'expires'}  || $self->default_exp)],
                 [7,      pack('LL', 4, $g->{'icon'}  || 0)],
                 [8,      pack('LS', 2, $g->{'level'} || 0)],
                 [0xFFFF, pack('L', 0)]);
        push @d, [$_, map {pack('L',length $_).$_} $g->{'unknown'}->{$_}]
        for grep {/^\d+$/ && $_ > 8} keys %{$g->{'unknown'} || {}};
        $buffer .= pack('S',$_->[0]).$_->[1] for sort {$a->[0] <=> $b->[0]} @d;
        foreach my $e (@{$g->{'entries'} || []}) {
            $head->{'n_entries'}++;

            my $bins = $e->{'binary'} || {}; if (ref($bins) ne 'HASH') {warn "Entry binary field was not a hashref of name/content pairs.\n"; $bins = {}}
            my @bkeys = sort keys %$bins;
            warn "Found more than one entry in the binary hashref.  Encoding only the first one of (@bkeys) on a version 1 database.\n" if @bkeys > 1;
            my $bname = @bkeys ? $bkeys[0] : '';
            my $bin = $bins->{$bname}; $bin = '' if ! defined $bin;

            my $at = $e->{'auto_type'} || []; if (ref($at) ne 'ARRAY') {warn "Entry auto_type field was not an arrayref of auto_type info.\n"; $at = []}
            my %AT; my @AT;
            for (@$at) {
                my ($k, $w) = map {defined($_) ? $_ : ''} @$_{qw(keys window)};
                push @AT, $k if ! grep {$_ eq $k} @AT;
                push @{$AT{$k}}, $w;
            }
            my $txt = '';
            for my $i (1 .. @AT) {
                $txt .= "Auto-Type".($i>1 ? "-$i" : '').": $AT[$i-1]\n";
                $txt .= "Auto-Type-Window".($i>1 ? "-$i" : '').": $_\n" for @{$AT{$AT[$i-1]}};
            }
            my $com = defined($e->{'comment'}) ? "$txt$e->{'comment'}" : $txt;
            my @d = ([1,      pack('L', 16). $uuid->($e->{'id'})],
                     [2,      pack('LL', 4, $gid->($g->{'id'}))],
                     [3,      pack('LL', 4, $e->{'icon'} || 0)],
                     [4,      pack('L', length($e->{'title'})+1)."$e->{'title'}\0"],
                     [5,      pack('L', length($e->{'url'})+1).   "$e->{'url'}\0"],
                     [6,      pack('L', length($e->{'username'})+1). "$e->{'username'}\0"],
                     [7,      pack('L', length($e->{'password'})+1). "$e->{'password'}\0"],
                     [8,      pack('L', length($com)+1).  "$com\0"],
                     [9,      pack('L', 5). $self->_gen_v1_date($e->{'created'}  || $self->now)],
                     [0xA,    pack('L', 5). $self->_gen_v1_date($e->{'modified'} || $self->now)],
                     [0xB,    pack('L', 5). $self->_gen_v1_date($e->{'accessed'} || $self->now)],
                     [0xC,    pack('L', 5). $self->_gen_v1_date($e->{'expires'}  || $self->default_exp)],
                     [0xD,    pack('L', length($bname)+1)."$bname\0"],
                     [0xE,    pack('L', length($bin)).$bin],
                     [0xFFFF, pack('L', 0)]);
            push @d, [$_, pack('L', length($e->{'unknown'}->{$_})).$e->{'unknown'}->{$_}]
            for grep {/^\d+$/ && $_ > 0xE} keys %{$e->{'unknown'} || {}};
            $entries .= pack('S',$_->[0]).$_->[1] for sort {$a->[0] <=> $b->[0]} @d;
        }
    }
    $buffer .= $entries; $entries = '';

    require utf8;
    utf8::downgrade($buffer);
    $head->{'checksum'} = sha256($buffer);

    return $self->_gen_v1_header($head) . $self->encrypt_rijndael_cbc($buffer, $key, $head->{'enc_iv'});
}

sub _gen_v1_header {
    my ($self, $head) = @_;
    $head->{'sig1'} = DB_SIG_1;
    $head->{'sig2'} = DB_SIG_2_v1;
    $head->{'flags'} = DB_FLAG_RIJNDAEL;
    $head->{'ver'} = DB_VER_DW_V1;
    $head->{'n_groups'}  ||= 0;
    $head->{'n_entries'} ||= 0;
    die "Length of $_ was not 32 (".length($head->{$_}).")\n" for grep {length($head->{$_}) != 32} qw(seed_key checksum);
    die "Length of $_ was not 16 (".length($head->{$_}).")\n" for grep {length($head->{$_}) != 16} qw(enc_iv seed_rand);
    my @f = qw(sig1 sig2 flags ver seed_rand enc_iv n_groups n_entries checksum seed_key rounds);
    my $t = 'L    L    L     L   a16       a16    L        L         a32      a32      L';
    my $header = pack $t, @$head{@f};
    die "Invalid generated header\n" if length($header) != DB_HEADSIZE_V1;
    return $header;
}

sub _gen_v1_date {
    my ($self, $date) = @_;
    return "\0\0\0\0\0" if ! $date;
    my ($year, $mon, $day, $hour, $min, $sec) = $date =~ /^(\d\d\d\d)-(\d\d)-(\d\d) (\d\d):(\d\d):(\d\d)$/ ? ($1,$2,$3,$4,$5,$6) : die "Invalid date ($date)";
    return pack('C*',
                ($year >> 6) & 0b111111,
                (($year & 0b111111) << 2) | (($mon >> 2) & 0b11),
                (($mon & 0b11) << 6) | (($day & 0b11111) << 1) | (($hour >> 4) & 0b1),
                (($hour & 0b1111) << 4) | (($min >> 2) & 0b1111),
                (($min & 0b11) << 6) | ($sec & 0b111111),
               );
}

sub _gen_v2_db {
    my ($self, $pass, $head, $groups) = @_;
    if ($head->{'sig2'} && $head->{'sig2'} eq DB_SIG_2_v1) {
        $head->{'seed_rand'} = $head->{'seed_rand'}x2 if $head->{'seed_rand'} && length($head->{'seed_rand'}) == 16; # if coming from a v1 db augment the key (roundtripable)
    }
    $head->{'compression'} = 1 if ! defined $head->{'compression'};
    $head->{'start_bytes'} ||= join '', map {chr rand 256} 1 .. 32;
    $head->{'protected_stream_key'} ||= join '', map {chr rand 256} 1..32;
    my $key = $self->_master_key($pass, $head);
    my $header = $self->_gen_v2_header($head);

    my $buffer = '';
    my $untri = sub {return (!defined($_[0]) && !$_[1]) ? 'null' : !$_[0] ? 'False' : 'True'};
    my %uniq;
    my $uuid = sub {my $id = (defined($_[0]) && $_[0] eq '0') ? "\0"x16 : $self->uuid($_[0], \%uniq); return $self->encode_base64($id)};

    my @mfld = qw(Generator HeaderHash DatabaseName DatabaseNameChanged DatabaseDescription DatabaseDescriptionChanged DefaultUserName DefaultUserNameChanged
        MaintenanceHistoryDays Color MasterKeyChanged MasterKeyChangeRec MasterKeyChangeForce MemoryProtection
        RecycleBinEnabled RecycleBinUUID RecycleBinChanged EntryTemplatesGroup EntryTemplatesGroupChanged HistoryMaxItems HistoryMaxSize
        LastSelectedGroup LastTopVisibleGroup Binaries CustomData
    );
    my $META = {__sort__ => \@mfld};
    for my $key (@mfld) {
        (my $copy = $key) =~ s/([a-z])([A-Z])/${1}_${2}/g;
        $META->{$key} = $head->{lc $copy};
    }
    my $def = sub {
        my ($k, $d, $r) = @_;
        $META->{$k} = $d if !defined($META->{$k}) || ($r and $META->{$k} !~ $r);
        $META->{$k} = $self->_gen_v2_date($META->{$k}) if $k =~ /Changed$/;
    };
    my $now = $self->_gen_v2_date;
    $META->{'HeaderHash'} = $self->encode_base64(sha256($header));
    $def->(Color => '');
    $def->(DatabaseDescription => '');
    $def->(DatabaseDescriptionChanged => $now, $qr_date);
    $def->(DatabaseName => '');
    $def->(DatabaseNameChanged => $now, $qr_date);
    $def->(DefaultUserName => '');
    $def->(DefaultUserNameChanged => $now, $qr_date);
    $def->(EntryTemplatesGroupChanged => $now, $qr_date);
    $def->(Generator => ref($self));
    $def->(HistoryMaxItems => 10, qr{^\d+$});
    $def->(HistoryMaxSize => 6291456, qr{^\d+$});
    $def->(MaintenanceHistoryDays => 365, qr{^\d+$});
    $def->(MasterKeyChangeForce => -1);
    $def->(MasterKeyChangeRec => -1);
    $def->(MasterKeyChanged => $now, $qr_date);
    $def->(RecycleBinChanged => $now, $qr_date);
    $META->{$_} = $uuid->($META->{$_} || 0) for qw(EntryTemplatesGroup LastSelectedGroup LastTopVisibleGroup RecycleBinUUID);
    $META->{'RecycleBinEnabled'} = $untri->(exists($META->{'RecycleBinEnabled'}) ? $META->{'RecycleBinEnabled'} : 1, 1);
    my $p = $META->{'MemoryProtection'} ||= {};
    for my $new (qw(ProtectTitle ProtectUserName ProtectPassword ProtectURL ProtectNotes)) {# unflatten protection
        (my $key = lc $new) =~ s/protect/protect_/;
        push @{$p->{'__sort__'}}, $new;
        $p->{$new} = (exists($META->{$key}) ? delete($META->{$key}) : ($key eq 'protect_password')) ? 'True' : 'False';
    }
    my $cd = $META->{'CustomData'} ||= {};
    $META->{'CustomData'} = {Item => [map {{Key => $_, Value => $cd->{$_}}} sort keys %$cd]} if ref($cd) eq 'HASH' && scalar keys %$cd;

    my @GROUPS;
    my $BIN = $META->{'Binaries'}->{'Binary'} = [];
    my @PROTECT_BIN;
    my @PROTECT_STR;
    my $data = {
        Meta => $META,
        Root => {
            __sort__ => [qw(Group DeletedObjects)],
            Group => \@GROUPS,
            DeletedObjects => undef,
        },
    };

    my $gen_entry; $gen_entry = sub {
        my ($e, $parent) = @_;
        push @$parent, my $E = {
            __sort__ => [qw(UUID IconID ForegroundColor BackgroundColor OverrideURL Tags Times String AutoType History)],
            UUID => $uuid->($e->{'id'}),
            IconID => $e->{'icon'} || 0,
            Times => {
                __sort__ => [qw(LastModificationTime CreationTime LastAccessTime ExpiryTime Expires UsageCount LocationChanged)],
                Expires => $untri->($e->{'expires_enabled'}, 1),
                UsageCount => $e->{'usage_count'} || 0,
                LastAccessTime => $self->_gen_v2_date($e->{'accessed'}),
                ExpiryTime => $self->_gen_v2_date($e->{'expires'} || $self->default_exp),
                CreationTime => $self->_gen_v2_date($e->{'created'}),
                LastModificationTime => $self->_gen_v2_date($e->{'modified'}),
                LocationChanged => $self->_gen_v2_date($e->{'location_changed'}),
            },
            Tags => $e->{'tags'},
            BackgroundColor => $e->{'background_color'},
            ForegroundColor => $e->{'foreground_color'},
            CustomIconUUID => $uuid->($e->{'custom_icon_uuid'} || 0),
            OverrideURL => $e->{'override_url'},
            AutoType => {
                Enabled => $untri->(exists($e->{'auto_type_enabled'}) ? $e->{'auto_type_enabled'} : 1, 1),
                DataTransferObfuscation => $e->{'auto_type_munge'} ? 1 : 0,
            },
        };
        foreach my $key (sort(keys %{$e->{'strings'} || {}}), qw(Notes Password Title URL UserName)) {
            my $val = ($key eq 'Notes') ? $e->{'comment'} : ($key=~/^(Password|Title|URL|UserName)$/) ? $e->{lc $key} : $e->{'strings'}->{$key};
            next if ! defined $val;
            push @{$E->{'String'}}, my $s = {
                Key => $key,
                Value => $val,
            };
            if (($META->{'MemoryProtection'}->{"Protect${key}"} || '') eq 'True'
                || $e->{'protected'}->{$key =~ /^(Password|UserName|URL|Notes|Title)$/ ? lc($key) : $key}) {
                $s->{'Value'} = {Protected => 'True', content => $val};
                push @PROTECT_STR, \$s->{'Value'}->{'content'} if length $s->{'Value'}->{'content'};
            }
        }
        foreach my $at (@{$e->{'auto_type'} || []}) {
            push @{$E->{'AutoType'}->{'Association'}}, {
                Window => $at->{'window'},
                KeystrokeSequence => $at->{'keys'},
            };
        }
        my $bin = $e->{'binary'} || {}; $bin = {__anon__ => $bin} if ref($bin) ne 'HASH';
        splice @{$E->{'__sort__'}}, -2, 0, 'Binary' if scalar keys %$bin;
        foreach my $key (sort keys %$bin) {
            push @$BIN, my $b = {
                __attr__ => [qw(ID Compressed)],
                ID => $#$BIN+1,
                content => defined($bin->{$key}) ? $bin->{$key} : '',
            };
            $b->{'Compressed'} = (length($b->{'content'}) < 100 || $self->{'no_binary_compress'}) ? 'False' : 'True';
            if ($b->{'Compressed'} eq 'True') {
                eval {$b->{'content'} = $self->compress($b->{'content'})} or warn "Could not compress associated binary ($b->{'ID'}): $@";
            }
            $b->{'content'} = $self->encode_base64($b->{'content'});
            push @{$E->{'Binary'}}, {Key => $key, Value => {__attr__ => [qw(Ref)], Ref => $b->{'ID'}, content => ''}};
        }
        foreach my $h (@{$e->{'history'}||[]}) {
            $gen_entry->($h, $E->{'History'}->{'Entry'} ||= []);
        }
    };

    my $rec; $rec = sub {
        my ($group, $parent) = @_;
        return if ref($group) ne 'HASH';
        push @$parent, my $G = {
            __sort__ => [qw(UUID Name Notes IconID Times IsExpanded DefaultAutoTypeSequence EnableAutoType EnableSearching LastTopVisibleEntry)],
            UUID => $uuid->($group->{'id'}),
            Name => $group->{'title'} || '',
            Notes => $group->{'notes'},
            IconID => $group->{'icon'} || 0,
            Times => {
                __sort__ => [qw(LastModificationTime CreationTime LastAccessTime ExpiryTime Expires UsageCount LocationChanged)],
                Expires => $untri->($group->{'expires_enabled'}, 1),
                UsageCount => $group->{'usage_count'} || 0,
                LastAccessTime => $self->_gen_v2_date($group->{'accessed'}),
                ExpiryTime => $self->_gen_v2_date($group->{'expires'} || $self->default_exp),
                CreationTime => $self->_gen_v2_date($group->{'created'}),
                LastModificationTime => $self->_gen_v2_date($group->{'modified'}),
                LocationChanged => $self->_gen_v2_date($group->{'location_changed'}),
            },
            IsExpanded => $untri->($group->{'expanded'}, 1),
            DefaultAutoTypeSequence => $group->{'auto_type_default'},
            EnableAutoType => lc($untri->(exists($group->{'auto_type_enabled'}) ? $group->{'auto_type_enabled'} : 1)),
            EnableSearching => lc($untri->(exists($group->{'enable_searching'}) ? $group->{'enable_searching'} : 1)),
            LastTopVisibleEntry => $uuid->($group->{'last_top_entry'} || 0),
        };
        $G->{'CustomIconUUID'} = $uuid->($group->{'custom_icon_uuid'}) if $group->{'custom_icon_uuid'}; # TODO
        push @{$G->{'__sort__'}}, 'Entry' if @{$group->{'entries'} || []};
        foreach my $e (@{$group->{'entries'} || []}) {
            $gen_entry->($e, $G->{'Entry'} ||= []);
        }
        push @{$G->{'__sort__'}}, 'Group' if @{$group->{'groups'} || []};
        $rec->($_, $G->{'Group'} ||= []) for @{$group->{'groups'} || []};
    };
    $groups = [{title => "Database", groups => [@$groups], notes => "Added as a top group by File::KeePass", expanded => 1}] if @$groups > 1;
    $rec->($_, \@GROUPS) for @$groups;

    if (@$groups && $groups->[0]->{'deleted_objects'}) {
        foreach my $dob (@{$groups->[0]->{'deleted_objects'}}) {
            push @{$data->{'Root'}->{'DeletedObjects'}->{'DeletedObject'}}, {
                UUID => $self->encode_base64($dob->{'uuid'}),
                DeletionTime => $self->_gen_v2_date($dob->{'date'}),
            }
        }
    }

    my $s20_stream = $self->salsa20_stream({key => sha256($head->{'protected_stream_key'}), iv => $salsa20_iv, rounds => 20});
    for my $ref (@PROTECT_BIN, @PROTECT_STR) {
        $$ref = $self->encode_base64($s20_stream->($$ref));
    }

    # gen the XML - use our own generator since XML::Simple does not do event based actions
    $buffer = $self->gen_xml($data, {
        top => 'KeePassFile',
        indent => "\t",
        declaration => '<?xml version="1.0" encoding="utf-8" standalone="yes"?>',
        sort => {
            AutoType => [qw(Enabled DataTransferObfuscation Association)],
            Association => [qw(Window KeystrokeSequence)],
            DeletedObject => [qw(UUID DeletionTime)],
        },
        no_trailing_newline => 1,
    });
    $self->{'xml_out'} = $buffer if $self->{'keep_xml'} || $head->{'keep_xml'};

    $buffer = $self->compress($buffer) if $head->{'compression'} eq '1';
    $buffer = $self->chunksum($buffer);

    substr $buffer, 0, 0, $head->{'start_bytes'};

    return $header . $self->encrypt_rijndael_cbc($buffer, $key, $head->{'enc_iv'});
}

sub _gen_v2_date {
    my ($self, $date) = @_;
    $date = $self->now($date) if !$date || $date =~ /^\d+$/;
    my ($year, $mon, $day, $hour, $min, $sec) = $date =~ $qr_date ? ($1,$2,$3,$4,$5,$6) : die "Invalid date ($date)";
    return "${year}-${mon}-${day}T${hour}:${min}:${sec}Z";
}

sub _gen_v2_header {
    my ($self, $head) = @_;
    $head->{'sig1'} = DB_SIG_1;
    $head->{'sig2'} = DB_SIG_2_v2;
    $head->{'ver'} = DB_VER_DW_V2;
    $head->{'comment'} = '' if ! defined $head->{'comment'};
    $head->{'compression'} = (!defined($head->{'compression'}) || $head->{'compression'} eq '1') ? 1 : 0;
    $head->{'0'}           ||= "\r\n\r\n";
    $head->{'protected_stream_key'} ||= join '', map {chr rand 256} 1..32;
    die "Missing start_bytes\n" if ! $head->{'start_bytes'};
    die "Length of $_ was not 32 (".length($head->{$_}).")\n" for grep {length($head->{$_}) != 32} qw(seed_rand seed_key protected_stream_key start_bytes);
    die "Length of enc_iv was not 16\n" if length($head->{'enc_iv'}) != 16;

    my $buffer = pack 'L3', @$head{qw(sig1 sig2 ver)};

    my $pack = sub {my ($type, $str) = @_; $buffer .= pack('C S', $type, length($str)) . $str};
    $pack->(1, $head->{'comment'}) if defined($head->{'comment'}) && length($head->{'comment'});
    $pack->(2, "\x31\xc1\xf2\xe6\xbf\x71\x43\x50\xbe\x58\x05\x21\x6a\xfc\x5a\xff"); # aes cipher
    $pack->(3, pack 'V', $head->{'compression'} ? 1 : 0);
    $pack->(4, $head->{'seed_rand'});
    $pack->(5, $head->{'seed_key'});
    $pack->(6, pack 'LL', $head->{'rounds'}, 0); # a little odd to be double the length but not used
    $pack->(7, $head->{'enc_iv'});
    $pack->(8, $head->{'protected_stream_key'});
    $pack->(9, $head->{'start_bytes'});
    $pack->(10, pack('V', 2)); # salsa20 protection
    $pack->(0, $head->{'0'});
    return $buffer;
}

###----------------------------------------------------------------###

sub slurp {
    my ($self, $file) = @_;
    open my $fh, '<', $file or die "Could not open $file: $!\n";
    my $size = -s $file || die "File $file appears to be empty.\n";
    binmode $fh;
    read($fh, my $buffer, $size);
    close $fh;
    die "Could not read entire file contents of $file.\n" if length($buffer) != $size;
    return $buffer;
}

sub decrypt_rijndael_cbc {
    my ($self, $buffer, $key, $enc_iv) = @_;
    #use Crypt::CBC; return Crypt::CBC->new(-cipher => 'Rijndael', -key => $key, -iv => $enc_iv, -regenerate_key => 0, -prepend_iv => 0)->decrypt($buffer);
    my $cipher = Crypt::Rijndael->new($key, Crypt::Rijndael::MODE_CBC());
    $cipher->set_iv($enc_iv);
    $buffer = $cipher->decrypt($buffer);
    my $extra = ord(substr $buffer, -1, 1);
    substr($buffer, length($buffer) - $extra, $extra, '');
    return $buffer;
}

sub encrypt_rijndael_cbc {
    my ($self, $buffer, $key, $enc_iv) = @_;
    #use Crypt::CBC; return Crypt::CBC->new(-cipher => 'Rijndael', -key => $key, -iv => $enc_iv, -regenerate_key => 0, -prepend_iv => 0)->encrypt($buffer);
    my $cipher = Crypt::Rijndael->new($key, Crypt::Rijndael::MODE_CBC());
    $cipher->set_iv($enc_iv);
    my $extra = (16 - length($buffer) % 16) || 16; # always pad so we can always trim
    $buffer .= chr($extra) for 1 .. $extra;
    return $cipher->encrypt($buffer);
}

sub unchunksum {
    my ($self, $buffer) = @_;
    my ($new, $pos) = ('', 0);
    while ($pos < length($buffer)) {
        my ($index, $hash, $size) = unpack "\@$pos L a32 i", $buffer;
        $pos += 40;
        if ($size == 0) {
            warn "Found mismatch for 0 chunksize\n" if $hash ne "\0"x32;
            last;
        }
        #print "$index $hash $size\n";
        my $chunk = substr $buffer, $pos, $size;
        die "Chunk hash of index $index did not match\n" if $hash ne sha256($chunk);
        $pos += $size;
        $new .= $chunk;
    }
    return $new;
}

sub chunksum {
    my ($self, $buffer) = @_;
    my $new;
    my $index = 0;
    my $chunk_size = 8192;
    my $pos = 0;
    while ($pos < length($buffer)) {
        my $chunk = substr($buffer, $pos, $chunk_size);
        $new .= pack "L a32 i", $index++, sha256($chunk), length($chunk);
        $new .= $chunk;
        $pos += length($chunk);
    }
    $new .= pack "L a32 i", $index++, "\0"x32, 0;
    return $new;
}

sub decompress {
    my ($self, $buffer) = @_;
    eval {require Compress::Raw::Zlib} or die "Cannot load compression library to decompress database: $@";
    my ($i, $status) = Compress::Raw::Zlib::Inflate->new(-WindowBits => 31);
    die "Failed to initialize inflator ($status)\n" if $status != Compress::Raw::Zlib::Z_OK();
    $status = $i->inflate($buffer, my $out);
    die "Failed to uncompress buffer ($status)\n" if $status != Compress::Raw::Zlib::Z_STREAM_END();
    return $out;
}

sub compress {
    my ($self, $buffer) = @_;
    eval {require Compress::Raw::Zlib} or die "Cannot load compression library to compress database: $@";
    my ($d, $status) = Compress::Raw::Zlib::Deflate->new(-WindowBits => 31, -AppendOutput => 1);
    die "Failed to initialize inflator ($status)\n" if $status != Compress::Raw::Zlib::Z_OK();
    $status = $d->deflate($buffer, my $out);
    die "Failed to compress buffer ($status)\n" if $status != Compress::Raw::Zlib::Z_OK();
    $status = $d->flush($out);
    die "Failed to compress buffer ($status).\n" if $status != Compress::Raw::Zlib::Z_OK();
    return $out;
}

sub decode_base64 {
    my ($self, $content) = @_;
    eval {require MIME::Base64} or die "Cannot load Base64 library to decode item: $@";
    return MIME::Base64::decode_base64($content);
}

sub encode_base64 {
    my ($self, $content) = @_;
    eval {require MIME::Base64} or die "Cannot load Base64 library to encode item: $@";
    ($content = MIME::Base64::encode_base64($content)) =~ s/\n//g;
    return $content;
}

sub parse_xml {
    my ($self, $buffer, $args) = @_;
    eval {require XML::Parser} or die "Cannot load XML library to parse database: $@";
    my $top = $args->{'top'};
    my $force_array = $args->{'force_array'} || {};
    my $s_handlers = $args->{'start_handlers'} || {};
    my $e_handlers = $args->{'end_handlers'}   || $args->{'handlers'} || {};
    my $data;
    my $ptr;
    my $x = XML::Parser->new(Handlers => {
        Start => sub {
            my ($x, $tag, %attr) = @_; # loses multiple values of duplicately named attrs
            my $prev_ptr = $ptr;
            $top = $tag if !defined $top;
            if ($tag eq $top) {
                die "The $top tag should only be used at the top level.\n" if $ptr || $data;
                $ptr = $data = {};
            } elsif (exists($prev_ptr->{$tag})  || ($force_array->{$tag} and $prev_ptr->{$tag} ||= [])) {
                $prev_ptr->{$tag} = [$prev_ptr->{$tag}] if 'ARRAY' ne ref $prev_ptr->{$tag};
                push @{$prev_ptr->{$tag}}, ($ptr = {});
            } else {
                $ptr = $prev_ptr->{$tag} ||= {};
            }
            @$ptr{keys %attr} = values %attr;
            $_->($ptr, $prev_ptr, $prev_ptr->{'__tag__'}, $tag) if $_ = $s_handlers->{$tag} || $s_handlers->{'__any__'};
            @$ptr{qw(__parent__ __tag__)} = ($prev_ptr, $tag);
        },
        End => sub {
            my ($x, $tag) = @_;
            my $cur_ptr = $ptr;
            $ptr = delete $cur_ptr->{'__parent__'};
            die "End tag mismatch on $tag.\n" if $tag ne delete($cur_ptr->{'__tag__'});
            my $n_keys = scalar keys %$cur_ptr;
            if (!$n_keys) {
                $ptr->{$tag} = ''; # SuppressEmpty
            } elsif (exists $cur_ptr->{'content'}) {
                if ($n_keys == 1) {
                    if ($ptr->{$tag} eq 'ARRAY') {
                        $ptr->{$tag}->[-1] = $cur_ptr->{'content'};
                    } else {
                        $ptr->{$tag} = $cur_ptr->{'content'};
                    }
                } elsif ($cur_ptr->{'content'} !~ /\S/) {
                    delete $cur_ptr->{'content'};
                }
            }
            $_->($cur_ptr, $ptr, $ptr->{'__tag__'}, $tag) if $_ = $e_handlers->{$tag} || $e_handlers->{'__any__'};
        },
        Char => sub {if (defined $ptr->{'content'}) {$ptr->{'content'} .= $_[1]} else {$ptr->{'content'} = $_[1]} },
    });
    $x->parse($buffer);
    return $data;
}

sub gen_xml {
    my ($self, $ref, $args) = @_;
    my $indent = !$args->{'indent'} ? '' : $args->{'indent'} eq "1" ? "  " : $args->{'indent'};
    my $level = 0;
    my $top = $args->{'top'} || 'root';
    my $xml = $args->{'declaration'} || '';
    $xml .= "\n" . ($indent x $level) if $xml && $indent;
    $xml .= "<$top>";
    my $rec; $rec = sub {
        $level++;
        my ($ref, $tag) = @_;
        my $n = 0;
        my $order = delete($ref->{'__sort__'}) || $args->{'sort'}->{$tag} || [sort grep {$_ ne '__attr__'} keys %$ref];
        for my $key (@$order) {
            next if ! exists $ref->{$key};
            for my $node (ref($ref->{$key}) eq 'ARRAY' ? @{$ref->{$key}} : $ref->{$key}) {
                $n++;
                $xml .= "\n" . ($indent x $level) if $indent;
                if (!ref $node) {
                    $xml .= (!defined($node) || !length($node)) ? "<$key />" : "<$key>".$self->escape_xml($node)."</$key>";
                    next;
                }
                if ($node->{'__attr__'} || exists($node->{'content'})) {
                    $xml .= "<$key".join('', map {" $_=\"".$self->escape_xml($node->{$_})."\""} @{$node->{'__attr__'}||[sort grep {$_ ne 'content'} keys %$node]}).">";
                } else {
                    $xml .= "<$key>";
                }
                if (exists $node->{'content'}) {
                    if (defined($node->{'content'}) && length $node->{'content'}) {
                        $xml .= $self->escape_xml($node->{'content'}) . "</$key>";
                    } else {
                        $xml =~ s|(>\s*)$| /$1|;
                    }
                    next;
                }
                if ($rec->($node, $key)) {
                    $xml .= "\n" . ($indent x $level) if $indent;
                    $xml .= "</$key>";
                } else {
                    $xml =~ s|(>\s*)$| /$1|;
                }
            }
        }
        $level--;
        return $n;
    };
    $rec->($ref, $top);
    $xml .= "\n" . ($indent x $level) if $indent;
    $xml .= "</$top>";
    $xml .= "\n" if $indent && ! $args->{'no_trailing_newline'};
    return $xml;
}

sub escape_xml {
    my $self = shift;
    local $_ = shift;
    return '' if ! defined;
    s/&/&amp;/g;
    s/</&lt;/g;
    s/>/&gt;/g;
    s/"/&quot;/g;
    s/([^\x00-\x7F])/'&#'.(ord $1).';'/ge;
    return $_;
}

sub uuid {
    my ($self, $id, $uniq) = @_;
    $id = $self->gen_uuid if !defined($id) || !length($id);
    return $uniq->{$id} ||= do {
        if (length($id) != 16) {
            $id = substr($self->encode_base64($id), 0, 16) if $id !~ /^\d+$/ || $id > 2**32-1;
            $id = sprintf '%016s', $id if $id ne '0';
        }
        $id = $self->gen_uuid while $uniq->{$id}++;
        $id;
    };
}

sub gen_uuid {shift->encode_base64(join '', map {chr rand 256} 1..12)} # (3072 bit vs 4096) only 8e28 entries vs 3e38 - but readable

###----------------------------------------------------------------###

sub dump_groups {
    my ($self, $args, $groups) = @_;
    my $t = '';
    my %gargs; for (keys %$args) {$gargs{$2} = $args->{$1} if /^(group_(.+))$/};
    foreach my $g ($self->find_groups(\%gargs, $groups)) {
        my $indent = '    ' x $g->{'level'};
        $t .= $indent.($g->{'expanded'} ? '-' : '+')."  $g->{'title'} ($g->{'id'}) $g->{'created'}\n";
        local $g->{'groups'}; # don't recurse while looking for entries since we are already flat
        $t .= "$indent    > $_->{'title'}\t($_->{'id'}) $_->{'created'}\n" for $self->find_entries($args, [$g]);
    }
    return $t;
}

sub add_group {
    my ($self, $args, $top_groups) = @_;
    $args = {%$args};
    my $groups;
    my $parent_group = delete $args->{'group'};
    if (defined $parent_group) {
        $parent_group = $self->find_group({id => $parent_group}, $top_groups) if ! ref($parent_group);
        $groups = $parent_group->{'groups'} ||= [] if $parent_group;
    }
    $groups ||= $top_groups || ($self->{'groups'} ||= []);

    $args->{$_} = $self->now for grep {!defined $args->{$_}} qw(created accessed modified);;
    $args->{'expires'} ||= $self->default_exp;

    push @$groups, $args;
    $self->find_groups({}, $groups); # sets title, level, icon and id
    return $args;
}

sub finder_tests {
    my ($self, $args) = @_;
    my @tests;
    foreach my $key (keys %{$args || {}}) {
        next if ! defined $args->{$key};
        my ($field, $op) = ($key =~ m{^ (\w+) \s* (|!|=|!~|=~|gt|lt) $}x) ? ($1, $2) : die "Invalid find match criteria \"$key\"\n";
        push @tests,  (!$op || $op eq '=') ? sub {defined($_[0]->{$field}) && $_[0]->{$field} eq $args->{$key}}
                    : ($op eq '!')         ? sub {!defined($_[0]->{$field}) || $_[0]->{$field} ne $args->{$key}}
                    : ($op eq '=~')        ? sub {defined($_[0]->{$field}) && $_[0]->{$field} =~ $args->{$key}}
                    : ($op eq '!~')        ? sub {!defined($_[0]->{$field}) || $_[0]->{$field} !~ $args->{$key}}
                    : ($op eq 'gt')        ? sub {defined($_[0]->{$field}) && $_[0]->{$field} gt $args->{$key}}
                    : ($op eq 'lt')        ? sub {defined($_[0]->{$field}) && $_[0]->{$field} lt $args->{$key}}
                    : die "Unknown op \"$op\"\n";
    }
    return @tests;
}

sub find_groups {
    my ($self, $args, $groups, $level) = @_;
    my @tests = $self->finder_tests($args);
    my @groups;
    my %uniq;
    my $container = $groups || $self->groups;
    for my $g (@$container) {
        $g->{'level'} = $level || 0;
        $g->{'title'} = '' if ! defined $g->{'title'};
        $g->{'icon'}  ||= 0;
        if ($self->{'force_v2_gid'}) {
            $g->{'id'} = $self->uuid($g->{'id'}, \%uniq);
        } else {
            $g->{'id'} = int(rand 2**32-1) while !defined($g->{'id'}) || $uniq{$g->{'id'}}++; # the non-v2 gid is compatible with both v1 and our v2 implementation
        }

        if (!@tests || !grep{!$_->($g)} @tests) {
            push @groups, $g;
            push @{$self->{'__group_groups'}}, $container if $self->{'__group_groups'};
        }
        push @groups, $self->find_groups($args, $g->{'groups'}, $g->{'level'} + 1) if $g->{'groups'};
    }
    return @groups;
}

sub find_group {
    my $self = shift;
    local $self->{'__group_groups'} = [] if wantarray;
    my @g = $self->find_groups(@_);
    die "Found too many groups (@g)\n" if @g > 1;
    return wantarray ? ($g[0], $self->{'__group_groups'}->[0]) : $g[0];
}

sub delete_group {
    my $self = shift;
    my ($g, $c) = $self->find_group(@_);
    return if !$g || !$c;
    for my $i (0 .. $#$c) {
        next if $c->[$i] ne $g;
        splice(@$c, $i, 1, ());
        last;
    }
    return $g;
}

###----------------------------------------------------------------###

sub add_entry {
    my ($self, $args, $groups) = @_;
    $groups ||= eval {$self->groups} || [];
    die "You must unlock the passwords before adding new entries.\n" if $self->is_locked($groups);
    $args = {%$args};
    my $group = delete($args->{'group'}) || $groups->[0] || $self->add_group({});
    if (! ref($group)) {
        $group = $self->find_group({id => $group}, $groups) || die "Could not find a matching group to add entry to.\n";
    }

    my %uniq;
    foreach my $g ($self->find_groups({}, $groups)) {
        $uniq{$_->{'id'}}++ for @{$g->{'entries'} || []};
    }
    $args->{'id'} = $self->uuid($args->{'id'}, \%uniq);
    $args->{$_} = ''         for grep {!defined $args->{$_}} qw(title url username password comment);
    $args->{$_} = 0          for grep {!defined $args->{$_}} qw(icon);
    $args->{$_} = $self->now for grep {!defined $args->{$_}} qw(created accessed modified);
    $args->{'expires'} ||= $self->default_exp;
    $self->_check_v1_binary($args);
    $self->_check_v1_auto_type($args);


    push @{$group->{'entries'} ||= []}, $args;
    return $args;
}

sub find_entries {
    my ($self, $args, $groups) = @_;
    local @{$args}{'expires gt', 'active'} = ($self->now, undef) if $args->{'active'};
    my @tests = $self->finder_tests($args);
    my @entries;
    foreach my $g ($self->find_groups({}, $groups)) {
        foreach my $e (@{$g->{'entries'} || []}) {
            local $e->{'group_id'} = $g->{'id'};
            local $e->{'group_title'} = $g->{'title'};
            if (!@tests || !grep{!$_->($e)} @tests) {
                push @entries, $e;
                push @{$self->{'__entry_groups'}}, $g if $self->{'__entry_groups'};
            }
        }
    }
    return @entries;
}

sub find_entry {
    my $self = shift;
    local $self->{'__entry_groups'} = [] if wantarray;
    my @e = $self->find_entries(@_);
    die "Found too many entries (@e)\n" if @e > 1;
    return wantarray ? ($e[0], $self->{'__entry_groups'}->[0]) : $e[0];
}

sub delete_entry {
    my $self = shift;
    my ($e, $g) = $self->find_entry(@_);
    return if !$e || !$g;
    for my $i (0 .. $#{$g->{'entries'} || []}) {
        next if $g->{'entries'}->[$i] ne $e;
        splice(@{$g->{'entries'}}, $i, 1, ());
        last;
    }
    return $e;
}

sub now {
    my ($self, $time) = @_;
    my ($sec, $min, $hour, $day, $mon, $year) = localtime($time || time);
    return sprintf '%04d-%02d-%02d %02d:%02d:%02d', $year+1900, $mon+1, $day, $hour, $min, $sec;
}

sub default_exp {shift->{'default_exp'} || '2999-12-31 23:23:59'}

###----------------------------------------------------------------###

sub is_locked {
    my $self = shift;
    my $groups = shift || $self->groups;
    return $locker{"$groups"} ? 1 : 0;
}

sub lock {
    my $self = shift;
    my $groups = shift || $self->groups;
    return 2 if $locker{"$groups"}; # not quite as fast as Scalar::Util::refaddr

    my $ref = $locker{"$groups"} = {};
    $ref->{'_key'} = join '', map {chr rand 256} 1..32;
    $ref->{'_enc_iv'} = join '', map {chr rand 256} 1..16;

    foreach my $e ($self->find_entries({}, $groups)) {
        my $pass = delete $e->{'password'}; $pass = '' if ! defined $pass;
        $ref->{"$e"} = $self->encrypt_rijndael_cbc($pass, $ref->{'_key'}, $ref->{'_enc_iv'}); # we don't leave plaintext in memory
    }

    return 1;
}

sub unlock {
    my $self = shift;
    my $groups = shift || $self->groups;
    return 2 if !$locker{"$groups"};
    my $ref = $locker{"$groups"};
    foreach my $e ($self->find_entries({}, $groups)) {
        my $pass = $ref->{"$e"};
        $pass = eval {$self->decrypt_rijndael_cbc($pass, $ref->{'_key'}, $ref->{'_enc_iv'})} if $pass;
        $pass = '' if ! defined $pass;
        $e->{'password'} = $pass;
    }
    delete $locker{"$groups"};
    return 1;
}

sub locked_entry_password {
    my $self = shift;
    my $entry = shift;
    my $groups = shift || $self->groups;
    my $ref = $locker{"$groups"} || die "Passwords are not locked\n";
    $entry = $self->find_entry({id => $entry}, $groups) if ! ref $entry;
    return if ! $entry;
    my $pass = $ref->{"$entry"};
    $pass = eval {$self->decrypt_rijndael_cbc($pass, $ref->{'_key'}, $ref->{'_enc_iv'})} if $pass;
    $pass = '' if ! defined $pass;
    $entry->{'accessed'} = $self->now;
    return $pass;
}

###----------------------------------------------------------------###

sub salsa20_stream {
    my ($self, $args) = @_;
    delete $args->{'data'};
    my $salsa20 = $self->salsa20($args);
    my $buffer = '';
    return sub {
        my $enc = shift;
        $buffer .= $salsa20->("\0" x 64) while length($buffer) < length($enc);
        my $data = join '', map {chr(ord(substr $enc, $_, 1) ^ ord(substr $buffer, $_, 1))} 0 .. length($enc)-1;
        substr $buffer, 0, length($enc), '';
        return $data;
    };
}


sub salsa20 {# http://cr.yp.to/snuffle/salsa20/regs/salsa20.c
    my ($self, $args) = @_;
    my ($key, $iv, $rounds) = @$args{qw(key iv rounds)};
    $rounds ||= 20;

    my (@k, @c);
    if (32 == length $key) {
        @k = unpack 'L8', $key;
        @c = (0x61707865, 0x3320646e, 0x79622d32, 0x6b206574); # SIGMA
    } elsif (16 == length $key) {
        @k = unpack 'L8', $key x 2;
        @c = (0x61707865, 0x3120646e, 0x79622d36, 0x6b206574); # TAU
    } else {
        die "Salsa20 key length must be 16 or 32\n";
    }
    die "Salsa20 IV length must be 8\n" if length($iv) != 8;
    die "Salsa20 rounds must be 8, 12, or 20.\n" if !grep {$rounds != $_} 8, 12, 20;
    my @v = unpack('L2', $iv);

    #            0                                  5      6      7            10                                 # 15
    my @state = ($c[0], $k[0], $k[1], $k[2], $k[3], $c[1], $v[0], $v[1], 0, 0, $c[2], $k[4], $k[5], $k[6], $k[7], $c[3]);

    my $rotl32 = sub {return (($_[0] << $_[1]) | ($_[0] >> (32 - $_[1]))) & 0xffffffff};
    my $word_to_byte = sub {
        my @x = @state;
        for (1 .. $rounds/2) {
            $x[4] ^= $rotl32->(($x[0] + $x[12]) & 0xffffffff,  7);
            $x[8] ^= $rotl32->(($x[4] + $x[0]) & 0xffffffff,  9);
            $x[12] ^= $rotl32->(($x[8] + $x[4]) & 0xffffffff, 13);
            $x[0] ^= $rotl32->(($x[12] + $x[8]) & 0xffffffff, 18);
            $x[9] ^= $rotl32->(($x[5] + $x[1]) & 0xffffffff,  7);
            $x[13] ^= $rotl32->(($x[9] + $x[5]) & 0xffffffff,  9);
            $x[1] ^= $rotl32->(($x[13] + $x[9]) & 0xffffffff, 13);
            $x[5] ^= $rotl32->(($x[1] + $x[13]) & 0xffffffff, 18);
            $x[14] ^= $rotl32->(($x[10] + $x[6]) & 0xffffffff,  7);
            $x[2] ^= $rotl32->(($x[14] + $x[10]) & 0xffffffff,  9);
            $x[6] ^= $rotl32->(($x[2] + $x[14]) & 0xffffffff, 13);
            $x[10] ^= $rotl32->(($x[6] + $x[2]) & 0xffffffff, 18);
            $x[3] ^= $rotl32->(($x[15] + $x[11]) & 0xffffffff,  7);
            $x[7] ^= $rotl32->(($x[3] + $x[15]) & 0xffffffff,  9);
            $x[11] ^= $rotl32->(($x[7] + $x[3]) & 0xffffffff, 13);
            $x[15] ^= $rotl32->(($x[11] + $x[7]) & 0xffffffff, 18);

            $x[1] ^= $rotl32->(($x[0] + $x[3]) & 0xffffffff,  7);
            $x[2] ^= $rotl32->(($x[1] + $x[0]) & 0xffffffff,  9);
            $x[3] ^= $rotl32->(($x[2] + $x[1]) & 0xffffffff, 13);
            $x[0] ^= $rotl32->(($x[3] + $x[2]) & 0xffffffff, 18);
            $x[6] ^= $rotl32->(($x[5] + $x[4]) & 0xffffffff,  7);
            $x[7] ^= $rotl32->(($x[6] + $x[5]) & 0xffffffff,  9);
            $x[4] ^= $rotl32->(($x[7] + $x[6]) & 0xffffffff, 13);
            $x[5] ^= $rotl32->(($x[4] + $x[7]) & 0xffffffff, 18);
            $x[11] ^= $rotl32->(($x[10] + $x[9]) & 0xffffffff,  7);
            $x[8] ^= $rotl32->(($x[11] + $x[10]) & 0xffffffff,  9);
            $x[9] ^= $rotl32->(($x[8] + $x[11]) & 0xffffffff, 13);
            $x[10] ^= $rotl32->(($x[9] + $x[8]) & 0xffffffff, 18);
            $x[12] ^= $rotl32->(($x[15] + $x[14]) & 0xffffffff,  7);
            $x[13] ^= $rotl32->(($x[12] + $x[15]) & 0xffffffff,  9);
            $x[14] ^= $rotl32->(($x[13] + $x[12]) & 0xffffffff, 13);
            $x[15] ^= $rotl32->(($x[14] + $x[13]) & 0xffffffff, 18);
        }
        return pack 'L16', map {($x[$_] + $state[$_]) & 0xffffffff} 0 .. 15;
    };

    my $encoder = sub {
        my $enc = shift;
        my $out = '';
        while (length $enc) {
            my $stream = $word_to_byte->();
            $state[8] = ($state[8] + 1) & 0xffffffff;
            $state[9] = ($state[9] + 1) & 0xffffffff if $state[8] == 0;
            my $chunk = substr $enc, 0, 64, '';
            $out .= join '', map {chr(ord(substr $stream, $_, 1) ^ ord(substr $chunk, $_, 1))} 0 .. length($chunk)-1;
        }
        return $out;
    };
    return $encoder if !exists $args->{'data'};
    return $encoder->(defined($args->{'data'}) ? $args->{'data'} : '');
}

###----------------------------------------------------------------###

1;

__END__

=head1 SYNOPSIS

    use File::KeePass;
    use Data::Dumper qw(Dumper);

    my $k = File::KeePass->new;

    # read a version 1 or version 2 database
    $k->load_db($file, $master_pass); # errors die

    print Dumper $k->header;
    print Dumper $k->groups; # passwords are locked

    $k->unlock;
    print Dumper $k->groups; # passwords are now visible

    $k->clear; # delete current db from memory


    my $group = $k->add_group({
        title => 'Foo',
    }); # root level group
    my $gid = $group->{'id'};

    my $group = $k->find_group({id => $gid});
    # OR
    my $group = $k->find_group({title => 'Foo'});


    my $group2 = $k->add_group({
        title => 'Bar',
        group => $gid,
        # OR group => $group,
    }); # nested group


    my $e = $k->add_entry({
        title => 'Something',
        username => 'someuser',
        password => 'somepass',
        group => $gid,
        # OR group => $group,
    });
    my $eid = $e->{'id'};

    my $e = $k->find_entry({id => $eid});
    # OR
    my $e = $k->find_entry({title => 'Something'});

    $k->lock;
    print $e->{'password'}; # eq undef
    print $k->locked_entry_password($e); # eq 'somepass'

    $k->unlock;
    print $e->{'password'}; # eq 'somepass'


    # save out a version 1 database
    $k->save_db("/some/file/location.kdb", $master_pass);

    # save out a version 2 database
    $k->save_db("/some/file/location.kdbx", $master_pass);

    # save out a version 1 database using a password and key file
    $k->save_db("/some/file/location.kdb", [$master_pass, $key_filename]);


    # read database from a file
    $k->parse_db($pass_db_string, $pass);

    # generate a keepass version 1 database string
    my $pass_db_string = $k->gen_db($pass);

    # generate a keepass version 2 database string
    my $pass_db_string = $k->gen_db($pass);


=head1 DESCRIPTION

File::KeePass gives access to KeePass version 1 (kdb) and version 2
(kdbx) databases.

The version 1 and version 2 databases are very different in
construction, but the majority of information overlaps and many
algorithms are similar.  File::KeePass attempts to iron out as many of
the differences.

File::KeePass gives nearly raw data access.  There are a few utility
methods for manipulating groups and entries.  More advanced
manipulation can easily be layered on top by other modules.

File::KeePass is only used for reading and writing databases and for
keeping passwords scrambled while in memory.  Programs dealing with UI
or using of auto-type features are the domain of other modules on
CPAN.  File::KeePass::Agent is one example.

=head1 METHODS

=over 4

=item new

Takes a hashref or hash of arguments.  Returns a new File::KeePass
object.  Any named arguments are added to self.

=item load_db

Takes a kdb filename, a master password, and an optional argument
hashref.  Returns the File::KeePass object on success (can be called
as a class method).  Errors die.  The resulting database can be
accessed via various methods including $k->groups.

    my $k = File::KeePass->new;
    $k->load_db($file, $pwd);

    my $k = File::KeePass->load_db($file, $pwd);

    my $k = File::KeePass->load_db($file, $pwd, {auto_lock => 0});

The contents are read from file and passed to parse_db.

The password passed to load_db may be a composite key in
any of the following forms:

    "password"                   # password only
    ["password"]                 # same
    ["password", "keyfilename"]  # password and key file
    [undef, "keyfilename"]       # key file only
    ["password", \"keycontent"]  # password and reference to key file content
    [undef, \"keycontent"]       # reference to key file content only

The key file is optional.  It may be passed as a filename, or as a
scalar reference to the contents of the key file.  If a filename is
passed it will be read in.  The key file can contain any of the
following three types:

    length 32         # treated as raw key
    length 64         # must be 64 hexidecimal characters
    any-other-length  # a SHA256 sum will be taken of the data

=item save_db

Takes a kdb filename and a master password.  Stores out the current
groups in the object.  Writes attempt to write first to
$file.new.$epoch and are then renamed into the correct location.

You will need to unlock the db via $k->unlock before calling this
method if the database is currently locked.

The same master password types passed to load_db can be used here.

=item parse_db

Takes a string or a reference to a string containting an encrypted kdb
database, a master password, and an optional argument hashref.
Returns the File::KeePass object on success (can be called as a class
method).  Errors die.  The resulting database can be accessed via
various methods including $k->groups.

    my $k = File::KeePass->new;
    $k->parse_db($loaded_kdb, $pwd);

    my $k = File::KeePass->parse_db($kdb_buffer, $pwd);

    my $k = File::KeePass->parse_db($kdb_buffer, $pwd, {auto_lock => 0});

The same master password types passed to load_db can be used here.

=item parse_header

Used by parse_db.  Reads just the header information.  Can be used as
a basic KeePass file check.  The returned hash will contain version =>
1 or version => 2 depending upon which type of header is found.  Can
be called as a class method.

    my $head = File::KeePass->parse_header($kdb_buffer); # errors die
    printf "This is a version %d database\n", $head->{'version'};

=item gen_db

Takes a master password.  Optionally takes a "groups" arrayref and a
"headers" hashref.  If groups are not passed, it defaults to using the
currently loaded groups.  If headers are not passed, a fresh set of
headers are generated based on the groups and the master password.
The headers can be passed in to test round trip portability.

You will need to unlock the db via $k->unlock before calling this
method if the database is currently locked.

The same master password types passed to load_db can be used here.

=item header

Returns a hashref representing the combined current header and meta
information for the currently loaded database.

The following fields are present in both version 1 and version 2
style databases (from the header):

    enc_iv => "123456789123456", # rand
    enc_type => "rijndael",
    header_size => 222,
    seed_key => "1234567890123456", # rand (32 bytes on v2)
    seed_rand => "12345678901234567890123456789012", # rand
    rounds => 6000,
    sig1 => "2594363651",
    sig2 => "3041655655", # indicates db version
    ver => 196608,
    version => 1, # or 2

The following keys will be present after the reading of a version 2
database (from the header):

    cipher => "aes",
    compression => 1,
    protected_stream => "salsa20",
    protected_stream_key => "12345678901234567890123456789012", # rand
    start_bytes => "12345678901234567890123456789012", # rand

Additionally, items parsed from the Meta section of a version 2
database will be added.  The following are the available fields.

    color => "#4FFF00",
    custom_data => {key1 => "val1"},
    database_description => "database desc",
    database_description_changed => "2012-08-17 00:30:56",
    database_name => "database name",
    database_name_changed => "2012-08-17 00:30:56",
    default_user_name => "",
    default_user_name_changed => "2012-08-17 00:30:34",
    entry_templates_group => "VL5nOpzlFUevGhqL71/OTA==",
    entry_templates_group_changed => "2012-08-21 14:05:32",
    generator => "KeePass",
    history_max_items => 10,
    history_max_size => 6291456, # bytes
    last_selected_group => "SUgL30QQqUK3tOWuNKUYJA==",
    last_top_visible_group => "dC1sQ1NO80W7klmRhfEUVw==",
    maintenance_history_days => 365,
    master_key_change_force => -1,
    master_key_change_rec => -1,
    master_key_changed => "2012-08-17 00:30:34",
    protect_notes => 0,
    protect_password => 1,
    protect_title => 0,
    protect_url => 0,
    protect_username => 0
    recycle_bin_changed => "2012-08-17 00:30:34",
    recycle_bin_enabled => 1,
    recycle_bin_uuid => "SUgL30QQqUK3tOWuNKUYJA=="

When writing a database via either save_db or gen_db, these
fields can be set and passed along.  Optionally, it is possible
to pass along a key called reuse_header to let calls to save_db
and gen_db automatically use the contents of the previous header.

=item clear

Clears any currently loaded database.

=item auto_lock

Default true.  If true, passwords are automatically hidden when a
database loaded via parse_db or load_db.

    $k->auto_lock(0); # turn off auto locking

=item is_locked

Returns true if the current database is locked.

=item lock

Locks the database.  This moves all passwords into a protected, in
memory, encrypted storage location.  Returns 1 on success.  Returns 2
if the db is already locked.  If a database is loaded via parse_db or
load_db and auto_lock is true, the newly loaded database will start
out locked.

=item unlock

Unlocks a previously locked database.  You will need to unlock a
database before calling save_db or gen_db.

=back

=head1 GROUP/ENTRY METHODS

=over 4

=item dump_groups

Returns a simplified string representation of the currently loaded
database.

    print $k->dump_groups;

You can optionally pass a match argument hashref.  Only entries
matching the criteria will be returned.

=item groups

Returns an arrayref of groups from the currently loaded database.
Groups returned will be hierarchal.  Note, groups simply returns a
reference to all of the data.  It makes no attempts at cleaning up the
data (find_groups will make sure the data is groomed).

    my $g = $k->groups;

Groups will look similar to the following:

    $g = [{
         expanded => 0,
         icon => 0,
         id => 234234234, # under v1 this is a 32 bit int, under v2 it is a 16 char id
         title => 'Foo',
         level => 0,
         entries => [{
             accessed => "2010-06-24 15:09:19",
             comment => "",
             created => "2010-06-24 15:09:19",
             expires => "2999-12-31 23:23:59",
             icon => 0,
             modified => "2010-06-24 15:09:19",
             title => "Something",
             password => 'somepass', # will be hidden if the database is locked
             url => "",
             username => "someuser",
             id => "0a55ac30af68149f", # v1 is any hex char, v2 is any 16 char
         }],
         groups => [{
             expanded => 0,
             icon => 0,
             id => 994414667,
             level => 1,
             title => "Bar"
         }],
     }];

=item add_group

Adds a new group to the database.  Returns a reference to the new
group.  If a database isn't loaded, it begins a new one.  Takes a
hashref of arguments for the new entry including title, icon,
expanded.  A new random group id will be generated.  An optional group
argument can be passed.  If a group is passed the new group will be
added under that parent group.

    my $group = $k->add_group({title => 'Foo'});
    my $gid = $group->{'id'};

    my $group2 = $k->add_group({title => 'Bar', group => $gid});

The group argument's value may also be a reference to a group - such as
that returned by find_group.

=item finder_tests {

Used by find_groups and find_entries.  Takes a hashref of arguments
and returns a list of test code refs.

    {title => 'Foo'} # will check if title equals Foo
    {'title !' => 'Foo'} # will check if title does not equal Foo
    {'title =~' => qr{^Foo$}} # will check if title does matches the regex
    {'title !~' => qr{^Foo$}} # will check if title does not match the regex

=item find_groups

Takes a hashref of search criteria and returns all matching groups.
Can be passed id, title, icon, and level.  Search arguments will be
parsed by finder_tests.

    my @groups = $k->find_groups({title => 'Foo'});

    my @all_groups_flattened = $k->find_groups({});

The find_groups method also checks to make sure group ids are unique
and that all needed values are defined.

=item find_group

Calls find_groups and returns the first group found.  Dies if multiple
results are found.  In scalar context it returns only the group.  In
list context it returns the group, and its the arrayref in which it is
stored (either the root level group or a sub groups group item).

=item delete_group

Passes arguments to find_group to find the group to delete.  Then
deletes the group.  Returns the group that was just deleted.

=item add_entry

Adds a new entry to the database.  Returns a reference to the new
entry.  An optional group argument can be passed.  If a group is not
passed, the entry will be added to the first group in the database.  A
new entry id will be created if one is not passed or if it conflicts
with an existing group.

The following fields can be passed to both v1 and v2 databases.

    accessed => "2010-06-24 15:09:19", # last accessed date
    auto_type => [{keys => "{USERNAME}{TAB}{PASSWORD}{ENTER}", window => "Foo*"}],
    binary => {foo => 'content'}; # hashref of filename/content pairs
    comment => "", # a comment for the system - auto-type info is normally here
    created => "2010-06-24 15:09:19", # entry creation date
    expires => "2999-12-31 23:23:59", # date entry expires
    icon => 0, # icon number for use with agents
    modified => "2010-06-24 15:09:19", # last modified
    title => "Something",
    password => 'somepass', # will be hidden if the database is locked
    url => "http://",
    username => "someuser",
    id => "0a55ac30af68149f", # auto generated if needed, v1 is any hex char, v2 is any 16 char
    group => $gid, # which group to add the entry to

For compatibility with earlier versions of File::KeePass, it is
possible to pass in a binary and binary_name when creating an entry.
They will be automatically converted to the hashref of
filename/content pairs

    binary_name => "foo", # description of the stored binary - typically a filename
    binary => "content", # raw data to be stored in the system - typically a file

    # results in
    binary => {"foo" => "content"}

Typically, version 1 databases store their Auto-Type information
inside of the comment.  They are also limited to having only one key
sequence per entry.  File::KeePass 2+ will automatically parse
Auto-Type values passed in the entry comment and store them out as the
auto_type arrayref.  This arrayref is serialized back into the comment
section when saving as a version 1 database.  Version 2 databases have
a separate storage mechanism for Auto-Type.

    If you passed in:
    comment => "
       Auto-Type: {USERNAME}{TAB}{PASSWORD}{ENTER}
       Auto-Type-Window: Foo*
       Auto-Type-Window: Bar*
    ",

    Will result in:
    auto_type => [{
        keys => "{USERNAME}{TAB}{PASSWORD}{ENTER}",
        window => "Foo*"
     }, {
        keys => "{USERNAME}{TAB}{PASSWORD}{ENTER}",
        window => "Bar*"
     }],

The group argument value may be either an existing group id, or a
reference to a group - such as that returned by find_group.

When using a version 2 database, the following additional fields are
also available:

    expires_enabled => 0,
    location_changed => "2012-08-05 12:12:12",
    usage_count => 0,
    tags => {},
    background_color => '#ff0000',
    foreground_color => '#ffffff',
    custom_icon_uuid => '234242342aa',
    history => [], # arrayref of previous entry changes
    override_url => $node->{'OverrideURL'},
    auto_type_enabled => 1,
    auto_type_munge => 0, # whether or not to attempt two channel auto typing
    protected => {password => 1}, # indicating which strings were/should be salsa20 protected
    strings => {'other key' => 'other value'},

=item find_entries

Takes a hashref of search criteria and returns all matching groups.
Can be passed an entry id, title, username, comment, url, active,
group_id, group_title, or any other entry property.  Search arguments
will be parsed by finder_tests.

    my @entries = $k->find_entries({title => 'Something'});

    my @all_entries_flattened = $k->find_entries({});

=item find_entry

Calls find_entries and returns the first entry found.  Dies if
multiple results are found.  In scalar context it returns only the
entry.  In list context it returns the entry, and its group.

=item delete_entry

Passes arguments to find_entry to find the entry to delete.  Then
deletes the entry.  Returns the entry that was just deleted.

=item locked_entry_password

Allows access to individual passwords for a database that is locked.
Dies if the database is not locked.

=back

=head1 UTILITY METHODS

The following methods are general purpose methods used during the
parsing and generating of kdb databases.

=over 4

=item now

Returns the current localtime datetime stamp.

=item default_exp

Returns the string representing the default expires time of an entry.
Will use $self->{'default_exp'} or fails to the string '2999-12-31
23:23:59'.

=item decrypt_rijndael_cbc

Takes an encrypted string, a key, and an encryption_iv string.
Returns a plaintext string.

=item encrypt_rijndael_cbc

Takes a plaintext string, a key, and an encryption_iv string.  Returns
an encrypted string.

=item decode_base64

Loads the MIME::Base64 library and decodes the passed string.

=item encode_base64

Loads the MIME::Base64 library and encodes the passed string.

=item unchunksum

Parses and reassembles a buffer, reading in lengths, and checksums
of chunks.

=item decompress

Loads the Compress::Raw::Zlib library and inflates the contents.

=item compress

Loads the Compress::Raw::Zlib library and deflates the contents.

=item parse_xml

Loads the XML::Parser library and sets up a basic parser that can call
hooks at various events.  Without the hooks, it runs similarly to
XML::Simple::parse.

    my $data = $self->parse_xml($buffer, {
        top => 'KeePassFile',
        force_array => {Group => 1, Entry => 1},
        start_handlers => {Group => sub {$level++}},
        end_handlers => {Group => sub {$level--}},
    });

=item gen_xml

Generates XML from the passed data structure.  The output of parse_xml
can be passed as is.  Additionally hints such as __sort__ can be used
to order the tags of a node and __attr__ can be used to indicate which
items of a node are attributes.

=item salsa20

Takes a hashref containing a salsa20 key string (length 32 or 16), a
salsa20 iv string (length 8), number of salsa20 rounds (8, 12, or 20 -
default 20), and an optional data string.  The key and iv are used to
initialize the salsa20 encryption.

If a data string is passed, the string is salsa20 encrypted and
returned.

If no data string is passed a salsa20 encrypting coderef is returned.

    my $encoded = $self->salsa20({key => $key, iv => $iv, data => $data});
    my $uncoded = $self->salsa20({key => $key, iv => $iv, data => $encoded});
    # $data eq $uncoded

    my $encoder = $self->salsa20({key => $key, iv => $Iv}); # no data
    my $encoded = $encoder->($data);
    my $part2 = $encoder->($more_data); # continues from previous state

=item salsa20_stream

Takes a hashref that will be passed to salsa20.  Uses the resulting
encoder to generate a more continuous encoded stream.  The salsa20
method encodes in chunks of 64 bytes.  If a string is not a multiple
of 64, then some of the xor bytes are unused.  The salsa20_stream
method maintains a buffer of xor bytes to ensure that none are wasted.

    my $encoder = $self->salsa20_stream({key => $key, iv => $Iv}); # no data
    my $encoded = $encoder->("1234");   # calls salsa20->()
    my $part2 = $encoder->("1234");   # uses the same pad until 64 bytes are used

=back

=head1 OTHER METHODS

=over 4

=item _parse_v1_header

=item _parse_v1_body

=item _parse_v1_groups

=item _parse_v1_entries

=item _parse_v1_date

Utilities used for parsing version 1 type databases.

=item _parse_v2_header

=item _parse_v2_body

=item _parse_v2_date

Utilities used for parsing version 2 type databases.

=item _gen_v1_db

=item _gen_v1_header

=item _gen_v1_date

Utilities used to generate version 1 type databases.

=item _gen_v2_db

=item _gen_v2_header

=item _gen_v2_date

Utilities used to generate version 2 type databases.

=item _master_key

Takes the password and parsed headers.  Returns the
master key based on database type.

=back

=head1 ONE LINERS

(Long one liners)

Here is a version 1 to version 2, or version 2 to version 1 converter.
Simply change the extension of the two files.  Someday we will include
a kdb2kdbx utility to do this for you.

    perl -MFile::KeePass -e 'use IO::Prompt; $p="".prompt("Pass:",-e=>"*",-tty); File::KeePass->load_db(+shift,$p,{auto_lock=>0})->save_db(+shift,$p)' ~/test.kdb ~/test.kdbx

    # OR using graphical prompt
    perl -MFile::KeePass -e 'chop($p=`zenity --password`); File::KeePass->load_db(+shift,$p,{auto_lock=>0})->save_db(+shift,$p)' ~/test.kdbx ~/test.kdb

    # OR using pure perl (but echoes password)
    perl -MFile::KeePass -e 'print "Pass:"; chop($p=<STDIN>); File::KeePass->load_db(+shift,$p,{auto_lock=>0})->save_db(+shift,$p)' ~/test.kdbx ~/test.kdb

Dumping the XML from a version 2 database.

    perl -MFile::KeePass -e 'chop($p=`zenity --password`); print File::KeePass->load_db(+shift,$p,{keep_xml=>1})->{xml_in},"\n"' ~/test.kdbx

Outlining group information.

    perl -MFile::KeePass -e 'chop($p=`zenity --password`); print File::KeePass->load_db(+shift,$p)->dump_groups' ~/test.kdbx

Dumping header information

    perl -MFile::KeePass -MData::Dumper -e 'chop($p=`zenity --password`); print Dumper +File::KeePass->load_db(+shift,$p)->header' ~/test.kdbx

=head1 BUGS

Only Rijndael is supported when using v1 databases.

This module makes no attempt to act as a password agent.  That is the
job of File::KeePass::Agent.  This isn't really a bug but some people
will think it is.

Groups and entries don't have true objects associated with them.  At
the moment this is by design.  The data is kept as plain boring data.

=head1 SOURCES

Knowledge about the algorithms necessary to decode a KeePass DB v1
format was gleaned from the source code of keepassx-0.4.3.  That
source code is published under the GPL2 license.  KeePassX 0.4.3 bears
the copyright of

    Copyright (C) 2005-2008 Tarek Saidi <tarek.saidi@arcor.de>
    Copyright (C) 2007-2009 Felix Geyer <debfx-keepassx {at} fobos.de>

Knowledge about the algorithms necessary to decode a KeePass DB v2
format was gleaned from the source code of keepassx-2.0-alpha1.  That
source code is published under the GPL2 or GPL3 license.  KeePassX
2.0-alpha1 bears the copyright of

    Copyright: 2010-2012, Felix Geyer <debfx@fobos.de>
               2011-2012, Florian Geyer <blueice@fobos.de>

The salsa20 algorithm is based on
http://cr.yp.to/snuffle/salsa20/regs/salsa20.c which is listed as
Public domain (D. J. Bernstein).

The ordering and layering of encryption/decryption algorithms of
File::KeePass are of derivative nature from KeePassX and could not
have been created without this insight - though the perl code is from
scratch.

=head1 AUTHOR

Paul Seamons <paul@seamons.com>

=head1 LICENSE

This module may be distributed under the same terms as Perl itself.

=cut
