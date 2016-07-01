#!env perl -w
# Reads a set of ALL.TXT files produced by WSJT-X, and extracts date/time/square/callsign for a given band,
# and orders them chronologically.
#
# syntax: normalise-sort-alltxt.pl [band] ALL.TXT ALL2.TXT ALL3.TXT.... ALLN.TXT
# Matt Gumbley M0CUV 2016
#
# Note: this is a early version of code that was converted into the Ham::WSJTX::Logparse CPAN module. That's a bit more
# reusable than this...

use warnings;
use strict;

use Data::Dumper;

my $band = undef;
my @allfiles = ();
foreach (@ARGV) {
    if (/^\d+m$/i) {
        $band = lc($_);
        next;
    }
    if (-f $_) {
        push @allfiles, $_;
        next;
    }
}

die "No band specified\n" unless (defined ($band));
die "No ALL.TXT files specified\n" unless (@allfiles);

print ("Scanning for $band band activity\n");
my %records = ();
my %callsignToGrid = ();
my %squaresByMinute = ();
my %grids = ();

my $insertRecord = sub {
    my $date = shift;
    my $time = shift;
    my $power = shift;
    my $mode = shift;
    my $callsign = shift;
    my $grid = shift;
    if ($grid =~ /(TU|RR)73/) {
        # warn "dodgy data from $date $time $callsign\n";
        return;
    }

    $grids{$grid} = 1;
    print "date $date time $time power $power mode $mode callsign $callsign grid $grid\n";
    $records{$time} ||= [];
    my $timeList = $records{$time};
    push @$timeList, [$grid, $callsign, $power, $mode];

    $callsignToGrid{$callsign} ||= [ $grid, '2359', '0000', -1000 ];
    my $callsignGrid = $callsignToGrid{$callsign};
    $callsignGrid->[1] = "$time" if ($time < $callsignGrid->[1]);
    $callsignGrid->[2] = "$time" if ($time > $callsignGrid->[2]);
    $callsignGrid->[3] = $power if ($power > $callsignGrid->[3]);

    $squaresByMinute{$time} ||= {};
    my $squareByMinute = $squaresByMinute{$time};
    $squareByMinute->{$grid} = 1;
};


foreach (@allfiles) {
    print ("file $_\n");
    process($band, $_, $insertRecord);
}

#print Dumper(\%records) . "\n";
my @timeSortedKeys = sort { $a <=> $b } (keys(%records));
foreach my $timeKey (@timeSortedKeys) {
    print "$timeKey:\n";
    my $list = $records{$timeKey};
    foreach my $arr (@$list) {
        print "  $arr->[0] $arr->[1] $arr->[2] $arr->[3]\n";
        sleep 0.1;
    }

    #my $squareByMinute = $squaresByMinute{$timeKey};
    #foreach (sort(keys $squareByMinute)) {
    #    print "  $_\n";
    #}
}

#print Dumper(\%callsignToGrid) . "\n";
#foreach my $callsign (sort(keys(%callsignToGrid))) {
#    my $callsignGrid = $callsignToGrid{$callsign};
#    print "$callsign $callsignGrid->[0] $callsignGrid->[3] [$callsignGrid->[1]..$callsignGrid->[2]]\n";
#}
print scalar(keys(%callsignToGrid)) . " callsigns\n";
print scalar(keys(%grids)) . " grid squares\n";

sub process {
    my $bandOfInterest = shift;
    my $filename = shift;
    my $callback = shift;

    my %freqToBand = (
        '144.491'  => '2m',    # +2
        '144.489'  => '2m',
        '70.093'   => '4m',    # +2
        '70.091'   => '4m',
        '50.278'   => '6m',    # +2
        '50.276'   => '6m',
        '28.078'   => '10m',   # +2
        '28.076'   => '10m',
        '24.919'   => '12m',   # +2
        '24.917'   => '12m',
        '21.078'   => '15m',   # +2
        '21.076'   => '15m',
        '18.104'   => '17m',   # +2
        '18.102'   => '17m',
        '14.078'   => '20m',   # +2
        '14.076'   => '20m',
        '10.14'    => '30m',   # +2
        '10.138'   => '30m',
        '7.078'   => '40m',   # +2
        '7.076'   => '40m',
        '5.359'   => '60m',   # +2
        '5.357'   => '60m',
        '3.578'   => '80m',   # +2
        '3.576'   => '80m',
        '1.84'    => '160m',  # +2
        '1.838'   => '160m',
        '0.4762'  => '630m',  # +2
        '0.4742'  => '630m',
        '0.13813' => '2200m', # +2
        '0.13613' => '2200m',
    );

    local *F;
    unless (open F, "<$filename") {
        warn "Cannot open $filename: $!\n";
        return;
    }
    my $currentBand = undef;
    my $currentDate = undef;
    while (<F>) {
        chomp;
        #print "line [$_]\n";
        # Only interested in data from a specific band, and the indicator for changing band/mode looks like:
        # 2015-Apr-15 20:13  14.076 MHz  JT9
        # So extract the frequency, and look up the band. This also gives us the date. Records like this are always
        # written at startup, mode change, and at midnight.
        if (/^(\d{4}-\S{3}-\d{2}) \d{2}:\d{2}\s+(\d+\.\d+) MHz\s+\S+\s*$/) {
            $currentDate = $1;
            my $frequency = $2;
            $currentBand = $freqToBand{$frequency};
            #print "data being received for $currentBand (filtering on $bandOfInterest)\n";
            next;
        }
        # Time/Power/Freq offset/Mode/Call/Square can be extracted from records like these:
        # 0000  -9  1.5 1259 # CQ TI4DJ EK70
        # 0001  -1  0.5  404 # DX K1RI FN41
        # 0001  -8  0.2  560 # KC0EFQ WA3ETR FN10
        # 0001 -15  0.1  628 # KK7X K8MDA EN80
        # 0002 -13  1.1 1322 # CQ YV5FRD FK60
        # 0003  -3  0.5 1002 # TF2MSN K1RI FN41
        if (/^(\d{4})\s+(-\d+)\s+[-\d.]+\s+\d+\s([#@])\s\w+\s+(\w+)\s+([A-Z]{2}\d{2})\s*$/) {
            my $ctime = $1;
            my $cpower = $2;
            my $cmode = $3;
            my $ccallsign = $4;
            my $cgrid = $5;
            #print "got line $1 $2 $3 $4 $5\n";
            # callsigns must have at least one digit.
            next unless ($ccallsign =~ /\d/);
            if (defined $currentDate && $bandOfInterest eq $currentBand) {
                #print "calling back\n";
                $callback->($currentDate, $ctime, $cpower, $cmode, $ccallsign, $cgrid);
            } else {
                #print "not interested\n";
            }
            next;
        }
    }
    close F;
}

=cut
