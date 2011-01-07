#!@PERL@
use POSIX;
#
# $Id: ldmadmin.in,v 1.86.2.3.2.2.2.17.2.53 2009/09/04 15:37:18 steve Exp $
#
# File:         ldmadmin
#
# See file ../COPYRIGHT for copying and redistribution conditions.
#
# Description: This perl script provides a command line interface to LDM
#  programs.
#
# Files:
#
#  $LDMHOME/ldm.pid          file containing process group ID
#  $LDMHOME/.ldmadmin.lck    lock file for operations that modify the state of
#                            the LDM system
#  $LDMHOME/.[0-9a-f]*.info  product-information of the last, successfuly-
#                            received data-product
###############################################################################

###############################################################################
# DEFAULT CONFIGURATION SECTION
###############################################################################
if (! $ENV{'LDMHOME'}) {
    $ENV{'LDMHOME'} = "$ENV{'HOME'}";
}

###############################################################################
# END OF DEFAULT CONFIGURATION
###############################################################################
srand;	# called once at start

# Some parameters used by this script:
$ldmhome = "@LDMHOME@";
$progname = "ldmadmin";
$feedset = "ANY";
chop($os = `uname -s`);
chop($release = `uname -r`);
$begin = 19700101;
$end = 30000101;
$lock_file = "$ldmhome/.ldmadmin.lck";
$pid_file = "$ldmhome/ldmd.pid";
$bin_path = "$ldmhome/bin";
$line_prefix = "";
$pqact_conf_option = 0;

# Ensure that some environment variables are set.
$ENV{'PATH'} = "$bin_path:$ENV{'PATH'}";

# we want a flush after every print statement
$| = 1;

# Get the command. Default to "usage" if no command specified.
$_ = $ARGV[0];
shift;
$command = $_;
if (!$command) {
    $command = "usage";
}

# Ensure that the registry is available because a locked registry will cause
# this script to hang.
if (resetRegistry()) {
    exit 4;
}

# Get some registry parameters
@regpar = (
    [\$ldmd_conf, "regpath{LDMD_CONFIG_PATH}"],
    [\$pq_path, "regpath{QUEUE_PATH}"],
    [\$hostname, "regpath{HOSTNAME}"],
    [\$insertion_check_period, "regpath{INSERTION_CHECK_INTERVAL}"],
    [\$pq_size, "regpath{QUEUE_SIZE}"],
    [\$pq_slots, "regpath{QUEUE_SLOTS}"],
    [\$reconMode, "regpath{RECONCILIATION_MODE}"],
    [\$surf_path, "regpath{SURFQUEUE_PATH}"],
    [\$surf_size, "regpath{SURFQUEUE_SIZE}"],
    [\$metrics_file, "regpath{METRICS_FILE}"],
    [\$metrics_files, "regpath{METRICS_FILES}"],
    [\$log_file, "regpath{LOG_FILE}"],
    [\$numlogs, "regpath{LOG_COUNT}"],
    [\$log_rotate, "regpath{LOG_ROTATE}"],
    [\$num_metrics, "regpath{METRICS_COUNT}"],
    [\$ip_addr, "regpath{IP_ADDR}"],
    [\$port, "regpath{PORT}"],
    [\$max_clients, "regpath{MAX_CLIENTS}"],
    [\$max_latency, "regpath{MAX_LATENCY}"],
    [\$offset, "regpath{TIME_OFFSET}"],
    [\$pqact_conf, "regpath{PQACT_CONFIG_PATH}"],
    [\$scour_file, "regpath{SCOUR_CONFIG_PATH}"],
    [\$check_time , "regpath{CHECK_TIME}"],
    [\$warn_if_check_time_disabled, "regpath{WARN_IF_CHECK_TIME_DISABLED}"],
    [\$ntpdate, "regpath{NTPDATE_COMMAND}"],
    [\$ntpdate_timeout, "regpath{NTPDATE_TIMEOUT}"],
    [\$time_servers, "regpath{NTPDATE_SERVERS}"],
    [\$check_time_limit, "regpath{CHECK_TIME_LIMIT}"],
    [\$netstat, "regpath{NETSTAT_COMMAND}"],
    [\$top, "regpath{TOP_COMMAND}"],
    [\$delete_info_files, "regpath{DELETE_INFO_FILES}"],
);
for my $entryRef (@regpar) {
    ${$entryRef->[0]} = `regutil $entryRef->[1]` || \
        die "Couldn't get \"$entryRef->[1]\"";
    chop(${$entryRef->[0]});
}
@time_servers = split(/\s+/, $time_servers);

# Check the hostname for a fully-qualified version.
#
if ($hostname !~ /\./) {
    errmsg("The LDM-hostname is not fully-qualified.  " . 
        "Execute the command \"regutil -s <hostname> regpath{HOSTNAME}\" ".
        "to set the fully-qualified name of the host.");
    exit 1;
}

# Change the current working directory to the home directory.  This will prevent
# core files from being created all over the place.
#
chdir $ldmhome;

#
# process the command request
#
if ($command eq "start") {	# start the ldm
    while ($_ = $ARGV[0]) {
        shift;
        /^([a-z]|[A-Z]|\/)/ && ($ldmd_conf = $_);
        /^-q/ && ($q_path = shift);
        /^-v/ && $verbose++;
        /^-x/ && ($debug++, $verbose++);
        /^-M/ && ($max_clients = shift);
        /^-m/ && ($max_latency = shift);
        /^-o/ && ($offset = shift);
    }
    if ($q_path) {
        $pq_path = $q_path;
    }
    if (0 == ($status = getLock())) {
        $status = start_ldm();
        releaseLock();
    }
}
elsif ($command eq "stop") {	# stop the ldm
    if (0 == ($status = getLock())) {
        $status = stop_ldm();
        releaseLock();
    }
}
elsif ($command eq "restart") {	# restart the ldm
    while ($_ = $ARGV[0]) {
        shift;
        /^([a-z]|[A-Z]|\/)/ && ($ldmd_conf = $_);
        /^-q/ && ($q_path = shift);
        /^-v/ && $verbose++;
        /^-x/ && ($debug++, $verbose++);
        /^-M/ && ($max_clients = shift);
        /^-m/ && ($max_latency = shift);
        /^-o/ && ($offset = shift);
    }
    if ($q_path) {
        $pq_path = $q_path;
    }
    if (0 == ($status = getLock())) {
        $status = stop_ldm();
        if (!$status) {
            $status = start_ldm();
        }
        releaseLock();
    }
}
elsif ($command eq "mkqueue") {	# create a product queue using pqcreate(1)
    while ($_ = $ARGV[0]) {
        shift;
        /^-q/ && ($q_path = shift);
        /^-c/ && $pq_clobber++;
        /^-f/ && $pq_fast++;
        /^-v/ && $verbose++;
        /^-x/ && ($debug++, $verbose++);
    }
    if ($q_path) {
        $pq_path = $q_path;
    }
    if (0 == ($status = getLock())) {
        $status = make_pq();
        releaseLock();
    }
}
elsif ($command eq "delqueue") { # delete a product queue
    while ($_ = $ARGV[0]) {
        shift;
        /^-q/ && ($q_path = shift);
    }
    if ($q_path) {
        $pq_path = $q_path;
    }
    if (0 == ($status = getLock())) {
        $status = deleteQueue($pq_path);
        if ($status == 0 && $delete_info_files) {
            unlink <.*.info>;
        }
        releaseLock();
    }
}
elsif ($command eq "mksurfqueue") { # create a product queue for pqsurf(1)
    while ($_ = $ARGV[0]) {
        shift;
        /^-q/ && ($q_path = shift);
        /^-c/ && $pq_clobber++;
        /^-f/ && $pq_fast++;
        /^-v/ && $verbose++;
        /^-x/ && ($debug++, $verbose++);
    }
    if ($q_path) {
        $surf_path = $q_path;
    }
    if (0 == ($status = getLock())) {
        $status = make_surf_pq();
        releaseLock();
    }
}
elsif ($command eq "delsurfqueue") { # delete a pqsurf product queue
    while ($_ = $ARGV[0]) {
        shift;
        /^-q/ && ($q_path = shift);
    }
    if ($q_path) {
        $surf_path = $q_path;
    }
    if (0 == ($status = getLock())) {
        $status = deleteQueue($surf_path);
        releaseLock();
    }
}
elsif ($command eq "newlog") {	# rotate the log files
    while ($_ = $ARGV[0]) {
        shift;
        /^-n/ && ($numlogs = shift);
        /^-l/ && ($log_file = shift);
    }
    $status = new_log();
}
elsif ($command eq "scour") {	# scour data directories
    system("scour $scour_file");
    $status = $?;
}
elsif ($command eq "isrunning") { # check if the ldm is running
    $status = !isRunning($pid_file, $ip_addr);
}
elsif ($command eq "checkinsertion") { # check if a product has been inserted
    $status = check_insertion();
}
elsif ($command eq "vetqueuesize") { # vet the size of the queue
    if (0 == ($status = getLock())) {
        $status = vetQueueSize();
        releaseLock();
    }
}
elsif ($command eq "check") {	# check the LDM system
    if (0 == ($status = getLock())) {
        $status = check_ldm();
        releaseLock();
    }
}
elsif ($command eq "watch") {	# monitor incoming products
    while ($_ = $ARGV[0]) {
        shift;
        /^-f/ && ($feedset = shift);
    }
    if (!isRunning($pid_file, $ip_addr)) {
	errmsg("There is no LDM server running");
        $status = 1;
    }
    else {
        system("pqutil -r -f \"$feedset\" -w $pq_path");
        $status = $?;
    }
}
elsif ($command eq "pqactcheck") {	# check pqact file for errors
    while ($_ = $ARGV[0]) {
        shift;
        /^([a-z]|[A-Z]|\/)/ && ($ldmd_conf = $_);
        /^-p/ && ($pqact_conf = shift, $pqact_conf_option = 1);
    }
    $status = !are_pqact_confs_ok();
}
elsif ($command eq "pqactHUP") {	# HUP pqact 
    $status = ldmadmin_pqactHUP();
}
elsif ($command eq "queuecheck") {	# check queue for corruption 
    if (isRunning($pid_file, $ip_addr)) {
	errmsg("queuecheck: The LDM system is running. queuecheck aborted");
        $status = 1;
    }
    else {
        $status = !isProductQueueOk();
    }
}
elsif ($command eq "config") {	# show the ldm configuration
    $status = ldm_config();
}
elsif ($command eq "log") {	# page the logfile
    system("$ENV{'PAGER'}","$log_file");
    $status = $?;
}
elsif ($command eq "tail") {	# do a "tail -f" on the logfile
    system("tail","-f","$log_file");
    $status = $?;
}
elsif ($command eq "clean") {	# clean up after an abnormal termination
    if (isRunning($pid_file, $ip_addr)) {
	errmsg("The LDM system is running!  Stop it first.");
	$status = 1;
    }
    elsif ((-e $pid_file) && (unlink($pid_file) == 0)) {
        errmsg("Couldn't remove LDM server PID-file \"$pid_file\"");
        $status = 3;
    }
    else {
	$status = 0;
    }
}
elsif ($command eq "checktime") {
    print "Checking accuracy of system clock ... ";
    $check_time = 1;
    if (checkTime()) {
        print "\n";
	$status = 1;
    }
    else {
	print "OK\n";
    }
}
elsif ($command eq "printmetrics") {
    $status = printMetrics();
}
elsif ($command eq "addmetrics") {
    $status = system("ldmadmin printmetrics >>$metrics_file");
}
elsif ($command eq "plotmetrics") {
    while ($_ = $ARGV[0]) {
        shift;
        /^-b/ && ($begin = shift);
        /^-e/ && ($end = shift);
    }
    $status = plotMetrics();
}
elsif ($command eq "newmetrics") {
    $status = system("newlog $metrics_file $num_metrics");
}
elsif ($command eq "usage") {	# print usage message
    print_usage();
    $status = 0;
}
else {				# bad command
    errmsg("Unknown command: \"$command\"");
    print_usage();
    $status = 1;
}
#
# that's all folks
#
exit $status;

###############################################################################
# Date Routine.  Gets data and time as GMT in the same format as the LDM log
# file.
###############################################################################

sub get_date
{
    @month_array = (Jan,Feb,Mar,Apr,May,Jun,Jul,Aug,Sep,Oct,Nov,Dec);
 
    my($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) =
        gmtime(time());
 
    my($date_string) =
        sprintf("%s %d %02d:%02d:%02d UTC", $month_array[$mon], $mday,
                $hour, $min,$sec);
 
    return $date_string;
}

###############################################################################
# Print a usage message and exit.  Should only be called when the command is
# usage, or command line arguments are bad or missing.
###############################################################################

sub print_usage
{
    print "\
Usage: $progname command [arg ...]

commands:
    start [-v] [-x] [-m maxLatency] [-o offset] [-q q_path] [-M max_clients]
        [conf_file]                          Starts the LDM
    stop                                     Stops the LDM
    restart [-v] [-x] [-m maxLatency] [-o offset] [-q q_path] [-M max_clients]
        [conf_file]                          Restarts a running LDM
    mkqueue [-v] [-x] [-c] [-f] [-q q_path]  Creates a product-queue
    delqueue [-q q_path]                     Deletes a product-queue
    mksurfqueue [-v] [-x] [-c] [-f] [-q q_path]
                                             Creates a product-queue for
                                                 pqsurf(1)
    delsurfqueue [-q q_path ]                Deletes a pqsurf(1) product-queue
    newlog [-n numlogs] [-l logfile]         Rotates a log file
    scour                                    Scours data directories
    isrunning                                Exits status 0 if LDM is running
                                                 else exit 1
    checkinsertion                           Checks for recent insertion of
                                                 data-product into product-queue
    vetqueuesize                             Vets the size of the product-queue
    pqactcheck [-p pqact_conf] [conf_file]   Checks syntax of pqact(1) files
    pqactHUP                                 Sends HUP signal to pqact(1)
                                                 program
    queuecheck                               Checks for product-queue corruption
    watch [-f feedset]                       Monitors incoming products
    config                                   Prints LDM configuration
    log                                      Pages through the LDM log file
    tail                                     Monitors the LDM log file
    checktime                                Checks the system clock
    clean                                    Cleans up after an abnormal
                                                 termination
    printmetrics                             Prints LDM metrics
    addmetrics                               Accumulates LDM metrics
    plotmetrics [-b begin] [-e end]          Plots LDM metrics
    newmetrics                               Rotates the metrics files
    usage                                    Prints this message

options:
    -b begin        Begin time as YYYYMMDD[.hh[mm[ss]]]
    -c              Clobber an exisiting product-queue
    -e end          End time as YYYYMMDD[.hh[mm[ss]]]
    -f              Create queue \"fast\"
    -f feedset      Feed-set to use with command. Default: $feedset
    -l logfile      Pathname of logfile. Default: $log_file
    -m maxLatency   Conditional data-request temporal-offset
    -M max_clients  Maximum number of active clients
    -n numlogs      Number of logs to rotate. Default: $numlogs
    -o offset       Unconditional data-request temporal-offset
    -q q_path       Specify a product-queue path. LDM Default: $pq_path,
                    pqsurf(1) default: $surf_path
    -v              Turn on verbose mode
    -x              Turn on debug mode (includes verbose mode)

conf_file:
    Which LDM configuration-file file to use. Default: $ldmd_conf
";
}

# Resets the LDM registry.
#
# Returns:
#       0               Success.
#       else            Failure.  "errmsg()" called.
#
sub resetRegistry
{
    my $status = 1;     # default failure

    if (system("regutil -R")) {
	errmsg("Couldn't reset LDM registry");
    }
    else {
        $status = 0;
    }

    return $status;
}

use Fcntl qw(:flock SEEK_END); # import LOCK_* and SEEK_END constants

###############################################################################
# Lock the lock-file.
###############################################################################

sub getLock
{
    my $status = 0;     # default success

    if (!open(LOCKFILE,">$lock_file")) {
        errmsg("getLock(): Cannot create/open lock-file \"$lock_file\"");
        $status = 1;
    }
    else {
        if (!flock(LOCKFILE, LOCK_EX | LOCK_NB)) {
            errmsg("getLock(): Couldn't lock lock-file \"$lock_file\". ".
                    "Another ldmadmin(1) script is likely running.");
            $status = 1;
            close(LOCKFILE);
        }
    }

    return $status;
}

###############################################################################
# Unlock the lock file.
###############################################################################

sub releaseLock
{
    if (!flock(LOCKFILE, LOCK_UN)) {
        errmsg("releaseLock(): Couldn't unlock lock-file \"$lock_file\"");
    }

    close(LOCKFILE);
}

###############################################################################
# create a product queue
###############################################################################

sub make_pq
{
    my $status = 1;     # default failure

    if ($q_size) {
	errmsg("product queue -s flag not supported, no action taken.");
    }
    else {
        # Ensure the LDM system isn't running
        if (isRunning($pid_file, $ip_addr)) {
            errmsg("make_pq(): There is a server running, mkqueue aborted");
        }
        else {
            # Build the command line
            $cmd_line = "pqcreate";
            $cmd_line .= " -x" if ($debug);
            $cmd_line .= " -v" if ($verbose);
            $cmd_line .= " -c" if ($pq_clobber);
            $cmd_line .= " -f" if ($pq_fast);
            $cmd_line .= " -S $pq_slots" if ($pq_slots ne "default");
            $cmd_line .= " -q $pq_path -s $pq_size";

            # execute pqcreate(1)
            if (system("$cmd_line")) {
                errmsg("make_pq(): mkqueue(1) failed");
            }
            else {
                $status = 0;
            }
        }                           # LDM system not running
    }

    return 0;
}

###############################################################################
# Deletes a product-queue
###############################################################################

sub deleteQueue
{
    my $queuePath       = $_[0];
    my $status          = 1;     # default failure

    # Check to see if the server is running.
    if (isRunning($pid_file, $ip_addr)) {
        errmsg("deleteQueue(): The LDM is running, cannot delete the queue");
    }
    else {
        # Delete the queue
        if (! -e $queuePath) {
            errmsg("deleteQueue(): Product-queue \"$queuePath\" doesn't exist");
            $status = 0;
        }
        else {
            if (unlink($queuePath) != 1) {
                errmsg("deleteQueue(): Couldn't delete product-queue ".
                        "\"$queuePath\": $!");
            }
            else {
                $status = 0;
            }
        }
    }

    return $status;
}

###############################################################################
# create a pqsurf product queue
###############################################################################

sub make_surf_pq
{
    my $status = 1;                     # default failure

    if ($q_size) {
	errmsg("product queue -s flag not supported, no action taken.");
    }
    else {
        # can't do this while there is a server running
        if (isRunning($pid_file, $ip_addr)) {
            errmsg("make_surf_pq(): There is a server running, ".
                "mkqueue aborted");
        }
        else {
            # need the number of slots to create
            $surf_slots = $surf_size / 1000000 * 6881;

            # build the command line
            $cmd_line = "pqcreate";

            if ($debug) {
                $cmd_line .= " -x";
            }
            if ($verbose) {
                $cmd_line .= " -v";
            }

            if ($pq_clobber) {
                $cmd_line .= " -c";
            }

            if ($pq_fast) {
                $cmd_line .= " -f";
            }

            $cmd_line .= " -S $surf_slots -q $surf_path -s $surf_size";

            # execute pqcreate
            if (system("$cmd_line")) {
                errmsg("make_surf_pq(): pqcreate(1) failure");
            }
            else {
                $status = 0;
            }
        }
    }

    return $status;
}

###############################################################################
# start the LDM server
###############################################################################

sub start
{
    my $status = 0;     # default success

    # Build the command line
    $cmd_line = "ldmd -I $ip_addr -P $port -M $max_clients -m $max_latency ".
        "-o $offset -q $pq_path";

    if ($debug) {
        $cmd_line .= " -x";
    }
    if ($verbose) {
        $cmd_line .= " -v";
    }

    # Check the ldm(1) configuration-file
    print "Checking LDM configuration-file ($ldmd_conf)...\n";
    my $prev_line_prefix = $line_prefix;
    $line_prefix .= "    ";
    ( @output ) = `$cmd_line -nl- $ldmd_conf 2>&1` ;
    if ($?) {
        errmsg("start(): Problem with LDM configuration-file:\n".
            "@output");
        $status = 1;
    }
    else {
        $line_prefix = $prev_line_prefix;

        print "Starting the LDM server...\n";
        system("$cmd_line $ldmd_conf > $pid_file");
        if ($?) {
            unlink($pid_file);
            errmsg("start(): Could not start LDM server");
            $status = 1;
        }
        else {
            # Check to make sure the LDM is running
            my($loopcount) = 1;
            while(!isRunning($pid_file, $ip_addr)) {
                if($loopcount > 15) {
                    errmsg("start(): ".
                        "Server not started.");
                    $status = 1;        # failure
                    break;
                }
                sleep($loopcount);
                $loopcount++;
            }
        }
    }

    return $status;
}

sub start_ldm
{
    my $status = 0;     # default success

    # Make sure there is no other server running
    #print "start_ldm(): Checking for running LDM\n";
    if (isRunning($pid_file, $ip_addr)) {
        errmsg("start_ldm(): There is another server running, ".
            "start aborted");
        $status = 1;
    }
    else {
        #print "start_ldm(): Checking for PID-file\n";
        if (-e $pid_file) {
            errmsg("start_ldm(): PID-file \"$pid_file\" exists.  ".
                "Verify that all is well and then execute ".
                "\"ldmadmin clean\" to remove the PID-file.");
            $status = 1;
        }
        else {
            # Check the product-queue
            #print "start_ldm(): Checking product-queue\n";
            if (!isProductQueueOk())  {
                errmsg("LDM not started");
                $status = 1;
            }
            else {
                # Check the pqact(1) configuration-file(s)
                print "Checking pqact(1) configuration-file(s)...\n";
                my $prev_line_prefix = $line_prefix;
                $line_prefix .= "    ";
                if (!are_pqact_confs_ok()) {
                    errmsg("");
                    $status = 1;
                }
                else {
                    $line_prefix = $prev_line_prefix;

                    # Rotate the ldm log files if appropriate
                    if ($log_rotate) {
                        #print "start_ldm(): Rotating log files\n";
                        if (new_log()) {
                            errmsg("start_ldm(): ".
                                "Couldn't rotate log files");
                            $status = 1;
                        }
                    }

                    if (0 == $status) {
                        $status = start();
                    }
                }                   # pqact(1) config-files OK
            }                       # product-queue OK
        }                           # PID-file doesn't exist
    }                               # LDM not running

    return $status;
}

###############################################################################
# stop the LDM server
###############################################################################

sub stop_ldm
{
    my $status = 0;                     # default success

    # get pid 
    $rpc_pid = getPid($pid_file) ;

    if ($rpc_pid == -1) {
        errmsg("The LDM server isn't running or its process-ID is ".
            "unavailable");
        $status = 1;
    }
    else {
        # kill the server and associated processes
        print "Stopping the LDM server...\n";
        system( "kill $rpc_pid" );

        # we may need to sleep to make sure that the port is deregistered
        my($loopcount) = 1;
        while(isRunning($pid_file, $ip_addr)) {
            if($loopcount > 65) {
                errmsg("stop_ldm: LDM server not dead.");
                $status = 1;
                last;
            }
            print "Waiting for the LDM server to terminate...\n" ;
            sleep($loopcount);
            $loopcount++;
        }
    }

    if (0 == $status) {
        # remove product-information files that are older than the LDM pid-file.
        removeOldProdInfoFiles();

        # get rid of the pid file
        unlink($pid_file);
    }

    return $status;
}

###############################################################################
# rotate the specified log file, keeping $numlog files
###############################################################################

sub new_log
{
    my $status = 1;      # default failure

    # Rotate the log file
    system("newlog $log_file $numlogs");

    # If rotation successful, notify syslogd(8)
    if ($?) {
	errmsg("new_log(): log rotation failed");
    }
    else {
	system("hupsyslog");

        if ($?) {
            errmsg("new_log(): Couldn't notify system logging daemon");
        }
        else {
            $status = 0;        # success
        }
    }

    return $status;
}

###############################################################################
# print the LDM configuration information
###############################################################################

sub ldm_config
{
    print  "\n";
    print  "hostname:              $hostname\n";
    print  "os:                    $os\n";
    print  "release:               $release\n";
    print  "ldmhome:               $ldmhome\n";
    print  "LDM version:           @VERSION@\n";
    print  "PATH:                  $ENV{'PATH'}\n";
    print  "LDM conf file:         $ldmd_conf\n";
    print  "pqact(1) conf file:    $pqact_conf\n";
    print  "scour(1) conf file:    $scour_file\n";
    print  "product queue:         $pq_path\n";
    print  "queue size:            $pq_size bytes\n";
    print  "queue slots:           $pq_slots\n";
    print  "reconcilliation mode:  $reconMode\n";
    print  "pqsurf(1) path:        $surf_path\n";
    print  "pqsurf(1) size:        $surf_size\n";
    printf "IP address:            %s\n", length($ip_addr) ? $ip_addr : "all";
    printf "port:                  %d\n", length($port) ? $port : @LDM_PORT@; 
    print  "PID file:              $pid_file\n";
    print  "Lock file:             $lock_file\n";
    print  "maximum clients:       $max_clients\n";
    print  "maximum latency:       $max_latency\n";
    print  "time offset:           $offset\n";
    print  "log file:              $log_file\n";
    print  "numlogs:               $numlogs\n";
    print  "log_rotate:            $log_rotate\n";
    print  "netstat:               $netstat\n";
    print  "top:                   $top\n";
    print  "metrics file:          $metrics_file\n";
    print  "metrics files:         $metrics_files\n";
    print  "num_metrics:           $num_metrics\n";
    print  "check time:            $check_time\n";
    print  "delete info files:     $delete_info_files\n";
    print  "ntpdate(1):            $ntpdate\n";
    print  "ntpdate(1) timeout:    $ntpdate_timeout\n";
    print  "time servers:          ", join(" ", @time_servers), "\n";
    print  "time-offset limit:     $check_time_limit\n";
    print "\n";

    return 0;
}

###############################################################################
# check if the LDM is running.  return 1 if running, 0 if not.
###############################################################################

sub isRunning
{
    my $pid_file = $_[0];
    my $ip_addr = $_[1];
    my($running) = 0;
    my($pid) = getPid($pid_file);

    if ($pid != -1) {
	system("kill -0 $pid > /dev/null 2>&1");
	$running = !$?;
    }

    if (!$running) {
	my($cmd_line) = "ldmping -l- -i 0";
	$cmd_line = $cmd_line . " $ip_addr" if $ip_addr ne "0.0.0.0";

	system("$cmd_line > /dev/null 2>&1");
	$running = !$?;
    }

    return $running;
}

###############################################################################
# Check that a data-product has been inserted into the product-queue
###############################################################################

sub check_insertion
{
    my $status = 1;                     # default failure
    chomp(my($line) = `pqmon -S -q $pq_path`);

    if ($?) {
        errmsg("check_insertion(): pqmon(1) failure");
    }
    else {
        my @params = split(/\s+/, $line);
        my $age = $params[8];

        if ($age > $insertion_check_period) {
            errmsg("check_insertion(): The last data-product was inserted ".
                "$age seconds ago, which is greater than the registry-".
                "parameter \"regpath{INSERTION_CHECK_INTERVAL}\" ".
                "($insertion_check_period seconds).");
        }
        else {
            $status = 0;
        }
    }

    return $status;
}

###############################################################################
# Check the size of the queue.
###############################################################################

sub grow
{
    my $oldQueuePath = $_[0];
    my $newQueuePath = $_[1];
    my $status = 1;                     # failure default;

    print "Copying products from old queue to new queue...\n";
    if (system("pqcopy $oldQueuePath $newQueuePath")) {
        errmsg("grow(): Couldn't copy products");
    }
    else {
        print "Renaming old queue\n";
        if (system("mv -f $oldQueuePath $oldQueuePath.old")) {
            errmsg("grow(): Couldn't rename old queue");
        }
        else {
            print "Renaming new queue\n";
            if (system("mv $newQueuePath $oldQueuePath")) {
                errmsg("grow(): Couldn't rename new queue");
            }
            else {
                print "Deleting old queue\n";
                if (unlink($oldQueuePath.".old") != 1) {
                    errmsg("grow(): Couldn't delete old queue");
                }
                else {
                    $status = 0;        # success
                }
            }                           # new queue renamed

            if ($status) {
                print "Restoring old queue\n";
                if (system("mv -f $oldQueuePath.old $oldQueuePath")) {
                    errmsg("grow(): Couldn't restore old queue");
                }
            }
        }                               # old queue renamed
    }                                   # products copied

    return $status;
}

sub saveQueuePar
{
    my $size = $_[0];
    my $slots = $_[1];
    my $status = 1;                     # failure default

    if (system("regutil -u $size regpath{QUEUE_SIZE}")) {
        errmsg("saveQueuePar(): Couldn't save new queue size");
    }
    else {
        if (system("regutil -u $slots regpath{QUEUE_SLOTS}")) {
            errmsg("saveQueuePar(): Couldn't save queue slots");

            print "Restoring previous queue size\n";
            if (system("regutil -u $pq_size regpath{QUEUE_SIZE}")) {
                errmsg("saveQueuePar(): Couldn't restore previous queue size");
            }
        }
        else {
            $pq_size = $size;
            $pq_slots = $slots;
            $status = 0;                # success
        }
    }

    return $status;
}

sub saveTimePar
{
    my $newTimeOffset = $_[0];
    my $newMaxLatency = $_[1];
    my $status = 1;                     # failure default

    if (system("regutil -u $newTimeOffset regpath{TIME_OFFSET}")) {
        errmsg("saveTimePar(): Couldn't save new time-offset");
    }
    else {
        if (system("regutil -u $newMaxLatency regpath{MAX_LATENCY}")) {
            errmsg("saveTimePar(): Couldn't save new maximum acceptable ".
                "latency");

            print "Restoring previous time-offset\n";
            if (system("regutil -u $offset regpath{TIME_OFFSET}")) {
                errmsg("saveTimePar(): Couldn't restore previous time-offset");
            }
        }
        else {
            $offset = $newTimeOffset;
            $max_latency = $newMaxLatency;
            $status = 0;                # success
        }
    }

    return $status;
}

sub vetQueueSize
{
    my $increaseQueue = "increase queue";
    my $decreaseMaxLatency = "decrease maximum latency";
    my $doNothing = "do nothing";
    my $status = 1;                     # failure default
    chomp(my $line = `pqmon -S -q $pq_path`);

    if ($?) {
        errmsg("vetQueueSize(): pqmon(1) failure");
    }
    else {
        my @params = split(/\s+/, $line);
        my $isFull = $params[0];
        my $minVirtResTime = $params[9];

        if (!$isFull || $minVirtResTime < 0 || $minVirtResTime >= $offset) {
            $status = 0;
        }
        else {
            errmsg("vetQueueSize(): The maximum acceptable latency ".
                "(registry parameter \"regpath{MAX_LATENCY}\": ".
                "$max_latency seconds) is greater ".
                "than the observed minimum virtual residence time of ".
                "data-products in the queue ($minVirtResTime seconds).  This ".
                "will hinder detection of duplicate data-products.");

            print "The value of the ".
                "\"regpath{RECONCILIATION_MODE}\" registry-parameter is ".
                "\"$reconMode\"\n";
            if ($reconMode eq $increaseQueue) {
                print "Increasing the capacity of the queue...\n";

                if (0 >= $minVirtResTime) {
                    # Use age of oldest product, instead
                    $minVirtResTime = $params[7];
                }
                if (0 >= $minVirtResTime) {
                    # Ensure that the divisor isn't zero
                    $minVirtResTime = 1;
                }
                my $ratio = $offset/$minVirtResTime + 0.1;
                my $newByteCount = int($ratio*$params[3]);
                my $newSlotCount = int($ratio*$params[6]);
                my $newQueuePath = "$pq_path.new";

                print "Creating new queue of $newByteCount ".
                    "bytes and $newSlotCount slots...\n";
                if (system("pqcreate -c -S $newSlotCount -s $newByteCount ".
                        "-q $newQueuePath")) {
                    errmsg("vetQueueSize(): Couldn't create new queue: ".
                        "$newQueuePath");
                }
                else {
                    my $restartNeeded;
                    $status = 0;

                    if (isRunning($pid_file, $ip_addr)) {
                        print "Stopping the LDM...\n";
                        if (0 == ($status = stop_ldm())) {
                            $restartNeeded = 1;
                        }
                    }
                    if (0 == $status) {
                        if (0 == ($status = grow($pq_path, $newQueuePath))) {
                            print "Saving new queue parameters...\n";
                            $status =
                                saveQueuePar($newByteCount, $newSlotCount);
                        }

                        if ($restartNeeded) {
                            print "Restarting the LDM...\n";
                            if ($status = start_ldm()) {
                                errmsg("vetQueueSize(): ".
                                    "Couldn't restart the LDM");
                            }
                        }
                    }                   # LDM stopped
                }                       # new queue created
            }                           # mode is increase queue
            elsif ($reconMode eq $decreaseMaxLatency) {
                print "Decreasing the maximum acceptable ".
                    "latency and the time-offset of requests (registry ".
                    "parameters \"regpath{MAX_LATENCY}\" and ".
                    "\"regpath{TIME_OFFSET}\")...\n";

                if (0 >= $minVirtResTime) {
                    # Use age of oldest product, instead
                    $minVirtResTime = $params[7];
                }
                $minVirtResTime = 1 if (0 >= $minVirtResTime);
                my $ratio = $minVirtResTime/$max_latency;
                my $newMaxLatency = int($ratio*$max_latency);
                my $newTimeOffset = $newMaxLatency;

                print "New time-offset and maximum latency: ".
                    "$newTimeOffset seconds\n";
                print "Saving new time parameters...\n";
                if (0 == ($status = saveTimePar($newTimeOffset,
                        $newMaxLatency))) {
                    if (isRunning($pid_file, $ip_addr)) {
                        print "Restarting the LDM...\n";
                        if ($status = stop_ldm()) {
                            errmsg("vetQueueSize(): Couldn't stop LDM");
                        }
                        else {
                            if ($status = start_ldm()) {
                                errmsg("vetQueueSize(): Couldn't start LDM");
                            }
                        }               # LDM stopped
                    }                   # LDM is running
                }                       # new time parameters saved
            }                           # mode is decrease max latency
            elsif ($reconMode eq $doNothing) {
                print "Doing nothing.  You should consider setting ".
                    "registry-parameter \"regpath{RECONCILIATION_MODE}\" ".
                    "to \"$increaseQueue\" or \"$decreaseMaxLatency\" or ".
                    "recreate the queue yourself.\n";
            }
            else {
                errmsg("Unknown reconciliation mode: \"$reconMode\"");
            }
        }
    }

    return $status;
}

###############################################################################
# Check the LDM system.
###############################################################################

sub check_ldm
{
    my $status;

    print "Checking for a running LDM system...\n";
    if (!isRunning($pid_file, $ip_addr)) {
        errmsg("The LDM server is not running");
        $status = 2;
    }
    else {
        print "Checking the system clock...\n";
        if (checkTime()) {
            $status = 3;
        }
        else {
            print "Checking the most-recent insertion into the queue...\n";
            if (check_insertion()) {
                $status = 4;
            }
            else {
                print "Vetting the size of the queue and the maximum ".
                    "acceptable latency...\n";
                if (vetQueueSize()) {
                    $status = 5;
                }
                else {
                    $status = 0;
                }
            }
        }
    }

    return $status;
}

###############################################################################
# get PID number.  return pid or -1
###############################################################################

sub getPid
{
    my $pid_file = $_[0];
    my( $i, @F, $pid_num ) ;

    if (-e $pid_file) {
	    open(PIDFILE,"<$pid_file");
	    $pid_num = <PIDFILE>;
	    chomp( $pid_num );
	    close( PIDFILE ) ;
	    return $pid_num if( $pid_num =~ /^\d{1,6}/ ) ;
    }
    return -1;
}

###############################################################################
# Check the pqact.conf file(s) for errors
###############################################################################

sub are_pqact_confs_ok
{
    my $are_ok = 1;
    my @pathnames = ();

    if ($pqact_conf_option) {
	# A "pqact" configuration-file was specified on the command-line.
	@pathnames = ($pqact_conf);
    }
    else {
	# No "pqact" configuration-file was specified on the command-line.
	# Set "@pathnames" according to the "pqact" configuration-files
	# specified in the LDM configuration-file.
	if (!open(LDM_CONF_FILE, "<$ldmd_conf")) {
	    errmsg("Could not open LDM configuration-file, $ldmd_conf");
            $are_ok = 0;
	}
	else {
	    while (<LDM_CONF_FILE>) {
		if (/^exec/i && /pqact/) {
		    chomp;
		    s/^exec\s+"\s*//i;
		    s/\s*"\s*$//;

		    my @fields = split;
		    my $pathname;

		    if (($#fields == 0) ||
			    ($fields[$#fields] =~ /^-/) ||
			    ($fields[$#fields-1] =~ /^-[ldqfpito]/)) {
		    	$pathname = $pqact_conf;
		    }
		    else {
			$pathname = $fields[$#fields];
		    }
		    @pathnames = (@pathnames, $pathname);
		}
	    }

	    close(LDM_CONF_FILE);
	}
    }

    if ($are_ok) {
    for my $pathname (@pathnames) {
	# Examine the "pqact" configuration-file for leading spaces.
	my @output;
	my $leading_spaces = 0;

	print "$line_prefix$pathname: ";

	( @output ) = `grep -n "^ " $pathname 2> /dev/null` ;
	if ($#output >= 0) {
	    print "remove leading spaces in the following:\n" ;

	    my $prev_line_prefix = $line_prefix;
	    $line_prefix .= "    ";

	    for my $line (@output) {
		print "$line_prefix$line";
	    }

	    $line_prefix = $prev_line_prefix;
	    $leading_spaces = 1;
	}

	if ($leading_spaces) {
	    $are_ok = 0;
	}
	else {
	    # Check the syntax of the "pqact" configuration-file via "pqact".
	    my $read_ok = 0;

	    ( @output ) = `pqact -vl - -q /dev/null $pathname 2>&1` ;

	    for my $line (@output) {
		if ($line =~ /Successfully read/) {
		    $read_ok = 1;
		    last;
		}
	    }

	    if ($read_ok) {
		print "syntactically correct\n" ;
	    }
	    else {
		print "has problems:\n" ;

		my $prev_line_prefix = $line_prefix;
		$line_prefix .= "    ";

		for my $line (@output) {
		    print "$line_prefix$line";
		}

		$line_prefix = $prev_line_prefix;
		$are_ok = 0;
	    }
	}
    }
    }

    return $are_ok;
}

###############################################################################
# HUP the pqact program(s)
###############################################################################

sub ldmadmin_pqactHUP
{
    my $status = 0;
    my $cmd;

    if ($os eq "SunOS" && $release =~ /^4/) {
        $cmd = "ps -gawxl";
        $default = 0 ;
    } elsif ($os =~ /BSD/i) {
        $cmd = "ps ajx";
        $default = 1 ;
    } else {
        $cmd = "ps -fu $ENV{'USER'}";
        $default = 1 ;
    }

    if (!open( IN, "$cmd |" )) {
        errmsg("ldmadmin_pqactHUP: Cannot open ps(1)");
        $status = 1;
    }
    else {
        # each platform has fields in different order, looking for PID
        $_ = <IN> ;
        s/^\s*([A-Z].*)/$1/ ;
        $index = -1 ;
        ( @F ) = split( /[ \t]+/, $_ ) ;
        for( $i = 0; $i <= $#F; $i++ ) {
                next if( $F[ $i ] =~ /PPID/i ) ;
                if( $F[ $i ] =~ /PID/i ) {
                        $index = $i ;
                        last ;
                }
        }
        $index = $default if( $index == -1 ) ;

        @F = ( ) ;
        # Search through all processes, looking for "pqact".  Only processes
        # that are owned by the user will respond to the HUP signal.
        while( <IN> ) {
                next unless( /pqact/ ) ;
                s/^\s*([a-z0-9].*)/$1/ ;
                ( @F ) = split( /[ \t]+/, $_ ) ;
            $pqactPid .= " $F[ $index ]" ;
        }
        close( IN ) ;

        if ($pqactPid eq "") {
              errmsg("ldmadmin_pqactHUP: process not found, cannot HUP pqact");
        } else {
              print "Check pqact HUP with command \"ldmadmin tail\"\n" ;
              system( "kill -HUP $pqactPid" );
        }
    }

    return $status;
}

###############################################################################
# Check the queue file for errors
###############################################################################

sub isProductQueueOk
{
    my $isOk = 0;
    my($status) = system("pqcheck -q $pq_path 2>/dev/null") >> 8;

    if( 0 == $status ) {
	print "The product-queue is OK.\n";
	$isOk = 1;
    }
    elsif (1 == $status) {
	errmsg(
	    "The self-consistency of the product-queue couldn't be " .
	    "determined.  See the logfile for details.");
    }
    elsif (2 == $status) {
	errmsg(
	    "The product-queue doesn't have a writer-counter.  Using " .
	    "\"pqcheck -F\" to create one...");
	system("pqcheck -F -q $pq_path");
	if ($?) {
	    errmsg("Couldn't add writer-counter to product-queue.");
	}
	else {
	    $isOk = 1;
	}
    }
    elsif (3 == $status) {
	errmsg(
	    "The writer-counter of the product-queue isn't zero.  Either " .
	    "a process has the product-queue open for writing or the queue " .
	    "might be corrupt.  Terminate the process and recheck or use\n" .
	    "    pqcat -l- -s -q $pq_path && pqcheck -F -q $pq_path\n" .
	    "to validate the queue and set the writer-counter to zero.");
    }
    else {
	errmsg(
	    "The product-queue is corrupt.  Use\n" .
	    "    ldmadmin delqueue && ldmadmin mkqueue\n" .
	    "to remove and recreate it.");
    }
    return $isOk;
}

###############################################################################
# Remove product-information files that are older than the LDM pid-file.
###############################################################################

sub removeOldProdInfoFiles
{
    system("find .*.info -prune \! -newer $pid_file 2>/dev/null | xargs rm -f");
}

###############################################################################
# Check the system clock
###############################################################################

sub checkTime
{
    my $failure = 1;

    if (!$check_time) {
	if ($warn_if_check_time_disabled) {
	    errmsg("\n".
		"WARNING: The checking of the system clock is disabled.  ".
		"You might loose data if the clock is off.  To enable this ".
		"checking, execute the command \"regutil -u 1 ".
                "regpath{CHECK_TIME}\".");
	}
	$failure = 0;
    }
    else {
	if ($#time_servers < 0) {
	    errmsg("\nWARNING: No time-servers are specified by the registry ".
		"parameter \"regpath{NTPDATE_SERVERS}\". Consequently, the ".
		"system clock can't be checked and you might loose data if ".
		"it's off.");
	}
	else {
	    my @hosts = @time_servers;
	    while ($#hosts >= 0) {
		my $i = int(rand(scalar(@hosts)));
		my $timeServer = $hosts[$i];
		@hosts = (@hosts[0 .. ($i-1)], @hosts[($i+1) .. $#hosts]);
		if (!open(NTPDATE,
		    "$ntpdate -q -t $ntpdate_timeout $timeServer 2>&1 |")) {
		    errmsg("\n".
			"Couldn't execute the command \"$ntpdate\": $!.  ".
                        "Execute the command \"regutil -s path ".
                        "regpath{NTPDATE_COMMAND}\" to set the pathname of ".
                        "the ntpdate(1) utility to \"path\".");
		    last;
		}
		else {
		    my $offset;
		    while (<NTPDATE>) {
			if (/offset\s+([+-]?\d*\.\d*)/) {
			    $offset = $1;
			    last;
			}
		    }
		    close NTPDATE;
		    if (length($offset) == 0) {
			errmsg("\n".
			    "Couldn't get time from time-server at ".
			    "$timeServer using the ntpdate(1) utility, ".
			    "\"$ntpdate\".  ".
			    "If the utility is valid and this happens often, ".
			    "then remove $timeServer ".
			    "from registry parameter ".
                            "\"regpath{NTPDATE_SERVERS}\".");
		    }
		    else {
			if (abs($offset) > $check_time_limit) {
			    errmsg("\n".
				"The system clock is more than ".
				"$check_time_limit seconds off, which is ".
				"specified by registry parameter ".
				"\"regpath{CHECK_TIME_LIMIT}\".");
			}
			else {
			    $failure = 0;
			}
			last;
		    }
		}
	    }
	}
	if ($failure) {
	    errmsg("\n".
		"You should either fix the problem (recommended) or disable ".
		"time-checking by executing the command ".
                "\"regutil -u 0 regpath{CHECK_TIME}\" (not recommended).");
	}
    }
    return $failure;
}

###############################################################################
# Metrics:
###############################################################################

# Command for getting a UTC timestamp:
sub getTime
{
    chomp(my($time) = `date -u +%Y%m%d.%H%M%S`);
    return $time;
}
#
# Command for getting the running 1, 5, and 15 minute load averages:
sub getLoad
{
    chomp(my($output) = `uptime`);
    return (split(/,?\s+/, $output))[-3, -2, -1];
}
#
# Command for getting the number of connections to the LDM port (local, remote):
sub getPortCount
{
    my($localCount) = 0;
    my($remoteCount) = 0;
    open(FH, $netstat."|") or die "Can't fork() netstat(1): $!";
    while (<FH>) {
	if (/ESTABLISHED/) {
	    my(@fields) = split(/\s+/);
	    $localCount++ if ($fields[3] =~ /:$port$/);
	    $remoteCount++ if ($fields[4] =~ /:$port$/);
	}
    }
    (close FH || !$!) or die "Can't close(): status=$?";
    return ($localCount, $remoteCount);
}
#
# Command for getting product-queue metrics (age, #prods):
sub getPq
{
    my($age) = -1;
    my($prodCount) = -1;
    my($byteCount) = -1;
    open(FH, "pqmon -l- -q $pq_path 2>&1 |") or die "Can't fork() pqmon(1): $!";
    while (<FH>) {
	my(@fields) = split(/\s+/);
	if ($#fields == 13) {
	    $age = $fields[13];
	    $prodCount = $fields[5];
	    $byteCount = $fields[8];
	}
    }
    (close FH || !$!) or die "Can't close(): status=$?";
    return ($age, $prodCount, $byteCount);
}
#
# Command for getting space-usage metrics:
#
sub getCpu
{
    my($userTime) = -1;
    my($sysTime) = -1;
    my($idleTime) = -1;
    my($waitTime) = -1;
    my($memUsed) = -1;
    my($memFree) = -1;
    my($swapUsed) = -1;
    my($swapFree) = -1;
    my($contextSwitches) = -1;
    my($haveMem) = 0;
    my($haveSwap) = 0;
    open(FH, $top."|") or die "Can't fork() top(1): $!";
    while (<FH>) {
	if (/^mem/i) {
	    s/k/e3/gi;
	    s/m/e6/gi;
	    s/g/e9/gi;
	    $memUsed = $1 if /([[:digit:]]+(e\d)?) used/i;
	    $memUsed = $1 if /([[:digit:]]+(e\d)?) phys/i;
	    $memFree = $1 if /([[:digit:]]+(e\d)?) free/i;
	    if ($memUsed < 0 && $memFree >= 0 && /([[:digit:]]+(e\d)?) real/i) {
		$memUsed = $1 - $memFree;
	    }
	    $haveMem = 1;
	    if (/swap/) {
		if (/([[:digit:]]+(e\d)?) (free swap|swap free)/i) {
		    $swapFree = $1;
		}
		elsif (/([[:digit:]]+(e\d)?) (total )?swap/i) {
		    $swapUsed = $1 - $swapFree;
		}
		if (/([[:digit:]]+(e\d)?) swap in use/i) {
		    $swapUsed = $1;
		}
		$haveSwap = 1;
	    }
	}
	elsif (/^swap/i) {
	    s/k/e3/gi;
	    s/m/e6/gi;
	    s/g/e9/gi;
	    /([[:digit:]]+(e\d)?) used/i;	$swapUsed = $1;
	    /([[:digit:]]+(e\d)?) free/i;	$swapFree = $1;
	    $haveSwap = 1;
	}
	last if ($haveMem && $haveSwap);
    }
    (close FH || !$!) or die "Can't close(): status=$?";

    my($csIndex) = -1;
    my($usIndex) = -1;
    my($syIndex) = -1;
    my($idIndex) = -1;
    my($waIndex) = -1;
    my($line) = "";
    open(FH, "vmstat 1 2|") or die "Can't fork() vmstat(1): $!";
    while (<FH>) {
	my(@fields) = split(/\s+/);
	for (my($i) = 0; $i <= $#fields; ++$i) {
	    if ($csIndex < 0 && $fields[$i] eq "cs") {
		$csIndex = $i;
	    }
	    elsif ($usIndex < 0 && $fields[$i] eq "us") {
		$usIndex = $i;
	    }
	    elsif ($syIndex < 0 && $fields[$i] eq "sy") {
		$syIndex = $i;
	    }
	    elsif ($idIndex < 0 && $fields[$i] eq "id") {
		$idIndex = $i;
	    }
	    elsif ($waIndex < 0 && $fields[$i] eq "wa") {
		$waIndex = $i;
	    }
	}
	$line = $_
    }
    (close FH || !$!) or die "Can't close(): status=$?";
    my(@fields) = split(/\s+/, $line);
    ($contextSwitches = $fields[$csIndex]) if $csIndex >= 0;
    ($sysTime = $fields[$syIndex]) if $syIndex >= 0;
    ($userTime = $fields[$usIndex]) if $usIndex >= 0;
    ($idleTime = $fields[$idIndex]) if $idIndex >= 0;
    ($waitTime = $fields[$waIndex]) if $waIndex >= 0;

    return ($userTime, $sysTime, $idleTime, $waitTime, 
	$memUsed, $memFree, $swapUsed, $swapFree, $contextSwitches);
}
#
# Command for printing metrics:
sub printMetrics
{
    print join(' ', getTime(), getLoad(), getPortCount(), getPq(), getCpu());
    print "\n";
    return $?;
}
#
# Command for plotting metrics:
sub plotMetrics
{
    return system("plotMetrics -b $begin -e $end $metrics_files");
}

###############################################################################
# Print an error-message
###############################################################################

sub errmsg
{
    $SIG{PIPE} = 'IGNORE';
    open(FH, "|fmt 1>&2")	or die "Can't fork() fmt(1): $!";
    print FH @_			or die "Can't write(): $!";
    close FH			or die "Can't close(): status=$?";
}