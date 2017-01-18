#!/usr/bin/perl 

# To enable this module (Torrus::DevDiscover::UPSMonitor),
# add: push(@Torrus::DevDiscover::loadModules, 'Torrus::DevDiscover::UPSMonitor')
# to: /etc/torrus/conf/devdiscover-siteconfig.pl
# It also comes with UPSMonitor.xml (the template)
#
# Debug lines here will be shown if you run torrus devdiscover with --debug 

package Torrus::DevDiscover::UPSMonitor;
use strict;
use Torrus::Log;

# This part is needed to register the module with torrus
$Torrus::DevDiscover::registry{'UPSMonitor'} = {
    'sequence'     => 500,
    'checkdevtype' => \&checkdevtype,
    'discover'     => \&discover,
    'buildConfig'  => \&buildConfig
};

# Define symbolic names for the OID's which we want to monitor
our %oiddef =
    (
     'upsCapacity'	=>	'1.3.6.1.4.1.9678.100.1',
     'upsLoad'      =>  '1.3.6.1.4.1.9678.100.2',
     'upsTemp'      =>  '1.3.6.1.4.1.9678.100.3',
     'upsBattVolt'  => 	'1.3.6.1.4.1.9678.100.4',
     'upsVoltOut'	=> 	'1.3.6.1.4.1.9678.100.5',
     'upsFreqIn'	=>	'1.3.6.1.4.1.9678.100.6',
     'upsVoltIn'	=>	'1.3.6.1.4.1.9678.100.7',
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
        $dd->retrieveSnmpOIDs( 'sysDescr');
    
    # Debug 
    Debug($check->{'sysDescr'}."\n");
    
    # Match $check->{'sysDescr'} against "UPS monitoring system"
    if ($check->{'sysDescr'} eq "UPS monitoring system" ) {   
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
    # Debug
    Debug("Entered Torrus::DevDiscover::UPSMonitor->discover() \n");
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
    my @list = qw(upsCapacity upsBattVolt upsVoltOut upsFreqIn upsVoltIn upsLoad upsTemp);
    my @comment = ('UPS remaining battery-capacitiy','UPS battery voltage','UPS output voltage','UPS input frequency','UPS input voltage','UPS power load','UPS internal temperature');
    my @max = qw (100 28 240 52 240 26 40);
    my @min = qw (80 26 220 48 220 24 30);
    my @label = ('Capacity(%)', 'Voltage (V)', 'Voltage (V)', 'Frequency(Hz)', 'Voltage(V)', 'Load(%)', 'Temperature(deg. C)');
    
    # Make a branch in $data to put our UPS information into
    $data->{'ups'} = {};
    
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
        $data->{'ups'}{'oid'}{$list[$i]} = $dd->oiddef($list[$i]);
        $data->{'ups'}{'comment'}{$list[$i]} = $comment[$i];
        $data->{'ups'}{'max'}{$list[$i]} = $max[$i];
        $data->{'ups'}{'label'}{$list[$i]} = $label[$i];
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
    if( $devdetails->hasCap('upsCapacity') )
    {
        # Build User_Usage subtree
        my $subtreeName='UPS';
        my $param={};
        #reference to the XML templates
        my $templates= ('UPSMonitor.xml::UPS');
        #name our dynamic rrd files
        $param->{'data-file'}='%snmp-host%_UPSMonitor.rrd';
        #add the subtree
        my $subtreeNode = $cb->addSubtree( $devNode, $subtreeName, $param, $templates  ); 
        
        # precedence: sort entries in descending order of precedence
        my %prec = {};
        # On top
        $prec{'upsCapacity'} = 8;
        # Second place
        $prec{'upsLoad'} = 7 ;
        # Third  
        $prec{'upsTemp'} = 6 ;   
        
        #loop through every found interface
        foreach my $key ( keys %{$data->{'ups'}{'oid'}} )
        {       
            my $leafName = $key;
            $leafName =~ s/\s+/_/g;
            
            # Precedence doesn't matter for other variables
            # So if precedence is already set it must not be 
            # overriden.
            my $leafPrec=0;
            if(defined $prec{$key}) {
                $leafPrec = $prec{$key};
            }
           
            # values from $param will be put in your generated
            # configuration file like this:
            # <param name="rrd-ds" value=$key>
            # In other words: put variable-specific stuff here.
            # Put "device-type"-specific stuff in the template 
            # which is refered below.   
            my $param = {
                    'rrd-ds' => $key,
                    'ds-names' => $key,
                    'snmp-object' =>   $data->{'ups'}{'oid'}{$key},                    
                    'graph-title' => $data->{'ups'}{'comment'}{$key},
                    'graph-legend' => $data->{'ups'}{'comment'}{$key},
                    'vertical-label' => $data->{'ups'}{'label'}{$key},
                    'comment' => $data->{'ups'}{'comment'}{$key},
                    'precedence' => $leafPrec,
                    'graph-upper-limit' => $data->{'ups'}{'max'}{$key},
                    'graph-lower-limit' => $data->{'ups'}{'min'}{$key}
                    
            };
            
            # Template is referred in /etc/torrus/conf/devdiscover-siteconfig.pl
            # like this:
            # $Torrus::ConfigBuilder::templateRegistry{'UPSMonitor.xml::UPS'} =
            # {
            #                 'name'   => 'UPS',
            #                 'source' => 'vendor/UPSMonitor.xml'
            # };
            #
            my $templates=['UPSMonitor.xml::UPS'];
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
