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

package Torrus::Renderer::HTML;

use strict;

use Torrus::ConfigTree;
use Torrus::Log;

use URI::Escape;
use POSIX;
use Template;

Torrus::SiteConfig::loadStyling();

# All our methods are imported by Torrus::Renderer;

sub render_html
{
    my $self = shift;
    my $config_tree = shift;
    my $token = shift;
    my $view = shift;
    my $outfile = shift;

    if( not -d $Torrus::Global::templateDir )
    {
        Error('$Torrus::Global::templateDir is not defined or incorrect');
        exit(1);
    }

    my $tmplfile = $config_tree->getParam($view, 'html-template');

    # Create the Template Toolkit processor once, and reuse
    # it in subsequent render() calls

    if( not defined( $self->{'tt'} ) )
    {
        $self->{'tt'} =
            new Template(INCLUDE_PATH => $Torrus::Global::templateDir,
                         TRIM => 1);
    }
    my $ttvars =
    {
        'treeName'   => $config_tree->treeName(),
        'token'      => $token,
        'view'       => $view,
        'path'       => sub { return $config_tree->path($_[0]); },
        'pathToken'  => sub { return $config_tree->token($_[0]); },
        'nodeExists' => sub { return $config_tree->nodeExists($_[0]); },
        'children'   => sub { return $config_tree->getChildren($_[0]); },
        'isLeaf'     => sub { return $config_tree->isLeaf($_[0]); },
        'isAlias'    => sub { return $config_tree->isAlias($_[0]); },
        'sortTokens' => sub { return $self->sortTokens($config_tree,
                                                       $_[0]); },
        'nodeName'   => sub { return $config_tree->nodeName($_[0]); },
        'parent'     => sub { return $config_tree->getParent($_[0]); },
        'nodeParam'  => sub { return $config_tree->getNodeParam(@_); },
        'param'      => sub { return $config_tree->getParam(@_); },
        'url'        => sub { return $self->makeURL($config_tree, 0, @_); },
        'pathUrl'    => sub { return $self->makeURL($config_tree, 1, @_); },
        'plainURL'   => $Torrus::Renderer::plainURL,
        'splitUrls'  => sub { return $self->makeSplitURLs($config_tree,
                                                          $_[0], $_[1]); },
        'topURL'     => $Torrus::Renderer::rendererURL,
        'rrprint'    => sub { return $self->rrPrint($config_tree,
                                                    $_[0], $_[1]); },
        'scale'      => sub { return $self->scale($_[0], $_[1]); },
        'tsetMembers' => sub { $config_tree->tsetMembers($_[0]); },
        'tsetList'   => sub { $config_tree->getTsets(); },
        'style'      => sub { return $self->style($_[0]); },
        'companyName'=> $Torrus::Renderer::companyName,
        'companyURL' => $Torrus::Renderer::companyURL,
        'siteInfo'   => $Torrus::Renderer::siteInfo,
        'treeInfo'   => sub { return $Torrus::Global::treeConfig{
            $config_tree->treeName()}{'info'}; },
        'version'    => $Torrus::Global::version,
        'xmlnorm'    => \&Torrus::Renderer::xmlnormalize,
        'userAuth'   => $Torrus::ApacheHandler::authorizeUsers,
        'uid'        => $self->{'options'}->{'uid'},
        'userAttr'   => sub { return $self->userAttribute( $_[0] ) },
        'mayDisplayAdmInfo' => sub {
            return $self->may_display_adminfo( $config_tree, $_[0] ) },
        'adminfo' => $self->{'adminfo'},
        'timestamp'  => sub { return strftime($Torrus::Renderer::timeFormat,
                                              localtime(time())); },
        'markup'     => sub{ return $self->translateMarkup( @_ ); }
    };
    
    
    # Pass the options from Torrus::Renderer::render() to Template
    while( my( $opt, $val ) = each( %{$self->{'options'}} ) )
    {
        $ttvars->{$opt} = $val;
    }

    my $result = $self->{'tt'}->process( $tmplfile, $ttvars, $outfile );

    undef $ttvars;

    if( not $result )
    {
        if( $config_tree->isTset( $token ) )
        {
            Error("Error while rendering tokenset $token: " .
                  $self->{'tt'}->error());
        }
        else
        {
            my $path = $config_tree->path($token);
            Error("Error while rendering $path: " .
                  $self->{'tt'}->error());
        }
        return undef;
    }

    return ($config_tree->getParam($view, 'expires')+time(),
            'text/html; charset=UTF-8');
}


sub sortTokens
{
    my $self = shift;
    my $config_tree = shift;
    my $tokenlist = shift;

    my @sorted = ();
    if( ref($tokenlist) and scalar(@{$tokenlist}) > 0 )
    {
        @sorted = sort
        {
            my $p_a = $config_tree->getNodeParam($a, 'precedence', 1);
            $p_a = 0 unless defined $p_a;
            my $p_b = $config_tree->getNodeParam($b, 'precedence', 1);
            $p_b = 0 unless defined $p_b;
            if( $p_a == $p_b )
            {
                my $n_a = $config_tree->path($a);
                my $n_b = $config_tree->path($b);
                return $n_a cmp $n_b;
            }
            else
            {
                return $p_b <=> $p_a;
            }
        } @{$tokenlist};
    }
    else
    {
        push(@sorted, $tokenlist);
    }
    return @sorted;
}


sub makeURL
{
    my $self = shift;
    my $config_tree = shift;
    my $pathref = shift;
    my $token = shift;
    my $view = shift;
    my @add_vars = @_;

    my $ret = $Torrus::Renderer::rendererURL . '/' . $config_tree->treeName();

    if( $pathref )
    {
        my $path = $config_tree->path($token);
        $ret .= '?path=' . uri_escape($path);
    }
    else
    {
        $ret .= '?token=' . uri_escape($token);
    }

    if( $view )
    {
        $ret .= '&amp;view=' . uri_escape($view);
    }

    my %vars = ();
    if( scalar( @add_vars ) )
    {
        # This could be array or a reference to array
        my $rvars;
        if( ref( $add_vars[0] ) )
        {
            %vars = @{$add_vars[0]};
        }
        else
        {
            %vars = @add_vars;
        }
    }

    if( ref( $self->{'options'}->{'variables'} ) )
    {
        foreach my $name ( sort keys %{$self->{'options'}->{'variables'}} )
        {
            my $val = $self->{'options'}->{'variables'}->{$name};
            if( not defined( $vars{$name} ) )
            {
                $vars{$name} = $val;
            }
        }
    }

    foreach my $name ( sort keys %vars )
    {
        if( $vars{$name} ne '' )
        {
            $ret .= '&amp;'.$name.'='.uri_escape( $vars{$name} );
        }
    }

    return $ret;
}

sub makeSplitURLs
{
    my $self = shift;
    my $config_tree = shift;
    my $token = shift;
    my $view = shift;

    my $path = $config_tree->path($token);

    my $ret = '';
    my $currpath = '';
    foreach my $node ($config_tree->splitPath($path))
    {
        $currpath .= $node;
        if( not defined(my $currtoken = $config_tree->token($currpath)) )
        {
            Error("Cannot find token for $currpath");
        }
        else
        {
            $ret .= '<SPAN CLASS="PathElement">';
            $ret .= sprintf('<A HREF="%s">%s</A>',
                            $self->makeURL($config_tree, 0, $currtoken, $view),
                            $node);
            $ret .= "</SPAN>\n";
        }
    }
    return $ret;
}


sub rrPrint
{
    my $self = shift;
    my $config_tree = shift;
    my $token = shift;
    my $view = shift;

    my @ret = ();
    my($fname, $mimetype) =  $self->render($config_tree, $token, $view);

    if( $mimetype ne 'text/plain' )
    {
        Error("View $view does not produce text/plain for token $token");
    }
    else
    {
        if( not open(IN, $fname) )
        {
            Error("Cannot open $fname for reading: $!");
        }
        else
        {
            chomp(my $values = <IN>);
            @ret = split(':', $values);
            close IN;
        }
    }
    return @ret;
}

# This subroutine is taken from Dave Plonka's Flowscan

sub scale
{
    my $self = shift;
    # This is based somewhat on Tobi Oetiker's code in rrd_graph.c:
    my $fmt = shift;
    my $value = shift;
    my @symbols = ("a", # 10e-18 Ato
                   "f", # 10e-15 Femto
                   "p", # 10e-12 Pico
                   "n", # 10e-9  Nano
                   "u", # 10e-6  Micro
                   "m", # 10e-3  Milli
                   " ", # Base
                   "k", # 10e3   Kilo
                   "M", # 10e6   Mega
                   "G", # 10e9   Giga
                   "T", # 10e12  Terra
                   "P", # 10e15  Peta
                   "E"); # 10e18  Exa

    my $symbcenter = 6;
    my $digits = (0 == $value)? 0 : floor(log(abs($value))/log(1000));
    return sprintf( $fmt . " %s", $value/pow(1000, $digits),
                    $symbols[ $symbcenter+$digits ] );
}

sub style
{
    my $self = shift;
    my $object = shift;

    my $media;
    if( not defined( $media = $self->{'options'}->{'variables'}->{'MEDIA'} ) )
    {
        $media = 'default';
    }
    return  $Torrus::Renderer::styling{$media}{$object};
}



sub userAttribute
{
    my $self = shift;
    my $attr = shift;

    if( $self->{'options'}->{'uid'} and $self->{'options'}->{'acl'} )
    {
        $self->{'options'}->{'acl'}->
            userAttribute( $self->{'options'}->{'uid'}, $attr );
    }
    else
    {
        return '';
    }
}

sub hasPrivilege
{
    my $self = shift;
    my $object = shift;
    my $privilege = shift;

    if( $self->{'options'}->{'uid'} and $self->{'options'}->{'acl'} )
    {
        $self->{'options'}->{'acl'}->
            hasPrivilege( $self->{'options'}->{'uid'}, $object, $privilege );
    }
    else
    {
        return undef;
    }
}


sub translateMarkup
{
    my $self = shift;
    my @strings = @_;

    my $tt = new Template( TRIM => 1 );

    my $ttvars =
    {
        'em'      =>  sub { return '<em>' . $_[0] . '</em>'; },
        'strong'  =>  sub { return '<strong>' . $_[0] . '</strong>'; }
    };
    
    my $ret = '';
    
    foreach my $str ( @strings )
    {
        my $output = '';
        my $result = $tt->process( \$str, $ttvars, \$output );

        if( not $result )
        {
            Error('Error translating markup: ' . $tt->error());
        }
        else
        {
            $ret .= $output;
        }
    }

    undef $tt;
    
    return $ret;
}

1;


# Local Variables:
# mode: perl
# indent-tabs-mode: nil
# perl-indent-level: 4
# End: