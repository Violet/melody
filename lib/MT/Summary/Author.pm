# Movable Type (r) Open Source (C) 2001-2010 Six Apart, Ltd.
# This program is distributed under the terms of the
# GNU General Public License, version 2.
#
# $Id$

# Core Summary Object Framework functions for MT::Author

package MT::Summary::Author;

use strict;
use warnings;
use MT::Author;
use MT::Entry;

sub summarize_comment_count {
    my $author = shift;
    my ($terms) = @_;
    my %args;
    use MT::Comment;
    $args{join} = MT::Entry->join_on(
                                      undef,
                                      {
                                         id     => \'= comment_entry_id',
                                         status => MT::Entry::RELEASE(),
                                      }
    );
    my $comment_count =
      MT::Comment->count( { commenter_id => $author->id, visible => 1, },
                          \%args );
    return $comment_count;
}

sub expire_comment_count {
    my ( $parent_obj, $obj, $terms ) = @_;

    # action: save/remove
    # parent_obj => author, obj => the comment
    return unless ( $parent_obj and $parent_obj->id );
    $parent_obj->set_summary( $terms, 0 );
    $parent_obj->expire_summary($terms);
}

sub expire_comment_count_entry {
    my ( $parent_obj, $obj, $terms, $action, $orig ) = @_;
    use MT::Comment;
    if ( $action eq 'remove' ) {
        my $c_iter = MT::Comment->load_iter( { entry_id => $obj->id } );
        while ( my $c = $c_iter->() ) {
            if ( $c->commenter_id ) {
                my $a = MT::Author->load( $c->commenter_id );
                $a->expire_summary('comment_count');
                if ( !$a->summary_is_expired('comment_count') ) {
                    $a->set_summary( $terms, 0 );
                    $a->expire_summary('comment_count');
                }
            }
        }
    }
    elsif ( $action eq 'save' ) {
        if ( $obj->{changed_cols}->{status} ) {
            my $c_iter = MT::Comment->load_iter( { entry_id => $obj->id } );
            while ( my $c = $c_iter->() ) {
                if ( $c->commenter_id ) {
                    my $a = MT::Author->load( $c->commenter_id );
                    $a->expire_summary('comment_count');
                    if ( !$a->summary_is_expired('comment_count') ) {
                        $a->set_summary( $terms, 0 );
                        $a->expire_summary('comment_count');
                    }
                }
            }
        }
    }
} ## end sub expire_comment_count_entry

sub summarize_entry_count {
    my $author = shift;
    my ($terms) = @_;

    return MT->model('entry')->count( {
                                        author_id => $author->id,
                                        status    => MT::Entry::RELEASE(),
                                      },
    );
}

sub expire_entry_count {
    my ( $parent_obj, $obj, $terms, $action, $orig ) = @_;

    # action: save/remove
    # parent_obj => author, obj => the entry
    my $count = $parent_obj->summary($terms);
    if ( !defined $count || $count < 1 && $action eq 'remove' ) {
        $parent_obj->expire_summary($terms);
    }
    elsif ( $action eq 'remove' ) {
        if ( $obj->status == MT::Entry::RELEASE()
             and !$parent_obj->summary_is_expired($terms) )
        {
            $parent_obj->set_summary( $terms, $count - 1 );
        }
    }
    elsif ( $action eq 'save' ) {
        if ( $obj->{changed_cols}->{status}
             && ( ( $orig->{__orig_value}->{status} || 0 ) != $obj->status ) )
        {
            if ( ( $obj->status || 0 ) == MT::Entry::RELEASE()
                 && !$parent_obj->summary_is_expired($terms) )
            {
                $parent_obj->set_summary( $terms, $count + 1 );
            }
            elsif ( ( $orig->{__orig_value}->{status} || 0 )
                    == MT::Entry::RELEASE() )
            {
                my $orig_author;
                if ( $orig->{__orig_value}->{author_id} ) {
                    $orig_author = MT::Author->load(
                                         $orig->{__orig_value}->{author_id} );
                }
                else {
                    $orig_author = $parent_obj;
                }
                if ( $orig_author
                     and !$orig_author->summary_is_expired($terms) )
                {
                    my $orig_count = $orig_author->summary($terms);
                    if ( !defined $orig_count || $orig_count < 1 ) {
                        $orig_author->expire_summary($terms);
                    }
                    else {
                        $orig_author->set_summary( $terms, $orig_count - 1 );
                    }
                }
            } ## end elsif ( ( $orig->{__orig_value...}))
        } ## end if ( $obj->{changed_cols...})
        if (     $obj->status == MT::Entry::RELEASE()
             and $obj->{changed_cols}->{author_id}
             and !$obj->{changed_cols}->{id}
             and $orig->{__orig_value}->{author_id} )
        {
            my $orig_author
              = MT::Author->load( $orig->{__orig_value}->{author_id} );
            if ( $orig_author and !$orig_author->summary_is_expired($terms) )
            {
                my $orig_count = $orig_author->summary($terms);
                if ( !defined $orig_count || $orig_count < 1 ) {
                    $orig_author->expire_summary($terms);
                }
                else {
                    $orig_author->set_summary( $terms, $orig_count - 1 );
                }
            }
            if ( !$parent_obj->summary_is_expired($terms) ) {
                $parent_obj->set_summary( $terms, $count + 1 );
            }
        } ## end if ( $obj->status == MT::Entry::RELEASE...)
    } ## end elsif ( $action eq 'save')
    else {
        die "Incorrect action type '$action'; expected save/remove\n";
    }
} ## end sub expire_entry_count

# ============= tags ===============

###########################################################################

=head2 AuthorCommentCount

The number of comments left by the current author in context.

B<Example:>
    <mt:Authors>
    <$mt:AuthorDisplayName$>
        <ul>
            <li><$mt:AuthorCommentCount$> comments</li>
            <li><$mt:AuthorEntriesCount$> posts</li>
            <li><$mt:AuthorEntryCount$> published</li>
        </ul>
    </mt:Authors>

=cut

sub _hdlr_author_comment_count {
    my ( $ctx, $args, $cond ) = @_;
    my $author = $ctx->stash('author')
      or return $ctx->_no_author_error('MTAuthorCommentCount');

    return $ctx->count_format( $author->summarize('comment_count'), $args );
}

###########################################################################

=head2 AuthorEntriesCount

The number of entries created by the current author in context.

B<Example:>
    <mt:Authors>
    <$mt:AuthorDisplayName$>
        <ul>
            <li><$mt:AuthorCommentCount$> comments</li>
            <li><$mt:AuthorEntriesCount$> posts</li>
            <li><$mt:AuthorEntryCount$> published</li>
        </ul>
    </mt:Authors>

=cut

sub _hdlr_author_entries_count {
    my ( $ctx, $args, $cond ) = @_;
    my $author = $ctx->stash('author')
      or return $ctx->_no_author_error('MTAuthorEntryCount');

    return $ctx->count_format( $author->summarize('entry_count'), $args );
}

1;

__END__

=head1 NAME

MT::Summary::Author

=head1 METHODS

=head2 expire_comment_count

=head2 expire_comment_count_entry

=head2 expire_entry_count

=head2 summarize_comment_count

=head2 summarize_entry_count

=head1 AUTHOR & COPYRIGHT

Please see L<MT/AUTHOR & COPYRIGHT>.

=cut
