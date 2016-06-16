#!env perl -w
# Shifts the modified map right a bit.
# Matt Gumbley M0CUV 2016
#
use warnings;
use strict;

use Data::Dumper;
use Imager;


my $origMap = Imager->new;
$origMap->read(file => 'BlankMap-World6-Equirectangular-modified.png') or die "Could not read map: " . $origMap->errstr;
my $h = $origMap->getheight();
my $w = $origMap->getwidth();
my $xinc = $w / 18;
my $yinc = $h / 18;

my $newMap = Imager->new(ysize => $h, xsize => $w);
$newMap->paste(left => $xinc / 2, top => 0, src => $origMap); # the bulk of the orig map, shifted right
$newMap->paste(left => 0, top => 0, width => $xinc / 2, src_minx => $w - ($xinc / 2) - 1, src => $origMap); # the sliver

$newMap->write(file => 'BlankMap-World6-Equirectangular-modified-shifted.png') or die "Could not write map: " . $origMap->errstr;
