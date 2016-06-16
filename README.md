# GridMapper #

Want to take log files from WSJT-X, and render the received station locator squares
on a nice map, with night/day boundary shown, so you can see when propagation will
provide a path to that square? Or see this data as a heatmap?

This is for you...

### This code... ###

* Contains normalise-sort-alltxt.pl, a Perl program for processing WSJT-X ALL.TXT files into a
  suitable output file containing date/time/callsign/locator.
* Contains draw-grid.pl, a Perl program to plot ALL.TXT data on a map
  of the world, for a given hour (by station or heatmap), or by minute.
* Contains draw-adif-log.pl, a Perl program to plot all stations from a .adif file onto a
  map.

### How do I get set up? ###

* Clone this repo!
* You need Perl 5.16 (or possibly later), and several CPAN modules:
  * Ham::WSJTX::Logparse (by me)
  * Ham::WorldMap (by me)
  * Imager
  * Ham::Locator
  * POSIX
  * Math::Trig
  * Ham::ADIF

* Edit the draw-XXXXXX.pl script, and change the variables near the top of the
  file, to state where your ALL.TXT file(s) are, where you'd like the map .png
  files creating, and which type of maps you'd like to produce.
* Run: perl draw-XXXXX.pl
* Enjoy your maps, and good DX!

### Who do I talk to? ###

* Matt Gumbley, M0CUV.
* @mattgumbley on Twitter or @devzendo
* matt.cpan@gumbley.me.uk via email
* http://mattgumbley.wordpress.com/