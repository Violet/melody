#!/usr/bin/perl

# Movable Type (r) Open Source (C) 2001-2009 Six Apart, Ltd.
# This program is distributed under the terms of the
# GNU General Public License, version 2.
#
# $Id$

use strict;
use warnings;
use Data::Dumper;
use English qw( -no_match_vars );

$OUTPUT_AUTOFLUSH = 1;

use Test::More;
use lib 't/lib';

BEGIN {
    plan skip_all => "Configuration file $ENV{MT_CONFIG} not found"
      if !-r "t/$ENV{MT_CONFIG}";
}

use MT::Test qw(:testdb :time);


package Zot;
use base 'MT::Object';
__PACKAGE__->install_properties( {
       column_defs =>
         { 'id' => 'integer not null auto_increment', 'x' => 'string(255)', },
       primary_key => 'id',
       datasource  => 'zot',
    }
);


package Test::GroupBy;
use base qw( Test::Class MT::Test );
use Test::More;
use POSIX qw(strftime);

sub reset_db : Test(setup) {
    my $self = shift;
    $self->clean_db();

    my @obj_data = ( {
                        class  => 'Foo',
                        id     => 1,
                        name   => 'foo',
                        text   => 'bar',
                        status => 2,
                     },
                     {
                        class  => 'Foo',
                        id     => 2,
                        name   => 'baz',
                        text   => 'quux',
                        status => 1,
                     },
                     {
                        class  => 'Bar',
                        __wait => 1,
                        id     => 1,
                        foo_id => 2,
                        name   => 'bar0',
                        status => 0,
                     },
                     {
                        class  => 'Bar',
                        __wait => 1,
                        id     => 2,
                        foo_id => 2,
                        name   => 'bar1',
                        status => 1,
                     },
                     {
                        class  => 'Bar',
                        __wait => 1,
                        id     => 3,
                        foo_id => 1,
                        name   => 'bar2',
                        status => 0,
                     },
    );

    for my $data (@obj_data) {
        my $class = delete $data->{class};
        my $wait  = delete $data->{__wait};
        my $obj   = $class->new;
        $obj->set_values($data);
        sleep($wait) if $wait;
        $obj->save();
    }
} ## end sub reset_db :

sub count_group_by : Tests(26) {

    # legacy way of specifying sort direction
    my $cgb_iter = Bar->count_group_by( { status => '0', },
                            { group => ['foo_id'], sort => 'foo_id desc', } );
    my ( $count, $bfid, $month );
    isa_ok( $cgb_iter, 'CODE' );
    ok( ( $count, $bfid ) = $cgb_iter->(), 'set' );
    is( $bfid,  2, 'id' );
    is( $count, 1, 'count4' );
    ok( ( $count, $bfid ) = $cgb_iter->(), 'set' );
    is( $bfid,  1, 'id' );
    is( $count, 1, 'count5' );
    ok( !$cgb_iter->(), 'no $iter' );

    # new way of specifying sort direction
    my $cgb_iter2 = Bar->count_group_by( { status => '0', },
          { group => ['foo_id'], sort => 'foo_id', direction => 'descend' } );

    isa_ok( $cgb_iter2, 'CODE' );
    ok( ( $count, $bfid ) = $cgb_iter2->(), 'set' );
    is( $bfid,  2, 'id' );
    is( $count, 1, 'count4' );
    ok( ( $count, $bfid ) = $cgb_iter2->(), 'set' );
    is( $bfid,  1, 'id' );
    is( $count, 1, 'count5' );
    ok( !$cgb_iter2->(), 'no $iter' );

    # legacy way of specifying sort direction
    my $cgb_iter3 = Bar->count_group_by(
                             undef,
                             {
                               group => ['extract(month from created_on)'],
                               sort  => 'extract(month from created_on) desc',
                             }
    );
    isa_ok( $cgb_iter3, 'CODE' );
    ok( ( $count, $month ) = $cgb_iter3->(), 'set' );
    is( int($month), int( strftime( "%m", localtime ) ), 'month' );
    is( $count, 3, 'count6' );
    ok( !$cgb_iter3->(), 'no $iter' );

    # new way of specifying sort direction
    my $cgb_iter4 = Bar->count_group_by(
         undef,
         {
           group => ['extract(month from created_on)'],
           sort  => [
                { column => 'extract(month from created_on)', desc => 'desc' }
           ]
         }
    );
    isa_ok( $cgb_iter4, 'CODE' );
    ok( ( $count, $month ) = $cgb_iter4->(), 'set' );
    is( int($month), int( strftime( "%m", localtime ) ), 'month' );
    is( $count, 3, 'count6' );
    ok( !$cgb_iter4->(), 'no $iter' );
} ## end sub count_group_by :

sub sum_group_by : Tests(7) {

    # Sum status values across groups of ids (that is, a group for each Foo).
    my $sgb = Foo->sum_group_by(
                                 undef,
                                 {
                                    sum       => 'status',
                                    group     => ['id'],
                                    direction => 'ascend',
                                 }
    );

    my ( $status, $id ) = $sgb->();
    ok( $status && $id, 'sum_group_by results had a first result' );
    is( $status, 1, q{sum_group_by result #1's status is 1} );
    is( $id,     2, 'sum_group_by result #1 was for Foo #2' );

    ( $status, $id ) = $sgb->();
    ok( $status && $id, 'sum_group_by results had a second result' );
    is( $status, 2, q{sum_group_by result #2's status is 2} );
    is( $id,     1, 'sum_group_by result #2 was for Foo #1' );

    ( $status, $id ) = $sgb->();
    ok( !$status, 'sum_group_by only had two results' );
} ## end sub sum_group_by :

sub avg_group_by : Tests(7) {
    my $agb = Foo->avg_group_by(
                                 undef,
                                 {
                                    avg       => 'status',
                                    group     => ['id'],
                                    direction => 'ascend',
                                 }
    );

    my ( $status, $id ) = $agb->();
    ok( $status && $id, 'avg_group_by results had a first result' );

    # Compare numerically; is() will compare stringwise.
    ok( $status == 1, q{avg_group_by result #1's status is 1} );
    is( $id, 2, 'avg_group_by result #1 was for Foo #2' );

    ( $status, $id ) = $agb->();
    ok( $status && $id, 'avg_group_by results had a second result' );

    # Compare numerically; is() will compare stringwise.
    ok( $status == 2, q{avg_group_by result #2's status is 2} );
    is( $id, 1, 'avg_group_by result #2 was for Foo #1' );

    ( $status, $id ) = $agb->();
    ok( !$status, 'avg_group_by only had two results' );
} ## end sub avg_group_by :

sub max_group_by : Tests(7) {
    my $mgb = Bar->max_group_by(
                                 undef,
                                 {
                                    join =>
                                      Foo->join_on(
                                            undef, { 'id' => \'=bar_foo_id', }
                                      ),
                                    group => ['foo_id'],
                                    max   => 'created_on',
                                 }
    );
    my ( $created_on, $foo_id ) = $mgb->();
    my $f1 = Foo->load(1);
    my $b3 = Bar->load(3);
    is( $foo_id, $f1->id, 'max_group_by had a second result' );

    #is($created_on, $b3->created_on, 'max_group_by had a second result');

    my $f2 = Foo->load(2);
    my $b2 = Bar->load(2);
    ( $created_on, $foo_id ) = $mgb->();
    is( $foo_id, $f2->id, 'max_group_by had a first result' );

    #is($created_on, $b2->created_on, 'max_group_by had a first result');

    ( $created_on, $foo_id ) = $mgb->();
    ok( !$created_on, 'max_group_by only had two results' );

    my $mgb2 = Bar->max_group_by(
                                  undef,
                                  {
                                     join =>
                                       Foo->join_on(
                                                   undef,
                                                   { 'id' => \'=bar_foo_id' },
                                                   { limit => 1 },
                                       ),
                                     group => ['foo_id'],
                                     max   => 'created_on',
                                  }
    );
    ( $created_on, $foo_id ) = $mgb2->();
    is( $foo_id, $f1->id, 'max_group_by with limit had a first result' );

    #is($created_on, $b3->created_on, 'max_group_by with limit had a first result');

    ( $created_on, $foo_id ) = $mgb2->();
    ok( !$created_on, 'max_group_by with limit only had one result' );

    my $mgb3 = Bar->max_group_by(
                                  undef,
                                  {
                                     join =>
                                       Foo->join_on(
                                                  undef,
                                                  { 'id'  => \'=bar_foo_id' },
                                                  { limit => 1, offset => 1 },
                                       ),
                                     group => ['foo_id'],
                                     max   => 'created_on',
                                  }
    );
    ( $created_on, $foo_id ) = $mgb3->();
    is( $foo_id, $f2->id,
        'max_group_by with limit and offset had a first result' );

    #is($created_on, $b2->created_on, 'max_group_by with limit and offset had a first result');

    ( $created_on, $foo_id ) = $mgb3->();
    ok( !$created_on,
        'max_group_by with limit and offset only had one result' );
} ## end sub max_group_by :

sub clean_db : Test(teardown) {
    MT::Test->reset_table_for(qw( Foo Bar ));
}


package Test::Search;
use Test::More;
use MT::Test;
use base qw( Test::Class MT::Test );

sub reset_db : Test(setup) {
    MT::Test->reset_table_for(qw( Foo Bar ));
}

sub make_basic_data {
    my $self = shift;
    $self->make_objects( {
                            __class => 'Foo',
                            __wait  => 1,
                            name    => 'foo',
                            text    => 'bar',
                            id      => 1,
                            status  => 2,
                         },
                         {
                            __class => 'Foo',
                            __wait  => 3,
                            name    => 'baz',
                            text    => 'quux',
                            id      => 2,
                            status  => 1,
                         },
    );
} ## end sub make_basic_data

sub make_pc_data {
    my $self = shift;
    $self->make_objects( {
           __class => 'Foo',
           name    => 'Apple',
           text    => 'MacBook',
           status  => 11,
        },
        {
           __class => 'Foo',
           name    => 'Linux',
           text    => 'Ubuntu',
           status  => 12,
        },
        {
           __class => 'Foo',
           name    => 'Microsoft',
           text    => 'Vista',
           status  => 13,
        },
        {
           __class => 'Foo',
           name    => 'Microsoft',
           text    => 'XP',
           status  => 10,
        },
        { __class => 'Foo', name => 'Apple', text => 'iBook', status => 10, },

        {
           __class => 'Bar',
           __wait  => 1,
           name    => 'Silverlight',
           status  => 2,
           foo_id  => 3,
        },
        {
           __class => 'Bar',
           __wait  => 1,
           name    => 'IronPython',
           status  => 3,
           foo_id  => 3,
        },
        {
           __class => 'Bar',
           __wait  => 1,
           name    => 'IronRuby',
           status  => 0,
           foo_id  => 1,
        },
    );
} ## end sub make_pc_data

sub basic : Tests(5) {
    my $self = shift;
    $self->make_basic_data();

    my $foo = Foo->load(1);    # not a search

    is_object( scalar Foo->load( { id => 1 } ),
               $foo, 'Foo #1 by id hash is Foo #1' );
    is_object( scalar Foo->load( { id => 1, name => 'foo' } ),
               $foo, 'Foo #1 by id-name hash is Foo #1' );
    is_object( scalar Foo->load( { name => 'foo' } ),
               $foo, 'Foo #1 by name hash is Foo #1' );
    is_object( scalar Foo->load( { created_on => $foo->created_on } ),
               $foo, 'Foo #1 by created_on hash is Foo #1' );
    is_object( scalar Foo->load( { status => 2 } ),
               $foo, 'Foo #1 by status hash is Foo #1' );
}

sub sorting : Tests(6) {
    my $self = shift;
    $self->make_basic_data();

    my ( $tmp, @tmp );
    my @foo = map { Foo->load($_) } ( 1 .. 2 );

    ## Load using descending sort (newest)
    $tmp = Foo->load(
                      undef,
                      {
                         sort      => 'created_on',
                         direction => 'descend',
                         limit     => 1
                      }
    );
    is_object( $tmp, $foo[1], 'Newest Foo is Foo #2' );

    ## Load using ascending sort (oldest)
    $tmp = Foo->load(
                      undef,
                      {
                         sort      => 'created_on',
                         direction => 'ascend',
                         limit     => 1
                      }
    );
    is_object( $tmp, $foo[0], 'Oldest Foo is Foo #1' );

    ## Load using descending sort with limit = 2
    @tmp = Foo->load(
                      undef,
                      {
                         sort      => 'created_on',
                         direction => 'descend',
                         limit     => 2
                      }
    );
    are_objects( \@tmp,
                 [ reverse @foo ],
                 'Two Foos newest-first load() finds Foos #2 and #1' );

    ## Load using descending sort by created_on, no limit
    @tmp
      = Foo->load( undef, { sort => 'created_on', direction => 'descend' } );
    are_objects( \@tmp,
                 [ reverse @foo ],
                 'All Foos newest-first load() finds Foos #2 and #1' );

    ## Load using ascending sort by status, no limit
    @tmp = Foo->load( undef, { sort => 'status', } );
    are_objects( \@tmp,
                 [ reverse @foo ],
                 'All Foos lowest-status-first load() finds Foos #2 and #1' );

    ## Load using 'last' where status == 2
    $tmp = Foo->load(
                      { status => 2 },
                      {
                         sort      => 'created_on',
                         direction => 'descend',
                         limit     => 1
                      }
    );
    is_object( $tmp, $foo[0], 'Newest status=2 Foo is Foo #1' );
} ## end sub sorting :

sub ranges : Tests(9) {
    my $self = shift;
    $self->make_basic_data();

    my $tmp;
    my @foo = map { Foo->load($_) } ( 1 .. 2 );

    ## Load using range search, one less than foo[1]->created_on and newer
    $tmp = Foo->load( { created_on => [ $foo[1]->column('created_on') - 1 ] },
                      { range => { created_on => 1 } } );
    is_object( $tmp, $foo[1],
               'Foo from open-ended date range before Foo #2 is Foo #2' );

    ## Load using EXCLUSIVE range search, up through the momment $foo[1] created
    $tmp = Foo->load( {
                         created_on => [
                                         $foo[1]->column('created_on') - 1,
                                         $foo[1]->column('created_on')
                         ]
                      },
                      { range => { created_on => 1 } }
    );
    ok( !$tmp,
        "Exclusive date range load() ending at Foo #1's date found no Foos" );

    $tmp = Foo->load( {
                         created_on => [
                                         $foo[1]->column('created_on'),
                                         $foo[1]->column('created_on') + 1
                         ]
                      },
                      { range => { created_on => 1 } }
    );
    ok( !$tmp,
        "Exclusive date range load() starting at Foo #1's date found no Foos"
    );

    ## Load using INCLUSIVE range search, up through the momment $foo[1] created
    $tmp = Foo->load( {
                         created_on => [
                                         $foo[1]->column('created_on') - 1,
                                         $foo[1]->column('created_on')
                         ]
                      },
                      { range_incl => { created_on => 1 } }
    );
    ok( $tmp, 'Loaded an object based on range_incl (ts-1 to ts)' );
    is_object(
               $tmp,
               $foo[1],
               "Foo from inclusive date-range load() ending at Foo #1's date is Foo #2"
    );

    $tmp = Foo->load( {
                         created_on => [
                                         $foo[1]->column('created_on'),
                                         $foo[1]->column('created_on') + 1
                         ]
                      },
                      { range_incl => { created_on => 1 } }
    );
    ok( $tmp, 'Loaded an object based on range_incl (ts to ts+1)' );
    is_object(
               $tmp,
               $foo[1],
               "Foo from inclusive date-range load() starting at Foo #1's date is Foo #2"
    );

    ## Check that range searches return nothing when nothing is in the range.
    $tmp = Foo->load( { created_on => [ undef, '19690101000000' ] },
                      { range => { created_on => 1 } } );
    ok( !$tmp, 'Prehistoric date range load() found no Foos' );

    ## Range search, all items with created_on less than foo[1]->created_on
    $tmp = Foo->load( {
                         created_on =>
                           [ undef, $foo[1]->column('created_on') - 1 ]
                      },
                      { range => { created_on => 1 } }
    );
    is_object(
               $tmp,
               $foo[0],
               "Foo from exclusive open-started date-range load() ending before Foo #1 is Foo #1"
    );
} ## end sub ranges :

sub alias : Tests(2) {
    my $self = shift;
    $self->make_pc_data();

    my $vista = Foo->load(3);    # not a search

    # select * from foo, bar bar1, bar bar2
    # where bar1.bar_foo_id = foo_id
    # and bar2.bar_foo_id = bar1.bar_foo_id
    # and bar1.status = 2
    # and bar2.status = 3
    my @a_foos = Foo->load(
                            undef,
                            {
                              join => [
                                     'Bar', undef,
                                     { foo_id => \'= foo_id', status => 2 },
                                     {
                                       join => [
                                            'Bar', undef,
                                            {
                                              foo_id => \'= bar1.bar_foo_id',
                                              status => 3
                                            },
                                            { alias => 'bar2' }
                                       ],
                                       alias => 'bar1'
                                     }
                              ],
                              sort      => 'created_on',
                              direction => 'descend',
                            }
    );
    are_objects( \@a_foos, [$vista],
                 'Has Bars with status=2 and status=3 (alias)' );

    @a_foos = Foo->load(
                        undef,
                        {
                          join => [
                                    'Bar', undef,
                                    { foo_id => \'= foo_id', status => 2 },
                                    {
                                      join => [
                                            'Bar', undef,
                                            {
                                              foo_id => \'= bar1.bar_foo_id',
                                              status => 0
                                            },
                                            { alias => 'bar2' }
                                      ],
                                      alias => 'bar1'
                                    }
                          ],
                          sort      => 'created_on',
                          direction => 'descend',
                        }
    );
    is_deeply( \@a_foos, [],
               'No Foo has Bars with status=2 and status=0 (alias)' );
} ## end sub alias :

sub conjunctions : Tests(4) {
    my $self = shift;
    $self->make_pc_data();
    my @foos = map { Foo->load($_) } ( 1 .. 5 );    # not a search

    my @res = Foo->load( [ { status => 10 }, -or => { name => 'Apple' }, ] );
    @res = sort { $a->id <=> $b->id } @res;
    are_objects( \@res, [ @foos[ 0, 3, 4 ] ], '-or results' );

    @res
      = Foo->load( [ { name => 'Microsoft' }, -and => { status => 10 }, ] );
    are_objects( \@res, [ $foos[3] ], '-and results' );

    @res = Foo->load( [
                        { status => { '<=' => 20 }, name => 'Apple' },
                        -and_not => { status => 11 },
                      ]
    );

    # where (foo_status <= 20 and foo_name = 'Apple') and not (foo_status = 11)
    are_objects( \@res, [ $foos[4] ], '-and_not results' );

    @res = Foo->load( [
                        { status => 10 },
                        -or => { name => 'Apple' },
                        -or => { name => { like => '%nux' } },
                      ]
    );
    @res = sort { $a->id <=> $b->id } @res;

    # where (foo_status = 10) or (foo_name = 'Apple') or (foo_name like '%nux')
    # (selects Apple+MacBook, Apple+iBook, Microsoft+XP, Linux+Ubuntu)
    are_objects( \@res, [ @foos[ 0, 1, 3, 4 ] ], 'big -or results' );
} ## end sub conjunctions :

sub early_ending_iterators : Tests(4) {
    my $self = shift;
    $self->make_pc_data();

    my ( $iter, $tmp, @tmp );
    my @foo = map { Foo->load($_) } ( 1 .. 5 );

    ## Load using descending sort (newest)
    $iter = Foo->load_iter(
                            undef,
                            {
                               join => [
                                         'Bar', 'foo_id', undef,
                                         {
                                           sort      => 'created_on',
                                           direction => 'descend',
                                           unique    => 1
                                         }
                               ]
                            }
    );
    $tmp = $iter->();
    is_object(
               $tmp,
               $foo[0],
               '(early ending iterator) Foo associated with the newest Bar is Foo #1'
    );
    eval { $iter->end(); };
    is( $@, q(), 'Iterator can be ended #1' );

    ## Load using ascending sort (oldest)
    $iter = Foo->load_iter(
                            undef,
                            {
                               join => [
                                         'Bar', 'foo_id', undef,
                                         {
                                           sort      => 'created_on',
                                           direction => 'ascend',
                                           unique    => 1
                                         }
                               ]
                            }
    );
    $tmp = $iter->();
    is_object(
               $tmp,
               $foo[2],
               '(early ending iterator) Foo associated with the oldest Bar is Foo #3'
    );
    eval { $iter->end(); };
    is( $@, q(), 'Iterator can be ended #2' );
} ## end sub early_ending_iterators :

sub clean_db : Test(teardown) {
    MT::Test->reset_table_for(qw( Foo Bar ));
}


package Test::Classy;
use Test::More;
use MT::Test;
use base qw( Test::Class MT::Test );

use Sock;

sub reset_db : Test(setup) {
    MT::Test->reset_table_for(qw( Sock ));
}

sub a_plain_old_sock : Tests(3) {
    my $s = Sock->new();
    $s->text('asf dasf');
    ok( $s->save(), 'A regular old sock could be saved' );
    is( $s->class, 'sock', q{A regular old sock's class is sock} );

    my $g = Classfree::Sock->load( $s->id );
    is( $g->class, 'sock',
        q{Class-unaware object says a regular old sock's class is sock too} );
}

sub sock_monkey_fish : Tests(8) {
    my $monkey = Sock::Monkey->new();
    $monkey->text('asf dasf');
    ok( $monkey->save(), 'A sock monkey could be saved' );
    is( $monkey->class, 'monkey', q{A sock monkey's class is monkey} );

    my $fish = Sock::Fish->new();
    $fish->text('asf dasf');
    ok( $fish->save(), 'A sock fish could be saved' );
    is( $fish->class, 'fish', q{A sock fish's class is fish} );

    my @socks = Sock->load();
    is( scalar @socks,
        0, 'Plain load looks for plain old socks and finds none' );

    @socks = Sock->load( { class => '*' } );
    is( scalar @socks, 2, 'Search for all Socks finds a pair of socks' );
    @socks = sort { ref($a) cmp ref($b) } @socks;
    is( ref $socks[0], 'Sock::Fish',
        'One of the discovered Socks is a fish' );
    is( ref $socks[1],
        'Sock::Monkey', 'The other discovered Sock is a monkey' );
} ## end sub sock_monkey_fish :

sub clean_db : Test(teardown) {
    MT::Test->reset_table_for(qw( Sock ));
}


package main;
use MT::Test;

Test::Class->runtests( 'Test::GroupBy', 'Test::Search', 'Test::Classy',
                       +137 );

my ( $foo, @foo, @bar );
my ( $tmp, @tmp );

# Test for existing table
ok( MT::Object->driver->dbd->ddl_class->column_defs('Foo'),
    "table mt_foo exists after upgrade" );

# Test for non-existent table
ok( !MT::Object->driver->dbd->ddl_class->column_defs('Zot'),
    "table mt_zot does not exist after upgrade where undefined" );

## Test creating object with new
##     test column access through column, then through AUTOLOAD
$foo = Foo->new;
isa_ok( $foo, 'Foo', 'New Foo could be created' );
$foo->column( 'name', 'foo' );
is( $foo->column('name'), 'foo',
    'Setting name field with column() persists through access' );
$foo->name('foo');
is( $foo->name, 'foo',
    'Setting name field with mutator method persists through access' );
$foo->status(2);
$foo->text('bar');

## Test saving created object
ok( $foo->save, 'A Foo could be saved' );
is( $foo->id, 1, 'First Foo was given an id of 1, says accessor method' );
is( $foo->column('id'), 1, 'First Foo was given an id of 1, says column()' );

is_object( scalar Foo->load(1), $foo, 'Foo #1 by id is Foo #1' );

##     Change column value, save, try to load using old value (fail?),
##     then load again using new value
$foo->status(0);
ok( $foo->save, 'Foo #1 saved with new status (0)' );
$tmp = Foo->load( { status => 2 } );
ok( !$tmp, 'Foo #1 no longer loads with old status (2)' );
$tmp = Foo->load( { status => 0 } );
is_object( $tmp, $foo, 'Foo #1 by new status (0) is Foo #1' );

## Create a new object so we can do range and last/first lookups.
## Sleep first so that they get different created_on timestamps.
sleep(3);

## Create new object for iterator testing
$foo[0] = $foo;
$foo[1] = Foo->new;
$foo[1]->name('baz');
$foo[1]->text('quux');
$foo[1]->status(1);
$foo[1]->save;

## TEST LOADING IN VARIOUS WAYS

## Load all objects via iterator
my $iter
  = Foo->load_iter( undef, { sort => 'created_on', direction => 'ascend' } );
isa_ok( $iter, 'CODE', "Iterator for all Foos" );
ok( $tmp = $iter->(), 'Iterator for our two Foos had one object' );
is_object( $tmp, $foo[0], "All Foo iterator's first Foo is Foo #1" );
ok( $tmp = $iter->(), 'Iterator for our two Foos had two objects' );
is_object( $tmp, $foo[1], "All Foo iterator's second Foo is Foo #2" );
ok( !$iter->(), 'Iterator for our two Foos did not have a third object' );

## Load all objects with status == 1 via iterator
$iter = Foo->load_iter( { status => 1 } );
isa_ok( $iter, 'CODE', "Iterator for status=1 Foos" );
ok( $tmp = $iter->(), 'Iterator for our status=1 Foos had one object' );
is_object( $tmp, $foo[1], "Status=1 Foo iterator's first Foo is Foo #2" );
ok( !$iter->(),
    "Iterator for our status=1 Foos did not have a second object" );

## Load using non-existent ID (should fail)
$tmp = Foo->load(3);
ok( !$tmp, 'There is no Foo #3' );


## Get count of objects
is( Foo->count(), 2, 'Count of all Foos finds both' );
is( Foo->count( { status => 0 } ),
    1, 'Count of all status=0 Foos finds all one' );
my $ranged_count = Foo->count( {
                                  created_on =>
                                    [ $foo[1]->column('created_on') - 1 ]
                               },
                               { range => { created_on => 1 } }
);
is( $ranged_count, 1,
    'Count of all Foos in open-ended date range starting before Foo #1 finds all one'
);

## Update status for later tests.
$foo[0]->status(2);
$foo[0]->save;

## Test start_val loads.
## Given the first Foo object, should load the "next" one
## (the one with a larger created_on time)
$tmp = Foo->load(
                  undef,
                  {
                     limit     => 1,
                     sort      => 'created_on',
                     direction => 'ascend',
                     start_val => $foo[0]->created_on
                  }
);
is_object( $tmp, $foo[1], 'Next newer Foo after Foo #1 is Foo #2' );

## Given the first Foo object, try to load the "previous" one
## (the one with a smaller created_on time). This should fail.
$tmp = Foo->load(
                  undef,
                  {
                     limit     => 1,
                     sort      => 'created_on',
                     direction => 'descend',
                     start_val => $foo[0]->created_on
                  }
);
ok( !$tmp, 'Search for next older Foo before Foo #1 found none' );

## Given the second Foo object, try to load the "previous" one
## (the one with a smaller created_on time). This should work.
$tmp = Foo->load(
                  undef,
                  {
                     limit     => 1,
                     sort      => 'created_on',
                     direction => 'descend',
                     start_val => $foo[1]->created_on
                  }
);
is_object( $tmp, $foo[0], 'Next older Foo before Foo #2 is Foo #1' );

## Given the second Foo object, try to load the "next" one
## (the one with a larger created_on time). This should fail.
$tmp = Foo->load(
                  undef,
                  {
                     limit     => 1,
                     sort      => 'created_on',
                     direction => 'ascend',
                     start_val => $foo[1]->created_on
                  }
);
ok( !$tmp, 'Search for next newer Foo after Foo #2 found none' );

## Now, given the second Foo object's created_on - 1, try to
## load the "previous" one. This should work.
$tmp = Foo->load(
                  undef,
                  {
                     limit     => 1,
                     sort      => 'created_on',
                     direction => 'descend',
                     start_val => $foo[1]->created_on - 1
                  }
);
is_object( $tmp, $foo[0],
           'Next older Foo before just before Foo #2 is Foo #1' );

## Now, given the second Foo object's created_on - 1, try to
## load the "next" one. This should work.
$tmp = Foo->load(
                  undef,
                  {
                     limit     => 1,
                     sort      => 'created_on',
                     direction => 'ascend',
                     start_val => $foo[1]->created_on - 1
                  }
);
is_object( $tmp, $foo[1],
           'Next newer Foo after just before Foo #2 is Foo #2' );

## Override created_on timestamp, make sure it works
my $ts = substr( $foo[1]->created_on, 0, -4 ) . '0000';
$foo[1]->created_on($ts);
$foo[1]->save;

@tmp = Foo->load(
                  undef,
                  {
                     sort      => 'created_on',
                     direction => 'descend',
                     limit     => 2
                  }
);
are_objects( \@tmp, \@foo,
             'Time-traveled Foos newest-first are Foos #1 and #2' );

## Test limit of 2 with direction descend, but without
## a sort option. This should sort by the most recently-added
## records, ie. sorted by ID, basically.
@tmp = Foo->load( undef, { direction => 'descend', limit => 2 } );
are_objects( \@tmp,
             [ reverse @foo ],
             'Foos highest-id-first are Foos #2 and #1' );

## Test loading using offset.
## Should load the second Foo object.
$tmp = Foo->load(
                  undef,
                  {
                     direction => 'descend',
                     sort      => 'created_on',
                     limit     => 1,
                     offset    => 1
                  }
);
is_object( $tmp, $foo[1], 'Second newest Foo is Foo #2' );

## We only have 2 Foo objects, so this should load
## only the second Foo object (because offset is 1).
@tmp = Foo->load(
                  undef,
                  {
                     direction => 'descend',
                     sort      => 'created_on',
                     limit     => 2,
                     offset    => 1
                  }
);
are_objects( \@tmp,
             [ $foo[1] ],
             'Second and third newest Foos is just Foo #2' );

## Should load the first Foo object (ascend with offset of 1).
$tmp = Foo->load(
                  undef,
                  {
                     direction => 'ascend',
                     sort      => 'created_on',
                     limit     => 1,
                     offset    => 1
                  }
);
is_object( $tmp, $foo[0], 'Second oldest Foo is Foo #1' );

## This should load only the first Foo object (because limit is 1).
@tmp = Foo->load(
                  undef,
                  {
                     direction => 'descend',
                     sort      => 'created_on',
                     fetchonly => ['id'],
                     limit     => 1
                  }
);
is( $tmp[0]->id, $foo[0]->id, 'The newest Foo is Foo #1 (fetchonly)' );

## Should load the first Foo object (ascend with offset of 1).
@tmp = Foo->load(
                  undef,
                  {
                     direction => 'ascend',
                     sort      => 'created_on',
                     fetchonly => ['id'],
                     limit     => 1,
                     offset    => 1
                  }
);
is( $tmp[0]->id, $foo[0]->id, 'Second oldest Foo is Foo #1 (fetchonly)' );

## Now test join loads.
## First we need to create a couple of Bar objects.
$bar[0] = Bar->new;
$bar[0]->foo_id( $foo[1]->id );
$bar[0]->name('bar0');
$bar[0]->status(0);
ok( $bar[0]->save, 'saved' );
sleep(2);    ## Sleep to ensure created_on timestamps are unique

$bar[1] = Bar->new;
$bar[1]->foo_id( $foo[1]->id );
$bar[1]->name('bar1');
$bar[1]->status(1);
ok( $bar[1]->save, 'saved' );
sleep(2);    ## Sleep to ensure created_on timestamps are unique

$bar[2] = Bar->new;
$bar[2]->foo_id( $foo[0]->id );
$bar[2]->name('bar2');
$bar[2]->status(0);
ok( $bar[2]->save, 'saved' );
sleep(2);    ## Sleep to ensure created_on timestamps are unique

## Get a count of all Foo objects in order of most recently
## created Bar object. No uniqueness requirement. This tests
## the on_load_complete temporary table stuff with count.

is(
    Foo->count(
                undef,
                {
                   join => [
                             'Bar', 'foo_id', undef,
                             {
                                unique    => 1,
                                sort      => 'created_on',
                                direction => 'descend',
                             }
                   ]
                }
    ),
    2,
    'There are 2 unique Foos associated with Bars'
);

## Now load all Foo objects in order of most recently
## created Bar object. Make sure they are unique.
@tmp = Foo->load(
                  undef,
                  {
                     join => [
                               'Bar', 'foo_id', undef,
                               {
                                  sort      => 'created_on',
                                  direction => 'descend',
                                  unique    => 1
                               }
                     ]
                  }
);
are_objects( \@tmp, \@foo, 'unique Foos associated with Bars, oldest first' );

## Use load_iter and do the same thing.
@tmp = ();
$iter = Foo->load_iter(
                        undef,
                        {
                           join => [
                                     'Bar', 'foo_id', undef,
                                     {
                                        sort      => 'created_on',
                                        direction => 'descend',
                                        unique    => 1
                                     }
                           ]
                        }
);

while ( my $obj = $iter->() ) {
    push @tmp, $obj;
}
are_objects( \@tmp, \@foo,
             'unique Foos associated with Bars, oldest first, by load_iter' );

## Load all Foo objects in order of most recently
## created Bar object. No uniqueness requirement.
@tmp = Foo->load(
                  undef,
                  {
                     join => [
                               'Bar', 'foo_id', undef,
                               {
                                  sort      => 'created_on',
                                  direction => 'descend',
                               }
                     ]
                  }
);
are_objects( \@tmp,
             [ @foo, $foo[1] ],
             'Foos associated with Bars, oldest first' );

## Use load_iter and do the same thing.
@tmp = ();
$iter = Foo->load_iter(
                        undef,
                        {
                           join => [
                                     'Bar', 'foo_id', undef,
                                     {
                                        sort      => 'created_on',
                                        direction => 'descend',
                                     }
                           ]
                        }
);
while ( my $obj = $iter->() ) {
    push @tmp, $obj;
}
are_objects( \@tmp,
             [ @foo, $foo[1] ],
             'Foos associated with Bars, oldest first, by load_iter' );

## Load last 1 Foo object in order of most recently
## created Bar object.
@tmp = Foo->load(
                  undef,
                  {
                     join => [
                               'Bar', 'foo_id', undef,
                               {
                                  sort      => 'created_on',
                                  direction => 'descend',
                                  unique    => 1,
                                  limit     => 1,
                               }
                     ]
                  }
);
are_objects( \@tmp, [ $foo[0] ], 'Foos associated with oldest Bar' );

## Use load_iter to do the same thing.
@tmp = ();
$iter = Foo->load_iter(
                        undef,
                        {
                           join => [
                                     'Bar', 'foo_id', undef,
                                     {
                                        sort      => 'created_on',
                                        direction => 'descend',
                                        unique    => 1,
                                        limit     => 1,
                                     }
                           ]
                        }
);
while ( my $obj = $iter->() ) {
    push @tmp, $obj;
}
are_objects( \@tmp,
             [ $foo[0] ],
             'Foos associated with oldest Bar, by load_iter' );

## Load all Foo objects where Bar.name = 'bar0'
@tmp = Foo->load(
                  undef,
                  {
                     join => [
                               'Bar', 'foo_id',
                               { name => 'bar0' },
                               {
                                  sort      => 'created_on',
                                  direction => 'descend',
                                  unique    => 1,
                               }
                     ]
                  }
);
are_objects( \@tmp, [ $foo[1] ], 'Foos associated with Bars named bar0' );

## Use load_iter and do the same thing.
@tmp = ();
$iter = Foo->load_iter(
                        undef,
                        {
                           join => [
                                     'Bar', 'foo_id',
                                     { name => 'bar0' },
                                     {
                                        sort      => 'created_on',
                                        direction => 'descend',
                                        unique    => 1,
                                     }
                           ]
                        }
);
while ( my $obj = $iter->() ) {
    push @tmp, $obj;
}
are_objects( \@tmp,
             [ $foo[1] ],
             'Foos associated with Bars named bar0, by load_iter' );

## foo[1] is older than foo[0] because we overrode the timestamp,
## so this should load foo[0]
@tmp = Foo->load(
                  undef,
                  {
                     sort      => 'created_on',
                     direction => 'descend',
                     limit     => 1,
                     join =>
                       [ 'Bar', 'foo_id', { status => 0 }, { unique => 1 } ]
                  }
);
are_objects( \@tmp, [ $foo[0] ], 'One Foo associated with Bars of status=0' );

## and load_iter
@tmp = ();
$iter = Foo->load_iter(
                        undef,
                        {
                           sort      => 'created_on',
                           direction => 'descend',
                           limit     => 1,
                           join      => [
                                    'Bar', 'foo_id',
                                    { status => 0 }, { unique => 1 }
                           ]
                        }
);
while ( my $obj = $iter->() ) {
    push @tmp, $obj;
}
are_objects( \@tmp,
             [ $foo[0] ],
             'One Foo associated with Bars of status=0, by load_iter' );

## This is the same join as the last one, but without the limit--so
## we should get both Foo objects this time, in descending order.
@tmp = Foo->load(
                  undef,
                  {
                     sort      => 'created_on',
                     direction => 'descend',
                     join =>
                       [ 'Bar', 'foo_id', { status => 0 }, { unique => 1 } ]
                  }
);
are_objects( \@tmp, \@foo, 'All Foos associated with Bars of status=0' );

## and load_iter.
@tmp = ();
$iter = Foo->load_iter(
                        undef,
                        {
                           sort      => 'created_on',
                           direction => 'descend',
                           join      => [
                                    'Bar', 'foo_id',
                                    { status => 0 }, { unique => 1 }
                           ]
                        }
);
while ( my $obj = $iter->() ) {
    push @tmp, $obj;
}
are_objects( \@tmp, \@foo,
             'All Foos associated with Bars of status=0, by load_iter' );

## Filter join results by providing a value for 'status'; only Foo[0]
## has a 'status' == 2, so only that record should be returned.
@tmp = Foo->load(
                  { status => 2 },
                  {
                     sort      => 'created_on',
                     direction => 'descend',
                     join =>
                       [ 'Bar', 'foo_id', { status => 0 }, { unique => 1 } ]
                  }
);
are_objects( \@tmp,
             [ $foo[0] ],
             'Foos of status=2 associated with Bars of status=0' );

## and load_iter.
@tmp = ();
$iter = Foo->load_iter(
                        { status => 2 },
                        {
                           sort      => 'created_on',
                           direction => 'descend',
                           join      => [
                                    'Bar', 'foo_id',
                                    { status => 0 }, { unique => 1 }
                           ]
                        }
);
while ( my $obj = $iter->() ) {
    push @tmp, $obj;
}
are_objects(
             \@tmp,
             [ $foo[0] ],
             'Foos of status=2 associated with Bars of status=0, by load_iter'
);

# Join across a column.
@tmp = Foo->load(
                  {},
                  {
                     sort      => 'created_on',
                     direction => 'descend',
                     join      => [
                              'Bar', undef,
                              { foo_id => \'= foo_id', status => 0 },
                              { unique => 1 }
                     ]
                  }
);
are_objects( \@tmp, \@foo, 'Foos loaded by explicit join across columns' );

@tmp = Foo->load(
                  { status => 2 },
                  {
                     sort      => 'created_on',
                     direction => 'descend',
                     join      => [
                              'Bar', undef,
                              { foo_id => \'= foo_id', status => 0 },
                              { unique => 1 }
                     ]
                  }
);
are_objects( \@tmp,
             [ $foo[0] ],
             'Foos of status=2 loaded by explicit join across columns' );

# and load_iter.
@tmp = ();
$iter = Foo->load_iter(
                        {},
                        {
                           sort      => 'created_on',
                           direction => 'descend',
                           join      => [
                                    'Bar', undef,
                                    { foo_id => \'= foo_id', status => 0 },
                                    { unique => 1 }
                           ]
                        }
);

while ( my $obj = $iter->() ) {
    push @tmp, $obj;
}
are_objects( \@tmp, \@foo,
             'Foos loaded by explicit join across columns, by load_iter' );

@tmp = ();
$iter = Foo->load_iter(
                        { status => 2 },
                        {
                           sort      => 'created_on',
                           direction => 'descend',
                           join      => [
                                    'Bar', undef,
                                    { foo_id => \'= foo_id', status => 0 },
                                    { unique => 1 }
                           ]
                        }
);
while ( my $obj = $iter->() ) {
    push @tmp, $obj;
}
are_objects(
       \@tmp,
       [ $foo[0] ],
       'Foos of status=2 loaded by explicit join across columns, by load_iter'
);

## TEST EXISTS METHOD
ok( $foo->exists, 'First Foo long saved exists in db' );
$tmp = Foo->new;
ok( !$tmp->exists, 'New Foo just created does not exist in db' );
$tmp->id(5);
ok( !$tmp->exists, 'New Foo just created with fake id does not exist in db' );

## Change foo[1]->status so that its value is unique (for index)
$foo[1]->status(5);
ok( $foo[1]->save, 'saved' );
ok( Foo->load( { status => 5 } ), 'loaded' );

## Test remove
ok( $foo[1]->remove, 'removed' );
ok( !Foo->load(2),   'not loaded' );
ok( !Foo->load( { status     => 5 } ),                   'not loaded' );
ok( !Foo->load( { name       => $foo[1]->name } ),       'not loaded' );
ok( !Foo->load( { created_on => $foo[1]->created_on } ), 'not loaded' );

## Test methods:
##     * properties
my $props1 = Foo->properties;
is( $props1->{audit},                    1,    'audit' );
is( scalar keys %{ $props1->{indexes} }, 3,    'indexes' );
is( $props1->{primary_key},              'id', 'id' );
is( scalar @{ $props1->{columns} },      9,    'columns' );
my $props2 = $foo->properties;
is( $props1, $props2, "$props1 is $props2" )
  ;    ## Same address, because same hashref

##     * column_names
my $cols = $foo->column_names;
isa_ok( $cols, 'ARRAY' );
my %cols = map { $_ => 1 } @$cols;
for (
    qw(id name status text data created_on created_by modified_on modified_by)
  )
{
    ok( $cols{$_}, 'cols' );
}

##     * column_values
my $vals = $foo->column_values;
isa_ok( $vals, 'HASH' );
is( $vals->{id},          $foo->id,          'id' );
is( $vals->{name},        $foo->name,        'name' );
is( $vals->{status},      $foo->status,      'status' );
is( $vals->{text},        $foo->text,        'text' );
is( $vals->{created_on},  $foo->created_on,  'created_on' );
is( $vals->{created_by},  $foo->created_by,  'created_by' );
is( $vals->{modified_on}, $foo->modified_on, 'modified_on' );
is( $vals->{modified_by}, $foo->modified_by, 'modified_by' );

##     * set_values
$vals = {
    id         => 5,
    name       => 'baz',
    status     => 7,
    text       => 'quux',
    created_on => 13209,
    created_by => 'bar',

    #modified_on => 39023, modified_by auto-set modified_on in our new code.
    modified_by => 'foo',
};
$foo->set_values($vals);
for my $col ( keys %$vals ) {
    is( $vals->{$col}, $foo->column($col), $col );
}

##     * binary data

my $binmonster = Foo->new;

$vals = { funky => "yes", monkey => "no", };

require MT::Serialize;
my $srlzr = MT::Serialize->new('MT');
$binmonster->data( $srlzr->serialize( \$vals ) );
my $x = $binmonster->save();
warn 'Failed binary data test: ' . $binmonster->errstr() unless $x;
ok( $x,              'saved' );
ok( $binmonster->id, 'id' );
Foo->driver->clear_cache if Foo->driver->can('clear_cache');
my $chk = Foo->load( $binmonster->id );

if ($chk) {
    my $chk_data = $chk->data;
    my $chk_vals = $srlzr->unserialize($chk_data);
    foreach ( keys %$vals ) {
        is( $$chk_vals->{$_}, $vals->{$_}, $_ );
    }
}
else {
    foreach ( keys %$vals ) {
        ok( 0, $_ );
    }
}

##     * datasource
is( $foo->table_name, 'mt_' . $foo->datasource, 'datasource' );

##     * clone
my $clone = $foo->clone_all;
for my $col (@$cols) {
    is( $clone->column($col), $foo->column($col), $col );
}

## Sleep first so that they get different created_on timestamps.
sleep(3);

Foo->set_by_key( { name => "this" } );
my $obj = Foo->load( { name => "this" } );
isa_ok( $obj, 'Foo' );

Foo->set_by_key( { name => "this" }, { status => 42 } );
$obj = Foo->load( { name => "this" } );
is( $obj && $obj->status, 42, 'status' );

Foo->set_by_key( { name => "this" }, { status => 47 } );
$obj = Foo->load( { name => "this" } );
is( $obj && $obj->status, 47, 'status' );

Foo->set_by_key( { name => "this", status => 47 }, { text => "spiffy" } );
$obj = Foo->load( { name => "this", status => 47 } );
is( $obj && $obj->text, 'spiffy', 'text' );

sleep(3);

Foo->set_by_key( { name => "that" }, { text => "Once" } );
$obj = Foo->load( { name => "that" } );
is( $obj && $obj->text, 'Once', 'text' );

Foo->driver->clear_cache if Foo->driver->can('clear_cache');
## Load use direct set of values for non-PK column
@tmp = Foo->load( { name => [qw(foo this)] } );
@tmp = sort { $a->name cmp $b->name } @tmp;
is( @tmp, 2, 'array length 2' );

is( Foo->count(), 4, 'check number of Foos' );

## check offsets without limits
## Should load the third and fourth Foo objects.
my $foo4 = Foo->load( { name => "this" } );
my $foo5 = Foo->load( { name => "that" } );
my $foo1
  = Foo->load( undef, { 'sort' => 'created_on', 'direction' => 'ascend' } );
my @offs = Foo->load(
                      undef,
                      {
                         direction => 'ascend',
                         sort      => 'created_on',
                         offset    => 2
                      }
);
is( @offs, 2, 'array length 2' );
isa_ok( $offs[0], 'Foo' );
is( $offs[0]->id, $foo4->id, 'id' );
isa_ok( $offs[1], 'Foo' );
is( $offs[1]->id, $foo5->id, 'id' );

## Should load the third and fourth Foo objects.
@offs = Foo->load(
                   undef,
                   {
                      direction => 'descend',
                      sort      => 'created_on',
                      offset    => 1
                   }
);
is( @offs, 3, 'array length 3' );
isa_ok( $offs[0], 'Foo' );
is( $offs[0]->id, $foo4->id, 'id' );
isa_ok( $offs[1], 'Foo' );
is( $offs[1]->id, $binmonster->id, 'id' );
isa_ok( $offs[2], 'Foo' );
is( $offs[2]->id, $foo1->id, 'id' );

# TODO: what are these even about?
SKIP: {
    skip( 1, '$tmp[0] undefined' ) unless $tmp[0];
    ok( $tmp[0] && ( $tmp[0]->name eq 'foo' ), 'name' );
}
SKIP: {
    skip( 1, '$tmp[1] undefined' ) unless $tmp[1];
    ok( $tmp[1] && ( $tmp[1]->name eq 'this' ), 'name' );
}

1;

