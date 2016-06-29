#!env perl -w
# Given the top-left GG grid square code, draws a 3x3 map.
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

my $topLeftSquare = $ARGV[0];
print "Using top left square $topLeftSquare\n";



my $outputDirectory = "$ENV{HOME}/Desktop/maps";

# This works fine on OS X; adjust for other platforms.
my $font = Imager::Font->new(file => "/Library/Fonts/Microsoft/Lucida Console.ttf");


my $grey = Imager::Color->new(64, 64, 64);


my $newMap = Ham::WorldMap->new();
my $img = $newMap->{image};

my ($x, $y) = $newMap->locatorToXY($topLeftSquare);
my $xinc = $newMap->{gridx};
my $yinc = $newMap->{gridy};

my $gX = int($x / $xinc) * $xinc;
my $gY = int($y / $yinc) * $yinc;

my $xmax = $gX + ($xinc * 3);
my $ymax = $gY + ($yinc * 3);

$newMap->drawLocatorGrid();

my $h = $newMap->{height};
my $w = $newMap->{width};

my $nine = $img->crop(left => $gX, top => $gY, right => $xmax, bottom => $ymax);
$nine = $nine->scale(xpixels => $w, ypixels => $h);

my $endMap = Imager->new(ysize => $h, xsize => $w);
$endMap = $endMap->convert(preset => 'addalpha');
$endMap->paste(src => $nine);

my $filename = "/Users/matt/Desktop/maps/printable.png";

$endMap->write(file => $filename) or die "Could not write map $filename: " . $endMap->errstr;

