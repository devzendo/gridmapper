#!env perl -w
# Draws a map showing all stations recorded in a .adif file, with locator grid and caption.
# Matt Gumbley M0CUV 2016
#
use warnings;
use strict;

use Data::Dumper;
use Imager;
use Ham::WSJTX::Logparse;
use Ham::Locator;
use POSIX;
use Math::Trig;
use Ham::WorldMap;
use Ham::ADIF;

# Change the following as needed...
my $adifFileName = "$ENV{HOME}/Documents/jt.adif";
my $myStationLocation = 'JO01EE';
my $captionText = "JT modes stations worked by M0CUV";
my $generatedMapFileName = "$ENV{HOME}/Desktop/stations-worked.png";

# Fine on OS X, change as necessary...
my $font = Imager::Font->new(file => "/Library/Fonts/Microsoft/Lucida Console.ttf");

# Shouldn't need to change anything below here... ----------------------------------------------------------------------

my $grey = Imager::Color->new(64, 64, 64);

# Read my log file
my $adif = Ham::ADIF->new();
my $adifrecs = $adif->parse_file($adifFileName);

my $newMap = Ham::WorldMap->new();

foreach my $rec (@$adifrecs) {
    # warn "$rec->{call} $rec->{mode} $rec->{gridsquare} $rec->{rst_sent}\n";

    $rec->{rst_sent} =~ /R?([+-]\d+)/;
    my $power = $1;

    my $color = $rec->{mode} eq 'JT65' ? 'orange' : 'green';
    dot($newMap, $rec->{gridsquare}, $power, $color);
}

# Where is my station?
dot($newMap, $myStationLocation, -20, 'blue');

$newMap->drawLocatorGrid();

my $finalMap = caption($captionText, $newMap);
$finalMap->write(file => $generatedMapFileName) or die "Could not write map $generatedMapFileName: " . $finalMap->errstr;


sub caption {
    my $text = shift;
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
        string => $text,
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
    #print "orig opacity $origOpacity final opacity $opacity\n";

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
