#!/usr/bin/env perl
##########
# Script for analyzing Check Point firewall logs for number dropped connection by source-IP.
#
# First export logs via fwm logexport:
# fwm logexport -n -p -i $FWDIR/log/2013-07-28_000000.log -o /tmp/2013-07-28.txt
# Feed these exported textfiles as arguments to this script:
# ./cp-fwlog-dropped-connections.pl /tmp/2013-07-28.txt /tmp/2013-07-27.txt
#
# Github: https://github.com/alpacacode/Homebrewn-Scripts
# Reference: http://alpacapowered.wordpress.com/2013/07/30/script-check-point-firewall-logfile-analysis-dropped-connections-statistics/
########

use strict;
use warnings;

my (%sourceaccept, %sourcedrop, %indexes);

#Define the names of the log fields that are relevant for us. In our case we just need src and action.
#Each log entry is basically a semicolon-separated list of the following properties:
#num;date;time;orig;type;action;alert;i/f_name;i/f_dir;product;log_sys_message;origin_id;ProductFamily;Log delay;rule;rule_uid;rule_name;src;dst;proto;service;s_port;service_id;message_info;ICMP;ICMP Type;ICMP Code;TCP packet out of state;tcp_flags;inzone;outzone;rule_guid;hit;policy;first_hit_time;last_hit_time;log_id;xlatesrc;xlatedst;NAT_rulenum;NAT_addtnl_rulenum;xlatedport;xlatesport;description;status;version;comment;update_service;reason;Severity;failure_impact;message;ip_id;ip_len;ip_offset;fragments_dropped;during_sec;Internal_CA:;serial_num:;dn:;sys_message:;SmartDefense profile;DCE-RPC Interface UUID;System Alert message;Object;Event;Parameter;Condition;Current value
my @LogFields = ("src", "action"); 

foreach my $file (@ARGV) {
  open my $fh, '<', $file or die "Can't open file $!";
  my @Fileheader = split (";", <$fh>);
  #Here we just loop through the log header fields (see above) until we know at which position our desired LogFields are
  foreach my $Field (@LogFields) {
        $indexes{$Field} = 0;
        ++$indexes{$Field} until $Fileheader[$indexes{$Field}] eq $Field;
  }
  <$fh>; #filters irrelevant "Log file has been switched to..." message

  #Loop through the rest of the log with the actual log entries and increment the drop/accept counters for each IP
  while(<$fh>) {
    my @Values = split (";", $_);
    if($Values[$indexes{"action"}] eq "drop") {
      ++$sourcedrop{$Values[$indexes{"src"}]};
    }
    elsif($Values[$indexes{"action"}] eq "accept") {
      ++$sourceaccept{$Values[$indexes{"src"}]}
    }
  }
  close $fh;
}

printf ("\n\n%-20s\t%-20s\t%-20s\n", "source-IP", "Dropped Connections", "Accepted Connections");
foreach (sort { $sourcedrop{$b} <=> $sourcedrop{$a} }  keys %sourcedrop) {
  $sourceaccept{$_} = 0 unless $sourceaccept{$_}; #Account for possible undef values for 0 accepted connections
  printf ("%-20s\t%-20d\t%-20d\n", $_, $sourcedrop{$_}, $sourceaccept{$_});
}