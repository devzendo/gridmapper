#!env perl -w
# Parses all data in a set of WSJT-X ALL.TXT files, and collects each heard station at the time it was heard,
# ignoring the date (so I can get an idea of which stations are heard at a particular time, over several days).
#
# For each minute, produce a map containing the locator grid and day/night boundary, and all stations heard at that
# minute. For artistic effect, fade out stations that I'm not hearing any more.
#
# Matt Gumbley M0CUV 2016
#
use warnings;
use strict;

use Data::Dumper;
use Imager;
use Ham::WSJTX::Logparse;
use Ham::Locator;
use Math::Trig;
use Ham::WorldMap;

# Where the input data comes from, and where the maps are stored...
my $dropbox = "$ENV{HOME}/Dropbox/";
my @logfiles = glob("$dropbox/*ALL.TXT");
my $outputDirectory = "$ENV{HOME}/Desktop/maps";

# This script can generate three types of maps, by setting the value of $mapType:
# 'mins' => 1440 maps, one per minute of 24 hours, each showing the stations received in that minute, and fading out
#           the ones recently heard for artistic effect.
# 'hours' => 24 maps, one per hour, each showing the stations received in that hour. No artistic fadeout.
# 'heatmap' => 24 maps, one per hour, each showing the quantity of stations received in that hour, as a heatmap of
#           grid squares.
my $mapType = 'mins'; # 'mins' or 'hours', 'heatmap'

# This works fine on OS X; adjust for other platforms.
my $font = Imager::Font->new(file => "/Library/Fonts/Microsoft/Lucida Console.ttf");




# Shouldn't need to change anything below here... ----------------------------------------------------------------------

# Read all the data....
my %gridsigs = (); # grid => highest powered signal at this grid
my %timed = (); # dddd minute => [ records for all stations heard at this minute ]
my %hourlytimed = (); # hh hour => [ records for all stations heard at this hour ]
my $logparser = Ham::WSJTX::Logparse->new(@logfiles);

my $callback = sub {
    my $date = shift;
    my $time = shift;
    my $power = shift;
    shift; # not using offset here
    my $mode = shift;
    my $callsign = shift;
    my $grid = shift;
    warn "date $date time $time power $power mode $mode callsign $callsign grid $grid\n";
    if ($grid =~ /(TU|RR)73/) {
        warn "dodgy data from $date $time $callsign\n";
        return;
    }

    # Store the highest recorded power for this grid.
    $gridsigs{$grid} ||= -1000;
    if ($power > $gridsigs{$grid}) {
        $gridsigs{$grid} = $power;
    }

    my $record = [$grid, $power, $mode];

    # Collect this record under its time.
    $timed{$time} ||= [];
    my $recs = $timed{$time};
    push @$recs, $record;

    # Collect this record under its hour.
    my $hour = substr($time, 0, 2);
    $hourlytimed{$hour} ||= [];
    my $hrecs = $hourlytimed{$hour};
    push @$hrecs, $record;
};

$logparser->parseForBand("20m", $callback);

# All data read, and stored in the above hashes.

my $grey = Imager::Color->new(64, 64, 64);


# A list of records from earlier 'minute maps' that I'm fading out.
my @opacities = ();
for (my $o = 16; $o > 0; $o--) {
    push @opacities, [];
}

# Create all the maps
if ($mapType eq 'mins') {
    generateMinuteMaps();
} elsif ($mapType eq 'hours' || $mapType eq 'heatmap') {
    generateHourMaps();
} else {
    die "Unknown map type $mapType\n";
}
print "done\n";

sub generateMinuteMaps {
    for (my $hour = 0; $hour < 24; $hour++) {
        for (my $minute = 0; $minute < 60; $minute++) {
            my $time = sprintf("%02d%02d", $hour, $minute);
            print "Creating map for time $time\n";
            # Started recording on 14-May-2016.

            my $dt = DateTime->new(
                    year       => 2016,
                    month      => 6,
                    day        => 5,
                    hour       => $hour,
                    minute     => $minute,
                    second     => 0,
                    nanosecond => 0,
                    time_zone  => 'UTC',
                );

            my $newMap = Ham::WorldMap->new();

            # Show all the old signals stored in @opacities. 0 is barely visible; 15 is starting to fade.
            for (my $o = 0; $o < 16; $o++) {
                my $opac = $opacities[$o];
                foreach my $rec (@$opac) {
                    my ($grid, $power, $mode) = (@$rec);

                    my $color = $mode eq '#' ? 'orange' : 'green';
                    dot($newMap, $grid, $power, $color, $o);
                }
            }

            # Show the current signals.
            my $recs = $timed{$time} || [];
            foreach my $rec (@$recs) {
                my ($grid, $power, $mode) = (@$rec); # grid is a 'ggnn' medium grid locator.

                my $color = $mode eq '#' ? 'orange' : 'green';
                dot($newMap, $grid, $power, $color, undef);
            }

            # Remove the oldest signals from the fadeout
            shift @opacities;

            # put the current records at the end
            my $newOpacities = [];
            foreach my $rec (@$recs) {
                push @$newOpacities, $rec;
            }
            push @opacities, $newOpacities;

            # Where is my station?
            dot($newMap, 'JO01EE', -20, 'blue');

            $newMap->drawNightRegions($dt);
            $newMap->drawLocatorGrid();

            my $finalMap = caption($time, $newMap);
            my $filename = "$outputDirectory/$time.png";

            print "$filename " . scalar(@$recs) . " signals heard\n";
            $finalMap->write(file => $filename) or die "Could not write map $filename: " . $finalMap->errstr;
        }
    }
}

sub generateHourMaps {
    for (my $hour = 0; $hour < 24; $hour++) {
        my $zhour = sprintf("%02d", $hour);
        print "Creating map for hour $zhour\n";
        # Started recording on 14-May-2016.

        my $dt = DateTime->new(
                year       => 2016,
                month      => 6,
                day        => 5,
                hour       => $hour,
                minute     => 30,
                second     => 0,
                nanosecond => 0,
                time_zone  => 'UTC',
            );

        my $newMap = Ham::WorldMap->new();

        my %gridcount = (); # gg 2 char grid square => count of stations heard from that large grid square
        my $maxgridcount = 0;

        # Show the current signals.
        my $recs = $hourlytimed{$zhour} || [];
        foreach my $rec (@$recs) {
            my ($grid, $power, $mode) = (@$rec); # grid is a 'ggnn' medium grid locator.

            # Increment how many stations have been heard for this large 'gg' grid square
            my $gridsq = substr($grid, 0, 2);
            #print "map no $mapno grid $grid (square $gridsq) power $power mode $mode\n";
            $gridcount{$gridsq} ||= 0;
            $gridcount{$gridsq}++;
            $maxgridcount = $gridcount{$gridsq} if $gridcount{$gridsq} > $maxgridcount;

            if ($mapType eq 'hours') {
                my $color = $mode eq '#' ? 'orange' : 'green';
                dot( $newMap, $grid, $power, $color, undef );
            }
        }

        if ($mapType eq 'heatmap') {
            print "maxgridcount $maxgridcount in " . scalar(keys(%gridcount)) . " unique grid squares, with " . scalar(@$recs). " records\n";
            foreach my $gridsq (keys(%gridcount)) {
                my $thisgridcount = $gridcount{$gridsq};
                my $prop = $thisgridcount / $maxgridcount;
                printf ("grid sq for heatmap is $gridsq this grid count $thisgridcount prop %3.2f%%\n", $prop * 100);
                $newMap->heatMapGridSquare($gridsq, $prop);
            }
        }

        # Where is my station?
        dot($newMap, 'JO01EE', -20, 'blue');

        $newMap->drawNightRegions($dt);
        $newMap->drawLocatorGrid();

        my $finalMap = caption($zhour, $newMap);
        my $filename = "/Users/matt/Desktop/maps/$zhour-$mapType.png";

        print "$filename " . scalar(@$recs) . " signals heard\n";
        $finalMap->write(file => $filename) or die "Could not write map $filename: " . $finalMap->errstr;
    }
}



sub caption {
    my $time = shift;
    my $srcMap = shift;
    my $h = $srcMap->{height};
    my $w = $srcMap->{width};
    my $yinc = $srcMap->{gridy};
    my $endMap = Imager->new(ysize => $h + $yinc, xsize => $w);
    $endMap = $endMap->convert(preset => 'addalpha');
    $endMap->paste(y => $yinc, src => $srcMap->{image});
    my $lightGrey = Imager::Color->new(192, 192, 192);
    $endMap->box(color => $lightGrey, xmin => 1, ymin => $h, xmax => $w - 2, ymax => $h + $yinc - 2, filled => 1);

    my $ytext = $h + ($yinc / 2) + 10;
    $endMap->string(x => 16, y => $ytext,
        font => $font,
        string => $time,
        color => $grey,
        size => 30,
        aa => 1);

    $endMap->string(x => 120, y => $ytext,
        font => $font,
        string => "24 Hours of JT65/9 signal reception at M0CUV",
        color => $grey,
        size => 30,
        aa => 1);
    return $endMap;
}



sub dot {
    my ($map, $grid, $power, $colour, $opacity) = @_;
    $opacity = 16 unless defined $opacity;
    #print "orig opacity $opacity\n";
    $opacity *= 16;
    $opacity = $opacity > 255 ? 255 : $opacity;

    my $r = (30 - ($power * -1)) / 2;
    #    print "lat $lat y $y ==== long $long x $x ==== power $power r $r\n";

    my $tColour;
    if ($colour eq 'orange') {
        $tColour = Imager::Color->new(192, 16, 16, $opacity);
    } elsif ($colour eq 'green') {
        $tColour = Imager::Color->new(16, 192, 16, $opacity);
    } elsif ($colour eq 'blue') {
        $tColour = Imager::Color->new(16, 16, 192, $opacity);
    }
    $map->dotAtLocator($grid, $r, $tColour);
}
