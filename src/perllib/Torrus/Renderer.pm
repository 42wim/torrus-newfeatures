#  Copyright (C) 2002  Stanislav Sinyagin
#
#  This program is free software; you can redistribute it and/or modify
#  it under the terms of the GNU General Public License as published by
#  the Free Software Foundation; either version 2 of the License, or
#  (at your option) any later version.
#
#  This program is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#  GNU General Public License for more details.
#
#  You should have received a copy of the GNU General Public License
#  along with this program; if not, write to the Free Software
#  Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.

# $Id$
# Stanislav Sinyagin <ssinyagin@yahoo.com>

package Torrus::Renderer;

use strict;

use Torrus::DB;
use Torrus::ConfigTree;
use Torrus::TimeStamp;
use Torrus::RPN;
use Torrus::Log;
use Torrus::SiteConfig;

use Torrus::Renderer::HTML;
use Torrus::Renderer::RRDtool;

# Inherit methods from these modules
use base qw(Torrus::Renderer::HTML
            Torrus::Renderer::RRDtool
            Torrus::Renderer::Frontpage
            Torrus::Renderer::AdmInfo);

sub new
{
    my $self = {};
    my $class = shift;
    bless $self, $class;

    if( not defined $Torrus::Global::cacheDir )
    {
        Error('$Torrus::Global::cacheDir must be defined');
        return undef;
    }
    elsif( not -d $Torrus::Global::cacheDir )
    {
        Error("No such directory: $Torrus::Global::cacheDir");
        return undef;
    }

    $self->{'db'} = new Torrus::DB('render_cache', -WriteAccess => 1);
    if( not defined( $self->{'db'} ) )
    {
        return undef;
    }

    return $self;
}


# Returns the absolute filename and MIME type:
#
# my($fname, $mimetype) = $renderer->render($config_tree, $token, $view);
#

sub render
{
    my $self = shift;
    my $config_tree = shift;
    my $token = shift;
    my $view = shift;
    my %new_options = @_;

    if( %new_options )
    {
        $self->{'options'} = \%new_options;
    }

    $self->checkAndClearCache( $config_tree );

    my($t_render, $t_expires, $filename, $mime_type);

    my $tree = $config_tree->treeName();

    if( not $config_tree->isTset($token) )
    {
        if( my $alias = $config_tree->isAlias($token) )
        {
            $token = $alias;
        }
        if( not defined( $config_tree->path($token) ) )
        {
            Error("No such token: $token");
            return undef;
        }
    }

    $view = $config_tree->getDefaultView($token) unless defined $view;

    my $uid = '';
    if( $self->{'options'}->{'uid'} )
    {
        $uid = $self->{'options'}->{'uid'};
    }

    my $cachekey = $self->cacheKey( $uid . ':' . $tree . ':' .
                                    $token . ':' . $view );

    ($t_render, $t_expires, $filename, $mime_type) =
        $self->getCache( $cachekey );

    if( defined( $filename ) )
    {
        if( $t_expires >= time() )
        {
            return ($Torrus::Global::cacheDir.'/'.$filename,
                    $mime_type, $t_expires - time());
        }
        # Else reuse the old filename
    }
    else
    {
        $filename = Torrus::Renderer::newCacheFileName();
    }

    my $cachefile = $Torrus::Global::cacheDir.'/'.$filename;

    my $method = 'render_' . $config_tree->getParam($view, 'view-type');

    ($t_expires, $mime_type) =
        $self->$method( $config_tree, $token, $view, $cachefile );

    if( %new_options )
    {
        delete $self->{'options'};
    }

    my @ret;
    if( defined($t_expires) and defined($mime_type) )
    {
        $self->setCache($cachekey, time(), $t_expires, $filename, $mime_type);
        @ret = ($cachefile, $mime_type, $t_expires - time());
    }

    return @ret;
}


sub cacheKey
{
    my $self = shift;
    my $keystring = shift;

    if( ref( $self->{'options'}->{'variables'} ) )
    {
        foreach my $name ( sort keys %{$self->{'options'}->{'variables'}} )
        {
            my $val = $self->{'options'}->{'variables'}->{$name};
            $keystring .= ':' . $name . '=' . $val;
        }
    }
    return $keystring;
}


sub getCache
{
    my $self = shift;
    my $keystring = shift;

    my $cacheval = $self->{'db'}->get( $keystring );

    if( defined($cacheval) )
    {
        return split(':', $cacheval);
    }
    else
    {
        return undef;
    }
}


sub setCache
{
    my $self = shift;
    my $keystring = shift;
    my $t_render = shift;
    my $t_expires = shift;
    my $filename = shift;
    my $mime_type = shift;

    $self->{'db'}->put( $keystring,
                        join(':',
                             ($t_render, $t_expires, $filename, $mime_type)));
}



sub checkAndClearCache
{
    my $self = shift;
    my $config_tree = shift;

    my $tree = $config_tree->treeName();

    Torrus::TimeStamp::init();
    my $known_ts = Torrus::TimeStamp::get($tree . ':renderer_cache');
    my $actual_ts = $config_tree->getTimestamp();
    if( $actual_ts >= $known_ts or
        time() >= $known_ts + $Torrus::Renderer::cacheMaxAge )
    {
        $self->clearcache();
        Torrus::TimeStamp::setNow($tree . ':renderer_cache');
    }
    Torrus::TimeStamp::release();
}


sub clearcache
{
    my $self = shift;

    Debug('Clearing renderer cache');
    my $cursor = $self->{'db'}->cursor( -Write => 1 );
    while( my ($key, $val) = $self->{'db'}->next( $cursor ) )
    {
        my($t_render, $t_expires, $filename, $mime_type) =  split(':', $val);

        unlink $Torrus::Global::cacheDir.'/'.$filename;
        $self->{'db'}->c_del( $cursor );
    }
    undef $cursor;
    Debug('Renderer cache cleared');
}


sub newCacheFileName
{
    while(1)
    {
        my $name = sprintf('%.10d', rand(1e9));
        if( not -r $Torrus::Global::cacheDir.'/'.$name )
        {
            Debug("Random file name: $name");
            return $name;
        }
    }
}

sub xmlnormalize
{
    my( $txt )= @_;

    $txt =~ s/\&/\&amp\;/gm;
    $txt =~ s/\</\&lt\;/gm;
    $txt =~ s/\>/\&gt\;/gm;
    $txt =~ s/\'/\&apos\;/gm;
    $txt =~ s/\"/\&quot\;/gm;

    return $txt;
}



1;


# Local Variables:
# mode: perl
# indent-tabs-mode: nil
# perl-indent-level: 4
# End: