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

use List::Util qw[min max];
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

# This script can generate several types of maps, by setting the value of $mapType:
# 'mins' => 1440 maps, one per minute of 24 hours, each showing the stations received in that minute, and fading out
#           the ones recently heard for artistic effect.
# 'hours' => 24 maps, one per hour, each showing the stations received in that hour. No artistic fadeout.
# 'heatmap' => 24 maps, one per hour, each showing the quantity of stations received in that hour, as a heatmap of
#           grid squares.
# 'clocks' => 1 map showing clocks in each grid square, showing at which hours stations were heard.
my $mapType = 'clocks'; # 'mins' or 'hours', 'heatmap', 'clocks'

# This works fine on OS X; adjust for other platforms.
my $font = Imager::Font->new(file => "/Library/Fonts/Microsoft/Lucida Console.ttf");




# Shouldn't need to change anything below here... ----------------------------------------------------------------------

# Read all the data....
my %gridsigs = (); # GGNN grid => highest powered signal at this grid
my %gridhours = (); # GG grid => hash of which hours contained a signal
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

    # Collect this hour under its GG grid, counting number of signals per hour
    my $ggGrid = substr($grid, 0, 2);
    $gridhours{$ggGrid} ||= {};
    $gridhours{$ggGrid}->{$hour} ||= 0;
    $gridhours{$ggGrid}->{$hour} ++;
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
} elsif ($mapType eq 'clocks') {
    generateClocksMap();
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


sub generateClocksMap {
    my $newMap = Ham::WorldMap->new();
    my $img = $newMap->{image};
    my $lightGrey = Imager::Color->new(240, 240, 240);
    my $red = Imager::Color->new(240, 0, 0);
    use constant HOUR_DEGREES => (360 / 24);
    while (my ($gg, $hoursHash) = each (%gridhours)) {
        my @hours = sort (keys (%$hoursHash));

        print "GRID $gg @hours ------------------------------------------------------------\n";

        my ($x, $y) = $newMap->locatorToXY($gg);
        # odd adjustments
        $x -= 6;
        $y += 3;
        my $radius = (min($newMap->{gridx}, $newMap->{gridy}) / 2) - 2;
        $img->circle(color => $grey, r => $radius, x => $x, y => $y, aa => 1);
        $img->circle(color => 'white', r => $radius - 1, x => $x, y => $y, aa => 1);

        # each arc is coloured to represent its proportion of all signals heard in this hour
        my $totalHourSignals = 0;
        foreach my $hour (@hours) {
            $totalHourSignals += $hoursHash->{$hour};
        }



        foreach my $hour (@hours) {
            my $hourSignals = $hoursHash->{$hour};

            # HSV, with SV fixed. H from 0 (red [proportion=0.0]) to 64 (yellow [proportion=1.0)
            my $proportion = $hourSignals / $totalHourSignals;
            my $h = 64 - int($proportion * 64);
            my $color = Imager::Color->new(h => $h, s => 40, v => 80);
            # printf ("proportion %3.2f%% h [0..64] $h\n", $proportion * 100);

            my $hourDeg = ((int($hour) * HOUR_DEGREES) + 270) % 360;
            $img->arc(color => $color, r => $radius - 2, x => $x, y => $y, d1 => $hourDeg, d2 => $hourDeg + HOUR_DEGREES );
        }

        # Spoke if there's no signal before or after this hour
        foreach my $hour (0 .. 23) {
            my $before = ($hour - 1) % 24;
            my $after = ($hour + 1) % 24;
            next unless (exists $hoursHash->{dig2($hour)});
            print "sig exists at $hour (before $before after $after)\n";
            unless (exists $hoursHash->{dig2($before)}) {
                my $hourRad = deg2rad((($hour * HOUR_DEGREES) + 270) % 360);
                $img->line(color => $grey, x1 => $x, y1 => $y, x2 => $x + (($radius - 2) * cos($hourRad)), y2 => $y + (($radius - 2) * sin($hourRad)));
            }
            unless (exists $hoursHash->{dig2($after)}) {
                my $hourRad = deg2rad((($after * HOUR_DEGREES) + 270) % 360);
                $img->line(color => $grey, x1 => $x, y1 => $y, x2 => $x + (($radius - 2) * cos($hourRad)), y2 => $y + (($radius - 2) * sin($hourRad)));

            }
        }
    }


    # Where is my station?
    dot($newMap, 'JO01EE', -20, 'blue');

    $newMap->drawLocatorGrid();


    # Clock Legend
    my ($x, $y) = $newMap->locatorToXY("CG");
    # odd adjustments
    $x -= 6;
    $y -= 30;
    my $radius = $newMap->{gridx} * 2;
    $img->circle(color => $grey, r => $radius, x => $x, y => $y, aa => 1);
    $img->circle(color => $lightGrey, r => $radius - 1, x => $x, y => $y, aa => 1);

    foreach my $hour (0 .. 23) {
        my $hourDeg = (($hour * HOUR_DEGREES) + 270) % 360;
        my $hourRad = deg2rad($hourDeg);
        $img->line(color => $grey, x1 => $x, y1 => $y, x2 => $x + ($radius * cos($hourRad)), y2 => $y + ($radius * sin($hourRad)));

        my $hourLabelDeg = ($hourDeg + (HOUR_DEGREES / 2)) % 360;
        my $hourLabelRad = deg2rad($hourLabelDeg);

        $img->align_string(x => $x + ($radius * 0.9 * cos($hourLabelRad)), y => $y + ($radius * 0.9 * sin($hourLabelRad)),
            font => $font,
            string => "" + $hour,
            color => $grey,
            halign=>'center',
            valign=>'center',
            size => 20,
            aa => 1);
    }




    my $finalMap = caption("TIME", $newMap);
    my $filename = "/Users/matt/Desktop/maps/clocks.png";

    $finalMap->write(file => $filename) or die "Could not write map $filename: " . $finalMap->errstr;
}

sub dig2 {
    return sprintf("%02d", shift);
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
