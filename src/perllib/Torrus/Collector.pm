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


package Torrus::Collector;
@Torrus::Collector::ISA = qw(Torrus::Scheduler::PeriodicTask);

use strict;
use Torrus::ConfigTree;
use Torrus::Log;
use Torrus::RPN;
use Torrus::Scheduler;

BEGIN
{
    foreach my $mod ( @Torrus::Collector::loadModules )
    {
        eval( 'require ' . $mod );
        die( $@ ) if $@;
    }
}


## One collector module instance holds all leaf tokens which
## must be collected at the same time.

sub new
{
    my $proto = shift;
    my %options = @_;

    if( not $options{'-Name'} )
    {
        $options{'-Name'} = "Collector";
    }

    my $class = ref($proto) || $proto;
    my $self  = $class->SUPER::new( %options );
    bless $self, $class;

    foreach my $collector_type ( keys %Torrus::Collector::collectorTypes )
    {
        $self->{'types'}{$collector_type} = {};
    }

    foreach my $storage_type ( keys %Torrus::Collector::storageTypes )
    {
        $self->{'storage'}{$storage_type} = {};
    }

    $self->{'tree_name'} = $options{'-TreeName'};
    
    return $self;
}


sub addTarget
{
    my $self = shift;
    my $config_tree = shift;
    my $token = shift;

    my $ok = 1;
    $self->{'targets'}{$token}{'path'} = $config_tree->path($token);

    my $collector_type = $config_tree->getNodeParam($token, 'collector-type');
    if( not $Torrus::Collector::collectorTypes{$collector_type} )
    {
        Error('Unknown collector type: ' . $collector_type);
        return;
    }

    $self->fetchParams($config_tree, $token, $collector_type);

    $self->{'targets'}{$token}{'type'} = $collector_type;

    my $storage_type = $config_tree->getNodeParam($token, 'storage-type');
    if( not $Torrus::Collector::storageTypes{$storage_type} )
    {
        Error('Unknown storage type: ' . $storage_type);
        return;
    }

    my $storage_string = $storage_type.'-storage';
    $self->{'targets'}{$token}{'storage-type'} = $storage_type;

    # If specified, store the value transformation code
    my $code = $config_tree->getNodeParam($token, 'transform-value');
    if( defined $code )
    {
        $self->{'targets'}{$token}{'transform'} = $code;
    }

    # If specified, store the scale RPN
    my $scalerpn = $config_tree->getNodeParam($token, 'collector-scale');
    if( defined $scalerpn )
    {
        $self->{'targets'}{$token}{'scalerpn'} = $scalerpn;
    }

    # If specified, store the value map
    my $valueMap = $config_tree->getNodeParam($token, 'value-map');
    if( defined $valueMap and length($valueMap) > 0 )
    {
        my $map = {};
        foreach my $item ( split( ',', $valueMap ) )
        {
            my ($key, $value) = split( ':', $item );
            $map->{$key} = $value;
        }
        $self->{'targets'}{$token}{'value-map'} = $map;
    }

    # Initialize local token, collectpor, and storage data
    if( not defined $self->{'targets'}{$token}{'local'} )
    {
        $self->{'targets'}{$token}{'local'} = {};
    }

    $self->fetchParams($config_tree, $token, $storage_string);

    if( ref( $Torrus::Collector::initTarget{$collector_type} ) )
    {
        $ok = &{$Torrus::Collector::initTarget{$collector_type}}($self, $token);
    }

    if( $ok and ref( $Torrus::Collector::initTarget{$storage_string} ) )
    {
        &{$Torrus::Collector::initTarget{$storage_string}}($self, $token);
    }
}


sub fetchParams
{
    my $self = shift;
    my $config_tree = shift;
    my $token = shift;
    my $type = shift;

    if( not defined( $Torrus::Collector::params{$type} ) )
    {
        Error("\%Torrus::Collector::params does not have member $type");
        return;
    }

    my $ref = \$self->{'targets'}{$token}{'params'};

    my @maps = ( $Torrus::Collector::params{$type} );

    while( scalar( @maps ) > 0 )
    {
        my @next_maps = ();
        foreach my $map ( @maps )
        {
            foreach my $param ( keys %{$map} )
            {
                my $value = $config_tree->getNodeParam( $token, $param );

                if( ref( $map->{$param} ) )
                {
                    if( defined $value )
                    {
                        if( exists $map->{$param}->{$value} )
                        {
                            if( defined $map->{$param}->{$value} )
                            {
                                push( @next_maps,
                                      $map->{$param}->{$value} );
                            }
                        }
                        else
                        {
                            Error("Parameter $param has unknown value: " .
                                  $value . " in " .
                                  $self->{'targets'}{$token}{'path'});
                        }
                    }
                }
                else
                {
                    if( not defined $value )
                    {
                        # We know the default value
                        $value = $map->{$param};
                    }
                }
                # Finally store the value
                if( defined $value )
                {
                    $$ref->{$param} = $value;
                }
            }
        }
        @maps = @next_maps;
    }
}


sub fetchMoreParams
{
    my $self = shift;
    my $config_tree = shift;
    my $token = shift;
    my @params = @_;

    my $ref = \$self->{'targets'}{$token}{'params'};

    foreach my $param ( @params )
    {
        my $value = $config_tree->getNodeParam( $token, $param );
        if( defined $value )
        {
            $$ref->{$param} = $value;
        }
    }
}


sub param
{
    my $self = shift;
    my $token = shift;
    my $param = shift;

    return $self->{'targets'}{$token}{'params'}{$param};
}

sub setParam
{
    my $self = shift;
    my $token = shift;
    my $param = shift;
    my $value = shift;

    $self->{'targets'}{$token}{'params'}{$param} = $value;
}


sub path
{
    my $self = shift;
    my $token = shift;
    my $param = shift;

    return $self->{'targets'}{$token}{'path'};
}

sub listCollectorTargets
{
    my $self = shift;
    my $collector_type = shift;

    my @ret;
    foreach my $token ( keys %{$self->{'targets'}} )
    {
        if( $self->{'targets'}{$token}{'type'} eq $collector_type )
        {
            push( @ret, $token );
        }
    }
    return @ret;
}

# A callback procedure that will be executed on deleteTarget()

sub registerDeleteCallback
{
    my $self = shift;
    my $token = shift;
    my $proc = shift;

    if( not ref( $self->{'targets'}{$token}{'deleteProc'} ) )
    {
        $self->{'targets'}{$token}{'deleteProc'} = [];
    }
    push( @{$self->{'targets'}{$token}{'deleteProc'}}, $proc );
}

sub deleteTarget
{
    my $self = shift;
    my $token = shift;

    if( ref( $self->{'targets'}{$token}{'deleteProc'} ) )
    {
        foreach my $proc ( @{$self->{'targets'}{$token}{'deleteProc'}} )
        {
            &{$proc}( $self, $token );
        }
    }
    delete $self->{'targets'}{$token};
}

# Returns a reference to token-specific local data

sub tokenData
{
    my $self = shift;
    my $token = shift;

    return $self->{'targets'}{$token}{'local'};
}

# Returns a reference to collector type-specific local data

sub collectorData
{
    my $self = shift;
    my $type = shift;

    return $self->{'types'}{$type};
}

# Returns a reference to storage type-specific local data

sub storageData
{
    my $self = shift;
    my $type = shift;

    return $self->{'storage'}{$type};
}


# Runs each collector type, and then stores the values
sub run
{
    my $self = shift;

    undef $self->{'values'};

    while( my ($collector_type, $ref) = each %{$self->{'types'}} )
    {
        if( $Torrus::Collector::needsConfigTree
            {$collector_type}{'runCollector'} )
        {
            $self->{'config_tree'} =
                new Torrus::ConfigTree( -TreeName => $self->{'tree_name'},
                                      -Wait => 1 );
        }
        
        &{$Torrus::Collector::runCollector{$collector_type}}( $self, $ref );

        if( defined( $self->{'config_tree'} ) )
        {
            undef $self->{'config_tree'};
        }
    }

    while( my ($storage_type, $ref) = each %{$self->{'storage'}} )
    {
        if( $Torrus::Collector::needsConfigTree
            {$storage_type}{'storeData'} )
        {
            $self->{'config_tree'} =
                new Torrus::ConfigTree( -TreeName => $self->{'tree_name'},
                                      -Wait => 1 );
        }

        &{$Torrus::Collector::storeData{$storage_type}}( $self, $ref );

        if( defined( $self->{'config_tree'} ) )
        {
            undef $self->{'config_tree'};
        }        
    }
    
    while( my ($collector_type, $ref) = each %{$self->{'types'}} )
    {
        if( ref( $Torrus::Collector::postProcess{$collector_type} ) )
        {
            if( $Torrus::Collector::needsConfigTree
                {$collector_type}{'postProcess'} )
            {
                $self->{'config_tree'} =
                    new Torrus::ConfigTree( -TreeName => $self->{'tree_name'},
                                          -Wait => 1 );
            }
            
            &{$Torrus::Collector::postProcess{$collector_type}}( $self, $ref );

            if( defined( $self->{'config_tree'} ) )
            {
                undef $self->{'config_tree'};
            }
        }
    }
}


# This procedure is called by the collector type-specific functions
# every time there's a new value for a token
sub setValue
{
    my $self = shift;
    my $token = shift;
    my $value = shift;
    my $timestamp = shift;
    my $uptime = shift;

    if( $value ne 'U' )
    {
        if( defined( my $code = $self->{'targets'}{$token}{'transform'} ) )
        {            
            # Screen out the percent sign and $_
            $code =~ s/DOLLAR/\$/gm;
            $code =~ s/MOD/\%/gm;
            Debug('Value before transformation: ' . $value);
            $_ = $value;
            $value = do { eval $code };
            if( $@ )
            {
                Error('Fatal error in transformation code: ' . $@ );
                $value = 'U';
            }
            elsif( $value !~ /^[0-9.+-eE]+$/ and $value ne 'U' )
            {
                Error('Non-numeric value after transformation: ' . $value);
                $value = 'U';
            }
        }
        elsif( defined( my $map = $self->{'targets'}{$token}{'value-map'} ) )
        {
            my $newValue;
            if( defined( $map->{$value} ) )
            {
                $newValue = $map->{$value};
            }
            elsif( defined( $map->{'_'} ) )
            {
                $newValue = $map->{'_'};
            }
            else
            {
                Warn('Could not find value mapping for ' . $value .
                     'in ' . $self->{'targets'}{$token}{'path'});
            }

            if( defined( $newValue ) )
            {
                Debug('Value mapping: ' . $value . ' -> ' . $newValue);
                $value = $newValue;
            }
        }

        if( defined( $self->{'targets'}{$token}{'scalerpn'} ) )
        {
            Debug('Value before scaling: ' . $value);
            my $rpn = new Torrus::RPN;
            $value = $rpn->run( $value . ',' .
                                $self->{'targets'}{$token}{'scalerpn'},
                                sub{} );
        }
    }

    Debug('Value ' . $value . ' set for ' .
          $self->{'targets'}{$token}{'path'} . ' TS=' . $timestamp);

    my $proc =
        $Torrus::Collector::setValue{$self->{'targets'}{$token}{'storage-type'}};
    &{$proc}( $self, $token, $value, $timestamp, $uptime );
}


sub configTree
{
    my $self = shift;

    if( defined( $self->{'config_tree'} ) )
    {
        return $self->{'config_tree'};
    }
    else
    {
        Error('Cannot provide ConfigTree object');
        return undef;
    }
}


#######  Collector scheduler  ########

package Torrus::CollectorScheduler;
@Torrus::CollectorScheduler::ISA = qw(Torrus::Scheduler);

use Torrus::ConfigTree;
use Torrus::Log;
use Torrus::Scheduler;
use Torrus::TimeStamp;


sub beforeRun
{
    my $self = shift;

    my $tree = $self->treeName();
    my $config_tree = new Torrus::ConfigTree(-TreeName => $tree, -Wait => 1);
    if( not defined( $config_tree ) )
    {
        return undef;
    }

    my $data = $self->data();

    # Prepare the list of tokens, sorted by period and offset,
    # from config tree or from cache.

    my $need_new_tasks = 0;

    Torrus::TimeStamp::init();
    my $known_ts = Torrus::TimeStamp::get($tree . ':collector_cache');
    my $actual_ts = $config_tree->getTimestamp();
    if( $actual_ts >= $known_ts )
    {
        Info("Rebuilding collector information");
        Debug("Config TS: $actual_ts, Collector TS: $known_ts");

        undef $data->{'targets'};
        $need_new_tasks = 1;

        $data->{'db_tokens'} = new Torrus::DB( 'collector_tokens',
                                             -Subdir => $tree,
                                             -WriteAccess => 1,
                                             -Truncate    => 1 );
        $self->cacheCollectors( $config_tree, $config_tree->token('/') );
        # explicitly close, since we don't need it often, and sometimes
        # open it in read-only mode
        $data->{'db_tokens'}->closeNow();
        undef $data->{'db_tokens'};

        # Set the timestamp
        &Torrus::TimeStamp::setNow($tree . ':collector_cache');
    }
    Torrus::TimeStamp::release();

    if( not $need_new_tasks and not defined $data->{'targets'} )
    {
        $need_new_tasks = 1;

        $data->{'db_tokens'} = new Torrus::DB('collector_tokens',
                                            -Subdir => $tree);
        my $cursor = $data->{'db_tokens'}->cursor();
        while( my ($token, $schedule) = $data->{'db_tokens'}->next($cursor) )
        {
            my ($period, $offset) = split(':', $schedule);
            if( not exists( $data->{'targets'}{$period}{$offset} ) )
            {
                $data->{'targets'}{$period}{$offset} = [];
            }
            push( @{$data->{'targets'}{$period}{$offset}}, $token );
        }
        undef $cursor;
        $data->{'db_tokens'}->closeNow();
        undef $data->{'db_tokens'};
    }

    # Now fill in Scheduler's task list, if needed

    if( $need_new_tasks )
    {
        Verbose("Initializing tasks");
        my $init_start = time();
        $self->flushTasks();

        foreach my $period ( keys %{$data->{'targets'}} )
        {
            foreach my $offset ( keys %{$data->{'targets'}{$period}} )
            {
                my $collector =
                    new Torrus::Collector( -Period => $period,
                                         -Offset => $offset,
                                         -TreeName => $tree );

                foreach my $token ( @{$data->{'targets'}{$period}{$offset}} )
                {
                    $collector->addTarget( $config_tree, $token );
                }

                $self->addTask( $collector );
            }
        }
        Verbose(sprintf("Tasks initialization finished in %d seconds",
                        time() - $init_start));
    }

    Verbose("Collector initialized");

    return 1;
}


sub cacheCollectors
{
    my $self = shift;
    my $config_tree = shift;
    my $ptoken = shift;

    my $data = $self->data();

    foreach my $ctoken ( $config_tree->getChildren( $ptoken ) )
    {
        if( $config_tree->isSubtree( $ctoken ) )
        {
            $self->cacheCollectors( $config_tree, $ctoken );
        }
        elsif( $config_tree->isLeaf( $ctoken ) and
               $config_tree->getNodeParam( $ctoken, 'ds-type' )
               eq 'collector' )
        {
            my $period = sprintf('%d',
                                 $config_tree->getNodeParam
                                 ( $ctoken, 'collector-period' ) );
            my $offset = sprintf('%d',
                                 $config_tree->getNodeParam
                                 ( $ctoken, 'collector-timeoffset' ) );

            $data->{'db_tokens'}->put( $ctoken, $period.':'.$offset );
            push( @{$data->{'targets'}{$period}{$offset}}, $ctoken );
        }
    }
}


1;


# Local Variables:
# mode: perl
# indent-tabs-mode: nil
# perl-indent-level: 4
# End: