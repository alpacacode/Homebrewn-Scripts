#!/usr/bin/env perl
##########
# Script for analyzing Check Point firewall logs for statistics about firewall rule usage.
#
# First export logs via fwm logexport:
# fwm logexport -n -p -i $FWDIR/log/2013-07-28_000000.log -o /tmp/2013-07-28.txt
# Feed these exported textfiles as arguments to this script:
# ./cp-fwlog-rule-usage.pl /tmp/2013-07-28.txt /tmp/2013-07-27.txt
#
# Github: https://github.com/alpacacode/Homebrewn-Scripts
# Reference: http://alpacapowered.wordpress.com/2013/07/30/script-perl-check-point-firewall-logfile-analysis-rule-usage/
########

use strict;
use warnings;

my (%rulenames, %indexes);
my @want = ("rule_name", "rule", "message_info", "TCP packet out of state", "type");

foreach my $file (@ARGV) {
  open my $fh, '<', $file or die "Can't open file $!";
  my @fileheader = split (";", <$fh>);
  foreach my $cur (@want) {
        $indexes{$cur} = 0;
        ++$indexes{$cur} until $fileheader[$indexes{$cur}] eq $cur;
  }   
  <$fh>; #filter "Log file has been switched to..." message

  while(<$fh>) {
    my @vals = split (";", $_);
    if($vals[$indexes{"type"}] ne "control") {
      ++$rulenames{"$vals[$indexes{\"rule\"}] - $vals[$indexes{\"rule_name\"}]"} if $vals[$indexes{"rule_name"}];
      ++$rulenames{"**TCP packet out of state**"} if $vals[$indexes{"TCP packet out of state"}];
      ++$rulenames{"**[No Rule Name]**"} unless ($vals[$indexes{"rule_name"}] || $vals[$indexes{"message_info"}] || $vals[$indexes{"TCP packet out of state"}]);
      ++$rulenames{"**$vals[$indexes{\"message_info\"}]**"} if $vals[$indexes{"message_info"}];
    }
  }
  close $fh;
}

printf ("\n\n%-40s\t%-10s\n", "Rule Name", "Hits");
foreach (sort { $rulenames{$b} <=> $rulenames{$a} }  keys %rulenames) {
  printf ("%-40s\t%-10d\n", $_, $rulenames{$_});
}

Exa