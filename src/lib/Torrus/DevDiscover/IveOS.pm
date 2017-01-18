#!/usr/bin/perl 

package Torrus::DevDiscover::IveOS;
use strict;
use Torrus::Log;

# This part is needed to register the module with torrus
$Torrus::DevDiscover::registry{'IveOS'} = {
    'sequence'     => 500,
    'checkdevtype' => \&checkdevtype,
    'discover'     => \&discover,
    'buildConfig'  => \&buildConfig
};

# Define symbolic names for the OID's which we want to monitor
our %oiddef =
    (
     'productName'  =>  '1.3.6.1.4.1.12532.6.0',
     'signedInWebUsers' => '1.3.6.1.4.1.12532.2.0',
     'iveConcurrentUsers' => '1.3.6.1.4.1.12532.12.0',
     'clusterConcurrentUsers' => '1.3.6.1.4.1.12532.13.0',
     );
          
#--------------------------------------------------------------------------------
# $exitStatus = checkdevtype();
#--------------------------------------------------------------------------------
# This function establishes wether the device tested, 
# is an "UPS monitoring system". 
# If so, this function returns 1. 
# If not, this function returns 0.
#--------------------------------------------------------------------------------     
sub checkdevtype
{
    # Get arguments from caller
    my $dd = shift;
    my $devdetails = shift;
    
    # Define which value we want to check
    my $check =
        $dd->retrieveSnmpOIDs( 'productName');
    
    # Debug 
    Debug($check->{'productName'}."\n");
    
    if ($check->{'productName'} =~ /SA/) {   
    # Debug
        Debug("Matched");
        # Return 1 (meaning: now the discovery script knows
        # the device is an "UPS monitoring system"
        return 1;
    }
    # Debug
    Debug("Not Matched");
    # Return 0 if not "UPS monitoring system"
    return 0;
}

#--------------------------------------------------------------------------------
# $exitstatus = discover();
#--------------------------------------------------------------------------------
# This function is used to add stuff to $data
#--------------------------------------------------------------------------------   
sub discover
{
    # Use Dumper if you want to dump lists and hashes
    use Data::Dumper;
    # Type: Torrus::DevDiscover
    # Useful methods:
    # retrieveSnmpOIDS: getByName
    # checkSnmpOID: Check if given OID is present
    # 
    
    # Get arguments from caller
    my $dd = shift;    
    # Object: Torrus::DevDetails
    my $devdetails = shift;
     
    # current Net::SNMP->session
    # Refer to Net::SNMP documentation for help
    my $session = $dd->session();
    # Discovery data from devDetails
    my $data = $devdetails->data();
    
    ##
    ## The next bit of code will push values in $data which will be 
    ## used in buildconfig().
    ## @list contains oid symbolic descriptions.
    ## @comments contains comments
    ## @max contains maximal values
    ## @label contains vertical-label
    ##
    ## These variables can be retrieved later from 
    ## $data->{'ups'}{'listname'}
    
    # Define some values which will be used below

    my @list = qw(signedInWebUsers iveConcurrentUsers clusterConcurrentUsers);
    my @dslist = qw(wusers cusers ccusers);
    my @comment = ('Number of Signed-In Web Users','Users Logged In for the IVE Node','Users Logged In for the Cluster');
    my @max = qw (2500 2500 2500);
    my @label = ('Users', 'Users', 'Users');
    
    # Make a branch in $data to put our UPS information into
    $data->{'sslvpn'} = {};
    
    # Cycle through the list to set capabilities
    foreach (@list) {
        # Set capabilities
        $devdetails->setCap($_);
        # Get SNMP variables
        my $result = $session->get_request( $dd->oiddef($_)); 
        # Store them.. Why: I don't know??
        $devdetails->storeSnmpVars ($result);
    }
    
    # Cycle through the list again
    for (my $i = 0; $i < @list; $i++) { 
        # push the information into $data->{'ups'}{'listname'}   
        $data->{'sslvpn'}{'oid'}{$list[$i]} = $dd->oiddef($list[$i]);
        $data->{'sslvpn'}{'dslist'}{$list[$i]} = $dslist[$i];
        $data->{'sslvpn'}{'comment'}{$list[$i]} = $comment[$i];
        $data->{'sslvpn'}{'max'}{$list[$i]} = $max[$i];
        $data->{'sslvpn'}{'label'}{$list[$i]} = $label[$i];
    }
    # Some debugging output
    Debug(Dumper($data));
    return 1;    
}

#--------------------------------------------------------------------------------
# $exitstatus = discover();
#--------------------------------------------------------------------------------
# This function is used to build a piece of the xml configuration
# $data->{'param'} holds the parameters which will be added.
#--------------------------------------------------------------------------------  
sub buildConfig
{
    my $devdetails = shift;
    my $data = $devdetails->data();
    my $cb = shift;
    my $devNode = shift; 
    if( $devdetails->hasCap('signedInWebUsers') )
    {
        # Build User_Usage subtree
        my $subtreeName='IveOS';
        my $param={};
        #reference to the XML templates
        my $templates= ('IveOS.xml::IveOS');
        #name our dynamic rrd files
        $param->{'data-file'}='%snmp-host%_IveOSMonitor.rrd';
        #add the subtree
        my $subtreeNode = $cb->addSubtree( $devNode, $subtreeName, $param, $templates  ); 
        
        #loop through every found interface
        foreach my $key ( keys %{$data->{'sslvpn'}{'oid'}} )
        {       
            my $leafName = $key;
            $leafName =~ s/\s+/_/g;
            
            # values from $param will be put in your generated
            # configuration file like this:
            # <param name="rrd-ds" value=$key>
            # In other words: put variable-specific stuff here.
            # Put "device-type"-specific stuff in the template 
            # which is refered below.   
            my $param = {
                    'rrd-ds' => $data->{'sslvpn'}{'dslist'}{$key},
                    'ds-names' => $data->{'sslvpn'}{'dslist'}{$key},
                    'snmp-object' =>   $data->{'sslvpn'}{'oid'}{$key},                    
                    'graph-title' => $data->{'sslvpn'}{'comment'}{$key},
                    'graph-legend' => $data->{'sslvpn'}{'comment'}{$key},
                    'vertical-label' => $data->{'sslvpn'}{'label'}{$key},
                    'comment' => $data->{'ups'}{'comment'}{$key},
                    'graph-upper-limit' => $data->{'sslvpn'}{'max'}{$key},
                    
            };
            
            my $templates=['IveOS.xml::IveOS'];
            $cb->addLeaf( $subtreeNode, $leafName, $param, $templates );
        }
    }
}


1;


# Local Variables:
# mode: perl
# indent-tabs-mode: nil
# perl-indent-level: 4
# End:
