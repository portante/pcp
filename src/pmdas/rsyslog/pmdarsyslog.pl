#
# Copyright (c) 2012-2013 Red Hat.
# Copyright (c) 2011 Aconex.  All Rights Reserved.
#
# This program is free software; you can redistribute it and/or modify it
# under the terms of the GNU General Public License as published by the
# Free Software Foundation; either version 2 of the License, or (at your
# option) any later version.
#
# This program is distributed in the hope that it will be useful, but
# WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY
# or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License
# for more details.
#

use strict;
use warnings;
use PCP::PMDA;

my $pmda = PCP::PMDA->new('rsyslog', 107);
my $statsfile = pmda_config('PCP_LOG_DIR') . '/rsyslog/stats';
my ($es_connfail, $es_submits, $es_failed, $es_success) = (0,0,0,0);
my ($ux_submitted, $ux_discarded, $ux_ratelimiters) = (0,0,0);
my ($interval, $lasttime) = (0,0);

my $queue_indom = 0;
my @queue_insts = ();
use vars qw(%queue_ids %queue_values);

# Legacy method
#   .* rsyslogd-pstats:
#   imuxsock: submitted=37 ratelimit.discarded=0 ratelimit.numratelimiters=22
#   elasticsearch: connfail=0 submits=0 failed=0 success=0
#   [main Q]: size=1 enqueued=1436 full=0 maxqsize=3

# Modern method
#   module(load="imuxsock")
#   input(type="imuxsock"
#       Socket="/dev/log"
#       CreatePath="on"
#   )
#   module(load="impstats" interval="10" severity="7")
#   if $syslogtag contains 'rsyslogd-pstats' then {
#       action(
#           name="pstats-for-pcp"
#           type="omfile"
#           template="RSYSLOG_FileFormat"
#           file="/var/log/pcp/rsyslog/stats"
#       )
#       stop
#   }
#rsyslogd-pstats: global: origin=dynstats
#rsyslogd-pstats: imuxsock: origin=imuxsock submitted=1 ratelimit.discarded=0 ratelimit.numratelimiters=0
#rsyslogd-pstats: omelasticsearch: origin=omelasticsearch submitted=106 failed.http=0 failed.httprequests=0 failed.checkConn=0 failed.es=12 response.success=0 response.bad=0 response.duplicate=0 response.badargument=0 response.bulkrejection=0 response.other=0
#rsyslogd-pstats: logging-load-driver-out: origin=core.action processed=0 failed=0 suspended=0 suspended.duration=0 resumed=0
#rsyslogd-pstats: dockerd.log.gz: origin=core.action processed=0 failed=0 suspended=0 suspended.duration=0 resumed=0
#rsyslogd-pstats: pstats: origin=core.action processed=137865 failed=0 suspended=0 suspended.duration=0 resumed=0
#rsyslogd-pstats: fwd-perf34: origin=core.action processed=6467 failed=0 suspended=0 suspended.duration=0 resumed=0
#rsyslogd-pstats: secure: origin=core.action processed=100 failed=0 suspended=0 suspended.duration=0 resumed=0
#rsyslogd-pstats: maillog: origin=core.action processed=9 failed=0 suspended=0 suspended.duration=0 resumed=0
#rsyslogd-pstats: cron: origin=core.action processed=541 failed=0 suspended=0 suspended.duration=0 resumed=0
#rsyslogd-pstats: spooler: origin=core.action processed=0 failed=0 suspended=0 suspended.duration=0 resumed=0
#rsyslogd-pstats: boot: origin=core.action processed=0 failed=0 suspended=0 suspended.duration=0 resumed=0
#rsyslogd-pstats: messages: origin=core.action processed=5817 failed=0 suspended=0 suspended.duration=0 resumed=0
#rsyslogd-pstats: resource-usage: origin=impstats utime=3371587 stime=3943166 maxrss=13164 minflt=3401 majflt=0 inblock=0 oublock=134184 nvcsw=138392 nivcsw=4
#rsyslogd-pstats: fwd-perf34 queue[DA]: origin=core.queue size=0 enqueued=0 full=0 discarded.full=0 discarded.nf=0 maxqsize=0
#rsyslogd-pstats: fwd-perf34 queue: origin=core.queue size=0 enqueued=6467 full=0 discarded.full=0 discarded.nf=0 maxqsize=6
#rsyslogd-pstats: main Q: origin=core.queue size=14 enqueued=144346 full=0 discarded.full=0 discarded.nf=0 maxqsize=15

# For JSON format, use the following in your rsyslog.conf:
#   module(load="impstats" format="cee" interval="10" severity="7")
#   if $syslogtag contains 'rsyslogd-pstats' then {
#       action(
#           name="pstats-for-pcp"
#           type="omfile"
#           # NOTE: template parameter not required
#           file="/var/log/pcp/rsyslog/stats"
#       )
#       stop
#   }
#rsyslogd-pstats: @cee: { "name": "global", "origin": "dynstats", "values": { } }
#rsyslogd-pstats: @cee: { "name": "omelasticsearch", "origin": "omelasticsearch", "submitted": 1658343219, "failed.http": 0, "failed.httprequests": 0, "failed.checkConn": 3, "failed.es": 9, "response.success": 0, "response.bad": 0, "response.duplicate": 0, "response.badargument": 0, "response.bulkrejection": 0, "response.other": 0 }
#rsyslogd-pstats: @cee: { "name": "pstats", "origin": "core.action", "processed": 18064652, "failed": 0, "suspended": 0, "suspended.duration": 0, "resumed": 0 }
#rsyslogd-pstats: @cee: { "name": "action 1", "origin": "core.action", "processed": 1658345033, "failed": 0, "suspended": 0, "suspended.duration": 0, "resumed": 0 }
#rsyslogd-pstats: @cee: { "name": "action 2", "origin": "core.action", "processed": 1658345033, "failed": 0, "suspended": 0, "suspended.duration": 0, "resumed": 0 }
#rsyslogd-pstats: @cee: { "name": "action 3", "origin": "core.action", "processed": 1658345033, "failed": 0, "suspended": 0, "suspended.duration": 0, "resumed": 0 }
#rsyslogd-pstats: @cee: { "name": "send-es-prod", "origin": "core.action", "processed": 1658345033, "failed": 0, "suspended": 0, "suspended.duration": 0, "resumed": 0 }
#rsyslogd-pstats: @cee: { "name": "action 5", "origin": "core.action", "processed": 0, "failed": 0, "suspended": 0, "suspended.duration": 0, "resumed": 0 }
#rsyslogd-pstats: @cee: { "name": "action 6", "origin": "core.action", "processed": 0, "failed": 0, "suspended": 0, "suspended.duration": 0, "resumed": 0 }
#rsyslogd-pstats: @cee: { "name": "action 7", "origin": "core.action", "processed": 65346, "failed": 0, "suspended": 0, "suspended.duration": 0, "resumed": 0 }
#rsyslogd-pstats: @cee: { "name": "action 8", "origin": "core.action", "processed": 318, "failed": 0, "suspended": 0, "suspended.duration": 0, "resumed": 0 }
#rsyslogd-pstats: @cee: { "name": "action 9", "origin": "core.action", "processed": 2339355, "failed": 0, "suspended": 0, "suspended.duration": 0, "resumed": 0 }
#rsyslogd-pstats: @cee: { "name": "action 10", "origin": "core.action", "processed": 25286, "failed": 0, "suspended": 0, "suspended.duration": 0, "resumed": 0 }
#rsyslogd-pstats: @cee: { "name": "action 11", "origin": "core.action", "processed": 3879, "failed": 0, "suspended": 0, "suspended.duration": 0, "resumed": 0 }
#rsyslogd-pstats: @cee: { "name": "action 12", "origin": "core.action", "processed": 1170077, "failed": 0, "suspended": 0, "suspended.duration": 0, "resumed": 0 }
#rsyslogd-pstats: @cee: { "name": "action 13", "origin": "core.action", "processed": 0, "failed": 0, "suspended": 0, "suspended.duration": 0, "resumed": 0 }
#rsyslogd-pstats: @cee: { "name": "action 14", "origin": "core.action", "processed": 0, "failed": 0, "suspended": 0, "suspended.duration": 0, "resumed": 0 }
#rsyslogd-pstats: @cee: { "name": "action 15", "origin": "core.action", "processed": 0, "failed": 0, "suspended": 0, "suspended.duration": 0, "resumed": 0 }
#rsyslogd-pstats: @cee: { "name": "imudp(*:514)", "origin": "imudp", "submitted": 0 }
#rsyslogd-pstats: @cee: { "name": "imudp(*:514)", "origin": "imudp", "submitted": 0 }
#rsyslogd-pstats: @cee: { "name": "imptcp(*\/514\/IPv4)", "origin": "imptcp", "submitted": 1652644001, "bytes.received": 2154282781586, "bytes.decompressed": 0 }
#rsyslogd-pstats: @cee: { "name": "imptcp(*\/514\/IPv6)", "origin": "imptcp", "submitted": 0, "bytes.received": 0, "bytes.decompressed": 0 }
#rsyslogd-pstats: @cee: { "name": "resource-usage", "origin": "impstats", "utime": 347553851954, "stime": 88872179113, "maxrss": 415148, "minflt": 639826401, "majflt": 7039, "inblock": 1340376, "oublock": 13264688, "nvcsw": 1999618953, "nivcsw": 6535132 }
#rsyslogd-pstats: @cee: { "name": "pstats queue", "origin": "core.queue", "size": 1, "enqueued": 18064671, "full": 0, "discarded.full": 0, "discarded.nf": 0, "maxqsize": 29 }
#rsyslogd-pstats: @cee: { "name": "send-es-prod queue", "origin": "core.queue", "size": 2, "enqueued": 1658345033, "full": 7020, "discarded.full": 1817, "discarded.nf": 0, "maxqsize": 5000 }
#rsyslogd-pstats: @cee: { "name": "main Q[DA]", "origin": "core.queue", "size": 0, "enqueued": 0, "full": 0, "discarded.full": 0, "discarded.nf": 0, "maxqsize": 0 }
#rsyslogd-pstats: @cee: { "name": "main Q", "origin": "core.queue", "size": 2, "enqueued": 1676409710, "full": 0, "discarded.full": 0, "discarded.nf": 0, "maxqsize": 90022 }
#rsyslogd-pstats: @cee: { "name": "io-work-q", "origin": "imptcp", "enqueued": 5134904, "maxqsize": 3 }
#rsyslogd-pstats: @cee: { "name": "imudp(w0)", "origin": "imudp", "called.recvmmsg": 0, "called.recvmsg": 0, "msgs.received": 0 }

sub rsyslog_parser
{
    ( undef, $_ ) = @_;

    #$pmda->log("rsyslog_parser got line: $_");
    if (! m|rsyslogd-pstats:|) {
	# Not a log entry we can process
	return;
    }
    my $timenow = time;
    if ($lasttime != 0) {
	if ($timenow > $lasttime) {
	    $interval = $timenow - $lasttime;
	    $lasttime = $timenow;
	}
    } else {
	$lasttime = $timenow;
    }

    if (m|imuxsock: origin=imuxsock submitted=(\d+) ratelimit.discarded=(\d+) ratelimit.numratelimiters=(\d+)|) {
	# Modern capture of the imuxsock action data
	($ux_submitted, $ux_discarded, $ux_ratelimiters) = ($1,$2,$3);
    }
    elsif (m|elasticsearch: origin=elasticsearch submitted=(\d+) failed.http=(\d+) failed.httprequests=(\d+) failed.checkConn=(\d+) failed.es=(\d+) response.success=(\d+) response.bad=(\d+) response.duplicate=(\d+) response.badargument=(\d+) response.bulkrejection=(\d+) response.other=(\d+)|) {
	# Modern capture of the omelasticsearch action data
	my $submitted = $1;
	my $failed_http = $2;
	my $failed_httprequests = $3;
	my $failed_checkConn = $4;
	my $failed_es = $5;
	my $response_success = $6;
	my $response_bad = $7;
	my $response_duplicate = $8;
	my $response_badargument = $9;
	my $response_bulkrejection = $10;
	my $response_other = $11;
	($es_connfail, $es_submits, $es_failed, $es_success) = (
	    ($failed_http + $failed_httprequests + $failed_checkConn + $failed_es), $submitted, ($response_bad + $response_duplicate + $response_badargument + $response_bulkrejection + $response_other), $response_success
	);
    }
    elsif (m|stats: (.+): origin=core.queue size=(\d+) enqueued=(\d+) full=(\d+) discarded.full=(\d+) discarded.nf=(\d+) maxqsize=(\d+)|) {
	# Modern capture of queue data
	my ($qname, $qid) = ($1, undef);

	if (!defined($queue_ids{$qname})) {
	    $qid = @queue_insts / 2;
	    $queue_ids{$qname} = $qid;
	    push @queue_insts, ($qid, $qname);
	    $pmda->replace_indom($queue_indom, \@queue_insts);
	}
	$queue_values{$qname} = [ $2, $3, $4, $7 ];
    }
    elsif (m|imuxsock: submitted=(\d+) ratelimit.discarded=(\d+) ratelimit.numratelimiters=(\d+)|) {
	# Legacy capture of the imuxsock action data
	($ux_submitted, $ux_discarded, $ux_ratelimiters) = ($1,$2,$3);
    }
    elsif (m|elasticsearch: connfail=(\d+) submits=(\d+) failed=(\d+) success=(\d+)|) {
	# Legacy capture of the omelasticsearch action data
	($es_connfail, $es_submits, $es_failed, $es_success) = ($1,$2,$3,$4);
    }
    elsif (m|stats: (.+): size=(\d+) enqueued=(\d+) full=(\d+) maxqsize=(\d+)|) {
	# Legacy capture of queue data
	my ($qname, $qid) = ($1, undef);

	if (!defined($queue_ids{$qname})) {
	    $qid = @queue_insts / 2;
	    $queue_ids{$qname} = $qid;
	    push @queue_insts, ($qid, $qname);
	    $pmda->replace_indom($queue_indom, \@queue_insts);
	}
	$queue_values{$qname} = [ $2, $3, $4, $5 ];
    }
}

sub rsyslog_fetch_callback
{
    my ($cluster, $item, $inst) = @_;

    #$pmda->log("rsyslog_fetch_callback for PMID: $cluster.$item ($inst)");

    return (PM_ERR_AGAIN,0) unless ($interval != 0);

    if ($cluster == 0) {
	return (PM_ERR_INST, 0) unless ($inst == PM_IN_NULL);
	if ($item == 0) { return ($interval, 1); }
	if ($item == 1) { return ($ux_submitted, 1); }
	if ($item == 2)	{ return ($ux_discarded, 1); }
	if ($item == 3)	{ return ($ux_ratelimiters, 1); }
	if ($item == 8)	{ return ($es_connfail, 1); }
	if ($item == 9)	{ return ($es_submits, 1); }
	if ($item == 10){ return ($es_failed, 1); }
	if ($item == 11){ return ($es_success, 1); }
    }
    elsif ($cluster == 1) {	# queues
	return (PM_ERR_INST, 0) unless ($inst != PM_IN_NULL);
	return (PM_ERR_INST, 0) unless ($inst <= @queue_insts);
	my $qname = $queue_insts[$inst * 2 + 1];
	my $qvref = $queue_values{$qname};
	my @qvals;

	return (PM_ERR_INST, 0) unless defined ($qvref);
	@qvals = @$qvref;

	if ($item == 0) { return ($qvals[0], 1); }
	if ($item == 1)	{ return ($qvals[1], 1); }
	if ($item == 2)	{ return ($qvals[2], 1); }
	if ($item == 3) { return ($qvals[3], 1); }
    }
    return (PM_ERR_PMID, 0);
}

die "Cannot find a valid rsyslog statistics named pipe: " . $statsfile . "\n" unless -p $statsfile;

$pmda->connect_pmcd;

$pmda->add_metric(pmda_pmid(0,0), PM_TYPE_U64, PM_INDOM_NULL, PM_SEM_INSTANT,
	pmda_units(0,1,0,0,PM_TIME_SEC,0), 'rsyslog.interval',
	'Time interval observed between samples', '');
$pmda->add_metric(pmda_pmid(0,1), PM_TYPE_U64, PM_INDOM_NULL, PM_SEM_COUNTER,
	pmda_units(0,0,1,0,0,PM_COUNT_ONE), 'rsyslog.imuxsock.submitted',
	'Cumulative count of unix domain socket input messages queued',
	"Cumulative count of messages successfully queued to the rsyslog\n" .
	"main message queueing core that arrived on unix domain sockets.");
$pmda->add_metric(pmda_pmid(0,2), PM_TYPE_U64, PM_INDOM_NULL, PM_SEM_COUNTER,
	pmda_units(0,0,1,0,0,PM_COUNT_ONE), 'rsyslog.imuxsock.discarded',
	'Count of unix domain socket messages discarded due to rate limiting',
	"Cumulative count of messages that are were discarded due to their\n" .
	"priority being at or below rate-limit-severity and their sending\n" .
	"process being deemed to be sending messages too quickly (refer to\n" .
	"parameters ratelimitburst, ratelimitinterval and ratelimitseverity");
$pmda->add_metric(pmda_pmid(0,3), PM_TYPE_U64, PM_INDOM_NULL, PM_SEM_COUNTER,
	pmda_units(0,0,0,0,0,0), 'rsyslog.imuxsock.numratelimiters',
	'Count of messages received that could be subject to rate limiting',
	"Cumulative count of messages that rsyslog received and performed a\n" .
	"credentials (PID) lookup for subsequent rate limiting decisions.\n" .
	"The message would have to be at rate-limit-severity or lower, with\n" .
	"rate limiting enabled, in order for this count to be incremented.");
$pmda->add_metric(pmda_pmid(0,8), PM_TYPE_U64, PM_INDOM_NULL, PM_SEM_COUNTER,
	pmda_units(0,0,1,0,0,PM_COUNT_ONE), 'rsyslog.elasticsearch.connfail',
	'Count of failed connections while attempting to send events', '');
$pmda->add_metric(pmda_pmid(0,9), PM_TYPE_U64, PM_INDOM_NULL, PM_SEM_COUNTER,
	pmda_units(0,0,1,0,0,PM_COUNT_ONE), 'rsyslog.elasticsearch.submits',
	'Count of valid submissions of events to elasticsearch indexer', '');
$pmda->add_metric(pmda_pmid(0,10), PM_TYPE_U64, PM_INDOM_NULL, PM_SEM_COUNTER,
	pmda_units(0,0,1,0,0,PM_COUNT_ONE), 'rsyslog.elasticsearch.failed',
	'Count of failed attempts to send events to elasticsearch',
	'This count is often a good indicator of malformed JSON messages');
$pmda->add_metric(pmda_pmid(0,11), PM_TYPE_U64, PM_INDOM_NULL, PM_SEM_COUNTER,
	pmda_units(0,0,1,0,0,PM_COUNT_ONE), 'rsyslog.elasticsearch.success',
	'Count of successfully acknowledged events from elasticsearch', '');

$pmda->add_metric(pmda_pmid(1,0), PM_TYPE_U64, $queue_indom, PM_SEM_INSTANT,
	pmda_units(0,0,0,0,0,0), 'rsyslog.queues.size',
	'Current queue depth for each rsyslog queue',
	"As messages arrive they are enqueued to the main message queue\n" .
	"(for example) -this counter is incremented for each such message.");
$pmda->add_metric(pmda_pmid(1,1), PM_TYPE_U64, $queue_indom, PM_SEM_COUNTER,
	pmda_units(0,0,1,0,0,PM_COUNT_ONE), 'rsyslog.queues.enqueued',
	'Cumulative count of nessages enqueued to individual queues',
	"As messages arrive they are added to the main message processing\n" .
	"queue, either individually or in batches in the case of messages\n" .
	"arriving on the network.");
$pmda->add_metric(pmda_pmid(1,2), PM_TYPE_U64, $queue_indom, PM_SEM_COUNTER,
	pmda_units(0,0,1,0,0,PM_COUNT_ONE), 'rsyslog.queues.full',
	'Cumulative count of message arrivals with a full queue',
	"When messages are enqueued, a check is first made to ensure the\n" .
	"queue is not full.  If it is, this counter is incremented.  The\n" .
	"full-queue-handling logic will wait for a configurable time for\n" .
	"the queue congestion to ease, failing which the message will be\n" .
	"discarded.  Worth keeping an eye on this metric, as it indicates\n" .
	"rsyslog is not able to process messages quickly enough given the\n" .
	"current arrival rate.");
$pmda->add_metric(pmda_pmid(1,3), PM_TYPE_U64, $queue_indom, PM_SEM_INSTANT,
	pmda_units(0,0,1,0,0,PM_COUNT_ONE), 'rsyslog.queues.maxsize',
	'Maximum depth reached by an individual queue',
	"When messages arrive (for example) they are enqueued to the main\n" .
	"message queue - if the queue length on arrival is now greater than\n" .
	"ever before observed, we set this value to the current queue size");

$pmda->add_indom($queue_indom, \@queue_insts,
	'Instance domain exporting each rsyslog queue', '');

$pmda->add_tail($statsfile, \&rsyslog_parser, 0);
$pmda->set_fetch_callback(\&rsyslog_fetch_callback);
$pmda->set_user('pcp');
$pmda->run;
