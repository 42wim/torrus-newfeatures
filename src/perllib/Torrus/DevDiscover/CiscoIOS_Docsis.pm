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
#  Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA 02111-1307, USA.

# $Id$
# Stanislav Sinyagin <ssinyagin@yahoo.com>

# DOCSIS interface, Cisco specific

package Torrus::DevDiscover::CiscoIOS_Docsis;

use strict;
use Torrus::Log;

# Sequence number is 600 - we depend on RFC2670_DOCS_IF and CiscoIOS

$Torrus::DevDiscover::registry{'CiscoIOS_Docsis'} = {
    'sequence'     => 600,
    'checkdevtype' => \&checkdevtype,
    'discover'     => \&discover,
    'buildConfig'  => \&buildConfig
    };


our %oiddef =
    (
     # CISCO-DOCS-EXT-MIB:cdxIfUpstreamChannelExtTable
     'cdxIfUpChannelNumActiveUGS' => '1.3.6.1.4.1.9.9.116.1.4.1.1.10'
     );


sub checkdevtype
{
    my $dd = shift;
    my $devdetails = shift;

    if( $devdetails->isDevType('CiscoIOS') and
        $devdetails->isDevType('RFC2670_DOCS_IF') )
    {
        return 1;
    }

    return 0;
}


sub discover
{
    my $dd = shift;
    my $devdetails = shift;

    if( $dd->checkSnmpTable( 'cdxIfUpChannelNumActiveUGS' ) )
    {
        $devdetails->setCap('cdxIfUpChannelNumActiveUGS');
    }

    return 1;
}


sub buildConfig
{
    my $devdetails = shift;
    my $cb = shift;
    my $devNode = shift;

    my $data = $devdetails->data();

    # Build Docsis_Utilization subtree

    my $utilNode =
        $cb->addSubtree( $devNode, 'Docsis_Utilization',
                         {'precedence' => '-450',
                          'comment' => 'DOCSIS resources utilization'},
                         [] );

    my $macNode =
        $cb->addSubtree( $utilNode, 'MAC_Layer', {},
                         ['CiscoIOS_Docsis::cisco-docsis-util-mac-subtree'] );

    my @macLayerInterfaces = ();
    
    foreach my $ifIndex ( @{$data->{'docsCableMaclayer'}} )
    {
        my $interface = $data->{'interfaces'}{$ifIndex};
        
        my $param = {
            'interface-name' => $interface->{'param'}{'interface-name'},
            'interface-nick' => $interface->{'param'}{'interface-nick'},
            'comment'        => $interface->{'param'}{'comment'}
        };

        my $ifSubtreeName = $interface->{$data->{'nameref'}{'ifSubtreeName'}};
        $cb->addSubtree
            ( $macNode, $ifSubtreeName,
              $param, ['CiscoIOS_Docsis::cisco-docsis-util-mac-intf'] );

        push( @macLayerInterfaces, $ifSubtreeName );
    }

    my $upsNode =
        $cb->addSubtree( $utilNode, 'Upstream_Channels', {},
                         ['CiscoIOS_Docsis::cisco-docsis-util-up-subtree'] );

    if( $devdetails->hasCap('cdxIfUpChannelNumActiveUGS') )
    {
        $cb->setVar( $upsNode, 'CiscoIOS_Docsis::ugs-supported', 'true' );
    }
    
    foreach my $ifIndex ( @{$data->{'docsCableUpstream'}} )
    {
        my $interface = $data->{'interfaces'}{$ifIndex};
        
        my $param = {
            'interface-name' => $interface->{'param'}{'interface-name'},
            'interface-nick' => $interface->{'param'}{'interface-nick'},
            'comment'        => $interface->{'param'}{'comment'}
        };

        $cb->addSubtree
            ( $upsNode, $interface->{$data->{'nameref'}{'ifSubtreeName'}},
              $param, ['CiscoIOS_Docsis::cisco-docsis-util-up-intf'] );
    }

    # Build All_Modems summary graph
    my $param = {
      'ds-type'              => 'rrd-multigraph',
      'ds-names'             => 'total,active',
      'graph-lower-limit'    => '0',
      'precedence'           => '-1000',
      'comment'              => 'Active and Total modems on all interfaces',
      'vertical-label'       => 'Modems',

      'graph-legend-total'   => 'Total',
      'line-style-total'     => '##totalresource',
      'line-color-total'     => '##totalresource',
      'line-order-total'     => '1',

      'graph-legend-active'  => 'Active',
      'line-style-active'    => '##resourceusage',
      'line-color-active'    => '##resourceusage',
      'line-order-active'    => '2'
      };

    my $first = 1;
    foreach my $intf ( @macLayerInterfaces )
    {
        if( $first )
        {
            $param->{'ds-expr-total'} =
                '{MAC_Layer/' . $intf . '/Modems_Total}';
            $param->{'ds-expr-active'} =
                '{MAC_Layer/' . $intf . '/Modems_Active}';
            $first = 0;
        }
        else
        {
            $param->{'ds-expr-total'} .=
                ',{MAC_Layer/' . $intf . '/Modems_Total},+';
            $param->{'ds-expr-active'} .=
                ',{MAC_Layer/' . $intf . '/Modems_Active},+';
        }
    }

    $cb->addLeaf( $utilNode, 'All_Modems', $param, [] );
}


1;


# Local Variables:
# mode: perl
# indent-tabs-mode: nil
# perl-indent-level: 4
# End: